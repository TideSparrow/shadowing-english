import 'dart:math';

class PlayerSubtitleWord {
  const PlayerSubtitleWord({
    required this.text,
    required this.startMs,
    required this.endMs,
    this.confidence,
  });

  final String text;
  final int startMs;
  final int endMs;
  final double? confidence;
}

class PlayerSubtitleLine {
  const PlayerSubtitleLine({
    required this.startTime,
    required this.english,
    required this.chinese,
    required this.startMs,
    required this.endMs,
    this.words = const <PlayerSubtitleWord>[],
  });

  final String startTime;
  final String english;
  final String chinese;
  final int startMs;
  final int endMs;
  final List<PlayerSubtitleWord> words;
}

class PlayerMockState {
  PlayerMockState({String? initialStartTime})
    : _initialStartTime = initialStartTime,
      lines = const <PlayerSubtitleLine>[],
      activeLineIndex = 0,
      positionMs = 0 {
    _syncCurrentWordIndex(forceLineStart: true);
  }

  static const List<String> subtitleModes = <String>['双语', '单英', '单中', '隐藏'];

  static const List<PlayerSubtitleLine> fallbackLines = <PlayerSubtitleLine>[
    PlayerSubtitleLine(
      startTime: '01:42',
      english: 'The city was too chaotic for them.',
      chinese: '这座城市对他们来说太混乱了。',
      startMs: 102000,
      endMs: 106000,
    ),
    PlayerSubtitleLine(
      startTime: '02:14',
      english: 'They sought a quiet sanctuary away from the noise.',
      chinese: '他们寻找一个远离喧嚣的安静避难所。',
      startMs: 134000,
      endMs: 140000,
    ),
    PlayerSubtitleLine(
      startTime: '02:31',
      english: 'Somewhere they could finally rest.',
      chinese: '一个他们最终可以休息的地方。',
      startMs: 151000,
      endMs: 156000,
    ),
    PlayerSubtitleLine(
      startTime: '02:48',
      english: 'A place of pure focused serenity.',
      chinese: '一个纯粹专注和平静的地方。',
      startMs: 168000,
      endMs: 173000,
    ),
  ];

  static const int _tickStepMs = 120;

  final String? _initialStartTime;

  List<PlayerSubtitleLine> lines;
  Map<String, String> generatedWordDefinitions = const <String, String>{};
  int activeLineIndex;
  int currentWordIndex = 0;
  int _subtitleDelayMs = 0;
  int get subtitleDelayMs => _subtitleDelayMs;
  set subtitleDelayMs(int value) {
    _subtitleDelayMs = value;
    _validateLoopBounds();
  }

  int positionMs;
  String speed = '0.8×';
  bool isPlaying = false;
  bool _isLooping = false;
  int? _loopStartMs;
  int? _loopEndMs;
  int? _loopFirstLine;
  int? _loopLastLine;
  int _videoDurationMs = 0;
  int get videoDurationMs => _videoDurationMs;
  set videoDurationMs(int value) {
    _videoDurationMs = max(0, value);
    if (_loopStartMs != null) _loopStartMs = _boundTime(_loopStartMs!);
    if (_loopEndMs != null) _loopEndMs = _boundTime(_loopEndMs!);
    _validateLoopBounds();
  }

  void _validateLoopBounds() {
    final int? start = loopStartMs;
    final int? end = loopEndMs;
    if (start != null && end != null && end <= start) clearLoop();
  }

  bool isSelectingLoopRange = false;
  bool resourcesLoaded = false;
  bool usingAiSubtitles = false;

  bool get isLooping => _isLooping;
  set isLooping(bool value) {
    _isLooping = value;
    if (!value) {
      _loopStartMs = null;
      _loopEndMs = null;
      _loopFirstLine = null;
      _loopLastLine = null;
    }
  }

  int _boundTime(int value) =>
      videoDurationMs > 0 ? value.clamp(0, videoDurationMs) : max(0, value);

  int? get loopStartMs => _loopFirstLine != null
      ? _boundTime(videoStartMsForLine(_loopFirstLine!))
      : _loopStartMs;
  int? get loopEndMs => _loopLastLine != null
      ? _boundTime(videoEndMsForLine(_loopLastLine!))
      : _loopEndMs;

