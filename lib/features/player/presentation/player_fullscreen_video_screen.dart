import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../../library/presentation/library_mock_data.dart';
import '../../settings/presentation/settings_provider.dart'
    show playerFontScales;
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../domain/pronunciation_assessment.dart';
import 'player_mock_state.dart';
import 'pronunciation_target_selection.dart';
import 'widgets/player_transcript_panel.dart';
import 'widgets/player_video_panel.dart';

class PlayerFullscreenVideoScreen extends StatefulWidget {
  const PlayerFullscreenVideoScreen({
    required this.playerState,
    this.subtitleLetterCase = '保留原样',
    required this.highlightWords,
    this.subtitleWordHighlightStyle = '绿色填充',
    this.subtitleWordHighlightBorderWidth = 2.5,
    required this.isMuted,
    required this.volumeLevel,
    required this.onTogglePlaying,
    required this.onPreviousLine,
    required this.onReplayLine,
    required this.onNextLine,
    required this.onSeekBackward,
    required this.onSeekForward,
    required this.onSelectLine,
    required this.onSeek,
    required this.onSpeedSelected,
    required this.onSelectSubtitleMode,
    this.onSelectSubtitleLetterCase,
    this.embeddedSubtitleTracks = const <SubtitleTrack>[],
    this.selectedEmbeddedSubtitleId,
    this.onSelectEmbeddedSubtitle,
    required this.onToggleShadowing,
    required this.onToggleLoop,
    required this.onToggleMuted,
    required this.onVolumeChanged,
    required this.onSubtitleLookupOpen,
    required this.onCollectWord,
    this.onCollectWordAtTime,
    this.onFavoriteWord,
    this.onBookmarkLine = _ignoreLine,
    this.onLoopFromLine = _ignoreLine,
    this.onDictationLine = _ignoreLine,
    this.onAiExplain = _ignoreLine,
    this.onRegenerateAiLine,
    this.fontScale = 1,
    this.fontSize = '中',
    this.onSelectFontSize,
    required this.episodes,
    required this.activeEpisodeId,
    this.videoSource,
    this.onAssessTarget = _ignoreTarget,
    required this.onExit,
    this.videoSurface,
    this.videoAspectRatio = 16 / 9,
    this.videoReady = false,
    this.videoLoading = false,
    this.videoDuration = Duration.zero,
    this.videoErrorText,
    super.key,
  });

  final PlayerMockState playerState;
  final String subtitleLetterCase;
  final bool highlightWords;
  final String subtitleWordHighlightStyle;
  final double subtitleWordHighlightBorderWidth;
  final bool isMuted;
  final double volumeLevel;
  final VoidCallback onTogglePlaying;
  final VoidCallback onPreviousLine;
  final VoidCallback onReplayLine;
  final VoidCallback onNextLine;
  final VoidCallback onSeekBackward;
  final VoidCallback onSeekForward;
  final ValueChanged<int> onSelectLine;
  final ValueChanged<double> onSeek;
  final ValueChanged<String> onSpeedSelected;
  final ValueChanged<String> onSelectSubtitleMode;
  final ValueChanged<String>? onSelectSubtitleLetterCase;
  final List<SubtitleTrack> embeddedSubtitleTracks;
  final String? selectedEmbeddedSubtitleId;
  final ValueChanged<SubtitleTrack?>? onSelectEmbeddedSubtitle;
  final VoidCallback onToggleShadowing;
  final VoidCallback onToggleLoop;
  final VoidCallback onToggleMuted;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onSubtitleLookupOpen;
  final ValueChanged<String> onCollectWord;
  final void Function(String word, String time)? onCollectWordAtTime;
  final ValueChanged<String>? onFavoriteWord;
  final ValueChanged<int> onBookmarkLine;
  final ValueChanged<int> onLoopFromLine;
  final ValueChanged<int> onDictationLine;
  final ValueChanged<int> onAiExplain;
  final Future<void> Function(int index)? onRegenerateAiLine;
  final double fontScale;
  final String fontSize;
  final ValueChanged<String>? onSelectFontSize;
  final List<LibraryEpisodeItem> episodes;
  final String activeEpisodeId;
  final String? videoSource;
  final ValueChanged<PronunciationAssessmentTarget> onAssessTarget;
  final VoidCallback onExit;
  final Widget? videoSurface;
  final double videoAspectRatio;
  final bool videoReady;
  final bool videoLoading;
  final Duration videoDuration;
  final String? videoErrorText;

