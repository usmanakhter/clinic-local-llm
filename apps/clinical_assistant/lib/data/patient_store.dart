import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../data/db_crypto.dart';
import '../models/models.dart';
import 'db.dart';

/// Local patient registry (not a full EMR). Sensitive fields encrypted at rest.
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
      final out = <Patient>[];
      for (final r in rows) {
        out.add(await _decryptPatient(Patient.fromMap(r)));
      }
      return out;
    }
    final rows = await AppDatabase.db.query(
      'patients',
      orderBy: 'updated_at DESC',
    );
    final out = <Patient>[];
    for (final r in rows) {
      out.add(await _decryptPatient(Patient.fromMap(r)));
    }
    return out;
  }

  static Future<Patient?> get(String id) async {
    if (id.isEmpty) return null;
    if (kIsWeb || AppDatabase.isWebMemory) {
      for (final row in AppDatabase.webPatientsInternal) {
        if (row['id'] == id) {
          return _decryptPatient(Patient.fromMap(row));
        }
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
    return _decryptPatient(Patient.fromMap(rows.first));
  }

  static Future<Patient> upsert({
    String? id,
    required String displayName,
    String? age,
    String? sex,
    String? phone,
    String? whatsapp,
    String? email,
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
        phone: _emptyToNull(phone),
        whatsapp: _emptyToNull(whatsapp),
        email: _emptyToNull(email),
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
        phone: _emptyToNull(phone),
        whatsapp: _emptyToNull(whatsapp),
        email: _emptyToNull(email),
        clinicalCondition: _emptyToNull(clinicalCondition),
        relevantNotes: _emptyToNull(relevantNotes),
        history: _emptyToNull(history),
        createdAt: now,
        updatedAt: now,
      );
    }

    final row = await _encryptMap(patient.toMap());
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

  static Future<Patient> _decryptPatient(Patient p) async {
    return Patient(
      id: p.id,
      displayName: await DbCrypto.decryptOptional(p.displayName) ?? p.displayName,
      age: p.age,
      sex: p.sex,
      phone: await DbCrypto.decryptOptional(p.phone),
      whatsapp: await DbCrypto.decryptOptional(p.whatsapp),
      email: await DbCrypto.decryptOptional(p.email),
      clinicalCondition: p.clinicalCondition,
      relevantNotes: await DbCrypto.decryptOptional(p.relevantNotes),
      history: await DbCrypto.decryptOptional(p.history),
      createdAt: p.createdAt,
      updatedAt: p.updatedAt,
    );
  }

  static Future<Map<String, dynamic>> _encryptMap(Map<String, dynamic> row) async {
    final out = Map<String, dynamic>.from(row);
    out['display_name'] = await DbCrypto.encryptOptional(row['display_name'] as String?);
    out['phone'] = await DbCrypto.encryptOptional(row['phone'] as String?);
    out['whatsapp'] = await DbCrypto.encryptOptional(row['whatsapp'] as String?);
    out['email'] = await DbCrypto.encryptOptional(row['email'] as String?);
    out['relevant_notes'] = await DbCrypto.encryptOptional(row['relevant_notes'] as String?);
    out['history'] = await DbCrypto.encryptOptional(row['history'] as String?);
    return out;
  }
}