  // Coverage is derived from time, so manual AB edits and subtitle selection
  // always describe the same contiguous interval (including subtitle gaps).
  ({int first, int last})? get loopLineRange {
    final int? start = loopStartMs;
    final int? end = loopEndMs;
    if (start == null || end == null) return null;
    int? first;
    int? last;
    for (int i = 0; i < lines.length; i++) {
      if (videoEndMsForLine(i) > start && videoStartMsForLine(i) < end) {
        first ??= i;
        last = i;
      }
    }
    return first == null ? null : (first: first, last: last!);
  }

  void clearLoop() => isLooping = false;

  void startAbLoop() {
    if (!hasLines) return;
    final int start = videoStartMsForLine(activeLineIndex);
    final int end = videoDurationMs > 0
        ? min(start + 120000, videoDurationMs)
        : min(start + 120000, videoEndMsForLine(lines.length - 1));
    setLoopRange(start, end);
    isSelectingLoopRange = false;
  }

  /// User-driven handle edits preview the boundary without starting playback.
  int? previewLoopRange(int startMs, int endMs) {
    final bool movedStart = startMs != loopStartMs;
    if (!setLoopRange(startMs, endMs)) return null;
    isPlaying = false;
    // B is exclusive: preview the last instant inside the selected segment.
    final int target = movedStart ? loopStartMs! : loopEndMs! - 1;
    syncWithTimestamp(target);
    return target;
  }

  int? exitLoopAtStart() {
    final int? start = loopStartMs;
    clearLoop();
    isSelectingLoopRange = false;
    if (start != null) syncWithTimestamp(start);
    return start;
  }

  void setLoopStart(int milliseconds) {
    final int start = _boundTime(milliseconds);
    final int? end = loopEndMs;
    clearLoop();
    _loopStartMs = start;
    if (end != null && end > start) {
      _loopEndMs = end;
      _isLooping = true;
    }
  }

  bool setLoopEnd(int milliseconds) {
    final int? start = loopStartMs;
    if (start == null) return false;
    return setLoopRange(start, milliseconds);
  }

  bool setLoopRange(int startMs, int endMs) {
    final int start = _boundTime(startMs);
    final int end = _boundTime(endMs);
    if (end <= start) return false;
    clearLoop();
    _loopStartMs = start;
    _loopEndMs = end;
    _isLooping = true;
    return true;
  }

  bool setLoopLines(int first, int last) {
    if (first < 0 ||
        last < 0 ||
        first >= lines.length ||
        last >= lines.length) {
      return false;
    }
    final int start = min(first, last);
    final int end = max(first, last);
    if (!setLoopRange(videoStartMsForLine(start), videoEndMsForLine(end))) {
      return false;
    }
    _loopFirstLine = start;
    _loopLastLine = end;
    return true;
  }

  int constrainToLoop(int milliseconds) {
    final int? start = loopStartMs;
    final int? end = loopEndMs;
    if (!isLooping || start == null || end == null) return milliseconds;
    return milliseconds.clamp(start, max(start, end - 1));
  }

  void leaveLoopIfOutside(int milliseconds) {
    if (isLooping && constrainToLoop(milliseconds) != milliseconds) clearLoop();
  }

  bool isShadowing = false;
  String subtitleMode = '双语';

  double get playbackRate {
    switch (speed) {
      case '0.5×':
        return 0.5;
      case '1.0×':
      case '1×':
        return 1;
      case '1.25×':
        return 1.25;
      case '1.5×':
        return 1.5;
      case '2.0×':
        return 2;
      default:
        return 0.8;
    }
  }

  Duration get playbackTickDuration => const Duration(milliseconds: 200);

  bool get hasLines => lines.isNotEmpty;

  List<String> get availableSubtitleModes {
    final bool hasEnglish = lines.any(
      (PlayerSubtitleLine line) => line.english.trim().isNotEmpty,
    );
    final bool hasChinese = lines.any(
      (PlayerSubtitleLine line) => line.chinese.trim().isNotEmpty,
    );

    final List<String> modes = <String>[];
    if (hasEnglish && hasChinese) {
      modes.add('双语');
    }
    if (hasEnglish) {
      modes.add('单英');
    }
    if (hasChinese) {
      modes.add('单中');
    }
    modes.add('隐藏');
    return modes;
  }

