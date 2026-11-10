import 'dart:math';

import '../../player/presentation/player_mock_state.dart';
import 'intensive_lesson.dart';

/// Subtitle cues are not sentences. Complete the target within a bounded,
/// contiguous dialogue window; the model receives neighbouring cues separately.
LessonSource selectLessonContext({
  required List<PlayerSubtitleLine> lines,
  required int index,
  required String episodeId,
  required String courseTitle,
  required String episodeTitle,
}) {
  if (index < 0 ||
      index >= lines.length ||
      lines[index].english.trim().isEmpty) {
    throw const FormatException('当前没有可解析的英文字幕。');
  }
  bool canJoin(int left, int right) =>
      lines[right].startMs - lines[left].endMs <= 2500 &&
      lines[right].startMs - lines[left].startMs <= 12000 &&
      lines[left].english.trim().isNotEmpty &&
      lines[right].english.trim().isNotEmpty &&
      !RegExp(r'^\s*[-–—]').hasMatch(lines[right].english);
  bool endsSentence(String text) =>
      RegExp(r'''[.!?]["'”’\s]*$''').hasMatch(text);

  int first = index;
  int last = index;
  while (first > 0 &&
      index - first < 3 &&
      !endsSentence(lines[first - 1].english) &&
      canJoin(first - 1, first) &&
      lines[index].endMs - lines[first - 1].startMs <= 20000) {
    first--;
  }
  while (last + 1 < lines.length &&
      last - first < 7 &&
      !endsSentence(lines[last].english) &&
      canJoin(last, last + 1) &&
      lines[last + 1].endMs - lines[first].startMs <= 20000) {
    last++;
  }
  final bool boundaryLimited =
      !endsSentence(lines[last].english) ||
      (first > 0 &&
          !endsSentence(lines[first - 1].english) &&
          !RegExp(r'^\s*[-–—]').hasMatch(lines[first].english));
  final String target = lines
      .sublist(first, last + 1)
      .map((PlayerSubtitleLine line) => line.english.trim())
      .join(' ');
  if (target.length > 2000) throw const FormatException('当前字幕过长，请先检查字幕分句。');
  final List<String> context = <String>[];
  for (int i = max(0, first - 3); i <= min(lines.length - 1, last + 3); i++) {
    if (lines[i].startMs < lines[first].startMs - 20000 ||
        lines[i].startMs > lines[last].endMs + 20000) {
      continue;
    }
    context.add(
      '[${lines[i].startMs}-${lines[i].endMs}] '
      '${lines[i].english.trim()}',
    );
  }
  final String surrounding = context.join('\n');
  if (surrounding.length > 8000) throw const FormatException('附近字幕过长，请检查字幕内容。');
  return LessonSource(
    episodeId: episodeId,
    courseTitle: courseTitle,
    episodeTitle: episodeTitle,
    startMs: lines[first].startMs,
    endMs: lines[last].endMs,
    english: target,
    context: surrounding,
    boundaryLimited: boundaryLimited,
  );
}
