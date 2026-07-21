import 'local_model_not_found.dart';

export 'local_model_not_found.dart';

/// On-device GGUF runtime contract.
abstract class GgufLlamaRuntime {
  bool get isReady;
  String? get modelPath;
  String? get modelLabel;
  String? get lastError;

  Future<String> expectedModelsPathHint();
  Future<String?> resolveModelPath();
  Future<bool> ensureLoaded();
  Future<String> complete({
    required String system,
    required String user,
    int maxTokens = 512,
    double temperature = 0.1,
  });
  Future<void> dispose();
}

/// Always-unloaded runtime (no native deps). Used as LocalLlmClient default
/// and for tests. Product UI wires [createNativeGgufRuntime] instead.
class UnloadedGgufRuntime implements GgufLlamaRuntime {
  UnloadedGgufRuntime({
    this.relativeModelsDir = 'nepal_clinical/models',
    String? message,
  }) : lastError = message ?? LocalModelNotFoundException.defaultMessage;

  final String relativeModelsDir;

  @override
  bool get isReady => false;

  @override
  String? get modelPath => null;

  @override
  String? get modelLabel => null;

  @override
  final String? lastError;

  @override
  Future<String> expectedModelsPathHint() async =>
      'Documents/$relativeModelsDir/';

  @override
  Future<String?> resolveModelPath() async => null;

  @override
  Future<bool> ensureLoaded() async => false;

  @override
  Future<String> complete({
    required String system,
    required String user,
    int maxTokens = 512,
    double temperature = 0.1,
  }) async {
    throw LocalModelNotFoundException(lastError);
  }

  @override
  Future<void> dispose() async {}
}
