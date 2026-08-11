import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'model_download_manager.dart';

ModelDownloadManager createPlatformModelDownloadManager({
  ModelManifest manifest = ModelManifest.product,
  HttpClient? httpClient,
  Directory? modelsDirectoryOverride,
  Future<NetworkKind> Function()? networkDetector,
  Future<int?> Function(String path)? freeBytesChecker,
}) {
  return IoModelDownloadManager(
    manifest: manifest,
    httpClient: httpClient,
    modelsDirectoryOverride: modelsDirectoryOverride,
    networkDetector: networkDetector,
    freeBytesChecker: freeBytesChecker,
  );
}

class IoModelDownloadManager implements ModelDownloadManager {
  IoModelDownloadManager({
    this.manifest = ModelManifest.product,
    HttpClient? httpClient,
    this.modelsDirectoryOverride,
    this.networkDetector,
    Future<int?> Function(String path)? freeBytesChecker,
  })  : _client = httpClient ?? HttpClient(),
        _freeBytesChecker = freeBytesChecker ?? _defaultFreeBytes,
        _ownsClient = httpClient == null;

  @override
  final ModelManifest manifest;

  final HttpClient _client;
  final bool _ownsClient;
  final Directory? modelsDirectoryOverride;
  final Future<NetworkKind> Function()? networkDetector;
  final Future<int?> Function(String path) _freeBytesChecker;

  final _progressController =
      StreamController<ModelDownloadProgress>.broadcast();
  ModelDownloadProgress _current = const ModelDownloadProgress(
    phase: ModelDownloadPhase.idle,
  );
  bool _cancelRequested = false;
  Future<String>? _inFlight;

  @override
  ModelDownloadProgress get current => _current;

  @override
  Stream<ModelDownloadProgress> get progress => _progressController.stream;

  void _emit(ModelDownloadProgress next) {
    _current = next;
    if (!_progressController.isClosed) {
      _progressController.add(next);
    }
  }

