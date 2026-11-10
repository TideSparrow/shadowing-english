import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../player_mock_state.dart';
import 'player_subtitle_list.dart';

class PlayerTranscriptPanel extends StatefulWidget {
  const PlayerTranscriptPanel({
    required this.lines,
    required this.activeIndex,
    required this.subtitleMode,
    this.subtitleLetterCase = '保留原样',
    required this.currentWordIndex,
    required this.fontScale,
    required this.highlightWords,
    required this.subtitleWordHighlightStyle,
    this.subtitleWordHighlightBorderWidth = 2.5,
    required this.onTapLine,
    required this.onCollectWord,
    this.onCollectWordAtTime,
    this.onFavoriteWord,
    required this.onBookmarkLine,
    required this.onLoopFromLine,
    required this.onDictationLine,
    required this.onAiExplain,
    this.loopingLineIndex,
    required this.isPlaying,
    required this.onTogglePlaying,
    this.episodeId,
    this.onPronounce,
    this.onAssessLine,
    this.pronunciationUnavailableReasonForLine,
    this.onRegenerateAiSubtitles,
    this.onDeleteAiSubtitles,
    this.onRegenerateAiLine,
    this.lessonPanel,
    super.key,
  });

  final List<PlayerSubtitleLine> lines;
  final int activeIndex;
  final String subtitleMode;
  final String subtitleLetterCase;
  final int currentWordIndex;
  final double fontScale;
  final bool highlightWords;
  final String subtitleWordHighlightStyle;
  final double subtitleWordHighlightBorderWidth;
  final ValueChanged<int> onTapLine;
  final ValueChanged<String> onCollectWord;
  final void Function(String word, String time)? onCollectWordAtTime;
  final ValueChanged<String>? onFavoriteWord;
  final ValueChanged<int> onBookmarkLine;
  final ValueChanged<int> onLoopFromLine;
  final ValueChanged<int> onDictationLine;
  final ValueChanged<int> onAiExplain;
  final int? loopingLineIndex;
  final bool isPlaying;
  final VoidCallback onTogglePlaying;
  final String? episodeId;
  final VoidCallback? onPronounce;
  final ValueChanged<int>? onAssessLine;
  final String? Function(int index)? pronunciationUnavailableReasonForLine;
  final VoidCallback? onRegenerateAiSubtitles;
  final VoidCallback? onDeleteAiSubtitles;
  final Future<void> Function(int index)? onRegenerateAiLine;
  final Widget? lessonPanel;

  @override
  State<PlayerTranscriptPanel> createState() => _PlayerTranscriptPanelState();
}

class _PlayerTranscriptPanelState extends State<PlayerTranscriptPanel> {
  bool _showCurrentOnly = false;
  bool _showLessons = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PanelHeader(
          showCurrentOnly: _showCurrentOnly,
          showLessons: _showLessons,
          onLessonsSelected: widget.lessonPanel == null
              ? null
              : () => setState(() => _showLessons = true),
          onViewChanged: (bool showCurrentOnly) {
            setState(() {
              _showCurrentOnly = showCurrentOnly;
              _showLessons = false;
            });
          },
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _showLessons && widget.lessonPanel != null
              ? widget.lessonPanel!
              : PlayerSubtitleList(
                  lines: widget.lines,
                  episodeId: widget.episodeId,
                  activeIndex: widget.activeIndex,
                  subtitleMode: widget.subtitleMode,
                  subtitleLetterCase: widget.subtitleLetterCase,
                  showCurrentOnly: _showCurrentOnly,
                  currentWordIndex: widget.currentWordIndex,
                  fontScale: widget.fontScale,
                  highlightWords: widget.highlightWords,
                  subtitleWordHighlightStyle: widget.subtitleWordHighlightStyle,
                  subtitleWordHighlightBorderWidth:
                      widget.subtitleWordHighlightBorderWidth,
                  onCollectWord: widget.onCollectWord,
                  onCollectWordAtTime: widget.onCollectWordAtTime,
                  onFavoriteWord: widget.onFavoriteWord,
                  onTapLine: widget.onTapLine,
                  onBookmarkLine: widget.onBookmarkLine,
                  onLoopFromLine: widget.onLoopFromLine,
                  onDictationLine: widget.onDictationLine,
                  onAiExplain: widget.onAiExplain,
                  loopingLineIndex: widget.loopingLineIndex,
                  isPlaying: widget.isPlaying,
                  onTogglePlaying: widget.onTogglePlaying,
                  onPronounce: widget.onPronounce,
                  onAssessLine: widget.onAssessLine,
                  pronunciationUnavailableReasonForLine:
                      widget.pronunciationUnavailableReasonForLine,
                  onRegenerateAiSubtitles: widget.onRegenerateAiSubtitles,
                  onDeleteAiSubtitles: widget.onDeleteAiSubtitles,
                  onRegenerateAiLine: widget.onRegenerateAiLine,
                ),
        ),
      ],
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.showCurrentOnly,
    required this.onViewChanged,
    required this.showLessons,
    this.onLessonsSelected,
  });
  final bool showCurrentOnly;
  final ValueChanged<bool> onViewChanged;
  final bool showLessons;
  final VoidCallback? onLessonsSelected;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF0FDFA),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFCCFBF1)),
    ),
    child: LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Widget heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              showLessons ? '本集精讲' : '逐句精听',
              style: const TextStyle(
                color: AppDesignTokens.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              showLessons ? '已保存的卡片，随时打开复习' : '点句子定位播放，点单词查看释义',
              style: const TextStyle(
                color: AppDesignTokens.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );
        final Widget tabs = SegmentedButton<int>(
          segments: <ButtonSegment<int>>[
            const ButtonSegment<int>(value: 0, label: Text('单句')),
            const ButtonSegment<int>(value: 1, label: Text('完整')),
            if (onLessonsSelected != null)
              const ButtonSegment<int>(value: 2, label: Text('精讲')),
          ],
          selected: <int>{if (showLessons) 2 else showCurrentOnly ? 0 : 1},
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll<TextStyle>(
              TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          onSelectionChanged: (Set<int> values) {
            if (values.single == 2) {
              onLessonsSelected?.call();
            } else {
              onViewChanged(values.single == 0);
            }
          },
        );
        if (constraints.maxWidth < 490) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[heading, const SizedBox(height: 12), tabs],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(child: heading),
            const SizedBox(width: 12),
            tabs,
          ],
        );
      },
    ),
  );
}
