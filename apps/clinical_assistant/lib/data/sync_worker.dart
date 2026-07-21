import 'dart:convert';

import 'package:http/http.dart' as http;

import 'session_store.dart';

/// Result of an [SyncWorker.flushPending] call.
class SyncFlushResult {
  const SyncFlushResult({
    required this.attempted,
    required this.synced,
    required this.failed,
    this.message,
  });

  final int attempted;
  final int synced;
  final int failed;
  final String? message;

  bool get ok => failed == 0 && attempted == synced;
}

/// Scrubbed-queue upload worker.
///
/// After Terms acceptance, sync is **on** (no in-app off switch). The app
/// queues scrubbed payloads continuously and [flushPending] attempts upload
/// whenever an ingest endpoint is reachable (local stub or future prod URL).
class SyncWorker {
  SyncWorker._();

  /// Local ingest stub (ADR-004). Replace with ap-south-1 URL for production.
  static const defaultBaseUrl = 'http://127.0.0.1:8787';

  /// POSTs pending scrubbed queue items to [baseUrl]/v1/ingest/batch`.
  static Future<SyncFlushResult> flushPending({
    String baseUrl = defaultBaseUrl,
    String deviceId = 'dev-device',
    String consentVersion = 'np-terms-1.2',
    int limit = 20,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final pending = await SessionStore.listPendingSync(limit: limit);
    if (pending.isEmpty) {
      return const SyncFlushResult(
        attempted: 0,
        synced: 0,
        failed: 0,
        message: 'No pending sync_queue items',
      );
    }

    final items = <Map<String, dynamic>>[];
    for (final row in pending) {
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) continue;
      dynamic payload = row['payload_json'];
      if (payload is String) {
        try {
          payload = jsonDecode(payload);
        } catch (_) {
          // Keep raw string if not JSON
        }
      }
      items.add({
        'id': id,
        'payload': payload,
        'scrubbed_at': row['scrubbed_at']?.toString() ??
            DateTime.now().toIso8601String(),
      });
    }

    if (items.isEmpty) {
      return const SyncFlushResult(
        attempted: 0,
        synced: 0,
        failed: 0,
        message: 'Pending rows missing ids',
      );
    }

    final uri = Uri.parse('$baseUrl/v1/ingest/batch');
    final body = jsonEncode({
      'device_id': deviceId,
      'consent_version': consentVersion,
      'items': items,
    });

    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(timeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        for (final item in items) {
          await SessionStore.markSynced(item['id'] as String);
        }
        return SyncFlushResult(
          attempted: items.length,
          synced: items.length,
          failed: 0,
          message: 'Synced ${items.length} item(s) to $baseUrl',
        );
      }

      final detail = response.body.length > 200
          ? '${response.body.substring(0, 200)}…'
          : response.body;
      for (final item in items) {
        await SessionStore.markSyncFailed(
          item['id'] as String,
          note: 'HTTP ${response.statusCode}: $detail',
        );
      }
      return SyncFlushResult(
        attempted: items.length,
        synced: 0,
        failed: items.length,
        message: 'Upload failed HTTP ${response.statusCode}',
      );
    } catch (e) {
      for (final item in items) {
        await SessionStore.markSyncFailed(
          item['id'] as String,
          note: e.toString(),
        );
      }
      return SyncFlushResult(
        attempted: items.length,
        synced: 0,
        failed: items.length,
        message: 'Upload error: $e',
      );
    }
  }

  /// Backward-compatible alias used by older call sites / docs.
  static Future<SyncFlushResult> debugFlushPending({
    String baseUrl = defaultBaseUrl,
    String deviceId = 'dev-device',
    String consentVersion = 'np-terms-1.2',
    int limit = 20,
    Duration timeout = const Duration(seconds: 15),
  }) =>
      flushPending(
        baseUrl: baseUrl,
        deviceId: deviceId,
        consentVersion: consentVersion,
        limit: limit,
        timeout: timeout,
      );
}
