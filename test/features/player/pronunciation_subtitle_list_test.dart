import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/widgets/player_subtitle_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sentence button reports its exact row without narrow overflow', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const List<PlayerSubtitleLine> lines = <PlayerSubtitleLine>[
      PlayerSubtitleLine(
        startTime: '00:00',
        english: 'Take a break.',
        chinese: '休息一下。',
        startMs: 0,
        endMs: 1000,
      ),
      PlayerSubtitleLine(
        startTime: '00:02',
        english: 'Listen carefully.',
        chinese: '仔细听。',
        startMs: 2000,
        endMs: 3000,
      ),
    ];
    int? assessedIndex;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 780,
            child: PlayerSubtitleList(
              lines: lines,
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
              onAssessLine: (int index) => assessedIndex = index,
              pronunciationUnavailableReasonForLine: (_) => null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final Finder assess = find.byKey(
      const ValueKey<String>('subtitle-line-assess-1'),
    );
    final Finder loop = find.byKey(
      const ValueKey<String>('subtitle-line-loop-1'),
    );
    expect(tester.getRect(assess).right, lessThan(tester.getRect(loop).left));
    expect(tester.getCenter(assess).dy, tester.getCenter(loop).dy);
    expect(
      tester
          .widget<Icon>(
            find.descendant(of: assess, matching: find.byType(Icon)),
          )
          .icon,
      Icons.mic_rounded,
    );
    await tester.tap(assess);
    expect(assessedIndex, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable line has disabled assessment action and reason', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: PlayerSubtitleList(
              lines: const <PlayerSubtitleLine>[
                PlayerSubtitleLine(
                  startTime: '00:00',
                  english: 'Take a break.',
                  chinese: '休息一下。',
                  startMs: 0,
                  endMs: 1000,
                ),
              ],
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
              onAssessLine: (_) {},
              pronunciationUnavailableReasonForLine: (_) => '视频暂不可用',
            ),
          ),
        ),
      ),
    );

    final IconButton button = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('subtitle-line-assess-0')),
    );
    expect(button.onPressed, isNull);
    expect(find.byTooltip('视频暂不可用'), findsOneWidget);
  });
}
