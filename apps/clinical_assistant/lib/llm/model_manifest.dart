/// Product Chat GGUF identity — Qwen2.5-1.5B-Instruct Q4_K_M from Hugging Face.
///
/// Weights stay off the Play AAB; phones pull once into app Documents.
class ModelManifest {
  const ModelManifest({
    required this.fileName,
    required this.downloadUrl,
    required this.expectedBytes,
    required this.sha256Hex,
    this.relativeModelsDir = 'nepal_clinical/models',
    this.displayName = 'Qwen2.5-1.5B Instruct (Q4_K_M)',
  });

  final String fileName;
  final String downloadUrl;
  final int expectedBytes;
  final String sha256Hex;
  final String relativeModelsDir;
  final String displayName;

  /// ~1.1 GB on disk; ask for a little headroom before download.
  int get minFreeBytes => expectedBytes + (100 * 1024 * 1024);

  String get sizeLabel {
    final gb = expectedBytes / (1024 * 1024 * 1024);
    return '~${gb.toStringAsFixed(1)} GB';
  }

  /// Official Qwen GGUF (LFS oid matches local product file).
  static const product = ModelManifest(
    fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
    downloadUrl:
        'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
    expectedBytes: 1117320736,
    sha256Hex:
        '6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e',
  );
}
