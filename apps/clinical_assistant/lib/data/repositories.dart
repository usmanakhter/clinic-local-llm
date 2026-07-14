import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import 'db.dart';

/// Mirrors packages/clinical_core_py repository + search + interactions rules.
class ClinicalRepository {
  ClinicalRepository();

  Future<bool> ftsAvailable() async {
    if (AppDatabase.isWebMemory) return false;
    try {
      final n = Sqflite.firstIntValue(
            await AppDatabase.db.rawQuery('SELECT COUNT(*) AS n FROM drugs_fts'),
          ) ??
          0;
      return n > 0;
    } catch (_) {
      return false;
    }
  }

  Future<Drug?> getDrug(String drugId) async {
    if (AppDatabase.isWebMemory) {
      for (final row in AppDatabase.webDrugs) {
        if (row['id'] == drugId) return Drug.fromMap(row);
      }
      return null;
    }
    final rows = await AppDatabase.db.query(
      'drugs',
      where: 'id = ?',
      whereArgs: [drugId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Drug.fromMap(rows.first);
  }

  Future<List<Drug>> listDrugs({int limit = 50}) async {
    if (AppDatabase.isWebMemory) {
      return AppDatabase.webDrugs
          .take(limit)
          .map(Drug.fromMap)
          .toList();
    }
    final rows = await AppDatabase.db.query(
      'drugs',
      orderBy: 'generic_name COLLATE NOCASE',
      limit: limit,
    );
    return rows.map(Drug.fromMap).toList();
  }

  /// Bidirectional lookup. Never invents severity — null means no curated row.
  Future<Interaction?> checkInteraction(String drugAId, String drugBId) async {
    if (drugAId.isEmpty || drugBId.isEmpty || drugAId == drugBId) {
      return null;
    }
    final exact = await _fetchPair(drugAId, drugBId);
    if (exact != null) return exact;
    return _fetchPair(drugBId, drugAId);
  }

  Future<Interaction?> _fetchPair(String a, String b) async {
    if (AppDatabase.isWebMemory) {
      for (final row in AppDatabase.webInteractions) {
        if (row['drug_a_id'] == a && row['drug_b_id'] == b) {
          return Interaction.fromMap(row);
        }
      }
      return null;
    }
    final rows = await AppDatabase.db.query(
      'interactions',
      where: 'drug_a_id = ? AND drug_b_id = ?',
      whereArgs: [a, b],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Interaction.fromMap(rows.first);
  }

  Future<List<Drug>> searchDrugs(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    List<Drug> candidates;
    if (!AppDatabase.isWebMemory && await ftsAvailable()) {
      try {
        candidates = await _searchFts(q, limit);
      } catch (_) {
        candidates = await _searchLike(q, limit);
      }
    } else {
      candidates = await _searchLike(q, limit);
    }
    return _rankDrugs(candidates, q, limit);
  }

  Future<List<Drug>> _searchFts(String query, int limit) async {
    final match = _ftsMatchQuery(query);
    final rows = await AppDatabase.db.rawQuery(
      '''
SELECT drugs.*
FROM drugs_fts
JOIN drugs ON drugs.rowid = drugs_fts.rowid
WHERE drugs_fts MATCH ?
LIMIT ?
''',
      [match, limit * 3],
    );
    return rows.map(Drug.fromMap).toList();
  }

  Future<List<Drug>> _searchLike(String query, int limit) async {
    final pattern = '%${query.trim()}%';
    if (AppDatabase.isWebMemory) {
      final q = query.trim().toLowerCase();
      return AppDatabase.webDrugs
          .map(Drug.fromMap)
          .where((d) {
            final brands = d.brandNames.map((b) => b.name.toLowerCase()).join(' ');
            return d.genericName.toLowerCase().contains(q) ||
                (d.genericNameNe ?? '').toLowerCase().contains(q) ||
                brands.contains(q) ||
                d.ragText.toLowerCase().contains(q);
          })
          .take(limit * 3)
          .toList();
    }
    final rows = await AppDatabase.db.rawQuery(
      '''
SELECT * FROM drugs
WHERE generic_name LIKE ? COLLATE NOCASE
   OR generic_name_ne LIKE ?
   OR brand_names LIKE ?
LIMIT ?
''',
      [pattern, pattern, pattern, limit * 3],
    );
    return rows.map(Drug.fromMap).toList();
  }

  Future<List<GuidelineChunk>> searchGuidelines(
    String query, {
    int limit = 20,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final pattern = '%$q%';

    List<GuidelineChunk> chunks;
    if (AppDatabase.isWebMemory) {
      final lower = q.toLowerCase();
      chunks = AppDatabase.webGuidelines
          .map(GuidelineChunk.fromMap)
          .where((c) {
            return c.title.toLowerCase().contains(lower) ||
                (c.titleNe ?? '').toLowerCase().contains(lower) ||
                (c.topic ?? '').toLowerCase().contains(lower) ||
                c.chunkText.toLowerCase().contains(lower) ||
                (c.chunkTextNe ?? '').toLowerCase().contains(lower) ||
                c.source.toLowerCase().contains(lower);
          })
          .toList();
    } else {
      final rows = await AppDatabase.db.rawQuery(
        '''
SELECT * FROM guideline_chunks
WHERE title LIKE ? COLLATE NOCASE
   OR title_ne LIKE ?
   OR topic LIKE ? COLLATE NOCASE
   OR chunk_text LIKE ? COLLATE NOCASE
   OR chunk_text_ne LIKE ?
   OR source LIKE ? COLLATE NOCASE
ORDER BY priority DESC
LIMIT ?
''',
        [pattern, pattern, pattern, pattern, pattern, pattern, limit * 3],
      );
      chunks = rows.map(GuidelineChunk.fromMap).toList();
    }

    final ranked = <({GuidelineChunk chunk, double score})>[];
    for (final chunk in chunks) {
      final score = _scoreGuideline(chunk, q);
      if (score <= 0) continue;
      ranked.add((chunk: chunk, score: score));
    }
    ranked.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.chunk.title.toLowerCase().compareTo(b.chunk.title.toLowerCase());
    });
    return ranked.take(limit).map((e) => e.chunk).toList();
  }

  Future<void> upsertConsentRecord({
    required bool granted,
    required List<String> scopes,
    required String consentVersion,
  }) async {
    if (AppDatabase.isWebMemory) return;
    final now = DateTime.now().toIso8601String();
    await AppDatabase.db.insert(
      'consent_records',
      {
        'id': 'local_device',
        'clinician_id': 'local',
        'scope': jsonEncode(scopes),
        'granted': granted ? 1 : 0,
        'consent_version': consentVersion,
        'granted_at': granted ? now : null,
        'revoked_at': granted ? null : now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

String _ftsMatchQuery(String query) {
  final tokens = RegExp(r'[\w\u0900-\u097F]+', unicode: true)
      .allMatches(query)
      .map((m) => m.group(0)!)
      .toList();
  if (tokens.isEmpty) return query.trim();
  final parts = tokens.map((t) {
    final ascii = RegExp(r'^[\x00-\x7F]+$').hasMatch(t);
    return ascii ? '"$t"*' : '"$t"';
  });
  return parts.join(' OR ');
}

List<Drug> _rankDrugs(List<Drug> drugs, String query, int limit) {
  final q = query.trim().toLowerCase();
  final seen = <String>{};
  final ranked = <({Drug drug, double score})>[];
  for (final drug in drugs) {
    if (!seen.add(drug.id)) continue;
    final score = _scoreDrug(drug, q);
    if (score <= 0) continue;
    ranked.add((drug: drug, score: score));
  }
  ranked.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return a.drug.genericName
        .toLowerCase()
        .compareTo(b.drug.genericName.toLowerCase());
  });
  return ranked.take(limit).map((e) => e.drug).toList();
}

double _scoreDrug(Drug drug, String q) {
  if (q.isEmpty) return 0;
  final gn = drug.genericName.toLowerCase();
  final gnNe = (drug.genericNameNe ?? '').toLowerCase();
  final brands = drug.brandNames.map((b) => b.name.toLowerCase()).toList();
  final brandHay = brands.join(' ');

  if (gn == q) return 100;
  if (brands.any((b) => b == q)) return 95;
  if (gnNe == q) return 92;
  if (gn.startsWith(q)) return 85;
  if (brands.any((b) => b.startsWith(q))) return 80;
  if (gn.contains(q)) return 70;
  if (brandHay.contains(q)) return 65;
  if (gnNe.contains(q)) return 60;
  if (drug.ragText.toLowerCase().contains(q)) return 40;
  return 10;
}

double _scoreGuideline(GuidelineChunk chunk, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return 0;
  final title = chunk.title.toLowerCase();
  final titleNe = (chunk.titleNe ?? '').toLowerCase();
  final topic = (chunk.topic ?? '').toLowerCase();
  final body = chunk.chunkText.toLowerCase();
  final bodyNe = (chunk.chunkTextNe ?? '').toLowerCase();
  final source = chunk.source.toLowerCase();
  final p = chunk.priority.toDouble();

  if (title == q || topic == q) return 100 + p;
  if (title.contains(q)) return 80 + p;
  if (topic.contains(q)) return 70 + p;
  if (titleNe.contains(q)) return 65 + p;
  if (body.contains(q)) return 50 + p;
  if (bodyNe.contains(q)) return 45 + p;
  if (source.contains(q)) return 30 + p;
  return 0;
}
