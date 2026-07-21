import '../models/models.dart';
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

/// Local activity hit: note drafts, past chats, other session history.
class RetrievedSessionHit {
  const RetrievedSessionHit({
    required this.sessionId,
    required this.createdAt,
    required this.queryType,
    required this.title,
    this.patientId,
    this.patientName,
    this.excerpt,
    this.score = 0,
  });

  final String sessionId;
  final DateTime createdAt;
  final String queryType; // note_draft | chat | …
  final String title;
  final String? patientId;
  final String? patientName;
  final String? excerpt;
  final double score;

  bool get isNote => queryType == 'note_draft';
  bool get isChat => queryType == 'chat';
}

/// Multi-source retrieve for Chat: drugs + guidelines + notes + history + past chats.
class RetrieveBundle {
  const RetrieveBundle({
    required this.query,
    required this.drugs,
    required this.guidelines,
    this.sessions = const [],
    this.refused = false,
    this.refuseReason,
    this.patientFilterLabel,
  });

  final String query;
  final List<RetrievedDrugHit> drugs;
  final List<RetrievedGuidelineHit> guidelines;
  final List<RetrievedSessionHit> sessions;
  final bool refused;
  final String? refuseReason;
  final String? patientFilterLabel;

  List<RetrievedSessionHit> get notes =>
      sessions.where((s) => s.isNote).toList();
  List<RetrievedSessionHit> get pastChats =>
      sessions.where((s) => s.isChat).toList();
  List<RetrievedSessionHit> get otherHistory =>
      sessions.where((s) => !s.isNote && !s.isChat).toList();

  bool get isEmpty =>
      drugs.isEmpty && guidelines.isEmpty && sessions.isEmpty;
}

class ClinicalRetriever {
  ClinicalRetriever(this._repo);

  final ClinicalRepository _repo;

  static const _intentStop = {
    'a', 'an', 'the', 'and', 'or', 'of', 'for', 'to', 'in', 'on', 'with',
    'my', 'me', 'i', 'about', 'them', 'tell', 'please', 'what', 'did',
    'is', 'are', 'be', 'do', 'does', 'can', 'you', 'we', 'past', 'review',
    'note', 'notes', 'draft', 'drafts', 'chat', 'chats', 'history',
    'patient', 'patients', 'show', 'list', 'all', 'their', 'her', 'his',
    'from', 'this', 'that', 'those', 'these', 'local', 'saved', 'previous',
    'earlier', 'conversation', 'summarize', 'summarise', 'see', 'look',
  };