  @override
  State<PlayerFullscreenVideoScreen> createState() =>
      _PlayerFullscreenVideoScreenState();
}

class _PlayerFullscreenVideoScreenState
    extends State<PlayerFullscreenVideoScreen> {
  static const double _episodePanelWidth = 280;
  static const double _episodePanelGap = 12;

  bool _showEpisodePanel = false;
  bool _showSubtitlePanel = false;
  bool _showControls = true;
  Timer? _refreshTimer;
  late String _subtitleLetterCase = widget.subtitleLetterCase;
  late String _fontSize = widget.fontSize;
  late double _fontScale = widget.fontScale;
  late String? _selectedEmbeddedSubtitleId = widget.selectedEmbeddedSubtitleId;
  late bool _isMuted = widget.isMuted;
  late double _volumeLevel = widget.volumeLevel;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _refreshTimer = Timer.periodic(widget.playerState.playbackTickDuration, (
      _,
    ) {
      if (mounted && widget.playerState.isPlaying) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(covariant PlayerFullscreenVideoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subtitleLetterCase != widget.subtitleLetterCase) {
      _subtitleLetterCase = widget.subtitleLetterCase;
    }
    if (oldWidget.fontSize != widget.fontSize ||
        oldWidget.fontScale != widget.fontScale) {
      _fontSize = widget.fontSize;
      _fontScale = widget.fontScale;
    }
    if (oldWidget.selectedEmbeddedSubtitleId !=
        widget.selectedEmbeddedSubtitleId) {
      _selectedEmbeddedSubtitleId = widget.selectedEmbeddedSubtitleId;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _refresh(VoidCallback action) {
    action();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final PlayerMockState player = widget.playerState;
    final PlayerSubtitleLine line = player.visibleLine ?? _emptySubtitleLine;
    final PronunciationTargetSelection visibleAssessment =
        selectPronunciationTarget(
          state: player,
          videoSource: widget.videoSource,
          videoReady: widget.videoReady,
          videoDuration: widget.videoDuration,
        );
    final double topInset = MediaQuery.paddingOf(context).top;
    final bool isMacOS = Theme.of(context).platform == TargetPlatform.macOS;
    final double backButtonTopInset = topInset + (isMacOS ? 44 : 12);
    final bool showBackControl = _showControls || !player.isPlaying;
    final bool showEpisodePanel =
        _showEpisodePanel && widget.episodes.isNotEmpty;
    final bool showSubtitlePanel = _showSubtitlePanel && player.hasLines;
    final double rightInset = showEpisodePanel
        ? _episodePanelWidth + _episodePanelGap + 12
        : showSubtitlePanel
        ? _subtitlePanelWidth + _episodePanelGap + 12
        : 0;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          AnimatedPositioned(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            left: 0,
            top: 0,
            bottom: 0,
            right: rightInset,
            child: PlayerVideoPanel(
              episodeId: widget.activeEpisodeId,
              line: line,
              isPlaying: player.isPlaying,
              speed: player.speed,
              subtitleMode: player.subtitleMode,
              subtitleModes: player.availableSubtitleModes,
              embeddedSubtitleTracks: widget.embeddedSubtitleTracks,
              selectedEmbeddedSubtitleId: _selectedEmbeddedSubtitleId,
              currentWordIndex: player.currentWordIndex,
              highlightWords: widget.highlightWords,
              subtitleLetterCase: _subtitleLetterCase,
              fontSize: _fontSize,
              fontScale: _fontScale,
              onSelectFontSize: widget.onSelectFontSize == null
                  ? null
                  : (String value) {
                      widget.onSelectFontSize!(value);
                      setState(() {
                        _fontSize = value;
                        _fontScale = playerFontScales[value] ?? 1;
                      });
                    },
              subtitleWordHighlightStyle: widget.subtitleWordHighlightStyle,
              subtitleWordHighlightBorderWidth:
                  widget.subtitleWordHighlightBorderWidth,
              isShadowing: player.isShadowing,
              isLooping: player.isLooping,
              isMuted: _isMuted,
              volumeLevel: _volumeLevel,
              onTogglePlaying: () => _refresh(widget.onTogglePlaying),
              onPreviousLine: () => _refresh(widget.onPreviousLine),
              onReplayLine: () => _refresh(widget.onReplayLine),
              onNextLine: () => _refresh(widget.onNextLine),
              onSeekBackward: () => _refresh(widget.onSeekBackward),
              onSeekForward: () => _refresh(widget.onSeekForward),
              activeIndex: player.activeLineIndex,
              totalLines: player.lines.length,
              onSelectLine: (int index) =>
                  _refresh(() => widget.onSelectLine(index)),
              onSeek: (double value) => _refresh(() => widget.onSeek(value)),
              onSpeedSelected: (String value) =>
                  _refresh(() => widget.onSpeedSelected(value)),
              onSelectSubtitleLetterCase:
                  widget.onSelectSubtitleLetterCase == null
                  ? null
                  : (String value) {
                      widget.onSelectSubtitleLetterCase!(value);
                      setState(() => _subtitleLetterCase = value);
                    },
              onSelectSubtitleMode: (String value) => _refresh(() {
                widget.onSelectSubtitleMode(value);
                _selectedEmbeddedSubtitleId = null;
              }),
              onSelectEmbeddedSubtitle: (SubtitleTrack? track) => _refresh(() {
                widget.onSelectEmbeddedSubtitle?.call(track);
                _selectedEmbeddedSubtitleId = track?.id;
              }),
              onToggleShadowing: () => _refresh(widget.onToggleShadowing),
              onToggleLoop: () => _refresh(widget.onToggleLoop),
              onToggleMuted: () {
                widget.onToggleMuted();
                setState(() {
                  _isMuted = !_isMuted;
                });
              },
              onVolumeChanged: (double value) {
                widget.onVolumeChanged(value);
                setState(() {
                  _volumeLevel = value;
                });
              },
              onSubtitleLookupOpen: () => _refresh(widget.onSubtitleLookupOpen),
              onAssessVisibleLine: visibleAssessment.target == null
                  ? null
                  : () => widget.onAssessTarget(visibleAssessment.target!),
              assessmentUnavailableReason: visibleAssessment.unavailableReason,
              onCollectWord: widget.onCollectWord,
              onCollectWordAtTime: widget.onCollectWordAtTime,
              onFavoriteWord: widget.onFavoriteWord,
              onPronounce: () => _refresh(widget.onSubtitleLookupOpen),
              onToggleEpisodePanel: widget.episodes.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _showEpisodePanel = !_showEpisodePanel;
                        _showSubtitlePanel = false;
                      });
                    },
              isEpisodePanelOpen: _showEpisodePanel,
              onToggleSubtitlePanel: player.hasLines
                  ? () {
                      setState(() {
                        _showSubtitlePanel = !_showSubtitlePanel;
                        _showEpisodePanel = false;
                      });
                    }
                  : null,
              isSubtitlePanelOpen: _showSubtitlePanel,
              onToggleFullscreen: widget.onExit,
              isFullscreen: true,
              sceneHeaderLeadingInset: 48,
              sceneHeaderTopInset: isMacOS ? -4 : null,
              onControlsVisibilityChanged: (bool visible) {
                if (_showControls != visible) {
                  setState(() {
                    _showControls = visible;
                  });
                }
              },
              videoSurface: widget.videoSurface,
              videoAspectRatio: widget.videoAspectRatio,
              videoReady: widget.videoReady,
              videoLoading: widget.videoLoading,
              videoDuration: widget.videoDuration,
              videoPosition: Duration(milliseconds: player.positionMs),
              videoErrorText: widget.videoErrorText,
            ),
          ),
          Positioned(
            top: backButtonTopInset,
            left: 12,
            child: AnimatedOpacity(
              key: const ValueKey<String>('fullscreen-back-control'),
              opacity: showBackControl ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !showBackControl,
                child: IconButton(
                  onPressed: widget.onExit,
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: Colors.white,
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            top: 0,
            right: showEpisodePanel ? 12 : -_episodePanelWidth - 24,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !showEpisodePanel,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: showEpisodePanel ? 1 : 0,
                child: _FullscreenEpisodePanel(
                  episodes: widget.episodes,
                  activeEpisodeId: widget.activeEpisodeId,
                  onOpenEpisode: (LibraryEpisodeItem episode) {
                    if (episode.id == widget.activeEpisodeId) {
                      return;
                    }
                    Navigator.of(context).pop<String>(episode.id);
                  },
                ),
              ),
            ),
          ),
          if (showSubtitlePanel)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              top: 0,
              right: 12,
              bottom: 0,
              child: _FullscreenSubtitlePanel(
                episodeId: widget.activeEpisodeId,
                player: player,
                fontScale: _fontScale,
                highlightWords: widget.highlightWords,
                subtitleLetterCase: _subtitleLetterCase,
                subtitleWordHighlightStyle: widget.subtitleWordHighlightStyle,
                subtitleWordHighlightBorderWidth:
                    widget.subtitleWordHighlightBorderWidth,
                onTapLine: (int index) =>
                    _refresh(() => widget.onSelectLine(index)),
                onCollectWord: widget.onCollectWord,
                onCollectWordAtTime: widget.onCollectWordAtTime,
                onFavoriteWord: widget.onFavoriteWord,
                onBookmarkLine: widget.onBookmarkLine,
                onLoopFromLine: (int index) =>
                    _refresh(() => widget.onLoopFromLine(index)),
                onDictationLine: widget.onDictationLine,
                onAiExplain: widget.onAiExplain,
                onAssessLine: _handleAssessLine,
                pronunciationUnavailableReasonForLine:
                    _lineAssessmentUnavailableReason,
                onRegenerateAiLine: widget.onRegenerateAiLine,
                onTogglePlaying: () => _refresh(widget.onTogglePlaying),
                onPronounce: () => _refresh(widget.onSubtitleLookupOpen),
              ),
            ),
        ],
      ),
    );
  }

  PronunciationTargetSelection _selectLineAssessment(int index) =>
      selectPronunciationTarget(
        state: widget.playerState,
        videoSource: widget.videoSource,
        videoReady: widget.videoReady,
        videoDuration: widget.videoDuration,
        subtitleIndex: index,
      );

  String? _lineAssessmentUnavailableReason(int index) =>
      _selectLineAssessment(index).unavailableReason;

  void _handleAssessLine(int index) {
    final PronunciationAssessmentTarget? target = _selectLineAssessment(
      index,
    ).target;
    if (target != null) widget.onAssessTarget(target);
  }
}

