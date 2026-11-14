import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../settings/presentation/settings_provider.dart';

final Provider<WordPronunciationService> wordPronunciationServiceProvider =
    Provider<WordPronunciationService>((Ref ref) {
      final LearningSettingsState settings = ref.watch(
        learningSettingsProvider,
      );
      return WordPronunciationService(
        selectedEngine: settings.ttsEngine,
        selectedVoice: settings.ttsVoice,
        selectedRate: settings.ttsRate,
      );
    });

final Provider<TtsEngineService> ttsEngineServiceProvider =
    Provider<TtsEngineService>((Ref ref) => const TtsEngineService());

final FutureProvider<TtsEngineSnapshot> ttsEngineSnapshotProvider =
    FutureProvider<TtsEngineSnapshot>((Ref ref) {
      return ref.read(ttsEngineServiceProvider).fetchEngines();
    });

// ignore: always_specify_types
final ttsVoiceSnapshotProvider =
    FutureProvider.family<TtsVoiceSnapshot, String>((Ref ref, String engine) {
      return ref.read(ttsEngineServiceProvider).fetchVoices(engine: engine);
    });

const Duration _ttsBindRetryDelay = Duration(milliseconds: 150);
const int _ttsBindRetryAttempts = 2;
const double _defaultPronunciationSpeechRate = 0.75;
const MethodChannel _nativeTtsChannel = MethodChannel(
  'com.shadowing.english/native_tts',
);

class WordPronunciationException implements Exception {
  const WordPronunciationException([this.message = '朗读失败，请检查设备 TTS。']);

  final String message;

  @override
  String toString() => message;
}

class WordPronunciationService {
  WordPronunciationService({
    this.speakOverride,
    this.stopOverride,
    this.selectedEngine = '',
    this.selectedVoice = '',
    this.selectedRate = _defaultPronunciationSpeechRate,
    this.offlineOnly = false,
    WordPronunciationTtsClient? ttsClient,
  }) : _ttsClient = ttsClient ?? WordPronunciationTtsClient();

  final Future<void> Function(String text)? speakOverride;
  final Future<void> Function()? stopOverride;
  final String selectedEngine;
  final String selectedVoice;
  final double selectedRate;
  final bool offlineOnly;
  final WordPronunciationTtsClient _ttsClient;

  Future<void> speak(
    String text, {
    String language = 'en-US',
    Duration speechTimeout = const Duration(seconds: 8),
    double? rate,
  }) async {
    if (speakOverride != null) {
      await speakOverride!(text);
      return;
    }

    final String normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return;
    }

    final Future<void> Function(
      String, {
      String language,
      String engine,
      String voice,
      double rate,
      Duration speechTimeout,
    })
    speakText = offlineOnly
        ? _ttsClient.speakOfflineText
        : _ttsClient.speakText;
    await speakText(
      normalizedText,
      language: language,
      engine: selectedEngine,
      voice: language.startsWith('en') ? selectedVoice : '',
      rate: rate ?? selectedRate,
      speechTimeout: speechTimeout,
    );
  }

  Future<void> stop() async {
    if (stopOverride != null) {
      await stopOverride!();
      return;
    }
    await _ttsClient.stop();
  }
}

class TtsEngineOption {
  const TtsEngineOption({
    required this.id,
    required this.label,
    required this.isDefault,
  });

  final String id;
  final String label;
  final bool isDefault;
}

class TtsEngineSnapshot {
  const TtsEngineSnapshot({required this.defaultEngine, required this.engines});

  final String defaultEngine;
  final List<TtsEngineOption> engines;
}

class TtsVoiceOption {
  const TtsVoiceOption({required this.id, required this.label});

  final String id;
  final String label;
}

class TtsVoiceSnapshot {
  const TtsVoiceSnapshot({required this.voices});

  final List<TtsVoiceOption> voices;
}

class TtsEngineService {
  const TtsEngineService({MethodChannel nativeChannel = _nativeTtsChannel})
    : _nativeChannel = nativeChannel;

  final MethodChannel _nativeChannel;

  Future<TtsEngineSnapshot> fetchEngines() async {
    try {
      final dynamic raw = await _nativeChannel.invokeMethod<dynamic>(
        'getEngines',
      );
      final Map<dynamic, dynamic> map = raw as Map<dynamic, dynamic>;
      final List<dynamic> engines =
          map['engines'] as List<dynamic>? ?? <dynamic>[];
      return TtsEngineSnapshot(
        defaultEngine: (map['defaultEngine'] as String?)?.trim() ?? '',
        engines: engines
            .map((dynamic item) {
              final Map<dynamic, dynamic> engine =
                  item as Map<dynamic, dynamic>;
              return TtsEngineOption(
                id: (engine['id'] as String?)?.trim() ?? '',
                label: (engine['label'] as String?)?.trim() ?? '',
                isDefault: engine['isDefault'] == true,
              );
            })
            .where((TtsEngineOption engine) => engine.id.isNotEmpty)
            .toList(growable: false),
      );
    } on MissingPluginException {
      return const TtsEngineSnapshot(
        defaultEngine: '',
        engines: <TtsEngineOption>[],
      );
    }
  }

