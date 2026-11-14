import 'package:common_learn_english/features/shared/data/word_pronunciation_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses native Android TTS channel before plugin fallback', () async {
    const MethodChannel channel = MethodChannel('test_native_tts');
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return true;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final WordPronunciationTtsClient client = WordPronunciationTtsClient(
      nativeChannel: channel,
    );

    await client.speakText('街道', language: 'zh-CN');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'speak');
    expect(calls.single.arguments, <String, Object>{
      'text': '街道',
      'language': 'zh-CN',
      'engine': '',
      'voice': '',
      'rate': 0.75,
    });
  });

  test('passes selected TTS engine and voice to native channel', () async {
    const MethodChannel channel = MethodChannel('test_native_tts_engine');
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return true;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final WordPronunciationTtsClient client = WordPronunciationTtsClient(
      nativeChannel: channel,
    );

    await client.speakText(
      'street',
      engine: 'com.example.tts',
      voice: 'en-us-female',
    );

    expect(calls.single.arguments, containsPair('engine', 'com.example.tts'));
    expect(calls.single.arguments, containsPair('voice', 'en-us-female'));
  });

  test('stops native Android TTS playback', () async {
    const MethodChannel channel = MethodChannel('test_native_tts_stop');
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return true;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await WordPronunciationTtsClient(nativeChannel: channel).stop();

    expect(calls.single.method, 'stop');
  });

  test(
    'requests an offline voice for Android pronunciation feedback',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const MethodChannel channel = MethodChannel('test_offline_pronunciation');
      final List<MethodCall> calls = <MethodCall>[];
      final TestDefaultBinaryMessenger messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            ..setMockMethodCallHandler(channel, (MethodCall call) async {
              calls.add(call);
              return true;
            });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      await WordPronunciationService(
        offlineOnly: true,
        ttsClient: WordPronunciationTtsClient(nativeChannel: channel),
      ).speak('嘴张大一些。', language: 'zh-CN');

      expect(calls.single.arguments, containsPair('offlineOnly', true));
      expect(calls.single.arguments, containsPair('language', 'zh-CN'));
    },
  );

  test('uses requested language before speaking', () async {
    final _FakeWordPronunciationTtsClient client =
        _FakeWordPronunciationTtsClient();
    final WordPronunciationService service = WordPronunciationService(
      ttsClient: client,
    );

    await service.speak('街道', language: 'zh-CN');

    expect(client.languages, <String>['zh-CN']);
    expect(client.spokenTexts, <String>['街道']);
  });
}

class _FakeWordPronunciationTtsClient extends WordPronunciationTtsClient {
  final List<String> languages = <String>[];
  final List<String> spokenTexts = <String>[];

  @override
  Future<void> speakText(
    String text, {
    String language = 'en-US',
    String engine = '',
    String voice = '',
    double rate = 0.75,
    Duration speechTimeout = const Duration(seconds: 8),
  }) async {
    languages.add(language);
    spokenTexts.add(text);
  }
}
