import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../router/app_router.dart';
import '../../guide/presentation/guide_screen.dart';
import '../../home/presentation/learning_dashboard_provider.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../phrases/presentation/phrase_book_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/data/word_lookup_service.dart';
import '../../shared/presentation/app_loading_overlay.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../words/data/offline_word_dictionary.dart';
import '../../words/presentation/word_book_provider.dart';
import 'asr_subtitle_cache.dart';
import 'asr_subtitle_job.dart';
import 'asr_subtitle_service.dart';
import 'embedded_subtitle_reference.dart';
import 'full_transcript_reader.dart';
import 'learning_resume_provider.dart';
import 'player_course_lookup.dart';
import 'player_fullscreen_video_screen.dart';
import 'player_media_source.dart';
import 'player_mock_state.dart';
import 'player_native_subtitles.dart';
import 'player_subtitle_loader.dart';
import 'player_system_media_controls.dart';
import 'player_video_init.dart';
import 'subtitle_reference_review.dart';
import 'transcript_reader_session.dart';
import 'widgets/ai_subtitle_generation_progress_dialog.dart';
import 'widgets/player_episode_strip.dart';
import 'widgets/player_subtitle_list.dart';
import 'widgets/player_top_bar.dart';
import 'widgets/player_transcript_panel.dart';
import 'widgets/player_video_panel.dart';

class PadLandscapePlayerScreen extends ConsumerStatefulWidget {
  const PadLandscapePlayerScreen({
    required this.episodeId,
    this.initialStartTime,
    this.autoPlay = false,
    this.autoOpenFullscreen = false,
    super.key,
  });

  final String episodeId;
  final String? initialStartTime;
  final bool autoPlay;
  final bool autoOpenFullscreen;

  @override
  ConsumerState<PadLandscapePlayerScreen> createState() =>
      PadLandscapePlayerScreenState();
}

