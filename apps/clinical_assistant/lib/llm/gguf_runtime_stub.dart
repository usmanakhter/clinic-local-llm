import 'gguf_runtime.dart';

/// Web / non-IO stub used by [createNativeGgufRuntime].
GgufLlamaRuntime createPlatformGgufRuntime({
  List<String> preferredFileNames = const [],
  String relativeModelsDir = 'nepal_clinical/models',
}) {
  return _WebGgufRuntime(relativeModelsDir: relativeModelsDir);
}

class _WebGgufRuntime implements GgufLlamaRuntime {
  _WebGgufRuntime({required this.relativeModelsDir});

  final String relativeModelsDir;

  @override
  bool get isReady => false;

  @override
  String? get modelPath => null;

  @override
  String? get modelLabel => null;

  @override
  String? get lastError =>
      'No local model found. Neural Chat requires Windows or Android '
      'with a GGUF file — Flutter web is not supported in this build.';

  @override
  Future<String> expectedModelsPathHint() async =>
      'native Windows/Android Documents/$relativeModelsDir/';

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