  Future<Directory> modelsDirectory() async {
    final override = modelsDirectoryOverride;
    if (override != null) {
      await override.create(recursive: true);
      return override;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, manifest.relativeModelsDir));
    await dir.create(recursive: true);
    return dir;
  }

  File finalFile(Directory dir) => File(p.join(dir.path, manifest.fileName));

  File partialFile(Directory dir) =>
      File(p.join(dir.path, '${manifest.fileName}.partial'));

  @override
  Future<String> modelsDirectoryPath() async {
    final dir = await modelsDirectory();
    return dir.path;
  }

  @override
  Future<bool> isModelReady({bool verifyHash = false}) async {
    final dir = await modelsDirectory();
    final file = finalFile(dir);
    if (!await file.exists()) return false;
    final len = await file.length();
    if (len != manifest.expectedBytes) return false;
    if (!verifyHash) return true;
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == manifest.sha256Hex;
  }

  @override
  Future<NetworkKind> detectNetwork() async {
    final custom = networkDetector;
    if (custom != null) return custom();
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.isEmpty || results.contains(ConnectivityResult.none)) {
        return NetworkKind.none;
      }
      if (results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet)) {
        return NetworkKind.wifi;
      }
      if (results.contains(ConnectivityResult.mobile)) {
        return NetworkKind.mobile;
      }
      return NetworkKind.other;
    } catch (_) {
      return NetworkKind.unknown;
    }
  }

  @override
  Future<int?> freeBytesAvailable() async {
    final dir = await modelsDirectory();
    return _freeBytesChecker(dir.path);
  }

  @override
  Future<void> assertDiskSpace() async {
    final free = await freeBytesAvailable();
    if (free == null) return;
    if (free < manifest.minFreeBytes) {
      final needGb = manifest.minFreeBytes / (1024 * 1024 * 1024);
      final freeGb = free / (1024 * 1024 * 1024);
      throw StateError(
        'Not enough free storage for the clinical model '
        '(need ~${needGb.toStringAsFixed(1)} GB, have ${freeGb.toStringAsFixed(1)} GB).',
      );
    }
  }

  @override
  Future<String> download({required bool allowMobileData}) {
    return _inFlight ??= _downloadBody(allowMobileData: allowMobileData)
        .whenComplete(() {
      _inFlight = null;
    });
  }

  Future<String> _downloadBody({required bool allowMobileData}) async {
    _cancelRequested = false;

    final dir = await modelsDirectory();
    final dest = finalFile(dir);
    if (await isModelReady(verifyHash: true)) {
      _emit(ModelDownloadProgress(
        phase: ModelDownloadPhase.complete,
        receivedBytes: manifest.expectedBytes,
        totalBytes: manifest.expectedBytes,
      ));
      return dest.path;
    }

    final net = await detectNetwork();
    if (net == NetworkKind.none) {
      throw StateError('No network connection. Connect to Wi‑Fi and try again.');
    }
    if (net == NetworkKind.mobile && !allowMobileData) {
      throw StateError(
        'Mobile data detected. Confirm “use mobile data” to download '
        '${manifest.sizeLabel}, or switch to Wi‑Fi.',
      );
    }

    await assertDiskSpace();

    final partial = partialFile(dir);
    var existing = 0;
    if (await partial.exists()) {
      existing = await partial.length();
      if (existing > manifest.expectedBytes) {
        await partial.delete();
        existing = 0;
      }
    }
    // Stale final with wrong size/hash — remove before writing.
    if (await dest.exists()) {
      await dest.delete();
    }

    _emit(ModelDownloadProgress(
      phase: ModelDownloadPhase.downloading,
      receivedBytes: existing,
      totalBytes: manifest.expectedBytes,
    ));

    final uri = Uri.parse(manifest.downloadUrl);
    final request = await _client.getUrl(uri);
    request.followRedirects = true;
    request.maxRedirects = 8;
    request.headers.set(HttpHeaders.userAgentHeader, 'nepal-clinical-assistant');
    if (existing > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
    }

    final response = await request.close();
    final code = response.statusCode;
    if (code != 200 && code != 206) {
      final body = await response.transform(utf8.decoder).join();
      throw StateError(
        'Model download failed (HTTP $code). ${body.length > 200 ? body.substring(0, 200) : body}',
      );
    }

    if (code == 200 && existing > 0) {
      // Server ignored Range — restart from scratch.
      await partial.writeAsBytes(const [], flush: true);
      existing = 0;
    }

    final sink = partial.openWrite(mode: FileMode.append);
    var received = existing;
    try {
      await for (final chunk in response) {
        if (_cancelRequested) {
          await sink.close();
          _emit(ModelDownloadProgress(
            phase: ModelDownloadPhase.cancelled,
            receivedBytes: received,
            totalBytes: manifest.expectedBytes,
            error: 'Download cancelled',
          ));
          throw StateError('Download cancelled');
        }
        sink.add(chunk);
        received += chunk.length;
        _emit(ModelDownloadProgress(
          phase: ModelDownloadPhase.downloading,
          receivedBytes: received,
          totalBytes: manifest.expectedBytes,
        ));
      }
      await sink.flush();
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      if (e is StateError && e.message == 'Download cancelled') rethrow;
      _emit(ModelDownloadProgress(
        phase: ModelDownloadPhase.failed,
        receivedBytes: received,
        totalBytes: manifest.expectedBytes,
        error: e.toString(),
      ));
      rethrow;
    }
    await sink.close();

    if (received != manifest.expectedBytes) {
      final msg =
          'Download incomplete ($received / ${manifest.expectedBytes} bytes). '
          'Resume by tapping Download again.';
      _emit(ModelDownloadProgress(
        phase: ModelDownloadPhase.failed,
        receivedBytes: received,
        totalBytes: manifest.expectedBytes,
        error: msg,
      ));
      throw StateError(msg);
    }

    _emit(ModelDownloadProgress(
      phase: ModelDownloadPhase.verifying,
      receivedBytes: received,
      totalBytes: manifest.expectedBytes,
    ));

    final digest = await sha256.bind(partial.openRead()).first;
    if (digest.toString() != manifest.sha256Hex) {
      await partial.delete();
      const msg =
          'Model checksum mismatch after download. File deleted; try again.';
      _emit(const ModelDownloadProgress(
        phase: ModelDownloadPhase.failed,
        error: msg,
      ));
      throw StateError(msg);
    }

    await partial.rename(dest.path);

    _emit(ModelDownloadProgress(
      phase: ModelDownloadPhase.complete,
      receivedBytes: manifest.expectedBytes,
      totalBytes: manifest.expectedBytes,
    ));
    return dest.path;
  }

  @override
  void cancel() {
    _cancelRequested = true;
  }

  @override
  Future<void> dispose() async {
    cancel();
    await _progressController.close();
    if (_ownsClient) {
      _client.close(force: true);
    }
  }
}

Future<int?> _defaultFreeBytes(String path) async {
  try {
    final result = await Process.run('df', ['-Pk', path]);
    if (result.exitCode != 0) return null;
    final lines = (result.stdout as String).trim().split('\n');
    if (lines.length < 2) return null;
    final parts = lines.last.trim().split(RegExp(r'\s+'));
    if (parts.length < 4) return null;
    final availKb = int.tryParse(parts[3]);
    if (availKb == null) return null;
    return availKb * 1024;
  } catch (_) {
    return null;
  }
}
