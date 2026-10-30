import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../../settings/presentation/settings_provider.dart'
    show playerFontOptions, playerFontScales;
import '../../../shared/domain/subtitle_letter_case.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../shared/presentation/word_lookup_popup.dart';
import '../player_mock_state.dart';
import '../player_native_subtitles.dart';
import 'subtitle_word_highlight_style.dart';

class PlayerVideoPanel extends StatefulWidget {
  const PlayerVideoPanel({
    required this.line,
    required this.isPlaying,
    required this.subtitleMode,
    this.subtitleLetterCase = '保留原样',
    this.fontSize = '中',
    this.fontScale = 1,
    this.onSelectFontSize,
    required this.subtitleModes,
    this.embeddedSubtitleTracks = const <SubtitleTrack>[],
    this.selectedEmbeddedSubtitleId,
    this.currentWordIndex = 0,
    this.highlightWords = false,
    this.subtitleWordHighlightStyle = '绿色填充',
    this.subtitleWordHighlightBorderWidth = 2.5,
    required this.speed,
    required this.isShadowing,
    required this.isLooping,
    required this.isMuted,
    required this.volumeLevel,
    required this.onTogglePlaying,
    required this.onPreviousLine,
    required this.onReplayLine,
    required this.onNextLine,
    required this.onSeekBackward,
    required this.onSeekForward,
    required this.activeIndex,
    required this.totalLines,
    required this.onSelectLine,
    required this.onSeek,
    required this.onSpeedSelected,
    required this.onSelectSubtitleMode,
    this.onSelectSubtitleLetterCase,
    this.onSelectEmbeddedSubtitle,
    required this.onToggleShadowing,
    required this.onToggleLoop,
    required this.onToggleMuted,
    required this.onVolumeChanged,
    required this.onToggleFullscreen,
    this.onSubtitleLookupOpen,
    this.onAssessVisibleLine,
    this.assessmentUnavailableReason,
    this.onCollectWord,
    this.onCollectWordAtTime,
    this.onFavoriteWord,
    this.episodeId,
    this.onPronounce,
    this.onToggleEpisodePanel,
    this.isEpisodePanelOpen = false,
    this.onToggleSubtitlePanel,
    this.isSubtitlePanelOpen = false,
    this.isFullscreen = false,
    this.showSceneHeader = true,
    this.sceneHeaderLeadingInset = 0,
    this.sceneHeaderTopInset,
    this.onControlsVisibilityChanged,
    this.videoSurface,
    this.videoAspectRatio = 16 / 9,
    this.videoReady = false,
    this.videoLoading = false,
    this.videoDuration = Duration.zero,
    this.videoPosition = Duration.zero,
    this.videoErrorText,
    this.showAiGenerateSubtitles = false,
    this.onGenerateAiSubtitles,
    super.key,
  });

  final PlayerSubtitleLine line;
  final bool isPlaying;
  final String subtitleMode;
  final String subtitleLetterCase;
  final String fontSize;
  final double fontScale;
  final ValueChanged<String>? onSelectFontSize;
  final List<String> subtitleModes;
  final List<SubtitleTrack> embeddedSubtitleTracks;
  final String? selectedEmbeddedSubtitleId;
  final int currentWordIndex;
  final bool highlightWords;
  final String subtitleWordHighlightStyle;
  final double subtitleWordHighlightBorderWidth;
  final String speed;
  final bool isShadowing;
  final bool isLooping;
  final bool isMuted;
  final double volumeLevel;
  final VoidCallback onTogglePlaying;
  final VoidCallback onPreviousLine;
  final VoidCallback onReplayLine;
  final VoidCallback onNextLine;
  final VoidCallback onSeekBackward;
  final VoidCallback onSeekForward;
  final int activeIndex;
  final int totalLines;
  final ValueChanged<int> onSelectLine;
  final ValueChanged<double> onSeek;
  final ValueChanged<String> onSpeedSelected;
  final ValueChanged<String> onSelectSubtitleMode;
  final ValueChanged<String>? onSelectSubtitleLetterCase;
  final ValueChanged<SubtitleTrack?>? onSelectEmbeddedSubtitle;
  final VoidCallback onToggleShadowing;
  final VoidCallback onToggleLoop;
  final VoidCallback onToggleMuted;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleFullscreen;
  final VoidCallback? onSubtitleLookupOpen;
  final VoidCallback? onAssessVisibleLine;
  final String? assessmentUnavailableReason;
  final ValueChanged<String>? onCollectWord;
  final void Function(String word, String time)? onCollectWordAtTime;
  final ValueChanged<String>? onFavoriteWord;
  final String? episodeId;
  final VoidCallback? onPronounce;
  final VoidCallback? onToggleEpisodePanel;
  final bool isEpisodePanelOpen;
  final VoidCallback? onToggleSubtitlePanel;
  final bool isSubtitlePanelOpen;
  final bool isFullscreen;
  final bool showSceneHeader;
  final double sceneHeaderLeadingInset;
  final double? sceneHeaderTopInset;
  final ValueChanged<bool>? onControlsVisibilityChanged;
  final Widget? videoSurface;
  final double videoAspectRatio;
  final bool videoReady;
  final bool videoLoading;
  final Duration videoDuration;
  final Duration videoPosition;
  final String? videoErrorText;
  final bool showAiGenerateSubtitles;
  final VoidCallback? onGenerateAiSubtitles;

  static const List<String> kSpeedOptions = <String>[
    '0.5×',
    '0.8×',
    '1.0×',
    '1.25×',
    '1.5×',
    '2.0×',
  ];
  static const String _videoPlaceholderLabel = '24:15';

  @override
  State<PlayerVideoPanel> createState() => _PlayerVideoPanelState();
}

class _PlayerVideoPanelState extends State<PlayerVideoPanel> {
  static const Duration _autoHideDelay = Duration(seconds: 3);
  static const Duration _gestureHintDuration = Duration(milliseconds: 900);

