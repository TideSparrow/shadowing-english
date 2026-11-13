import 'dart:convert';

import 'package:common_learn_english/features/library/presentation/library_catalog_provider.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:common_learn_english/features/player/presentation/pad_landscape_player_screen.dart';
import 'package:common_learn_english/features/player/presentation/pad_portrait_player_screen.dart';
import 'package:common_learn_english/features/player/presentation/player_fullscreen_video_screen.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/player_screen.dart';
import 'package:common_learn_english/features/player/presentation/widgets/player_ab_timeline.dart';
import 'package:common_learn_english/features/player/presentation/widgets/player_subtitle_list.dart';
import 'package:common_learn_english/features/player/presentation/widgets/player_video_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final List<PlayerSubtitleLine> _lines = List<PlayerSubtitleLine>.generate(
  5,
  (int i) => PlayerSubtitleLine(
    startTime: '00:0$i',
    english: 'Sentence $i.',
    chinese: '第 $i 句。',
    startMs: i * 1500,
    endMs: i * 1500 + 1000,
  ),
);

PlayerMockState _state() => PlayerMockState()
  ..loadLines(_lines)
  ..videoDurationMs = 8000;

class _Catalog extends LibraryCatalogNotifier {
  @override
  List<LibraryCourseData> build() => const <LibraryCourseData>[
    LibraryCourseData(
      id: 'ab-course',
      title: 'AB 测试',
      description: '',
      sourceLabel: '本地',
      coverImage: '',
      level: 'B1',
      category: '',
      progressPercent: 0,
      totalWords: 0,
      completedEpisodes: 0,
      totalEpisodes: 1,
      lastStudiedStr: '',
      rating: 0,
      episodes: <LibraryEpisodeItem>[
        LibraryEpisodeItem(
          id: 'ab-episode',
          numberStr: '01',
          title: 'AB 测试',
          durationMinutes: 1,
          hasChineseSubtitles: false,
          hasEnglishSubtitles: true,
          completed: false,
          progressPercent: 0,
          coverImage: '',
          enSubtitleAsset: 'assets/test/ab.srt',
        ),
      ],
    ),
  ];
}

Widget _fullscreen(PlayerMockState state) => MaterialApp(
  home: PlayerFullscreenVideoScreen(
    playerState: state,
    highlightWords: false,
    isMuted: false,
    volumeLevel: 1,
    onTogglePlaying: state.togglePlaying,
    onPreviousLine: state.previousLine,
    onReplayLine: () => state.selectLine(state.activeLineIndex),
    onNextLine: state.nextLine,
    onSeekBackward: () {},
    onSeekForward: () {},
    onSelectLine: state.selectLine,
    onSeek: (double value) => state.seekToMilliseconds((value * 8000).round()),
    onSpeedSelected: state.selectSpeed,
    onSelectSubtitleMode: state.setSubtitleMode,
    onToggleShadowing: state.toggleShadowing,
    onToggleLoop: state.toggleLoop,
    onStartAbLoop: state.startAbLoop,
    onLoopSelectionChanged: (bool selecting) =>
        state.isSelectingLoopRange = selecting,
    onLoopRangeChanged: state.previewLoopRange,
    onClearLoop: state.exitLoopAtStart,
    onLoopLinesSelected: state.setLoopLines,
    onToggleMuted: () {},
    onVolumeChanged: (_) {},
    onSubtitleLookupOpen: () {},
    onCollectWord: (_) {},
    episodes: const <LibraryEpisodeItem>[],
    activeEpisodeId: 'ab-episode',
    onExit: () {},
    videoDuration: const Duration(seconds: 8),
  ),
);

