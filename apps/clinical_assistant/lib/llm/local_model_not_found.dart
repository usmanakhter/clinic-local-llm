/// Thrown when Chat requires an on-device GGUF and none is available.
class LocalModelNotFoundException implements Exception {
  LocalModelNotFoundException([String? message])
      : message = message ?? defaultMessage;

  static const defaultMessage =
      'No local model found. On Android/Linux/Windows open Chat and tap '
      '“Download clinical model” (~1.1 GB from Hugging Face, Wi‑Fi '
      'recommended), or place a Qwen2.5 Instruct GGUF at '
      'Documents/nepal_clinical/models/. Chat does not use a rules-engine '
      'fallback. Flutter web has no neural Chat in this build.';

  final String message;

  @override
  String toString() => message;
}