  /// Searches local sources with **strict patient filtering** when a name/id is given.
  Future<RetrieveBundle> retrieve(
    String query, {
    int drugLimit = 5,
    int guidelineLimit = 5,
    int sessionLimit = 10,
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

    final patients = await _repo.listPatients();
    final patientMatch = _resolvePatients(q, patients);
    final notesIntent = _isNotesOrHistoryIntent(q);
    final contentTokens = _contentTokens(q);
    final patientNameTokens = _patientNameTokens(patients, patientMatch.ids);
    final clinicalTokens = contentTokens
        .where((t) => !patientNameTokens.contains(t))
        .toList();

    // Notes/history review without an explicit clinical topic → no formulary.
    // (Stops "review notes with Karen" from dumping random drugs/guidelines.)
    final skipFormulary = notesIntent && clinicalTokens.isEmpty;

    List<RetrievedDrugHit> drugHits = const [];
    List<RetrievedGuidelineHit> guideHits = const [];

    if (!skipFormulary) {
      // Search formulary with clinical tokens only — not the full chat sentence.
      final formularyQuery =
          clinicalTokens.isNotEmpty ? clinicalTokens.join(' ') : q;
      final drugs = await _repo.searchDrugs(formularyQuery, limit: drugLimit);
      final guides =
          await _repo.searchGuidelines(formularyQuery, limit: guidelineLimit);
      drugHits = drugs
          .map(
            (d) => RetrievedDrugHit(
              id: d.id,
              genericName: d.genericName,
              score: 1,
              excerpt: _excerpt(
                d.ragText.isNotEmpty ? d.ragText : d.adultDose ?? d.genericName,
              ),
            ),
          )
          .where((d) => _strongFormularyHit(d.genericName, d.excerpt, clinicalTokens))
          .toList();
      guideHits = guides
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
          .where((g) => _strongFormularyHit(
                '${g.title} ${g.topic ?? ''} ${g.excerpt}',
                g.excerpt,
                clinicalTokens,
              ))
          .toList();
    }

    final allSessions = await _repo.listSessions(limit: 250);
    final sessionHits = _matchSessions(
      query: q,
      sessions: allSessions,
      patientsById: {for (final p in patients) p.id: p},
      patientIds: patientMatch.ids,
      notesIntent: notesIntent,
      contentTokens: contentTokens,
      limit: sessionLimit,
    );

    if (drugHits.isEmpty && guideHits.isEmpty && sessionHits.isEmpty) {
      final who = patientMatch.label;
      return RetrieveBundle(
        query: q,
        drugs: const [],
        guidelines: const [],
        refused: true,
        patientFilterLabel: who,
        refuseReason: who != null
            ? 'No local notes (or linked history) found for patient “$who”. '
                'Link the note to that patient on the Notes tab, then ask again.'
            : 'Nothing matched in local notes, history, chats, drugs, or guidelines. '
                'Try a patient name, drug name, or guideline topic.',
      );
    }

    return RetrieveBundle(
      query: q,
      drugs: drugHits,
      guidelines: guideHits,
      sessions: sessionHits,
      patientFilterLabel: patientMatch.label,
    );
  }

  ({Set<String> ids, String? label}) _resolvePatients(
    String query,
    List<Patient> patients,
  ) {
    final q = query.toLowerCase();
    final ids = <String>{};
    final labels = <String>{};

    for (final p in patients) {
      final name = p.displayName.trim();
      if (name.isEmpty) continue;
      final nameLower = name.toLowerCase();
      // Full name or any name token length >= 3 (e.g. "Karen")
      final nameParts = nameLower
          .split(RegExp(r'\s+'))
          .where((t) => t.length >= 3)
          .toList();
      final hit = q.contains(nameLower) ||
          nameParts.any((part) => RegExp('\\b${RegExp.escape(part)}\\b')
              .hasMatch(q)) ||
          q.contains(p.id.toLowerCase());
      if (hit) {
        ids.add(p.id);
        labels.add(name);
      }
    }
    return (
      ids: ids,
      label: labels.isEmpty ? null : labels.join(' / '),
    );
  }

  static Set<String> _patientNameTokens(
    List<Patient> patients,
    Set<String> matchedIds,
  ) {
    if (matchedIds.isEmpty) return {};
    final out = <String>{};
    for (final p in patients) {
      if (!matchedIds.contains(p.id)) continue;
      for (final part in p.displayName.toLowerCase().split(RegExp(r'\s+'))) {
        if (part.length >= 3) out.add(part);
      }
      out.add(p.id.toLowerCase());
    }
    return out;
  }

  /// Require at least one clinical token to appear in the hit text.
  static bool _strongFormularyHit(
    String title,
    String excerpt,
    List<String> clinicalTokens,
  ) {
    if (clinicalTokens.isEmpty) return false;
    final hay = '$title $excerpt'.toLowerCase();
    return clinicalTokens.any((t) => hay.contains(t));
  }

  static bool _isNotesOrHistoryIntent(String query) {
    final q = query.toLowerCase();
    const cues = [
      'note',
      'notes',
      'draft',
      'past note',
      'past notes',
      'review',
      'history',
      'patient',
      'tell me about',
      'summarize',
      'summarise',
    ];
    return cues.any(q.contains);
  }

  List<RetrievedSessionHit> _matchSessions({
    required String query,
    required List<ClinicalSession> sessions,
    required Map<String, Patient> patientsById,
    required Set<String> patientIds,
    required bool notesIntent,
    required List<String> contentTokens,
    required int limit,
  }) {
    final q = query.toLowerCase();
    final wantsChats = q.contains('chat') ||
        q.contains('conversation') ||
        q.contains('we discussed');
    // Default notes review → notes only unless user also asks for chats
    final notesOnly = notesIntent && !wantsChats;
    final hasPatientFilter = patientIds.isNotEmpty;
    final hasContentFilter = contentTokens.isNotEmpty;

    final scored = <RetrievedSessionHit>[];
    for (final s in sessions) {
      if (notesOnly && s.queryType != 'note_draft') continue;
      if (s.queryType == 'chat' && s.outputSummary == 'refused') continue;

      final pid = s.patientId ?? (s.payload?['patient_id'] as String?);
      if (hasPatientFilter) {
        if (pid == null || !patientIds.contains(pid)) continue;
      }

      final p = s.payload ?? {};
      final patient = pid == null ? null : patientsById[pid];
      final patientName = patient?.displayName;
      final cc = (p['chief_complaint'] as String?) ?? s.inputSummary ?? '';
      final draft = (p['draft_text'] as String?) ??
          (p['draft_preview'] as String?) ??
          '';
      final assess = (p['assessment'] as String?) ?? '';
      final plan = (p['plan'] as String?) ?? '';
      final out = s.outputSummary ?? '';

      final hay = [
        cc,
        draft,
        assess,
        plan,
        out,
        pid ?? '',
        patientName ?? '',
        (p['history'] as String?) ?? '',
        (p['examination'] as String?) ?? '',
      ].join(' ').toLowerCase();

      var score = 0.0;
      for (final t in contentTokens) {
        if (hay.contains(t)) score += 2;
      }

      // Patient-filtered notes: include all linked notes for that patient
      if (hasPatientFilter && s.queryType == 'note_draft') {
        score += 3;
      } else if (hasPatientFilter && s.queryType == 'chat' && wantsChats) {
        score += 2;
      } else if (!hasPatientFilter && !hasContentFilter && notesIntent) {
        // Open-ended "my notes" with no name/topic → recent notes only
        if (s.queryType == 'note_draft') score += 1;
      } else if (!hasPatientFilter && hasContentFilter && score <= 0) {
        continue; // topic filter missed
      }

      if (score <= 0) continue;

      final title = s.queryType == 'note_draft'
          ? (cc.isEmpty ? 'Note draft' : cc)
          : (s.inputSummary?.isNotEmpty == true
              ? s.inputSummary!
              : s.typeLabel);

      final excerpt = draft.isNotEmpty
          ? draft
          : [
              if (assess.isNotEmpty) 'Assessment: $assess',
              if (plan.isNotEmpty) 'Plan: $plan',
              if (out.isNotEmpty) out,
              if (cc.isNotEmpty) cc,
            ].join(' · ');

      scored.add(
        RetrievedSessionHit(
          sessionId: s.id,
          createdAt: s.createdAt,
          queryType: s.queryType,
          title: title,
          patientId: pid,
          patientName: patientName,
          excerpt: _excerpt(excerpt, 360),
          score: score,
        ),
      );
    }

    scored.sort((a, b) {
      final c = b.score.compareTo(a.score);
      if (c != 0) return c;
      return b.createdAt.compareTo(a.createdAt);
    });
    return scored.take(limit).toList();
  }

  static List<String> _contentTokens(String query) {
    return RegExp(r'[\w\u0900-\u097F]+', unicode: true)
        .allMatches(query.toLowerCase())
        .map((m) => m.group(0)!)
        .where((t) => t.length >= 3 && !_intentStop.contains(t))
        .toList();
  }

  String formatContext(RetrieveBundle bundle) {
    if (bundle.refused) {
      return '[RETRIEVAL REFUSED] ${bundle.refuseReason}';
    }
    final buf = StringBuffer('Query: ${bundle.query}\n');
    if (bundle.patientFilterLabel != null) {
      buf.writeln('Patient filter: ${bundle.patientFilterLabel}');
    }

    final notes = bundle.notes;
    final chats = bundle.pastChats;
    final other = bundle.otherHistory;

    if (notes.isNotEmpty) {
      buf.writeln('\n### Local notes');
      for (final n in notes) {
        final who = n.patientName ?? n.patientId ?? 'none';
        buf.writeln(
          '- [${n.sessionId}] ${n.createdAt.toIso8601String()} '
          'patient=$who · ${n.title}',
        );
        if (n.excerpt != null && n.excerpt!.isNotEmpty) {
          buf.writeln('  ${n.excerpt}');
        }
      }
    }
    if (chats.isNotEmpty) {
      buf.writeln('\n### Past chats');
      for (final c in chats) {
        buf.writeln(
          '- [${c.sessionId}] ${c.createdAt.toIso8601String()} · ${c.title}',
        );
        if (c.excerpt != null && c.excerpt!.isNotEmpty) {
          buf.writeln('  ${c.excerpt}');
        }
      }
    }
    if (other.isNotEmpty) {
      buf.writeln('\n### Other local history');
      for (final h in other) {
        buf.writeln(
          '- [${h.sessionId}] ${h.queryType} · ${h.title}',
        );
        if (h.excerpt != null && h.excerpt!.isNotEmpty) {
          buf.writeln('  ${h.excerpt}');
        }
      }
    }
    if (bundle.drugs.isNotEmpty) {
      buf.writeln('\n### Drugs');
      for (final d in bundle.drugs) {
        buf.writeln('- [${d.id}] ${d.genericName}: ${d.excerpt}');
      }
    }
    if (bundle.guidelines.isNotEmpty) {
      buf.writeln('\n### Guidelines');
      for (final g in bundle.guidelines) {
        buf.writeln('- [${g.id}] ${g.title} (${g.source}): ${g.excerpt}');
      }
    }
    buf.writeln(
      '\nRules: Answer using ONLY the sections above. If a patient filter is '
      'set, do not mention other patients. Cite ids. '
      'Never invent drug-drug interaction severity.',
    );
    return buf.toString();
  }

  static String _excerpt(String text, [int max = 240]) {
    final t = text.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max - 1)}…';
  }
}
