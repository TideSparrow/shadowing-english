import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:common_learn_english/constants/feature_flags.dart';
import 'package:common_learn_english/features/player/data/doubao_pronunciation_service.dart';
import 'package:common_learn_english/features/player/data/pronunciation_audio_extractor.dart';
import 'package:common_learn_english/features/player/data/pronunciation_history_store.dart';
import 'package:common_learn_english/features/player/data/pronunciation_providers.dart';
import 'package:common_learn_english/features/player/domain/pronunciation_assessment.dart';
import 'package:common_learn_english/features/player/presentation/widgets/pronunciation_assessment_dialog.dart';
import 'package:common_learn_english/features/settings/data/pronunciation_credentials.dart';
import 'package:common_learn_english/features/shared/data/word_pronunciation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:riverpod/src/framework.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  PronunciationCredentials credentials = const PronunciationCredentials();

  @override
  Future<PronunciationCredentials> read() async {
    reads++;
    if (pendingRead != null) {
      return pendingRead!.future;
    }
    return credentials;
  }

  @override
  Future<void> write(PronunciationCredentials value) async {
    credentials = value;
  }
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

class ReviewService extends DoubaoPronunciationService {
  int calls = 0;
  final Completer<PronunciationAssessmentResult> pending =
      Completer<PronunciationAssessmentResult>();
  @override
  Future<PronunciationAssessmentResult> evaluate({
    required PronunciationCredentials credentials,
    required PronunciationAssessmentTarget target,
    required Pcm16MonoAudio audio,
    required Pcm16MonoAudio reference,
    void Function(Future<void> Function())? onCancelAvailable,
  }) {
    calls++;
    expect(target.text, 'Take a break.');
    expect(reference.durationMs, 500);
    expect(audio.durationMs, anyOf(500, 520));
    return pending.future;
  }
}

