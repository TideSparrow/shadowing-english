import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../constants/feature_flags.dart';
import '../../../settings/data/pronunciation_credentials.dart';
import '../../../settings/presentation/widgets/pronunciation_help.dart';
import '../../../settings/presentation/widgets/pronunciation_settings_card.dart';
import '../../../shared/data/word_pronunciation_service.dart';
import '../../data/doubao_pronunciation_service.dart';
import '../../data/pronunciation_audio_extractor.dart';
import '../../data/pronunciation_history_store.dart';
import '../../data/pronunciation_providers.dart';
import '../../domain/pronunciation_assessment.dart';
import '../../domain/pronunciation_feedback.dart';

final Provider<WordPronunciationService> pronunciationFeedbackSpeechProvider =
    Provider<WordPronunciationService>(
      (Ref ref) => WordPronunciationService(offlineOnly: true),
    );

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
  static const String _billingNoticeKey =
      'pronunciation.doubao.billingAccepted.v1';

  late final PronunciationMicrophone _microphone;
  late final PronunciationPreviewPlayer _previewPlayer;
  late final PronunciationHistoryStore _historyStore;
  List<PronunciationHistoryEntry> _history =
      const <PronunciationHistoryEntry>[];
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
  bool _showCloudSetup = false;
  String? _referenceError;
  bool _loadingReference = true;
  bool _recordingActive = false;
  bool _finishingRecording = false;
  bool _assessing = false;
  bool _sendingAssessment = false;
  bool _showingResult = false;
  bool _resourcesReleased = false;
  bool _releasing = false;
  bool _closing = false;
  bool _billingAccepted = false;
  bool _viewingAssessmentLink = false;
  Future<void> Function()? _cancelExtraction;
  Future<void> Function()? _cancelAssessment;
  Future<void> Function()? _stopFeedbackSpeech;
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
    _historyStore = ref.read(pronunciationHistoryStoreProvider);
    _previewSubscription = _previewPlayer.position.listen((Duration position) {
      if (mounted && !_resourcesReleased && _playingPath != null) {
        setState(() => _previewPositionMs = position.inMilliseconds);
      }
    });
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadReferenceAudio());
    if (pronunciationCoachingEnabled) unawaited(_loadHistory());
  }

  Future<void> _loadHistory() async {
    try {
      final List<PronunciationHistoryEntry> history = await _historyStore.load(
        widget.target,
      );
      if (!mounted || _resourcesReleased) return;
      setState(() {
        final Map<String, PronunciationHistoryEntry> entries =
            <String, PronunciationHistoryEntry>{
              for (final PronunciationHistoryEntry entry in _history)
                entry.directory.path: entry,
              for (final PronunciationHistoryEntry entry in history)
                entry.directory.path: entry,
            };
        _history = entries.values.toList()
          ..sort(
            (PronunciationHistoryEntry a, PronunciationHistoryEntry b) =>
                b.recordedAt.compareTo(a.recordedAt),
          );
      });
    } catch (_) {
      if (!mounted || _resourcesReleased) return;
      setState(() => _message ??= '无法读取本机指导记录。');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _viewingAssessmentLink = false;
    // Keep the finished recording while the user checks the billing documents.
    if (_viewingAssessmentLink && state != AppLifecycleState.detached) return;
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
        _showingResult ||
        _assessing) {
      return;
    }
    setState(() {
      _message = null;
      _showCloudSetup = false;
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
        setState(() {
          _message = '无法播放这段音频。';
          _showCloudSetup = false;
        });
      }
    }
  }

  Future<void> _requestGuidance() async {
    if (!pronunciationCoachingEnabled ||
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
    final Pcm16MonoAudio? reference = _reference?.audio;
    if (reference == null) {
      setState(
        () => _message = _loadingReference
            ? '正在读取原声，请稍后再试。'
            : '无法读取视频原声，暂时无法获取指导。',
      );
      return;
    }
    final Pcm16MonoAudio audio = _recording!;
    final int attempt = ++_assessmentAttempt;
    setState(() {
      _assessing = true;
      _message = null;
      _showCloudSetup = false;
      _result = null;
    });
    try {
      final PronunciationCredentials credentials;
      try {
        await ref.read(pronunciationCredentialsProvider.notifier).pendingSave;
        if (!mounted || _resourcesReleased || attempt != _assessmentAttempt) {
          return;
        }
        credentials = await ref.read(pronunciationCredentialsProvider.future);
      } catch (_) {
        throw const PronunciationAssessmentException(
          '读取 API Key 失败，请到「设置 · 跟读指导」检查配置。',
        );
      }
      if (!mounted || _resourcesReleased || attempt != _assessmentAttempt) {
        return;
      }
      if (!credentials.isComplete) {
        await _showMissingCredentials();
        return;
      }
      if (!await _confirmBilling() ||
          !mounted ||
          _resourcesReleased ||
          attempt != _assessmentAttempt) {
        return;
      }
      setState(() => _sendingAssessment = true);
      final PronunciationAssessmentResult result = await ref
          .read(doubaoPronunciationServiceProvider)
          .evaluate(
            credentials: credentials,
            target: widget.target,
            audio: audio,
            reference: reference,
            onCancelAvailable: _registerAssessmentCancel,
          );
      _cancelAssessment = null;
      if (!mounted || _resourcesReleased || attempt != _assessmentAttempt) {
        return;
      }
      setState(() => _result = result);
      try {
        final PronunciationHistoryEntry saved = await _historyStore.save(
          widget.target,
          result,
          audio,
        );
        if (mounted && !_resourcesReleased) {
          setState(
            () => _history = <PronunciationHistoryEntry>[
              saved,
              ..._history.where(
                (PronunciationHistoryEntry entry) =>
                    entry.directory.path != saved.directory.path,
              ),
            ],
          );
        }
      } catch (_) {
        if (mounted && !_resourcesReleased) {
          setState(() => _message = '指导已生成，本次记录未能保存到本机。');
        }
      }
    } on PronunciationAssessmentException catch (error) {
      _cancelAssessment = null;
      if (!mounted || _resourcesReleased || attempt != _assessmentAttempt) {
        return;
      }
      setState(() {
        _message = error.message;
        _showCloudSetup = error.showSetup;
      });
    } catch (_) {
      _cancelAssessment = null;
      if (!mounted || _resourcesReleased || attempt != _assessmentAttempt) {
        return;
      }
      setState(() {
        _message = '获取指导失败，请稍后重试。';
      });
    } finally {
      if (mounted && !_resourcesReleased && attempt == _assessmentAttempt) {
        setState(() {
          _assessing = false;
          _sendingAssessment = false;
        });
      }
    }
    if (mounted && !_resourcesReleased && _result != null) {
      await _showResult(readFeedback: true);
    }
  }

  String get _estimatedUsage {
    final double estimate = DoubaoPronunciationService.estimateCost(
      targetText: widget.target.text,
      recordingMs: _recording?.durationMs ?? 0,
      referenceMs: _reference?.audio.durationMs ?? 0,
    );
    return '预计 ¥${estimate.toStringAsFixed(4)} · 按实际音频和文字用量计费';
  }

  Future<void> _showMissingCredentials() async {
    final bool? openSettings = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('配置火山方舟 API Key'),
        content: const Text('请在设置里填写你自己的火山方舟 API Key。配置好后可以回来分析这段录音。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('去配置'),
          ),
        ],
      ),
    );
    if (openSettings != true || !mounted || _resourcesReleased) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => Scaffold(
          appBar: AppBar(title: const Text('设置 · 跟读指导')),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: PronunciationSettingsCard(
                    openLink: _openAssessmentLink,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmBilling() async {
    if (_billingAccepted) return true;
    SharedPreferences? preferences;
    try {
      preferences = await SharedPreferences.getInstance();
      if (preferences.getBool(_billingNoticeKey) ?? false) return true;
    } catch (_) {
      // The notice still works if the preference store is unavailable.
    }
    if (!mounted || _resourcesReleased) return false;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('首次使用豆包发音指导'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(_estimatedUsage),
            const SizedBox(height: 10),
            const Text(
              '继续会把本句字幕、视频原声和你的录音发给火山方舟。费用记在你自己的账号，按实际用量扣费。设备会朗读豆包给出的指导。',
            ),
            _buildHelpLinks(context),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('同意并获取指导'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _resourcesReleased) return false;
    _billingAccepted = true;
    try {
      await preferences?.setBool(_billingNoticeKey, true);
    } catch (_) {
      // Confirmation remains valid for the current recording dialog.
    }
    return true;
  }

  Future<bool> _openAssessmentLink(BuildContext context, String url) async {
    _viewingAssessmentLink = !_recordingActive && !_finishingRecording;
    final bool opened = await openPronunciationLink(context, url);
    if (!opened) _viewingAssessmentLink = false;
    return opened;
  }

  Widget _buildHelpLinks(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    children: <Widget>[
      TextButton(
        onPressed: () =>
            showPronunciationHelp(context, openLink: _openAssessmentLink),
        child: const Text('跟读指导帮助'),
      ),
      TextButton(
        onPressed: () =>
            _openAssessmentLink(context, doubaoPronunciationBillingUrl),
        child: const Text('火山方舟计费说明'),
      ),
    ],
  );

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
    final Future<void> Function()? stopSpeech = _stopFeedbackSpeech;
    if (stopSpeech != null) await _runCleanup(stopSpeech);
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
        _sendingAssessment = false;
        _recordingActive = false;
        _loadingReference = false;
        _message = '应用进入后台，录音与临时音频已清理。请关闭后重新打开跟读对照。';
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
        !_showingResult &&
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
                                    if (pronunciationCoachingEnabled) ...<
                                      Widget
                                    >[
                                      const SizedBox(height: 8),
                                      if (_result == null && _recording != null)
                                        Text(
                                          _estimatedUsage,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Color(0xFFD6E3EC),
                                            fontSize: 12,
                                          ),
                                        ),
                                      if (!_recordingActive && !_assessing)
                                        _buildHelpLinks(context),
                                    ],
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
                                      if (!_resourcesReleased &&
                                          !_recordingActive &&
                                          _showCloudSetup)
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton.icon(
                                            onPressed: () =>
                                                _openAssessmentLink(
                                                  context,
                                                  doubaoPronunciationConsoleUrl,
                                                ),
                                            icon: const Icon(
                                              Icons.open_in_new_rounded,
                                            ),
                                            label: const Text('打开火山方舟'),
                                          ),
                                        ),
                                    ],
                                    const SizedBox(height: 20),
                                    const Text(
                                      pronunciationCoachingEnabled
                                          ? '录音和回听在本机进行。获取指导时会把本句原声、你的录音和字幕发给火山方舟。'
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
          pronunciationCoachingEnabled
              ? '叠加波形对照节奏与停顿。'
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
          onPressed:
              _resourcesReleased ||
                  _finishingRecording ||
                  _assessing ||
                  _showingResult
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
      if (pronunciationCoachingEnabled)
        FilledButton.icon(
          key: const ValueKey<String>('pronunciation-guidance-button'),
          onPressed:
              _recording == null ||
                  _recordingActive ||
                  _finishingRecording ||
                  _assessing ||
                  _showingResult ||
                  _resourcesReleased
              ? null
              : () => unawaited(
                  _result == null ? _requestGuidance() : _showResult(),
                ),
          icon: _sendingAssessment
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.record_voice_over_outlined),
          label: Text(
            _result != null ? '查看指导' : (_sendingAssessment ? '正在听录音…' : '获取指导'),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: _originalColor,
            foregroundColor: const Color(0xFF092333),
            minimumSize: const Size(156, 52),
          ),
        ),
      if (_history.isNotEmpty)
        OutlinedButton.icon(
          onPressed:
              _recordingActive ||
                  _finishingRecording ||
                  _assessing ||
                  _showingResult ||
                  _resourcesReleased
              ? null
              : () => unawaited(_showHistory()),
          icon: const Icon(Icons.history_rounded),
          label: const Text('练习记录'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(156, 52)),
        ),
      if (_finishingRecording)
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
    ],
  );

  Future<void> _showHistory() async {
    final PronunciationHistoryEntry?
    entry = await showDialog<PronunciationHistoryEntry>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('本句练习记录'),
        scrollable: true,
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final (int index, PronunciationHistoryEntry entry)
                  in _history.indexed)
                ListTile(
                  title: Text(
                    index == 0
                        ? '第 ${_history.length} 次 · 最近一次'
                        : '第 ${_history.length - index} 次',
                  ),
                  subtitle: Text(
                    '${MaterialLocalizations.of(context).formatCompactDate(entry.recordedAt)} '
                    '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(entry.recordedAt))}',
                  ),
                  trailing: entry.result.guidance == null
                      ? Text(
                          '评分 ${_formatMetric(entry.result.suggestedScore, max: 100)}',
                        )
                      : null,
                  onTap: () => Navigator.of(context).pop(entry),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    if (mounted && !_resourcesReleased && entry != null) {
      await _showResult(historyEntry: entry);
    }
  }

  Future<void> _showResult({
    bool readFeedback = false,
    PronunciationHistoryEntry? historyEntry,
  }) async {
    final PronunciationAssessmentResult? result =
        historyEntry?.result ?? _result;
    if (_showingResult || result == null) return;
    final int historyIndex = _history.indexWhere(
      (PronunciationHistoryEntry entry) => historyEntry == null
          ? identical(entry.result, result)
          : entry.directory.path == historyEntry.directory.path,
    );
    final int previousIndex = historyIndex + 1;
    final double? previousScore =
        result.guidance == null && previousIndex < _history.length
        ? _history[previousIndex].result.suggestedScore
        : null;
    setState(() => _showingResult = true);
    final ({String text, String speech}) feedback = pronunciationFeedback(
      result,
    );
    final WordPronunciationService speech = ref.read(
      pronunciationFeedbackSpeechProvider,
    );
    Directory? excerpts;
    Future<void>? playback;
    bool closed = false;
    bool speaking = false;
    int speechAttempt = 0;
    Future<void>? stoppingSpeech;
    Future<void> stopSpeech() async {
      speechAttempt++;
      if (!speaking) {
        await stoppingSpeech;
        return;
      }
      speaking = false;
      final Future<void> stop = _runCleanup(speech.stop);
      stoppingSpeech = stop;
      await stop;
      stoppingSpeech = null;
    }

    _stopFeedbackSpeech = stopSpeech;
    try {
      final String? recordingPath =
          historyEntry?.recordingFile.path ?? _recordingPath;
      Pcm16MonoAudio? recording = _recording;
      if (historyEntry != null) {
        try {
          recording = Pcm16MonoAudio.parseWav(
            await historyEntry.recordingFile.readAsBytes(),
          );
        } on FileSystemException {
          recording = null;
        } on FormatException {
          recording = null;
        }
      }
      await _stopResultPlayback();
      if (!mounted || _resourcesReleased) return;
      final ThemeData theme = Theme.of(context);
      String? playbackError;
      String? speechError;
      bool autoReadPending = readFeedback;
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) => Theme(
          data: ThemeData.dark(useMaterial3: true).copyWith(
            textTheme: ThemeData.dark().textTheme.apply(
              fontFamily: theme.textTheme.bodyMedium?.fontFamily,
            ),
          ),
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter update) {
              Future<void> readHint() async {
                if (!context.mounted ||
                    closed ||
                    _resourcesReleased ||
                    speaking ||
                    playback != null) {
                  return;
                }
                final int attempt = ++speechAttempt;
                update(() {
                  speaking = true;
                  speechError = null;
                });
                try {
                  await stoppingSpeech;
                  await _previewPlayer.stop();
                  if (attempt != speechAttempt ||
                      closed ||
                      _resourcesReleased) {
                    return;
                  }
                  await speech.speak(
                    feedback.speech,
                    language: 'zh-CN',
                    speechTimeout: const Duration(seconds: 35),
                  );
                } catch (_) {
                  if (context.mounted && attempt == speechAttempt) {
                    update(() => speechError = '无法使用设备的中文朗读，可直接查看文字提示。');
                  }
                } finally {
                  if (context.mounted && attempt == speechAttempt) {
                    update(() => speaking = false);
                  }
                }
              }

              if (autoReadPending) {
                autoReadPending = false;
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => unawaited(readHint()),
                );
              }

              void play(String? path, {Pcm16MonoAudio? excerpt}) {
                if (playback != null || closed || _resourcesReleased) return;
                update(() => playbackError = null);
                playback = () async {
                  try {
                    await stopSpeech();
                    if (context.mounted && !closed) update(() {});
                    String? source = path;
                    if (excerpt != null) {
                      excerpts ??= await (await getTemporaryDirectory())
                          .createTemp('pronunciation-excerpts-');
                      final File file = File('${excerpts!.path}/excerpt.wav');
                      await _previewPlayer.stop();
                      await file.writeAsBytes(excerpt.toWav());
                      source = file.path;
                    }
                    if (!closed && !_resourcesReleased && source != null) {
                      await _previewPlayer.playLocalFile(source);
                    }
                  } catch (_) {
                    if (context.mounted && !closed) {
                      update(() => playbackError = '无法播放这段音频。');
                    }
                  }
                }().whenComplete(() => playback = null);
              }

              VoidCallback? replay(
                PronunciationAudioRange? range,
                int paddingMs,
              ) {
                final Pcm16MonoAudio? audio = recording;
                if (range == null ||
                    audio == null ||
                    !range.fits(audio.durationMs)) {
                  return null;
                }
                return () => play(
                  null,
                  excerpt: audio.excerpt(range, paddingMs: paddingMs),
                );
              }

              return AlertDialog(
                title: Text(result.guidance == null ? '历史发音评分' : '发音指导'),
                scrollable: true,
                content: SizedBox(
                  width: 620,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(widget.target.text),
                      if (previousScore != null) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          '上次得分 ${_formatMetric(previousScore, max: 100)}',
                          style: const TextStyle(color: Color(0xFFD6E3EC)),
                        ),
                      ],
                      Wrap(
                        spacing: 8,
                        children: <Widget>[
                          if (_reference != null)
                            TextButton.icon(
                              onPressed: () => play(_reference?.path),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('听原声整句'),
                            ),
                          if (recording != null && recordingPath != null)
                            TextButton.icon(
                              onPressed: () => play(recordingPath),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('听我的整句'),
                            ),
                        ],
                      ),
                      if (playbackError != null) Text(playbackError!),
                      if (recording == null) const Text('这条记录的录音不可用。'),
                      _CardSurface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            TextButton.icon(
                              onPressed: speaking
                                  ? () {
                                      unawaited(stopSpeech());
                                      update(() {});
                                    }
                                  : () => unawaited(readHint()),
                              icon: Icon(
                                speaking
                                    ? Icons.stop_rounded
                                    : Icons.volume_up_rounded,
                              ),
                              label: Text(speaking ? '停止朗读' : '听发音指导'),
                            ),
                            Text(feedback.text),
                            if (speechError != null) Text(speechError!),
                          ],
                        ),
                      ),
                      if (result.guidance == null) ...<Widget>[
                        const SizedBox(height: 8),
                        _buildResult(result, replay: replay),
                      ],
                    ],
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              );
            },
          ),
        ),
      );
    } finally {
      closed = true;
      _stopFeedbackSpeech = null;
      await stopSpeech();
      await playback;
      await _stopResultPlayback();
      final Directory? directory = excerpts;
      if (directory != null) {
        await _runCleanup(() async => directory.delete(recursive: true));
      }
      if (mounted && !_resourcesReleased) {
        setState(() => _showingResult = false);
      }
    }
  }

  Future<void> _stopResultPlayback() async {
    if (_resourcesReleased) return;
    await _runCleanup(_previewPlayer.stop);
    if (mounted && !_resourcesReleased) {
      setState(() {
        _playingPath = null;
        _previewPositionMs = 0;
      });
    }
  }

  Widget _buildResult(
    PronunciationAssessmentResult result, {
    required VoidCallback? Function(PronunciationAudioRange?, int) replay,
  }) => _CardSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _MetricTile(
                title: '建议评分',
                value: _formatMetric(result.suggestedScore, max: 100),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricTile(
                title: '准确度',
                value: _formatMetric(result.accuracy, max: 100),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: _MetricTile(
                title: '流利度',
                value: _formatMetric(result.fluency, max: 1),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricTile(
                title: '完整度',
                value: _formatMetric(result.completion, max: 1),
              ),
            ),
          ],
        ),
        if (result.words.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          const Text(
            '逐词结果',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const Text(
            '高亮项建议复练。点带播放图标的词或音素，回听自己的录音片段。',
            style: TextStyle(color: Color(0xFFD6E3EC), fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final PronunciationWordResult word in result.words)
                _wordChip(word, replay: replay),
            ],
          ),
        ],
      ],
    ),
  );

  Widget _wordChip(
    PronunciationWordResult word, {
    required VoidCallback? Function(PronunciationAudioRange?, int) replay,
  }) {
    final String reference = word.referenceWord.replaceFirst(
      RegExp(r'_\d+$'),
      '',
    );
    final String spoken = word.word == '*' ? '' : word.word;
    final bool needsReview =
        (word.accuracy ?? 100) < pronunciationReviewThreshold ||
        word.phones.any(
          (PronunciationPhoneResult phone) =>
              (phone.accuracy ?? 100) < pronunciationReviewThreshold,
        );
    final String label = switch (word.matchTag) {
      2 => reference.isEmpty || reference == '*' ? '漏读' : '$reference · 漏读',
      1 => spoken.isEmpty ? '多读' : '$spoken · 多读',
      _ => spoken.isEmpty ? reference : spoken,
    };
    final Color color = switch (word.matchTag) {
      1 => const Color(0xFFFFCE90),
      2 || 3 => const Color(0xFFFFB5AC),
      4 => const Color(0xFFD6E3EC),
      _ when needsReview => const Color(0xFFFFB5AC),
      _ when word.accuracy == null => const Color(0xFFD6E3EC),
      _ => const Color(0xFF8EDAB7),
    };
    final String detail = switch (word.matchTag) {
      1 => '新增单词',
      2 => '缺少单词',
      3 => '错读的词',
      4 => '未录入单词',
      _ when needsReview => '建议复练',
      _ => '发音准确度',
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _replayLabel(
              '${label.isEmpty ? '—' : label}${word.accuracy == null ? '' : ' ${word.accuracy!.round()}'}',
              color: color,
              onPlay: replay(word.audioRange, 60),
            ),
            if (word.phones.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  for (final PronunciationPhoneResult phone in word.phones)
                    _replayLabel(
                      phone.detectedLabel == null
                          ? '${phone.label} ${phone.accuracy?.round() ?? '—'}'
                          : '${phone.label} ${phone.accuracy?.round() ?? '—'}（听起来像 ${phone.detectedLabel}）',
                      color:
                          (phone.accuracy ?? 100) < pronunciationReviewThreshold
                          ? const Color(0xFFFFB5AC)
                          : const Color(0xFFD6E3EC),
                      onPlay: replay(phone.audioRange, 100),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _replayLabel(
    String label, {
    required Color color,
    VoidCallback? onPlay,
  }) {
    final Widget text = Text(
      label,
      style: TextStyle(color: color, fontSize: 12),
    );
    if (onPlay == null) return text;
    return TextButton.icon(
      onPressed: onPlay,
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(44, 40),
      ),
      icon: const Icon(Icons.play_arrow_rounded, size: 16),
      label: text,
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
  const _MetricTile({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => DecoratedBox(
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