const double _subtitlePanelWidth = 390;

class _FullscreenSubtitlePanel extends StatelessWidget {
  const _FullscreenSubtitlePanel({
    required this.episodeId,
    required this.player,
    required this.subtitleLetterCase,
    required this.fontScale,
    required this.highlightWords,
    required this.subtitleWordHighlightStyle,
    required this.subtitleWordHighlightBorderWidth,
    required this.onTapLine,
    required this.onCollectWord,
    this.onCollectWordAtTime,
    this.onFavoriteWord,
    required this.onBookmarkLine,
    required this.onLoopFromLine,
    required this.onDictationLine,
    required this.onAiExplain,
    this.onRegenerateAiLine,
    required this.onAssessLine,
    required this.pronunciationUnavailableReasonForLine,
    required this.onTogglePlaying,
    required this.onPronounce,
  });

  final String episodeId;
  final PlayerMockState player;
  final String subtitleLetterCase;
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
  final Future<void> Function(int index)? onRegenerateAiLine;
  final ValueChanged<int> onAssessLine;
  final String? Function(int index) pronunciationUnavailableReasonForLine;
  final VoidCallback onTogglePlaying;
  final VoidCallback onPronounce;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _subtitlePanelWidth,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(left: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: SafeArea(
        bottom: false,
        child: PlayerTranscriptPanel(
          episodeId: episodeId,
          lines: player.lines,
          activeIndex: player.activeLineIndex,
          subtitleMode: player.subtitleMode,
          subtitleLetterCase: subtitleLetterCase,
          currentWordIndex: player.currentWordIndex,
          fontScale: fontScale,
          highlightWords: highlightWords,
          subtitleWordHighlightStyle: subtitleWordHighlightStyle,
          subtitleWordHighlightBorderWidth: subtitleWordHighlightBorderWidth,
          onTapLine: onTapLine,
          onCollectWord: onCollectWord,
          onCollectWordAtTime: onCollectWordAtTime,
          onFavoriteWord: onFavoriteWord,
          onBookmarkLine: onBookmarkLine,
          onLoopFromLine: onLoopFromLine,
          onDictationLine: onDictationLine,
          onAiExplain: onAiExplain,
          onAssessLine: onAssessLine,
          pronunciationUnavailableReasonForLine:
              pronunciationUnavailableReasonForLine,
          onRegenerateAiLine: onRegenerateAiLine,
          loopingLineIndex: player.isLooping ? player.activeLineIndex : null,
          isPlaying: player.isPlaying,
          onTogglePlaying: onTogglePlaying,
          onPronounce: onPronounce,
        ),
      ),
    );
  }
}

