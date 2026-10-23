import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';

import '../../../shared/domain/subtitle_letter_case.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../shared/presentation/word_lookup_popup.dart';
import '../player_mock_state.dart';
import 'subtitle_word_highlight_style.dart';

const double _activeFontSize = 20;

class PlayerSubtitleList extends StatefulWidget {
  const PlayerSubtitleList({
    required this.lines,
    required this.activeIndex,
    required this.subtitleMode,
    this.subtitleLetterCase = '保留原样',
    this.showCurrentOnly = false,
    required this.currentWordIndex,
    required this.fontScale,
    required this.highlightWords,
    this.subtitleWordHighlightStyle = '绿色填充',
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
    this.isPlaying = false,
    this.onTogglePlaying,
    this.episodeId,
    this.onPronounce,
    this.showAiGenerateSubtitles = false,
    this.generatingAiSubtitles = false,
    this.aiSubtitleProgressValue,
    this.aiSubtitleProgressText,
    this.aiSubtitlePreviewText,
    this.aiSubtitleErrorText,
    this.onGenerateAiSubtitles,
    this.onRegenerateAiSubtitles,
    this.onDeleteAiSubtitles,
    this.onRegenerateAiLine,
    super.key,
  });

  final List<PlayerSubtitleLine> lines;
  final int activeIndex;
  final String subtitleMode;
  final String subtitleLetterCase;
  final bool showCurrentOnly;
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
  final VoidCallback? onTogglePlaying;
  final String? episodeId;
  final VoidCallback? onPronounce;
  final bool showAiGenerateSubtitles;
  final bool generatingAiSubtitles;
  final double? aiSubtitleProgressValue;
  final String? aiSubtitleProgressText;
  final String? aiSubtitlePreviewText;
  final String? aiSubtitleErrorText;
  final VoidCallback? onGenerateAiSubtitles;
  final VoidCallback? onRegenerateAiSubtitles;
  final VoidCallback? onDeleteAiSubtitles;
  final Future<void> Function(int index)? onRegenerateAiLine;

  @override
  State<PlayerSubtitleList> createState() => _PlayerSubtitleListState();
}