void main() {
  test('AB opens two minutes after the current sentence and clamps at EOF', () {
    final PlayerMockState state = _state()
      ..videoDurationMs = 600000
      ..syncWithTimestamp(2000)
      ..startAbLoop();
    expect(state.loopStartMs, 1500);
    expect(state.loopEndMs, 121500);
    state
      ..videoDurationMs = 8000
      ..startAbLoop();
    expect(state.loopEndMs, 8000);
  });

  test('reverse endpoint selection includes every intervening subtitle', () {
    final PlayerMockState state = _state()..setLoopLines(3, 1);
    expect(state.loopStartMs, 1500);
    expect(state.loopEndMs, 5500);
    expect(state.loopLineRange, (first: 1, last: 3));
    state.syncWithTimestamp(3200);
    expect(state.restartLoopAtTimestamp(4000), isFalse);
    expect(state.loopStartMs, 1500);
    expect(state.restartLoopAtTimestamp(5700), isTrue);
    expect(state.positionMs, 1500);
    expect(state.activeLineIndex, 1);
  });

  test('manual AB handles derive contiguous coverage including gaps', () {
    final PlayerMockState state = _state()..setLoopRange(1750, 5100);
    expect(state.loopLineRange, (first: 1, last: 3));
    state.setLoopRange(2500, 3000);
    expect(state.loopLineRange, isNull);
    expect(state.restartLoopAtTimestamp(3000), isTrue);
    expect(state.positionMs, 2500);
  });

  test('subtitle ranges follow subtitle delay, manual ranges stay fixed', () {
    final PlayerMockState state = _state()
      ..setLoopLines(1, 3)
      ..subtitleDelayMs = 250;
    expect(state.loopStartMs, 1750);
    expect(state.loopEndMs, 5750);
    state
      ..setLoopRange(1800, 5600)
      ..subtitleDelayMs = -1000;
    expect(state.loopStartMs, 1800);
    expect(state.loopEndMs, 5600);
    expect(state.loopLineRange, (first: 2, last: 4));
  });

  test('AB rejects reversed or empty ranges and clamps to video bounds', () {
    final PlayerMockState state = _state()..setLoopStart(2000);
    expect(state.isLooping, isFalse);
    expect(state.setLoopEnd(2000), isFalse);
    expect(state.setLoopEnd(1000), isFalse);
    expect(state.setLoopEnd(9000), isTrue);
    expect(state.loopEndMs, 8000);
    expect(state.setLoopRange(5000, 1000), isFalse);
    expect(state.loopStartMs, 2000);
    state.setLoopRange(-100, 1500);
    expect(state.loopStartMs, 0);
  });

  test(
    'duration and delay changes cannot leave an empty loop at media boundaries',
    () {
      final PlayerMockState state = _state()
        ..setLoopLines(3, 4)
        ..videoDurationMs = 4000;
      expect(state.isLooping, isFalse);
      state
        ..videoDurationMs = 8000
        ..setLoopLines(0, 1)
        ..subtitleDelayMs = -3000;
      expect(state.loopStartMs, isNull);
      expect(state.isLooping, isFalse);
    },
  );

  test('manual looping works without subtitles and at the media end', () {
    final PlayerMockState state = PlayerMockState()
      ..videoDurationMs = 8000
      ..setLoopRange(2000, 8000);
    expect(state.restartLoopAtTimestamp(8000), isTrue);
    expect(state.positionMs, 2000);
    expect(state.loopLineRange, isNull);
  });

  test('double speed keeps silence and all sentences inside the loop', () {
    final PlayerMockState state = _state()
      ..setLoopLines(0, 2)
      ..speed = '2.0×'
      ..isPlaying = true
      ..syncWithTimestamp(900)
      ..tick();
    expect(state.positionMs, 1140);
    state
      ..syncWithTimestamp(3900)
      ..tick();
    expect(state.positionMs, 0);
    expect(state.loopEndMs, 4000);
  });

  test('preview both boundaries and exit at A without changing play state', () {
    final PlayerMockState state = _state()
      ..setLoopLines(1, 2)
      ..isPlaying = true;
    expect(state.previewLoopRange(1500, 5500), 5499);
    expect(state.activeLineIndex, 3);
    expect(state.isPlaying, isFalse);
    expect(state.previewLoopRange(500, 5500), 500);
    expect(state.activeLineIndex, 0);
    state.isPlaying = true;
    expect(state.exitLoopAtStart(), 500);
    expect(state.positionMs, 500);
    expect(state.isPlaying, isTrue);
    expect(state.isLooping, isFalse);
  });

  test(
    'seeking within AB preserves it; leaving or changing subtitles clears it',
    () {
      final PlayerMockState state = _state()
        ..setLoopLines(1, 3)
        ..seekToMilliseconds(3500);
      expect(state.isLooping, isTrue);
      state.seekToMilliseconds(6000);
      expect(state.isLooping, isFalse);
      state
        ..setLoopLines(1, 2)
        ..loadLines(_lines);
      expect(state.loopStartMs, isNull);
      expect(state.loopEndMs, isNull);
    },
  );

  for (final Size size in <Size>[
    const Size(1366, 1024),
    const Size(844, 390),
    const Size(390, 844),
  ]) {
    testWidgets('fullscreen AB selection and handles stay linked at $size', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final PlayerMockState state = _state();
      await tester.pumpWidget(_fullscreen(state));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('player-loop-menu')));
      await tester.pumpAndSettle();
      expect(find.text('单句循环'), findsOneWidget);
      await tester.tap(find.text('AB 区间循环'));
      await tester.pumpAndSettle();
      expect(state.loopStartMs, 0);
      expect(state.loopEndMs, 8000);
      expect(
        find.byKey(const ValueKey<String>('player-seek-slider')),
        findsNothing,
      );
      expect(find.byType(RangeSlider), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('player-clear-ab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('字幕列表'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('subtitle-select-loop-range')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('subtitle-range-select-0')),
      );
      await tester.pumpAndSettle();
      final Finder third = find.byKey(
        const ValueKey<String>('subtitle-range-select-2'),
      );
      await tester.scrollUntilVisible(
        third,
        100,
        scrollable: find
            .descendant(
              of: find.byType(PlayerSubtitleList),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getTopLeft(third) + const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(state.loopLineRange, (first: 0, last: 2));
      RangeSlider slider = tester.widget<RangeSlider>(find.byType(RangeSlider));
      expect(slider.values, const RangeValues(0, 4000));
      await tester.tap(find.text('完成选择'));
      await tester.pumpAndSettle();
      // Move the actual B handle toward the end of the video.
      final Rect track = tester.getRect(find.byType(RangeSlider));
      await tester.dragFrom(
        Offset(track.center.dx, track.center.dy),
        Offset(track.width * 0.25, 0),
      );
      await tester.pumpAndSettle();
      expect(state.loopEndMs, greaterThan(5000));
      // A range-handle drag must not also trigger the surface seek gesture.
      expect(state.positionMs, state.loopEndMs! - 1);
      expect(state.isPlaying, isFalse);
      final PlayerSubtitleList list = tester.widget<PlayerSubtitleList>(
        find.byType(PlayerSubtitleList),
      );
      expect(list.loopFirstLine, 0);
      expect(list.loopLastLine, greaterThanOrEqualTo(3));
      slider = tester.widget<RangeSlider>(find.byType(RangeSlider));
      expect(slider.values.end.round(), state.loopEndMs);
      await tester.tap(find.byKey(const ValueKey<String>('player-clear-ab')));
      await tester.pumpAndSettle();
      expect(state.isLooping, isFalse);
      expect(find.byType(RangeSlider), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'AB starts at the current sentence and replaces the seek slider',
    (WidgetTester tester) async {
      final PlayerMockState state = _state()
        ..subtitleDelayMs = 250
        ..syncWithTimestamp(2000);
      await tester.pumpWidget(_fullscreen(state));
      await tester.pumpAndSettle();
      expect(find.byType(RangeSlider), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('player-seek-slider')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey<String>('player-loop-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AB 区间循环'));
      await tester.pumpAndSettle();
      expect(state.loopStartMs, 1750);
      expect(state.loopEndMs, 8000);
      expect(state.isLooping, isTrue);
      expect(state.isSelectingLoopRange, isFalse);
      expect(
        find.byKey(const ValueKey<String>('player-seek-slider')),
        findsNothing,
      );
      expect(find.byType(RangeSlider), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('player-clear-ab')));
      await tester.pumpAndSettle();
      expect(state.loopStartMs, isNull);
      expect(find.byType(RangeSlider), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('player-seek-slider')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final Size size in <Size>[
    const Size(1366, 1024),
    const Size(844, 390),
    const Size(390, 844),
  ]) {
    testWidgets(
      'loop progress above total AB rail seeks independently at $size',
      (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final PlayerMockState state = _state()
          ..setLoopRange(1500, 5500)
          ..syncWithTimestamp(2500);
        await tester.pumpWidget(_fullscreen(state));
        await tester.pumpAndSettle();
        final Finder progress = find.byKey(
          const ValueKey<String>('player-loop-progress'),
        );
        final Finder rail = find.byKey(
          const ValueKey<String>('player-ab-range'),
        );
        expect(
          tester.getCenter(progress).dy,
          lessThan(tester.getCenter(rail).dy),
        );
        expect(
          find.byKey(const ValueKey<String>('player-playhead')),
          findsNothing,
        );
        expect(tester.widget<Slider>(progress).value, 0.25);
        await tester.drag(progress, const Offset(2000, 0));
        await tester.pumpAndSettle();
        expect(state.positionMs, 5499);
        expect(state.loopStartMs, 1500);
        expect(state.loopEndMs, 5500);
        expect(state.isLooping, isTrue);
        await tester.tap(find.byKey(const ValueKey<String>('player-clear-ab')));
        await tester.pumpAndSettle();
        expect(progress, findsNothing);
        expect(state.positionMs, 1500);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('a long video can shrink to a two-second loop and expand again', (
    WidgetTester tester,
  ) async {
    int start = 100000;
    int end = 220000;
    const int duration = 1200000;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 640,
              child: StatefulBuilder(
                builder: (BuildContext context, StateSetter update) =>
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 16,
                        ),
                      ),
                      child: PlayerAbTimeline(
                        seekBar: const SizedBox.shrink(),
                        durationMs: duration,
                        positionMs: start,
                        startMs: start,
                        endMs: end,
                        onSeekPosition: (_) {},
                        onClear: () {},
                        onRangeChanged: (int a, int b) => update(() {
                          start = a;
                          end = b;
                        }),
                      ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final Rect rail = tester.getRect(find.byType(RangeSlider));
    final double scale = (rail.width - 32) / duration;
    final TestGesture fastDrag = await tester.startGesture(
      Offset(rail.left + 16 + end * scale, rail.center.dy),
    );
    await fastDrag.moveBy(Offset((102000 - end) * scale, 0));
    await fastDrag.up();
    await tester.pumpAndSettle();
    expect(start, 100000);
    expect(end - start, inInclusiveRange(1, 3000));
    await tester.dragFrom(
      Offset(rail.left + 16 + end * scale, rail.center.dy),
      const Offset(40, 0),
    );
    await tester.pumpAndSettle();
    expect(start, 100000);
    expect(end - start, greaterThan(3000));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'landscape and portrait retain and share the AB range on rotation',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1366, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final TestDefaultBinaryMessenger messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            ..setMockMessageHandler('flutter/assets', (
              ByteData? message,
            ) async {
              final String key = utf8.decode(message!.buffer.asUint8List());
              return key == 'assets/test/ab.srt'
                  ? ByteData.sublistView(
                      utf8.encode('''
1
00:00:01,000 --> 00:00:02,000
First line.

2
00:00:03,000 --> 00:00:04,000
Second line.

3
00:00:05,000 --> 00:00:06,000
Third line.
'''),
                    )
                  : null;
            });
      addTearDown(
        () => messenger.setMockMessageHandler('flutter/assets', null),
      );
      await tester.pumpWidget(
        ProviderScope(
          // ignore: always_specify_types
          overrides: [libraryCatalogProvider.overrideWith(_Catalog.new)],
          child: const MaterialApp(home: PlayerScreen(episodeId: 'ab-episode')),
        ),
      );
      await tester.pumpAndSettle();
      final PadLandscapePlayerScreenState landscape = tester.state(
        find.byType(PadLandscapePlayerScreen),
      );
      await tester.tap(find.byKey(const ValueKey<String>('player-loop-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AB 区间循环'));
      await tester.pumpAndSettle();
      expect(landscape.state.loopStartMs, 1000);
      expect(landscape.state.loopEndMs, 6000);
      expect(landscape.state.isSelectingLoopRange, isFalse);
      final PlayerSubtitleList list = tester.widget(
        find.byType(PlayerSubtitleList),
      );
      list.onLoopLinesSelected!(0, 2);
      await tester.pumpAndSettle();
      expect(landscape.state.loopStartMs, 1000);
      expect(landscape.state.loopEndMs, 6000);
      tester
          .widget<PlayerVideoPanel>(find.byType(PlayerVideoPanel))
          .onToggleFullscreen();
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(768, 1024);
      await tester.pumpAndSettle();
      expect(
        find.byType(PadLandscapePlayerScreen, skipOffstage: false),
        findsOneWidget,
      );
      final PlayerVideoPanel fullPanel = tester.widget(
        find.byType(PlayerVideoPanel),
      );
      fullPanel.onLoopRangeChanged!(1000, 6000);
      fullPanel.onToggleFullscreen();
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(768, 1024);
      await tester.pumpAndSettle();
      expect(find.byType(PadPortraitPlayerScreen), findsOneWidget);
      final PlayerVideoPanel panel = tester.widget(
        find.byType(PlayerVideoPanel),
      );
      expect(panel.loopStartMs, 1000);
      expect(panel.loopEndMs, 6000);
      panel.onLoopRangeChanged!(3500, 5500);
      await tester.pumpAndSettle();
      final PlayerSubtitleList portraitList = tester.widget(
        find.byType(PlayerSubtitleList),
      );
      expect(portraitList.loopFirstLine, 1);
      expect(portraitList.loopLastLine, 2);
      final PadPortraitPlayerScreen portrait = tester.widget(
        find.byType(PadPortraitPlayerScreen),
      );
      expect(portrait.playerState!.positionMs, 3500);
      expect(portrait.playerState!.isPlaying, isFalse);
      tester.view.physicalSize = const Size(1366, 1024);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PlayerVideoPanel>(find.byType(PlayerVideoPanel))
            .loopStartMs,
        3500,
      );
      final PlayerVideoPanel finalPanel = tester.widget(
        find.byType(PlayerVideoPanel),
      );
      finalPanel.onLoopRangeChanged!(3500, 5900);
      await tester.pumpAndSettle();
      final PadLandscapePlayerScreenState finalLandscape = tester.state(
        find.byType(PadLandscapePlayerScreen),
      );
      expect(finalLandscape.state.positionMs, 5899);
      finalPanel.onClearLoop!();
      await tester.pumpAndSettle();
      expect(finalLandscape.state.positionMs, 3500);
      expect(finalLandscape.state.isLooping, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