  Future<TtsVoiceSnapshot> fetchVoices({required String engine}) async {
    try {
      final dynamic raw = await _nativeChannel.invokeMethod<dynamic>(
        'getVoices',
        <String, Object>{'engine': engine},
      );
      final Map<dynamic, dynamic> map = raw as Map<dynamic, dynamic>;
      final List<dynamic> voices =
          map['voices'] as List<dynamic>? ?? <dynamic>[];
      return TtsVoiceSnapshot(
        voices: voices
            .map((dynamic item) {
              final Map<dynamic, dynamic> voice = item as Map<dynamic, dynamic>;
              return TtsVoiceOption(
                id: (voice['id'] as String?)?.trim() ?? '',
                label: (voice['label'] as String?)?.trim() ?? '',
              );
            })
            .where((TtsVoiceOption voice) => voice.id.isNotEmpty)
            .toList(growable: false),
      );
    } on MissingPluginException {
      return const TtsVoiceSnapshot(voices: <TtsVoiceOption>[]);
    }
  }
}

class WordPronunciationTtsClient {
  WordPronunciationTtsClient({MethodChannel nativeChannel = _nativeTtsChannel})
    : _nativeChannel = nativeChannel;

  final MethodChannel _nativeChannel;
  FlutterTts? _flutterTts;
  bool _handlersInitialized = false;
  Completer<void>? _activeSpeakCompleter;

  FlutterTts get _client => _flutterTts ??= FlutterTts();

  Future<void> speakOfflineText(
    String text, {
    String language = 'en-US',
    String engine = '',
    String voice = '',
    double rate = _defaultPronunciationSpeechRate,
    Duration speechTimeout = const Duration(seconds: 8),
  }) async {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.linux) {
      throw const WordPronunciationException();
    }
    if (defaultTargetPlatform != TargetPlatform.android) {
      await speakText(
        text,
        language: language,
        rate: rate,
        speechTimeout: speechTimeout,
      );
      return;
    }
    final bool? success = await _nativeChannel
        .invokeMethod<bool>('speak', <String, Object>{
          'text': text,
          'language': language,
          'engine': engine,
          'voice': voice,
          'rate': rate,
          'offlineOnly': true,
        });
    if (success != true) throw const WordPronunciationException();
  }

  Future<void> speakText(
    String text, {
    String language = 'en-US',
    String engine = '',
    String voice = '',
    double rate = _defaultPronunciationSpeechRate,
    Duration speechTimeout = const Duration(seconds: 8),
  }) async {
    try {
      final bool? success = await _nativeChannel.invokeMethod<bool>(
        'speak',
        <String, Object>{
          'text': text,
          'language': language,
          'engine': engine,
          'voice': voice,
          'rate': rate,
        },
      );
      if (success ?? false) {
        return;
      }
      throw const WordPronunciationException();
    } on MissingPluginException {
      await _speakWithFlutterTts(
        text,
        language: language,
        rate: rate,
        speechTimeout: speechTimeout,
      );
    } on PlatformException {
      throw const WordPronunciationException();
    }
  }

  Future<void> stop() async {
    try {
      final bool? success = await _nativeChannel.invokeMethod<bool>('stop');
      if (success ?? false) return;
      throw const WordPronunciationException();
    } on MissingPluginException {
      _ensureHandlers();
      await _ensureTtsCallSucceeded(_client.stop());
      _completeActiveSpeak();
    } on PlatformException {
      throw const WordPronunciationException();
    }
  }

  Future<void> _speakWithFlutterTts(
    String normalizedText, {
    required String language,
    required double rate,
    required Duration speechTimeout,
  }) async {
    _ensureHandlers();
    if (_activeSpeakCompleter != null) {
      await _ensureTtsCallSucceeded(_client.stop());
    }
    await _ensureLanguageReady(language);
    await _client.setSpeechRate(rate / 2);
    await _client.awaitSpeakCompletion(true);
    final Completer<void> completer = Completer<void>();
    _activeSpeakCompleter = completer;
    final Future<void> speaking = _ensureTtsCallSucceeded(
      _client.speak(normalizedText),
    );
    try {
      // Some platforms do not resolve speak() when stop() is called. The local
      // completion signal lets a stopped narration leave its queue promptly.
      await Future.any<void>(<Future<void>>[
        speaking,
        completer.future,
      ]).timeout(speechTimeout);
    } on TimeoutException {
      await _client.stop();
      throw const WordPronunciationException('设备朗读超时，请重试。');
    } finally {
      if (identical(_activeSpeakCompleter, completer)) {
        _activeSpeakCompleter = null;
      }
    }
  }

  void _ensureHandlers() {
    if (_handlersInitialized) {
      return;
    }
    _handlersInitialized = true;
    _client
      ..setCompletionHandler(_completeActiveSpeak)
      ..setCancelHandler(_completeActiveSpeak)
      ..setErrorHandler((dynamic _) => _completeActiveSpeak());
  }

  void _completeActiveSpeak() {
    final Completer<void>? completer = _activeSpeakCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    completer.complete();
  }

  Future<void> _ensureLanguageReady(String language) async {
    for (int attempt = 0; attempt < _ttsBindRetryAttempts; attempt++) {
      try {
        await _ensureTtsCallSucceeded(_client.setLanguage(language));
        return;
      } on WordPronunciationException {
        if (attempt == _ttsBindRetryAttempts - 1) {
          rethrow;
        }
      } on PlatformException catch (error) {
        if (!_isTransientTtsBindError(error) ||
            attempt == _ttsBindRetryAttempts - 1) {
          rethrow;
        }
      }
      await Future<void>.delayed(_ttsBindRetryDelay);
    }
  }

  bool _isTransientTtsBindError(PlatformException error) {
    final String message = error.message?.toLowerCase() ?? '';
    return message.contains('not bound to tts engine');
  }

  Future<void> _ensureTtsCallSucceeded(Future<dynamic> action) async {
    final dynamic result = await action;
    if (result == false || result == 0) {
      throw const WordPronunciationException();
    }
  }
}
