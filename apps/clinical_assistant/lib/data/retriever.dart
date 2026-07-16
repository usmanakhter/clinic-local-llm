import 'repositories.dart';

class RetrievedDrugHit {
  const RetrievedDrugHit({
    required this.id,
    required this.genericName,
    required this.score,
    required this.excerpt,
  });

  final String id;
  final String genericName;
  final double score;
  final String excerpt;
}

class RetrievedGuidelineHit {
  const RetrievedGuidelineHit({
    required this.id,
    required this.title,
    required this.source,
    required this.excerpt,
    this.topic,
    required this.score,
  });

  final String id;
  final String title;
  final String source;
  final String? topic;
  final double score;
  final String excerpt;
}

class RetrieveBundle {
  const RetrieveBundle({
    required this.query,
    required this.drugs,
    required this.guidelines,
    this.refused = false,
    this.refuseReason,
  });

  final String query;
  final List<RetrievedDrugHit> drugs;
  final List<RetrievedGuidelineHit> guidelines;
  final bool refused;
  final String? refuseReason;

  bool get isEmpty => drugs.isEmpty && guidelines.isEmpty;
}

/// Shared retrieve for Chat / future export — mirrors clinical_core_py.retrieve.
class ClinicalRetriever {
  ClinicalRetriever(this._repo);

  final ClinicalRepository _repo;

  Future<RetrieveBundle> retrieve(
    String query, {
    int drugLimit = 5,
    int guidelineLimit = 5,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return const RetrieveBundle(
        query: '',
        drugs: [],
        guidelines: [],
        refused: true,
        refuseReason: 'Empty query',
      );
    }

    final drugs = await _repo.searchDrugs(q, limit: drugLimit);
    final guides = await _repo.searchGuidelines(q, limit: guidelineLimit);

    final drugHits = drugs
        .map(
          (d) => RetrievedDrugHit(
            id: d.id,
            genericName: d.genericName,
            score: 0,
            excerpt: _excerpt(d.ragText.isNotEmpty ? d.ragText : d.adultDose ?? d.genericName),
          ),
        )
        .toList();
    final guideHits = guides
        .map(
          (g) => RetrievedGuidelineHit(
            id: g.id,
            title: g.title,
            source: g.source,
            topic: g.topic,
            score: g.priority.toDouble(),
            excerpt: _excerpt(g.chunkText),
          ),
        )
        .toList();

    if (drugHits.isEmpty && guideHits.isEmpty) {
      return RetrieveBundle(
        query: q,
        drugs: const [],
        guidelines: const [],
        refused: true,
        refuseReason:
            'No local drugs or guidelines matched — refuse to invent clinical content',
      );
    }

    return RetrieveBundle(query: q, drugs: drugHits, guidelines: guideHits);
  }

  String formatContext(RetrieveBundle bundle) {
    if (bundle.refused) {
      return '[RETRIEVAL REFUSED] ${bundle.refuseReason}';
    }
    final buf = StringBuffer('Query: ${bundle.query}\n\n### Drugs\n');
    for (final d in bundle.drugs) {
      buf.writeln('- [${d.id}] ${d.genericName}: ${d.excerpt}');
    }
    buf.writeln('\n### Guidelines');
    for (final g in bundle.guidelines) {
      buf.writeln('- [${g.id}] ${g.title} (${g.source}): ${g.excerpt}');
    }
    buf.writeln(
      '\nRules: Answer only from the snippets above. Cite ids. '
      'Do not invent drug-drug interaction severity.',
    );
    return buf.toString();
  }

  static String _excerpt(String text, [int max = 240]) {
    final t = text.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max - 1)}…';
  }
}
