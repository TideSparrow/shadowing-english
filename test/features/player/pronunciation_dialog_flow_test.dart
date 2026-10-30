import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:common_learn_english/constants/feature_flags.dart';
import 'package:common_learn_english/features/player/data/pronunciation_audio_extractor.dart';
import 'package:common_learn_english/features/player/data/pronunciation_providers.dart';
import 'package:common_learn_english/features/player/data/tencent_pronunciation_service.dart';
import 'package:common_learn_english/features/player/domain/pronunciation_assessment.dart';
import 'package:common_learn_english/features/player/presentation/widgets/pronunciation_assessment_dialog.dart';
import 'package:common_learn_english/features/settings/data/pronunciation_credentials.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:riverpod/src/framework.dart';

class ReviewPaths extends PathProviderPlatform {
  ReviewPaths(this.directory);
  final String directory;
  @override
  Future<String?> getTemporaryPath() async => directory;
}

Pcm16MonoAudio speech() {
  final Uint8List bytes = Uint8List(16000);
  final ByteData data = ByteData.sublistView(bytes);
  for (int i = 0; i < bytes.length ~/ 2; i++) {
    data.setInt16(i * 2, i.isEven ? 4000 : -4000, Endian.little);
  }
  return Pcm16MonoAudio(bytes: bytes, sampleRate: 16000);
}

class ReviewExtractor extends PronunciationAudioExtractor {
  ReviewExtractor(this.directory);
  final Directory directory;
  @override
  Future<PronunciationAudioSegment> extract({
    required String source,
    required int startMs,
    required int endMs,
    required Duration videoDuration,
    void Function(Future<void> Function())? onCancelAvailable,
  }) async {
    final File file = File('${directory.path}/reference.wav')
      ..writeAsBytesSync(speech().toWav());
    return PronunciationAudioSegment(path: file.path, audio: speech());
  }
}

class ReviewStore implements PronunciationCredentialStore {
  int reads = 0;
  Completer<PronunciationCredentials>? pendingRead;

  @override
  Future<PronunciationCredentials> read() async {
    reads++;
    if (pendingRead != null) {
      return pendingRead!.future;
    }
    return const PronunciationCredentials(
      appId: '1250000000',
      secretId: 'test-id',
      secretKey: 'test-key',
    );
  }

  @override
  Future<void> write(PronunciationCredentials value) async {}
}

