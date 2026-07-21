import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:clinical_assistant/llm/gguf_runtime_io.dart';

/// Integration smoke for desktop GGUF placement (Linux Documents path).
/// Run: `flutter test test/gguf_model_resolve_test.dart`
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads preferred Qwen GGUF from ~/Documents/nepal_clinical/models', () async {
    if (!Platform.isLinux && !Platform.isWindows) {
      return;
    }

    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'];
    expect(home, isNotNull, reason: 'HOME/USERPROFILE required');
    final preferred = File(
      p.join(
        home!,
        'Documents',
        'nepal_clinical',
        'models',
        'qwen2.5-1.5b-instruct-q4_k_m.gguf',
      ),
    );
    expect(
      preferred.existsSync(),
      isTrue,
      reason: 'Expected GGUF at ${preferred.path}',
    );

    // Use a relative dir under a temp docs root by copying path layout:
    // IoGgufLlamaRuntime uses path_provider; call Llama load via resolve by
    // pointing relativeModelsDir at an absolute-style layout under HOME/Documents.
    final runtime = _DocsRootRuntime(
      docsRoot: Directory(p.join(home, 'Documents')),
      preferredFileNames: const [
        'qwen2.5-1.5b-instruct-q4_k_m.gguf',
        'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
        'qwen2.5-1.5b-instruct-q4_0.gguf',
      ],
      relativeModelsDir: 'nepal_clinical/models',
    );

    final resolved = await runtime.resolveModelPath();
    expect(resolved, isNotNull);
    expect(File(resolved!).existsSync(), isTrue);

    final loaded = await runtime.ensureLoaded();
    expect(loaded, isTrue, reason: runtime.lastError ?? 'load failed');
    expect(runtime.modelLabel!.toLowerCase(), contains('qwen'));
    await runtime.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// Test helper: same as [IoGgufLlamaRuntime] but skips path_provider.
class _DocsRootRuntime extends IoGgufLlamaRuntime {
  _DocsRootRuntime({
    required this.docsRoot,
    required super.preferredFileNames,
    required super.relativeModelsDir,
  });

  final Directory docsRoot;

  @override
  Future<Directory> modelsDirectory() async {
    return Directory(p.join(docsRoot.path, relativeModelsDir));
  }
}
