import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../constants/feature_flags.dart';
import '../../../settings/data/pronunciation_credentials.dart';
import '../../data/pronunciation_audio_extractor.dart';
import '../../data/pronunciation_providers.dart';
import '../../data/tencent_pronunciation_service.dart';
import '../../domain/pronunciation_assessment.dart';

Future<void> showPronunciationAssessmentDialog(
  BuildContext context, {
  required PronunciationAssessmentTarget target,
}) {
  return showDialog<void>(
    context: context,
    useSafeArea: false,
    barrierColor: Colors.transparent,
    builder: (BuildContext context) =>
        PronunciationAssessmentDialog(target: target),
  );
}

class PronunciationAssessmentDialog extends ConsumerStatefulWidget {
  const PronunciationAssessmentDialog({required this.target, super.key});

  final PronunciationAssessmentTarget target;

  @override
  ConsumerState<PronunciationAssessmentDialog> createState() =>
      _PronunciationAssessmentDialogState();
}

class _PronunciationAssessmentDialogState
    extends ConsumerState<PronunciationAssessmentDialog>
    with WidgetsBindingObserver {
  static const int _maxRecordingBytes =
      Pcm16MonoAudio.expectedSampleRate * 2 * 60;

  late final PronunciationMicrophone _microphone;
  late final PronunciationPreviewPlayer _previewPlayer;
  final Uint8List _recordingBuffer = Uint8List(_maxRecordingBytes);
  int _recordingBytesWritten = 0;
  StreamSubscription<Uint8List>? _recordingSubscription;
  Timer? _recordingRefreshTimer;
  Timer? _recordingLimitTimer;
  Stopwatch? _recordingStopwatch;
  PronunciationAudioSegment? _reference;
  Pcm16MonoAudio? _recording;
  PronunciationAssessmentResult? _result;
  String? _recordingPath;
  String? _message;
  String? _referenceError;
  bool _loadingReference = true;
  bool _recordingActive = false;
  bool _finishingRecording = false;
  bool _assessing = false;
  bool _resourcesReleased = false;
  bool _releasing = false;
  bool _closing = false;
  Future<void> Function()? _cancelExtraction;
  Future<void> Function()? _cancelAssessment;
  Future<void>? _releaseFuture;
  int _assessmentAttempt = 0;
  StreamSubscription<Duration>? _previewSubscription;
  int _previewPositionMs = 0;
  String? _playingPath;
  List<double> _referenceWaveform = const <double>[];
  List<double> _recordingWaveform = const <double>[];

  static const Color _originalColor = Color(0xFF93E7FF);
  static const Color _ownColor = Color(0xFFFFB878);

  @override
  void initState() {
    super.initState();
    _microphone = ref.read(pronunciationMicrophoneFactoryProvider)();
    _previewPlayer = ref.read(pronunciationPreviewPlayerFactoryProvider)();
    _previewSubscription = _previewPlayer.position.listen((Duration position) {
      if (mounted && !_resourcesReleased && _playingPath != null) {
        setState(() => _previewPositionMs = position.inMilliseconds);
      }
    });
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadReferenceAudio());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_releaseResources(clearTemporaryFiles: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_releaseResources(clearTemporaryFiles: true));
    super.dispose();
  }

  Future<void> _loadReferenceAudio() async {
    final String? validationError = widget.target.validationError;
    if (validationError != null) {
      if (mounted) {
        setState(() {
          _loadingReference = false;
          _referenceError = validationError;
        });
      }
      return;
    }
    try {
      final PronunciationAudioSegment segment = await ref
          .read(pronunciationAudioExtractorProvider)
          .extract(
            source: widget.target.videoSource,
            startMs: widget.target.startMs,
            endMs: widget.target.endMs,
            videoDuration: widget.target.videoDuration,
            onCancelAvailable: _registerExtractionCancel,
          );
      _cancelExtraction = null;
      if (!mounted || _resourcesReleased) {
        await _deleteTemporaryPath(segment.path);
        return;
      }
      final Pcm16MonoAudio aligned = segment.audio.trimLeadingSilence();
      try {
        if (aligned.bytes.isEmpty) {
          throw const PronunciationAudioExtractionException('这段原声未检测到有效声音。');
        }
        if (!identical(aligned, segment.audio)) {
          await File(segment.path).writeAsBytes(aligned.toWav(), flush: true);
        }
      } catch (_) {
        await _deleteTemporaryPath(segment.path);
        rethrow;
      }
      if (!mounted || _resourcesReleased) {
        await _deleteTemporaryPath(segment.path);
        return;
      }
      setState(() {
        _referenceWaveform = aligned.waveform;
        _reference = PronunciationAudioSegment(
          path: segment.path,
          audio: aligned,
        );
        _loadingReference = false;
      });
    } on PronunciationAudioExtractionException catch (error) {
      if (!mounted || _resourcesReleased) return;
      setState(() {
        _loadingReference = false;
        _referenceError = error.message;
      });
    } catch (_) {
      if (!mounted || _resourcesReleased) return;
      setState(() {
        _loadingReference = false;
        _referenceError = '原声暂不可用。';
      });
    }
  }

  void _registerExtractionCancel(Future<void> Function() cancel) {
    if (_resourcesReleased) {
      unawaited(_runCleanup(cancel));
      return;
    }
    _cancelExtraction = cancel;
  }

  void _registerAssessmentCancel(Future<void> Function() cancel) {
    if (_resourcesReleased) {
      unawaited(_runCleanup(cancel));
      return;
    }
    _cancelAssessment = cancel;
  }

  Future<void> _startRecording() async {
    if (_resourcesReleased ||
        _recordingActive ||
        _finishingRecording ||
        _assessing) {
      return;
    }
    setState(() {
      _message = null;
      _result = null;
      _finishingRecording = true;
      _playingPath = null;
      _previewPositionMs = 0;
    });
    try {
      await _previewPlayer.stop();
      await _deleteRecordingFile();
      _recordingBuffer.fillRange(0, _recordingBytesWritten, 0);
      _recordingBytesWritten = 0;
      final bool allowed = await _microphone.requestPermission();
      if (!mounted || _resourcesReleased) return;
      if (!allowed) {
        setState(() {
          _message = '需要麦克风权限才能录制跟读。';
          _finishingRecording = false;
        });
        return;
      }
      final Stream<Uint8List> stream = await _microphone.start();
      if (!mounted || _resourcesReleased) {
        await _microphone.cancel();
        return;
      }
      _recordingBytesWritten = 0;
      _recording = null;
      _recordingStopwatch = Stopwatch()..start();
      setState(() {
        _recordingActive = true;
        _finishingRecording = false;
      });
      _recordingSubscription = stream.listen(
        (Uint8List chunk) {
          if (_recordingActive && !_resourcesReleased) {
            final int remaining = _maxRecordingBytes - _recordingBytesWritten;
            if (remaining > 0) {
              final int bytesToCopy = min(remaining, chunk.length);
              _recordingBuffer.setRange(
                _recordingBytesWritten,
                _recordingBytesWritten + bytesToCopy,
                chunk,
              );
              _recordingBytesWritten += bytesToCopy;
            }
            if (_recordingBytesWritten >= _maxRecordingBytes) {
              unawaited(_stopRecording(reachedLimit: true));
            }
          }
        },
        onError: (Object _) {
          if (mounted && !_resourcesReleased) {
            setState(() => _message = '录音中断，请重新录制。');
          }
          unawaited(_stopRecording(discard: true));
        },
      );
      _recordingRefreshTimer = Timer.periodic(
        const Duration(milliseconds: 220),
        (_) {
          if (mounted && _recordingActive) setState(() {});
        },
      );
      _recordingLimitTimer = Timer(
        const Duration(seconds: 60),
        () => unawaited(_stopRecording(reachedLimit: true)),
      );
    } catch (_) {
      if (!mounted || _resourcesReleased) return;
      setState(() {
        _recordingActive = false;
        _finishingRecording = false;
        _message = '无法启动录音，请检查麦克风权限。';
      });
    }
  }

  Future<void> _stopRecording({
    bool reachedLimit = false,
    bool discard = false,
  }) async {
    if (!_recordingActive || _finishingRecording) return;
    bool shouldDiscard = discard;
    setState(() {
      _finishingRecording = true;
    });
    _recordingLimitTimer?.cancel();
    _recordingRefreshTimer?.cancel();
    _recordingStopwatch?.stop();
    try {
      await _microphone.stop();
    } catch (_) {
      shouldDiscard = true;
    }
    await _recordingSubscription?.cancel();
    _recordingSubscription = null;
    if (shouldDiscard || _resourcesReleased) {
      _recordingBuffer.fillRange(0, _recordingBytesWritten, 0);
      _recordingBytesWritten = 0;
      if (mounted) {
        setState(() {
          _recordingActive = false;
          _finishingRecording = false;
          _recording = null;
        });
      }
      return;
    }
    final int audioLength = _recordingBytesWritten & ~1;
    final Uint8List audioBytes = _recordingBuffer.sublist(0, audioLength);
    final Pcm16MonoAudio audio = Pcm16MonoAudio(
      bytes: audioBytes,
      sampleRate: Pcm16MonoAudio.expectedSampleRate,
    ).trimLeadingSilence();
    _recordingBuffer.fillRange(0, _recordingBytesWritten, 0);
    _recordingBytesWritten = 0;
    if (!audio.hasSpeechEnergy) {
      if (mounted) {
        setState(() {
          _recordingActive = false;
          _finishingRecording = false;
          _recording = null;
          _message = '未检测到有效语音，请靠近麦克风后重录。';
        });
      }
      return;
    }
    String? path;
    try {
      final Directory directory = await getTemporaryDirectory();
      await directory.create(recursive: true);
      path =
          '${directory.path}/pronunciation-recording-${DateTime.now().microsecondsSinceEpoch}.wav';
      await File(path).writeAsBytes(audio.toWav(), flush: true);
      if (!mounted || _resourcesReleased) {
        await _deleteTemporaryPath(path);
        return;
      }
      setState(() {
        _recordingActive = false;
        _finishingRecording = false;
        _recording = audio;
        _recordingWaveform = audio.waveform;
        _recordingPath = path;
        _result = null;
        _message = reachedLimit ? '已达到 60 秒上限，录音已停止。' : null;
      });
    } catch (_) {
      if (path != null) await _deleteTemporaryPath(path);
      if (!mounted || _resourcesReleased) return;
      setState(() {
        _recordingActive = false;
        _finishingRecording = false;
        _message = '保存临时录音失败，请重试。';
      });
    }
  }

  Future<void> _playLocalFile(String? path) async {
    if (_resourcesReleased ||
        _recordingActive ||
        _finishingRecording ||
        path == null) {
      return;
    }
    try {
      setState(() {
        _playingPath = path;
        _previewPositionMs = 0;
      });
      await _previewPlayer.playLocalFile(path);
    } catch (_) {
      if (mounted && !_resourcesReleased) {
        setState(() => _message = '无法播放这段音频。');
      }
    }
  }

  Future<void> _score() async {
    if (!pronunciationScoringEnabled ||
        _assessing ||
        _result != null ||
        _recordingActive ||
        _finishingRecording ||
        _resourcesReleased ||
        _recording == null) {
      return;
    }
    final String? validationError = widget.target.validationError;
    if (validationError != null) {
      setState(() => _message = validationError);
      return;
    }
    final Pcm16MonoAudio audio = _recording!;
    final int attempt = ++_assessmentAttempt;
    setState(() {
      _assessing = true;
      _message = null;
      _result = null;
    });
    try {
      final PronunciationCredentials credentials;
      try {
        credentials = await ref.read(pronunciationCredentialsProvider.future);
      } catch (_) {
        throw const PronunciationAssessmentException(
          '读取评测密钥失败，请到「设置 - 跟读评测」检查配置。',
        );
      }
      if (!mounted || _resourcesReleased || attempt != _assessmentAttempt) {
        return;
      }
      if (!credentials.isComplete) {
        throw const PronunciationAssessmentException(
          '请先在「设置 - 跟读评测」中填写并保存腾讯云密钥。',
        );
      }
      final PronunciationAssessmentResult result = await ref
          .read(tencentPronunciationServiceProvider)
          .evaluate(
            credentials: credentials,
            target: widget.target,
            audio: audio,
            onCancelAvailable: _registerAssessmentCancel,
          );
      _cancelAssessment = null;
      if (!mounted || _resourcesReleased || attempt != _assessmentAttempt) {
        return;
      }
      setState(() {
        _result = result;
        _assessing = false;
      });
    } on PronunciationAssessmentException catch (error) {
      _cancelAssessment = null;
      if (!mounted || _resourcesReleased || attempt != _assessmentAttempt) {
        return;
      }
      setState(() {
        _assessing = false;
        _message = error.message;
      });
    } catch (_) {
      _cancelAssessment = null;
      if (!mounted || _resourcesReleased || attempt != _assessmentAttempt) {
        return;
      }
      setState(() {
        _assessing = false;
        _message = '评分失败，请稍后重试。';
      });
    }
  }

  Future<void> _deleteRecordingFile() async {
    final String? path = _recordingPath;
    _recordingPath = null;
    if (path == null) return;
    await _deleteTemporaryPath(path);
  }

  Future<void> _deleteTemporaryPath(String path) async {
    try {
      final File file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (_) {
      debugPrint('Pronunciation temporary audio cleanup failed.');
    }
  }

  Future<void> _runCleanup(Future<void> Function() cleanup) async {
    try {
      await cleanup();
    } catch (_) {
      debugPrint('Pronunciation session cleanup failed.');
    }
  }

  Future<void> _releaseResources({required bool clearTemporaryFiles}) {
    return _releaseFuture ??= _releaseResourcesNow(
      clearTemporaryFiles: clearTemporaryFiles,
    );
  }

  Future<void> _releaseResourcesNow({required bool clearTemporaryFiles}) async {
    if (_releasing) return;
    _releasing = true;
    _resourcesReleased = true;
    _assessmentAttempt++;
    await _previewSubscription?.cancel();
    _recordingLimitTimer?.cancel();
    _recordingRefreshTimer?.cancel();
    await _recordingSubscription?.cancel();
    _recordingSubscription = null;
    _recordingBuffer.fillRange(0, _recordingBytesWritten, 0);
    _recordingBytesWritten = 0;
    if (_recordingActive) {
      try {
        await _microphone.cancel();
      } catch (_) {}
    }
    _recordingActive = false;
    final Future<void> Function()? cancelAssessment = _cancelAssessment;
    _cancelAssessment = null;
    if (cancelAssessment != null) {
      try {
        await cancelAssessment();
      } catch (_) {}
    }
    final Future<void> Function()? cancelExtraction = _cancelExtraction;
    _cancelExtraction = null;
    if (cancelExtraction != null) {
      try {
        await cancelExtraction();
      } catch (_) {}
    }
    try {
      await _previewPlayer.stop();
      await _previewPlayer.dispose();
    } catch (_) {}
    try {
      await _microphone.dispose();
    } catch (_) {}
    if (clearTemporaryFiles) {
      final PronunciationAudioSegment? reference = _reference;
      _reference = null;
      if (reference != null) {
        await _deleteTemporaryPath(reference.path);
      }
      await _deleteRecordingFile();
    }
    if (mounted && !_closing) {
      setState(() {
        _recording = null;
        _result = null;
        _assessing = false;
        _recordingActive = false;
        _loadingReference = false;
        _message = '应用进入后台，录音与临时音频已清理。请关闭后重新打开此评测窗口。';
      });
    }
  }

  Pcm16MonoAudio? get _liveRecording {
    if (_recordingBytesWritten < 2) return null;
    final int audioLength = _recordingBytesWritten & ~1;
    return Pcm16MonoAudio(
      bytes: Uint8List.sublistView(_recordingBuffer, 0, audioLength),
      sampleRate: Pcm16MonoAudio.expectedSampleRate,
    ).trimLeadingSilence();
  }

  KeyEventResult _handleRecordingShortcut(FocusNode _, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.space ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    // Consume key-up and repeat too, so focused buttons cannot activate an
    // unrelated action and holding Space never toggles recording repeatedly.
    if (event is KeyDownEvent &&
        !_resourcesReleased &&
        !_closing &&
        !_assessing &&
        !_finishingRecording) {
      unawaited(_recordingActive ? _stopRecording() : _startRecording());
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 600;
    final ThemeData darkTheme = ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _originalColor,
        brightness: Brightness.dark,
      ),
      fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
      useMaterial3: true,
    );
    return PopScope<void>(
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) {
          _closing = true;
          unawaited(_releaseResources(clearTemporaryFiles: true));
        }
      },
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        onKeyEvent: _handleRecordingShortcut,
        child: Theme(
          data: darkTheme,
          child: Dialog.fullscreen(
            key: const ValueKey<String>('pronunciation-assessment-dialog'),
            backgroundColor: Colors.transparent,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                child: ColoredBox(
                  color: const Color(0xB30B1722),
                  child: SafeArea(
                    child: Column(
                      children: <Widget>[
                        _buildHeader(context),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              compact ? 20 : 48,
                              12,
                              compact ? 20 : 48,
                              32,
                            ),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1040,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    _buildTarget(compact),
                                    SizedBox(height: compact ? 24 : 36),
                                    _buildComparison(compact),
                                    const SizedBox(height: 24),
                                    _buildActions(),
                                    if (!compact) ...<Widget>[
                                      const SizedBox(height: 10),
                                      const Text(
                                        '空格键：开始 / 停止录音',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Color(0xFFD6E3EC),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                    if (_message != null) ...<Widget>[
                                      const SizedBox(height: 16),
                                      Text(
                                        _message!,
                                        key: const ValueKey<String>(
                                          'pronunciation-message',
                                        ),
                                        style: const TextStyle(
                                          color: Color(0xFFFFB5AC),
                                          height: 1.5,
                                        ),
                                      ),
                                    ],
                                    if (pronunciationScoringEnabled &&
                                        _result != null) ...<Widget>[
                                      const SizedBox(height: 28),
                                      _buildResult(_result!),
                                    ],
                                    const SizedBox(height: 20),
                                    const Text(
                                      pronunciationScoringEnabled
                                          ? '录音与波形在本地处理。点击「获取评分」才会发送本次录音及字幕至腾讯云，并按账号计费。密钥可在「设置 · 跟读评测」中配置。'
                                          : '录音与波形仅在本机处理。可反复录制、回放并与视频原声对照。',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Color(0xFFD6E3EC),
                                        fontSize: 12,
                                        height: 1.6,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 12, 12, 8),
    child: Row(
      children: <Widget>[
        const Icon(Icons.graphic_eq_rounded, color: _originalColor, size: 22),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            '跟读对照',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          key: const ValueKey<String>('pronunciation-dialog-close'),
          tooltip: '关闭',
          color: Colors.white,
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );

  Widget _buildTarget(bool compact) => Column(
    children: <Widget>[
      SelectableText(
        widget.target.text,
        key: const ValueKey<String>('pronunciation-frozen-text'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: compact ? 26 : 36,
          height: 1.35,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFF1F7FC),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        '视频时间段 ${_formatVideoPosition(widget.target.startMs)} – ${_formatVideoPosition(widget.target.endMs)}',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: Color(0xFFD6E3EC)),
      ),
    ],
  );

  Widget _buildComparison(bool compact) {
    final Pcm16MonoAudio? own = _recordingActive ? _liveRecording : _recording;
    final int referenceMs = _reference?.audio.durationMs ?? 0;
    final int ownMs = own?.durationMs ?? 0;
    final int timelineMs = max(1000, max(referenceMs, ownMs));
    final List<double> ownWaveform = _recordingActive
        ? (own?.waveform ?? const <double>[])
        : _recordingWaveform;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          alignment: WrapAlignment.center,
          spacing: compact ? 16 : 40,
          runSpacing: 8,
          children: <Widget>[
            _buildLegend(
              label: '视频原声',
              color: _originalColor,
              audio: _reference?.audio,
              playKey: 'pronunciation-reference-play',
              path: _reference?.path,
            ),
            _buildLegend(
              label: '我的录音',
              color: _ownColor,
              audio: own,
              playKey: 'pronunciation-recording-play',
              path: _recordingPath,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loadingReference) const LinearProgressIndicator(minHeight: 2),
        RepaintBoundary(
          child: SizedBox(
            key: const ValueKey<String>('pronunciation-overlaid-waveforms'),
            height: compact ? 180 : 240,
            child: CustomPaint(
              painter: _ComparisonWaveformPainter(
                reference: _referenceWaveform,
                own: ownWaveform,
                referenceMs: referenceMs,
                ownMs: ownMs,
                timelineMs: timelineMs,
                positionMs: _playingPath == null ? null : _previewPositionMs,
                playingOwn:
                    _playingPath != null && _playingPath == _recordingPath,
              ),
              child: ownMs == 0
                  ? Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          _recordingActive
                              ? '正在聆听，开口后显示波形…'
                              : '点击开始录音，将你的声音叠在原声上',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFD6E3EC),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            const Text(
              '0 秒 · 声音起点',
              style: TextStyle(color: Color(0xFFD6E3EC), fontSize: 11),
            ),
            Text(
              _formatDuration(timelineMs),
              style: const TextStyle(color: Color(0xFFD6E3EC), fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          '已自动对齐声音起点 · 保留真实语速与句中停顿',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFE4EDF3), fontSize: 12),
        ),
        const SizedBox(height: 6),
        const Text(
          pronunciationScoringEnabled
              ? '叠加波形对照节奏与停顿；发音评分依据字幕和标准读音。'
              : '叠加波形对照节奏与停顿，可分别回放原声和你的录音。',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFD6E3EC), fontSize: 12, height: 1.5),
        ),
        if (_referenceError != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            _referenceError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFFCF99), fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _buildLegend({
    required String label,
    required Color color,
    required Pcm16MonoAudio? audio,
    required String playKey,
    required String? path,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Container(width: 16, height: 3, color: color),
      const SizedBox(width: 8),
      Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(width: 8),
      if (audio != null && audio.bytes.isNotEmpty)
        Text(
          _formatDuration(audio.durationMs),
          style: const TextStyle(color: Color(0xFFD6E3EC), fontSize: 12),
        ),
      IconButton(
        key: ValueKey<String>(playKey),
        tooltip: '播放$label',
        color: color,
        onPressed:
            path == null ||
                _resourcesReleased ||
                _recordingActive ||
                _finishingRecording
            ? null
            : () => unawaited(_playLocalFile(path)),
        icon: const Icon(Icons.play_arrow_rounded),
      ),
    ],
  );

  Widget _buildActions() => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 16,
    runSpacing: 12,
    children: <Widget>[
      if (_recordingActive)
        FilledButton.icon(
          key: const ValueKey<String>('pronunciation-record-stop'),
          onPressed: _finishingRecording
              ? null
              : () => unawaited(_stopRecording()),
          icon: const Icon(Icons.stop_rounded),
          label: const Text('停止录音'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFC34145),
            foregroundColor: Colors.white,
            minimumSize: const Size(156, 52),
          ),
        )
      else
        FilledButton.icon(
          key: const ValueKey<String>('pronunciation-record-start'),
          onPressed: _resourcesReleased || _finishingRecording || _assessing
              ? null
              : () => unawaited(_startRecording()),
          icon: Icon(
            _recording == null ? Icons.mic_rounded : Icons.replay_rounded,
          ),
          label: Text(_recording == null ? '开始录音' : '重新录制'),
          style: FilledButton.styleFrom(
            backgroundColor: _ownColor,
            foregroundColor: const Color(0xFF30200F),
            minimumSize: const Size(156, 52),
          ),
        ),
      if (pronunciationScoringEnabled)
        FilledButton.icon(
          key: const ValueKey<String>('pronunciation-score-button'),
          onPressed:
              _recording == null ||
                  _result != null ||
                  _recordingActive ||
                  _finishingRecording ||
                  _assessing ||
                  _resourcesReleased
              ? null
              : () => unawaited(_score()),
          icon: _assessing
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.fact_check_outlined),
          label: Text(
            _result != null ? '已评分' : (_assessing ? '正在评分…' : '获取评分'),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: _originalColor,
            foregroundColor: const Color(0xFF092333),
            minimumSize: const Size(156, 52),
          ),
        ),
      if (_finishingRecording)
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
    ],
  );

  Widget _buildResult(PronunciationAssessmentResult result) => _CardSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SectionTitle('腾讯云发音评分'),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double width = (constraints.maxWidth - 8) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _MetricTile(
                  width: width,
                  title: '建议评分',
                  value: _formatMetric(result.suggestedScore, max: 100),
                ),
                _MetricTile(
                  width: width,
                  title: '准确度',
                  value: _formatMetric(result.accuracy, max: 100),
                ),
                _MetricTile(
                  width: width,
                  title: '流利度',
                  value: _formatMetric(result.fluency, max: 1),
                ),
                _MetricTile(
                  width: width,
                  title: '完整度',
                  value: _formatMetric(result.completion, max: 1),
                ),
              ],
            );
          },
        ),
        if (result.words.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          const Text(
            '逐词结果',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: result.words.map(_wordChip).toList(growable: false),
          ),
        ],
      ],
    ),
  );

  Widget _wordChip(PronunciationWordResult word) {
    final String label = switch (word.matchTag) {
      2 => word.referenceWord.isEmpty ? '漏读' : word.referenceWord,
      1 => word.word.isEmpty ? '新增' : word.word,
      3 => word.word.isEmpty ? '错读' : word.word,
      4 => word.word.isEmpty ? '未录入' : word.word,
      _ => word.word.isEmpty ? word.referenceWord : word.word,
    };
    final Color color = switch (word.matchTag) {
      1 => const Color(0xFFFFCE90),
      2 || 3 => const Color(0xFFFFB5AC),
      4 => const Color(0xFFD6E3EC),
      _ => const Color(0xFF8EDAB7),
    };
    final String detail = switch (word.matchTag) {
      1 => '新增单词',
      2 => '缺少单词',
      3 => '错读的词',
      4 => '未录入单词',
      _ => '匹配单词',
    };
    return Tooltip(
      message: detail,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Text(
          '${label.isEmpty ? '—' : label}${word.accuracy == null ? '' : ' ${word.accuracy!.round()}'}',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _CardSurface extends StatelessWidget {
  const _CardSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0x50304452),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(padding: const EdgeInsets.all(12), child: child),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFFF1F7FC),
      fontSize: 14,
      fontWeight: FontWeight.w800,
    ),
  );
}

