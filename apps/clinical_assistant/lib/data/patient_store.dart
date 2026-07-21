import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import 'db.dart';

/// Local patient registry (not a full EMR). Plain-text on-device only.
class PatientStore {
  PatientStore._();

  static const _webPatientsKey = 'nepal_patients_v1';
  static SharedPreferences? _prefs;

  static Future<void> initWebPersistence(SharedPreferences prefs) async {
    _prefs = prefs;
    final raw = prefs.getString(_webPatientsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      AppDatabase.webPatientsInternal
        ..clear()
        ..addAll(
          list
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e)),
        );
    } catch (_) {
      AppDatabase.webPatientsInternal.clear();
    }
  }

  static Future<List<Patient>> list() async {
    if (kIsWeb || AppDatabase.isWebMemory) {
      final rows = List<Map<String, dynamic>>.from(
        AppDatabase.webPatientsInternal,
      );
      rows.sort((a, b) {
        final au = a['updated_at'] as String? ?? '';
        final bu = b['updated_at'] as String? ?? '';
        return bu.compareTo(au);
      });
      return rows.map(Patient.fromMap).toList();
    }
    final rows = await AppDatabase.db.query(
      'patients',
      orderBy: 'updated_at DESC',
    );
    return rows.map(Patient.fromMap).toList();
  }

  static Future<Patient?> get(String id) async {
    if (id.isEmpty) return null;
    if (kIsWeb || AppDatabase.isWebMemory) {
      for (final row in AppDatabase.webPatientsInternal) {
        if (row['id'] == id) return Patient.fromMap(row);
      }
      return null;
    }
    final rows = await AppDatabase.db.query(
      'patients',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Patient.fromMap(rows.first);
  }

  static Future<Patient> upsert({
    String? id,
    required String displayName,
    String? age,
    String? sex,
    String? clinicalCondition,
    String? relevantNotes,
    String? history,
  }) async {
    final name = displayName.trim();
    if (name.isEmpty) {
      throw ArgumentError('Patient name is required');
    }
    final now = DateTime.now();
    final existingId = id?.trim();
    Patient patient;
    if (existingId != null && existingId.isNotEmpty) {
      final prev = await get(existingId);
      patient = Patient(
        id: existingId,
        displayName: name,
        age: _emptyToNull(age),
        sex: _emptyToNull(sex),
        clinicalCondition: _emptyToNull(clinicalCondition),
        relevantNotes: _emptyToNull(relevantNotes),
        history: _emptyToNull(history),
        createdAt: prev?.createdAt ?? now,
        updatedAt: now,
      );
    } else {
      patient = Patient(
        id: 'pat_${now.millisecondsSinceEpoch}',
        displayName: name,
        age: _emptyToNull(age),
        sex: _emptyToNull(sex),
        clinicalCondition: _emptyToNull(clinicalCondition),
        relevantNotes: _emptyToNull(relevantNotes),
        history: _emptyToNull(history),
        createdAt: now,
        updatedAt: now,
      );
    }

    final row = patient.toMap();
    if (kIsWeb || AppDatabase.isWebMemory) {
      final list = AppDatabase.webPatientsInternal;
      final idx = list.indexWhere((e) => e['id'] == patient.id);
      if (idx >= 0) {
        list[idx] = row;
      } else {
        list.insert(0, row);
      }
      await _persistWeb();
      return patient;
    }

    await AppDatabase.db.insert(
      'patients',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return patient;
  }

  static Future<void> delete(String id) async {
    if (kIsWeb || AppDatabase.isWebMemory) {
      AppDatabase.webPatientsInternal.removeWhere((e) => e['id'] == id);
      await _persistWeb();
      return;
    }
    await AppDatabase.db.delete('patients', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> _persistWeb() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString(
      _webPatientsKey,
      jsonEncode(AppDatabase.webPatientsInternal),
    );
  }

  static String? _emptyToNull(String? v) {
    if (v == null) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
}
