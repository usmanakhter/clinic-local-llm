import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import '../privacy/pii_scrubber.dart';
import 'db.dart';

/// Persists scrubbed clinical activity locally (device DB or web prefs).
/// Rows are queued for future consent-gated sync — no backend upload yet.
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
  }) async {
    final scrubbedIn = PiiScrubber.scrub(inputSummary);
    final scrubbedOut =
        outputSummary == null ? null : PiiScrubber.scrub(outputSummary);
    Map<String, dynamic>? scrubbedMeta;
    if (metadata != null && metadata.isNotEmpty) {
      scrubbedMeta = _scrubMetadata(metadata);
    }

    final id = 'sess_${DateTime.now().millisecondsSinceEpoch}';
    final row = ClinicalSession(
      id: id,
      createdAt: DateTime.now(),
      queryType: queryType,
      inputSummary: scrubbedIn,
      outputSummary: scrubbedOut,
      payloadJson: scrubbedMeta == null ? null : jsonEncode(scrubbedMeta),
      syncStatus: 'pending_sync',
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

  static Future<void> _persistWeb() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final encoded = jsonEncode(AppDatabase.webSessionsInternal);
    await prefs.setString(_webSessionsKey, encoded);
  }

  static Future<void> _enqueueWeb(String sessionId, Map<String, dynamic> row) async {
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
    queue.insert(0, {
      'id': 'sync_$sessionId',
      'session_id': sessionId,
      'payload_json': jsonEncode(row),
      'scrubbed_at': DateTime.now().toIso8601String(),
      'status': 'pending',
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
      await AppDatabase.db.insert(
        'sync_queue',
        {
          'id': 'sync_$sessionId',
          'session_id': sessionId,
          'payload_json': jsonEncode(row),
          'scrubbed_at': DateTime.now().toIso8601String(),
          'status': 'pending',
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