  bool get canAutoAdvance => hasLines && isPlaying;

  PlayerSubtitleLine get activeLine => lines[activeLineIndex];

  PlayerSubtitleLine? get visibleLine {
    if (!hasLines) {
      return null;
    }
    final PlayerSubtitleLine line = activeLine;
    final int displayEndMs = _displayEndMsFor(activeLineIndex);
    final int subtitleMs = _subtitlePositionMs;
    return subtitleMs >= line.startMs && subtitleMs < displayEndMs
        ? line
        : null;
  }

  bool tick() {
    if (!canAutoAdvance) {
      return false;
    }

    final int lineIncrement = max(1, (playbackRate * _tickStepMs).round());
    positionMs += lineIncrement;
    if (restartLoopAtTimestamp(positionMs)) return true;
    if (isLooping && loopStartMs != null) {
      syncWithTimestamp(positionMs);
      return true;
    }

    if (!hasLines) {
      isPlaying = false;
      return false;
    }

    final PlayerSubtitleLine currentLine = lines[activeLineIndex];
    if (_subtitlePositionMs >= currentLine.endMs) {
      if (isLooping) {
        positionMs = videoStartMsForLine(activeLineIndex);
        _syncCurrentWordIndex(forceLineStart: true);
        return true;
      }

      final int nextIndex = activeLineIndex + 1;
      if (nextIndex >= lines.length) {
        positionMs = currentLine.endMs;
        isPlaying = false;
        return false;
      }

      activeLineIndex = nextIndex;
      positionMs = videoStartMsForLine(activeLineIndex);
      _syncCurrentWordIndex(forceLineStart: true);
      return true;
    }

    _syncCurrentWordIndex();
    return true;
  }

  void selectLine(int index) {
    if (index < 0 || index >= lines.length) {
      return;
    }
    leaveLoopIfOutside(videoStartMsForLine(index));
    activeLineIndex = index;
    positionMs = videoStartMsForLine(activeLineIndex);
    currentWordIndex = 0;
    isPlaying = false;
  }

  void selectSpeed(String nextSpeed) {
    speed = nextSpeed;
  }

  void toggleLoop() {
    if (isLooping) {
      clearLoop();
    } else if (hasLines) {
      setLoopLines(activeLineIndex, activeLineIndex);
    }
  }

  bool toggleLineLoopAt(int index) {
    if (index < 0 || index >= lines.length) {
      return isLooping;
    }
    if (isLooping && loopLineRange == (first: index, last: index)) {
      isLooping = false;
      return false;
    }
    selectLine(index);
    setLoopLines(index, index);
    isPlaying = true;
    return true;
  }

  void toggleShadowing() {
    isShadowing = !isShadowing;
  }

  void togglePlaying({bool allowWithoutLines = false}) {
    if (!hasLines && !allowWithoutLines) {
      isPlaying = false;
      return;
    }
    isPlaying = !isPlaying;
    if (isPlaying && hasLines) {
      _syncCurrentWordIndex();
    }
  }

  void previousLine() {
    if (activeLineIndex == 0) {
      return;
    }
    leaveLoopIfOutside(videoStartMsForLine(activeLineIndex - 1));
    activeLineIndex -= 1;
    positionMs = videoStartMsForLine(activeLineIndex);
    currentWordIndex = 0;
    isPlaying = false;
  }

  void nextLine() {
    if (activeLineIndex >= lines.length - 1) {
      return;
    }
    leaveLoopIfOutside(videoStartMsForLine(activeLineIndex + 1));
    activeLineIndex += 1;
    positionMs = videoStartMsForLine(activeLineIndex);
    currentWordIndex = 0;
    isPlaying = false;
  }

