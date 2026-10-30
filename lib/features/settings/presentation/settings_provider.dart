import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../shared/domain/subtitle_letter_case.dart';

export '../../shared/domain/subtitle_letter_case.dart'
    show subtitleLetterCaseOptions;

const List<double> ttsRateOptions = <double>[
  0.5,
  0.75,
  1,
  1.25,
  1.5,
  2,
  2.5,
  3,
];

const List<String> playerFontOptions = <String>[
  '特小',
  '小',
  '中',
  '大',
  '特大',
  '超大',
  '最大',
];
const Map<String, double> playerFontScales = <String, double>{
  '特小': 0.75,
  '小': 0.92,
  '中': 1,
  '大': 1.18,
  '特大': 1.4,
  '超大': 1.7,
  '最大': 2,
};
const List<String> subtitleWordHighlightStyleOptions = <String>[
  '绿色填充',
  '黄色填充',
  '蓝色填充',
  '下划线',
  '描边',
];

const List<String> subtitleModeOptions = <String>['双语', '单英', '单中', '隐藏'];
const List<String> playbackSpeedOptions = <String>[
  '0.5×',
  '0.8×',
  '1.0×',
  '1.25×',
  '1.5×',
];
const List<String> translationProviderOptions = <String>[
  'OpenAI',
  'OpenRouter',
  'SiliconFlow',
  'DeepSeek',
  'Google 翻译',
  '百度翻译',
  '阿里云翻译',
];
const List<String> asrProviderOptions = <String>['阿里云百炼', '腾讯云'];

const String _learningSettingsStorageKey = 'learning_settings_v1';

class TranslationProviderPreset {
  const TranslationProviderPreset({
    required this.name,
    required this.baseUrl,
    required this.model,
  });

  final String name;
  final String baseUrl;
  final String model;
}

const Map<String, TranslationProviderPreset> translationProviderPresets =
    <String, TranslationProviderPreset>{
      'OpenAI': TranslationProviderPreset(
        name: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-4o-mini',
      ),
      'OpenRouter': TranslationProviderPreset(
        name: 'OpenRouter',
        baseUrl: 'https://openrouter.ai/api/v1',
        model: 'openrouter/auto',
      ),
      'SiliconFlow': TranslationProviderPreset(
        name: 'SiliconFlow',
        baseUrl: 'https://api.siliconflow.com/v1',
        model: 'Qwen/Qwen3-32B',
      ),
      'DeepSeek': TranslationProviderPreset(
        name: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-v4-flash',
      ),
      'Google 翻译': TranslationProviderPreset(
        name: 'Google 翻译',
        baseUrl: 'https://translation.googleapis.com',
        model: '',
      ),
      '百度翻译': TranslationProviderPreset(
        name: '百度翻译',
        baseUrl: 'https://fanyi-api.baidu.com',
        model: '',
      ),
      '阿里云翻译': TranslationProviderPreset(
        name: '阿里云翻译',
        baseUrl: 'https://mt.cn-hangzhou.aliyuncs.com',
        model: 'general',
      ),
    };

const Map<String, TranslationProviderPreset> asrProviderPresets =
    <String, TranslationProviderPreset>{
      '阿里云百炼': TranslationProviderPreset(
        name: '阿里云百炼',
        baseUrl: 'https://dashscope.aliyuncs.com',
        model: 'qwen3-asr-flash-filetrans',
      ),
      '腾讯云': TranslationProviderPreset(
        name: '腾讯云',
        baseUrl: 'https://asr.tencentcloudapi.com',
        model: '16k_en',
      ),
    };

