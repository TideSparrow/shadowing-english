import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/presentation/settings_provider.dart';
import '../../shared/data/word_lookup_service.dart';
import '../../shared/data/word_pronunciation_service.dart';
import '../../shared/domain/subtitle_letter_case.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/word_lookup_popup.dart';
import '../../words/data/offline_word_dictionary.dart';
import 'player_mock_state.dart';

class TranscriptReaderProgress {
  const TranscriptReaderProgress({
    required this.lineIndex,
    required this.wordIndex,
    this.loopingLineIndex,
    this.subtitleLetterCase,
  });

  factory TranscriptReaderProgress.fromJson(Map<dynamic, dynamic> json) {
    return TranscriptReaderProgress(
      lineIndex: json['lineIndex'] as int? ?? 0,
      wordIndex: json['wordIndex'] as int? ?? 0,
      loopingLineIndex: json['loopingLineIndex'] as int?,
      subtitleLetterCase: json['subtitleLetterCase'] as String?,
    );
  }

  final int lineIndex;
  final int wordIndex;
  final int? loopingLineIndex;
  final String? subtitleLetterCase;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'lineIndex': lineIndex,
    'wordIndex': wordIndex,
    'loopingLineIndex': loopingLineIndex,
    'subtitleLetterCase': subtitleLetterCase,
  };
}

class TranscriptReaderSnapshot {
  const TranscriptReaderSnapshot({
    required this.courseTitle,
    this.subtitleLetterCase = '保留原样',
    required this.episodeTitle,
    required this.lines,
    required this.meanings,
    required this.progress,
  });

