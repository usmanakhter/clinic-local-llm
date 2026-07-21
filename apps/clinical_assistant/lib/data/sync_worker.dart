import 'dart:convert';

import 'package:http/http.dart' as http;

import 'session_store.dart';

/// Result of an explicit [SyncWorker.debugFlushPending] call.
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

/// Phase 3 sync stub — **network OFF by default**.
///
/// Does not run on app start or in background. Call [debugFlushPending]
/// only from debug / developer tooling against a local ingest-api.
class SyncWorker {
  SyncWorker._();

  static const defaultBaseUrl = 'http://127.0.0.1:8787';

  /// POSTs pending scrubbed queue items to [baseUrl]/v1/ingest/batch`.
  ///
  /// Feature is opt-in: this method is the only entry point in the stub.
  static Future<SyncFlushResult> debugFlushPending({
    String baseUrl = defaultBaseUrl,
    String deviceId = 'dev-device',
    String consentVersion = 'np-terms-1.1',
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

    final uri = Uri.parse(
      '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/v1/ingest/batch',
    );
    final body = jsonEncode({
      'device_id': deviceId,
      'consent_version': consentVersion,
      'items': items,
    });

    try {
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(timeout);

      if (res.statusCode >= 200 && res.statusCode < 300) {
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

      final err = 'HTTP ${res.statusCode}: ${res.body}';
      for (final item in items) {
        await SessionStore.markSyncFailed(
          item['id'] as String,
          note: err,
        );
      }
      return SyncFlushResult(
        attempted: items.length,
        synced: 0,
        failed: items.length,
        message: err,
      );
    } catch (e) {
      final err = e.toString();
      for (final item in items) {
        await SessionStore.markSyncFailed(
          item['id'] as String,
          note: err,
        );
      }
      return SyncFlushResult(
        attempted: items.length,
        synced: 0,
        failed: items.length,
        message: err,
      );
    }
  }
}