class LearningSettingsState {
  const LearningSettingsState({
    required this.subtitleMode,
    this.subtitleLetterCase = '保留原样',
    required this.playbackSpeed,
    required this.fontSize,
    required this.subtitleDelayMs,
    required this.dictionarySource,
    required this.highlightWords,
    required this.subtitleWordHighlightStyle,
    required this.subtitleWordHighlightBorderWidth,
    required this.reminder,
    required this.translationProvider,
    required this.translationApiKey,
    required this.translationApiSecret,
    required this.translationBaseUrl,
    required this.translationModel,
    required this.availableTranslationModels,
    required this.isFetchingTranslationModels,
    required this.useCustomTranslationEndpoint,
    required this.asrProvider,
    required this.asrApiKey,
    required this.asrBaseUrl,
    required this.asrModel,
    required this.useCustomAsrEndpoint,
    required this.generateBilingualAsrSubtitles,
    required this.ttsEngine,
    required this.ttsVoice,
    required this.ttsRate,
  });

  factory LearningSettingsState.defaults() {
    final TranslationProviderPreset defaultPreset =
        translationProviderPresets['OpenAI']!;
    final TranslationProviderPreset defaultAsrPreset =
        asrProviderPresets['阿里云百炼']!;
    return LearningSettingsState(
      subtitleMode: '双语',
      playbackSpeed: '0.8×',
      fontSize: '中',
      subtitleDelayMs: 0,
      dictionarySource: '牛津学习者',
      highlightWords: true,
      subtitleWordHighlightStyle: '绿色填充',
      subtitleWordHighlightBorderWidth: 2.5,
      reminder: false,
      translationProvider: defaultPreset.name,
      translationApiKey: '',
      translationApiSecret: '',
      translationBaseUrl: defaultPreset.baseUrl,
      translationModel: defaultPreset.model,
      availableTranslationModels: const <String>[],
      isFetchingTranslationModels: false,
      useCustomTranslationEndpoint: false,
      asrProvider: defaultAsrPreset.name,
      asrApiKey: '',
      asrBaseUrl: defaultAsrPreset.baseUrl,
      asrModel: defaultAsrPreset.model,
      useCustomAsrEndpoint: false,
      generateBilingualAsrSubtitles: true,
      ttsEngine: '',
      ttsVoice: '',
      ttsRate: 0.75,
    );
  }

  final String subtitleMode;
  final String subtitleLetterCase;
  final String playbackSpeed;
  final String fontSize;
  final int subtitleDelayMs;
  final String dictionarySource;
  final bool highlightWords;
  final String subtitleWordHighlightStyle;
  final double subtitleWordHighlightBorderWidth;
  final bool reminder;
  final String translationProvider;
  final String translationApiKey;
  final String translationApiSecret;
  final String translationBaseUrl;
  final String translationModel;
  final List<String> availableTranslationModels;
  final bool isFetchingTranslationModels;
  final bool useCustomTranslationEndpoint;
  final String asrProvider;
  final String asrApiKey;
  final String asrBaseUrl;
  final String asrModel;
  final bool useCustomAsrEndpoint;
  final bool generateBilingualAsrSubtitles;
  final String ttsEngine;
  final String ttsVoice;
  final double ttsRate;

