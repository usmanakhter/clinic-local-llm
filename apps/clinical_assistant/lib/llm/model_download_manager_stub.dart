import 'model_download_manager.dart';

ModelDownloadManager createPlatformModelDownloadManager({
  ModelManifest manifest = ModelManifest.product,
}) {
  return StubModelDownloadManager(manifest: manifest);
}

/// Web / non-IO: neural model download is not available.
class StubModelDownloadManager implements ModelDownloadManager {
  StubModelDownloadManager({this.manifest = ModelManifest.product});

  @override
  final ModelManifest manifest;

  @override
  ModelDownloadProgress get current => const ModelDownloadProgress(
        phase: ModelDownloadPhase.idle,
      );

  @override
  Stream<ModelDownloadProgress> get progress => const Stream.empty();

  @override
  Future<bool> isModelReady({bool verifyHash = false}) async => false;

  @override
  Future<String> modelsDirectoryPath() async =>
      'Documents/${manifest.relativeModelsDir}/';

  @override
  Future<NetworkKind> detectNetwork() async => NetworkKind.unknown;

  @override
  Future<int?> freeBytesAvailable() async => null;

  @override
  Future<void> assertDiskSpace() async {}

  @override
  Future<String> download({required bool allowMobileData}) async {
    throw StateError(
      'Model download is not available on this platform. '
      'Use a native Android/Linux/Windows build for on-device Chat.',
    );
  }

  @override
  void cancel() {}

  @override
  Future<void> dispose() async {}
}
