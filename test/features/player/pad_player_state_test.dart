import 'dart:convert';
import 'dart:ui';

import 'package:common_learn_english/features/library/presentation/library_catalog_provider.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:common_learn_english/features/player/presentation/asr_subtitle_service.dart';
import 'package:common_learn_english/features/player/presentation/pad_landscape_player_screen.dart';
import 'package:common_learn_english/features/player/presentation/player_fullscreen_video_screen.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/widgets/ai_subtitle_generation_progress_dialog.dart';
import 'package:common_learn_english/features/player/presentation/widgets/player_current_line_card.dart';
import 'package:common_learn_english/features/player/presentation/widgets/player_episode_strip.dart';
import 'package:common_learn_english/features/player/presentation/widgets/player_subtitle_list.dart';
import 'package:common_learn_english/features/player/presentation/widgets/player_transcript_panel.dart';
import 'package:common_learn_english/features/player/presentation/widgets/player_video_panel.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:common_learn_english/features/shared/data/word_lookup_service.dart';
import 'package:common_learn_english/features/shared/data/word_pronunciation_service.dart';
import 'package:common_learn_english/features/shared/domain/word_lookup_entry.dart';
import 'package:common_learn_english/features/shared/presentation/word_lookup_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

class _TestLibraryCatalogNotifier extends LibraryCatalogNotifier {
  @override
  List<LibraryCourseData> build() => const <LibraryCourseData>[_testCourse];
}

class _EmptySubtitleLibraryCatalogNotifier extends LibraryCatalogNotifier {
  @override
  List<LibraryCourseData> build() => const <LibraryCourseData>[
    _emptySubtitleCourse,
  ];
}

class _ConfiguredLearningSettingsNotifier extends LearningSettingsNotifier {
  @override
  LearningSettingsState build() {
    return LearningSettingsState.defaults().copyWith(
      translationProvider: 'OpenAI',
      translationApiKey: 'demo-key',
      translationBaseUrl: 'https://api.openai.com/v1',
      translationModel: 'gpt-4o-mini',
    );
  }
}

const LibraryCourseData _testCourse = LibraryCourseData(
  id: 'course-1',
  title: '我的课程',
  description: '测试课程',
  sourceLabel: '本地资源',
  coverImage: '',
  level: 'B1',
  category: '自定义',
  progressPercent: 25,
  totalWords: 12,
  completedEpisodes: 0,
  totalEpisodes: 1,
  lastStudiedStr: '刚刚',
  rating: 4.5,
  episodes: <LibraryEpisodeItem>[
    LibraryEpisodeItem(
      id: 'intern-ep3',
      numberStr: '03',
      title: '第三集',
      durationMinutes: 10,
      hasChineseSubtitles: true,
      hasEnglishSubtitles: true,
      completed: false,
      progressPercent: 25,
      coverImage: '',
      enSubtitleAsset: 'assets/test/player/en.srt',
      cnSubtitleAsset: 'assets/test/player/zh.srt',
    ),
  ],
);

const LibraryCourseData _emptySubtitleCourse = LibraryCourseData(
  id: 'course-empty',
  title: '空字幕课程',
  description: '测试课程',
  sourceLabel: '本地资源',
  coverImage: '',
  level: 'B1',
  category: '自定义',
  progressPercent: 0,
  totalWords: 0,
  completedEpisodes: 0,
  totalEpisodes: 1,
  lastStudiedStr: '刚刚',
  rating: 4.5,
  episodes: <LibraryEpisodeItem>[
    LibraryEpisodeItem(
      id: 'empty-ep',
      numberStr: '01',
      title: '空字幕剧集',
      durationMinutes: 10,
      hasChineseSubtitles: false,
      hasEnglishSubtitles: false,
      completed: false,
      progressPercent: 0,
      coverImage: '',
    ),
  ],
);

const String _englishSubtitle = '''
1
00:00:01,000 --> 00:00:03,000
What are you doing here?

2
00:00:03,500 --> 00:00:06,000
I am practicing English sentence by sentence.
''';

const String _chineseSubtitle = '''
1
00:00:01,000 --> 00:00:03,000
你在这里做什么？

2
00:00:03,500 --> 00:00:06,000
我正在一句一句地练习英语。
''';

const PlayerSubtitleLine _dictionaryLine = PlayerSubtitleLine(
  startTime: '00:01',
  english: 'They found a sanctuary nearby.',
  chinese: '他们在附近找到了一个避难所。',
  startMs: 1000,
  endMs: 3000,
);