  LearningSettingsState copyWith({
    String? subtitleMode,
    String? subtitleLetterCase,
    String? playbackSpeed,
    String? fontSize,
    int? subtitleDelayMs,
    String? dictionarySource,
    bool? highlightWords,
    String? subtitleWordHighlightStyle,
    double? subtitleWordHighlightBorderWidth,
    bool? reminder,
    String? translationProvider,
    String? translationApiKey,
    String? translationApiSecret,
    String? translationBaseUrl,
    String? translationModel,
    List<String>? availableTranslationModels,
    bool? isFetchingTranslationModels,
    bool? useCustomTranslationEndpoint,
    String? asrProvider,
    String? asrApiKey,
    String? asrBaseUrl,
    String? asrModel,
    bool? useCustomAsrEndpoint,
    bool? generateBilingualAsrSubtitles,
    String? ttsEngine,
    String? ttsVoice,
    double? ttsRate,
  }) {
    return LearningSettingsState(
      subtitleMode: subtitleMode ?? this.subtitleMode,
      subtitleLetterCase: subtitleLetterCase ?? this.subtitleLetterCase,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      fontSize: fontSize ?? this.fontSize,
      subtitleDelayMs: subtitleDelayMs ?? this.subtitleDelayMs,
      dictionarySource: dictionarySource ?? this.dictionarySource,
      highlightWords: highlightWords ?? this.highlightWords,
      subtitleWordHighlightStyle:
          subtitleWordHighlightStyle ?? this.subtitleWordHighlightStyle,
      subtitleWordHighlightBorderWidth:
          subtitleWordHighlightBorderWidth ??
          this.subtitleWordHighlightBorderWidth,
      reminder: reminder ?? this.reminder,
      translationProvider: translationProvider ?? this.translationProvider,
      translationApiKey: translationApiKey ?? this.translationApiKey,
      translationApiSecret: translationApiSecret ?? this.translationApiSecret,
      translationBaseUrl: translationBaseUrl ?? this.translationBaseUrl,
      translationModel: translationModel ?? this.translationModel,
      availableTranslationModels:
          availableTranslationModels ?? this.availableTranslationModels,
      isFetchingTranslationModels:
          isFetchingTranslationModels ?? this.isFetchingTranslationModels,
      useCustomTranslationEndpoint:
          useCustomTranslationEndpoint ?? this.useCustomTranslationEndpoint,
      asrProvider: asrProvider ?? this.asrProvider,
      asrApiKey: asrApiKey ?? this.asrApiKey,
      asrBaseUrl: asrBaseUrl ?? this.asrBaseUrl,
      asrModel: asrModel ?? this.asrModel,
      useCustomAsrEndpoint: useCustomAsrEndpoint ?? this.useCustomAsrEndpoint,
      generateBilingualAsrSubtitles:
          generateBilingualAsrSubtitles ?? this.generateBilingualAsrSubtitles,
      ttsEngine: ttsEngine ?? this.ttsEngine,
      ttsVoice: ttsVoice ?? this.ttsVoice,
      ttsRate: ttsRate ?? this.ttsRate,
    );
  }

  double get fontScale => playerFontScales[fontSize] ?? 1;
}

final NotifierProvider<LearningSettingsNotifier, LearningSettingsState>
learningSettingsProvider =
    NotifierProvider<LearningSettingsNotifier, LearningSettingsState>(
      LearningSettingsNotifier.new,
    );

final Provider<TranslationModelService> translationModelServiceProvider =
    Provider<TranslationModelService>(
      (Ref ref) => const TranslationModelService(),
    );

class TranslationModelService {
  const TranslationModelService({this.httpRequestOverride});

  final Future<Response<dynamic>> Function({
    required BaseOptions options,
    required String path,
  })?
  httpRequestOverride;

