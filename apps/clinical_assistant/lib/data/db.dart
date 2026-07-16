import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

/// Opens local SQLite (native) or an in-memory store (web), then seeds from assets.
class AppDatabase {
  AppDatabase._();

  static Database? _db;
  static bool _webMemory = false;
  static final List<Map<String, dynamic>> _webDrugs = [];
  static final List<Map<String, dynamic>> _webInteractions = [];
  static final List<Map<String, dynamic>> _webGuidelines = [];
  static final List<Map<String, dynamic>> _webSessions = [];
  static ConsentTemplate? consentTemplate;

  static bool get isWebMemory => _webMemory;

  /// Mutable web session store — persisted via [SessionStore] + SharedPreferences.
  static List<Map<String, dynamic>> get webSessionsInternal => _webSessions;

  static Database get db {
    final d = _db;
    if (d == null) {
      throw StateError('AppDatabase not initialized. Call AppDatabase.init() first.');
    }
    return d;
  }

  static List<Map<String, dynamic>> get webDrugs =>
      List.unmodifiable(_webDrugs);
  static List<Map<String, dynamic>> get webInteractions =>
      List.unmodifiable(_webInteractions);
  static List<Map<String, dynamic>> get webGuidelines =>
      List.unmodifiable(_webGuidelines);
  static List<Map<String, dynamic>> get webSessions =>
      List.unmodifiable(_webSessions);

  static Future<void> init() async {
    consentTemplate = await _loadConsentTemplate();

    if (kIsWeb) {
      _webMemory = true;
      await _seedWebMemory();
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'nepal_mvp.db');
    _db = await openDatabase(
      path,
      version: 3,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, version) async {
        await _createSchema(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _ensureSessionsAndGuidelineFts(database);
        }
        if (oldVersion < 3) {
          await _migrateV3(database);
        }
      },
    );

