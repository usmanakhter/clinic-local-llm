import 'package:clinical_assistant/llm/in_app_draft_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = InAppDraftEngine();

  test('draftNote builds SOAP from fields without inventing severity', () {
    final text = engine.draftNote(
      chiefComplaint: 'Fever 3 days',
      history: 'Adult, hills travel',
      examination: 'Temp 38.2, eschar',
      assessment: 'Possible scrub typhus',
      plan: 'Doxycycline if not pregnant',
    );
    expect(text, contains('S — Subjective'));
    expect(text, contains('Fever 3 days'));
    expect(text, contains('Doxycycline if not pregnant'));
    expect(text, contains('Not for clinical use'));
    expect(text.toLowerCase(), isNot(contains('contraindicated')));
  });

  test('groundedChatAnswer cites retrieved drug and guide lines', () {
    final text = engine.groundedChatAnswer(
      question: 'scrub typhus',
      retrievedContext: '''
Query: scrub typhus

### Drugs
- [drug_056] Doxycycline: first-line for scrub typhus

### Guidelines
- [guide_019] Scrub Typhus: empiric doxycycline when suspected
''',
    );
    expect(text, contains('drug_056'));
    expect(text, contains('guide_019'));
    expect(text, contains('not for clinical use'));
  });

  test('groundedChatAnswer rejects empty context', () {
    expect(
      () => engine.groundedChatAnswer(question: 'x', retrievedContext: '  '),
      throwsStateError,
    );
  });
}