void main() {
  testWidgets('each sidebar sentence has a visible loop button', (
    WidgetTester tester,
  ) async {
    int? requestedLineIndex;
    const List<PlayerSubtitleLine> lines = <PlayerSubtitleLine>[
      PlayerSubtitleLine(
        startTime: '00:01',
        english: 'First sentence.',
        chinese: '第一句。',
        startMs: 1000,
        endMs: 2000,
      ),
      PlayerSubtitleLine(
        startTime: '00:03',
        english: 'Second sentence.',
        chinese: '第二句。',
        startMs: 3000,
        endMs: 4000,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: PlayerSubtitleList(
              lines: lines,
              activeIndex: 1,
              subtitleMode: '双语',
              currentWordIndex: 0,
              fontScale: 1,
              highlightWords: false,
              onTapLine: (_) {},
              onCollectWord: (_) {},
              onBookmarkLine: (_) {},
              onLoopFromLine: (int index) => requestedLineIndex = index,
              onDictationLine: (_) {},
              onAiExplain: (_) {},
              loopingLineIndex: 1,
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('subtitle-line-loop-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('subtitle-line-loop-1')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('subtitle-line-loop-0')),
    );
    expect(requestedLineIndex, 0);
  });

  testWidgets('transcript view switch belongs to the right-side list', (
    WidgetTester tester,
  ) async {
    const List<PlayerSubtitleLine> lines = <PlayerSubtitleLine>[
      PlayerSubtitleLine(
        startTime: '00:01',
        english: 'First sentence.',
        chinese: '第一句。',
        startMs: 1000,
        endMs: 2000,
      ),
      PlayerSubtitleLine(
        startTime: '00:03',
        english: 'Second sentence.',
        chinese: '第二句。',
        startMs: 3000,
        endMs: 4000,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: PlayerTranscriptPanel(
              lines: lines,
              activeIndex: 0,
              subtitleMode: '双语',
              currentWordIndex: 0,
              fontScale: 1,
              highlightWords: false,
              subtitleWordHighlightStyle: '绿色填充',
              onTapLine: (_) {},
              onCollectWord: (_) {},
              onBookmarkLine: (_) {},
              onLoopFromLine: (_) {},
              onDictationLine: (_) {},
              onAiExplain: (_) {},
              isPlaying: false,
              onTogglePlaying: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('完整'), findsOneWidget);
    expect(
      tester
          .widget<PlayerSubtitleList>(find.byType(PlayerSubtitleList))
          .showCurrentOnly,
      isFalse,
    );

    await tester.tap(find.text('单句'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<PlayerSubtitleList>(find.byType(PlayerSubtitleList))
          .showCurrentOnly,
      isTrue,
    );
  });

  testWidgets('subtitle actions can regenerate only the selected AI line', (
    WidgetTester tester,
  ) async {
    int? regeneratedIndex;
    const PlayerSubtitleLine line = PlayerSubtitleLine(
      startTime: '00:01',
      english: 'Wrong sentence.',
      chinese: '错误的句子。',
      startMs: 1000,
      endMs: 2500,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: PlayerSubtitleList(
              lines: const <PlayerSubtitleLine>[line],
              activeIndex: 0,
              subtitleMode: '双语',
              currentWordIndex: 0,
              fontScale: 1,
              highlightWords: false,
              onTapLine: (_) {},
              onCollectWord: (_) {},
              onBookmarkLine: (_) {},
              onLoopFromLine: (_) {},
              onDictationLine: (_) {},
              onAiExplain: (_) {},
              onRegenerateAiLine: (int index) async {
                regeneratedIndex = index;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    expect(find.text('AI 重新生成当前句'), findsOneWidget);
    expect(find.text('只替换这一句，失败时保留原句'), findsOneWidget);
    await tester.ensureVisible(find.text('AI 重新生成当前句'));
    await tester.tap(find.text('AI 重新生成当前句'));
    await tester.pumpAndSettle();
    expect(regeneratedIndex, 0);
  });

  testWidgets('episode strip opens picker and returns selected episode', (
    WidgetTester tester,
  ) async {
    const List<LibraryEpisodeItem> episodes = <LibraryEpisodeItem>[
      LibraryEpisodeItem(
        id: 'episode-1',
        numberStr: '01',
        title: '第一集',
        durationMinutes: 10,
        hasChineseSubtitles: true,
        hasEnglishSubtitles: true,
        completed: false,
        progressPercent: 0,
        coverImage: '',
      ),
      LibraryEpisodeItem(
        id: 'episode-2',
        numberStr: '02',
        title: '第二集',
        durationMinutes: 10,
        hasChineseSubtitles: true,
        hasEnglishSubtitles: true,
        completed: false,
        progressPercent: 0,
        coverImage: '',
      ),
    ];
    String? selectedId;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerEpisodeStrip(
            episodes: episodes,
            activeEpisodeId: 'episode-1',
            onOpenEpisode: (LibraryEpisodeItem episode) {
              selectedId = episode.id;
            },
          ),
        ),
      ),
    );

    expect(find.text('第一集'), findsOneWidget);

    await tester.tap(find.text('查看全部'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第 02 集'));
    await tester.pumpAndSettle();

    expect(selectedId, 'episode-2');
  });

  testWidgets('episode strip starts at the active episode', (
    WidgetTester tester,
  ) async {
    final List<LibraryEpisodeItem> episodes = List<LibraryEpisodeItem>.generate(
      5,
      (int index) => LibraryEpisodeItem(
        id: 'episode-$index',
        numberStr: '${index + 1}'.padLeft(2, '0'),
        title: '第${index + 1}集',
        durationMinutes: 10,
        hasChineseSubtitles: true,
        hasEnglishSubtitles: true,
        completed: false,
        progressPercent: 0,
        coverImage: '',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerEpisodeStrip(
            episodes: episodes,
            activeEpisodeId: 'episode-4',
            onOpenEpisode: (LibraryEpisodeItem _) {},
          ),
        ),
      ),
    );

    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      greaterThan(0),
    );
  });

  testWidgets('episode strip supports mouse dragging', (
    WidgetTester tester,
  ) async {
    final List<LibraryEpisodeItem> episodes = List<LibraryEpisodeItem>.generate(
      5,
      (int index) => LibraryEpisodeItem(
        id: 'episode-$index',
        numberStr: '${index + 1}'.padLeft(2, '0'),
        title: '第${index + 1}集',
        durationMinutes: 10,
        hasChineseSubtitles: true,
        hasEnglishSubtitles: true,
        completed: false,
        progressPercent: 0,
        coverImage: '',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerEpisodeStrip(
            episodes: episodes,
            activeEpisodeId: 'episode-0',
            onOpenEpisode: (LibraryEpisodeItem _) {},
          ),
        ),
      ),
    );

    await tester.dragFrom(
      tester.getCenter(find.byType(ListView)),
      const Offset(-200, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      greaterThan(0),
    );
  });

  test('player state can play video-only lesson without subtitles', () {
    final PlayerMockState state = PlayerMockState()
      ..loadLines(const <PlayerSubtitleLine>[])
      ..togglePlaying(allowWithoutLines: true);

    expect(state.isPlaying, isTrue);
  });

  testWidgets('player controls update speed, subtitle mode, and letter case', (
    WidgetTester tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (ByteData? message) async {
          final String key = utf8.decode(message!.buffer.asUint8List());
          if (key == 'assets/test/player/en.srt') {
            return ByteData.sublistView(utf8.encode(_englishSubtitle));
          }
          if (key == 'assets/test/player/zh.srt') {
            return ByteData.sublistView(utf8.encode(_chineseSubtitle));
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null);
    });

    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        // ignore: always_specify_types
        overrides: [
          libraryCatalogProvider.overrideWith(_TestLibraryCatalogNotifier.new),
        ],
        child: const MaterialApp(
          home: PadLandscapePlayerScreen(episodeId: 'intern-ep3'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的课程'), findsOneWidget);
    expect(find.text('第 03 集'), findsOneWidget);
    expect(find.text('0.8'), findsOneWidget);
    expect(find.text('What are you doing here?'), findsNothing);

    await tester.tap(find.text('0.8'));
    await tester.pumpAndSettle();
    expect(_hasCheckedMenuItem(tester, '0.8×'), isTrue);
    await tester.tap(find.text('1.0×').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('1.0×'), findsWidgets);

    await tester.tap(find.byIcon(Icons.skip_next_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('practicing'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey<String>('scrubber-dot-0')));
    await tester.pumpAndSettle();

    expect(find.text('doing'), findsWidgets);

    await tester.tap(find.text('双语'));
    await tester.pumpAndSettle();
    expect(_hasCheckedMenuItem(tester, '双语'), isTrue);
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('单英'), warnIfMissed: false);
    await tester.pumpAndSettle();

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(PadLandscapePlayerScreen)),
    );
    expect(container.read(learningSettingsProvider).subtitleMode, '单英');

    await tester.tap(find.byTooltip('字幕模式'));
    await tester.pumpAndSettle();
    expect(find.text('全部大写'), findsNothing);
    expect(find.text('全部小写'), findsNothing);
    await tester.tap(find.text('单英').last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('英文字幕大小写'), findsNothing);
    container.read(learningSettingsProvider.notifier).setSubtitleLetterCase('全部大写');
    await tester.pumpAndSettle();
    expect(container.read(learningSettingsProvider).subtitleLetterCase, '全部大写');
    expect(find.text('DOING'), findsWidgets);
    final double previousFontSize = tester.widget<Text>(
      find.descendant(of: find.byType(PlayerVideoPanel), matching: find.text('DOING')).first,
    ).style!.fontSize!;
    await tester.tap(find.byTooltip('字幕大小'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('最大（200%）'));
    await tester.tap(find.text('最大（200%）'));
    await tester.pumpAndSettle();
    expect(container.read(learningSettingsProvider).fontSize, '最大');
    expect(tester.widget<PlayerVideoPanel>(find.byType(PlayerVideoPanel)).fontScale, 2);
    expect(tester.widget<PlayerSubtitleList>(find.byType(PlayerSubtitleList)).fontScale, 2);
    expect(tester.widget<Text>(
      find.descendant(of: find.byType(PlayerVideoPanel), matching: find.text('DOING')).first,
    ).style!.fontSize, previousFontSize * 2);
    await tester.tap(find.byTooltip('字幕大小'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('中（100%）'));
    await tester.pumpAndSettle();

    final PadLandscapePlayerScreenState playerState = tester.state(
      find.byType(PadLandscapePlayerScreen),
    );
    expect(playerState.state.isPlaying, isFalse);
    expect(
      playerState.debugTranscriptReaderProgress.value.subtitleLetterCase,
      '全部大写',
    );
    expect(
      tester
          .widget<PlayerVideoPanel>(find.byType(PlayerVideoPanel))
          .subtitleLetterCase,
      '全部大写',
    );
    expect(
      tester
          .widget<PlayerSubtitleList>(find.byType(PlayerSubtitleList))
          .subtitleLetterCase,
      '全部大写',
    );
    expect(find.byTooltip('英文字幕大小写'), findsNothing);
    container.read(learningSettingsProvider.notifier).setSubtitleLetterCase('保留原样');
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.mic_none_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('加入听写练习'));
    await tester.pumpAndSettle();

    expect(find.text('已加入听写练习'), findsOneWidget);
  });


  for (final Size size in <Size>[const Size(390, 844), const Size(844, 390)]) {
    testWidgets('subtitle size can change in a small fullscreen player at $size', (WidgetTester tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final PlayerMockState state = PlayerMockState()..loadLines(const <PlayerSubtitleLine>[_dictionaryLine]);
      await tester.pumpWidget(MaterialApp(
        home: PlayerFullscreenVideoScreen(
          playerState: state,
          highlightWords: true,
          isMuted: false,
          volumeLevel: 1,
          onTogglePlaying: state.togglePlaying,
          onPreviousLine: state.previousLine,
          onReplayLine: () => state.selectLine(0),
          onNextLine: state.nextLine,
          onSeekBackward: () {},
          onSeekForward: () {},
          onSelectLine: state.selectLine,
          onSeek: (_) {},
          onSpeedSelected: state.selectSpeed,
          onSelectSubtitleMode: state.setSubtitleMode,
          onSelectFontSize: (_) {},
          onToggleShadowing: state.toggleShadowing,
          onToggleLoop: state.toggleLoop,
          onToggleMuted: () {},
          onVolumeChanged: (_) {},
          onSubtitleLookupOpen: () {},
          onCollectWord: (_) {},
          episodes: const <LibraryEpisodeItem>[],
          activeEpisodeId: 'episode-1',
          onExit: () {},
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('字幕大小'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('最大（200%）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('最大（200%）'));
      await tester.pumpAndSettle();
      expect(tester.widget<PlayerVideoPanel>(find.byType(PlayerVideoPanel)).fontScale, 2);
      expect(find.byTooltip('英文字幕大小写'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('player shows real empty state when subtitles are missing', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        // ignore: always_specify_types
        overrides: [
          libraryCatalogProvider.overrideWith(
            _EmptySubtitleLibraryCatalogNotifier.new,
          ),
        ],
        child: const MaterialApp(
          home: PadLandscapePlayerScreen(episodeId: 'empty-ep'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前剧集没有可用字幕或视频'), findsOneWidget);
    expect(find.text('What are you doing here?'), findsNothing);
  });

  testWidgets('video-only controls show AI subtitle generation action', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    bool generated = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              Expanded(
                child: PlayerVideoPanel(
                  line: const PlayerSubtitleLine(
                    startTime: '00:00',
                    english: '',
                    chinese: '',
                    startMs: 0,
                    endMs: 1,
                  ),
                  isPlaying: false,
                  subtitleMode: '隐藏',
                  subtitleModes: const <String>['隐藏'],
                  speed: '1.25×',
                  isShadowing: false,
                  isLooping: false,
                  isMuted: false,
                  volumeLevel: 1,
                  onTogglePlaying: () {},
                  onPreviousLine: () {},
                  onReplayLine: () {},
                  onNextLine: () {},
                  onSeekBackward: () {},
                  onSeekForward: () {},
                  activeIndex: 0,
                  totalLines: 0,
                  onSelectLine: (_) {},
                  onSeek: (_) {},
                  onSpeedSelected: (_) {},
                  onSelectSubtitleMode: (_) {},
                  onToggleShadowing: () {},
                  onToggleLoop: () {},
                  onToggleMuted: () {},
                  onVolumeChanged: (_) {},
                  onToggleFullscreen: () {},
                  showAiGenerateSubtitles: true,
                  onGenerateAiSubtitles: () {
                    generated = true;
                  },
                ),
              ),
              SizedBox(
                height: 220,
                child: PlayerSubtitleList(
                  lines: const <PlayerSubtitleLine>[],
                  activeIndex: 0,
                  subtitleMode: '隐藏',
                  currentWordIndex: 0,
                  fontScale: 1,
                  highlightWords: true,
                  onTapLine: (_) {},
                  onCollectWord: (_) {},
                  onBookmarkLine: (_) {},
                  onLoopFromLine: (_) {},
                  onDictationLine: (_) {},
                  onAiExplain: (_) {},
                  showAiGenerateSubtitles: true,
                  onGenerateAiSubtitles: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1.25'), findsOneWidget);
    expect(find.text('AI生成可跟读的词级同步字幕'), findsOneWidget);
    expect(find.byTooltip('更多控制'), findsNothing);
    expect(find.byTooltip('AI生成可跟读的词级同步字幕'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byTooltip('AI生成可跟读的词级同步字幕'),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pump();

    expect(generated, isTrue);
  });

  testWidgets('local subtitles keep AI generation progress in a modal', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<AsrSubtitleProgress> progress =
        ValueNotifier<AsrSubtitleProgress>(
          const AsrSubtitleProgress(completedChunks: 0, totalChunks: 0),
        );
    addTearDown(progress.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => FilledButton(
            onPressed: () => showAiSubtitleGenerationProgressDialog(
              context: context,
              progress: progress,
            ),
            child: const Text('生成'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('生成'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('正在生成 AI 词级字幕'), findsOneWidget);
    expect(find.text('正在准备音频...'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    progress.value = const AsrSubtitleProgress(
      completedChunks: 1,
      totalChunks: 2,
      previewText: 'Recognized preview.',
    );
    await tester.pump();
    expect(find.text('正在生成词级同步字幕 1/2'), findsOneWidget);
    expect(find.text('Recognized preview.'), findsOneWidget);

    progress.value = const AsrSubtitleProgress(
      completedChunks: 2,
      totalChunks: 2,
      phase: AsrSubtitlePhase.translating,
      completedTranslations: 1,
      totalTranslations: 3,
    );
    await tester.pump();
    expect(find.text('正在翻译中文字幕 1/3 句'), findsOneWidget);
    expect(find.text('正在生成词级同步字幕 1/2'), findsNothing);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      closeTo(1 / 3, 0.001),
    );

    progress.value = const AsrSubtitleProgress(
      completedChunks: 2,
      totalChunks: 2,
      phase: AsrSubtitlePhase.finalizing,
    );
    await tester.pump();
    expect(find.text('正在校验并保存字幕...'), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(find.text('正在生成 AI 词级字幕'), findsOneWidget);
  });

  testWidgets('video subtitle word is boxed when highlighting is enabled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 960,
            height: 540,
            child: PlayerVideoPanel(
              line: const PlayerSubtitleLine(
                startTime: '00:22',
                english: 'It is raining today.',
                chinese: '',
                startMs: 22000,
                endMs: 25000,
                words: <PlayerSubtitleWord>[
                  PlayerSubtitleWord(text: 'It', startMs: 22000, endMs: 22400),
                  PlayerSubtitleWord(text: 'is', startMs: 22400, endMs: 22800),
                  PlayerSubtitleWord(
                    text: 'raining',
                    startMs: 22800,
                    endMs: 23800,
                  ),
                ],
              ),
              isPlaying: true,
              subtitleMode: '单英',
              subtitleModes: const <String>['单英'],
              currentWordIndex: 2,
              highlightWords: true,
              speed: '1.0×',
              isShadowing: false,
              isLooping: false,
              isMuted: false,
              volumeLevel: 1,
              onTogglePlaying: () {},
              onPreviousLine: () {},
              onReplayLine: () {},
              onNextLine: () {},
              onSeekBackward: () {},
              onSeekForward: () {},
              activeIndex: 0,
              totalLines: 1,
              onSelectLine: (_) {},
              onSeek: (_) {},
              onSpeedSelected: (_) {},
              onSelectSubtitleMode: (_) {},
              onToggleShadowing: () {},
              onToggleLoop: () {},
              onToggleMuted: () {},
              onVolumeChanged: (_) {},
              onToggleFullscreen: () {},
            ),
          ),
        ),
      ),
    );

    final Container highlighted = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('video-subtitle-word-2')),
        matching: find.byType(Container),
      ),
    );
    final BoxDecoration decoration = highlighted.decoration! as BoxDecoration;
    expect(decoration.border, isNotNull);
    expect(decoration.color, Colors.transparent);
    final Text highlightedText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('video-subtitle-word-2')),
        matching: find.byType(Text),
      ),
    );
    expect(highlightedText.style!.color, Colors.white);
    expect(highlightedText.style!.shadows, isNotEmpty);
  });

  testWidgets('video subtitle word supports yellow highlight style', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerVideoPanel(
            line: const PlayerSubtitleLine(
              startTime: '00:22',
              startMs: 22000,
              endMs: 24000,
              english: 'It is a quiet afternoon.',
              chinese: '',
              words: <PlayerSubtitleWord>[
                PlayerSubtitleWord(text: 'It', startMs: 22000, endMs: 22400),
              ],
            ),
            isPlaying: true,
            speed: '1.0×',
            subtitleMode: '单英',
            subtitleModes: const <String>['单英'],
            highlightWords: true,
            subtitleWordHighlightStyle: '黄色填充',
            isShadowing: false,
            isLooping: false,
            isMuted: false,
            volumeLevel: 1,
            onTogglePlaying: () {},
            onPreviousLine: () {},
            onReplayLine: () {},
            onNextLine: () {},
            onSeekBackward: () {},
            onSeekForward: () {},
            activeIndex: 0,
            totalLines: 1,
            onSelectLine: (_) {},
            onSeek: (_) {},
            onSpeedSelected: (_) {},
            onSelectSubtitleMode: (_) {},
            onToggleShadowing: () {},
            onToggleLoop: () {},
            onToggleMuted: () {},
            onVolumeChanged: (_) {},
            onToggleFullscreen: () {},
          ),
        ),
      ),
    );

    final Container highlighted = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('video-subtitle-word-0')),
        matching: find.byType(Container),
      ),
    );
    final BoxDecoration decoration = highlighted.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xFFFFF4C2));
  });

  testWidgets('video subtitle word opens lookup popup and pauses playback', (
    WidgetTester tester,
  ) async {
    bool paused = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 960,
              height: 540,
              child: PlayerVideoPanel(
                line: const PlayerSubtitleLine(
                  startTime: '00:22',
                  english: 'It is raining today.',
                  chinese: '',
                  startMs: 22000,
                  endMs: 25000,
                ),
                isPlaying: true,
                subtitleMode: '单英',
                subtitleModes: const <String>['单英'],
                speed: '1.0×',
                isShadowing: false,
                isLooping: false,
                isMuted: false,
                volumeLevel: 1,
                onTogglePlaying: () {},
                onPreviousLine: () {},
                onReplayLine: () {},
                onNextLine: () {},
                onSeekBackward: () {},
                onSeekForward: () {},
                activeIndex: 0,
                totalLines: 1,
                onSelectLine: (_) {},
                onSeek: (_) {},
                onSpeedSelected: (_) {},
                onSelectSubtitleMode: (_) {},
                onToggleShadowing: () {},
                onToggleLoop: () {},
                onToggleMuted: () {},
                onVolumeChanged: (_) {},
                onToggleFullscreen: () {},
                onSubtitleLookupOpen: () {
                  paused = true;
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(const Offset(80, 80));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('video-subtitle-word-2')),
    );
    await tester.pump();

    expect(paused, isTrue);
    expect(find.byType(WordLookupPopupCard), findsOneWidget);
  });

  testWidgets('fullscreen controls refresh from live player state', (
    WidgetTester tester,
  ) async {
    final PlayerMockState state = PlayerMockState()
      ..loadLines(const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Hello there.',
          chinese: '',
          startMs: 1000,
          endMs: 2500,
        ),
        PlayerSubtitleLine(
          startTime: '00:03',
          english: 'Second line.',
          chinese: '',
          startMs: 3000,
          endMs: 4500,
        ),
      ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: PlayerFullscreenVideoScreen(
          playerState: state,
          highlightWords: true,
          isMuted: false,
          volumeLevel: 1,
          onTogglePlaying: state.togglePlaying,
          onPreviousLine: state.previousLine,
          onReplayLine: () => state.selectLine(state.activeLineIndex),
          onNextLine: state.nextLine,
          onSeekBackward: () {},
          onSeekForward: () {},
          onSelectLine: state.selectLine,
          onSeek: (_) {},
          onSpeedSelected: state.selectSpeed,
          onSelectSubtitleMode: state.setSubtitleMode,
          onToggleShadowing: state.toggleShadowing,
          onToggleLoop: state.toggleLoop,
          onToggleMuted: () {},
          onVolumeChanged: (_) {},
          onSubtitleLookupOpen: () {},
          onCollectWord: (_) {},
          episodes: const <LibraryEpisodeItem>[],
          activeEpisodeId: 'episode-1',
          onExit: () {},
        ),
      ),
    );

    expect(tester.getTopLeft(find.byIcon(Icons.arrow_back_rounded)).dx, 20);
    expect(tester.getTopLeft(find.byIcon(Icons.arrow_back_rounded)).dy, 52);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    await tester.tap(find.text('0.8'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.5×').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('1.5'), findsOneWidget);

    state
      ..isPlaying = true
      ..syncWithTimestamp(3200);
    await tester.pump(state.playbackTickDuration);
    expect(find.text('Second'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 180));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey<String>('fullscreen-back-control')),
          )
          .opacity,
      0,
    );
  });

  testWidgets('fullscreen hides stale subtitle between cues', (
    WidgetTester tester,
  ) async {
    final PlayerMockState state = PlayerMockState()
      ..loadLines(const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Hello there.',
          chinese: '',
          startMs: 1000,
          endMs: 2500,
        ),
        PlayerSubtitleLine(
          startTime: '00:05',
          english: 'Second line.',
          chinese: '',
          startMs: 5000,
          endMs: 6500,
        ),
      ])
      ..syncWithTimestamp(3500);

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerFullscreenVideoScreen(
          playerState: state,
          highlightWords: true,
          isMuted: false,
          volumeLevel: 1,
          onTogglePlaying: state.togglePlaying,
          onPreviousLine: state.previousLine,
          onReplayLine: () => state.selectLine(state.activeLineIndex),
          onNextLine: state.nextLine,
          onSeekBackward: () {},
          onSeekForward: () {},
          onSelectLine: state.selectLine,
          onSeek: (_) {},
          onSpeedSelected: state.selectSpeed,
          onSelectSubtitleMode: state.setSubtitleMode,
          onToggleShadowing: state.toggleShadowing,
          onToggleLoop: state.toggleLoop,
          onToggleMuted: () {},
          onVolumeChanged: (_) {},
          onSubtitleLookupOpen: () {},
          onCollectWord: (_) {},
          episodes: const <LibraryEpisodeItem>[],
          activeEpisodeId: 'episode-1',
          onExit: () {},
        ),
      ),
    );

    expect(find.text('Hello'), findsNothing);
    expect(find.text('Second'), findsNothing);
  });

  testWidgets('fullscreen opens the subtitle list panel', (
    WidgetTester tester,
  ) async {
    final PlayerMockState state = PlayerMockState()
      ..loadLines(const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Hello there.',
          chinese: '',
          startMs: 1000,
          endMs: 2500,
        ),
      ]);

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerFullscreenVideoScreen(
          playerState: state,
          highlightWords: true,
          isMuted: false,
          volumeLevel: 1,
          onTogglePlaying: state.togglePlaying,
          onPreviousLine: state.previousLine,
          onReplayLine: () => state.selectLine(state.activeLineIndex),
          onNextLine: state.nextLine,
          onSeekBackward: () {},
          onSeekForward: () {},
          onSelectLine: state.selectLine,
          onSeek: (_) {},
          onSpeedSelected: state.selectSpeed,
          onSelectSubtitleMode: state.setSubtitleMode,
          onToggleShadowing: state.toggleShadowing,
          onToggleLoop: state.toggleLoop,
          onToggleMuted: () {},
          onVolumeChanged: (_) {},
          onSubtitleLookupOpen: () {},
          onCollectWord: (_) {},
          episodes: const <LibraryEpisodeItem>[],
          activeEpisodeId: 'episode-1',
          onExit: () {},
        ),
      ),
    );

    expect(find.text('逐句精听'), findsNothing);
    await tester.tap(find.byIcon(Icons.subtitles_rounded));
    await tester.pump();
    expect(find.text('逐句精听'), findsOneWidget);
  });

  testWidgets(
    'fullscreen subtitle controls sync mode and case without reopening',
    (WidgetTester tester) async {
      final ProviderContainer settings = ProviderContainer();
      addTearDown(settings.dispose);
      final PlayerMockState state = PlayerMockState()
        ..loadLines(const <PlayerSubtitleLine>[
          PlayerSubtitleLine(
            startTime: '00:01',
            english: 'Hello there.',
            chinese: '你好。',
            startMs: 1000,
            endMs: 2500,
          ),
        ])
        ..setSubtitleMode('双语')
        ..selectLine(0);

      await tester.pumpWidget(
        MaterialApp(
          home: PlayerFullscreenVideoScreen(
            playerState: state,
            highlightWords: true,
            isMuted: false,
            volumeLevel: 1,
            onTogglePlaying: state.togglePlaying,
            onPreviousLine: state.previousLine,
            onReplayLine: () => state.selectLine(state.activeLineIndex),
            onNextLine: state.nextLine,
            onSeekBackward: () {},
            onSeekForward: () {},
            onSelectLine: state.selectLine,
            onSeek: (_) {},
            onSpeedSelected: state.selectSpeed,
            onSelectSubtitleMode: state.setSubtitleMode,
            embeddedSubtitleTracks: const <SubtitleTrack>[
              SubtitleTrack('1', 'Embedded', 'eng'),
            ],
            onSelectEmbeddedSubtitle: (_) => state.setSubtitleMode('隐藏'),
            onSelectFontSize: settings.read(learningSettingsProvider.notifier).setFontSize,
            onSelectSubtitleLetterCase: settings
                .read(learningSettingsProvider.notifier)
                .setSubtitleLetterCase,
            onToggleShadowing: state.toggleShadowing,
            onToggleLoop: state.toggleLoop,
            onToggleMuted: () {},
            onVolumeChanged: (_) {},
            onSubtitleLookupOpen: () {},
            onCollectWord: (_) {},
            episodes: const <LibraryEpisodeItem>[],
            activeEpisodeId: 'episode-1',
            onExit: () {},
          ),
        ),
      );

      await tester.tap(find.text('双语'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('单英').last, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('单英'), findsOneWidget);
      expect(state.subtitleMode, '单英');
      await tester.tap(find.byTooltip('英文字幕大小写'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('全部小写').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部小写').last);
      await tester.pumpAndSettle();
      expect(
        settings.read(learningSettingsProvider).subtitleLetterCase,
        '全部小写',
      );
      expect(find.text('hello'), findsOneWidget);
      expect(
        tester
            .widget<PlayerVideoPanel>(find.byType(PlayerVideoPanel))
            .subtitleLetterCase,
        '全部小写',
      );
      await tester.tap(find.byIcon(Icons.subtitles_rounded));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PlayerSubtitleList>(find.byType(PlayerSubtitleList))
            .subtitleLetterCase,
        '全部小写',
      );
      expect(find.text('hello'), findsNWidgets(2));
      await tester.tap(find.byTooltip('英文字幕大小写'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('全部小写').last);
      expect(_hasCheckedMenuItem(tester, '全部小写'), isTrue);
      await tester.tap(find.text('句首字母大写').last);
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsNWidgets(2));

      await tester.tap(find.byTooltip('字幕模式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('英语 · Embedded').last);
      await tester.pumpAndSettle();
      expect(find.byTooltip('英文字幕大小写'), findsNothing);
      expect(find.byTooltip('字幕大小'), findsOneWidget);
      await tester.tap(find.byTooltip('字幕大小'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('超大（170%）'));
      await tester.tap(find.text('超大（170%）'));
      await tester.pumpAndSettle();
      expect(settings.read(learningSettingsProvider).fontSize, '超大');
      expect(tester.widget<PlayerVideoPanel>(find.byType(PlayerVideoPanel)).fontScale, 1.7);
      expect(tester.widget<PlayerSubtitleList>(find.byType(PlayerSubtitleList)).fontScale, 1.7);


      await tester.tap(find.byTooltip('字幕模式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('单英').last);
      await tester.pumpAndSettle();
      expect(find.byTooltip('英文字幕大小写'), findsOneWidget);
      expect(
        settings.read(learningSettingsProvider).subtitleLetterCase,
        '句首字母大写',
      );
    },
  );

  testWidgets('active subtitle word is boxed when highlighting is enabled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 260,
            child: PlayerSubtitleList(
              lines: const <PlayerSubtitleLine>[
                PlayerSubtitleLine(
                  startTime: '00:22',
                  english: 'It is raining today.',
                  chinese: '',
                  startMs: 22000,
                  endMs: 25000,
                  words: <PlayerSubtitleWord>[
                    PlayerSubtitleWord(
                      text: 'It',
                      startMs: 22000,
                      endMs: 22400,
                    ),
                    PlayerSubtitleWord(
                      text: 'is',
                      startMs: 22400,
                      endMs: 22800,
                    ),
                    PlayerSubtitleWord(
                      text: 'raining',
                      startMs: 22800,
                      endMs: 23800,
                    ),
                    PlayerSubtitleWord(
                      text: 'today.',
                      startMs: 23800,
                      endMs: 25000,
                    ),
                  ],
                ),
              ],
              activeIndex: 0,
              subtitleMode: '单英',
              currentWordIndex: 2,
              fontScale: 1,
              highlightWords: true,
              subtitleWordHighlightStyle: '黄色填充',
              onTapLine: (_) {},
              onCollectWord: (_) {},
              onBookmarkLine: (_) {},
              onLoopFromLine: (_) {},
              onDictationLine: (_) {},
              onAiExplain: (_) {},
            ),
          ),
        ),
      ),
    );

    final Container wordBox = tester.widget<Container>(
      find
          .ancestor(of: find.text('raining'), matching: find.byType(Container))
          .first,
    );
    final BoxDecoration decoration = wordBox.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xFFFFF4C2));
    expect(decoration.border, isNotNull);
    expect(decoration.border!.top.color, const Color(0xFFFFC107));
  });

  testWidgets('subtitle word is not boxed without word timestamps', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 260,
            child: PlayerSubtitleList(
              lines: const <PlayerSubtitleLine>[
                PlayerSubtitleLine(
                  startTime: '00:22',
                  english: 'It is raining today.',
                  chinese: '',
                  startMs: 22000,
                  endMs: 25000,
                ),
              ],
              activeIndex: 0,
              subtitleMode: '单英',
              currentWordIndex: 2,
              fontScale: 1,
              highlightWords: true,
              onTapLine: (_) {},
              onCollectWord: (_) {},
              onBookmarkLine: (_) {},
              onLoopFromLine: (_) {},
              onDictationLine: (_) {},
              onAiExplain: (_) {},
            ),
          ),
        ),
      ),
    );

    final Container wordBox = tester.widget<Container>(
      find
          .ancestor(of: find.text('raining'), matching: find.byType(Container))
          .first,
    );
    final BoxDecoration decoration = wordBox.decoration! as BoxDecoration;
    expect(decoration.border!.top.color, Colors.transparent);
  });

  testWidgets('AI subtitle empty state shows generation progress', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerSubtitleList(
            lines: const <PlayerSubtitleLine>[],
            activeIndex: 0,
            subtitleMode: '完整列表',
            currentWordIndex: 0,
            fontScale: 1,
            highlightWords: true,
            onTapLine: (_) {},
            onCollectWord: (_) {},
            onBookmarkLine: (_) {},
            onLoopFromLine: (_) {},
            onDictationLine: (_) {},
            onAiExplain: (_) {},
            showAiGenerateSubtitles: true,
            generatingAiSubtitles: true,
            aiSubtitleProgressValue: 0.5,
            aiSubtitleProgressText: '正在生成字幕 1/2',
            onGenerateAiSubtitles: () {},
          ),
        ),
      ),
    );

    expect(find.text('正在生成字幕 1/2'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('current line word card shows english usage explanation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        // ignore: always_specify_types
        overrides: [
          learningSettingsProvider.overrideWith(
            _ConfiguredLearningSettingsNotifier.new,
          ),
          wordLookupServiceProvider.overrideWith(
            (Ref ref) => WordLookupService(
              remoteLookupOverride:
                  ({
                    required String rawWord,
                    String? contextSentence,
                    required LearningSettingsState settings,
                  }) async {
                    return const WordLookupEntry(
                      word: 'Sanctuary',
                      phonetic: '/test/',
                      type: 'noun',
                      definitionEn:
                          'A place of safety, refuge, or holy protection; a nature reserve.',
                      usageEn:
                          'Use sanctuary for a place that feels protected, peaceful, or sheltered from danger.',
                      exampleSentenceEn:
                          'The small island became a sanctuary for rare birds.',
                      definitionCn: '避难所；圣所；庇护所',
                      sourceLabel: 'API',
                    );
                  },
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: PlayerCurrentLineCard(
              line: _dictionaryLine,
              subtitleMode: '双语',
              currentWordIndex: 0,
              fontScale: 1,
              highlightWords: true,
              onBookmark: () {},
              onCollectWord: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('sanctuary'));
    await tester.pumpAndSettle();

    expect(find.textContaining('holy protection'), findsOneWidget);
    expect(find.text('They found a sanctuary nearby.'), findsOneWidget);
    expect(
      find.text('The small island became a sanctuary for rare birds.'),
      findsOneWidget,
    );
    expect(find.text('避难所；圣所；庇护所'), findsOneWidget);
  });

  testWidgets('subtitle popup shows english usage explanation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        // ignore: always_specify_types
        overrides: [
          learningSettingsProvider.overrideWith(
            _ConfiguredLearningSettingsNotifier.new,
          ),
          wordLookupServiceProvider.overrideWith(
            (Ref ref) => WordLookupService(
              remoteLookupOverride:
                  ({
                    required String rawWord,
                    String? contextSentence,
                    required LearningSettingsState settings,
                  }) async {
                    return const WordLookupEntry(
                      word: 'Sanctuary',
                      phonetic: '/test/',
                      type: 'noun',
                      definitionEn:
                          'A place of safety, refuge, or holy protection; a nature reserve.',
                      usageEn:
                          'Use sanctuary for a place that feels protected, peaceful, or sheltered from danger.',
                      exampleSentenceEn:
                          'The small island became a sanctuary for rare birds.',
                      definitionCn: '避难所；圣所；庇护所',
                      sourceLabel: 'API',
                    );
                  },
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: PlayerSubtitleList(
              lines: const <PlayerSubtitleLine>[_dictionaryLine],
              activeIndex: 0,
              subtitleMode: '双语',
              currentWordIndex: 0,
              fontScale: 1,
              highlightWords: true,
              onTapLine: (_) {},
              onCollectWord: (_) {},
              onBookmarkLine: (_) {},
              onLoopFromLine: (_) {},
              onDictationLine: (_) {},
              onAiExplain: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('sanctuary'));
    await tester.pumpAndSettle();

    expect(find.textContaining('holy protection'), findsOneWidget);
    expect(find.text('They found a sanctuary nearby.'), findsOneWidget);
    expect(
      find.text('The small island became a sanctuary for rare birds.'),
      findsOneWidget,
    );
  });

  testWidgets('subtitle popup closes from close button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: PlayerSubtitleList(
              lines: const <PlayerSubtitleLine>[_dictionaryLine],
              activeIndex: 0,
              subtitleMode: '双语',
              currentWordIndex: 0,
              fontScale: 1,
              highlightWords: true,
              onTapLine: (_) {},
              onCollectWord: (_) {},
              onBookmarkLine: (_) {},
              onLoopFromLine: (_) {},
              onDictationLine: (_) {},
              onAiExplain: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('sanctuary'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('word-lookup-popup-card')),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('word-lookup-popup-card')),
      findsNothing,
    );
  });

  testWidgets('subtitle popup shows action buttons without scrolling', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: PlayerSubtitleList(
              lines: const <PlayerSubtitleLine>[_dictionaryLine],
              activeIndex: 0,
              subtitleMode: '双语',
              currentWordIndex: 0,
              fontScale: 1,
              highlightWords: true,
              onTapLine: (_) {},
              onCollectWord: (_) {},
              onBookmarkLine: (_) {},
              onLoopFromLine: (_) {},
              onDictationLine: (_) {},
              onAiExplain: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('sanctuary'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('加入短语库'), findsOneWidget);
    expect(find.byTooltip('播放发音'), findsOneWidget);
  });

  testWidgets('subtitle popup stays on screen and scrolls when content is tall', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(430, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        // ignore: always_specify_types
        overrides: [
          learningSettingsProvider.overrideWith(
            _ConfiguredLearningSettingsNotifier.new,
          ),
          wordLookupServiceProvider.overrideWith(
            (Ref ref) => WordLookupService(
              remoteLookupOverride:
                  ({
                    required String rawWord,
                    String? contextSentence,
                    required LearningSettingsState settings,
                  }) async {
                    return WordLookupEntry(
                      word: 'Sanctuary',
                      phonetic: '/test/',
                      type: 'noun',
                      definitionEn: List<String>.filled(
                        12,
                        'A protected place for practice and careful listening.',
                      ).join(' '),
                      usageEn: List<String>.filled(
                        8,
                        'Used when the word describes a safe context.',
                      ).join(' '),
                      exampleSentenceEn:
                          'The room became a sanctuary for quiet study.',
                      definitionCn: '避难所；圣所；庇护所',
                      sourceLabel: 'API',
                    );
                  },
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.only(top: 180),
              child: PlayerSubtitleList(
                lines: const <PlayerSubtitleLine>[_dictionaryLine],
                activeIndex: 0,
                subtitleMode: '双语',
                currentWordIndex: 0,
                fontScale: 1,
                highlightWords: true,
                onTapLine: (_) {},
                onCollectWord: (_) {},
                onBookmarkLine: (_) {},
                onLoopFromLine: (_) {},
                onDictationLine: (_) {},
                onAiExplain: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('sanctuary'));
    await tester.pumpAndSettle();

    final Rect popupRect = tester.getRect(
      find.byKey(const ValueKey<String>('word-lookup-popup-card')),
    );
    expect(popupRect.top, greaterThanOrEqualTo(16));
    expect(popupRect.bottom, lessThanOrEqualTo(344));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('subtitle popup shows pronounce buttons on each content block', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        // ignore: always_specify_types
        overrides: [
          learningSettingsProvider.overrideWith(
            _ConfiguredLearningSettingsNotifier.new,
          ),
          wordLookupServiceProvider.overrideWith(
            (Ref ref) => WordLookupService(
              remoteLookupOverride:
                  ({
                    required String rawWord,
                    String? contextSentence,
                    required LearningSettingsState settings,
                  }) async {
                    return const WordLookupEntry(
                      word: 'Sanctuary',
                      phonetic: '/test/',
                      type: 'noun',
                      definitionEn:
                          'A place of safety, refuge, or holy protection; a nature reserve.',
                      usageEn:
                          'Use sanctuary for a place that feels protected, peaceful, or sheltered from danger.',
                      exampleSentenceEn:
                          'The small island became a sanctuary for rare birds.',
                      definitionCn: '避难所；圣所；庇护所',
                      sourceLabel: 'API',
                    );
                  },
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: PlayerSubtitleList(
              lines: const <PlayerSubtitleLine>[_dictionaryLine],
              activeIndex: 0,
              subtitleMode: '双语',
              currentWordIndex: 0,
              fontScale: 1,
              highlightWords: true,
              onTapLine: (_) {},
              onCollectWord: (_) {},
              onBookmarkLine: (_) {},
              onLoopFromLine: (_) {},
              onDictationLine: (_) {},
              onAiExplain: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('sanctuary'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('word-lookup-pronounce-cn')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('word-lookup-pronounce-en')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('word-lookup-pronounce-context')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('word-lookup-pronounce-example')),
      findsOneWidget,
    );
  });

  testWidgets('word popup pronounces the selected content block', (
    WidgetTester tester,
  ) async {
    String? spokenText;

    await tester.pumpWidget(
      ProviderScope(
        // ignore: always_specify_types
        overrides: [
          learningSettingsProvider.overrideWith(
            _ConfiguredLearningSettingsNotifier.new,
          ),
          wordLookupServiceProvider.overrideWith(
            (Ref ref) => WordLookupService(
              remoteLookupOverride:
                  ({
                    required String rawWord,
                    String? contextSentence,
                    required LearningSettingsState settings,
                  }) async {
                    return const WordLookupEntry(
                      word: 'Sanctuary',
                      phonetic: '/test/',
                      type: 'noun',
                      definitionEn: 'A place of safety.',
                      usageEn: '',
                      exampleSentenceEn: 'The island became a sanctuary.',
                      definitionCn: '避难所；圣所；庇护所',
                      sourceLabel: 'API',
                    );
                  },
            ),
          ),
          wordPronunciationServiceProvider.overrideWith(
            (Ref ref) => WordPronunciationService(
              speakOverride: (String text) async {
                spokenText = text;
              },
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: PlayerCurrentLineCard(
              line: _dictionaryLine,
              subtitleMode: '双语',
              currentWordIndex: 0,
              fontScale: 1,
              highlightWords: true,
              onBookmark: () {},
              onCollectWord: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('sanctuary'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('word-lookup-pronounce-cn')),
    );
    await tester.pumpAndSettle();

    expect(spokenText, '避难所；圣所；庇护所');
  });

  testWidgets('word popup can trigger local pronunciation service', (
    WidgetTester tester,
  ) async {
    String? spokenWord;
    bool pausedForPronunciation = false;

    await tester.pumpWidget(
      ProviderScope(
        // ignore: always_specify_types
        overrides: [
          wordLookupServiceProvider.overrideWith(
            (Ref ref) => const WordLookupService(),
          ),
          wordPronunciationServiceProvider.overrideWith(
            (Ref ref) => WordPronunciationService(
              speakOverride: (String text) async {
                spokenWord = text;
              },
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: PlayerCurrentLineCard(
              line: _dictionaryLine,
              subtitleMode: '双语',
              currentWordIndex: 0,
              fontScale: 1,
              highlightWords: true,
              onBookmark: () {},
              onCollectWord: (_) {},
              onPronounce: () {
                pausedForPronunciation = true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('sanctuary'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('播放发音'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('播放发音'));
    await tester.pumpAndSettle();

    expect(pausedForPronunciation, isTrue);
    expect(spokenWord, 'Sanctuary');
  });

  testWidgets('word popup shows snackbar when pronunciation fails', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        // ignore: always_specify_types
        overrides: [
          wordLookupServiceProvider.overrideWith(
            (Ref ref) => const WordLookupService(),
          ),
          wordPronunciationServiceProvider.overrideWith(
            (Ref ref) => WordPronunciationService(
              speakOverride: (String text) async {
                throw const WordPronunciationException();
              },
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: WordLookupPopupCard(
              rawWord: 'sanctuary',
              contextSentence: 'They found a sanctuary nearby.',
              onClose: _noop,
              onCollect: _noop,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('播放发音'));
    await tester.pump();

    expect(find.text('朗读失败，请检查设备 TTS。'), findsOneWidget);
  });
}

bool _hasCheckedMenuItem(WidgetTester tester, String value) {
  return tester.allWidgets.whereType<CheckedPopupMenuItem<dynamic>>().any((
    CheckedPopupMenuItem<dynamic> item,
  ) {
    final Widget? child = item.child;
    return item.checked && child is Text && child.data == value;
  });
}

void _noop() {}