class _ComparisonWaveformPainter extends CustomPainter {
  const _ComparisonWaveformPainter({
    required this.reference,
    required this.own,
    required this.referenceMs,
    required this.ownMs,
    required this.timelineMs,
    required this.positionMs,
    required this.playingOwn,
  });

  final List<double> reference;
  final List<double> own;
  final int referenceMs;
  final int ownMs;
  final int timelineMs;
  final int? positionMs;
  final bool playingOwn;

  @override
  void paint(Canvas canvas, Size size) {
    final double center = size.height / 2;
    canvas.drawLine(
      Offset(0, center),
      Offset(size.width, center),
      Paint()
        ..color = const Color(0x38D6E3EC)
        ..strokeWidth = 1,
    );
    void drawWave(
      List<double> samples,
      int durationMs,
      Color color, {
      required bool foreground,
    }) {
      if (samples.isEmpty || durationMs == 0) return;
      final double width = size.width * (durationMs / timelineMs).clamp(0, 1);
      // Every bar contains measured energy. Aggregate only when the viewport
      // is narrow; the shared horizontal scale always remains actual seconds.
      final int count = min(samples.length, max(1, (width / 4).floor()));
      final double stride = samples.length / count;
      final double peak = max(0.01, samples.reduce(max));
      final Paint bars = Paint()
        ..color = color.withValues(alpha: foreground ? 0.95 : 0.72)
        ..strokeWidth = min(foreground ? 1.6 : 3.0, width / count * 0.72)
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < count; i++) {
        final int start = (i * stride).floor();
        final int end = min(samples.length, ((i + 1) * stride).ceil());
        double amplitude = 0;
        for (int j = start; j < end; j++) {
          amplitude = max(amplitude, samples[j]);
        }
        final double height =
            (amplitude / peak).clamp(0, 1) * size.height * 0.35;
        if (height < 0.8) continue;
        final double x = width * (i + 0.5) / count;
        canvas.drawLine(
          Offset(x, center - height),
          Offset(x, center + height),
          bars,
        );
      }
    }