void main() {
  testWidgets(
    'local recording and optional coaching preserve session and clean files',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
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
      final Directory support = Directory('${temp.path}/app-support');
      final PronunciationHistoryStore historyStore = PronunciationHistoryStore(
        supportDirectory: () async => support,
      );
      const PronunciationAssessmentTarget target =
          PronunciationAssessmentTarget(
            text: 'Take a break.',
            videoSource: '/local/fixture.mp4',
            startMs: 600,
            endMs: 1551,
            videoDuration: Duration(milliseconds: 5393),
          );
      final List<String> spokenFeedback = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            pronunciationAudioExtractorProvider.overrideWithValue(
              ReviewExtractor(temp),
            ),
            pronunciationCredentialStoreProvider.overrideWithValue(store),
            pronunciationMicrophoneFactoryProvider.overrideWithValue(
              () => mic.disposes == 0 ? mic : ReviewMicrophone(),
            ),
            pronunciationHistoryStoreProvider.overrideWithValue(historyStore),
            pronunciationPreviewPlayerFactoryProvider.overrideWithValue(
              () => preview,
            ),
            doubaoPronunciationServiceProvider.overrideWithValue(service),
            pronunciationFeedbackSpeechProvider.overrideWithValue(
              WordPronunciationService(
                speakOverride: (String text) async => spokenFeedback.add(text),
              ),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (BuildContext context) => Scaffold(
                body: TextButton(
                  onPressed: () => showPronunciationAssessmentDialog(
                    context,
                    target: target,
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
      if (pronunciationCoachingEnabled) {
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(
                  const ValueKey<String>('pronunciation-guidance-button'),
                ),
              )
              .onPressed,
          isNull,
        );
      } else {
        expect(
          find.byKey(const ValueKey<String>('pronunciation-guidance-button')),
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
      if (!pronunciationCoachingEnabled) {
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
      // A focused guidance button must not submit on Space.
      Focus.of(
        tester.element(find.byIcon(Icons.record_voice_over_outlined)),
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
      final Finder guidanceButton = find.byKey(
        const ValueKey<String>('pronunciation-guidance-button'),
      );
      expect(find.textContaining('按实际音频和文字用量计费'), findsOneWidget);
      await tester.tap(guidanceButton);
      await tester.pumpAndSettle();
      expect(service.calls, 0);
      expect(find.text('配置火山方舟 API Key'), findsOneWidget);
      await tester.tap(find.text('去配置'));
      await tester.pumpAndSettle();
      expect(find.text('设置 · 跟读指导'), findsOneWidget);
      expect(find.text('申请 API Key'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'test-key');
      expect(find.text('保存密钥'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(store.credentials.isComplete, isTrue);
      expect(find.text('重新录制'), findsOneWidget);
      await tester.tap(guidanceButton);
      await tester.pumpAndSettle();
      expect(find.text('首次使用豆包发音指导'), findsOneWidget);
      await tester.tap(find.text('跟读指导帮助').last);
      await tester.pumpAndSettle();
      expect(find.text('火山方舟官方计费说明'), findsOneWidget);
      await tester.tap(find.text('关闭').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(service.calls, 0);
      await tester.tap(guidanceButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('同意并获取指导'));
      await tester.pump();
      expect(service.calls, 1);
      expect(store.reads, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(mic.starts, 2, reason: 'Space cannot re-record during a request');
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey<String>('pronunciation-record-start')),
            )
            .onPressed,
        isNull,
      );
      const String guidance = '最后一个词可以再读一遍，嘴慢慢收窄。';
      service.pending.complete(
        const PronunciationAssessmentResult(guidance: guidance),
      );
      for (int i = 0; i < 20 && find.text('发音指导').evaluate().isEmpty; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('逐词结果'), findsNothing);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'pronunciation.doubao.billingAccepted.v1',
        ),
        isTrue,
      );
      expect(find.widgetWithText(AlertDialog, '发音指导'), findsOneWidget);
      expect(find.text(guidance), findsOneWidget);
      expect(spokenFeedback.single, guidance);
      await tester.tap(find.text('听原声整句'));
      await tester.pumpAndSettle();
      expect(preview.played.last, endsWith('reference.wav'));
      await tester.tap(find.widgetWithText(TextButton, '关闭'));
      await tester.pumpAndSettle();
      expect(find.text('查看指导'), findsOneWidget);
      await tester.tap(guidanceButton);
      await tester.pumpAndSettle();
      expect(find.text(guidance), findsOneWidget);
      expect(spokenFeedback, hasLength(1));
      await tester.tap(find.widgetWithText(TextButton, '听发音指导'));
      await tester.pumpAndSettle();
      expect(spokenFeedback, hasLength(2));
      expect(service.calls, 1);
      await tester.tap(find.widgetWithText(TextButton, '关闭'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // A fresh recording may be submitted, but dismissing while the system is
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
        find.byKey(const ValueKey<String>('pronunciation-guidance-button')),
      );
      await tester.pump();
      expect(store.reads, 2);
      await tester.tap(
        find.byKey(const ValueKey<String>('pronunciation-dialog-close')),
      );
      delayedKey.complete(const PronunciationCredentials(apiKey: 'test-key'));
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
      final List<File> savedFiles = temp
          .listSync(recursive: true)
          .whereType<File>()
          .toList();
      expect(savedFiles, hasLength(2));
      expect(
        savedFiles.every((File file) => file.path.startsWith(support.path)),
        isTrue,
      );

      final PronunciationHistoryEntry? latest = await tester.runAsync(
        () => historyStore.save(
          target,
          const PronunciationAssessmentResult(suggestedScore: 91, accuracy: 91),
          Pcm16MonoAudio(bytes: Uint8List(9600), sampleRate: 16000),
        ),
      );
      await tester.tap(find.text('Open'));
      for (int i = 0; i < 20 && find.text('练习记录').evaluate().isEmpty; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('练习记录'));
      await tester.pumpAndSettle();
      expect(find.text('本句练习记录'), findsOneWidget);
      expect(find.text('第 2 次 · 最近一次'), findsOneWidget);
      expect(find.text('第 1 次'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, '评分 91.0'));
      for (int i = 0; i < 20 && find.text('历史发音评分').evaluate().isEmpty; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('历史发音评分'), findsOneWidget);
      await tester.tap(find.text('听我的整句'));
      await tester.pump();
      expect(preview.played.last, latest!.recordingFile.path);
      await tester.tap(find.widgetWithText(TextButton, '关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('练习记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, '第 1 次'));
      for (int i = 0; i < 20 && find.text('发音指导').evaluate().isEmpty; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pumpAndSettle();
      expect(find.text(guidance), findsOneWidget);
      expect(find.text('听我的整句'), findsOneWidget);
      await tester.tap(find.text('听我的整句'));
      await tester.pump();
      expect(preview.played.last, endsWith('/recording.wav'));
      expect(preview.played.last, isNot(latest.recordingFile.path));
      expect(service.calls, 1);
    },
  );
}