  bool loadLines(
    List<PlayerSubtitleLine> loadedLines, {
    String? initialStartTime,
    Map<String, String> wordDefinitions = const <String, String>{},
  }) {
    clearLoop();
    final List<PlayerSubtitleLine> validLines = loadedLines
        .where((PlayerSubtitleLine line) => line.endMs > line.startMs)
        .toList(growable: false);

    lines = validLines;
    generatedWordDefinitions = wordDefinitions;
    final int? initialPositionMs =
        _parseTimestampToMs(initialStartTime) ??
        _parseTimestampToMs(_initialStartTime);

    if (lines.isEmpty) {
      activeLineIndex = 0;
      positionMs = initialPositionMs ?? 0;
      currentWordIndex = 0;
      isPlaying = false;
      subtitleMode = '隐藏';
      return false;
    }

    final bool hasInitialStartTime =
        initialStartTime != null && initialStartTime.trim().isNotEmpty;
    final String? seekTime = hasInitialStartTime
        ? initialStartTime
        : _initialStartTime;
    activeLineIndex = _resolveInitialIndex(seekTime, lines);
    positionMs = initialPositionMs ?? 0;
    currentWordIndex = 0;
    _normalizeSubtitleMode();
    if (isPlaying) {
      _syncCurrentWordIndex();
    }
    return validLines.isNotEmpty;
  }

  bool seekToStartTime(String startTime) {
    final int? targetMs = _parseTimestampToMs(startTime);
    if (targetMs == null) {
      return false;
    }
    return seekToMilliseconds(targetMs);
  }

  bool seekToMilliseconds(int milliseconds) {
    leaveLoopIfOutside(milliseconds);
    if (!hasLines) {
      return false;
    }
    final int lineIndex = _resolveInitialIndexByMilliseconds(
      milliseconds,
      lines,
    );
    activeLineIndex = lineIndex;
    positionMs = milliseconds;
    currentWordIndex = 0;
    return true;
  }

  int resolveLineIndexForTimestamp(int milliseconds) {
    return _resolveInitialIndexByMilliseconds(milliseconds, lines);
  }

  bool syncWithTimestamp(int milliseconds) {
    if (!hasLines) {
      positionMs = milliseconds;
      currentWordIndex = 0;
      return false;
    }

    final int subtitleMs = max(0, milliseconds - subtitleDelayMs);
    final int nextIndex = resolveLineIndexForTimestamp(subtitleMs);
    final bool lineChanged = nextIndex != activeLineIndex;
    activeLineIndex = nextIndex;
    positionMs = milliseconds;
    if (!lineChanged) {
      _syncCurrentWordIndex();
      return false;
    }
    _syncCurrentWordIndex(forceLineStart: true);
    return true;
  }

  bool restartLoopAtTimestamp(int milliseconds) {
    if (!isLooping) return false;
    final int? start =
        loopStartMs ?? (hasLines ? videoStartMsForLine(activeLineIndex) : null);
    final int? end =
        loopEndMs ?? (hasLines ? videoEndMsForLine(activeLineIndex) : null);
    if (start == null || end == null || end <= start || milliseconds < end) {
      return false;
    }
    syncWithTimestamp(start);
    return true;
  }

  bool get isLineCompleted {
    if (!hasLines) {
      return false;
    }
    final PlayerSubtitleLine line = lines[activeLineIndex];
    return _subtitlePositionMs >= line.endMs;
  }

  bool isWithinActiveLine(int milliseconds) {
    if (!hasLines) {
      return false;
    }
    final PlayerSubtitleLine line = lines[activeLineIndex];
    final int subtitleMs = max(0, milliseconds - subtitleDelayMs);
    return subtitleMs >= line.startMs && subtitleMs <= line.endMs;
  }

  int videoStartMsForLine(int index) {
    return lines[index].startMs + subtitleDelayMs;
  }

  int videoEndMsForLine(int index) {
    return lines[index].endMs + subtitleDelayMs;
  }

  void cycleSubtitleMode() {
    final List<String> modes = availableSubtitleModes;
    final int currentIndex = modes.indexOf(subtitleMode);
    final int nextIndex = currentIndex < 0 || currentIndex == modes.length - 1
        ? 0
        : currentIndex + 1;
    subtitleMode = modes[nextIndex];
  }

  void setSubtitleMode(String value) {
    if (!hasLines && subtitleModes.contains(value)) {
      subtitleMode = value;
      return;
    }
    subtitleMode = availableSubtitleModes.contains(value)
        ? value
        : availableSubtitleModes.first;
  }

  void _normalizeSubtitleMode() {
    if (!availableSubtitleModes.contains(subtitleMode)) {
      subtitleMode = availableSubtitleModes.first;
    }
  }

