import 'package:flutter_test/flutter_test.dart';

/// Chat vignette retrieval smoke runs in CI via [qa/run_chat_vignette_smoke.py].
/// Flutter unit tests lack path_provider/sqflite native bindings in this harness.
void main() {
  test('vignette smoke delegated to qa/run_chat_vignette_smoke.py', () {
    expect(true, isTrue);
  });
}
