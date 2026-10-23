import 'dart:convert';
import 'dart:io';

import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:riverpod/src/framework.dart' show Override;

void main() {
  late Directory hiveDir;

  setUp(() async {
    hiveDir = Directory.systemTemp.createTempSync('learning-settings-test-');
    Hive.init(hiveDir.path);
    await Hive.openBox<String>('prefs');
  });

  tearDown(() async {
    if (Hive.isBoxOpen('prefs')) {
      await Hive.box<String>('prefs').close();
    }
    await Hive.deleteBoxFromDisk('prefs');
    hiveDir.deleteSync(recursive: true);
  });

  test(
    'subtitle letter case persists, rejects invalid values, and resets',
    () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final LearningSettingsNotifier settings = container.read(
        learningSettingsProvider.notifier,
      );
      expect(
        container.read(learningSettingsProvider).subtitleLetterCase,
        '保留原样',
      );
      settings
        ..setSubtitleLetterCase('全部小写')
        ..setSubtitleLetterCase('invalid');
      await Hive.box<String>('prefs').flush();
      final ProviderContainer restored = ProviderContainer();
      addTearDown(restored.dispose);
      expect(
        restored.read(learningSettingsProvider).subtitleLetterCase,
        '全部小写',
      );
      restored.read(learningSettingsProvider.notifier).resetToDefaults();
      expect(
        restored.read(learningSettingsProvider).subtitleLetterCase,
        '保留原样',
      );
    },
  );

  test(
    'old or invalid subtitle letter case settings keep the original text',
    () async {
      for (final Object? value in <Object?>[null, 'invalid', 42]) {
        await Hive.box<String>('prefs').put(
          'learning_settings_v1',
          jsonEncode(<String, Object?>{
            if (value != null) 'subtitleLetterCase': value,
            'fontSize': '大',
          }),
        );
        final ProviderContainer container = ProviderContainer();
        expect(
          container.read(learningSettingsProvider).subtitleLetterCase,
          '保留原样',
        );
        expect(container.read(learningSettingsProvider).fontSize, '大');
        container.dispose();
      }
    },
  );

  test('defaults to OpenAI translation source', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    final LearningSettingsState state = container.read(
      learningSettingsProvider,
    );
    expect(state.translationProvider, 'OpenAI');
    expect(state.translationApiKey, isEmpty);
    expect(state.translationBaseUrl, 'https://api.openai.com/v1');
  });

  test('translation provider presets fill default base url and model', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(learningSettingsProvider.notifier)
        .setTranslationProvider('OpenRouter');

    final LearningSettingsState state = container.read(
      learningSettingsProvider,
    );
    expect(state.translationProvider, 'OpenRouter');
    expect(state.translationBaseUrl, 'https://openrouter.ai/api/v1');
    expect(state.translationModel, 'openrouter/auto');
  });

  test('asr provider presets are independent from translation settings', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(learningSettingsProvider.notifier)
      ..setTranslationProvider('DeepSeek')
      ..setTranslationApiKey('translation-key')
      ..setAsrProvider('腾讯云')
      ..setAsrApiKey('secret-id:secret-key');

    final LearningSettingsState state = container.read(
      learningSettingsProvider,
    );
    expect(state.translationProvider, 'DeepSeek');
    expect(state.translationApiKey, 'translation-key');
    expect(state.asrProvider, '腾讯云');
    expect(state.asrApiKey, 'secret-id:secret-key');
    expect(state.asrBaseUrl, 'https://asr.tencentcloudapi.com');
    expect(state.asrModel, '16k_en');
  });

  test('tencent cloud asr preset fills endpoint and english model', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(learningSettingsProvider.notifier).setAsrProvider('腾讯云');

    final LearningSettingsState state = container.read(
      learningSettingsProvider,
    );
    expect(state.asrProvider, '腾讯云');
    expect(state.asrBaseUrl, 'https://asr.tencentcloudapi.com');
    expect(state.asrModel, '16k_en');
  });

  test('legacy Tencent Cloud asr preset is normalized to chinese name', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(learningSettingsProvider.notifier)
        .setAsrProvider('Tencent Cloud');

    final LearningSettingsState state = container.read(
      learningSettingsProvider,
    );
    expect(state.asrProvider, '腾讯云');
    expect(state.asrBaseUrl, 'https://asr.tencentcloudapi.com');
  });

  test('deepseek preset fills default base url and model', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(learningSettingsProvider.notifier)
        .setTranslationProvider('DeepSeek');

    final LearningSettingsState state = container.read(
      learningSettingsProvider,
    );
    expect(state.translationProvider, 'DeepSeek');
    expect(state.translationBaseUrl, 'https://api.deepseek.com');
    expect(state.translationModel, 'deepseek-v4-flash');
  });

  test('google translate preset fills direct endpoint', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(learningSettingsProvider.notifier)
        .setTranslationProvider('Google 翻译');

    final LearningSettingsState state = container.read(
      learningSettingsProvider,
    );
    expect(state.translationProvider, 'Google 翻译');
    expect(state.translationBaseUrl, 'https://translation.googleapis.com');
    expect(state.translationModel, '');
  });

  test('custom translation endpoint can override base url and model', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(learningSettingsProvider.notifier)
      ..setUseCustomTranslationEndpoint(value: true)
      ..setTranslationBaseUrl('https://example.com/v1')
      ..setTranslationModel('demo-model');

    final LearningSettingsState state = container.read(
      learningSettingsProvider,
    );
    expect(state.useCustomTranslationEndpoint, isTrue);
    expect(state.translationBaseUrl, 'https://example.com/v1');
    expect(state.translationModel, 'demo-model');
  });

  test('settings persist across provider rebuilds', () async {
    final ProviderContainer first = ProviderContainer();
    addTearDown(first.dispose);

    first.read(learningSettingsProvider.notifier)
      ..setTranslationProvider('阿里云翻译')
      ..setTranslationApiKey('demo-key')
      ..setTranslationApiSecret('demo-secret')
      ..setHighlightWords(value: false)
      ..setSubtitleWordHighlightStyle('蓝色填充')
      ..setSubtitleWordHighlightBorderWidth(3.5);

    await Future<void>.delayed(Duration.zero);

    final ProviderContainer second = ProviderContainer();
    addTearDown(second.dispose);

    final LearningSettingsState state = second.read(learningSettingsProvider);
    expect(state.translationProvider, '阿里云翻译');
    expect(state.translationApiKey, 'demo-key');
    expect(state.translationApiSecret, 'demo-secret');
    expect(state.highlightWords, isFalse);
    expect(state.subtitleWordHighlightStyle, '蓝色填充');
    expect(state.subtitleWordHighlightBorderWidth, 3.5);
  });

  test('TTS voice settings persist across provider rebuilds', () async {
    final ProviderContainer first = ProviderContainer();
    addTearDown(first.dispose);

    first
        .read(learningSettingsProvider.notifier)
        .setTtsEngine('com.example.tts');
    first.read(learningSettingsProvider.notifier).setTtsVoice('en-us-female');
    first.read(learningSettingsProvider.notifier).setTtsRate(1.25);

    await Future<void>.delayed(Duration.zero);

    final ProviderContainer second = ProviderContainer();
    addTearDown(second.dispose);

    final LearningSettingsState state = second.read(learningSettingsProvider);
    expect(state.ttsEngine, 'com.example.tts');
    expect(state.ttsVoice, 'en-us-female');
    expect(state.ttsRate, 1.25);
  });

  test('ASR settings persist across provider rebuilds', () async {
    final ProviderContainer first = ProviderContainer();
    addTearDown(first.dispose);

    first.read(learningSettingsProvider.notifier)
      ..setAsrProvider('腾讯云')
      ..setAsrApiKey('secret-id:secret-key')
      ..setUseCustomAsrEndpoint(value: true)
      ..setAsrBaseUrl('https://asr.example.com/v1')
      ..setAsrModel('asr-demo')
      ..setGenerateBilingualAsrSubtitles(value: true)
      ..setSubtitleDelayMs(600);

    await Future<void>.delayed(Duration.zero);

    final ProviderContainer second = ProviderContainer();
    addTearDown(second.dispose);

    final LearningSettingsState state = second.read(learningSettingsProvider);
    expect(state.asrProvider, '腾讯云');
    expect(state.asrApiKey, 'secret-id:secret-key');
    expect(state.useCustomAsrEndpoint, isTrue);
    expect(state.asrBaseUrl, 'https://asr.example.com/v1');
    expect(state.asrModel, 'asr-demo');
    expect(state.generateBilingualAsrSubtitles, isTrue);
    expect(state.subtitleDelayMs, 600);
  });

  test(
    'unsupported ASR providers are no longer selectable or restored',
    () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(learningSettingsProvider.notifier)
          .setAsrProvider('MiMo Token Plan');

      expect(container.read(learningSettingsProvider).asrProvider, '阿里云百炼');

      await Hive.box<String>('prefs').put(
        'learning_settings_v1',
        jsonEncode(<String, Object?>{
          'asrProvider': 'DeepSeek',
          'asrBaseUrl': 'https://api.deepseek.com',
          'asrModel': 'deepseek-v4-flash',
        }),
      );

      final ProviderContainer legacy = ProviderContainer();
      addTearDown(legacy.dispose);

      final LearningSettingsState state = legacy.read(learningSettingsProvider);
      expect(state.asrProvider, '阿里云百炼');
      expect(state.asrBaseUrl, 'https://dashscope.aliyuncs.com');
      expect(state.asrModel, 'qwen3-asr-flash-filetrans');
    },
  );

  test(
    'fetch translation models updates available models and selected model',
    () async {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          translationModelServiceProvider.overrideWith(
            (Ref ref) => TranslationModelService(
              httpRequestOverride:
                  ({required BaseOptions options, required String path}) async {
                    expect(options.baseUrl, 'https://api.deepseek.com');
                    expect(path, '/models');
                    return Response<dynamic>(
                      requestOptions: RequestOptions(path: path),
                      data: <String, dynamic>{
                        'data': <Map<String, dynamic>>[
                          <String, dynamic>{'id': 'deepseek-v4-pro'},
                          <String, dynamic>{'id': 'deepseek-v4-flash'},
                        ],
                      },
                    );
                  },
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(learningSettingsProvider.notifier)
        ..setTranslationProvider('DeepSeek')
        ..setTranslationApiKey('demo-key')
        ..setTranslationModel('custom-model');

      final List<String> models = await container
          .read(learningSettingsProvider.notifier)
          .fetchTranslationModels();

      final LearningSettingsState state = container.read(
        learningSettingsProvider,
      );
      expect(models, <String>['deepseek-v4-flash', 'deepseek-v4-pro']);
      expect(state.availableTranslationModels, <String>[
        'deepseek-v4-flash',
        'deepseek-v4-pro',
      ]);
      expect(state.translationModel, 'deepseek-v4-flash');
      expect(state.isFetchingTranslationModels, isFalse);
    },
  );
}
