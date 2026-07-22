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
/// After Terms acceptance, sync is **on** (no in-app off switch or sync chrome).
/// The app queues scrubbed payloads continuously; [SyncCoordinator] drives
/// [flushPending] (enqueue wake, periodic, resume) when an ingest endpoint
/// is reachable (local stub or Supabase Mumbai).
class SyncWorker {
  SyncWorker._();

  /// Local FastAPI stub. Override with Supabase function URL via
  /// `--dart-define=INGEST_BASE_URL=https://<ref>.supabase.co/functions/v1/ingest-batch`.
  static const defaultBaseUrl = String.fromEnvironment(
    'INGEST_BASE_URL',
    defaultValue: 'http://127.0.0.1:8787',
  );

  /// Supabase anon/publishable key (required when posting to Edge Functions).
  static const ingestAnonKey = String.fromEnvironment('INGEST_ANON_KEY');

  /// Resolves local `/v1/ingest/batch` vs a full Supabase function URL.
  static Uri ingestUri([String? baseUrl]) {
    final trimmed = (baseUrl ?? defaultBaseUrl).replaceAll(RegExp(r'/+$'), '');
    if (trimmed.contains('/functions/v1/')) {
      return Uri.parse(trimmed);
    }
    return Uri.parse('$trimmed/v1/ingest/batch');
  }

  static Map<String, String> _headers() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (ingestAnonKey.isNotEmpty) {
      headers['apikey'] = ingestAnonKey;
      headers['Authorization'] = 'Bearer $ingestAnonKey';
    }
    return headers;
  }

  /// POSTs pending scrubbed queue items to the ingest endpoint.
  static Future<SyncFlushResult> flushPending({
    String? baseUrl,
    String deviceId = 'dev-device',
    String consentVersion = 'np-terms-1.2',
    int limit = 20,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final resolvedBase = baseUrl ?? defaultBaseUrl;
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

    final uri = ingestUri(resolvedBase);
    final body = jsonEncode({
      'device_id': deviceId,
      'consent_version': consentVersion,
      'items': items,
    });

    try {
      final response = await http
          .post(
            uri,
            headers: _headers(),
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
          message: 'Synced ${items.length} item(s) to $uri',
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
    String? baseUrl,
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