const PlayerSubtitleLine _emptySubtitleLine = PlayerSubtitleLine(
  startTime: '',
  english: '',
  chinese: '',
  startMs: 0,
  endMs: 0,
);

void _ignoreLine(int _) {}

void _ignoreTarget(PronunciationAssessmentTarget _) {}

class _FullscreenEpisodePanel extends StatelessWidget {
  const _FullscreenEpisodePanel({
    required this.episodes,
    required this.activeEpisodeId,
    required this.onOpenEpisode,
  });

  final List<LibraryEpisodeItem> episodes;
  final String activeEpisodeId;
  final ValueChanged<LibraryEpisodeItem> onOpenEpisode;

  @override
  Widget build(BuildContext context) {
    final double topInset = MediaQuery.paddingOf(context).top;
    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: Color(0xDD101827),
        border: Border(left: BorderSide(color: Colors.white12)),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(18, topInset > 0 ? 6 : 18, 18, 12),
              child: const Text(
                '选集',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                itemCount: episodes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int index) {
                  final LibraryEpisodeItem episode = episodes[index];
                  final bool isActive = episode.id == activeEpisodeId;
                  return InkWell(
                    onTap: () => onOpenEpisode(episode),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppDesignTokens.brandGreen.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isActive
                              ? AppDesignTokens.brandGreen
                              : Colors.white12,
                          width: isActive ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? AppDesignTokens.brandGreen
                                  : Colors.white.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isActive
                                  ? Icons.play_arrow_rounded
                                  : Icons.menu_book_rounded,
                              color: Colors.white,
                              size: isActive ? 24 : 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '第${episode.numberStr}集',
                                  style: TextStyle(
                                    color: isActive
                                        ? Colors.white
                                        : Colors.white70,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  episode.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  episode.totalTimeStr ??
                                      '${episode.durationMinutes}:00',
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
