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

    final byId = <String, Drug>{};
    if (!AppDatabase.isWebMemory && await ftsAvailable()) {
      try {
        for (final d in await _searchFts(q, limit)) {
          byId[d.id] = d;
        }
      } catch (_) {
        // LIKE path below
      }
    }
    for (final d in await _searchLike(q, limit)) {
      byId[d.id] = d;
    }
    return _rankDrugs(byId.values.toList(), q, limit);
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
    final tokens = _searchTokens(query);
    if (AppDatabase.isWebMemory) {
      final drugs = AppDatabase.webDrugs.map(Drug.fromMap).toList();
      final hits = <String, Drug>{};
      for (final tok in tokens) {
        final q = tok.toLowerCase();
        for (final d in drugs) {
          final brands =
              d.brandNames.map((b) => b.name.toLowerCase()).join(' ');
          final hay = [
            d.genericName.toLowerCase(),
            (d.genericNameNe ?? '').toLowerCase(),
            brands,
            d.ragText.toLowerCase(),
            d.indications.map((e) => e.toLowerCase()).join(' '),
          ].join(' ');
          if (hay.contains(q)) hits[d.id] = d;
        }
      }
      return hits.values.take(limit * 5).toList();
    }
    final seen = <String, Drug>{};
    for (final tok in tokens) {
      final pattern = '%$tok%';
      final rows = await AppDatabase.db.rawQuery(
        '''
SELECT * FROM drugs
WHERE generic_name LIKE ? COLLATE NOCASE
   OR generic_name_ne LIKE ?
   OR brand_names LIKE ?
   OR rag_text LIKE ? COLLATE NOCASE
   OR indications LIKE ?
LIMIT ?
''',
        [pattern, pattern, pattern, pattern, pattern, limit * 3],
      );
      for (final row in rows) {
        final d = Drug.fromMap(row);
        seen[d.id] = d;
      }
    }
    return seen.values.take(limit * 5).toList();
  }

  Future<List<GuidelineChunk>> searchGuidelines(
    String query, {
    int limit = 20,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final tokens = _searchTokens(q);

    final byId = <String, GuidelineChunk>{};
    if (AppDatabase.isWebMemory) {
      final all = AppDatabase.webGuidelines.map(GuidelineChunk.fromMap);
      for (final tok in tokens) {
        final lower = tok.toLowerCase();
        for (final c in all) {
          final hay = [
            c.title,
            c.titleNe ?? '',
            c.topic ?? '',
            c.chunkText,
            c.chunkTextNe ?? '',
            c.source,
          ].join(' ').toLowerCase();
          if (hay.contains(lower)) byId[c.id] = c;
        }
      }
    } else {
      // Prefer guideline FTS when present; always merge token LIKE hits.
      if (await _guidelineFtsAvailable()) {
        try {
          final match = _ftsMatchQuery(q);
          final rows = await AppDatabase.db.rawQuery(
            '''
SELECT guideline_chunks.*
FROM guidelines_fts
JOIN guideline_chunks ON guideline_chunks.rowid = guidelines_fts.rowid
WHERE guidelines_fts MATCH ?
LIMIT ?
''',
            [match, limit * 5],
          );
          for (final row in rows) {
            final c = GuidelineChunk.fromMap(row);
            byId[c.id] = c;
          }
        } catch (_) {
          // fall through to LIKE
        }
      }
      for (final tok in tokens) {
        final pattern = '%$tok%';
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
        for (final row in rows) {
          final c = GuidelineChunk.fromMap(row);
          byId[c.id] = c;
        }
      }
    }

    final ranked = <({GuidelineChunk chunk, double score})>[];
    for (final chunk in byId.values) {
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

  Future<bool> _guidelineFtsAvailable() async {
    if (AppDatabase.isWebMemory) return false;
    try {
      final n = Sqflite.firstIntValue(
            await AppDatabase.db.rawQuery(
              'SELECT COUNT(*) AS n FROM guidelines_fts',
            ),
          ) ??
          0;
      return n > 0;
    } catch (_) {
      return false;
    }
  }

  /// Scrub structural PII then persist a local clinical session (never synced here).
  Future<void> logSession({
    required String queryType,
    required String inputSummary,
    String? outputSummary,
  }) async {
    await AppDatabase.insertSession(
      queryType: queryType,
      inputSummary: inputSummary,
      outputSummary: outputSummary,
    );
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

const _stopwords = {
  'a', 'an', 'the', 'and', 'or', 'of', 'for', 'to', 'in', 'on', 'with', 'no',
  'not', 'dose', 'child', 'years', 'year', 'safe', 'problem', 'together',
  'should', 'give', 'first', 'aid', 'cheap', 'start', 'rural', 'nepal',
  'medicine', 'fever', 'avoid', 'cold', 'flu',
};

List<String> _searchTokens(String query) {
  final raw = RegExp(r'[\w\u0900-\u097F]+', unicode: true)
      .allMatches(query)
      .map((m) => m.group(0)!)
      .toList();
  final out = <String>[];
  for (final t in raw) {
    final tl = t.toLowerCase();
    if (tl.length < 2 || _stopwords.contains(tl)) continue;
    out.add(t);
  }
  if (out.isEmpty) return raw.isEmpty ? [query.trim()] : raw;
  return out;
}

String _ftsMatchQuery(String query) {
  final tokens = _searchTokens(query);
  if (tokens.isEmpty) return query.trim();
  final parts = tokens.map((t) {
    final ascii = RegExp(r'^[\x00-\x7F]+$').hasMatch(t);
    return ascii ? '"$t"*' : '"$t"';
  });
  return parts.join(' OR ');
}

List<Drug> _rankDrugs(List<Drug> drugs, String query, int limit) {
  final seen = <String>{};
  final ranked = <({Drug drug, double score})>[];
  for (final drug in drugs) {
    if (!seen.add(drug.id)) continue;
    final score = _scoreDrug(drug, query);
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

double _scoreDrug(Drug drug, String query) {
  final qFull = query.trim().toLowerCase();
  if (qFull.isEmpty) return 0;
  final gn = drug.genericName.toLowerCase();
  final gnNe = (drug.genericNameNe ?? '').toLowerCase();
  final brands = drug.brandNames.map((b) => b.name.toLowerCase()).toList();
  final brandHay = brands.join(' ');
  final rag = drug.ragText.toLowerCase();
  final indications = drug.indications.map((e) => e.toLowerCase()).join(' ');

  double scoreOne(String q) {
    if (gn == q) return 100;
    if (brands.any((b) => b == q)) return 95;
    if (gnNe == q) return 92;
    if (gn.startsWith(q)) return 85;
    if (brands.any((b) => b.startsWith(q))) return 80;
    if (gn.contains(q)) return 70;
    if (brandHay.contains(q)) return 65;
    if (gnNe.contains(q)) return 60;
    if (rag.contains(q) || indications.contains(q)) return 40;
    return 0;
  }

  var best = scoreOne(qFull);
  for (final tok in _searchTokens(query)) {
    final s = scoreOne(tok.toLowerCase());
    if (s > best) best = s;
  }
  return best > 0 ? best : 10;
}

double _scoreGuideline(GuidelineChunk chunk, String query) {
  final qFull = query.trim().toLowerCase();
  if (qFull.isEmpty) return 0;
  final title = chunk.title.toLowerCase();
  final titleNe = (chunk.titleNe ?? '').toLowerCase();
  final topic = (chunk.topic ?? '').toLowerCase();
  final body = chunk.chunkText.toLowerCase();
  final bodyNe = (chunk.chunkTextNe ?? '').toLowerCase();
  final source = chunk.source.toLowerCase();
  final p = chunk.priority.toDouble();

  double scoreOne(String q) {
    if (title == q || topic == q) return 100 + p;
    if (title.contains(q)) return 80 + p;
    if (topic.contains(q)) return 70 + p;
    if (titleNe.contains(q)) return 65 + p;
    if (body.contains(q)) return 50 + p;
    if (bodyNe.contains(q)) return 45 + p;
    if (source.contains(q)) return 30 + p;
    return 0;
  }

  var best = scoreOne(qFull);
  var bonus = 0.0;
  for (final tok in _searchTokens(query)) {
    final s = scoreOne(tok.toLowerCase());
    if (s > best) {
      best = s;
    } else if (s > 0) {
      bonus += 5;
    }
  }
  if (best <= 0) return 0;
  return best + (bonus > 20 ? 20 : bonus);
}
