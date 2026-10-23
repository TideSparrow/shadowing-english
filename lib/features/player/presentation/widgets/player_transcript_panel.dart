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
    this.onRegenerateAiSubtitles,
    this.onDeleteAiSubtitles,
    this.onRegenerateAiLine,
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
  final VoidCallback? onRegenerateAiSubtitles;
  final VoidCallback? onDeleteAiSubtitles;
  final Future<void> Function(int index)? onRegenerateAiLine;

  @override
  State<PlayerTranscriptPanel> createState() => _PlayerTranscriptPanelState();
}

class _PlayerTranscriptPanelState extends State<PlayerTranscriptPanel> {
  bool _showCurrentOnly = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PanelHeader(
          showCurrentOnly: _showCurrentOnly,
          onViewChanged: (bool showCurrentOnly) {
            setState(() {
              _showCurrentOnly = showCurrentOnly;
            });
          },
        ),
        const SizedBox(height: 12),
        Expanded(
          child: PlayerSubtitleList(
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
  });

  final bool showCurrentOnly;
  final ValueChanged<bool> onViewChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDFA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFCCFBF1)),
      ),
      child: Row(
        children: <Widget>[
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '逐句精听',
                  style: TextStyle(
                    color: AppDesignTokens.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '点句子定位播放，点单词查看释义',
                  style: TextStyle(
                    color: AppDesignTokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _TranscriptViewSwitch(
            showCurrentOnly: showCurrentOnly,
            onChanged: onViewChanged,
          ),
        ],
      ),
    );
  }
}

class _TranscriptViewSwitch extends StatelessWidget {
  const _TranscriptViewSwitch({
    required this.showCurrentOnly,
    required this.onChanged,
  });

  final bool showCurrentOnly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      segments: const <ButtonSegment<bool>>[
        ButtonSegment<bool>(value: true, label: Text('单句')),
        ButtonSegment<bool>(value: false, label: Text('完整')),
      ],
      selected: <bool>{showCurrentOnly},
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll<TextStyle>(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
      onSelectionChanged: (Set<bool> selected) {
        onChanged(selected.single);
      },
    );
  }
}
