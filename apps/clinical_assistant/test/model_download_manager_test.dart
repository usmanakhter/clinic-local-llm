import 'dart:io';

import 'package:clinical_assistant/llm/local_model_not_found.dart';
import 'package:clinical_assistant/llm/model_download_manager.dart';
import 'package:clinical_assistant/llm/model_download_manager_io.dart';
import 'package:clinical_assistant/llm/model_manifest.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late List<int> payload;
  late String sha;
  late HttpServer server;
  late Uri baseUri;

  setUpAll(() async {
    payload = List<int>.generate(64 * 1024, (i) => i % 256);
    sha = sha256.convert(payload).toString();
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('gguf_dl_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUri = Uri.parse('http://127.0.0.1:${server.port}/model.gguf');
    server.listen((request) async {
      final path = request.uri.path;
      if (path != '/model.gguf') {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null && range.startsWith('bytes=')) {
        final spec = range.substring('bytes='.length);
        final start = int.parse(spec.split('-').first);
        final slice = payload.sublist(start);
        request.response.statusCode = 206;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-${payload.length - 1}/${payload.length}',
        );
        request.response.contentLength = slice.length;
        request.response.add(slice);
      } else {
        request.response.statusCode = 200;
        request.response.contentLength = payload.length;
        request.response.add(payload);
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  ModelManifest testManifest() => ModelManifest(
        fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
        downloadUrl: baseUri.toString(),
        expectedBytes: payload.length,
        sha256Hex: sha,
        relativeModelsDir: 'nepal_clinical/models',
      );

  IoModelDownloadManager manager() => IoModelDownloadManager(
        manifest: testManifest(),
        modelsDirectoryOverride: Directory(p.join(tmp.path, 'models')),
        networkDetector: () async => NetworkKind.wifi,
        freeBytesChecker: (_) async => 10 * 1024 * 1024 * 1024,
      );

  test('download writes final file and verifies checksum', () async {
    final m = manager();
    final path = await m.download(allowMobileData: false);
    expect(File(path).existsSync(), isTrue);
    expect(await File(path).length(), payload.length);
    expect(await m.isModelReady(verifyHash: true), isTrue);
    expect(m.current.phase, ModelDownloadPhase.complete);
    await m.dispose();
  });

  test('already-present valid file skips network', () async {
    final m = manager();
    final dir = Directory(p.join(tmp.path, 'models'));
    await dir.create(recursive: true);
    final dest = File(p.join(dir.path, testManifest().fileName));
    await dest.writeAsBytes(payload, flush: true);

    final path = await m.download(allowMobileData: false);
    expect(path, dest.path);
    expect(m.current.phase, ModelDownloadPhase.complete);
    await m.dispose();
  });

  test('resumes from .partial via Range', () async {
    final m = manager();
    final dir = Directory(p.join(tmp.path, 'models'));
    await dir.create(recursive: true);
    final partial = File(
      p.join(dir.path, '${testManifest().fileName}.partial'),
    );
    const offset = 1000;
    await partial.writeAsBytes(payload.sublist(0, offset), flush: true);

    final path = await m.download(allowMobileData: false);
    expect(await File(path).length(), payload.length);
    expect(await m.isModelReady(verifyHash: true), isTrue);
    expect(partial.existsSync(), isFalse);
    await m.dispose();
  });

  test('checksum mismatch deletes partial and fails', () async {
    final bad = ModelManifest(
      fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
      downloadUrl: baseUri.toString(),
      expectedBytes: payload.length,
      sha256Hex: '0' * 64,
      relativeModelsDir: 'nepal_clinical/models',
    );
    final m = IoModelDownloadManager(
      manifest: bad,
      modelsDirectoryOverride: Directory(p.join(tmp.path, 'models')),
      networkDetector: () async => NetworkKind.wifi,
      freeBytesChecker: (_) async => 10 * 1024 * 1024 * 1024,
    );
    await expectLater(
      m.download(allowMobileData: false),
      throwsA(isA<StateError>()),
    );
    expect(m.current.phase, ModelDownloadPhase.failed);
    final partial = File(
      p.join(tmp.path, 'models', '${bad.fileName}.partial'),
    );
    expect(partial.existsSync(), isFalse);
    await m.dispose();
  });

  test('mobile without allowMobileData refuses', () async {
    final m = IoModelDownloadManager(
      manifest: testManifest(),
      modelsDirectoryOverride: Directory(p.join(tmp.path, 'models')),
      networkDetector: () async => NetworkKind.mobile,
      freeBytesChecker: (_) async => 10 * 1024 * 1024 * 1024,
    );
    await expectLater(
      m.download(allowMobileData: false),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Mobile data'),
        ),
      ),
    );
    await m.dispose();
  });

  test('disk space assertion when free bytes known', () async {
    final m = IoModelDownloadManager(
      manifest: testManifest(),
      modelsDirectoryOverride: Directory(p.join(tmp.path, 'models')),
      networkDetector: () async => NetworkKind.wifi,
      freeBytesChecker: (_) async => 1024,
    );
    await expectLater(
      m.assertDiskSpace(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Not enough free storage'),
        ),
      ),
    );
    await m.dispose();
  });

  test('product manifest points at official HF Qwen GGUF', () {
    expect(ModelManifest.product.fileName, 'qwen2.5-1.5b-instruct-q4_k_m.gguf');
    expect(
      ModelManifest.product.downloadUrl,
      contains('Qwen/Qwen2.5-1.5B-Instruct-GGUF'),
    );
    expect(ModelManifest.product.expectedBytes, 1117320736);
    expect(
      ModelManifest.product.sha256Hex,
      '6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e',
    );
  });

  test('LocalModelNotFoundException mentions download CTA', () {
    expect(
      LocalModelNotFoundException.defaultMessage.toLowerCase(),
      contains('download'),
    );
  });
}
