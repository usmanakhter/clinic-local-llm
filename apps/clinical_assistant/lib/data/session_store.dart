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

  /// Sync-queue status when the on-device scrub gate blocks upload.
  static const statusBlockedResidualPii = 'blocked_residual_pii';
  static const statusPending = 'pending';

  /// Maps scrub-gate result → sync_queue status (never upload blocked rows).
  static String statusForScrubGate(SyncScrubResult gate) =>
      gate.allowed ? statusPending : statusBlockedResidualPii;

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

  /// All sync_queue rows for transparency UI (any status).
  static Future<List<Map<String, dynamic>>> listSyncQueue({
    int limit = 100,
  }) async {
    if (kIsWeb || AppDatabase.isWebMemory) {
      final raw = _prefs?.getString(_webSyncQueueKey);
      if (raw == null || raw.isEmpty) return [];
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        return list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .take(limit)
            .toList();
      } catch (_) {
        return [];
      }
    }
    final rows = await AppDatabase.db.query(
      'sync_queue',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Structured chat feedback — updates local session + sync payload metadata.
  static Future<void> updateFeedback({
    required String sessionId,
    required String feedback,
    String? reason,
  }) async {
    if (feedback != 'up' && feedback != 'down') {
      throw ArgumentError('feedback must be up or down');
    }
    if (kIsWeb || AppDatabase.isWebMemory) {
      for (final row in AppDatabase.webSessionsInternal) {
        if (row['id'] == sessionId) {
          row['feedback'] = feedback;
          row['feedback_reason'] = reason;
          break;
        }
      }
      await _persistWeb();
      await _refreshSyncFeedback(sessionId, feedback, reason);
      return;
    }
    await AppDatabase.db.update(
      'clinical_sessions',
      {'feedback': feedback, 'feedback_reason': reason},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    await _refreshSyncFeedback(sessionId, feedback, reason);
  }

  /// Update an existing saved note draft (local history + re-enqueue scrubbed sync).
  static Future<ClinicalSession> updateNoteDraft({
    required String sessionId,
    required String chiefComplaint,
    required String history,
    required String examination,
    required String assessment,
    required String plan,
    required String draftText,
    bool fromModel = false,
    String? patientId,
  }) async {
    final metadata = {
      'action': 'save',
      'patient_id': patientId,
      'chief_complaint': chiefComplaint,
      'history': history,
      'examination': examination,
      'assessment': assessment,
      'plan': plan,
      'draft_text': draftText,
      'from_model': fromModel,
      'edited_at': DateTime.now().toIso8601String(),
    };
    final row = {
      'input_summary': chiefComplaint,
      'output_summary': 'saved_locally',
      'payload_json': jsonEncode(metadata),
      'patient_id':
          (patientId == null || patientId.trim().isEmpty) ? null : patientId.trim(),
      'sync_status': 'pending_sync',
    };

    if (kIsWeb || AppDatabase.isWebMemory) {
      Map<String, dynamic>? existing;
      for (final s in AppDatabase.webSessionsInternal) {
        if (s['id'] == sessionId) {
          existing = s;
          break;
        }
      }
      if (existing == null) {
        throw StateError('Note session not found: $sessionId');
      }
      existing.addAll(row);
      await _persistWeb();
      await _enqueueWeb(sessionId, Map<String, dynamic>.from(existing));
      return ClinicalSession.fromMap(existing);
    }

    final existingRows = await AppDatabase.db.query(
      'clinical_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (existingRows.isEmpty) {
      throw StateError('Note session not found: $sessionId');
    }
    await AppDatabase.db.update(
      'clinical_sessions',
      row,
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    final updated = {
      ...existingRows.first,
      ...row,
      'id': sessionId,
    };
    await _enqueueNative(sessionId, updated);
    return ClinicalSession.fromMap(updated);
  }

  static Future<void> _refreshSyncFeedback(
    String sessionId,
    String feedback,
    String? reason,
  ) async {
    final syncId = 'sync_$sessionId';
    if (kIsWeb || AppDatabase.isWebMemory) {
      final prefs = _prefs;
      if (prefs == null) return;
      final raw = prefs.getString(_webSyncQueueKey);
      if (raw == null) return;
      try {
        final list = (jsonDecode(raw) as List<dynamic>)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        for (final row in list) {
          if (row['session_id'] == sessionId || row['id'] == syncId) {
            var payload = row['payload_json'];
            Map<String, dynamic> map;
            if (payload is String) {
              map = jsonDecode(payload) as Map<String, dynamic>;
            } else if (payload is Map) {
              map = Map<String, dynamic>.from(payload);
            } else {
              map = {};
            }
            map['feedback'] = feedback;
            if (reason != null) map['feedback_reason'] = reason;
            row['payload_json'] = jsonEncode(map);
            break;
          }
        }
        await prefs.setString(_webSyncQueueKey, jsonEncode(list));
      } catch (_) {}
      return;
    }
    try {
      final rows = await AppDatabase.db.query(
        'sync_queue',
        where: 'session_id = ? OR id = ?',
        whereArgs: [sessionId, syncId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final row = rows.first;
      final payloadRaw = row['payload_json'] as String?;
      if (payloadRaw == null) return;
      final map = jsonDecode(payloadRaw) as Map<String, dynamic>;
      map['feedback'] = feedback;
      if (reason != null) map['feedback_reason'] = reason;
      await AppDatabase.db.update(
        'sync_queue',
        {'payload_json': jsonEncode(map)},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    } catch (_) {}
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
    final values = <String, Object?>{'status': status};
    if (note != null) values['scrub_note'] = note;
    await AppDatabase.db.update(
      'sync_queue',
      values,
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
      'status': statusForScrubGate(gate),
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
          'status': statusForScrubGate(gate),
          'scrub_note': gate.reason,
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
