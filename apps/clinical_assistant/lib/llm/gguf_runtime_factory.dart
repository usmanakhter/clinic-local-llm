import 'gguf_runtime.dart';
import 'gguf_runtime_stub.dart'
    if (dart.library.io) 'gguf_runtime_io.dart' as platform;

/// Native llama.cpp GGUF runtime (Windows/Android). Web → stub.
GgufLlamaRuntime createNativeGgufRuntime({
  List<String> preferredFileNames = const [
    'qwen2.5-1.5b-instruct-q4_k_m.gguf',
    'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
    'qwen2.5-1.5b-instruct-q4_0.gguf',
  ],
  String relativeModelsDir = 'nepal_clinical/models',
}) {
  return platform.createPlatformGgufRuntime(
    preferredFileNames: preferredFileNames,
    relativeModelsDir: relativeModelsDir,
  );
}