  Timer? _controlsTimer;
  Timer? _gestureHintTimer;
  bool _showControls = true;
  String? _gestureHintText;
  _PlayerGestureMode? _gestureMode;
  Offset? _gestureStartLocalPosition;
  double? _gestureStartProgress;
  double? _gesturePreviewProgress;
  double? _gestureStartVolume;
  double? _gestureStartBrightness;
  double _brightnessLevel = 0.5;
  bool _canChangeSystemBrightness = true;
  OverlayEntry? _subtitleLookupOverlayEntry;
  late final FocusNode _keyboardFocusNode;
  _PlayerContentFit _contentFit = _PlayerContentFit.wide;

  @override
  void initState() {
    super.initState();
    _keyboardFocusNode = FocusNode(debugLabel: 'player-video-controls');
    _scheduleAutoHide();
    unawaited(_loadSystemBrightnessState());
  }

  @override
  void didUpdateWidget(covariant PlayerVideoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying ||
        widget.activeIndex != oldWidget.activeIndex) {
      _scheduleAutoHide();
    }
    if (widget.line.english != oldWidget.line.english) {
      _closeSubtitleLookup();
    }
  }

  @override
  void dispose() {
    _closeSubtitleLookup();
    _controlsTimer?.cancel();
    _gestureHintTimer?.cancel();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _scheduleAutoHide() {
    _controlsTimer?.cancel();
    if (!widget.isPlaying) {
      _setControlsVisible(true);
      return;
    }
    _controlsTimer = Timer(_autoHideDelay, () {
      if (mounted) {
        _setControlsVisible(false);
      }
    });
  }

  void _handleSurfaceTap() {
    _setControlsVisible(!_showControls);
    if (_showControls) {
      _scheduleAutoHide();
    } else {
      _controlsTimer?.cancel();
    }
  }

  void _setControlsVisible(bool visible) {
    if (_showControls == visible) {
      return;
    }
    setState(() => _showControls = visible);
    widget.onControlsVisibilityChanged?.call(visible);
  }

  void _handleControlTap(VoidCallback callback) {
    callback();
    _scheduleAutoHide();
  }

  void _showGestureHint(String text) {
    _gestureHintTimer?.cancel();
    setState(() {
      _gestureHintText = text;
    });
    _gestureHintTimer = Timer(_gestureHintDuration, () {
      if (mounted) {
        setState(() {
          _gestureHintText = null;
        });
      }
    });
  }

  void _openSubtitleLookup(BuildContext anchorContext, String word) {
    _closeSubtitleLookup();
    widget.onSubtitleLookupOpen?.call();
    _setControlsVisible(false);
    final OverlayState overlayState = Overlay.of(context, rootOverlay: true);
    final RenderBox overlayBox =
        overlayState.context.findRenderObject()! as RenderBox;
    final RenderBox anchorBox = anchorContext.findRenderObject()! as RenderBox;
    final Offset anchorTopLeft = anchorBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final Size anchorSize = anchorBox.size;
    _subtitleLookupOverlayEntry = OverlayEntry(
      builder: (BuildContext overlayContext) {
        final EdgeInsets padding = MediaQuery.paddingOf(overlayContext);
        final Size overlaySize = MediaQuery.sizeOf(overlayContext);
        const double popupMaxHeight = 520;
        const double gap = 10;
        const double inset = 16;
        final double popupWidth = (overlaySize.width - inset * 2).clamp(
          0.0,
          WordLookupPopupCard.preferredWidth,
        );
        final double popupHeight = (overlaySize.height - padding.top - 80)
            .clamp(180.0, popupMaxHeight);
        final double left =
            (anchorTopLeft.dx + (anchorSize.width / 2) - (popupWidth / 2))
                .clamp(inset, overlaySize.width - popupWidth - inset);
        final bool showAbove = anchorTopLeft.dy > popupHeight + gap + inset;
        final double top = showAbove
            ? anchorTopLeft.dy - popupHeight - gap
            : (anchorTopLeft.dy + anchorSize.height + gap).clamp(
                padding.top + inset,
                overlaySize.height - popupHeight - inset,
              );
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeSubtitleLookup,
              ),
            ),
            Positioned(
              top: top,
              left: left,
              width: popupWidth,
              child: Material(
                color: Colors.transparent,
                child: WordLookupPopupCard(
                  rawWord: word,
                  episodeId: widget.episodeId,
                  contextTime: widget.line.startTime,
                  contextSentence: widget.line.english,
                  showAbove: showAbove,
                  maxHeight: popupHeight,
                  onPronounce: widget.onPronounce,
                  onClose: _closeSubtitleLookup,
                  onCollect: () {
                    final void Function(String, String)? collect =
                        widget.onCollectWordAtTime;
                    if (collect != null) {
                      collect(word, widget.line.startTime);
                    } else {
                      widget.onCollectWord?.call(word);
                    }
                  },
                  onFavorite: widget.onFavoriteWord == null
                      ? null
                      : () => widget.onFavoriteWord!(word),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlayState.insert(_subtitleLookupOverlayEntry!);
    setState(() {});
  }

  void _closeSubtitleLookup() {
    _subtitleLookupOverlayEntry?.remove();
    _subtitleLookupOverlayEntry = null;
  }

  Future<void> _loadSystemBrightnessState() async {
    try {
      final bool canChange =
          await ScreenBrightness.instance.canChangeSystemBrightness;
      final double systemBrightness = await ScreenBrightness.instance.system;
      if (!mounted) {
        return;
      }
      setState(() {
        _canChangeSystemBrightness = canChange;
        _brightnessLevel = systemBrightness.clamp(0.0, 1.0);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _canChangeSystemBrightness = false;
      });
    }
  }

  void _handleBrightnessChanged(double nextBrightness) {
    if (!_canChangeSystemBrightness) {
      _showGestureHint('系统亮度未授权');
      return;
    }
    final double safeBrightness = nextBrightness.clamp(0.0, 1.0);
    setState(() {
      _brightnessLevel = safeBrightness;
    });
    unawaited(
      ScreenBrightness.instance
          .setSystemScreenBrightness(safeBrightness)
          .catchError((_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _canChangeSystemBrightness = false;
            });
            _showGestureHint('系统亮度未授权');
          }),
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    _keyboardFocusNode.requestFocus();
    _gestureMode = null;
    _gestureStartLocalPosition = event.localPosition;
    _gestureStartProgress = null;
    _gesturePreviewProgress = null;
    _gestureStartVolume = widget.volumeLevel;
    _gestureStartBrightness = _brightnessLevel;
  }

  KeyEventResult _handleKeyboardShortcut(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.mediaPlayPause:
        _handleControlTap(widget.onTogglePlaying);
      case LogicalKeyboardKey.arrowLeft:
        _handleControlTap(widget.onSeekBackward);
      case LogicalKeyboardKey.arrowRight:
        _handleControlTap(widget.onSeekForward);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _handlePointerMove(PointerMoveEvent event, Size size) {
    final Offset? start = _gestureStartLocalPosition;
    if (start == null || size.height <= 0 || size.width <= 0) {
      return;
    }

    final Offset delta = event.localPosition - start;
    if (_gestureMode == null) {
      if (delta.distance < 8) {
        return;
      }
      if (delta.dx.abs() >= delta.dy.abs()) {
        if (widget.videoDuration.inMilliseconds <= 0) {
          return;
        }
        _gestureMode = _PlayerGestureMode.seek;
        _gestureStartProgress =
            widget.videoPosition.inMilliseconds /
            widget.videoDuration.inMilliseconds;
      } else {
        _gestureMode = start.dx >= size.width / 2
            ? _PlayerGestureMode.volume
            : _PlayerGestureMode.brightness;
      }
    }

    switch (_gestureMode) {
      case _PlayerGestureMode.seek:
        if (_gestureStartProgress == null || size.width <= 0) {
          return;
        }
        final double nextProgress =
            (_gestureStartProgress! + delta.dx / size.width).clamp(0.0, 1.0);
        _gesturePreviewProgress = nextProgress;
        final int targetSeconds =
            (widget.videoDuration.inSeconds * nextProgress).round();
        _showGestureHint(_formatDuration(Duration(seconds: targetSeconds)));
        return;
      case _PlayerGestureMode.volume:
        final double nextVolume =
            ((_gestureStartVolume ?? widget.volumeLevel) -
                    delta.dy / size.height)
                .clamp(0.0, 1.0);
        widget.onVolumeChanged(nextVolume);
        _showGestureHint('音量 ${(nextVolume * 100).round()}%');
        return;
      case _PlayerGestureMode.brightness:
        final double nextBrightness =
            ((_gestureStartBrightness ?? _brightnessLevel) -
                    delta.dy / size.height)
                .clamp(0.0, 1.0);
        _handleBrightnessChanged(nextBrightness);
        _showGestureHint('亮度 ${(nextBrightness * 100).round()}%');
        return;
      case null:
        return;
    }
  }

  void _handleGestureEnd() {
    if (_gestureMode == _PlayerGestureMode.seek &&
        _gesturePreviewProgress != null) {
      widget.onSeek(_gesturePreviewProgress!);
    }
    setState(() {
      _gestureMode = null;
      _gestureStartLocalPosition = null;
      _gestureStartProgress = null;
      _gesturePreviewProgress = null;
      _gestureStartVolume = null;
      _gestureStartBrightness = null;
    });
    _scheduleAutoHide();
  }

  String? _overlayText() {
    switch (widget.subtitleMode) {
      case '双语':
        return '${widget.line.english}\n${widget.line.chinese}';
      case '单英':
        return widget.line.english;
      case '单中':
        return widget.line.chinese;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? overlayText = _overlayText();
    final bool showChinese =
        overlayText != null &&
        overlayText.contains('\n') &&
        widget.subtitleMode != '单英';
    final bool showPrimaryButton = _showControls || !widget.isPlaying;
    final Duration safeDuration = widget.videoDuration.isNegative
        ? Duration.zero
        : widget.videoDuration;
    final bool hasVideoDuration = safeDuration.inMilliseconds > 0;
    final double videoProgress = safeDuration.inMilliseconds <= 0
        ? 0
        : (widget.videoPosition.inMilliseconds / safeDuration.inMilliseconds)
              .clamp(0.0, 1.0);
    final double effectiveProgress = _gesturePreviewProgress ?? videoProgress;
    final double surfaceRadius = widget.isFullscreen ? 0 : 24;
    final Widget videoStage = ClipRRect(
      borderRadius: BorderRadius.circular(surfaceRadius),
      child: Material(
        color: widget.isFullscreen ? Colors.black : const Color(0xFF111827),
        child: _buildVideoStage(
          context,
          overlayText,
          showChinese,
          showPrimaryButton,
          hasVideoDuration,
          effectiveProgress,
        ),
      ),
    );

    if (widget.isFullscreen) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: AspectRatio(aspectRatio: 16 / 9, child: videoStage),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x1FFFFFFF)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x240F172A),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: AspectRatio(aspectRatio: 16 / 9, child: videoStage),
    );
  }

  Widget _buildVideoStage(
    BuildContext context,
    String? overlayText,
    bool showChinese,
    bool showPrimaryButton,
    bool hasVideoDuration,
    double effectiveProgress,
  ) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compactControls = constraints.maxWidth < 900;
        final bool tinyControls =
            constraints.maxWidth < 720 || constraints.maxHeight < 430;
        final Size gestureSize = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final double dockInset = widget.isFullscreen ? 24 : 18;
        final double topInset = widget.isFullscreen
            ? 20
            : (tinyControls ? 12 : 16);
        final double sceneHeaderTopInset =
            widget.sceneHeaderTopInset ?? topInset;
        final double subtitleBottom = _showControls
            ? (tinyControls ? 126 : (compactControls ? 138 : 146))
            : 40;
        return Focus(
          focusNode: _keyboardFocusNode,
          autofocus: true,
          onKeyEvent: _handleKeyboardShortcut,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _handlePointerDown,
            onPointerMove: (PointerMoveEvent event) =>
                _handlePointerMove(event, gestureSize),
            onPointerUp: (_) => _handleGestureEnd(),
            onPointerCancel: (_) => _handleGestureEnd(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleSurfaceTap,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _buildVideoBackdrop(),
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Color(0x6B101827),
                            Color(0x1A101827),
                            Color(0x1A101827),
                            Color(0x80101827),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (widget.showSceneHeader)
                    Positioned(
                      top: sceneHeaderTopInset,
                      left: topInset + widget.sceneHeaderLeadingInset,
                      child: AnimatedOpacity(
                        opacity: _showControls ? 1 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: IgnorePointer(
                          ignoring: !_showControls,
                          child: _SceneHeader(
                            compact: tinyControls,
                            title: '学习小剧场',
                            subtitle:
                                '第 ${widget.activeIndex + 1} 句 / ${widget.totalLines} 句',
                            fullscreen: widget.isFullscreen,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: widget.isFullscreen
                        ? topInset
                        : (tinyControls ? 12 : 18),
                    right: widget.isFullscreen ? 20 : (tinyControls ? 12 : 16),
                    child: AnimatedOpacity(
                      opacity: _showControls ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: IgnorePointer(
                        ignoring: !_showControls,
                        child: _StatusBubble(
                          compact: tinyControls,
                          icon: widget.videoErrorText != null
                              ? Icons.info_outline_rounded
                              : Icons.menu_book_rounded,
                          label: widget.videoErrorText ?? '学习模式',
                          background: widget.isFullscreen
                              ? const Color(0x33101827)
                              : (widget.videoErrorText != null
                                    ? const Color(0xCCFFFBEB)
                                    : const Color(0xCCFFFFFF)),
                          foreground: widget.isFullscreen
                              ? Colors.white
                              : (widget.videoErrorText != null
                                    ? AppDesignTokens.textPrimary
                                    : AppDesignTokens.primaryBlueDark),
                        ),
                      ),
                    ),
                  ),
                  if (widget.videoLoading)
                    const Positioned.fill(
                      child: Align(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                  if (overlayText != null)
                    Positioned(
                      left: widget.isFullscreen ? 40 : (tinyControls ? 18 : 24),
                      right: widget.isFullscreen
                          ? 40
                          : (tinyControls ? 18 : 24),
                      bottom: subtitleBottom,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _buildEnglishSubtitle(
                            widget.subtitleMode == '单中'
                                ? overlayText
                                : formatSubtitleLetterCase(
                                    widget.line.english,
                                    widget.subtitleLetterCase,
                                  ),
                            tinyControls: tinyControls,
                          ),
                          if (showChinese) ...<Widget>[
                            SizedBox(height: tinyControls ? 6 : 10),
                            Text(
                              widget.line.chinese,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize:
                                    (widget.isFullscreen
                                        ? (tinyControls ? 15 : 18)
                                        : (tinyControls ? 14 : 16)) *
                                    widget.fontScale,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                                color: const Color(0xFFF7F7F7),
                                shadows: const <Shadow>[
                                  Shadow(
                                    color: Color(0xB3000000),
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  Center(
                    child: AnimatedOpacity(
                      opacity: showPrimaryButton ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: IgnorePointer(
                        ignoring: !showPrimaryButton,
                        child: _PrimaryPlayButton(
                          isPlaying: widget.isPlaying,
                          compact: compactControls,
                          tiny: tinyControls,
                          onPressed: () =>
                              _handleControlTap(widget.onTogglePlaying),
                        ),
                      ),
                    ),
                  ),
                  if (widget.onAssessVisibleLine != null ||
                      widget.assessmentUnavailableReason != null)
                    Positioned(
                      right: dockInset,
                      bottom: _showControls ? subtitleBottom : 18,
                      child: Tooltip(
                        message:
                            widget.assessmentUnavailableReason ?? '跟读录音 · 原声对照',
                        child: IconButton.filledTonal(
                          key: ValueKey<String>(
                            widget.isFullscreen
                                ? 'fullscreen-visible-pronunciation-assessment'
                                : 'player-visible-pronunciation-assessment',
                          ),
                          onPressed:
                              widget.assessmentUnavailableReason != null ||
                                  widget.onAssessVisibleLine == null
                              ? null
                              : () => _handleControlTap(
                                  widget.onAssessVisibleLine!,
                                ),
                          icon: const Icon(Icons.mic_rounded),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF0F7A43),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(44, 44),
                            shape: const CircleBorder(),
                          ),
                        ),
                      ),
                    ),
                  if (_gestureHintText != null)
                    Center(
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xCC101827),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _gestureHintText!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: AnimatedOpacity(
                      opacity: _showControls ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: IgnorePointer(
                        ignoring: !_showControls,
                        child: Stack(
                          children: <Widget>[
                            Positioned(
                              left: dockInset,
                              right: dockInset,
                              bottom: widget.isFullscreen ? 22 : 18,
                              child: _ControlDock(
                                compact: compactControls,
                                tiny: tinyControls,
                                fullscreen: widget.isFullscreen,
                                videoProgress: effectiveProgress,
                                hasVideoDuration: hasVideoDuration,
                                currentLabel: hasVideoDuration
                                    ? _formatDuration(widget.videoPosition)
                                    : widget.line.startTime,
                                totalLabel: hasVideoDuration
                                    ? _formatDuration(widget.videoDuration)
                                    : PlayerVideoPanel._videoPlaceholderLabel,
                                onSeek: widget.onSeek,
                                leadingButtons: <Widget>[
                                  _RoundActionButton(
                                    icon: Icons.skip_previous_rounded,
                                    tooltip: '上一句',
                                    compact: compactControls,
                                    tiny: tinyControls,
                                    fullscreen: widget.isFullscreen,
                                    onPressed: () => _handleControlTap(
                                      widget.onPreviousLine,
                                    ),
                                  ),
                                  _RoundActionButton(
                                    icon: Icons.replay_rounded,
                                    tooltip: '重播当前句',
                                    compact: compactControls,
                                    tiny: tinyControls,
                                    fullscreen: widget.isFullscreen,
                                    onPressed: () =>
                                        _handleControlTap(widget.onReplayLine),
                                  ),
                                  _RoundActionButton(
                                    icon: Icons.skip_next_rounded,
                                    tooltip: '下一句',
                                    compact: compactControls,
                                    tiny: tinyControls,
                                    fullscreen: widget.isFullscreen,
                                    onPressed: () =>
                                        _handleControlTap(widget.onNextLine),
                                  ),
                                ],
                                trailingButtons: <Widget>[
                                  if (widget.showAiGenerateSubtitles)
                                    _RoundActionButton(
                                      icon: Icons.auto_awesome_rounded,
                                      tooltip: 'AI生成可跟读的词级同步字幕',
                                      compact: compactControls,
                                      tiny: tinyControls,
                                      fullscreen: widget.isFullscreen,
                                      onPressed:
                                          widget.onGenerateAiSubtitles == null
                                          ? null
                                          : () => _handleControlTap(
                                              widget.onGenerateAiSubtitles!,
                                            ),
                                    ),
                                  PopupMenuButton<_SubtitleMenuSelection>(
                                    tooltip: '字幕模式',
                                    onSelected: (_SubtitleMenuSelection value) {
                                      if (value.mode != null) {
                                        widget.onSelectSubtitleMode(
                                          value.mode!,
                                        );
                                      } else {
                                        widget.onSelectEmbeddedSubtitle?.call(
                                          value.embeddedTrack,
                                        );
                                      }
                                      _scheduleAutoHide();
                                    },
                                    itemBuilder: (BuildContext context) =>
                                        <
                                          PopupMenuEntry<_SubtitleMenuSelection>
                                        >[
                                          const PopupMenuItem<
                                            _SubtitleMenuSelection
                                          >(
                                            enabled: false,
                                            height: 32,
                                            child: Text('学习字幕'),
                                          ),
                                          ...widget.subtitleModes.map(
                                            (String mode) =>
                                                CheckedPopupMenuItem<
                                                  _SubtitleMenuSelection
                                                >(
                                                  value:
                                                      _SubtitleMenuSelection.mode(
                                                        mode,
                                                      ),
                                                  checked:
                                                      mode ==
                                                      widget.subtitleMode,
                                                  child: Text(mode),
                                                ),
                                          ),
                                          if (widget
                                              .embeddedSubtitleTracks
                                              .isNotEmpty) ...<
                                            PopupMenuEntry<
                                              _SubtitleMenuSelection
                                            >
                                          >[
                                            const PopupMenuDivider(),
                                            const PopupMenuItem<
                                              _SubtitleMenuSelection
                                            >(
                                              enabled: false,
                                              height: 32,
                                              child: Text('视频内置字幕'),
                                            ),
                                            CheckedPopupMenuItem<
                                              _SubtitleMenuSelection
                                            >(
                                              value:
                                                  const _SubtitleMenuSelection.embedded(
                                                    null,
                                                  ),
                                              checked:
                                                  widget
                                                      .selectedEmbeddedSubtitleId ==
                                                  null,
                                              child: const Text('关闭内置字幕'),
                                            ),
                                            ...widget.embeddedSubtitleTracks.map(
                                              (SubtitleTrack track) =>
                                                  CheckedPopupMenuItem<
                                                    _SubtitleMenuSelection
                                                  >(
                                                    value:
                                                        _SubtitleMenuSelection.embedded(
                                                          track,
                                                        ),
                                                    checked:
                                                        track.id ==
                                                        widget
                                                            .selectedEmbeddedSubtitleId,
                                                    child: Text(
                                                      embeddedSubtitleTrackLabel(
                                                        track,
                                                      ),
                                                    ),
                                                  ),
                                            ),
                                          ],
                                        ],
                                    child: _MiniPillAction(
                                      icon: Icons.closed_caption_rounded,
                                      label: tinyControls
                                          ? null
                                          : widget.subtitleMode,
                                      compact: compactControls,
                                      tiny: tinyControls,
                                      fullscreen: widget.isFullscreen,
                                    ),
                                  ),
                                  if (widget.onSelectFontSize != null)
                                    PopupMenuButton<String>(
                                      tooltip: '字幕大小',
                                      onSelected: (String value) {
                                        widget.onSelectFontSize!(value);
                                        _scheduleAutoHide();
                                      },
                                      itemBuilder: (BuildContext context) =>
                                          playerFontOptions
                                              .map(
                                                (
                                                  String size,
                                                ) => CheckedPopupMenuItem<String>(
                                                  value: size,
                                                  checked:
                                                      size == widget.fontSize,
                                                  child: Text(
                                                    '$size（${(playerFontScales[size]! * 100).round()}%）',
                                                  ),
                                                ),
                                              )
                                              .toList(growable: false),
                                      child: _MiniPillAction(
                                        icon: Icons.format_size_rounded,
                                        label: compactControls ? null : '字号',
                                        compact: compactControls,
                                        tiny: tinyControls,
                                        fullscreen: widget.isFullscreen,
                                      ),
                                    ),
                                  if (widget.onSelectSubtitleLetterCase !=
                                          null &&
                                      widget.selectedEmbeddedSubtitleId == null)
                                    PopupMenuButton<String>(
                                      tooltip: '英文字幕大小写',
                                      onSelected: (String value) {
                                        widget.onSelectSubtitleLetterCase!(
                                          value,
                                        );
                                        _scheduleAutoHide();
                                      },
                                      itemBuilder: (BuildContext context) =>
                                          subtitleLetterCaseOptions
                                              .map(
                                                (
                                                  String mode,
                                                ) => CheckedPopupMenuItem<String>(
                                                  value: mode,
                                                  checked:
                                                      mode ==
                                                      widget.subtitleLetterCase,
                                                  child: Text(mode),
                                                ),
                                              )
                                              .toList(growable: false),
                                      child: _MiniPillAction(
                                        icon: Icons.text_fields_rounded,
                                        iconText: 'Aa',
                                        label: compactControls ? null : '大小写',
                                        compact: compactControls,
                                        tiny: tinyControls,
                                        fullscreen: widget.isFullscreen,
                                      ),
                                    ),
                                  PopupMenuButton<String>(
                                    tooltip: '播放速度',
                                    onSelected: (String value) {
                                      widget.onSpeedSelected(value);
                                      _scheduleAutoHide();
                                    },
                                    itemBuilder: (BuildContext context) =>
                                        PlayerVideoPanel.kSpeedOptions
                                            .map(
                                              (String speedValue) =>
                                                  CheckedPopupMenuItem<String>(
                                                    value: speedValue,
                                                    checked:
                                                        speedValue ==
                                                        widget.speed,
                                                    child: Text(speedValue),
                                                  ),
                                            )
                                            .toList(growable: false),
                                    child: _MiniPillAction(
                                      icon: Icons.bolt_rounded,
                                      iconText: widget.speed == '1.0×'
                                          ? null
                                          : widget.speed.replaceAll('×', ''),
                                      label:
                                          tinyControls || widget.speed != '1.0×'
                                          ? null
                                          : widget.speed,
                                      compact: compactControls,
                                      tiny: tinyControls,
                                      fullscreen: widget.isFullscreen,
                                    ),
                                  ),
                                  PopupMenuButton<_PlayerContentFit>(
                                    tooltip: '画面比例',
                                    onSelected: (_PlayerContentFit value) {
                                      setState(() {
                                        _contentFit = value;
                                      });
                                      _scheduleAutoHide();
                                    },
                                    itemBuilder: (BuildContext context) =>
                                        _PlayerContentFit.values
                                            .map(
                                              (_PlayerContentFit fit) =>
                                                  CheckedPopupMenuItem<
                                                    _PlayerContentFit
                                                  >(
                                                    value: fit,
                                                    checked: fit == _contentFit,
                                                    child: Text(fit.label),
                                                  ),
                                            )
                                            .toList(growable: false),
                                    child: _MiniPillAction(
                                      icon: Icons.aspect_ratio_rounded,
                                      label: tinyControls
                                          ? null
                                          : _contentFit.label,
                                      compact: compactControls,
                                      tiny: tinyControls,
                                      fullscreen: widget.isFullscreen,
                                    ),
                                  ),
                                  _RoundActionButton(
                                    icon: widget.isMuted
                                        ? Icons.volume_off_rounded
                                        : Icons.volume_up_rounded,
                                    tooltip: '静音',
                                    active: widget.isMuted,
                                    compact: compactControls,
                                    tiny: tinyControls,
                                    fullscreen: widget.isFullscreen,
                                    onPressed: () =>
                                        _handleControlTap(widget.onToggleMuted),
                                  ),
                                  _RoundActionButton(
                                    icon: Icons.repeat_one_rounded,
                                    tooltip: '单句循环',
                                    active: widget.isLooping,
                                    compact: compactControls,
                                    tiny: tinyControls,
                                    fullscreen: widget.isFullscreen,
                                    onPressed: () =>
                                        _handleControlTap(widget.onToggleLoop),
                                  ),
                                  if (widget.isFullscreen && !tinyControls)
                                    _RoundActionButton(
                                      icon: widget.isSubtitlePanelOpen
                                          ? Icons.subtitles_off_rounded
                                          : Icons.subtitles_rounded,
                                      tooltip: widget.isSubtitlePanelOpen
                                          ? '收起字幕列表'
                                          : '字幕列表',
                                      compact: compactControls,
                                      tiny: tinyControls,
                                      fullscreen: widget.isFullscreen,
                                      onPressed:
                                          widget.onToggleSubtitlePanel == null
                                          ? null
                                          : () => _handleControlTap(
                                              widget.onToggleSubtitlePanel!,
                                            ),
                                    ),
                                  if (widget.isFullscreen && !tinyControls)
                                    _RoundActionButton(
                                      icon: widget.isEpisodePanelOpen
                                          ? Icons.view_sidebar_rounded
                                          : Icons.video_library_rounded,
                                      tooltip: widget.isEpisodePanelOpen
                                          ? '收起选集'
                                          : '选集',
                                      compact: compactControls,
                                      tiny: tinyControls,
                                      fullscreen: widget.isFullscreen,
                                      onPressed:
                                          widget.onToggleEpisodePanel == null
                                          ? null
                                          : () => _handleControlTap(
                                              widget.onToggleEpisodePanel!,
                                            ),
                                    ),
                                  _RoundActionButton(
                                    icon: widget.isFullscreen
                                        ? Icons.fullscreen_exit_rounded
                                        : Icons.fullscreen_rounded,
                                    tooltip: widget.isFullscreen
                                        ? '退出全屏'
                                        : '全屏',
                                    compact: compactControls,
                                    tiny: tinyControls,
                                    fullscreen: widget.isFullscreen,
                                    onPressed: () => _handleControlTap(
                                      widget.onToggleFullscreen,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (widget.totalLines > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Opacity(
                        opacity: 0.01,
                        child: SizedBox(
                          height: 12,
                          child: LayoutBuilder(
                            builder:
                                (
                                  BuildContext context,
                                  BoxConstraints constraints,
                                ) {
                                  final double width = constraints.maxWidth;
                                  return Stack(
                                    children: List<Widget>.generate(
                                      widget.totalLines,
                                      (int index) {
                                        final double ratio =
                                            widget.totalLines == 1
                                            ? 0
                                            : index / (widget.totalLines - 1);
                                        final double left =
                                            (width - 12) * ratio;
                                        return Positioned(
                                          left: left,
                                          top: 0,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            key: ValueKey<String>(
                                              'scrubber-dot-$index',
                                            ),
                                            onTap: () =>
                                                widget.onSelectLine(index),
                                            child: const SizedBox(
                                              width: 12,
                                              height: 12,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEnglishSubtitle(String text, {required bool tinyControls}) {
    final TextStyle style = TextStyle(
      fontSize:
          (widget.isFullscreen
              ? (tinyControls ? 24 : 34)
              : (tinyControls ? 22 : 28)) *
          widget.fontScale,
      fontWeight: FontWeight.w800,
      height: 1.25,
      color: Colors.white,
      shadows: const <Shadow>[
        Shadow(color: Color(0xCC000000), blurRadius: 10, offset: Offset(0, 3)),
      ],
    );
    final List<String> tokens = text
        .split(' ')
        .where((String token) => token.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) {
      return Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: tokens
          .asMap()
          .entries
          .map((MapEntry<int, String> entry) {
            final bool highlighted =
                widget.highlightWords &&
                widget.line.words.isNotEmpty &&
                entry.key == widget.currentWordIndex;
            return Builder(
              builder: (BuildContext tokenContext) {
                return GestureDetector(
                  key: ValueKey<String>('video-subtitle-word-${entry.key}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openSubtitleLookup(tokenContext, entry.value),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: SubtitleWordHighlightStyle.background(
                        widget.subtitleWordHighlightStyle,
                        highlighted: highlighted,
                      ),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: SubtitleWordHighlightStyle.borderColor(
                          widget.subtitleWordHighlightStyle,
                          highlighted: highlighted,
                        ),
                        width: SubtitleWordHighlightStyle.borderWidth(
                          widget.subtitleWordHighlightStyle,
                          highlighted: highlighted,
                          width: widget.subtitleWordHighlightBorderWidth,
                        ),
                      ),
                    ),
                    child: Text(
                      entry.value,
                      style: style.copyWith(
                        decoration: SubtitleWordHighlightStyle.textDecoration(
                          widget.subtitleWordHighlightStyle,
                          highlighted: highlighted,
                        ),
                        decorationColor:
                            SubtitleWordHighlightStyle.textDecorationColor(
                              widget.subtitleWordHighlightStyle,
                              highlighted: highlighted,
                            ),
                        decorationThickness:
                            highlighted &&
                                widget.subtitleWordHighlightStyle == '下划线'
                            ? 2
                            : null,
                      ),
                    ),
                  ),
                );
              },
            );
          })
          .toList(growable: false),
    );
  }

  Widget _buildVideoBackdrop() {
    if (widget.videoSurface == null || !widget.videoReady) {
      return const Positioned.fill(child: ColoredBox(color: Colors.black));
    }

    final Widget video = SizedBox(
      width: 1000 * widget.videoAspectRatio,
      height: 1000,
      child: widget.videoSurface,
    );
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black,
        child: _contentFit == _PlayerContentFit.fill
            ? ClipRect(
                child: FittedBox(fit: BoxFit.cover, child: video),
              )
            : Center(
                child: AspectRatio(
                  key: const ValueKey<String>('player-content-fit-frame'),
                  aspectRatio: _contentFit.aspectRatio,
                  child: ClipRect(
                    child: FittedBox(fit: BoxFit.cover, child: video),
                  ),
                ),
              ),
      ),
    );
  }
}

class _SubtitleMenuSelection {
  const _SubtitleMenuSelection.mode(this.mode) : embeddedTrack = null;

  const _SubtitleMenuSelection.embedded(this.embeddedTrack) : mode = null;

  final String? mode;
  final SubtitleTrack? embeddedTrack;
}

enum _PlayerGestureMode { seek, volume, brightness }

enum _PlayerContentFit {
  fill('撑满', 0),
  wide('16:9', 16 / 9),
  square('1:1', 1);

  const _PlayerContentFit(this.label, this.aspectRatio);

  final String label;
  final double aspectRatio;
}

String _formatDuration(Duration value) {
  final int totalSeconds = value.inSeconds;
  final int minutes = totalSeconds ~/ 60;
  final int seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

class _SceneHeader extends StatelessWidget {
  const _SceneHeader({
    required this.title,
    required this.subtitle,
    this.compact = false,
    this.fullscreen = false,
  });

  final String title;
  final String subtitle;
  final bool compact;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: fullscreen ? const Color(0x33101827) : const Color(0xCCFFFFFF),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              fontSize: compact ? 12 : 14,
              fontWeight: FontWeight.w800,
              color: fullscreen ? Colors.white : AppDesignTokens.textPrimary,
            ),
          ),
          SizedBox(height: compact ? 1 : 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w700,
              color: fullscreen
                  ? Colors.white.withValues(alpha: 0.78)
                  : AppDesignTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBubble extends StatelessWidget {
  const _StatusBubble({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: compact ? 14 : 16, color: foreground),
          SizedBox(width: compact ? 4 : 6),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 120 : 180),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w800,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryPlayButton extends StatelessWidget {
  const _PrimaryPlayButton({
    required this.isPlaying,
    required this.compact,
    required this.tiny,
    required this.onPressed,
  });

  final bool isPlaying;
  final bool compact;
  final bool tiny;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: AppDesignTokens.toyButtonShadow,
      ),
      child: SizedBox(
        width: tiny ? 54 : (compact ? 62 : 76),
        height: tiny ? 54 : (compact ? 62 : 76),
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppDesignTokens.brandGreen,
            foregroundColor: Colors.white,
            padding: EdgeInsets.zero,
            shape: const CircleBorder(),
          ),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: tiny ? 26 : (compact ? 30 : 38),
          ),
        ),
      ),
    );
  }
}

class _ControlDock extends StatelessWidget {
  const _ControlDock({
    required this.compact,
    required this.tiny,
    required this.fullscreen,
    required this.videoProgress,
    required this.hasVideoDuration,
    required this.currentLabel,
    required this.totalLabel,
    required this.onSeek,
    required this.leadingButtons,
    required this.trailingButtons,
  });

  final bool compact;
  final bool tiny;
  final bool fullscreen;
  final double videoProgress;
  final bool hasVideoDuration;
  final String currentLabel;
  final String totalLabel;
  final ValueChanged<double> onSeek;
  final List<Widget> leadingButtons;
  final List<Widget> trailingButtons;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        tiny ? 10 : (compact ? 12 : 16),
        tiny ? 8 : (compact ? 10 : 14),
        tiny ? 10 : (compact ? 12 : 16),
        tiny ? 8 : (compact ? 10 : 14),
      ),
      decoration: BoxDecoration(
        color: fullscreen ? const Color(0xA6101827) : const Color(0xCCFFFFFF),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                currentLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: fullscreen
                      ? Colors.white
                      : AppDesignTokens.textPrimary,
                ),
              ),
              SizedBox(width: tiny ? 8 : 12),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: tiny ? 8 : 10,
                    thumbShape: RoundSliderThumbShape(
                      enabledThumbRadius: tiny ? 6 : 8,
                    ),
                    overlayShape: RoundSliderOverlayShape(
                      overlayRadius: tiny ? 10 : 14,
                    ),
                    activeTrackColor: AppDesignTokens.brandGreen,
                    inactiveTrackColor: fullscreen
                        ? Colors.white24
                        : AppDesignTokens.softGray,
                    thumbColor: AppDesignTokens.brandGreen,
                    overlayColor: AppDesignTokens.brandGreen.withValues(
                      alpha: 0.15,
                    ),
                  ),
                  // Keep the Slider's OverlayPortal in the same semantics
                  // subtree during route and subtitle transitions. Flutter
                  // 3.44 can otherwise send an orphan node to the native AX
                  // bridge and crash on macOS (flutter/flutter#190357).
                  child: Overlay.wrap(
                    alwaysSizeToContent: true,
                    clipBehavior: Clip.none,
                    child: Slider(
                      key: const ValueKey<String>('player-seek-slider'),
                      value: videoProgress.clamp(0.0, 1.0),
                      onChanged: onSeek,
                    ),
                  ),
                ),
              ),
              SizedBox(width: tiny ? 8 : 12),
              Text(
                totalLabel,
                style: TextStyle(
                  fontSize: tiny ? 10 : 11,
                  fontWeight: FontWeight.w800,
                  color: fullscreen
                      ? Colors.white70
                      : AppDesignTokens.textSecondary,
                ),
              ),
            ],
          ),
          SizedBox(height: tiny ? 8 : 10),
          if (compact)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(children: leadingButtons),
                Flexible(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    runSpacing: 6,
                    children: trailingButtons,
                  ),
                ),
              ],
            )
          else
            Row(
              children: <Widget>[
                ...leadingButtons,
                const Spacer(),
                ...trailingButtons,
              ],
            ),
        ],
      ),
    );
  }
}

class _RoundActionButton extends StatelessWidget {
  const _RoundActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.compact = false,
    this.tiny = false,
    this.fullscreen = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final bool compact;
  final bool tiny;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(right: tiny ? 4 : (compact ? 6 : 8)),
      child: Tooltip(
        message: tooltip,
        child: SizedBox(
          width: tiny ? 34 : (compact ? 40 : 48),
          height: tiny ? 34 : (compact ? 40 : 48),
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor: active
                  ? AppDesignTokens.brandGreen
                  : (fullscreen ? const Color(0x33101827) : Colors.white),
              foregroundColor: active
                  ? Colors.white
                  : (fullscreen
                        ? Colors.white
                        : AppDesignTokens.primaryBlueDark),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: Icon(icon, size: tiny ? 16 : (compact ? 18 : 22)),
          ),
        ),
      ),
    );
  }
}

class _MiniPillAction extends StatelessWidget {
  const _MiniPillAction({
    required this.icon,
    required this.label,
    this.iconText,
    this.compact = false,
    this.tiny = false,
    this.fullscreen = false,
  });

  final IconData icon;
  final String? label;
  final String? iconText;
  final bool compact;
  final bool tiny;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(right: tiny ? 4 : (label == null ? 6 : 8)),
      padding: EdgeInsets.symmetric(
        horizontal: tiny ? 10 : (label == null ? 14 : 12),
        vertical: tiny ? 8 : (label == null ? 10 : 12),
      ),
      decoration: BoxDecoration(
        color: fullscreen ? const Color(0x33101827) : Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (iconText != null)
            Text(
              iconText!,
              style: TextStyle(
                fontSize: tiny ? 12 : 14,
                fontWeight: FontWeight.w800,
                color: fullscreen
                    ? Colors.white
                    : AppDesignTokens.primaryBlueDark,
              ),
            )
          else
            Icon(
              icon,
              size: tiny ? 16 : (label == null ? 18 : 20),
              color: fullscreen
                  ? Colors.white
                  : AppDesignTokens.primaryBlueDark,
            ),
          if (label != null) ...<Widget>[
            SizedBox(width: tiny ? 4 : 6),
            Text(
              label!,
              style: TextStyle(
                fontSize: tiny ? 11 : 12,
                fontWeight: FontWeight.w800,
                color: fullscreen
                    ? Colors.white
                    : AppDesignTokens.primaryBlueDark,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