  Future<List<String>> fetchModels({
    required LearningSettingsState settings,
  }) async {
    final Response<dynamic> response = httpRequestOverride != null
        ? await httpRequestOverride!(
            options: BaseOptions(
              baseUrl: settings.translationBaseUrl,
              headers: <String, String>{
                'Authorization': 'Bearer ${settings.translationApiKey}',
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
            ),
            path: '/models',
          )
        : await Dio(
            BaseOptions(
              baseUrl: settings.translationBaseUrl,
              headers: <String, String>{
                'Authorization': 'Bearer ${settings.translationApiKey}',
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
            ),
          ).get<dynamic>('/models');

    final dynamic data = response.data;
    final List<dynamic> modelItems = data is Map<String, dynamic>
        ? (data['data'] as List<dynamic>? ?? <dynamic>[])
        : data is List<dynamic>
        ? data
        : <dynamic>[];

    return modelItems
        .map((dynamic item) => (item as Map<String, dynamic>)['id'] as String?)
        .whereType<String>()
        .map((String id) => id.trim())
        .where((String id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
  }
}

class LearningSettingsNotifier extends Notifier<LearningSettingsState> {
  @override
  LearningSettingsState build() {
    final LearningSettingsState defaults = LearningSettingsState.defaults();
    if (!Hive.isBoxOpen('prefs')) {
      return defaults;
    }

    final String? raw = Hive.box<String>(
      'prefs',
    ).get(_learningSettingsStorageKey);
    if (raw == null || raw.isEmpty) {
      return defaults;
    }

    try {
      final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
      final String? asrProvider = _asrProviderOrNull(json['asrProvider']);
      return defaults.copyWith(
        subtitleMode: _stringOrNull(json['subtitleMode']),
        subtitleLetterCase:
            subtitleLetterCaseOptions.contains(json['subtitleLetterCase'])
            ? json['subtitleLetterCase'] as String
            : null,
        playbackSpeed: _stringOrNull(json['playbackSpeed']),
        fontSize: _stringOrNull(json['fontSize']),
        subtitleDelayMs: _intOrNull(json['subtitleDelayMs']),
        dictionarySource: _stringOrNull(json['dictionarySource']),
        highlightWords: _boolOrNull(json['highlightWords']),
        subtitleWordHighlightStyle: _subtitleWordHighlightStyleOrNull(
          json['subtitleWordHighlightStyle'],
        ),
        subtitleWordHighlightBorderWidth:
            _subtitleWordHighlightBorderWidthOrNull(
              json['subtitleWordHighlightBorderWidth'],
            ),
        reminder: _boolOrNull(json['reminder']),
        translationProvider: _translationProviderOrNull(
          json['translationProvider'],
        ),
        translationApiKey: _stringOrNull(json['translationApiKey']),
        translationApiSecret: _stringOrNull(json['translationApiSecret']),
        translationBaseUrl: _stringOrNull(json['translationBaseUrl']),
        translationModel: _stringOrNull(json['translationModel']),
        useCustomTranslationEndpoint: _boolOrNull(
          json['useCustomTranslationEndpoint'],
        ),
        asrProvider: asrProvider,
        asrApiKey: asrProvider == null
            ? null
            : _stringOrNull(json['asrApiKey']),
        asrBaseUrl: asrProvider == null
            ? null
            : _stringOrNull(json['asrBaseUrl']),
        asrModel: asrProvider == null ? null : _stringOrNull(json['asrModel']),
        useCustomAsrEndpoint: asrProvider == null
            ? null
            : _boolOrNull(json['useCustomAsrEndpoint']),
        generateBilingualAsrSubtitles: _boolOrNull(
          json['generateBilingualAsrSubtitles'],
        ),
        ttsEngine: _stringOrNull(json['ttsEngine']),
        ttsVoice: _stringOrNull(json['ttsVoice']),
        ttsRate: _doubleOrNull(json['ttsRate']),
      );
    } catch (_) {
      return defaults;
    }
  }

  void setSubtitleMode(String value) {
    if (!subtitleModeOptions.contains(value)) {
      return;
    }
    state = state.copyWith(subtitleMode: value);
    _persist();
  }

  void setSubtitleLetterCase(String value) {
    if (!subtitleLetterCaseOptions.contains(value)) return;
    state = state.copyWith(subtitleLetterCase: value);
    _persist();
  }

  void setPlaybackSpeed(String value) {
    if (!playbackSpeedOptions.contains(value)) {
      return;
    }
    state = state.copyWith(playbackSpeed: value);
    _persist();
  }

  void setFontSize(String value) {
    if (!playerFontOptions.contains(value)) {
      return;
    }
    state = state.copyWith(fontSize: value);
    _persist();
  }

  void setSubtitleDelayMs(int value) {
    state = state.copyWith(subtitleDelayMs: value.clamp(-5000, 5000));
    _persist();
  }

  void setDictionarySource(String value) {
    state = state.copyWith(dictionarySource: value);
    _persist();
  }

  void setTranslationProvider(String value) {
    if (!translationProviderOptions.contains(value)) {
      return;
    }
    final TranslationProviderPreset preset = translationProviderPresets[value]!;
    state = state.copyWith(
      translationProvider: value,
      translationBaseUrl: preset.baseUrl,
      translationModel: preset.model,
      availableTranslationModels: const <String>[],
      isFetchingTranslationModels: false,
    );
    _persist();
  }

  void setTranslationApiKey(String value) {
    state = state.copyWith(translationApiKey: value.trim());
    _persist();
  }

  void setTranslationApiSecret(String value) {
    state = state.copyWith(translationApiSecret: value.trim());
    _persist();
  }

  void setUseCustomTranslationEndpoint({required bool value}) {
    if (value) {
      state = state.copyWith(useCustomTranslationEndpoint: true);
      _persist();
      return;
    }

    final TranslationProviderPreset preset =
        translationProviderPresets[state.translationProvider]!;
    state = state.copyWith(
      useCustomTranslationEndpoint: false,
      translationBaseUrl: preset.baseUrl,
      translationModel: preset.model,
    );
    _persist();
  }

  void setTranslationBaseUrl(String value) {
    state = state.copyWith(translationBaseUrl: value.trim());
    _persist();
  }

  void setTranslationModel(String value) {
    state = state.copyWith(translationModel: value.trim());
    _persist();
  }

  Future<List<String>> fetchTranslationModels() async {
    if (!_isAiProvider(state.translationProvider)) {
      return const <String>[];
    }
    if (state.translationApiKey.isEmpty) {
      throw StateError('missing-api-key');
    }

    state = state.copyWith(isFetchingTranslationModels: true);
    try {
      final List<String> models = await ref
          .read(translationModelServiceProvider)
          .fetchModels(settings: state);
      state = state.copyWith(
        isFetchingTranslationModels: false,
        availableTranslationModels: models,
        translationModel:
            models.contains(state.translationModel) || models.isEmpty
            ? state.translationModel
            : models.first,
      );
      return models;
    } catch (_) {
      state = state.copyWith(isFetchingTranslationModels: false);
      rethrow;
    }
  }

  void setAsrProvider(String value) {
    final String provider = _normalizeAsrProvider(value);
    if (!asrProviderOptions.contains(provider)) {
      return;
    }
    final TranslationProviderPreset preset = asrProviderPresets[provider]!;
    state = state.copyWith(
      asrProvider: provider,
      asrBaseUrl: preset.baseUrl,
      asrModel: preset.model,
    );
    _persist();
  }

  void setAsrApiKey(String value) {
    state = state.copyWith(asrApiKey: value.trim());
    _persist();
  }

  void setGenerateBilingualAsrSubtitles({required bool value}) {
    state = state.copyWith(generateBilingualAsrSubtitles: value);
    _persist();
  }

  void setUseCustomAsrEndpoint({required bool value}) {
    if (value) {
      state = state.copyWith(useCustomAsrEndpoint: true);
      _persist();
      return;
    }

    final TranslationProviderPreset preset =
        asrProviderPresets[state.asrProvider]!;
    state = state.copyWith(
      useCustomAsrEndpoint: false,
      asrBaseUrl: preset.baseUrl,
      asrModel: preset.model,
    );
    _persist();
  }

  void setAsrBaseUrl(String value) {
    state = state.copyWith(asrBaseUrl: value.trim());
    _persist();
  }

  void setAsrModel(String value) {
    state = state.copyWith(asrModel: value.trim());
    _persist();
  }

  void setHighlightWords({required bool value}) {
    state = state.copyWith(highlightWords: value);
    _persist();
  }

  void setSubtitleWordHighlightStyle(String value) {
    if (!subtitleWordHighlightStyleOptions.contains(value)) {
      return;
    }
    state = state.copyWith(subtitleWordHighlightStyle: value);
    _persist();
  }

  void setSubtitleWordHighlightBorderWidth(double value) {
    state = state.copyWith(
      subtitleWordHighlightBorderWidth: value.clamp(1.5, 3.5),
    );
    _persist();
  }

  void setReminder({required bool value}) {
    state = state.copyWith(reminder: value);
    _persist();
  }

  void setTtsEngine(String value) {
    state = state.copyWith(ttsEngine: value.trim(), ttsVoice: '');
    _persist();
  }

  void setTtsVoice(String value) {
    state = state.copyWith(ttsVoice: value.trim());
    _persist();
  }

  void setTtsRate(double value) {
    state = state.copyWith(
      ttsRate: value.clamp(ttsRateOptions.first, ttsRateOptions.last),
    );
    _persist();
  }

  void resetToDefaults() {
    state = LearningSettingsState.defaults();
    _persist();
  }

  void _persist() {
    if (!Hive.isBoxOpen('prefs')) {
      return;
    }
    unawaited(
      Hive.box<String>('prefs').put(
        _learningSettingsStorageKey,
        jsonEncode(<String, Object?>{
          'subtitleMode': state.subtitleMode,
          'subtitleLetterCase': state.subtitleLetterCase,
          'playbackSpeed': state.playbackSpeed,
          'fontSize': state.fontSize,
          'subtitleDelayMs': state.subtitleDelayMs,
          'dictionarySource': state.dictionarySource,
          'highlightWords': state.highlightWords,
          'subtitleWordHighlightStyle': state.subtitleWordHighlightStyle,
          'subtitleWordHighlightBorderWidth':
              state.subtitleWordHighlightBorderWidth,
          'reminder': state.reminder,
          'translationProvider': state.translationProvider,
          'translationApiKey': state.translationApiKey,
          'translationApiSecret': state.translationApiSecret,
          'translationBaseUrl': state.translationBaseUrl,
          'translationModel': state.translationModel,
          'useCustomTranslationEndpoint': state.useCustomTranslationEndpoint,
          'asrProvider': state.asrProvider,
          'asrApiKey': state.asrApiKey,
          'asrBaseUrl': state.asrBaseUrl,
          'asrModel': state.asrModel,
          'useCustomAsrEndpoint': state.useCustomAsrEndpoint,
          'generateBilingualAsrSubtitles': state.generateBilingualAsrSubtitles,
          'ttsEngine': state.ttsEngine,
          'ttsVoice': state.ttsVoice,
          'ttsRate': state.ttsRate,
        }),
      ),
    );
  }

  String? _stringOrNull(Object? value) {
    final String? raw = value as String?;
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return raw.trim();
  }

  bool? _boolOrNull(Object? value) => value as bool?;

  double? _doubleOrNull(Object? value) =>
      value is num ? value.toDouble() : null;

  String? _subtitleWordHighlightStyleOrNull(Object? value) {
    final String? style = _stringOrNull(value);
    return subtitleWordHighlightStyleOptions.contains(style) ? style : null;
  }

  double? _subtitleWordHighlightBorderWidthOrNull(Object? value) {
    final double? width = _doubleOrNull(value);
    return width != null && width >= 1.5 && width <= 3.5 ? width : null;
  }

  int? _intOrNull(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return null;
  }

  String? _translationProviderOrNull(Object? value) {
    final String? provider = _stringOrNull(value);
    if (provider == null || !translationProviderOptions.contains(provider)) {
      return null;
    }
    return provider;
  }

  String? _asrProviderOrNull(Object? value) {
    final String? rawProvider = _stringOrNull(value);
    final String? provider = rawProvider == null
        ? null
        : _normalizeAsrProvider(rawProvider);
    if (provider == null || !asrProviderOptions.contains(provider)) {
      return null;
    }
    return provider;
  }

  String _normalizeAsrProvider(String value) {
    if (value == 'Tencent Cloud') return '腾讯云';
    if (value == 'Alibaba Cloud') return '阿里云百炼';
    return value;
  }

  bool _isAiProvider(String provider) {
    return provider == 'OpenAI' ||
        provider == 'OpenRouter' ||
        provider == 'SiliconFlow' ||
        provider == 'DeepSeek';
  }
}
