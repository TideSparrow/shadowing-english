import '../domain/pronunciation_assessment.dart';
import 'player_mock_state.dart';

class PronunciationTargetSelection {
  const PronunciationTargetSelection.available(this.target)
    : unavailableReason = null;

  const PronunciationTargetSelection.unavailable(this.unavailableReason)
    : target = null;

  final PronunciationAssessmentTarget? target;
  final String? unavailableReason;

  bool get isAvailable => target != null;
}

PronunciationTargetSelection selectPronunciationTarget({
  required PlayerMockState state,
  required String? videoSource,
  required bool videoReady,
  required Duration videoDuration,
  int? subtitleIndex,
}) {
  if (videoSource == null || videoSource.trim().isEmpty || !videoReady) {
    return const PronunciationTargetSelection.unavailable('视频暂不可用');
  }
  if (videoSource.startsWith('http://') || videoSource.startsWith('https://')) {
    return const PronunciationTargetSelection.unavailable('远程视频暂不支持原声提取');
  }
  if (videoDuration <= Duration.zero) {
    return const PronunciationTargetSelection.unavailable('视频时长暂不可用');
  }
  final int index;
  if (subtitleIndex == null) {
    if (state.subtitleMode == '隐藏' || state.subtitleMode == '单中') {
      return const PronunciationTargetSelection.unavailable('当前没有正在显示的英文字幕');
    }
    if (state.visibleLine == null) {
      return const PronunciationTargetSelection.unavailable('当前没有正在显示的英文字幕');
    }
    index = state.activeLineIndex;
  } else {
    index = subtitleIndex;
  }
  if (index < 0 || index >= state.lines.length) {
    return const PronunciationTargetSelection.unavailable('字幕行不可用');
  }
  final PlayerSubtitleLine line = state.lines[index];
  if (line.english.trim().isEmpty ||
      !RegExp('[A-Za-z]').hasMatch(line.english)) {
    return const PronunciationTargetSelection.unavailable('此句没有可跟读的英文字幕');
  }
  final PronunciationAssessmentTarget target = PronunciationAssessmentTarget(
    text: line.english,
    videoSource: videoSource,
    startMs: state.videoStartMsForLine(index),
    endMs: state.videoEndMsForLine(index),
    videoDuration: videoDuration,
  );
  final String? validationError = target.validationError;
  if (validationError != null) {
    return PronunciationTargetSelection.unavailable(validationError);
  }
  return PronunciationTargetSelection.available(target);
}