  static int _resolveInitialIndex(
    String? initialStartTime,
    List<PlayerSubtitleLine> lines,
  ) {
    if (lines.isEmpty ||
        initialStartTime == null ||
        initialStartTime.trim().isEmpty) {
      return 0;
    }

    final String trimmedStartTime = initialStartTime.trim();
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startTime == trimmedStartTime) {
        return i;
      }
    }

    final int? targetMs = _parseTimestampToMs(initialStartTime);
    if (targetMs == null) {
      return 0;
    }
    return _resolveInitialIndexByMilliseconds(targetMs, lines);
  }

  static int _resolveInitialIndexByMilliseconds(
    int milliseconds,
    List<PlayerSubtitleLine> lines,
  ) {
    if (lines.isEmpty) {
      return 0;
    }

    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startMs == milliseconds) {
        return i;
      }
    }

    for (int i = lines.length - 1; i >= 0; i--) {
      if (lines[i].startMs <= milliseconds) {
        return i;
      }
    }
    return 0;
  }

  void _syncCurrentWordIndex({bool forceLineStart = false}) {
    if (!hasLines) {
      currentWordIndex = 0;
      return;
    }

    final PlayerSubtitleLine line = lines[activeLineIndex];
    final int subtitleMs = _subtitlePositionMs;
    if (line.words.isNotEmpty) {
      if (subtitleMs < line.words.first.startMs) {
        currentWordIndex = -1;
        return;
      }
      for (int index = 0; index < line.words.length; index++) {
        final PlayerSubtitleWord word = line.words[index];
        if (subtitleMs >= word.startMs && subtitleMs < word.endMs) {
          currentWordIndex = index;
          return;
        }
      }
      for (int index = line.words.length - 1; index >= 0; index--) {
        if (subtitleMs >= line.words[index].endMs) {
          currentWordIndex = index;
          return;
        }
      }
      return;
    }

    final List<String> words = line.english
        .trim()
        .split(' ')
        .where((String word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) {
      currentWordIndex = 0;
      return;
    }
    if (forceLineStart) {
      currentWordIndex = 0;
      return;
    }

    final int lineDuration = max(1, line.endMs - line.startMs);
    if (subtitleMs <= line.startMs) {
      currentWordIndex = 0;
      return;
    }
    if (subtitleMs >= line.endMs) {
      currentWordIndex = words.length - 1;
      return;
    }

    final int elapsedInLine = subtitleMs - line.startMs;
    final int wordMs = max(1, lineDuration ~/ words.length);
    final int index = min(words.length - 1, elapsedInLine ~/ wordMs);
    currentWordIndex = max(0, index);
  }

  int _displayEndMsFor(int index) {
    final PlayerSubtitleLine line = lines[index];
    if (line.words.isNotEmpty) {
      return line.endMs;
    }
    final int minimumEndMs =
        line.startMs + _minimumReadableDurationMs(line.english);
    int displayEndMs = max(line.endMs, minimumEndMs);
    if (index < lines.length - 1) {
      displayEndMs = min(displayEndMs, lines[index + 1].startMs);
    }
    return displayEndMs;
  }

  int get _subtitlePositionMs {
    return max(0, positionMs - subtitleDelayMs);
  }

  int _minimumReadableDurationMs(String text) {
    final int words = text
        .trim()
        .split(RegExp(r'\s+'))
        .where((String word) => word.isNotEmpty)
        .length;
    return (900 + words * 360).clamp(1400, 5200);
  }

  static int? _parseTimestampToMs(String? value) {
    if (value == null) {
      return null;
    }
    final RegExp matcher = RegExp(
      r'^(?:(\d+):)?(\d{1,2}):(\d{2})(?:[.,](\d{1,3}))?$',
    );
    final Match? match = matcher.firstMatch(value.trim());
    if (match == null) {
      return null;
    }

    final int hours = int.tryParse(match.group(1) ?? '0') ?? 0;
    final int minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
    final int seconds = int.tryParse(match.group(3) ?? '0') ?? 0;
    final String millisecondsText = match.group(4) ?? '';
    final int normalizedMilliseconds = millisecondsText.isEmpty
        ? 0
        : int.parse(millisecondsText.padRight(3, '0').substring(0, 3));

    return (((hours * 60 + minutes) * 60) + seconds) * 1000 +
        normalizedMilliseconds;
  }
}
