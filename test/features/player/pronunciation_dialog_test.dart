import 'dart:typed_data';

import 'package:common_learn_english/features/player/data/pronunciation_audio_extractor.dart';
import 'package:common_learn_english/features/player/data/pronunciation_providers.dart';
import 'package:common_learn_english/features/player/domain/pronunciation_assessment.dart';
import 'package:common_learn_english/features/player/presentation/widgets/pronunciation_assessment_dialog.dart';
import 'package:common_learn_english/features/settings/data/pronunciation_credentials.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/src/framework.dart' show Override;

class _Extractor extends PronunciationAudioExtractor {
  @override
  Future<PronunciationAudioSegment> extract({
    required String source,
    required int startMs,
    required int endMs,
    required Duration videoDuration,
    void Function(Future<void> Function())? onCancelAvailable,
  }) async {
    throw const PronunciationAudioExtractionException('原声暂不可用。');
  }
}

class _Store implements PronunciationCredentialStore {
  int readCount = 0;

  @override
  Future<PronunciationCredentials> read() async {
    readCount++;
    return const PronunciationCredentials();
  }

  @override
  Future<void> write(PronunciationCredentials credentials) async {}
}

class _Microphone implements PronunciationMicrophone {
  int disposeCount = 0;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<Stream<Uint8List>> start() async => const Stream<Uint8List>.empty();

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}

class _PreviewPlayer implements PronunciationPreviewPlayer {
  @override
  Stream<Duration> get position => const Stream<Duration>.empty();
  @override
  Future<void> playLocalFile(String path) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('dialog fits 320 px and creates a fresh session on reopen', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final List<_Microphone> microphones = <_Microphone>[];
    final _Store store = _Store();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          pronunciationAudioExtractorProvider.overrideWithValue(_Extractor()),
          pronunciationCredentialStoreProvider.overrideWithValue(store),
          pronunciationMicrophoneFactoryProvider.overrideWithValue(() {
            final _Microphone microphone = _Microphone();
            microphones.add(microphone);
            return microphone;
          }),
          pronunciationPreviewPlayerFactoryProvider.overrideWithValue(
            _PreviewPlayer.new,
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showPronunciationAssessmentDialog(
                    context,
                    target: const PronunciationAssessmentTarget(
                      text: 'Take a break.',
                      videoSource: '/local/video.mp4',
                      startMs: 600,
                      endMs: 1551,
                      videoDuration: Duration(seconds: 5),
                    ),
                  ),
                  child: const Text('打开评测'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    for (int session = 0; session < 2; session++) {
      await tester.tap(find.text('打开评测'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('pronunciation-frozen-text')),
        findsOneWidget,
      );
      expect(find.text('视频时间段 00:00.600 – 00:01.551'), findsOneWidget);
      expect(
        tester.getSize(
          find.byKey(const ValueKey<String>('pronunciation-assessment-dialog')),
        ),
        const Size(320, 800),
      );
      expect(
        find.byKey(const ValueKey<String>('pronunciation-overlaid-waveforms')),
        findsOneWidget,
      );
      expect(store.readCount, 0);
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.byKey(const ValueKey<String>('pronunciation-dialog-close')),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {});
      await tester.pump();
    }

    expect(microphones, hasLength(2));
    expect(microphones[0], isNot(same(microphones[1])));
    expect(microphones.map((_Microphone device) => device.disposeCount), <int>[
      1,
      1,
    ]);
  });
}
