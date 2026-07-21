import 'package:clinical_assistant/llm/gguf_runtime.dart';
import 'package:clinical_assistant/llm/local_llm_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('groundedChatAnswer throws when GGUF missing — no rules fallback',
      () async {
    final client = LocalLlmClient(gguf: UnloadedGgufRuntime());
    expect(
      () => client.groundedChatAnswer(
        question: 'scrub typhus',
        retrievedContext: 'GUIDELINE np-guide-1: doxycycline',
      ),
      throwsA(isA<LocalModelNotFoundException>()),
    );
  });

  test('probe reports unreachable gguf without inventing in-app success',
      () async {
    final client = LocalLlmClient(
      gguf: UnloadedGgufRuntime(message: 'No local model found (test)'),
    );
    final status = await client.probe();
    expect(status.reachable, isFalse);
    expect(status.backend, LlmBackend.gguf);
    expect(status.shortLabel, 'No local model');
    expect(status.message, contains('No local model'));
  });

  test('draftNote still works via in-app when GGUF missing', () async {
    final client = LocalLlmClient(gguf: UnloadedGgufRuntime());
    final text = await client.draftNote(
      chiefComplaint: 'fever',
      history: '2 days',
      examination: 'temp 38',
      assessment: 'viral',
      plan: 'fluids',
    );
    expect(text.toLowerCase(), contains('fever'));
    expect(text.toLowerCase(), contains('draft'));
  });
}
