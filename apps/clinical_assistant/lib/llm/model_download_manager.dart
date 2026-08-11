export 'model_manifest.dart';

import 'model_manifest.dart';
import 'model_download_manager_stub.dart'
    if (dart.library.io) 'model_download_manager_io.dart' as impl;

/// Download / verify phases for the on-device GGUF.
enum ModelDownloadPhase {
  idle,
  downloading,
  verifying,
  complete,
  failed,
  cancelled,
}

class ModelDownloadProgress {
  const ModelDownloadProgress({
    required this.phase,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.error,
  });

  final ModelDownloadPhase phase;
  final int receivedBytes;
  final int totalBytes;
  final String? error;

  double? get fraction {
    if (totalBytes <= 0) return null;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }

  bool get isTerminal =>
      phase == ModelDownloadPhase.complete ||
      phase == ModelDownloadPhase.failed ||
      phase == ModelDownloadPhase.cancelled;
}

/// Connectivity hint before starting a ~1GB pull.
enum NetworkKind { wifi, mobile, other, none, unknown }

/// Resumable HTTPS GGUF downloader → app Documents `nepal_clinical/models/`.
abstract class ModelDownloadManager {
  ModelManifest get manifest;

  Stream<ModelDownloadProgress> get progress;

  ModelDownloadProgress get current;

  /// True when the product GGUF file exists with the expected byte size.
  /// Set [verifyHash] after a download; full SHA-256 of ~1GB is slow on-device.
  Future<bool> isModelReady({bool verifyHash = false});

  Future<String> modelsDirectoryPath();

  Future<NetworkKind> detectNetwork();

  /// Returns null when free space is unknown; otherwise available bytes.
  Future<int?> freeBytesAvailable();

  /// Ensures enough free space when measurable.
  Future<void> assertDiskSpace();

  /// Downloads (or resumes) until the file matches [manifest] size + SHA-256.
  /// Idempotent if already valid.
  Future<String> download({required bool allowMobileData});

  void cancel();

  Future<void> dispose();
}

/// Native IO manager on Linux/Android/Windows; stub on web.
ModelDownloadManager createModelDownloadManager({
  ModelManifest manifest = ModelManifest.product,
}) {
  return impl.createPlatformModelDownloadManager(manifest: manifest);
}
