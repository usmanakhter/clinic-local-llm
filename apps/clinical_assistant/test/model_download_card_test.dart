import 'dart:async';

import 'package:clinical_assistant/llm/model_download_manager.dart';
import 'package:clinical_assistant/llm/model_manifest.dart';
import 'package:clinical_assistant/widgets/model_download_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeManager implements ModelDownloadManager {
  _FakeManager();

  final _controller = StreamController<ModelDownloadProgress>.broadcast();
  ModelDownloadProgress _current = const ModelDownloadProgress(
    phase: ModelDownloadPhase.idle,
  );
  bool downloaded = false;
  NetworkKind network = NetworkKind.wifi;

  @override
  ModelManifest get manifest => ModelManifest.product;

  @override
  ModelDownloadProgress get current => _current;

  @override
  Stream<ModelDownloadProgress> get progress => _controller.stream;

  @override
  Future<bool> isModelReady({bool verifyHash = false}) async => downloaded;

  @override
  Future<String> modelsDirectoryPath() async => '/tmp/models';

  @override
  Future<NetworkKind> detectNetwork() async => network;

  @override
  Future<int?> freeBytesAvailable() async => 8 * 1024 * 1024 * 1024;

  @override
  Future<void> assertDiskSpace() async {}

  @override
  Future<String> download({required bool allowMobileData}) async {
    if (network == NetworkKind.mobile && !allowMobileData) {
      throw StateError('Mobile data detected. Confirm use mobile data.');
    }
    _current = ModelDownloadProgress(
      phase: ModelDownloadPhase.downloading,
      receivedBytes: manifest.expectedBytes ~/ 2,
      totalBytes: manifest.expectedBytes,
    );
    _controller.add(_current);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    downloaded = true;
    _current = ModelDownloadProgress(
      phase: ModelDownloadPhase.complete,
      receivedBytes: manifest.expectedBytes,
      totalBytes: manifest.expectedBytes,
    );
    _controller.add(_current);
    return '/tmp/models/${manifest.fileName}';
  }

  @override
  void cancel() {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

void main() {
  testWidgets('missing-model card shows download CTA', (tester) async {
    final fake = _FakeManager();
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModelDownloadCard(
            manager: fake,
            onComplete: () => completed = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('On-device clinical model required'), findsOneWidget);
    expect(find.text('Download clinical model'), findsOneWidget);

    await tester.tap(find.text('Download clinical model'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(fake.downloaded, isTrue);
    await fake.dispose();
  });

  testWidgets('mobile data requires checkbox before download proceeds',
      (tester) async {
    final fake = _FakeManager()..network = NetworkKind.mobile;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModelDownloadCard(
            manager: fake,
            onComplete: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Download clinical model'));
    await tester.pumpAndSettle();

    expect(fake.downloaded, isFalse);
    expect(find.textContaining('Mobile data'), findsWidgets);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download clinical model'));
    await tester.pumpAndSettle();

    expect(fake.downloaded, isTrue);
    await fake.dispose();
  });
}