    drawWave(
      reference,
      referenceMs,
      const Color(0xFF93E7FF),
      foreground: false,
    );
    drawWave(own, ownMs, const Color(0xFFFFB878), foreground: true);
    if (positionMs != null) {
      final int activeMs = playingOwn ? ownMs : referenceMs;
      final double x = size.width * positionMs!.clamp(0, activeMs) / timelineMs;
      final Color color = playingOwn
          ? const Color(0xFFFFB878)
          : const Color(0xFF93E7FF);
      canvas
        ..drawLine(
          Offset(x, 8),
          Offset(x, size.height - 8),
          Paint()
            ..color = color
            ..strokeWidth = 1.5,
        )
        ..drawCircle(Offset(x, 8), 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _ComparisonWaveformPainter oldDelegate) =>
      reference != oldDelegate.reference ||
      own != oldDelegate.own ||
      referenceMs != oldDelegate.referenceMs ||
      ownMs != oldDelegate.ownMs ||
      timelineMs != oldDelegate.timelineMs ||
      positionMs != oldDelegate.positionMs ||
      playingOwn != oldDelegate.playingOwn;
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.width,
    required this.title,
    required this.value,
  });

  final double width;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x303B5262),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(fontSize: 11, color: Color(0xFFD6E3EC)),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ),
  );
}

String _formatMetric(double? value, {required double max}) {
  if (value == null) return '—';
  final double normalized = max == 1 ? value * 100 : value;
  return normalized.toStringAsFixed(1);
}

String _formatDuration(int milliseconds) {
  return '${(max(0, milliseconds) / 1000).toStringAsFixed(2)} 秒';
}

String _formatVideoPosition(int milliseconds) {
  final int bounded = milliseconds.clamp(0, 999999999);
  final int minutes = bounded ~/ 60000;
  final int seconds = bounded ~/ 1000 % 60;
  final int fraction = bounded % 1000;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${fraction.toString().padLeft(3, '0')}';
}