class ReviewMicrophone implements PronunciationMicrophone {
  final StreamController<Uint8List> stream =
      StreamController<Uint8List>.broadcast();
  int stops = 0;
  int starts = 0;
  int disposes = 0;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<Stream<Uint8List>> start() async {
    starts++;
    return stream.stream;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {
    disposes++;
    unawaited(stream.close());
  }
}

class ReviewPreview implements PronunciationPreviewPlayer {
  @override
  Stream<Duration> get position => const Stream<Duration>.empty();
  final List<String> played = <String>[];
  @override
  Future<void> playLocalFile(String path) async {
    played.add(path);
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class ReviewService extends TencentPronunciationService {
  int calls = 0;
  final Completer<PronunciationAssessmentResult> pending =
      Completer<PronunciationAssessmentResult>();
  @override
  Future<PronunciationAssessmentResult> evaluate({
    required PronunciationCredentials credentials,
    required PronunciationAssessmentTarget target,
    required Pcm16MonoAudio audio,
    void Function(Future<void> Function())? onCancelAvailable,
  }) {
    calls++;
    expect(target.text, 'Take a break.');
    expect(audio.durationMs, anyOf(500, 520));
    return pending.future;
  }
}

void main() {
  testWidgets(
    'local recording and optional scoring preserve session and clean files',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final Directory temp = Directory.systemTemp.createTempSync(
        'pronunciation-flow-review-',
      );
      addTearDown(() {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
      });
      PathProviderPlatform.instance = ReviewPaths(
        '${temp.path}/new-recording-cache',
      );
      final ReviewMicrophone mic = ReviewMicrophone();
      final ReviewPreview preview = ReviewPreview();
      final ReviewService service = ReviewService();
      final ReviewStore store = ReviewStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            pronunciationAudioExtractorProvider.overrideWithValue(
              ReviewExtractor(temp),
            ),
            pronunciationCredentialStoreProvider.overrideWithValue(store),
            pronunciationMicrophoneFactoryProvider.overrideWithValue(() => mic),
            pronunciationPreviewPlayerFactoryProvider.overrideWithValue(
              () => preview,
            ),
            tencentPronunciationServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (BuildContext context) => Scaffold(
                body: TextButton(
                  onPressed: () => showPronunciationAssessmentDialog(
                    context,
                    target: const PronunciationAssessmentTarget(
                      text: 'Take a break.',
                      videoSource: '/local/fixture.mp4',
                      startMs: 600,
                      endMs: 1551,
                      videoDuration: Duration(milliseconds: 5393),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(service.calls, 0);
      expect(store.reads, 0);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(mic.starts, 1);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(mic.starts, 1);
      expect(mic.stops, 0);
      await tester.pump();
      mic.stream.add(Uint8List(32000));
      mic.stream.add(speech().bytes);
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byKey(
                const ValueKey<String>('pronunciation-reference-play'),
              ),
            )
            .onPressed,
        isNull,
      );
      if (pronunciationScoringEnabled) {
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(
                  const ValueKey<String>('pronunciation-score-button'),
                ),
              )
              .onPressed,
          isNull,
        );
      } else {
        expect(
          find.byKey(const ValueKey<String>('pronunciation-score-button')),
          findsNothing,
        );
      }

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      for (int i = 0; i < 8; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pumpAndSettle();
      expect(mic.stops, 1);
      expect(
        service.calls,
        0,
        reason: 'Finishing a recording must not upload it',
      );
      expect(find.text('重新录制'), findsOneWidget);
      final File recording = temp
          .listSync(recursive: true)
          .whereType<File>()
          .firstWhere(
            (File file) => file.path.contains('pronunciation-recording-'),
          );
      expect(
        Pcm16MonoAudio.parseWav(recording.readAsBytesSync()).durationMs,
        520,
      );
      expect(find.text('0.50 秒'), findsOneWidget);
      expect(find.text('0.52 秒'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (!pronunciationScoringEnabled) {
        expect(find.textContaining('评分'), findsNothing);
        expect(find.textContaining('腾讯'), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey<String>('pronunciation-reference-play')),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey<String>('pronunciation-recording-play')),
        );
        await tester.pump();
        expect(preview.played, hasLength(2));
        expect(store.reads, 0);
        expect(service.calls, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        for (int i = 0; i < 8; i++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        expect(mic.starts, 2);
        mic.stream.add(speech().bytes);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        for (int i = 0; i < 8; i++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        expect(mic.stops, 2);
        expect(store.reads, 0);
        expect(service.calls, 0);
        await tester.tap(
          find.byKey(const ValueKey<String>('pronunciation-dialog-close')),
        );
        await tester.pumpAndSettle();
        for (int i = 0; i < 8; i++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        expect(mic.disposes, 1);
        expect(temp.listSync(recursive: true).whereType<File>(), isEmpty);
        return;
      }
      // An enabled, focused score button must not score on Space.
      Focus.of(
        tester.element(find.byIcon(Icons.fact_check_outlined)),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      for (int i = 0; i < 8; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(mic.starts, 2);
      expect(service.calls, 0);
      mic.stream.add(Uint8List(32000));
      mic.stream.add(speech().bytes);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      for (int i = 0; i < 8; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('pronunciation-score-button')),
      );
      await tester.pump();
      expect(service.calls, 1);
      expect(store.reads, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(mic.starts, 2, reason: 'Space cannot re-record while scoring');
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey<String>('pronunciation-record-start')),
            )
            .onPressed,
        isNull,
      );
      service.pending.complete(
        const PronunciationAssessmentResult(
          suggestedScore: 86,
          accuracy: 84,
          fluency: .9,
          completion: 1,
          words: <PronunciationWordResult>[
            PronunciationWordResult(
              word: 'break',
              referenceWord: 'break',
              matchTag: 3,
              accuracy: 50,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('逐词结果'), findsOneWidget);
      expect(find.textContaining('86'), findsWidgets);
      expect(find.text('已评分'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey<String>('pronunciation-score-button')),
            )
            .onPressed,
        isNull,
      );
      expect(service.calls, 1);
      expect(tester.takeException(), isNull);

      // A fresh recording may be scored, but dismissing while the system is
      // reading the key must cancel before the route's exit animation finishes.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      for (int i = 0; i < 8; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(mic.starts, 3);
      expect(service.calls, 1);
      mic.stream.add(speech().bytes);
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('pronunciation-record-stop')),
      );
      for (int i = 0; i < 8; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      final Completer<PronunciationCredentials> delayedKey =
          Completer<PronunciationCredentials>();
      store.pendingRead = delayedKey;
      ProviderScope.containerOf(
        tester.element(find.byType(PronunciationAssessmentDialog)),
        listen: false,
      ).invalidate(pronunciationCredentialsProvider);
      await tester.tap(
        find.byKey(const ValueKey<String>('pronunciation-score-button')),
      );
      await tester.pump();
      expect(store.reads, 2);
      await tester.tap(
        find.byKey(const ValueKey<String>('pronunciation-dialog-close')),
      );
      delayedKey.complete(
        const PronunciationCredentials(
          appId: '1250000000',
          secretId: 'test-id',
          secretKey: 'test-key',
        ),
      );
      await tester.pump();
      expect(service.calls, 1);
      await tester.pumpAndSettle();
      for (int i = 0; i < 8; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(mic.disposes, 1);
      expect(temp.listSync(recursive: true).whereType<File>(), isEmpty);
    },
  );
}
