import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'gguf_runtime.dart';

/// Creates the native llama.cpp-backed runtime.
GgufLlamaRuntime createPlatformGgufRuntime({
  List<String> preferredFileNames = const [
    'qwen2.5-1.5b-instruct-q4_k_m.gguf',
    'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
    'qwen2.5-1.5b-instruct-q4_0.gguf',
  ],
  String relativeModelsDir = 'nepal_clinical/models',
}) {
  return IoGgufLlamaRuntime(
    preferredFileNames: preferredFileNames,
    relativeModelsDir: relativeModelsDir,
  );
}

/// On-device GGUF runtime (llama.cpp via llamadart) for Android / Windows.
class IoGgufLlamaRuntime implements GgufLlamaRuntime {
  IoGgufLlamaRuntime({
    required this.preferredFileNames,
    required this.relativeModelsDir,
  });

  final List<String> preferredFileNames;
  final String relativeModelsDir;

  LlamaEngine? _engine;
  String? _modelPath;
  String? _modelLabel;
  String? _lastError;
  Future<bool>? _loadInFlight;

  @override
  bool get isReady => _engine?.isReady == true;

  @override
  String? get modelPath => _modelPath;

  @override
  String? get modelLabel => _modelLabel;

  @override
  String? get lastError => _lastError;

  Future<Directory> modelsDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, relativeModelsDir));
  }

  @override
  Future<String> expectedModelsPathHint() async {
    final dir = await modelsDirectory();
    return dir.path;
  }

  @override
  Future<String?> resolveModelPath() async {
    final dir = await modelsDirectory();
    if (await dir.exists()) {
      for (final name in preferredFileNames) {
        final file = File(p.join(dir.path, name));
        if (await file.exists()) return file.path;
      }
      final ggufs = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.gguf'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      if (ggufs.isNotEmpty) return ggufs.first.path;
    }

    for (final name in preferredFileNames) {
      try {
        final data = await rootBundle.load('assets/models/$name');
        await dir.create(recursive: true);
        final dest = File(p.join(dir.path, name));
        await dest.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
        return dest.path;
      } catch (_) {}
    }
    return null;
  }

  @override
  Future<bool> ensureLoaded() {
    if (isReady) return Future.value(true);
    return _loadInFlight ??= _ensureLoadedBody().whenComplete(() {
      _loadInFlight = null;
    });
  }

  Future<bool> _ensureLoadedBody() async {
    final path = await resolveModelPath();
    if (path == null) {
      final hint = await expectedModelsPathHint();
      _lastError =
          'No local model found. Place Qwen2.5 Instruct Q4 GGUF at:\n$hint\n'
          'Expected filename e.g. qwen2.5-1.5b-instruct-q4_k_m.gguf. '
          'Chat will not fall back to rules or Ollama.';
      return false;
    }

    try {
      final engine = LlamaEngine(LlamaBackend());
      await engine.loadModel(
        path,
        modelParams: const ModelParams(
          contextSize: 2048,
          gpuLayers: 0,
        ),
      );
      _engine = engine;
      _modelPath = path;
      _modelLabel = p.basename(path);
      _lastError = null;
      return true;
    } catch (e) {
      await dispose();
      final hint = await expectedModelsPathHint();
      _lastError =
          'Failed to load local GGUF (${p.basename(path)}): $e\n'
          'Fix or replace the file under:\n$hint';
      return false;
    }
  }

  @override
  Future<String> complete({
    required String system,
    required String user,
    int maxTokens = 512,
    double temperature = 0.1,
  }) async {
    final ok = await ensureLoaded();
    if (!ok || _engine == null) {
      throw LocalModelNotFoundException(_lastError);
    }

    final buf = StringBuffer();
    await for (final chunk in _engine!.create(
      [
        LlamaChatMessage.fromText(role: LlamaChatRole.system, text: system),
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: user),
      ],
      params: GenerationParams(
        maxTokens: maxTokens,
        temp: temperature,
      ),
      enableThinking: false,
    )) {
      final text = chunk.choices.isEmpty
          ? null
          : chunk.choices.first.delta.content;
      if (text != null) buf.write(text);
    }

    final out = buf.toString().trim();
    if (out.isEmpty) {
      throw StateError('Local GGUF returned empty content');
    }
    return out;
  }

  @override
  Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    _modelPath = null;
    _modelLabel = null;
    if (engine != null) {
      try {
        await engine.dispose();
      } catch (_) {}
    }
  }
}
