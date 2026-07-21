import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import '../privacy/pii_scrubber.dart';
import 'db.dart';

/// Local-first activity store.
///
/// Device history keeps clinician-readable (unredacted) text.
/// PII scrubbing applies only to [sync_queue] payloads destined for cloud backup.
class SessionStore {
  SessionStore._();

  static const _webSessionsKey = 'nepal_clinical_sessions_v1';
  static const _webSyncQueueKey = 'nepal_sync_queue_v1';
  static const _maxSessions = 500;

  static SharedPreferences? _prefs;

  static Future<void> initWebPersistence(SharedPreferences prefs) async {
    _prefs = prefs;
    final raw = prefs.getString(_webSessionsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      AppDatabase.webSessionsInternal
        ..clear()
        ..addAll(
          list
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e)),
        );
    } catch (_) {
      // Corrupt store — start fresh
      AppDatabase.webSessionsInternal.clear();
    }
  }

  static Future<ClinicalSession> insert({
    required String queryType,
    required String inputSummary,
    String? outputSummary,
    Map<String, dynamic>? metadata,
    String? patientId,
  }) async {
    final id = 'sess_${DateTime.now().millisecondsSinceEpoch}';
    // Local history: keep full clinician-readable content (no scrub).
    final row = ClinicalSession(
      id: id,
      createdAt: DateTime.now(),
      queryType: queryType,
      inputSummary: inputSummary,
      outputSummary: outputSummary,
      payloadJson: metadata == null || metadata.isEmpty
          ? null
          : jsonEncode(metadata),
      syncStatus: 'pending_sync',
      patientId: (patientId == null || patientId.trim().isEmpty)
          ? null
          : patientId.trim(),
    ).toMap();

    if (kIsWeb || AppDatabase.isWebMemory) {
      AppDatabase.webSessionsInternal.insert(0, row);
      if (AppDatabase.webSessionsInternal.length > _maxSessions) {
        AppDatabase.webSessionsInternal.removeRange(
          _maxSessions,
          AppDatabase.webSessionsInternal.length,
        );
      }
      await _persistWeb();
      await _enqueueWeb(id, row);
      return ClinicalSession.fromMap(row);
    }

    await AppDatabase.db.insert(
      'clinical_sessions',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _enqueueNative(id, row);
    return ClinicalSession.fromMap(row);
  }

  static Future<List<ClinicalSession>> list({int limit = 100}) async {
    if (kIsWeb || AppDatabase.isWebMemory) {
      return AppDatabase.webSessionsInternal
          .take(limit)
          .map(ClinicalSession.fromMap)
          .toList();
    }
    final rows = await AppDatabase.db.query(
      'clinical_sessions',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(ClinicalSession.fromMap).toList();
  }

  static Future<int> pendingSyncCount() async {
    if (kIsWeb || AppDatabase.isWebMemory) {
      final raw = _prefs?.getString(_webSyncQueueKey);
      if (raw == null) return 0;
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        return list
            .whereType<Map>()
            .where((m) => m['status'] == 'pending')
            .length;
      } catch (_) {
        return 0;
      }
    }
    final n = Sqflite.firstIntValue(
          await AppDatabase.db.rawQuery(
            "SELECT COUNT(*) FROM sync_queue WHERE status = 'pending'",
          ),
        ) ??
        0;
    return n;
  }

  /// Pending [sync_queue] rows for an explicit debug flush (network OFF by default).
  static Future<List<Map<String, dynamic>>> listPendingSync({
    int limit = 50,
  }) async {
    if (kIsWeb || AppDatabase.isWebMemory) {
      final raw = _prefs?.getString(_webSyncQueueKey);
      if (raw == null || raw.isEmpty) return [];
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        return list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((m) => m['status'] == 'pending')
            .take(limit)
            .toList();
      } catch (_) {
        return [];
      }
    }
    final rows = await AppDatabase.db.query(
      'sync_queue',
      where: "status = ?",
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> markSynced(String syncId) =>
      markSyncStatus(syncId, 'synced');

  static Future<void> markSyncFailed(String syncId, {String? note}) =>
      markSyncStatus(syncId, 'failed', note: note);

  static Future<void> markSyncStatus(
    String syncId,
    String status, {
    String? note,
  }) async {
    if (kIsWeb || AppDatabase.isWebMemory) {
      final prefs = _prefs;
      if (prefs == null) return;
      final raw = prefs.getString(_webSyncQueueKey);
      if (raw == null || raw.isEmpty) return;
      try {
        final list = (jsonDecode(raw) as List<dynamic>)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        for (final row in list) {
          if (row['id'] == syncId) {
            row['status'] = status;
            if (note != null) row['scrub_note'] = note;
            row['updated_at'] = DateTime.now().toIso8601String();
            break;
          }
        }
        await prefs.setString(_webSyncQueueKey, jsonEncode(list));
      } catch (_) {
        // Corrupt queue — leave unchanged
      }
      return;
    }
    // Native schema has no note column; status is enough for the stub.
    await AppDatabase.db.update(
      'sync_queue',
      {'status': status},
      where: 'id = ?',
      whereArgs: [syncId],
    );
  }

  static Future<void> _persistWeb() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final encoded = jsonEncode(AppDatabase.webSessionsInternal);
    await prefs.setString(_webSessionsKey, encoded);
  }

  /// Scrub only the outbound sync payload — never overwrite local history.
  static Map<String, dynamic> _scrubbedSyncPayload(Map<String, dynamic> row) {
    final out = Map<String, dynamic>.from(row);
    final input = out['input_summary'];
    if (input is String) {
      out['input_summary'] = PiiScrubber.scrub(input);
    }
    final output = out['output_summary'];
    if (output is String) {
      out['output_summary'] = PiiScrubber.scrub(output);
    }
    final payload = out['payload_json'];
    if (payload is String && payload.isNotEmpty) {
      try {
        final meta = jsonDecode(payload);
        if (meta is Map) {
          out['payload_json'] = jsonEncode(
            _scrubMetadata(Map<String, dynamic>.from(meta)),
          );
        } else {
          out['payload_json'] = PiiScrubber.scrub(payload);
        }
      } catch (_) {
        out['payload_json'] = PiiScrubber.scrub(payload);
      }
    }
    return out;
  }

  static Future<void> _enqueueWeb(
    String sessionId,
    Map<String, dynamic> row,
  ) async {
    final prefs = _prefs;
    if (prefs == null) return;
    List<dynamic> queue = [];
    final raw = prefs.getString(_webSyncQueueKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        queue = jsonDecode(raw) as List<dynamic>;
      } catch (_) {
        queue = [];
      }
    }
    final scrubbed = _scrubbedSyncPayload(row);
    final gate = PiiScrubber.evaluateForSync(jsonEncode(scrubbed));
    queue.insert(0, {
      'id': 'sync_$sessionId',
      'session_id': sessionId,
      'payload_json': jsonEncode(scrubbed),
      'scrubbed_at': DateTime.now().toIso8601String(),
      'status': gate.allowed ? 'pending' : 'blocked_residual_pii',
      'scrub_note': gate.reason,
      'created_at': DateTime.now().toIso8601String(),
    });
    if (queue.length > _maxSessions) {
      queue = queue.sublist(0, _maxSessions);
    }
    await prefs.setString(_webSyncQueueKey, jsonEncode(queue));
  }

  static Future<void> _enqueueNative(
    String sessionId,
    Map<String, dynamic> row,
  ) async {
    try {
      final scrubbed = _scrubbedSyncPayload(row);
      final gate = PiiScrubber.evaluateForSync(jsonEncode(scrubbed));
      await AppDatabase.db.insert(
        'sync_queue',
        {
          'id': 'sync_$sessionId',
          'session_id': sessionId,
          'payload_json': jsonEncode(scrubbed),
          'scrubbed_at': DateTime.now().toIso8601String(),
          'status': gate.allowed ? 'pending' : 'blocked_residual_pii',
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // sync_queue table may be missing on very old DB — migration handles v3
    }
  }

  static Map<String, dynamic> _scrubMetadata(Map<String, dynamic> meta) {
    final out = <String, dynamic>{};
    for (final entry in meta.entries) {
      final v = entry.value;
      if (v is String) {
        out[entry.key] = PiiScrubber.scrub(v);
      } else if (v is List) {
        out[entry.key] = v
            .map((item) => item is String ? PiiScrubber.scrub(item) : item)
            .toList();
      } else {
        out[entry.key] = v;
      }
    }
    return out;
  }
}