  factory TranscriptReaderSnapshot.fromJson(Map<dynamic, dynamic> json) {
    return TranscriptReaderSnapshot(
      courseTitle: json['courseTitle'] as String? ?? '',
      subtitleLetterCase: json['subtitleLetterCase'] as String? ?? '保留原样',
      episodeTitle: json['episodeTitle'] as String? ?? '',
      lines: (json['lines'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<dynamic, dynamic>>()
          .map(_lineFromJson)
          .toList(growable: false),
      meanings:
          (json['meanings'] as Map<dynamic, dynamic>? ??
                  const <dynamic, dynamic>{})
              .map(
                (dynamic key, dynamic value) =>
                    MapEntry<String, String>(key as String, value as String),
              ),
      progress: TranscriptReaderProgress.fromJson(
        json['progress'] as Map<dynamic, dynamic>? ??
            const <dynamic, dynamic>{},
      ),
    );
  }

  final String courseTitle;
  final String subtitleLetterCase;
  final String episodeTitle;
  final List<PlayerSubtitleLine> lines;
  final Map<String, String> meanings;
  final TranscriptReaderProgress progress;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'courseTitle': courseTitle,
    'subtitleLetterCase': subtitleLetterCase,
    'episodeTitle': episodeTitle,
    'lines': lines.map(_lineToJson).toList(growable: false),
    'meanings': meanings,
    'progress': progress.toJson(),
  };
}

Future<TranscriptReaderSnapshot> buildTranscriptReaderSnapshot({
  String subtitleLetterCase = '保留原样',
  required String courseTitle,
  required String episodeTitle,
  required List<PlayerSubtitleLine> lines,
  required int activeLineIndex,
  required int currentWordIndex,
  int? loopingLineIndex,
  required Map<String, String> generatedMeanings,
  required OfflineWordDictionary dictionary,
}) async {
  final Set<String> words = <String>{
    for (final PlayerSubtitleLine line in lines)
      for (final String token in transcriptReaderTokens(line))
        if (normalizeTranscriptReaderWord(token).isNotEmpty)
          normalizeTranscriptReaderWord(token),
  };
  final List<String> missingWords = words
      .where((String word) => (generatedMeanings[word] ?? '').trim().isEmpty)
      .toList(growable: false);
  final List<OfflineWordDefinition?> offlineDefinitions = await Future.wait(
    missingWords.map(dictionary.lookup),
  );
  final Map<String, String> meanings = <String, String>{
    for (final String word in words)
      if ((generatedMeanings[word] ?? '').trim().isNotEmpty)
        word: generatedMeanings[word]!.trim(),
  };
  for (int index = 0; index < missingWords.length; index++) {
    final String translation =
        offlineDefinitions[index]?.translation.trim() ?? '';
    if (translation.isNotEmpty) {
      meanings[missingWords[index]] = translation;
    }
  }

  return TranscriptReaderSnapshot(
    subtitleLetterCase: subtitleLetterCase,
    courseTitle: courseTitle,
    episodeTitle: episodeTitle,
    lines: lines,
    meanings: meanings,
    progress: TranscriptReaderProgress(
      lineIndex: activeLineIndex,
      wordIndex: currentWordIndex,
      loopingLineIndex: loopingLineIndex,
      subtitleLetterCase: subtitleLetterCase,
    ),
  );
}

List<String> transcriptReaderTokens(PlayerSubtitleLine line) => line.english
    .trim()
    .split(RegExp(r'\s+'))
    .where((String token) => token.isNotEmpty)
    .toList(growable: false);

String normalizeTranscriptReaderWord(String value) {
  final Match? match = RegExp("[A-Za-z]+(?:['’][A-Za-z]+)?").firstMatch(value);
  return (match?.group(0) ?? '').toLowerCase().replaceAll('’', "'");
}

Duration transcriptReaderWordHighlightInterval(
  PlayerSubtitleLine line, {
  required double speechRate,
}) {
  final int wordCount = transcriptReaderTokens(line).length;
  if (wordCount == 0) return Duration.zero;
  final int lineDurationMs = line.endMs - line.startMs;
  final int sourceIntervalMs = lineDurationMs > 0
      ? (lineDurationMs / wordCount).round()
      : 420;
  final double normalizedRate = speechRate.clamp(0.5, 1.25);
  final int intervalMs = (sourceIntervalMs / normalizedRate).round();
  return Duration(milliseconds: intervalMs.clamp(280, 900));
}

Duration transcriptReaderFollowAlongPause(PlayerSubtitleLine line) {
  final int lineDurationMs = line.endMs - line.startMs;
  final int pauseMs = lineDurationMs > 0 ? (lineDurationMs * 0.2).round() : 500;
  return Duration(milliseconds: pauseMs.clamp(350, 900));
}

class FullTranscriptReaderScreen extends ConsumerStatefulWidget {
  const FullTranscriptReaderScreen({
    required this.snapshot,
    required this.progressListenable,
    required this.onClose,
    this.onPlayFullTranscript,
    this.onToggleLineLoop,
    super.key,
  });

  final TranscriptReaderSnapshot snapshot;
  final ValueListenable<TranscriptReaderProgress> progressListenable;
  final VoidCallback onClose;
  final FutureOr<void> Function()? onPlayFullTranscript;
  final FutureOr<void> Function(int lineIndex)? onToggleLineLoop;

  @override
  ConsumerState<FullTranscriptReaderScreen> createState() =>
      _FullTranscriptReaderScreenState();
}

class _FullTranscriptReaderScreenState
    extends ConsumerState<FullTranscriptReaderScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _activeWordKey = GlobalKey();
  late TranscriptReaderProgress _progress;
  bool _showTranslations = true;
  bool _hasTextSelection = false;
  bool _isListeningFullTranscript = false;
  bool _isFullTranscriptPaused = false;
  int _narrationRun = 0;
  WordPronunciationService? _activePronunciationService;
  Timer? _narrationTimer;
  Completer<void>? _narrationDelayCompleter;
  String? _activeLookupTokenId;
  OverlayEntry? _lookupOverlayEntry;

  @override
  void initState() {
    super.initState();
    _progress = widget.progressListenable.value;
    widget.progressListenable.addListener(_handleProgressChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealActiveWord());
  }

