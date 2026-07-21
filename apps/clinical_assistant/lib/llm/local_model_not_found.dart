/// Thrown when Chat requires an on-device GGUF and none is available.
class LocalModelNotFoundException implements Exception {
  LocalModelNotFoundException([String? message])
      : message = message ?? defaultMessage;

  static const defaultMessage =
      'No local model found. Place a Qwen2.5 Instruct GGUF at '
      'Documents/nepal_clinical/models/ (Linux/Windows/Android), then refresh. '
      'Chat does not use a rules-engine fallback. Flutter web has no neural '
      'Chat in this build.';

  final String message;

  @override
  String toString() => message;
}