class PadLandscapePlayerScreenState
    extends ConsumerState<PadLandscapePlayerScreen> {
  late final PlayerMockState state;
  final TranscriptReaderSession _transcriptReaderSession =
      TranscriptReaderSession();
  Player? _videoPlayer;
  VideoController? _videoController;
  StreamSubscription<Duration>? _videoPositionSubscription;
  StreamSubscription<Duration>? _videoDurationSubscription;
  StreamSubscription<bool>? _videoPlayingSubscription;
  StreamSubscription<bool>? _videoCompletedSubscription;
  StreamSubscription<int?>? _videoWidthSubscription;
  StreamSubscription<int?>? _videoHeightSubscription;
  bool _isMuted = false;
  double _volumeLevel = 1;
  bool _videoReady = false;
  bool _videoLoading = false;
  bool _isBootstrapping = true;
  bool _videoIsPlaying = false;
  Duration _videoDuration = Duration.zero;
  Duration _videoPosition = Duration.zero;
  String? _videoErrorText;
  String? _videoAsset;
  double _videoAspectRatio = 16 / 9;
  Duration _lastTrackedVideoPosition = Duration.zero;
  bool _didAutoOpenFullscreen = false;
  bool _isFullscreenOpen = false;
  bool _generatingAiSubtitles = false;
  AsrSubtitleCancellationToken? _aiSubtitleCancellationToken;
  double? _aiSubtitleProgressValue;
  String? _aiSubtitleProgressText;
  String? _aiSubtitlePreviewText;
  String? _aiSubtitleErrorText;
  bool _usingAiSubtitles = false;
  List<SubtitleTrack> _embeddedSubtitleTracks = const <SubtitleTrack>[];
  String? _selectedEmbeddedSubtitleId;
  List<PlayerSubtitleLine> _referenceSubtitleLines =
      const <PlayerSubtitleLine>[];

  @override
  void initState() {
    super.initState();
    state = PlayerMockState(initialStartTime: widget.initialStartTime);
    _syncSettingsToState(ref.read(learningSettingsProvider));
    ref.listenManual<String>(
      learningSettingsProvider.select(
        (LearningSettingsState settings) => settings.subtitleLetterCase,
      ),
      (String? previous, String next) => _syncTranscriptReader(),
    );
    PlayerSystemMediaControls.bind(
      onPlay: _handleSystemPlay,
      onPause: _handleSystemPause,
      onToggle: _handleTogglePlaying,
      onNext: _handleNextLine,
      onPrevious: _handlePreviousLine,
    );
    _loadEpisodeResources();
  }

  void _syncSettingsToState(LearningSettingsState settings) {
    state
      ..selectSpeed(settings.playbackSpeed)
      ..subtitleDelayMs = settings.subtitleDelayMs
      ..setSubtitleMode(settings.subtitleMode);
  }

  @override
  void dispose() {
    _aiSubtitleCancellationToken?.cancel();
    PlayerSystemMediaControls.unbind();
    _cancelVideoSubscriptions();
    unawaited(_videoPlayer?.dispose());
    _transcriptReaderSession.dispose();
    super.dispose();
  }

  Future<void> _loadEpisodeResources() async {
    final List<LibraryCourseData> courses = ref.read(libraryCatalogProvider);
    final PlayerCourseLookupResult resource = resolvePlayerCourseForEpisode(
      courses: courses,
      episodeId: widget.episodeId,
    );
    final String? initialStartTime =
        widget.initialStartTime ??
        ((resource.episode?.completed ?? false)
            ? null
            : resource.episode?.progressTimeStr);
    _videoAsset = resource.videoAsset;

    List<PlayerSubtitleLine> resolvedLines = const <PlayerSubtitleLine>[];
    if ((resource.englishSubtitleAsset ?? '').isNotEmpty) {
      try {
        final List<PlayerSubtitleLine> englishLines = await loadSubtitleLines(
          resource.englishSubtitleAsset!,
        );
        List<PlayerSubtitleLine> chineseLines = const <PlayerSubtitleLine>[];
        if ((resource.chineseSubtitleAsset ?? '').isNotEmpty) {
          chineseLines = await loadSubtitleLines(
            resource.chineseSubtitleAsset!,
          );
        }
        resolvedLines = mergeSubtitleLines(
          englishLines: englishLines,
          chineseLines: chineseLines,
        );
      } catch (_) {
        resolvedLines = const <PlayerSubtitleLine>[];
      }
    }
    if (!mounted) {
      return;
    }

    setState(() {
      state
        ..loadLines(resolvedLines, initialStartTime: initialStartTime)
        ..isPlaying = widget.autoPlay && (_videoAsset?.isNotEmpty ?? false);
      _usingAiSubtitles = false;
      _referenceSubtitleLines = resolvedLines;
    });
    if (resource.episode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
        ref.read(lastLearningEpisodeProvider.notifier).record(widget.episodeId);
      });
    }
    await _initVideo();
    if (!mounted) {
      return;
    }
    setState(() {
      _isBootstrapping = false;
    });
  }

  Future<void> _initVideo() async {
    await _disposeVideo();

    if (_videoAsset == null || _videoAsset!.isEmpty) {
      setState(() {
        _videoReady = false;
        _videoLoading = false;
        _videoErrorText = null;
        _videoDuration = Duration.zero;
        _videoPosition = Duration.zero;
      });
      _applyPlaybackMode();
      return;
    }

    setState(() {
      _videoReady = false;
      _videoLoading = true;
      _videoErrorText = null;
    });

    final Player player = Player();
    final VideoController controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration:
            defaultTargetPlatform != TargetPlatform.macOS,
      ),
    );
    final int initialPositionMs = state.positionMs;

    try {
      await waitForVideoInitialization(() async {
        await player.open(Media(createPlayerMediaUri(_videoAsset!)));
      });
      await waitForPlayerReady(player);
      final List<SubtitleTrack> embeddedTracks = embeddedSubtitleTracks(
        player.state.tracks.subtitle,
      );
      await player.setSubtitleTrack(SubtitleTrack.no());
      await player.setRate(state.playbackRate);
      await player.setVolume(_volumeLevel * 100);
      if (!mounted) {
        await player.dispose();
        return;
      }

      _videoDuration = player.state.duration;
      _videoPosition = player.state.position;
      _syncVideoAspectRatio(player.state.width, player.state.height);
      if (initialPositionMs > 0) {
        await player.seek(Duration(milliseconds: initialPositionMs));
      }
      await player.pause();
      _videoPosition = player.state.position;
      _attachVideoListeners(player);

      _videoPlayer = player;
      _videoController = controller;
      setState(() {
        _embeddedSubtitleTracks = embeddedTracks;
        _selectedEmbeddedSubtitleId = null;
        _videoReady = true;
        _videoLoading = false;
        _videoErrorText = null;
      });
      final bool hasEmbeddedEnglish = embeddedTracks.any(
        (SubtitleTrack track) =>
            track.language == 'eng' || track.language == 'en',
      );
      if (_referenceSubtitleLines.isEmpty && hasEmbeddedEnglish) {
        unawaited(_loadEmbeddedReferenceAndCachedAiSubtitles(embeddedTracks));
      } else if (!state.hasLines) {
        await _loadCachedAiSubtitles();
      }
      if (!mounted) return;
      _applyPlaybackMode();
    } catch (_) {
      _cancelVideoSubscriptions();
      await player.dispose();
      if (!mounted) {
        return;
      }
      setState(() {
        _videoPlayer = null;
        _videoController = null;
        _videoReady = false;
        _videoLoading = false;
        _videoErrorText = '视频加载失败';
      });
      _applyPlaybackMode();
    }
  }

  Future<void> _loadEmbeddedSubtitleReference(
    List<SubtitleTrack> tracks,
  ) async {
    final String? videoPath = _videoAsset;
    if (videoPath == null) return;
    final List<PlayerSubtitleLine> lines =
        await extractEmbeddedEnglishSubtitles(
          videoPath: videoPath,
          tracks: tracks,
        );
    if (!mounted || lines.isEmpty || _referenceSubtitleLines.isNotEmpty) return;
    setState(() => _referenceSubtitleLines = lines);
  }

  Future<void> _loadEmbeddedReferenceAndCachedAiSubtitles(
    List<SubtitleTrack> tracks,
  ) async {
    try {
      await _loadEmbeddedSubtitleReference(tracks);
      if (!mounted || state.hasLines || _generatingAiSubtitles) return;
      await _loadCachedAiSubtitles(
        validateReferenceSignature: _referenceSubtitleLines.isNotEmpty,
      );
    } catch (_) {
      // Reference subtitles are optional and must not block video playback.
    }
  }

  Future<void> _loadCachedAiSubtitles({
    bool validateReferenceSignature = true,
  }) async {
    final String? videoPath = _videoAsset;
    if (videoPath == null || !mounted) return;
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    final String? cached = await const AsrSubtitleCache().read(
      episodeId: widget.episodeId,
      videoPath: videoPath,
      settings: settings,
      referenceSignature: _referenceSubtitleLines.isEmpty
          ? null
          : subtitleReferenceSignature(_referenceSubtitleLines),
      validateReferenceSignature: validateReferenceSignature,
    );
    if (cached == null || !mounted) return;
    final List<PlayerSubtitleLine> lines = parseSubtitleLines(cached);
    if (lines.isEmpty) return;
    final int positionMs = state.positionMs;
    setState(() {
      state
        ..loadLines(lines, wordDefinitions: parseSubtitleGlossary(cached))
        ..seekToMilliseconds(positionMs)
        ..setSubtitleMode(settings.subtitleMode);
      _usingAiSubtitles = true;
    });
  }

  Future<void> _disposeVideo() async {
    _cancelVideoSubscriptions();
    if (_videoPlayer == null) {
      return;
    }

    final Player player = _videoPlayer!;
    _videoPlayer = null;
    _videoController = null;
    _videoIsPlaying = false;
    try {
      await player.dispose();
    } catch (_) {
      // Ignore cleanup failures, disposal is best effort.
    }
  }

  void _attachVideoListeners(Player player) {
    _videoPositionSubscription = player.stream.position.listen(
      _onVideoProgress,
    );
    _videoDurationSubscription = player.stream.duration.listen((
      Duration duration,
    ) {
      if (!mounted) {
        return;
      }
      setState(() {
        _videoDuration = duration;
      });
    });
    _videoPlayingSubscription = player.stream.playing.listen((bool playing) {
      _videoIsPlaying = playing;
    });
    _videoCompletedSubscription = player.stream.completed.listen((
      bool completed,
    ) {
      if (completed) {
        _stopVideo();
      }
    });
    _syncTranscriptReader();
    _videoWidthSubscription = player.stream.width.listen((int? width) {
      _syncVideoAspectRatio(width, player.state.height);
    });
    _videoHeightSubscription = player.stream.height.listen((int? height) {
      _syncVideoAspectRatio(player.state.width, height);
    });
  }

  void _cancelVideoSubscriptions() {
    unawaited(_videoPositionSubscription?.cancel());
    unawaited(_videoDurationSubscription?.cancel());
    unawaited(_videoPlayingSubscription?.cancel());
    unawaited(_videoCompletedSubscription?.cancel());
    unawaited(_videoWidthSubscription?.cancel());
    unawaited(_videoHeightSubscription?.cancel());
    _videoPositionSubscription = null;
    _videoDurationSubscription = null;
    _videoPlayingSubscription = null;
    _videoCompletedSubscription = null;
    _videoWidthSubscription = null;
    _videoHeightSubscription = null;
  }

  void _syncVideoAspectRatio(int? width, int? height) {
    if (!mounted ||
        width == null ||
        height == null ||
        width <= 0 ||
        height <= 0) {
      return;
    }
    final double nextAspectRatio = width / height;
    if ((_videoAspectRatio - nextAspectRatio).abs() < 0.001) {
      return;
    }
    setState(() {
      _videoAspectRatio = nextAspectRatio;
    });
  }

  void _onVideoProgress(Duration position) {
    if (!mounted) {
      return;
    }

    final bool wasPlaying = _videoIsPlaying;
    bool lineChanged = false;
    bool loopRestarted = false;

    setState(() {
      _videoPosition = position;
      loopRestarted = state.restartLoopAtTimestamp(position.inMilliseconds);
      if (loopRestarted) {
        _videoPosition = Duration(milliseconds: state.positionMs);
      } else {
        lineChanged = state.syncWithTimestamp(position.inMilliseconds);
      }
    });
    _syncTranscriptReader();

    if (wasPlaying) {
      _trackPlayProgress(position);
      unawaited(
        ref
            .read(libraryCatalogProvider.notifier)
            .updateEpisodeProgress(
              episodeId: widget.episodeId,
              position: position,
              duration: _videoDuration,
            ),
      );
    }

    if (loopRestarted) {
      _lastTrackedVideoPosition = Duration(milliseconds: state.positionMs);
      unawaited(_videoPlayer?.seek(_videoPosition));
      return;
    }

    if (lineChanged && wasPlaying) {
      _recordCurrentSentenceStudy();
      _recordCurrentLineWords();
    }

    if (!state.hasLines) {
      return;
    }
  }

  void _stopVideo() {
    if (!state.isPlaying) {
      return;
    }
    setState(() {
      state.isPlaying = false;
    });
    unawaited(_videoPlayer?.pause());
  }

  void _applyPlaybackMode() {
    PlayerSystemMediaControls.updatePlaybackState(isPlaying: state.isPlaying);
    if (!state.isPlaying) {
      unawaited(_videoPlayer?.pause());
      return;
    }

    if (_videoAsset == null || _videoErrorText != null) {
      setState(() {
        state.isPlaying = false;
      });
      unawaited(_videoPlayer?.pause());
      return;
    }

    if (_videoLoading || _videoPlayer == null || !_videoReady) {
      return;
    }

    if (state.hasLines) {
      unawaited(_videoPlayer!.seek(Duration(milliseconds: state.positionMs)));
    }
    unawaited(_videoPlayer!.setRate(state.playbackRate));
    unawaited(_videoPlayer!.play());
  }

  void _seekToActiveLine() {
    if (_videoPlayer == null || !state.hasLines) {
      return;
    }
    unawaited(
      _videoPlayer!.seek(
        Duration(
          milliseconds: state.videoStartMsForLine(state.activeLineIndex),
        ),
      ),
    );
  }

  void _goToLine(int index) {
    setState(() {
      state
        ..selectLine(index)
        ..isPlaying = true;
    });
    _syncTranscriptReader();
    _seekToActiveLine();
    _recordCurrentSentenceStudy();
    _lastTrackedVideoPosition = _currentVideoPosition();
    _applyPlaybackMode();
  }

  void _handleSeek(double progress) {
    final double safeProgress = progress.clamp(0.0, 1.0);

    setState(() {
      if (_videoDuration.inMilliseconds > 0) {
        final int targetMs = (_videoDuration.inMilliseconds * safeProgress)
            .round();
        if (state.hasLines) {
          state.seekToMilliseconds(targetMs);
        }
        _lastTrackedVideoPosition = Duration(milliseconds: targetMs);
        if (_videoPlayer != null) {
          unawaited(_videoPlayer!.seek(Duration(milliseconds: targetMs)));
        }
      } else {
        if (!state.hasLines) {
          return;
        }
        final int maxIndex = state.lines.length - 1;
        final int targetIndex = (safeProgress * maxIndex).round().clamp(
          0,
          maxIndex,
        );
        state.selectLine(targetIndex);
        _recordCurrentSentenceStudy();
      }
    });
    _syncTranscriptReader();
    _applyPlaybackMode();
  }

  void _handleSeekBySeconds(int deltaSeconds) {
    if (_videoDuration.inMilliseconds > 0) {
      final int targetMs =
          (_videoPosition.inMilliseconds + (deltaSeconds * 1000)).clamp(
            0,
            _videoDuration.inMilliseconds,
          );
      _handleSeek(targetMs / _videoDuration.inMilliseconds);
      return;
    }
    final int targetMs = (state.positionMs + (deltaSeconds * 1000)).clamp(
      state.lines.first.startMs,
      state.lines.last.endMs,
    );
    setState(() {
      state.seekToMilliseconds(targetMs);
    });
    _syncTranscriptReader();
    _seekToActiveLine();
    _lastTrackedVideoPosition = Duration(milliseconds: state.positionMs);
    _applyPlaybackMode();
  }

  void _syncTranscriptReader() {
    if (!state.hasLines) return;
    _transcriptReaderSession.updateProgress(
      subtitleLetterCase: ref.read(learningSettingsProvider).subtitleLetterCase,
      lineIndex: state.activeLineIndex,
      wordIndex: state.currentWordIndex,
      loopingLineIndex: state.isLooping ? state.activeLineIndex : null,
    );
  }

  @visibleForTesting
  void debugHandleVideoProgress(Duration position) =>
      _onVideoProgress(position);

  @visibleForTesting
  ValueListenable<TranscriptReaderProgress> get debugTranscriptReaderProgress =>
      _transcriptReaderSession.progress;

  Future<void> _handleOpenTranscriptReader({
    required String courseTitle,
    required String episodeTitle,
  }) async {
    final TranscriptReaderSnapshot snapshot =
        await buildTranscriptReaderSnapshot(
          subtitleLetterCase: ref
              .read(learningSettingsProvider)
              .subtitleLetterCase,
          courseTitle: courseTitle,
          episodeTitle: episodeTitle,
          lines: state.lines,
          activeLineIndex: state.activeLineIndex,
          currentWordIndex: state.currentWordIndex,
          loopingLineIndex: state.isLooping ? state.activeLineIndex : null,
          generatedMeanings: state.generatedWordDefinitions,
          dictionary: ref.read(offlineWordDictionaryProvider),
        );
    if (!mounted) return;
    final LearningSettingsState lookupSettings = ref.read(
      learningSettingsProvider,
    );
    final WordLookupService lookupService = ref.read(wordLookupServiceProvider);
    try {
      await _transcriptReaderSession.open(
        context: context,
        snapshot: snapshot,
        lookupWord:
            ({required String rawWord, required String contextSentence}) =>
                lookupService.lookupWord(
                  rawWord: rawWord,
                  contextSentence: contextSentence,
                  settings: lookupSettings,
                ),
        translateSentence: (String sentence) => lookupService.translateSentence(
          sentence: sentence,
          settings: lookupSettings,
        ),
        playFullTranscript: _handlePlayFullTranscript,
        toggleLineLoop: (int lineIndex) async {
          _handleLoopFromLine(lineIndex);
        },
      );
    } catch (_) {
      _showMessage('无法打开逐词全文，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<LibraryCourseData> courses = ref.watch(libraryCatalogProvider);
    final PlayerCourseLookupResult courseContext =
        resolvePlayerCourseForEpisode(
          courses: courses,
          episodeId: widget.episodeId,
        );
    final PlayerSubtitleLine activeLine = state.hasLines
        ? state.visibleLine ?? _emptySubtitleLine
        : _emptySubtitleLine;
    final LibraryCourseData? course = courseContext.course;
    final LibraryEpisodeItem? episode = courseContext.episode;
    final LearningSettingsState settings = ref.watch(learningSettingsProvider);
    final bool canGenerateAiSubtitles =
        (_videoAsset?.isNotEmpty ?? false) && !_usingAiSubtitles;
    final LearningDashboardStats dashboard = ref.watch(
      learningDashboardProvider,
    );
    if (widget.autoOpenFullscreen &&
        !_didAutoOpenFullscreen &&
        !_isBootstrapping) {
      _didAutoOpenFullscreen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _handleOpenFullscreen(course?.episodes ?? const <LibraryEpisodeItem>[]);
      });
    }
    final Uri libraryDetailUri = Uri(
      path: SGRoute.library.route,
      queryParameters: <String, String>{
        'view': 'detail',
        if (course != null) 'courseId': course.id,
        'episodeId': widget.episodeId,
      },
    );

    return PadScaffold(
      showContinueLearning: false,
      currentDestination: AppNavDestination.library,
      showNavigation: false,
      topBar: PlayerTopBar(
        courseTitle: course?.title ?? '课程名称',
        episodeTitle: episode == null ? '第 01 集' : '第 ${episode.numberStr} 集',
        episodeName: episode?.title,
        streakText: '${dashboard.streakDays} Day Streak',
        onTranscriptPressed: state.hasLines
            ? () => unawaited(
                _handleOpenTranscriptReader(
                  courseTitle: course?.title ?? '课程名称',
                  episodeTitle: episode == null
                      ? '第 01 集'
                      : '第 ${episode.numberStr} 集',
                ),
              )
            : null,
        onLearningGuidePressed: () =>
            unawaited(GuideScreen.showLearningGuideDialog(context)),
        onStatsPressed: () {
          final String progressMessage = dashboard.checkedIn
              ? '今日打卡已完成'
              : '今日仍在学习中，继续加油';
          _showMessage(
            '今日学习 ${dashboard.todayStudyMinutes} 分钟 | ${dashboard.todaySentenceCount} 句 '
            '| ${dashboard.todayShadowingCount} 次跟读 | ${dashboard.todaySavedPhrases} 收藏 - $progressMessage',
          );
        },
        onBack: () {
          if (context.canPop()) {
            context.pop();
            return;
          }
          context.go(libraryDetailUri.toString());
        },
      ),
      body: AppLoadingOverlay(
        isLoading: _isBootstrapping,
        message: '正在打开课程...',
        child: Column(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 18, 28, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: <Widget>[
                          Expanded(
                            child: PlayerVideoPanel(
                              line: activeLine,
                              isPlaying: state.isPlaying,
                              speed: state.speed,
                              subtitleMode: state.subtitleMode,
                              subtitleModes: state.availableSubtitleModes,
                              embeddedSubtitleTracks: _embeddedSubtitleTracks,
                              selectedEmbeddedSubtitleId:
                                  _selectedEmbeddedSubtitleId,
                              currentWordIndex: state.currentWordIndex,
                              highlightWords: settings.highlightWords,
                              subtitleLetterCase: settings.subtitleLetterCase,
                              subtitleWordHighlightStyle:
                                  settings.subtitleWordHighlightStyle,
                              subtitleWordHighlightBorderWidth:
                                  settings.subtitleWordHighlightBorderWidth,
                              isShadowing: state.isShadowing,
                              isLooping: state.isLooping,
                              isMuted: _isMuted,
                              volumeLevel: _volumeLevel,
                              onTogglePlaying: _handleTogglePlaying,
                              onPreviousLine: _handlePreviousLine,
                              onReplayLine: _handleReplayLine,
                              onNextLine: _handleNextLine,
                              onSeekBackward: () => _handleSeekBySeconds(-10),
                              onSeekForward: () => _handleSeekBySeconds(10),
                              activeIndex: state.activeLineIndex,
                              totalLines: state.lines.length,
                              onSelectLine: _goToLine,
                              onSeek: _handleSeek,
                              onSpeedSelected: _handleSpeedSelected,
                              onSelectSubtitleMode: _handleSetSubtitleMode,
                              onSelectSubtitleLetterCase: ref
                                  .read(learningSettingsProvider.notifier)
                                  .setSubtitleLetterCase,
                              onSelectEmbeddedSubtitle:
                                  _handleSelectEmbeddedSubtitle,
                              onToggleShadowing: _handleToggleShadowing,
                              onToggleLoop: _handleToggleLoop,
                              onToggleMuted: _handleToggleMuted,
                              onVolumeChanged: _handleVolumeChanged,
                              onSubtitleLookupOpen: _stopVideo,
                              onCollectWord: (String word) =>
                                  _handleCollectWord(word, courseContext),
                              onFavoriteWord: _handleFavoriteWord,
                              onPronounce: _stopVideo,
                              onToggleFullscreen: () => _handleOpenFullscreen(
                                course?.episodes ??
                                    const <LibraryEpisodeItem>[],
                              ),
                              videoSurface: _isFullscreenOpen
                                  ? null
                                  : _buildVideoSurface(),
                              videoAspectRatio: _videoAspectRatio,
                              videoReady: _videoReady,
                              videoLoading: _videoLoading,
                              videoDuration: _videoDuration,
                              videoPosition: _videoPosition,
                              videoErrorText: _videoErrorText,
                              showAiGenerateSubtitles: canGenerateAiSubtitles,
                              onGenerateAiSubtitles: _generatingAiSubtitles
                                  ? null
                                  : _handleGenerateAiSubtitles,
                            ),
                          ),
                          const SizedBox(height: 12),
                          PlayerEpisodeStrip(
                            episodes:
                                course?.episodes ??
                                const <LibraryEpisodeItem>[],
                            activeEpisodeId: widget.episodeId,
                            onOpenEpisode: _openEpisode,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 22),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x120F172A),
                              blurRadius: 20,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: <Widget>[
                            Expanded(
                              child: state.hasLines
                                  ? PlayerTranscriptPanel(
                                      lines: state.lines,
                                      activeIndex: state.activeLineIndex,
                                      subtitleMode: state.subtitleMode,
                                      currentWordIndex: state.currentWordIndex,
                                      fontScale: settings.fontScale,
                                      highlightWords: settings.highlightWords,
                                      subtitleLetterCase:
                                          settings.subtitleLetterCase,
                                      subtitleWordHighlightStyle:
                                          settings.subtitleWordHighlightStyle,
                                      subtitleWordHighlightBorderWidth: settings
                                          .subtitleWordHighlightBorderWidth,
                                      onTapLine: _goToLine,
                                      onCollectWord: (String word) =>
                                          _handleCollectWord(
                                            word,
                                            courseContext,
                                          ),
                                      onFavoriteWord: _handleFavoriteWord,
                                      onBookmarkLine: (int index) =>
                                          _handleBookmarkLine(
                                            index,
                                            courseContext,
                                          ),
                                      onLoopFromLine: _handleLoopFromLine,
                                      onDictationLine: _handleDictationLine,
                                      onAiExplain: _handleAiExplain,
                                      loopingLineIndex: state.isLooping
                                          ? state.activeLineIndex
                                          : null,
                                      isPlaying: state.isPlaying,
                                      onTogglePlaying: _handleTogglePlaying,
                                      onPronounce: _stopVideo,
                                      onRegenerateAiSubtitles:
                                          _usingAiSubtitles &&
                                              !_generatingAiSubtitles
                                          ? _handleRegenerateAiSubtitles
                                          : null,
                                      onDeleteAiSubtitles: _usingAiSubtitles
                                          ? _handleDeleteAiSubtitles
                                          : null,
                                      onRegenerateAiLine: _usingAiSubtitles
                                          ? _handleRegenerateAiLine
                                          : null,
                                    )
                                  : canGenerateAiSubtitles
                                  ? PlayerSubtitleList(
                                      lines: const <PlayerSubtitleLine>[],
                                      activeIndex: 0,
                                      subtitleMode: '隐藏',
                                      currentWordIndex: 0,
                                      fontScale: settings.fontScale,
                                      highlightWords: settings.highlightWords,
                                      subtitleLetterCase:
                                          settings.subtitleLetterCase,
                                      onTapLine: (_) {},
                                      onCollectWord: (_) {},
                                      onBookmarkLine: (_) {},
                                      onLoopFromLine: (_) {},
                                      onDictationLine: (_) {},
                                      onAiExplain: (_) {},
                                      onPronounce: _stopVideo,
                                      showAiGenerateSubtitles: true,
                                      generatingAiSubtitles:
                                          _generatingAiSubtitles,
                                      aiSubtitleProgressValue:
                                          _aiSubtitleProgressValue,
                                      aiSubtitleProgressText:
                                          _aiSubtitleProgressText,
                                      aiSubtitlePreviewText:
                                          _aiSubtitlePreviewText,
                                      aiSubtitleErrorText: _aiSubtitleErrorText,
                                      onGenerateAiSubtitles:
                                          _handleGenerateAiSubtitles,
                                    )
                                  : const Center(
                                      child: Text(
                                        '当前剧集没有可用字幕或视频',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF5F6368),
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openEpisode(LibraryEpisodeItem episode) {
    if (episode.id == widget.episodeId) {
      return;
    }
    context.goNamed(
      SGRoute.player.name,
      pathParameters: <String, String>{'episodeId': episode.id},
    );
  }

  void _handleSpeedSelected(String nextSpeed) {
    setState(() {
      state.selectSpeed(nextSpeed);
    });
    _applyPlaybackMode();
  }

  void _handleSetSubtitleMode(String mode) {
    setState(() {
      state.setSubtitleMode(mode);
      _selectedEmbeddedSubtitleId = null;
    });
    ref.read(learningSettingsProvider.notifier).setSubtitleMode(mode);
    unawaited(_videoPlayer?.setSubtitleTrack(SubtitleTrack.no()));
    _applyPlaybackMode();
  }

  void _handleSelectEmbeddedSubtitle(SubtitleTrack? track) {
    setState(() {
      _selectedEmbeddedSubtitleId = track?.id;
      if (track != null) {
        state.setSubtitleMode('隐藏');
      }
    });
    if (track != null) {
      ref.read(learningSettingsProvider.notifier).setSubtitleMode('隐藏');
    }
    unawaited(_videoPlayer?.setSubtitleTrack(track ?? SubtitleTrack.no()));
  }

  void _handleTogglePlaying() {
    setState(() {
      state.togglePlaying(
        allowWithoutLines:
            (_videoAsset?.isNotEmpty ?? false) && _videoErrorText == null,
      );
    });
    _applyPlaybackMode();
    if (state.isPlaying) {
      _lastTrackedVideoPosition = _currentVideoPosition();
      _recordCurrentSentenceStudy();
      _recordCurrentLineWords();
    }
  }

  void _handleSystemPlay() {
    if (!state.isPlaying) {
      _handleTogglePlaying();
    }
  }

  void _handleSystemPause() {
    if (state.isPlaying) {
      _handleTogglePlaying();
    }
  }

  void _handlePreviousLine() {
    setState(state.previousLine);
    _syncTranscriptReader();
    _seekToActiveLine();
    _recordCurrentSentenceStudy();
    _lastTrackedVideoPosition = _currentVideoPosition();
    _applyPlaybackMode();
  }

  void _handleReplayLine() {
    _goToLine(state.activeLineIndex);
    _showMessage('已重播当前句');
  }

  void _handleNextLine() {
    setState(state.nextLine);
    _syncTranscriptReader();
    _seekToActiveLine();
    _recordCurrentSentenceStudy();
    _lastTrackedVideoPosition = _currentVideoPosition();
    _applyPlaybackMode();
  }

  void _handleToggleShadowing() {
    setState(state.toggleShadowing);
    ref
        .read(learningActivityProvider.notifier)
        .recordShadowingToggle(enabled: state.isShadowing);
    _showMessage(state.isShadowing ? '已开启跟读模式' : '已关闭跟读模式');
  }

  void _handleToggleLoop() {
    setState(state.toggleLoop);
    _syncTranscriptReader();
    _showMessage(state.isLooping ? '已开启单句循环' : '已关闭单句循环');
    if (state.isLooping && state.hasLines) {
      _seekToActiveLine();
    }
  }

  void _handleToggleMuted() {
    final double nextVolume = _isMuted ? 1 : 0;
    _handleVolumeChanged(nextVolume);
    _showMessage(_isMuted ? '已静音' : '已恢复声音');
  }

  Future<void> _handleGenerateAiSubtitles({
    bool forceRegenerate = false,
  }) async {
    if (_generatingAiSubtitles) {
      return;
    }
    final String? videoPath = _videoAsset;
    if (videoPath == null || videoPath.isEmpty) {
      _showMessage('当前视频不可用');
      return;
    }
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    final bool showProgressDialog = state.hasLines;
    setState(() {
      _generatingAiSubtitles = true;
      _aiSubtitleProgressValue = null;
      _aiSubtitleProgressText = '正在准备音频...';
      _aiSubtitlePreviewText = null;
      _aiSubtitleErrorText = null;
    });
    final ValueNotifier<AsrSubtitleProgress> dialogProgress =
        ValueNotifier<AsrSubtitleProgress>(
          const AsrSubtitleProgress(completedChunks: 0, totalChunks: 0),
        );
    final Future<void>? progressDialogFuture = showProgressDialog
        ? showAiSubtitleGenerationProgressDialog(
            context: context,
            progress: dialogProgress,
          )
        : null;
    final AsrSubtitleCancellationToken cancellationToken =
        AsrSubtitleCancellationToken();
    _aiSubtitleCancellationToken = cancellationToken;
    try {
      if (!forceRegenerate && !_usingAiSubtitles) {
        final String? cached = await const AsrSubtitleCache().read(
          episodeId: widget.episodeId,
          videoPath: videoPath,
          settings: settings,
          referenceSignature: _referenceSubtitleLines.isEmpty
              ? null
              : subtitleReferenceSignature(_referenceSubtitleLines),
        );
        if (cached != null) {
          final List<PlayerSubtitleLine> lines = parseSubtitleLines(cached);
          if (lines.isNotEmpty && mounted) {
            setState(() {
              state.loadLines(
                lines,
                wordDefinitions: parseSubtitleGlossary(cached),
              );
              _usingAiSubtitles = true;
            });
            _showMessage('已切换到 AI 字幕');
            return;
          }
        }
      }
      const AsrSubtitleJobRunner runner = AsrSubtitleJobRunner();
      final String raw = await runner.run(
        episodeId: widget.episodeId,
        videoPath: videoPath,
        settings: settings,
        referenceSubtitleLines: _referenceSubtitleLines,
        forceRegenerate: forceRegenerate,
        cancellationToken: cancellationToken,
        onProgress: (AsrSubtitleProgress progress) {
          dialogProgress.value = progress;
          if (!mounted) {
            return;
          }
          setState(() {
            _aiSubtitleProgressValue = progress.value;
            _aiSubtitleProgressText = progress.label;
            _aiSubtitlePreviewText = progress.previewText;
          });
        },
      );
      final List<PlayerSubtitleLine> lines = parseSubtitleLines(raw);
      if (!mounted) {
        return;
      }
      setState(() {
        state.loadLines(lines, wordDefinitions: parseSubtitleGlossary(raw));
        _usingAiSubtitles = true;
      });
      final SubtitleReferenceReview review = reviewGeneratedSubtitles(
        generated: lines,
        reference: _referenceSubtitleLines,
      );
      final AsrSubtitleRepairSummary repairSummary = await runner
          .readRepairSummary(
            episodeId: widget.episodeId,
            videoPath: videoPath,
            settings: settings,
          );
      final String? warning = subtitleGenerationWarning(raw);
      if (warning != null) {
        _showMessage(repairSummary.appendTo('AI 字幕已生成；$warning'));
      } else if (subtitleReferenceSignature(
        _referenceSubtitleLines,
      ).isNotEmpty) {
        _showMessage(repairSummary.appendTo('AI 字幕已生成，已按原字幕校准'));
      } else if (review.comparedLines == 0) {
        _showMessage(repairSummary.appendTo('AI 字幕已生成'));
      } else if (review.differentLines == 0) {
        _showMessage(repairSummary.appendTo('AI 字幕已生成，已通过参考字幕校对'));
      } else {
        _showMessage(repairSummary.appendTo('AI 字幕已生成'));
      }
    } catch (error) {
      if (cancellationToken.isCancelled) return;
      if (mounted) {
        final String message = error.toString().replaceFirst(
          RegExp(r'^Bad state:\s*'),
          '',
        );
        setState(() {
          _aiSubtitleErrorText = message;
        });
        _showMessage('AI 字幕生成失败：$message');
      }
    } finally {
      if (identical(_aiSubtitleCancellationToken, cancellationToken)) {
        _aiSubtitleCancellationToken = null;
      }
      if (progressDialogFuture != null && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        await progressDialogFuture;
      }
      dialogProgress.dispose();
      if (mounted) {
        setState(() {
          _generatingAiSubtitles = false;
          _aiSubtitleProgressValue = null;
          _aiSubtitleProgressText = null;
          _aiSubtitlePreviewText = null;
        });
      }
    }
  }

  Future<void> _handleRegenerateAiSubtitles() async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('重新生成 AI 字幕？'),
            content: const Text('这会再次调用已配置的 AI 服务，可能产生费用。生成失败时会保留当前字幕。'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('重新生成'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    _showMessage('正在重新生成 AI 字幕，当前字幕会保留到生成成功。');
    await _handleGenerateAiSubtitles(forceRegenerate: true);
  }

  Future<void> _handleRegenerateAiLine(int index) async {
    if (_generatingAiSubtitles || index < 0 || index >= state.lines.length) {
      _showMessage('AI 字幕正在处理中，请稍后再试');
      return;
    }
    final String? videoPath = _videoAsset;
    if (videoPath == null || videoPath.isEmpty) {
      _showMessage('当前视频不可用');
      return;
    }
    _showMessage('正在重新生成当前句，失败时会保留原句。');
    try {
      const AsrSubtitleJobRunner runner = AsrSubtitleJobRunner();
      final LearningSettingsState settings = ref.read(learningSettingsProvider);
      final String referenceSignature = subtitleReferenceSignature(
        _referenceSubtitleLines,
      );
      final AsrRegeneratedLineResult result = await runner.regenerateLine(
        episodeId: widget.episodeId,
        videoPath: videoPath,
        settings: settings,
        currentLines: List<PlayerSubtitleLine>.of(state.lines),
        lineIndex: index,
        referenceSignature: referenceSignature.isEmpty
            ? null
            : referenceSignature,
      );
      if (!mounted || index >= state.lines.length) return;
      setState(() {
        state.lines[index] = result.line;
        state.generatedWordDefinitions = parseSubtitleGlossary(result.raw);
      });
      _syncTranscriptReader();
      _showMessage('当前句已重新生成并保存');
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  Future<void> _handleDeleteAiSubtitles() async {
    final String? videoPath = _videoAsset;
    if (videoPath == null || videoPath.isEmpty) {
      return;
    }
    if (!mounted) {
      return;
    }
    await _loadEpisodeResources();
    _showMessage('已切回原始字幕');
  }

  void _handleVolumeChanged(double nextVolume) {
    final double safeVolume = nextVolume.clamp(0.0, 1.0);
    setState(() {
      _volumeLevel = safeVolume;
      _isMuted = safeVolume <= 0.001;
    });
    if (_videoPlayer != null) {
      unawaited(_videoPlayer!.setVolume(safeVolume * 100));
    }
  }

  void _handleBookmarkLine(int index, PlayerCourseLookupResult courseContext) {
    final PlayerSubtitleLine line = state.lines[index];
    final LibraryCourseData? course = courseContext.course;
    final LibraryEpisodeItem? episode = courseContext.episode;
    final bool added = ref
        .read(phraseBookProvider.notifier)
        .addPhraseIfMissing(
          english: line.english,
          chinese: line.chinese,
          course: course?.title ?? '课程',
          episode: '第 ${episode?.numberStr ?? '01'} 集',
          time: line.startTime,
          courseId: course?.id,
          episodeId: episode?.id,
          endTime: _formatTimestamp(line.endMs),
        );
    if (added) {
      ref.read(learningActivityProvider.notifier).recordPhraseSaved();
    }
    _showMessage(added ? '成功收藏当前句型到短语库！' : '该例句已经在您的短语库中！');
  }

  void _handleCollectWord(String word, PlayerCourseLookupResult courseContext) {
    final PlayerSubtitleLine line = state.lines[state.activeLineIndex];
    final LibraryCourseData? course = courseContext.course;
    final LibraryEpisodeItem? episode = courseContext.episode;
    final bool added = ref
        .read(phraseBookProvider.notifier)
        .addPhraseIfMissing(
          english: line.english,
          chinese: '${line.chinese} (生词: $word)',
          course: course?.title ?? '课程',
          episode: '第 ${episode?.numberStr ?? '01'} 集',
          time: line.startTime,
          courseId: course?.id,
          episodeId: episode?.id,
          endTime: _formatTimestamp(line.endMs),
        );
    if (added) {
      ref.read(learningActivityProvider.notifier).recordPhraseSaved();
    }
    _showMessage(added ? '成功收藏单词 "$word" 到短语库！' : '该例句已经在您的短语库中！');
  }

  void _handleFavoriteWord(String word) {
    if (!state.hasLines) return;
    final PlayerSubtitleLine line = state.activeLine;
    final PlayerCourseLookupResult courseContext =
        resolvePlayerCourseForEpisode(
          courses: ref.read(libraryCatalogProvider),
          episodeId: widget.episodeId,
        );
    final LibraryEpisodeItem? episode = courseContext.episode;
    ref
        .read(wordBookProvider.notifier)
        .addFavoriteWord(
          rawWord: word,
          episodeId: widget.episodeId,
          course: courseContext.course?.title ?? '课程',
          episode: '第 ${episode?.numberStr ?? '01'} 集',
          time: line.startTime,
          lineKey: '${line.startMs}-${line.endMs}',
          sentence: line.english,
          chinese: line.chinese,
          generatedDefinition:
              state.generatedWordDefinitions[normalizeWord(word)],
        );
    _showMessage('已收藏单词 "$word"');
  }

  void _recordPlayDuration({required int durationMs}) {
    if (durationMs <= 0) {
      return;
    }
    ref
        .read(learningActivityProvider.notifier)
        .recordPlayDuration(duration: Duration(milliseconds: durationMs));
  }

  void _recordCurrentSentenceStudy() {
    if (!state.hasLines) {
      return;
    }
    final PlayerSubtitleLine line = state.activeLine;
    final String sentenceKey = _makeSentenceKey(line);
    ref
        .read(learningActivityProvider.notifier)
        .recordSentenceStudy(sentenceKey: sentenceKey);
  }

  void _recordCurrentLineWords() {
    if (!state.hasLines) return;
    final PlayerCourseLookupResult context = resolvePlayerCourseForEpisode(
      courses: ref.read(libraryCatalogProvider),
      episodeId: widget.episodeId,
    );
    final LibraryEpisodeItem? episode = context.episode;
    final PlayerSubtitleLine line = state.activeLine;
    ref
        .read(wordBookProvider.notifier)
        .recordLine(
          english: line.english,
          episodeId: widget.episodeId,
          course: context.course?.title ?? '课程',
          episode: '第 ${episode?.numberStr ?? '01'} 集',
          time: line.startTime,
          lineKey: '${line.startMs}-${line.endMs}',
          chinese: line.chinese,
          generatedDefinitions: state.generatedWordDefinitions,
        );
  }

  void _trackPlayProgress(Duration position) {
    final int diff =
        position.inMilliseconds - _lastTrackedVideoPosition.inMilliseconds;
    _lastTrackedVideoPosition = position;
    _recordPlayDuration(durationMs: diff);
  }

  Duration _currentVideoPosition() {
    if (state.hasLines) {
      return Duration(milliseconds: state.lines[state.activeLineIndex].startMs);
    }
    return _videoPosition;
  }

  String _makeSentenceKey(PlayerSubtitleLine line) {
    return '${widget.episodeId}-${line.startMs}-${line.endMs}-${line.english}';
  }

  Future<void> _handlePlayFullTranscript() async {
    if (!state.hasLines || _videoPlayer == null || !_videoReady) {
      throw StateError('Original video playback is unavailable');
    }
    setState(() {
      if (state.isLooping) state.toggleLoop();
      state
        ..selectLine(0)
        ..isPlaying = true;
    });
    _syncTranscriptReader();
    _seekToActiveLine();
    _lastTrackedVideoPosition = _currentVideoPosition();
    _applyPlaybackMode();
  }

  void _handleLoopFromLine(int index) {
    late bool enabled;
    setState(() {
      enabled = state.toggleLineLoopAt(index);
    });
    _syncTranscriptReader();
    if (enabled) {
      _seekToActiveLine();
    }
    _applyPlaybackMode();
    _showMessage(enabled ? '已开启单句循环' : '已关闭单句循环');
  }

  void _handleDictationLine(int index) {
    setState(() {
      state.selectLine(index);
    });
    _seekToActiveLine();
    _showMessage('已加入听写练习');
  }

  void _handleAiExplain(int index) {
    final PlayerSubtitleLine line = state.lines[index];
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('AI 解释'),
          content: Text(
            '这是对该句的临时说明：\n${line.english}\n\n后续可接入 AI 接口进行更完整的语法和表达解析。',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleOpenFullscreen(List<LibraryEpisodeItem> episodes) async {
    final Widget? fullscreenVideoSurface = _buildVideoSurface();
    final bool highlightWords = ref
        .read(learningSettingsProvider)
        .highlightWords;
    final String subtitleWordHighlightStyle = ref
        .read(learningSettingsProvider)
        .subtitleWordHighlightStyle;
    final double subtitleWordHighlightBorderWidth = ref
        .read(learningSettingsProvider)
        .subtitleWordHighlightBorderWidth;
    final PlayerCourseLookupResult courseContext =
        resolvePlayerCourseForEpisode(
          courses: ref.read(libraryCatalogProvider),
          episodeId: widget.episodeId,
        );
    String? nextEpisodeId;
    setState(() {
      _isFullscreenOpen = true;
    });
    try {
      nextEpisodeId = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (BuildContext context) => PlayerFullscreenVideoScreen(
            playerState: state,
            highlightWords: highlightWords,
            subtitleLetterCase: ref
                .read(learningSettingsProvider)
                .subtitleLetterCase,
            subtitleWordHighlightStyle: subtitleWordHighlightStyle,
            subtitleWordHighlightBorderWidth: subtitleWordHighlightBorderWidth,
            isMuted: _isMuted,
            volumeLevel: _volumeLevel,
            onTogglePlaying: _handleTogglePlaying,
            onPreviousLine: _handlePreviousLine,
            onReplayLine: _handleReplayLine,
            onNextLine: _handleNextLine,
            onSeekBackward: () => _handleSeekBySeconds(-10),
            onSeekForward: () => _handleSeekBySeconds(10),
            onSelectLine: _goToLine,
            onSeek: _handleSeek,
            onSpeedSelected: _handleSpeedSelected,
            onSelectSubtitleMode: _handleSetSubtitleMode,
            onSelectSubtitleLetterCase: ref
                .read(learningSettingsProvider.notifier)
                .setSubtitleLetterCase,
            embeddedSubtitleTracks: _embeddedSubtitleTracks,
            selectedEmbeddedSubtitleId: _selectedEmbeddedSubtitleId,
            onSelectEmbeddedSubtitle: _handleSelectEmbeddedSubtitle,
            onToggleShadowing: _handleToggleShadowing,
            onToggleLoop: _handleToggleLoop,
            onToggleMuted: _handleToggleMuted,
            onVolumeChanged: _handleVolumeChanged,
            onSubtitleLookupOpen: _stopVideo,
            onCollectWord: (String word) =>
                _handleCollectWord(word, courseContext),
            onFavoriteWord: _handleFavoriteWord,
            onBookmarkLine: (int index) =>
                _handleBookmarkLine(index, courseContext),
            onLoopFromLine: _handleLoopFromLine,
            onDictationLine: _handleDictationLine,
            onAiExplain: _handleAiExplain,
            onRegenerateAiLine: _usingAiSubtitles
                ? _handleRegenerateAiLine
                : null,
            fontScale: ref.read(learningSettingsProvider).fontScale,
            episodes: episodes,
            activeEpisodeId: widget.episodeId,
            onExit: () => Navigator.of(context).maybePop(),
            videoSurface: fullscreenVideoSurface,
            videoAspectRatio: _videoAspectRatio,
            videoReady: _videoReady,
            videoLoading: _videoLoading,
            videoDuration: _videoDuration,
            videoErrorText: _videoErrorText,
          ),
        ),
      );
    } finally {
      if (mounted &&
          (nextEpisodeId == null || nextEpisodeId == widget.episodeId)) {
        setState(() {
          _isFullscreenOpen = false;
        });
      }
    }
    if (!mounted ||
        nextEpisodeId == null ||
        nextEpisodeId == widget.episodeId) {
      return;
    }
    await _videoPlayer?.pause();
    if (!mounted) {
      return;
    }
    context.goNamed(
      SGRoute.player.name,
      pathParameters: <String, String>{'episodeId': nextEpisodeId},
      queryParameters: const <String, String>{'fullscreen': '1'},
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatTimestamp(int milliseconds) {
    final int totalSeconds = milliseconds ~/ 1000;
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Widget? _buildVideoSurface() {
    final VideoController? controller = _videoController;
    if (controller == null) {
      return null;
    }
    return Video(
      controller: controller,
      controls: null,
      pauseUponEnteringBackgroundMode: false,
      filterQuality: FilterQuality.medium,
    );
  }
}

const PlayerSubtitleLine _emptySubtitleLine = PlayerSubtitleLine(
  startTime: '00:00',
  english: '',
  chinese: '',
  startMs: 0,
  endMs: 0,
);
