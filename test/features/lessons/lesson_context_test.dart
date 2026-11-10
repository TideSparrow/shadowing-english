import 'package:common_learn_english/features/lessons/domain/intensive_lesson.dart';
import 'package:common_learn_english/features/lessons/domain/lesson_context.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:flutter_test/flutter_test.dart';

PlayerSubtitleLine cue(int start, String text, {int? end}) =>
    PlayerSubtitleLine(
      startTime: '00:00',
      english: text,
      chinese: '',
      startMs: start,
      endMs: end ?? start + 1000,
    );

LessonSource select(List<PlayerSubtitleLine> lines, int index) =>
    selectLessonContext(
      lines: lines,
      index: index,
      episodeId: 'episode',
      courseTitle: 'course',
      episodeTitle: 'episode',
    );

void main() {
  test(
    'split cues complete the same sentence and reuse the same cache identity',
    () {
      final List<PlayerSubtitleLine> lines = <PlayerSubtitleLine>[
        cue(0, 'Breakfast is ready.'),
        cue(1500, 'Phil, would you'),
        cue(2700, 'get them?'),
        cue(4000, 'Sure.'),
      ];
      final LessonSource source = select(lines, 2);
      expect(source.english, 'Phil, would you get them?');
      expect(source.startMs, 1500);
      expect(source.endMs, 3700);
      expect(source.seekTime, '00:00:01.500');
      expect(source.seekTimeWithDelay(1000), '00:00:02.500');
      expect(source.seekTimeWithDelay(-3000), '00:00:00.000');
      expect(source.boundaryLimited, false);
      expect(source.context, contains('Breakfast is ready.'));
      expect(select(lines, 1).id, source.id);
      final List<PlayerSubtitleLine> edited = <PlayerSubtitleLine>[
        cue(0, 'The car is ready.'),
        ...lines.skip(1),
      ];
      expect(select(edited, 2).id, isNot(source.id));
    },
  );

  test('speaker markers and long gaps stop sentence completion', () {
    final List<PlayerSubtitleLine> lines = <PlayerSubtitleLine>[
      cue(0, 'If you'),
      cue(1500, '- Wait!'),
      cue(9000, 'come back'),
    ];
    expect(select(lines, 0).english, 'If you');
    expect(select(lines, 0).boundaryLimited, true);
    expect(select(lines, 1).english, '- Wait!');
    expect(select(lines, 2).english, 'come back');
  });

  test('unpunctuated subtitles have bounded target and context', () {
    final List<PlayerSubtitleLine> lines = List<PlayerSubtitleLine>.generate(
      80,
      (int i) => cue(i * 1200, 'a subtitle fragment'),
    );
    final LessonSource source = select(lines, 40);
    expect(source.boundaryLimited, true);
    expect(source.endMs - source.startMs, lessThanOrEqualTo(20000));
    expect(source.context.split('\n').length, lessThanOrEqualTo(14));
  });

  test('invalid/empty selections never form a model request', () {
    expect(() => select(<PlayerSubtitleLine>[], 0), throwsFormatException);
    expect(
      () => select(<PlayerSubtitleLine>[cue(0, '')], 0),
      throwsFormatException,
    );
  });
}
