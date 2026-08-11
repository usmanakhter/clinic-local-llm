import 'dart:io';
import 'dart:math' as math;

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

/// On-device GGUF runtime (llama.cpp via llamadart) for Linux / Android / Windows.
///
/// Tuned for chat latency on mid-range devices (Surface / phones):
/// smaller context, greedy decode, capped output, Vulkan when available.
class IoGgufLlamaRuntime implements GgufLlamaRuntime {
  IoGgufLlamaRuntime({
    required this.preferredFileNames,
    required this.relativeModelsDir,
  });

  final List<String> preferredFileNames;
  final String relativeModelsDir;

  /// Enough for short grounded answers + compact retrieve context.
  static const int chatContextSize = 1024;

  LlamaEngine? _engine;
  String? _modelPath;
  String? _modelLabel;
  String? _lastError;
  Future<bool>? _loadInFlight;
  String _accelLabel = 'cpu';

  @override
  bool get isReady => _engine?.isReady == true;

  @override
  String? get modelPath => _modelPath;

  @override
  String? get modelLabel {
    final base = _modelLabel;
    if (base == null) return null;
    return '$base ($_accelLabel)';
  }

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

  int get _threadCount {
    final n = Platform.numberOfProcessors;
    // Leave one core for UI / compositor; keep at least 2.
    return math.max(2, math.min(n - 1, 8));
  }

  List<({String label, ModelParams params})> _loadAttempts() {
    final threads = _threadCount;
    // CPU-only by default. Vulkan/GPU offload can hard-crash flaky Surface /
    // Mesa stacks; re-enable behind an explicit opt-in later if needed.
    return [
      (
        label: 'cpu',
        params: ModelParams(
          contextSize: chatContextSize,
          gpuLayers: 0,
          preferredBackend: GpuBackend.cpu,
          numberOfThreads: threads,
          numberOfThreadsBatch: threads,
          batchSize: 512,
          microBatchSize: 512,
          useMmap: true,
        ),
      ),
    ];
  }

  Future<bool> _ensureLoadedBody() async {
    final path = await resolveModelPath();
    if (path == null) {
      final hint = await expectedModelsPathHint();
      _lastError =
          'No local model found. Open Chat and tap Download clinical model '
          '(~1.1 GB, Wi‑Fi recommended), or place Qwen2.5 Instruct Q4 GGUF at:\n'
          '$hint\n'
          'Expected filename e.g. qwen2.5-1.5b-instruct-q4_k_m.gguf. '
          'Chat will not fall back to rules or Ollama.';
      return false;
    }

    Object? lastLoadError;
    for (final attempt in _loadAttempts()) {
      LlamaEngine? engine;
      try {
        engine = LlamaEngine(LlamaBackend());
        await engine.loadModel(path, modelParams: attempt.params);
        _engine = engine;
        _modelPath = path;
        _modelLabel = p.basename(path);
        _accelLabel = attempt.label;
        _lastError = null;
        return true;
      } catch (e) {
        lastLoadError = e;
        try {
          await engine?.dispose();
        } catch (_) {}
      }
    }

    await dispose();
    final hint = await expectedModelsPathHint();
    _lastError =
        'Failed to load local GGUF (${p.basename(path)}): $lastLoadError\n'
        'Fix or replace the file under:\n$hint';
    return false;
  }

  @override
  Future<String> complete({
    required String system,
    required String user,
    int maxTokens = 192,
    double temperature = 0.1,
    void Function(String token)? onToken,
  }) async {
    final ok = await ensureLoaded();
    if (!ok || _engine == null) {
      throw LocalModelNotFoundException(_lastError);
    }

    // Greedy for grounded chat (temp≈0) — faster sampling, more deterministic.
    final greedy = temperature <= 0.05;
    final buf = StringBuffer();
    await for (final chunk in _engine!.create(
      [
        LlamaChatMessage.fromText(role: LlamaChatRole.system, text: system),
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: user),
      ],
      params: GenerationParams(
        maxTokens: maxTokens,
        temp: greedy ? 0.0 : temperature,
        topK: greedy ? 1 : 40,
        topP: greedy ? 1.0 : 0.9,
        penalty: 1.0,
        // Emit sooner so the UI can stream.
        streamBatchTokenThreshold: 1,
        streamBatchByteThreshold: 16,
        stopSequences: const [
          'Draft only — not for clinical use.',
          'Draft only - not for clinical use.',
          '\n\n\n',
        ],
        reusePromptPrefix: true,
      ),
      enableThinking: false,
    )) {
      final text = chunk.choices.isEmpty
          ? null
          : chunk.choices.first.delta.content;
      if (text != null && text.isNotEmpty) {
        buf.write(text);
        onToken?.call(text);
      }
    }

    var out = buf.toString().trim();
    // Stop sequences are often omitted from the stream — restore disclaimer.
    if (out.isNotEmpty &&
        !out.toLowerCase().contains('not for clinical use')) {
      out = '$out\n\nDraft only — not for clinical use.';
      onToken?.call('\n\nDraft only — not for clinical use.');
    }
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
    _accelLabel = 'cpu';
    if (engine != null) {
      try {
        await engine.dispose();
      } catch (_) {}
    }
  }
}
