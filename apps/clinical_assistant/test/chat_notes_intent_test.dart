import 'package:clinical_assistant/llm/in_app_draft_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = InAppDraftEngine();

  test('answer respects patient filter and does not invent other patients', () {
    final text = engine.groundedChatAnswer(
      question: 'review past notes with Karen',
      retrievedContext: '''
Query: review past notes with Karen
Patient filter: Karen

### Local notes
- [sess_1] 2026-07-20T12:00:00.000 patient=Karen · Fever 3 days
  Assessment: Possible viral illness

Rules: If a patient filter is set, do not mention other patients.
''',
    );
    expect(text, contains('Scoped to patient: Karen'));
    expect(text, contains('Fever 3 days'));
    expect(text, isNot(contains('Matching drugs')));
  });
}