  @override
  void didUpdateWidget(FullTranscriptReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progressListenable != widget.progressListenable) {
      oldWidget.progressListenable.removeListener(_handleProgressChanged);
      widget.progressListenable.addListener(_handleProgressChanged);
      _progress = widget.progressListenable.value;
    }
  }

  @override
  void dispose() {
    _narrationRun += 1;
    _cancelNarrationDelay();
    final WordPronunciationService? pronunciation = _activePronunciationService;
    if (pronunciation != null) {
      unawaited(pronunciation.stop().catchError((Object _) {}));
    }
    _removeWordLookupOverlay();
    widget.progressListenable.removeListener(_handleProgressChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleProgressChanged() {
    final TranscriptReaderProgress next = widget.progressListenable.value;
    final bool positionChanged =
        next.lineIndex != _progress.lineIndex ||
        next.wordIndex != _progress.wordIndex ||
        next.loopingLineIndex != _progress.loopingLineIndex;
    if (!positionChanged &&
        next.subtitleLetterCase == _progress.subtitleLetterCase) {
      return;
    }
    setState(() => _progress = next);
    if (positionChanged && !_hasTextSelection) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealActiveWord());
    }
  }

  Future<void> _revealActiveWord() async {
    if (!mounted) return;
    final BuildContext? activeContext = _activeWordKey.currentContext;
    if (activeContext != null) {
      await Scrollable.ensureVisible(
        activeContext,
        alignment: 0.42,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    if (!_scrollController.hasClients || widget.snapshot.lines.length < 2) {
      return;
    }
    final double target =
        _scrollController.position.maxScrollExtent *
        (_progress.lineIndex / (widget.snapshot.lines.length - 1));
    await _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    final BuildContext? revealedContext = _activeWordKey.currentContext;
    if (revealedContext != null && revealedContext.mounted) {
      await Scrollable.ensureVisible(
        revealedContext,
        alignment: 0.42,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _dismissWordLookup() {
    if (_lookupOverlayEntry == null && _activeLookupTokenId == null) return;
    _removeWordLookupOverlay();
  }

  void _removeWordLookupOverlay() {
    _lookupOverlayEntry?.remove();
    _lookupOverlayEntry = null;
    _activeLookupTokenId = null;
  }

  Future<void> _listenFullTranscript() async {
    if (_isListeningFullTranscript) return;
    if (widget.snapshot.lines.isEmpty) return;
    final int narrationRun = ++_narrationRun;
    final int startLineIndex = _isFullTranscriptPaused
        ? _progress.lineIndex.clamp(0, widget.snapshot.lines.length - 1)
        : 0;
    setState(() {
      _isListeningFullTranscript = true;
      _isFullTranscriptPaused = false;
    });
    try {
      final FutureOr<void> Function()? playOriginal =
          widget.onPlayFullTranscript;
      if (playOriginal != null) {
        try {
          await playOriginal();
          return;
        } catch (_) {
          // The player may have closed while the transcript window stays open.
        }
      }
      final WordPronunciationService pronunciation = ref.read(
        wordPronunciationServiceProvider,
      );
      final double speechRate = ref.read(learningSettingsProvider).ttsRate;
      _activePronunciationService = pronunciation;
      final List<PlayerSubtitleLine> lines = widget.snapshot.lines;
      for (
        int lineIndex = startLineIndex;
        lineIndex < lines.length;
        lineIndex++
      ) {
        if (!_isNarrationActive(narrationRun)) return;
        final PlayerSubtitleLine line = lines[lineIndex];
        final String text = line.english.trim();
        final List<String> tokens = transcriptReaderTokens(line);
        if (text.isEmpty || tokens.isEmpty) continue;

        await Future.wait<void>(<Future<void>>[
          pronunciation.speak(text),
          _trackNarratedWords(
            narrationRun: narrationRun,
            line: line,
            lineIndex: lineIndex,
            wordCount: tokens.length,
            speechRate: speechRate,
          ),
        ]);
        if (!_isNarrationActive(narrationRun) ||
            lineIndex == lines.length - 1) {
          continue;
        }
        await _waitForNarrationDelay(transcriptReaderFollowAlongPause(line));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('朗读失败，请检查设备 TTS。')));
    } finally {
      if (mounted && narrationRun == _narrationRun) {
        _activePronunciationService = null;
        setState(() {
          _isListeningFullTranscript = false;
          _isFullTranscriptPaused = false;
        });
      }
    }
  }

  Future<void> _toggleFullTranscriptNarration() async {
    if (_isListeningFullTranscript) {
      await _stopFullTranscriptNarration(rememberPosition: true);
      return;
    }
    await _listenFullTranscript();
  }

  Future<void> _stopFullTranscriptNarration({
    required bool rememberPosition,
  }) async {
    _narrationRun += 1;
    _cancelNarrationDelay();
    final WordPronunciationService? pronunciation = _activePronunciationService;
    _activePronunciationService = null;
    if (mounted) {
      setState(() {
        _isListeningFullTranscript = false;
        _isFullTranscriptPaused = rememberPosition;
      });
    }
    if (pronunciation != null) {
      try {
        await pronunciation.stop();
      } catch (_) {
        // Closing or pausing should still finish even if the TTS engine exited.
      }
    }
  }

  Future<void> _closeReader() async {
    await _stopFullTranscriptNarration(rememberPosition: false);
    widget.onClose();
  }

  bool _isNarrationActive(int narrationRun) {
    return mounted && narrationRun == _narrationRun;
  }

  Future<void> _waitForNarrationDelay(Duration duration) {
    final Completer<void> completer = Completer<void>();
    _narrationDelayCompleter = completer;
    _narrationTimer = Timer(duration, () {
      if (identical(_narrationDelayCompleter, completer)) {
        _narrationDelayCompleter = null;
        _narrationTimer = null;
      }
      completer.complete();
    });
    return completer.future;
  }

  void _cancelNarrationDelay() {
    _narrationTimer?.cancel();
    _narrationTimer = null;
    final Completer<void>? completer = _narrationDelayCompleter;
    _narrationDelayCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  Future<void> _trackNarratedWords({
    required int narrationRun,
    required PlayerSubtitleLine line,
    required int lineIndex,
    required int wordCount,
    required double speechRate,
  }) async {
    final Duration interval = transcriptReaderWordHighlightInterval(
      line,
      speechRate: speechRate,
    );
    for (int wordIndex = 0; wordIndex < wordCount; wordIndex++) {
      if (!_isNarrationActive(narrationRun)) return;
      setState(
        () => _progress = TranscriptReaderProgress(
          lineIndex: lineIndex,
          wordIndex: wordIndex,
          loopingLineIndex: _progress.loopingLineIndex,
          subtitleLetterCase: _progress.subtitleLetterCase,
        ),
      );
      if (!_hasTextSelection) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _revealActiveWord(),
        );
      }
      await _waitForNarrationDelay(interval);
    }
  }

  void _toggleWordLookup({
    required BuildContext anchorContext,
    required String rawWord,
    required String contextSentence,
    required String tokenId,
    required String fallbackDefinitionCn,
  }) {
    if (_activeLookupTokenId == tokenId) {
      _removeWordLookupOverlay();
      return;
    }
    _removeWordLookupOverlay();

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
    const double popupWidth = 336;
    const double preferredPopupHeight = 520;
    const double viewportPadding = 16;
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
      left = (anchorTopLeft.dx + (anchorSize.width / 2) - (popupWidth / 2))
          .clamp(
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

    _lookupOverlayEntry = OverlayEntry(
      builder: (BuildContext overlayContext) => Stack(
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _dismissWordLookup,
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
                contextSentence: contextSentence,
                fallbackDefinitionCn: fallbackDefinitionCn,
                showAbove: showAbove,
                showSide: showSide,
                showRight: showRight,
                maxHeight: popupHeight,
                onClose: _dismissWordLookup,
              ),
            ),
          ),
        ],
      ),
    );
    overlayState.insert(_lookupOverlayEntry!);
    _activeLookupTokenId = tokenId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F9F4),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _ReaderHeader(
              courseTitle: widget.snapshot.courseTitle,
              episodeTitle: widget.snapshot.episodeTitle,
              showTranslations: _showTranslations,
              onTranslationChanged: (bool value) {
                setState(() => _showTranslations = value);
              },
              isListeningFullTranscript: _isListeningFullTranscript,
              isFullTranscriptPaused: _isFullTranscriptPaused,
              onListenFullTranscript: _toggleFullTranscriptNarration,
              onLocateCurrentWord: _revealActiveWord,
              onClose: _closeReader,
            ),
            Expanded(
              child: SelectionArea(
                key: const ValueKey<String>('full-transcript-selection-area'),
                onSelectionChanged: (SelectedContent? selection) {
                  _hasTextSelection =
                      selection?.plainText.trim().isNotEmpty ?? false;
                },
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(32, 28, 32, 80),
                    itemCount: widget.snapshot.lines.length,
                    itemBuilder: (BuildContext context, int lineIndex) => Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: Column(
                          children: <Widget>[
                            _ReaderLine(
                              line: widget.snapshot.lines[lineIndex],
                              subtitleLetterCase:
                                  _progress.subtitleLetterCase ??
                                  widget.snapshot.subtitleLetterCase,
                              meanings: widget.snapshot.meanings,
                              lineIndex: lineIndex,
                              activeLineIndex: _progress.lineIndex,
                              activeWordIndex: _progress.wordIndex,
                              activeWordKey: _activeWordKey,
                              showTranslations: _showTranslations,
                              isLooping:
                                  _progress.loopingLineIndex == lineIndex,
                              onToggleLoop: widget.onToggleLineLoop == null
                                  ? null
                                  : () => widget.onToggleLineLoop!(lineIndex),
                              onWordTap:
                                  (
                                    BuildContext anchorContext,
                                    String token,
                                    int wordIndex,
                                  ) {
                                    _toggleWordLookup(
                                      anchorContext: anchorContext,
                                      rawWord: token,
                                      contextSentence: widget
                                          .snapshot
                                          .lines[lineIndex]
                                          .english,
                                      tokenId: '$lineIndex-$wordIndex',
                                      fallbackDefinitionCn:
                                          widget
                                              .snapshot
                                              .meanings[normalizeTranscriptReaderWord(
                                            token,
                                          )] ??
                                          '',
                                    );
                                  },
                            ),
                            const _SelectableLineBreak(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderHeader extends StatelessWidget {
  const _ReaderHeader({
    required this.courseTitle,
    required this.episodeTitle,
    required this.showTranslations,
    required this.onTranslationChanged,
    required this.isListeningFullTranscript,
    required this.isFullTranscriptPaused,
    required this.onListenFullTranscript,
    required this.onLocateCurrentWord,
    required this.onClose,
  });

  final String courseTitle;
  final String episodeTitle;
  final bool showTranslations;
  final ValueChanged<bool> onTranslationChanged;
  final bool isListeningFullTranscript;
  final bool isFullTranscriptPaused;
  final VoidCallback onListenFullTranscript;
  final VoidCallback onLocateCurrentWord;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 18, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppDesignTokens.borderGray)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.menu_book_rounded,
              color: AppDesignTokens.brandGreenDark,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  courseTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppDesignTokens.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$episodeTitle · 逐词全文',
                  style: const TextStyle(
                    color: AppDesignTokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                '翻译',
                style: TextStyle(
                  color: AppDesignTokens.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              Switch(
                key: const ValueKey<String>('reader-translation-toggle'),
                value: showTranslations,
                onChanged: onTranslationChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: const ValueKey<String>('reader-play-full-transcript'),
            onPressed: onListenFullTranscript,
            icon: Icon(
              isListeningFullTranscript
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
            ),
            label: Text(
              isListeningFullTranscript
                  ? '暂停'
                  : isFullTranscriptPaused
                  ? '继续'
                  : '听全文',
            ),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            key: const ValueKey<String>('reader-locate-current-word'),
            onPressed: onLocateCurrentWord,
            tooltip: '定位到当前单词',
            icon: const Icon(
              Icons.my_location_rounded,
              color: AppDesignTokens.brandGreenDark,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: onClose,
            tooltip: '关闭逐词全文',
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _ReaderLine extends StatelessWidget {
  const _ReaderLine({
    required this.subtitleLetterCase,
    required this.line,
    required this.meanings,
    required this.lineIndex,
    required this.activeLineIndex,
    required this.activeWordIndex,
    required this.activeWordKey,
    required this.showTranslations,
    required this.isLooping,
    required this.onToggleLoop,
    required this.onWordTap,
  });

  final PlayerSubtitleLine line;
  final String subtitleLetterCase;
  final Map<String, String> meanings;
  final int lineIndex;
  final int activeLineIndex;
  final int activeWordIndex;
  final GlobalKey activeWordKey;
  final bool showTranslations;
  final bool isLooping;
  final VoidCallback? onToggleLoop;
  final void Function(BuildContext context, String token, int wordIndex)
  onWordTap;

  @override
  Widget build(BuildContext context) {
    final List<String> tokens =
        formatSubtitleLetterCase(line.english, subtitleLetterCase)
            .split(RegExp(r'\s+'))
            .where((String token) => token.isNotEmpty)
            .toList(growable: false);
    final bool isActive = lineIndex == activeLineIndex;
    return AnimatedContainer(
      key: ValueKey<String>('reader-line-$lineIndex-$isActive'),
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFFE8F7ED)
            : lineIndex.isOdd
            ? const Color(0x99FFFFFF)
            : Colors.transparent,
        border: Border(
          left: BorderSide(
            color: isActive ? AppDesignTokens.brandGreen : Colors.transparent,
            width: 3,
          ),
          bottom: const BorderSide(color: Color(0xFFD7E4DA)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                line.startTime,
                style: const TextStyle(
                  color: AppDesignTokens.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              IconButton.filledTonal(
                key: ValueKey<String>('reader-line-loop-$lineIndex'),
                onPressed: onToggleLoop,
                tooltip: isLooping ? '关闭单句循环' : '循环播放这一句',
                style: IconButton.styleFrom(
                  backgroundColor: isLooping
                      ? const Color(0xFFDFF8C8)
                      : const Color(0xFFF4F6F4),
                  foregroundColor: isLooping
                      ? AppDesignTokens.brandGreenDark
                      : AppDesignTokens.textSecondary,
                ),
                icon: const Icon(Icons.repeat_one_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 12,
            children: <Widget>[
              for (int wordIndex = 0; wordIndex < tokens.length; wordIndex++)
                Builder(
                  builder: (BuildContext wordContext) => _WordMeaningTile(
                    key: isActive && wordIndex == activeWordIndex
                        ? activeWordKey
                        : ValueKey<String>('reader-word-$lineIndex-$wordIndex'),
                    token: tokens[wordIndex],
                    meaning:
                        meanings[normalizeTranscriptReaderWord(
                          tokens[wordIndex],
                        )] ??
                        '—',
                    active: isActive && wordIndex == activeWordIndex,
                    showMeaning: showTranslations,
                    onTap: () =>
                        onWordTap(wordContext, tokens[wordIndex], wordIndex),
                  ),
                ),
            ],
          ),
          if (showTranslations) ...<Widget>[
            const _SelectableLineBreak(),
            const SizedBox(height: 14),
            _SentenceTranslationText(
              english: line.english,
              initialTranslation: line.chinese,
            ),
          ],
        ],
      ),
    );
  }
}

class _SentenceTranslationText extends ConsumerStatefulWidget {
  const _SentenceTranslationText({
    required this.english,
    required this.initialTranslation,
  });

  final String english;
  final String initialTranslation;

  @override
  ConsumerState<_SentenceTranslationText> createState() =>
      _SentenceTranslationTextState();
}

class _SentenceTranslationTextState
    extends ConsumerState<_SentenceTranslationText> {
  late String _translation;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _translation = widget.initialTranslation.trim();
    if (_translation.isEmpty) {
      _loadTranslation();
    }
  }

  Future<void> _loadTranslation() async {
    setState(() => _loading = true);
    String? translation;
    try {
      translation = await ref
          .read(wordLookupServiceProvider)
          .translateSentence(
            sentence: widget.english,
            settings: ref.read(learningSettingsProvider),
          );
    } catch (_) {
      translation = null;
    }
    if (!mounted) return;
    setState(() {
      _translation = translation?.trim() ?? '';
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final String text = _translation.isNotEmpty
        ? _translation
        : _loading
        ? '整句翻译中…'
        : '暂无整句翻译';
    return Container(
      key: const ValueKey<String>('reader-sentence-translation'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: _translation.isNotEmpty
              ? const Color(0xFF704B12)
              : AppDesignTokens.textSecondary,
          fontSize: 14,
          height: 1.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _WordMeaningTile extends StatelessWidget {
  const _WordMeaningTile({
    required this.token,
    required this.meaning,
    required this.active,
    required this.showMeaning,
    required this.onTap,
    super.key,
  });

  final String token;
  final String meaning;
  final bool active;
  final bool showMeaning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          key: ValueKey<String>('reader-word-box-$token-$active'),
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minWidth: 52, maxWidth: 180),
          padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFDDF7EA) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: active ? AppDesignTokens.brandGreen : Colors.transparent,
              width: active ? 2 : 1,
            ),
            boxShadow: active
                ? const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x2410B981),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Wrap(
                alignment: WrapAlignment.center,
                children: <Widget>[
                  Text(
                    token,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: active
                          ? AppDesignTokens.brandGreenDark
                          : AppDesignTokens.textPrimary,
                      fontSize: 25,
                      height: 1.08,
                      fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                  const IgnorePointer(
                    child: Text(' ', style: TextStyle(fontSize: 1)),
                  ),
                ],
              ),
              if (showMeaning) ...<Widget>[
                const SizedBox(height: 5),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: <Widget>[
                    Text(
                      meaning,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF8A5A12),
                        fontSize: 11,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const IgnorePointer(child: Text(' ')),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
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

Map<String, dynamic> _lineToJson(PlayerSubtitleLine line) => <String, dynamic>{
  'startTime': line.startTime,
  'english': line.english,
  'chinese': line.chinese,
  'startMs': line.startMs,
  'endMs': line.endMs,
  'words': line.words
      .map(
        (PlayerSubtitleWord word) => <String, dynamic>{
          'text': word.text,
          'startMs': word.startMs,
          'endMs': word.endMs,
          'confidence': word.confidence,
        },
      )
      .toList(growable: false),
};

PlayerSubtitleLine _lineFromJson(Map<dynamic, dynamic> json) {
  return PlayerSubtitleLine(
    startTime: json['startTime'] as String? ?? '',
    english: json['english'] as String? ?? '',
    chinese: json['chinese'] as String? ?? '',
    startMs: json['startMs'] as int? ?? 0,
    endMs: json['endMs'] as int? ?? 0,
    words: (json['words'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (Map<dynamic, dynamic> word) => PlayerSubtitleWord(
            text: word['text'] as String? ?? '',
            startMs: word['startMs'] as int? ?? 0,
            endMs: word['endMs'] as int? ?? 0,
            confidence: (word['confidence'] as num?)?.toDouble(),
          ),
        )
        .toList(growable: false),
  );
}