class _PlayerSubtitleListState extends State<PlayerSubtitleList> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _rowKeys = <int, GlobalKey>{};
  String? _activeDictionaryTokenId;
  OverlayEntry? _dictionaryOverlayEntry;
  bool _autoFollowCurrentLine = true;
  int? _regeneratingAiLineIndex;

  bool get _showCurrentOnly => widget.showCurrentOnly;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_dismissDictionary);
    if (widget.isPlaying) {
      _scheduleScrollToActiveLine();
    }
  }

  @override
  void didUpdateWidget(covariant PlayerSubtitleList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool listStateChanged =
        oldWidget.activeIndex != widget.activeIndex ||
        oldWidget.lines.length != widget.lines.length ||
        oldWidget.subtitleMode != widget.subtitleMode ||
        oldWidget.showCurrentOnly != widget.showCurrentOnly;
    final bool shouldFollowCurrentLine =
        _autoFollowCurrentLine &&
        widget.isPlaying &&
        (oldWidget.activeIndex != widget.activeIndex ||
            oldWidget.isPlaying != widget.isPlaying);

    if (!listStateChanged && !shouldFollowCurrentLine) {
      return;
    }

    final bool activeLineChanged = oldWidget.activeIndex != widget.activeIndex;
    final bool listStructureChanged =
        oldWidget.lines.length != widget.lines.length ||
        oldWidget.subtitleMode != widget.subtitleMode ||
        oldWidget.showCurrentOnly != widget.showCurrentOnly;

    if (listStructureChanged) {
      _dismissDictionary();
    }

    if (activeLineChanged && _dictionaryOverlayEntry != null) {
      return;
    }

    if (shouldFollowCurrentLine) {
      _scheduleScrollToActiveLine();
    }
  }

  @override
  void dispose() {
    _removeDictionaryOverlay(notify: false);
    _scrollController
      ..removeListener(_dismissDictionary)
      ..dispose();
    super.dispose();
  }

  GlobalKey _rowKeyFor(int index) {
    return _rowKeys[index] ??= GlobalKey(debugLabel: 'subtitle-line-$index');
  }

  void _scrollToActiveLine() {
    if (_showCurrentOnly || !_scrollController.hasClients) {
      return;
    }

    final BuildContext? activeContext =
        _rowKeys[widget.activeIndex]?.currentContext;
    if (activeContext == null) {
      final double targetOffset = (widget.activeIndex * 132.0).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
      return;
    }

    Scrollable.ensureVisible(
      activeContext,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: 0.5,
    );
  }

  void _scheduleScrollToActiveLine() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _autoFollowCurrentLine) {
        _scrollToActiveLine();
      }
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _autoFollowCurrentLine = false;
    }
    return false;
  }

  void _dismissDictionary() {
    if (_activeDictionaryTokenId == null && _dictionaryOverlayEntry == null) {
      return;
    }
    _removeDictionaryOverlay();
  }

  void _removeDictionaryOverlay({bool notify = true}) {
    _dictionaryOverlayEntry?.remove();
    _dictionaryOverlayEntry = null;
    if (!notify || !mounted || _activeDictionaryTokenId == null) {
      return;
    }
    setState(() {
      _activeDictionaryTokenId = null;
    });
  }

  void _toggleDictionaryOverlay(
    BuildContext anchorContext,
    String rawWord,
    String contextSentence,
    String tokenId,
    String contextTime,
  ) {
    if (_activeDictionaryTokenId == tokenId) {
      _removeDictionaryOverlay();
      return;
    }

    _removeDictionaryOverlay(notify: false);

    final OverlayState overlayState = Overlay.of(context, rootOverlay: true);
    final RenderBox overlayBox =
        overlayState.context.findRenderObject()! as RenderBox;
    final RenderBox anchorBox = anchorContext.findRenderObject()! as RenderBox;
    final Offset anchorTopLeft = anchorBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final Size anchorSize = anchorBox.size;
    final Size overlaySize = overlayBox.size;
    const double preferredPopupHeight = 520;
    const double viewportPadding = 16;
    final double popupWidth = (overlaySize.width - viewportPadding * 2).clamp(
      0.0,
      WordLookupPopupCard.preferredWidth,
    );
    const double popupGap = 8;
    final double popupHeight = (overlaySize.height - (viewportPadding * 2))
        .clamp(120.0, preferredPopupHeight);

    final double availableRight =
        overlaySize.width - (anchorTopLeft.dx + anchorSize.width);
    final double availableLeft = anchorTopLeft.dx;
    final double availableBelow =
        overlaySize.height - (anchorTopLeft.dy + anchorSize.height);
    final bool canShowRight = availableRight >= popupWidth + popupGap;
    final bool canShowLeft = availableLeft >= popupWidth + popupGap;
    final bool showRight = canShowRight || !canShowLeft;
    final bool showSide = canShowRight || canShowLeft;
    final bool showAbove =
        !showSide &&
        availableBelow < popupHeight + viewportPadding &&
        anchorTopLeft.dy > availableBelow;

    final double left;
    final double top;
    if (showSide) {
      left = showRight
          ? (anchorTopLeft.dx + anchorSize.width + popupGap).clamp(
              viewportPadding,
              overlaySize.width - popupWidth - viewportPadding,
            )
          : (anchorTopLeft.dx - popupWidth - popupGap).clamp(
              viewportPadding,
              overlaySize.width - popupWidth - viewportPadding,
            );
      top = (anchorTopLeft.dy + (anchorSize.height / 2) - (popupHeight / 2))
          .clamp(
            viewportPadding,
            overlaySize.height - popupHeight - viewportPadding,
          );
    } else {
      final double unclampedLeft =
          anchorTopLeft.dx + (anchorSize.width / 2) - (popupWidth / 2);
      left = unclampedLeft.clamp(
        viewportPadding,
        overlaySize.width - popupWidth - viewportPadding,
      );
      top = showAbove
          ? (anchorTopLeft.dy - popupHeight - popupGap).clamp(
              viewportPadding,
              overlaySize.height - popupHeight - viewportPadding,
            )
          : (anchorTopLeft.dy + anchorSize.height + popupGap).clamp(
              viewportPadding,
              overlaySize.height - popupHeight - viewportPadding,
            );
    }

    _dictionaryOverlayEntry = OverlayEntry(
      builder: (BuildContext overlayContext) {
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _dismissDictionary,
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: popupWidth,
              child: Material(
                color: Colors.transparent,
                child: WordLookupPopupCard(
                  rawWord: rawWord,
                  episodeId: widget.episodeId,
                  contextTime: contextTime,
                  contextSentence: contextSentence,
                  showAbove: showAbove,
                  showSide: showSide,
                  showRight: showRight,
                  maxHeight: popupHeight,
                  onPronounce: widget.onPronounce,
                  onClose: _dismissDictionary,
                  onCollect: () {
                    final void Function(String, String)? collect =
                        widget.onCollectWordAtTime;
                    if (collect != null) {
                      collect(rawWord, contextTime);
                    } else {
                      widget.onCollectWord(rawWord);
                    }
                  },
                  onFavorite: widget.onFavoriteWord == null
                      ? null
                      : () => widget.onFavoriteWord!(rawWord),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlayState.insert(_dictionaryOverlayEntry!);
    setState(() {
      _activeDictionaryTokenId = tokenId;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.subtitleMode == '隐藏') {
      return _SubtitlePlaceholder(
        icon: Icons.closed_caption_disabled_outlined,
        title: '字幕已隐藏',
        body: '在播放器控制栏中重新开启字幕后可恢复列表。',
        showAiGenerateSubtitles: widget.showAiGenerateSubtitles,
        generatingAiSubtitles: widget.generatingAiSubtitles,
        progressValue: widget.aiSubtitleProgressValue,
        progressText: widget.aiSubtitleProgressText,
        previewText: widget.aiSubtitlePreviewText,
        errorText: widget.aiSubtitleErrorText,
        onGenerateAiSubtitles: widget.onGenerateAiSubtitles,
      );
    }

    final int totalLineCount = widget.lines.length;
    if (totalLineCount == 0 && widget.showAiGenerateSubtitles) {
      return _SubtitlePlaceholder(
        icon: Icons.auto_awesome_rounded,
        title: '当前视频没有字幕',
        body: '可生成可随播放逐词高亮的 AI 词级同步字幕。',
        showAiGenerateSubtitles: widget.showAiGenerateSubtitles,
        generatingAiSubtitles: widget.generatingAiSubtitles,
        progressValue: widget.aiSubtitleProgressValue,
        progressText: widget.aiSubtitleProgressText,
        previewText: widget.aiSubtitlePreviewText,
        errorText: widget.aiSubtitleErrorText,
        onGenerateAiSubtitles: widget.onGenerateAiSubtitles,
      );
    }

    final int itemCount = _showCurrentOnly ? 1 : totalLineCount;

    final Widget list = SelectionArea(
      key: const ValueKey<String>('subtitle-list-selection-area'),
      onSelectionChanged: (SelectedContent? selection) {
        if (selection?.plainText.trim().isNotEmpty ?? false) {
          _autoFollowCurrentLine = false;
        }
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.all(2),
          itemCount: itemCount,
          itemBuilder: (BuildContext context, int itemIndex) {
            final int originalIndex = _showCurrentOnly
                ? widget.activeIndex
                : itemIndex;
            if (originalIndex < 0 || originalIndex >= totalLineCount) {
              return const SizedBox.shrink();
            }

            final PlayerSubtitleLine line = widget.lines[originalIndex];
            final bool active = originalIndex == widget.activeIndex;
            final bool isLooping = originalIndex == widget.loopingLineIndex;
            final bool isPast = originalIndex < widget.activeIndex;
            final double textOpacity = active ? 1 : (isPast ? 0.84 : 0.60);
            final double chineseFontSize =
                (active ? 19.0 : 17.0) * widget.fontScale;
            final double subtitleFontSize = 15 * widget.fontScale;
            const Color inactiveStartTimeColor = Color(0xFFADB7B0);
            const Color inactiveZhTextColor = Color(0xFFB7C2BA);

            return InkWell(
              key: _rowKeyFor(originalIndex),
              onTap: () => widget.onTapLine(originalIndex),
              onLongPress: () => _openActions(context, line, originalIndex),
              borderRadius: BorderRadius.circular(20),
              child: Ink(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFFEFFFF5) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: active
                        ? AppDesignTokens.brandGreen
                        : const Color(0xFFE1E7E1),
                    width: active ? 2.5 : 1.5,
                  ),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x0F000000),
                      blurRadius: 10,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Stack(
                  children: <Widget>[
                    if (active)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7D6),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text(
                            '正在学习',
                            style: TextStyle(
                              color: AppDesignTokens.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            FilledButton.tonal(
                              onPressed: active
                                  ? widget.onTogglePlaying
                                  : () => widget.onTapLine(originalIndex),
                              style: FilledButton.styleFrom(
                                backgroundColor: active
                                    ? const Color(0xFFDFF8C8)
                                    : AppDesignTokens.softWhite,
                                foregroundColor: active
                                    ? AppDesignTokens.brandGreenDark
                                    : AppDesignTokens.primaryBlueDark,
                                minimumSize: const Size(44, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Icon(
                                active && widget.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                line.startTime,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: active
                                      ? const Color(0xFF7E8A82)
                                      : inactiveStartTimeColor.withValues(
                                          alpha: textOpacity,
                                        ),
                                ),
                              ),
                            ),
                            FilledButton.tonal(
                              key: ValueKey<String>(
                                'subtitle-line-loop-$originalIndex',
                              ),
                              onPressed: () =>
                                  widget.onLoopFromLine(originalIndex),
                              style: FilledButton.styleFrom(
                                backgroundColor: isLooping
                                    ? const Color(0xFFDFF8C8)
                                    : AppDesignTokens.softWhite,
                                foregroundColor: isLooping
                                    ? AppDesignTokens.brandGreenDark
                                    : AppDesignTokens.textSecondary,
                                minimumSize: const Size(44, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Icon(Icons.repeat_one_rounded),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonal(
                              onPressed: () =>
                                  widget.onBookmarkLine(originalIndex),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFFFF7D6),
                                foregroundColor: const Color(0xFFB58600),
                                minimumSize: const Size(44, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Icon(Icons.star_rounded),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonal(
                              onPressed: () =>
                                  _openActions(context, line, originalIndex),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppDesignTokens.softWhite,
                                foregroundColor: AppDesignTokens.textSecondary,
                                minimumSize: const Size(44, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Icon(Icons.more_horiz_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (widget.subtitleMode == '单中')
                          Text(
                            line.chinese,
                            style: TextStyle(
                              fontSize: chineseFontSize,
                              fontWeight: active
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: active
                                  ? const Color(0xFF191C1E)
                                  : inactiveZhTextColor.withValues(
                                      alpha: textOpacity,
                                    ),
                              height: 1.35,
                            ),
                          )
                        else
                          _buildWordLine(
                            formatSubtitleLetterCase(
                              line.english,
                              widget.subtitleLetterCase,
                            ),
                            active && line.words.isNotEmpty
                                ? widget.currentWordIndex
                                : null,
                            active,
                            line.startTime,
                          ),
                        if (widget.subtitleMode != '单英') ...<Widget>[
                          const _SelectableLineBreak(),
                          const SizedBox(height: 4),
                          Text(
                            line.chinese,
                            style: TextStyle(
                              fontSize: subtitleFontSize,
                              color: active
                                  ? const Color(0xFF708077)
                                  : inactiveZhTextColor.withValues(
                                      alpha: textOpacity,
                                    ),
                              height: 1.45,
                            ),
                          ),
                        ],
                        const _SelectableLineBreak(),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
          separatorBuilder: (_, __) => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              children: <Widget>[
                SizedBox(height: 4),
                Divider(
                  key: ValueKey<String>('subtitle-list-divider'),
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFE6EBE7),
                ),
                SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
    return Column(
      children: <Widget>[
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextButton.icon(
                onPressed: () {
                  _autoFollowCurrentLine = true;
                  _scrollToActiveLine();
                },
                icon: const Icon(Icons.my_location_rounded),
                label: const Text('定位当前'),
              ),
              if (widget.onRegenerateAiSubtitles != null)
                TextButton.icon(
                  onPressed: widget.onRegenerateAiSubtitles,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重新生成'),
                ),
              if (widget.onDeleteAiSubtitles != null)
                TextButton.icon(
                  onPressed: widget.onDeleteAiSubtitles,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('切回原始字幕'),
                ),
            ],
          ),
        ),
        Expanded(child: list),
      ],
    );
  }

  Future<void> _openActions(
    BuildContext context,
    PlayerSubtitleLine line,
    int index,
  ) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.bookmark_add_outlined),
                  title: const Text('收藏到短语库'),
                  onTap: () => Navigator.of(context).pop('bookmark'),
                ),
                ListTile(
                  leading: const Icon(Icons.copy_all_rounded),
                  title: const Text('复制英文'),
                  onTap: () => Navigator.of(context).pop('copy-en'),
                ),
                ListTile(
                  leading: const Icon(Icons.translate_rounded),
                  title: const Text('复制中英双语'),
                  onTap: () => Navigator.of(context).pop('copy-bi'),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('AI 解释这句话'),
                  onTap: () => Navigator.of(context).pop('ai-explain'),
                ),
                if (widget.onRegenerateAiLine != null)
                  ListTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: const Text('AI 重新生成当前句'),
                    subtitle: const Text('只替换这一句，失败时保留原句'),
                    trailing: _regeneratingAiLineIndex == index
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    enabled: _regeneratingAiLineIndex == null,
                    onTap: _regeneratingAiLineIndex == null
                        ? () => Navigator.of(context).pop('regenerate-ai-line')
                        : null,
                  ),
                ListTile(
                  leading: const Icon(Icons.repeat_one_rounded),
                  title: const Text('从这里开始循环'),
                  onTap: () => Navigator.of(context).pop('loop'),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_note_rounded),
                  title: const Text('加入听写练习'),
                  onTap: () => Navigator.of(context).pop('dictation'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!context.mounted || action == null) {
      return;
    }

    switch (action) {
      case 'bookmark':
        widget.onBookmarkLine(index);
        return;
      case 'copy-en':
        await Clipboard.setData(ClipboardData(text: line.english));
        if (!context.mounted) {
          return;
        }
        _showMessage(context, '已复制英文');
        return;
      case 'copy-bi':
        await Clipboard.setData(
          ClipboardData(text: '${line.english}\n${line.chinese}'),
        );
        if (!context.mounted) {
          return;
        }
        _showMessage(context, '已复制中英双语');
        return;
      case 'loop':
        widget.onLoopFromLine(index);
        return;
      case 'dictation':
        widget.onDictationLine(index);
        return;
      case 'ai-explain':
        widget.onAiExplain(index);
        return;
      case 'regenerate-ai-line':
        final Future<void> Function(int index)? regenerate =
            widget.onRegenerateAiLine;
        if (regenerate == null || _regeneratingAiLineIndex != null) return;
        setState(() {
          _regeneratingAiLineIndex = index;
        });
        try {
          await regenerate(index);
        } finally {
          if (mounted) {
            setState(() {
              _regeneratingAiLineIndex = null;
            });
          }
        }
        return;
    }
  }

  Widget _buildWordLine(
    String text,
    int? highlightIndex,
    bool active,
    String contextTime,
  ) {
    final List<_WordToken> tokens = text
        .split(' ')
        .where((String rawWord) => rawWord.isNotEmpty)
        .map((String rawWord) => _WordToken(value: rawWord))
        .toList(growable: false);

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: tokens
          .asMap()
          .entries
          .map((MapEntry<int, _WordToken> entry) {
            final int index = entry.key;
            final _WordToken token = entry.value;
            final bool highlighted =
                active &&
                widget.highlightWords &&
                highlightIndex != null &&
                index == highlightIndex;
            final String tokenId = '$text-$index';

            return Builder(
              builder: (BuildContext wordContext) {
                return InkWell(
                  onTap: () => _toggleDictionaryOverlay(
                    wordContext,
                    token.value,
                    text,
                    tokenId,
                    contextTime,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: SubtitleWordHighlightStyle.background(
                        widget.subtitleWordHighlightStyle,
                        highlighted: highlighted,
                      ),
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
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        Text(
                          token.value,
                          style: TextStyle(
                            fontSize: active
                                ? _activeFontSize * widget.fontScale
                                : (_activeFontSize * widget.fontScale) - 2,
                            fontWeight: highlighted
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: AppDesignTokens.textPrimary,
                            decoration:
                                SubtitleWordHighlightStyle.textDecoration(
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
                            height: 1.35,
                          ),
                        ),
                        if (index != tokens.length - 1)
                          const Positioned(
                            right: -1,
                            bottom: 0,
                            child: IgnorePointer(child: Text(' ')),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          })
          .toList(growable: false),
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _WordToken {
  const _WordToken({required this.value});

  final String value;
}

class _SelectableLineBreak extends StatelessWidget {
  const _SelectableLineBreak();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: SizedBox(
        height: 0.01,
        child: Text(
          '\n',
          style: TextStyle(
            fontSize: 1,
            height: 0.01,
            color: Colors.transparent,
          ),
        ),
      ),
    );
  }
}

class _SubtitlePlaceholder extends StatelessWidget {
  const _SubtitlePlaceholder({
    required this.icon,
    required this.title,
    required this.body,
    required this.showAiGenerateSubtitles,
    required this.generatingAiSubtitles,
    required this.progressValue,
    required this.progressText,
    required this.previewText,
    required this.errorText,
    required this.onGenerateAiSubtitles,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool showAiGenerateSubtitles;
  final bool generatingAiSubtitles;
  final double? progressValue;
  final String? progressText;
  final String? previewText;
  final String? errorText;
  final VoidCallback? onGenerateAiSubtitles;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 34, color: const Color(0xFF9AA69E)),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF53625A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Color(0xFF7E8A82),
              ),
            ),
            if (showAiGenerateSubtitles) ...<Widget>[
              const SizedBox(height: 14),
              if (!generatingAiSubtitles &&
                  (errorText?.isNotEmpty ?? false)) ...<Widget>[
                SizedBox(
                  width: 320,
                  child: Text(
                    '生成失败：$errorText',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Color(0xFFC62828),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (generatingAiSubtitles) ...<Widget>[
                SizedBox(
                  width: 240,
                  child: LinearProgressIndicator(value: progressValue),
                ),
                const SizedBox(height: 10),
                Text(
                  progressText ?? '正在准备音频...',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF53625A),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 300,
                  height: 44,
                  child: Text(
                    previewText?.isNotEmpty ?? false
                        ? previewText!
                        : '等待识别文本...',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Color(0xFF53625A),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              FilledButton.icon(
                onPressed: generatingAiSubtitles ? null : onGenerateAiSubtitles,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text(
                  generatingAiSubtitles ? '正在生成词级同步字幕...' : 'AI生成可跟读的词级同步字幕',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
