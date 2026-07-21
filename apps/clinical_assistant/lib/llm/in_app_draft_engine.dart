/// In-app local assistant — no Ollama / network required.
///
/// Assembles answers from multi-source local context (notes, history, chats,
/// drugs, guidelines). Not a neural LLM. Never invents interaction severity.
class InAppDraftEngine {
  const InAppDraftEngine();

  static const modelId = 'in-app-draft-v1';

  String draftNote({
    required String chiefComplaint,
    required String history,
    required String examination,
    required String assessment,
    required String plan,
  }) {
    final cc = _nz(chiefComplaint, 'Not provided');
    final hx = _nz(history, 'Not provided');
    final exam = _nz(examination, 'Not provided');
    final assess = _nz(assessment, 'Not provided');
    final pl = _nz(plan, 'Not provided');

    return '''
SOAP draft (in-app engine — $modelId)

S — Subjective
Chief complaint: $cc
History: $hx

O — Objective
Examination: $exam

A — Assessment
$assess
(Impression only as provided by clinician; not a diagnosis by this tool.)

P — Plan
$pl

Notes:
- Do not invent lab values or findings beyond the fields above.
- Drug–drug interaction severity is never assigned by this engine (DB only).

Draft only — clinician must review. Not for clinical use.
'''
        .trim();
  }

  /// Synthesize a chat answer from unified local retrieval context.
  String groundedChatAnswer({
    required String question,
    required String retrievedContext,
  }) {
    final ctx = retrievedContext.trim();
    if (ctx.isEmpty) {
      throw StateError('groundedChatAnswer requires non-empty retrieved context');
    }
    if (ctx.startsWith('[RETRIEVAL REFUSED]')) {
      return '${ctx.replaceFirst('[RETRIEVAL REFUSED] ', '')}\n\n'
          'Draft assist only — not for clinical use.';
    }

    final notes = _sectionItems(ctx, '### Local notes');
    final chats = _sectionItems(ctx, '### Past chats');
    final history = _sectionItems(ctx, '### Other local history');
    final drugs = _sectionItems(ctx, '### Drugs');
    final guides = _sectionItems(ctx, '### Guidelines');

    final buf = StringBuffer();
    buf.writeln('Local assistant ($modelId)');
    buf.writeln();
    buf.writeln('Question: ${_nz(question, "(empty)")}');
    buf.writeln();

    final filterLine = RegExp(r'^Patient filter:\s*(.+)$', multiLine: true)
        .firstMatch(ctx);
    if (filterLine != null) {
      buf.writeln('Scoped to patient: ${filterLine.group(1)}');
      buf.writeln();
    }

    var wrote = false;

    if (notes.isNotEmpty) {
      buf.writeln('From your local notes');
      for (final n in notes.take(5)) {
        buf.writeln('• $n');
      }
      buf.writeln();
      wrote = true;
    }
    if (chats.isNotEmpty) {
      buf.writeln('From past chats on this device');
      for (final c in chats.take(4)) {
        buf.writeln('• $c');
      }
      buf.writeln();
      wrote = true;
    }
    if (history.isNotEmpty) {
      buf.writeln('From other local activity');
      for (final h in history.take(4)) {
        buf.writeln('• $h');
      }
      buf.writeln();
      wrote = true;
    }
    if (drugs.isNotEmpty) {
      buf.writeln('Matching drugs (local formulary)');
      for (final d in drugs.take(4)) {
        buf.writeln('• $d');
      }
      buf.writeln();
      wrote = true;
    }
    if (guides.isNotEmpty) {
      buf.writeln('Matching guidelines');
      for (final g in guides.take(4)) {
        buf.writeln('• $g');
      }
      buf.writeln();
      wrote = true;
    }

    if (!wrote) {
      buf.writeln(ctx);
      buf.writeln();
    }

    buf.writeln(
      'I only used on-device notes/history/chats and local drug/guideline '
      'fixtures. Interaction severity is never invented.',
    );
    buf.writeln();
    buf.write('Draft assist only — not for clinical use.');
    return buf.toString();
  }

  /// Pull bullet lines under a markdown ### section until the next ### or Rules.
  static List<String> _sectionItems(String ctx, String header) {
    final start = ctx.indexOf(header);
    if (start < 0) return const [];
    final after = ctx.substring(start + header.length);
    final next = RegExp(r'\n### |\nRules:', multiLine: true).firstMatch(after);
    final body = next == null ? after : after.substring(0, next.start);
    final items = <String>[];
    final buf = StringBuffer();
    for (final raw in body.split('\n')) {
      final line = raw.trimRight();
      final t = line.trimLeft();
      if (t.startsWith('- [')) {
        if (buf.isNotEmpty) {
          items.add(buf.toString().trim());
          buf.clear();
        }
        buf.write(t.substring(2).trim()); // drop "- "
      } else if (buf.isNotEmpty && t.isNotEmpty && !t.startsWith('#')) {
        buf.write(' | $t');
      }
    }
    if (buf.isNotEmpty) items.add(buf.toString().trim());
    return items;
  }

  static String _nz(String s, String fallback) {
    final t = s.trim();
    return t.isEmpty ? fallback : t;
  }
}
