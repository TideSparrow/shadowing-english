import 'dart:async';

import 'package:common_learn_english/features/player/domain/pronunciation_assessment.dart';
import 'package:common_learn_english/features/settings/data/pronunciation_credentials.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:common_learn_english/features/settings/presentation/settings_screen.dart';
import 'package:common_learn_english/features/settings/presentation/widgets/settings_group_card.dart';
import 'package:common_learn_english/features/shared/data/word_pronunciation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/src/framework.dart' show Override;

class _EmptyCredentialStore implements PronunciationCredentialStore {
  @override
  Future<PronunciationCredentials> read() async =>
      const PronunciationCredentials();

  @override
  Future<void> write(PronunciationCredentials credentials) async {}
}

void main() {
  testWidgets(
    'speech speed menu includes two, two-and-a-half, and three times',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1366, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          pronunciationCredentialStoreProvider.overrideWithValue(
            _EmptyCredentialStore(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final Finder dropdown = find.byWidgetPredicate(
        (Widget widget) =>
            widget is DropdownButton<double> &&
            (widget.items?.any(
                  (DropdownMenuItem<double> item) => item.value == 3,
                ) ??
                false),
      );
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      final DropdownButton<double> control = tester
          .widget<DropdownButton<double>>(dropdown);
      expect(
        control.items!.map((DropdownMenuItem<double> item) => item.value),
        ttsRateOptions,
      );
      control.onChanged!(3);
      await tester.pumpAndSettle();
      expect(container.read(learningSettingsProvider).ttsRate, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('follow-along coaching sits above system settings', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          pronunciationCredentialStoreProvider.overrideWithValue(
            _EmptyCredentialStore(),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final Finder assessment = _section('跟读指导');
    final Finder system = _section('系统');
    expect(
      tester.getTopLeft(assessment).dy,
      lessThan(tester.getTopLeft(system).dy),
    );
    await tester.tap(assessment);
    await tester.pumpAndSettle();
    expect(find.text('申请 API Key').hitTestable(), findsOneWidget);
    expect(find.text('保存密钥'), findsNothing);
    expect(_selectedSection(tester, '跟读指导'), isTrue);
    await tester.tap(system);
    await tester.pumpAndSettle();
    expect(find.text('管理 AI 字幕').hitTestable(), findsOneWidget);
    expect(_selectedSection(tester, '系统'), isTrue);
    await tester.drag(_settingsContent, const Offset(0, 360));
    await tester.pumpAndSettle();
    expect(_selectedSection(tester, '系统'), isFalse);
  });

  testWidgets('narrow settings open the vertical directory on demand', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    expect(_section('系统'), findsNothing);
    await tester.tap(find.text('设置目录'));
    await tester.pumpAndSettle();
    final Finder system = _section('系统');
    await tester.ensureVisible(system);
    await tester.tap(system);
    await tester.pumpAndSettle();
    expect(system, findsNothing);
    expect(find.text('管理 AI 字幕').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'voice preview uses current voice and rate, stops on selection and navigation',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1366, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final List<(String, String, double)> requests =
          <(String, String, double)>[];
      final List<Completer<void>> pending = <Completer<void>>[];
      int stops = 0;
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          ttsEngineSnapshotProvider.overrideWith(
            (Ref ref) async => const TtsEngineSnapshot(
              defaultEngine: '',
              engines: <TtsEngineOption>[],
            ),
          ),
          ttsVoiceSnapshotProvider('').overrideWith(
            (Ref ref) async => const TtsVoiceSnapshot(
              voices: <TtsVoiceOption>[
                TtsVoiceOption(id: 'samantha', label: 'Samantha · en-US · 标准'),
                TtsVoiceOption(id: 'daniel', label: 'Daniel · en-GB · 标准'),
              ],
            ),
          ),
          wordPronunciationServiceProvider.overrideWith((Ref ref) {
            final LearningSettingsState settings = ref.watch(
              learningSettingsProvider,
            );
            Completer<void>? active;
            return WordPronunciationService(
              speakOverride: (String text) {
                requests.add((text, settings.ttsVoice, settings.ttsRate));
                active = Completer<void>();
                pending.add(active!);
                return active!.future;
              },
              stopOverride: () async {
                stops++;
                if (active != null && !active!.isCompleted) active!.complete();
              },
            );
          }),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final Finder button = find.byKey(const Key('tts-voice-preview'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();
      expect(requests.single, (
        'Hello! I have three projects to finish today.',
        '',
        0.75,
      ));
      expect(find.text('停止'), findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(stops, 1);
      expect(find.text('试听'), findsOneWidget);
      container.read(learningSettingsProvider.notifier).setTtsVoice('samantha');
      container.read(learningSettingsProvider.notifier).setTtsRate(1);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();
      expect(requests.last.$2, 'samantha');
      expect(requests.last.$3, 1.0);
      container.read(learningSettingsProvider.notifier).setTtsVoice('daniel');
      await tester.pumpAndSettle();
      expect(stops, 2);
      expect(find.text('试听'), findsOneWidget);
      await tester.tap(button);
      await tester.pump();
      expect(requests.last.$2, 'daniel');
      container.read(learningSettingsProvider.notifier).setTtsRate(0.5);
      await tester.pumpAndSettle();
      expect(stops, 3);
      expect(find.text('试听'), findsOneWidget);
      await tester.tap(button);
      await tester.pump();
      expect(requests.last.$3, 0.5);
      pending.last.complete();
      await tester.pumpAndSettle();
      expect(find.text('试听'), findsOneWidget);
      await tester.tap(button);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(stops, 4);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('voice preview reports a failure and can be retried', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ttsEngineSnapshotProvider.overrideWith(
            (Ref ref) async => const TtsEngineSnapshot(
              defaultEngine: '',
              engines: <TtsEngineOption>[],
            ),
          ),
          ttsVoiceSnapshotProvider('').overrideWith(
            (Ref ref) async =>
                const TtsVoiceSnapshot(voices: <TtsVoiceOption>[]),
          ),
          wordPronunciationServiceProvider.overrideWithValue(
            WordPronunciationService(
              speakOverride: (_) async {
                throw const WordPronunciationException();
              },
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final Finder button = find.byKey(const Key('tts-voice-preview'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('试听失败，请检查设备是否已安装所选英语音色。'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('subtitle letter case can be changed from playback settings', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final Finder dropdown = find.byWidgetPredicate(
      (Widget widget) =>
          widget is DropdownButton<String> &&
          (widget.items?.any(
                (DropdownMenuItem<String> item) => item.value == '句首字母大写',
              ) ??
              false),
    );
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    expect(find.text('全部大写').last, findsOneWidget);
    expect(find.text('句首字母大写').last, findsOneWidget);
    await tester.tap(find.text('全部小写').last);
    await tester.pumpAndSettle();
    expect(container.read(learningSettingsProvider).subtitleLetterCase, '全部小写');
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings screen shows prototype sections', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsWidgets);
    expect(_settingsText('播放'), findsOneWidget);
    expect(find.text('学习').last, findsOneWidget);
    expect(find.text('默认字幕模式'), findsOneWidget);
    expect(find.text('单词高亮样式'), findsOneWidget);
    expect(find.text('单词高亮边框粗细'), findsOneWidget);
    expect(find.text('每日打卡提醒'), findsOneWidget);
    expect(find.text('词典来源'), findsNothing);

    await _scrollToTranslationSettings(tester);

    expect(_settingsText('翻译'), findsOneWidget);
    expect(find.text('翻译来源'), findsOneWidget);
    expect(find.text('API Key').hitTestable(), findsOneWidget);
    expect(find.text('获取模型'), findsWidgets);
    expect(find.text('Model'), findsOneWidget);
    expect(find.text('API Secret'), findsNothing);
    expect(find.text('App ID'), findsNothing);
    expect(find.text('AccessKey ID'), findsNothing);
  });

  testWidgets('settings screen shows AI translation fields for OpenAI', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();

    await _scrollToTranslationSettings(tester);
    await tester.tap(_translationProviderDropdown());
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenAI').last);
    await tester.pumpAndSettle();

    expect(find.text('API Key').hitTestable(), findsOneWidget);
    expect(find.text('获取模型'), findsWidgets);
    expect(find.text('Model'), findsOneWidget);
  });

  testWidgets('settings screen shows DeepSeek as AI provider option', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();

    await _scrollToTranslationSettings(tester);
    await tester.tap(_translationProviderDropdown());
    await tester.pumpAndSettle();

    expect(find.text('DeepSeek').last, findsOneWidget);
  });

  testWidgets('settings screen shows direct translation fields for baidu', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();

    await _scrollToTranslationSettings(tester);
    await tester.tap(_translationProviderDropdown());
    await tester.pumpAndSettle();
    await tester.tap(find.text('百度翻译').last);
    await tester.pumpAndSettle();

    expect(find.text('App ID'), findsOneWidget);
    expect(find.text('Secret'), findsOneWidget);
  });

  testWidgets('settings screen shows fetched models dropdown for AI provider', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          learningSettingsProvider.overrideWith(
            () => _TestLearningSettingsNotifier(
              LearningSettingsState.defaults().copyWith(
                translationProvider: 'DeepSeek',
                translationModel: 'deepseek-v4-flash',
                availableTranslationModels: const <String>[
                  'deepseek-v4-flash',
                  'deepseek-v4-pro',
                ],
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await _scrollToTranslationSettings(tester);

    expect(find.text('模型选择'), findsOneWidget);
    expect(find.text('deepseek-v4-flash'), findsWidgets);
  });

  testWidgets('OpenAI remains in translation but is removed from ASR choices', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();
    await _scrollToTranslationSettings(tester);
    final Finder translation = find.byWidgetPredicate(
      (Widget widget) =>
          widget is DropdownButton<String> &&
          (widget.items?.any(
                (DropdownMenuItem<String> item) => item.value == 'OpenRouter',
              ) ??
              false),
    );
    expect(
      tester
          .widget<DropdownButton<String>>(translation)
          .items!
          .map((DropdownMenuItem<String> item) => item.value),
      contains('OpenAI'),
    );
    final Finder asr = find.byWidgetPredicate(
      (Widget widget) =>
          widget is DropdownButton<String> &&
          (widget.items?.any(
                (DropdownMenuItem<String> item) => item.value == '腾讯云',
              ) ??
              false),
    );
    for (int i = 0; i < 12 && asr.evaluate().isEmpty; i += 1) {
      await tester.drag(_settingsContent, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    expect(
      tester
          .widget<DropdownButton<String>>(asr)
          .items!
          .map((DropdownMenuItem<String> item) => item.value),
      <String>['阿里云百炼', '腾讯云'],
    );
    expect(find.text('获取 ASR 模型'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings links to AI subtitle management', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();
    for (
      int index = 0;
      index < 8 && find.text('管理 AI 字幕').evaluate().isEmpty;
      index++
    ) {
      await tester.drag(_settingsContent, const Offset(0, -500));
      await tester.pumpAndSettle();
    }

    expect(find.text('管理 AI 字幕'), findsOneWidget);
    expect(find.text('导出 AI 字幕'), findsNothing);
  });
}

Future<void> _scrollToTranslationSettings(WidgetTester tester) async {
  await tester.ensureVisible(find.text('翻译来源'));
  await tester.pumpAndSettle();
}

Finder get _settingsContent =>
    find.byKey(const ValueKey<String>('settings-content'));

Finder _settingsText(String text) =>
    find.descendant(of: _settingsContent, matching: find.text(text));

Finder _section(String name) =>
    find.byKey(ValueKey<String>('settings-section-$name'));

bool? _selectedSection(WidgetTester tester, String name) => tester
    .widget<Semantics>(
      find.ancestor(of: _section(name), matching: find.byType(Semantics)).first,
    )
    .properties
    .selected;

Finder _translationProviderDropdown() {
  return find.descendant(
    of: find.ancestor(
      of: find.text('翻译来源'),
      matching: find.byType(SettingsGroupCard),
    ),
    matching: find.byType(DropdownButton<String>),
  );
}

class _TestLearningSettingsNotifier extends LearningSettingsNotifier {
  _TestLearningSettingsNotifier(this._state);

  final LearningSettingsState _state;

  @override
  LearningSettingsState build() => _state;
}