    await _seedIfEmpty(_db!);
    await _ensureSessionsAndGuidelineFts(_db!);
    await _ensureSyncQueue(_db!);
  }

  static Future<void> _migrateV3(Database database) async {
    try {
      await database.execute(
        "ALTER TABLE clinical_sessions ADD COLUMN payload_json TEXT",
      );
    } catch (_) {}
    try {
      await database.execute(
        "ALTER TABLE clinical_sessions ADD COLUMN sync_status TEXT "
        "NOT NULL DEFAULT 'pending_sync'",
      );
    } catch (_) {}
    await _ensureSyncQueue(database);
  }

  static Future<ConsentTemplate> _loadConsentTemplate() async {
    try {
      final raw =
          await rootBundle.loadString('assets/nepal/consent_templates.json');
      return ConsentTemplate.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const ConsentTemplate(
        consentVersion: 'np-pilot-1.0',
        templates: {
          'onboarding_title': {
            'en': 'Help improve clinical AI for Nepal',
            'ne': 'नेपालका लागि क्लिनिकल AI सुधार गर्न मद्दत गर्नुहोस्',
          },
          'onboarding_body': {
            'en':
                'This app works fully offline. Optional sharing of de-identified data is OFF by default.',
            'ne': 'यो एप अफलाइन चल्छ। पूर्वनिर्धारित: बन्द।',
          },
          'scope_model_improvement': {
            'en':
                'Use my de-identified interactions to improve the local AI model',
            'ne':
                'मेरो पहिचान नखुलेका प्रश्नहरू AI मोडेल सुधारका लागि प्रयोग गर्नुहोस्',
          },
          'scope_analytics': {
            'en': 'Anonymous usage statistics (no clinical content)',
            'ne': 'गुमनाम प्रयोग तथ्याङ्क (क्लिनिकल सामग्री बिना)',
          },
          'data_transparency': {
            'en':
                'You can view, export, or delete all data associated with your device at any time.',
            'ne':
                'जुनसुकै बेला हेर्न, निर्यात वा मेटाउन सक्नुहुन्छ।',
          },
          'wifi_only_notice': {
            'en': 'Data uploads only on Wi-Fi unless you change this in Settings.',
            'ne': 'डाटा Wi-Fi मा मात्र पठाइन्छ।',
          },
          'prohibited_uses': {
            'en':
                'We do not sell data to life insurers or employers. Data is not used for automated diagnosis.',
            'ne':
                'जीवन बीमा वा रोजगारदातालाई डाटा बेचिँदैन। स्वचालित निदानका लागि प्रयोग हुँदैन।',
          },
        },
      );
    }
  }

  static Future<void> _createSchema(Database database) async {
    await database.execute('''
CREATE TABLE IF NOT EXISTS drugs (
    id              TEXT PRIMARY KEY,
    generic_name    TEXT NOT NULL,
    generic_name_ne TEXT,
    category        TEXT,
    nelm_tier       TEXT CHECK (nelm_tier IN ('core', 'complementary', 'supplementary')),
    dosage_forms    TEXT NOT NULL,
    strengths       TEXT NOT NULL,
    brand_names     TEXT NOT NULL,
    indications     TEXT,
    contraindications TEXT,
    adult_dose      TEXT,
    pediatric_dose  TEXT,
    pregnancy_category TEXT,
    rag_text        TEXT NOT NULL,
    updated_at      TEXT DEFAULT (datetime('now'))
)
''');

    // FTS5 may be unavailable on some builds; fall back silently in seed.
    try {
      await database.execute('''
CREATE VIRTUAL TABLE IF NOT EXISTS drugs_fts USING fts5(
    generic_name,
    generic_name_ne,
    brand_names,
    rag_text,
    content='drugs',
    content_rowid='rowid'
)
''');
    } catch (_) {
      // LIKE search remains available without FTS.
    }

    await database.execute('''
CREATE TABLE IF NOT EXISTS interactions (
    id              TEXT PRIMARY KEY,
    drug_a_id       TEXT NOT NULL REFERENCES drugs(id),
    drug_b_id       TEXT NOT NULL REFERENCES drugs(id),
    severity        TEXT NOT NULL CHECK (severity IN ('contraindicated', 'major', 'moderate', 'minor')),
    mechanism       TEXT,
    clinical_effect TEXT,
    recommendation  TEXT NOT NULL,
    source          TEXT,
    UNIQUE (drug_a_id, drug_b_id)
)
''');

    await database.execute('''
CREATE TABLE IF NOT EXISTS guideline_chunks (
    id              TEXT PRIMARY KEY,
    title           TEXT NOT NULL,
    title_ne        TEXT,
    source          TEXT NOT NULL,
    topic           TEXT,
    chunk_text      TEXT NOT NULL,
    chunk_text_ne   TEXT,
    priority        INTEGER DEFAULT 0
)
''');

    await database.execute('''
CREATE TABLE IF NOT EXISTS consent_records (
    id              TEXT PRIMARY KEY,
    clinician_id    TEXT,
    scope           TEXT NOT NULL,
    granted         INTEGER NOT NULL DEFAULT 0,
    consent_version TEXT NOT NULL,
    granted_at      TEXT,
    revoked_at      TEXT
)
''');

    await _ensureSessionsAndGuidelineFts(database);

    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_drugs_generic ON drugs(generic_name)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_interactions_drugs ON interactions(drug_a_id, drug_b_id)',
    );
  }

  static Future<void> _ensureSessionsAndGuidelineFts(Database database) async {
    await database.execute('''
CREATE TABLE IF NOT EXISTS clinical_sessions (
    id              TEXT PRIMARY KEY,
    created_at      TEXT NOT NULL,
    query_type      TEXT NOT NULL,
    input_summary   TEXT,
    output_summary  TEXT,
    payload_json    TEXT,
    sync_status     TEXT NOT NULL DEFAULT 'pending_sync',
    feedback        TEXT,
    patient_id      TEXT,
    device_id       TEXT
)
''');
    await _ensureSyncQueue(database);
    try {
      await database.execute('''
CREATE VIRTUAL TABLE IF NOT EXISTS guidelines_fts USING fts5(
    title,
    title_ne,
    topic,
    chunk_text,
    chunk_text_ne,
    source,
    content='guideline_chunks',
    content_rowid='rowid'
)
''');
    } catch (_) {
      // FTS optional
    }
  }

  static Future<void> _ensureSyncQueue(Database database) async {
    await database.execute('''
CREATE TABLE IF NOT EXISTS sync_queue (
    id              TEXT PRIMARY KEY,
    session_id      TEXT,
    payload_json    TEXT NOT NULL,
    scrubbed_at     TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'pending',
    created_at      TEXT
)
''');
  }

  static Future<void> _seedIfEmpty(Database database) async {
    final count = Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) AS c FROM drugs'),
        ) ??
        0;
    if (count > 0) return;

    final drugs = await _loadDrugs();
    final interactions = await _loadInteractions();
    final guidelines = await _loadGuidelines();

    final batch = database.batch();
    for (final drug in drugs) {
      batch.insert('drugs', drug.toSqlMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    for (final ix in interactions) {
      batch.insert('interactions', ix.toSqlMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    for (final g in guidelines) {
      batch.insert('guideline_chunks', g.toSqlMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    await _rebuildFts(database);
    await _rebuildGuidelineFts(database);
  }

  static Future<void> _rebuildFts(Database database) async {
    try {
      await database.delete('drugs_fts');
      await database.execute('''
INSERT INTO drugs_fts(rowid, generic_name, generic_name_ne, brand_names, rag_text)
SELECT rowid, generic_name, generic_name_ne, brand_names, rag_text FROM drugs
''');
    } catch (_) {
      // FTS not available.
    }
  }

  static Future<void> _rebuildGuidelineFts(Database database) async {
    try {
      await database.delete('guidelines_fts');
      await database.execute('''
INSERT INTO guidelines_fts(rowid, title, title_ne, topic, chunk_text, chunk_text_ne, source)
SELECT rowid, title, title_ne, topic, chunk_text, chunk_text_ne, source FROM guideline_chunks
''');
    } catch (_) {
      // FTS not available.
    }
  }

  static Future<void> _seedWebMemory() async {
    _webDrugs
      ..clear()
      ..addAll((await _loadDrugs()).map((d) => d.toSqlMap()));
    _webInteractions
      ..clear()
      ..addAll((await _loadInteractions()).map((i) => i.toSqlMap()));
    _webGuidelines
      ..clear()
      ..addAll((await _loadGuidelines()).map((g) => g.toSqlMap()));
  }

  static Future<List<Drug>> _loadDrugs() async {
    final raw = await rootBundle.loadString('assets/nepal/drugs.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = json['drugs'] as List<dynamic>? ?? [];
    return list
        .whereType<Map>()
        .map((e) => Drug.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<List<Interaction>> _loadInteractions() async {
    final raw = await rootBundle.loadString('assets/nepal/interactions.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = json['interactions'] as List<dynamic>? ?? [];
    return list
        .whereType<Map>()
        .map((e) => Interaction.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<List<GuidelineChunk>> _loadGuidelines() async {
    final raw =
        await rootBundle.loadString('assets/nepal/guideline_chunks.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = json['chunks'] as List<dynamic>? ?? [];
    return list
        .whereType<Map>()
        .map((e) => GuidelineChunk.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }
}
