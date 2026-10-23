import 'package:common_learn_english/features/player/presentation/full_transcript_reader.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/transcript_reader_session.dart';
import 'package:common_learn_english/features/player/presentation/widgets/player_subtitle_list.dart';
import 'package:common_learn_english/features/shared/domain/subtitle_letter_case.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats all modes without changing whitespace or punctuation', () {
    const String text = '  HELLO, WORLD!\n"HOW are YOU?" 我很好。';
    expect(formatSubtitleLetterCase(text, '保留原样'), text);
    expect(formatSubtitleLetterCase(text, 'invalid'), text);
    expect(
      formatSubtitleLetterCase(text, '全部大写'),
      '  HELLO, WORLD!\n"HOW ARE YOU?" 我很好。',
    );
    expect(
      formatSubtitleLetterCase(text, '全部小写'),
      '  hello, world!\n"how are you?" 我很好。',
    );
    expect(
      formatSubtitleLetterCase(text, '句首字母大写'),
      '  Hello, world!\n"How are you?" 我很好。',
    );
    expect(
      formatSubtitleLetterCase("I'M HERE. AND I WILL STAY!", '句首字母大写'),
      "I'm here. And I will stay!",
    );
    expect(formatSubtitleLetterCase('', '句首字母大写'), isEmpty);
  });

  const PlayerSubtitleLine line = PlayerSubtitleLine(
    startTime: '00:01',
    english: 'HELLO WORLD!',
    chinese: '你好世界！',
    startMs: 1000,
    endMs: 3000,
    words: <PlayerSubtitleWord>[
      PlayerSubtitleWord(text: 'HELLO', startMs: 1000, endMs: 2000),
      PlayerSubtitleWord(text: 'WORLD!', startMs: 2000, endMs: 3000),
    ],
  );

  test('reader sync includes case changes while paused', () {
    final TranscriptReaderSession session = TranscriptReaderSession();
    addTearDown(session.dispose);
    session.updateProgress(lineIndex: 3, wordIndex: 2);
    int changes = 0;
    session.progress.addListener(() => changes++);
    session.updateProgress(
      lineIndex: 3,
      wordIndex: 2,
      subtitleLetterCase: '全部小写',
    );
    expect(changes, 1);
    final TranscriptReaderProgress received = TranscriptReaderProgress.fromJson(
      session.progress.value.toJson(),
    );
    expect(received.subtitleLetterCase, '全部小写');
    expect(received.lineIndex, 3);
    expect(received.wordIndex, 2);
    session.updateProgress(
      lineIndex: 3,
      wordIndex: 2,
      subtitleLetterCase: '全部小写',
    );
    expect(changes, 1);
    session.updateProgress(lineIndex: 3, wordIndex: 3);
    expect(session.progress.value.subtitleLetterCase, '全部小写');
    expect(changes, 2);
    expect(
      TranscriptReaderProgress.fromJson(<String, dynamic>{
        'lineIndex': 3,
        'wordIndex': 2,
      }).subtitleLetterCase,
      isNull,
    );
  });

  testWidgets('existing subtitles switch case and still select the same line', (
    WidgetTester tester,
  ) async {
    int? selectedLine;
    Widget build(String mode) => MaterialApp(
      home: Scaffold(
        body: PlayerSubtitleList(
          lines: const <PlayerSubtitleLine>[line],
          activeIndex: 0,
          subtitleMode: '双语',
          subtitleLetterCase: mode,
          currentWordIndex: 1,
          fontScale: 1,
          highlightWords: true,
          onTapLine: (int index) => selectedLine = index,
          onCollectWord: (_) {},
          onBookmarkLine: (_) {},
          onLoopFromLine: (_) {},
          onDictationLine: (_) {},
          onAiExplain: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(build('保留原样'));
    await tester.pumpAndSettle();
    expect(find.text('HELLO'), findsOneWidget);
    await tester.pumpWidget(build('全部小写'));
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('world!'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('world!')).style?.fontWeight,
      FontWeight.w800,
    );
    expect(find.text('你好世界！'), findsOneWidget);
    await tester.tap(find.text('00:01'));
    expect(selectedLine, 0);
    expect(line.english, 'HELLO WORLD!');
    expect(line.words.last.startMs, 2000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('case-only updates preserve the reader scroll position', (
    WidgetTester tester,
  ) async {
    final List<PlayerSubtitleLine> lines = List<PlayerSubtitleLine>.generate(
      20,
      (int index) => PlayerSubtitleLine(
        startTime: '00:$index',
        english: 'HELLO WORLD!',
        chinese: '',
        startMs: index * 1000,
        endMs: (index + 1) * 1000,
      ),
    );
    final ValueNotifier<TranscriptReaderProgress> progress =
        ValueNotifier<TranscriptReaderProgress>(
          const TranscriptReaderProgress(lineIndex: 0, wordIndex: 0),
        );
    addTearDown(progress.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: FullTranscriptReaderScreen(
          snapshot: TranscriptReaderSnapshot(
            courseTitle: '课程',
            episodeTitle: '视频',
            lines: lines,
            meanings: const <String, String>{},
            progress: progress.value,
          ),
          progressListenable: progress,
          onClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final ScrollableState scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    scrollable.position.jumpTo(400);
    await tester.pumpAndSettle();
    final double offset = scrollable.position.pixels;
    expect(offset, greaterThan(0));
    progress.value = const TranscriptReaderProgress(
      lineIndex: 0,
      wordIndex: 0,
      subtitleLetterCase: '全部小写',
    );
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, offset);
    expect(find.text('hello'), findsWidgets);
    expect(find.text('HELLO'), findsNothing);
  });

  testWidgets(
    'reader window serializes case and renders original timed words in the chosen case',
    (WidgetTester tester) async {
      const TranscriptReaderSnapshot snapshot = TranscriptReaderSnapshot(
        courseTitle: '课程',
        episodeTitle: '视频',
        lines: <PlayerSubtitleLine>[line],
        meanings: <String, String>{},
        subtitleLetterCase: '句首字母大写',
        progress: TranscriptReaderProgress(lineIndex: 0, wordIndex: 1),
      );
      final TranscriptReaderSnapshot restored =
          TranscriptReaderSnapshot.fromJson(snapshot.toJson());
      expect(restored.subtitleLetterCase, '句首字母大写');
      expect(restored.lines.single.english, line.english);
      expect(restored.lines.single.words.last.startMs, 2000);
      final ValueNotifier<TranscriptReaderProgress> progress =
          ValueNotifier<TranscriptReaderProgress>(snapshot.progress);
      addTearDown(progress.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: FullTranscriptReaderScreen(
            snapshot: restored,
            progressListenable: progress,
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('world!'), findsOneWidget);
      final State<StatefulWidget> originalReader = tester.state(
        find.byType(FullTranscriptReaderScreen),
      );
      progress.value = TranscriptReaderProgress.fromJson(
        const TranscriptReaderProgress(
          lineIndex: 0,
          wordIndex: 1,
          subtitleLetterCase: '全部大写',
        ).toJson(),
      );
      await tester.pumpAndSettle();
      expect(find.text('HELLO'), findsOneWidget);
      expect(find.text('WORLD!'), findsOneWidget);
      expect(
        tester.state(find.byType(FullTranscriptReaderScreen)),
        same(originalReader),
      );
      progress.value = TranscriptReaderProgress.fromJson(
        const TranscriptReaderProgress(
          lineIndex: 0,
          wordIndex: 1,
          subtitleLetterCase: '全部小写',
        ).toJson(),
      );
      await tester.pumpAndSettle();
      expect(find.text('hello'), findsOneWidget);
      expect(find.text('world!'), findsOneWidget);
      expect(progress.value.wordIndex, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
