import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:record/record.dart';

import '../domain/pronunciation_assessment.dart';
import 'pronunciation_audio_extractor.dart';
import 'tencent_pronunciation_service.dart';

final Provider<PronunciationAudioExtractor>
pronunciationAudioExtractorProvider = Provider<PronunciationAudioExtractor>(
  (Ref ref) => PronunciationAudioExtractor(),
);

final Provider<TencentPronunciationService>
tencentPronunciationServiceProvider = Provider<TencentPronunciationService>(
  (Ref ref) => TencentPronunciationService(),
);

abstract interface class PronunciationMicrophone {
  Future<bool> requestPermission();
  Future<Stream<Uint8List>> start();
  Future<void> stop();
  Future<void> cancel();
  Future<void> dispose();
}

class RecordPronunciationMicrophone implements PronunciationMicrophone {
  RecordPronunciationMicrophone({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> requestPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> start() => _recorder.startStream(
    const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: Pcm16MonoAudio.expectedSampleRate,
      numChannels: 1,
    ),
  );

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> dispose() => _recorder.dispose();
}

abstract interface class PronunciationPreviewPlayer {
  Stream<Duration> get position;
  Future<void> playLocalFile(String path);
  Future<void> stop();
  Future<void> dispose();
}

class MediaKitPronunciationPreviewPlayer implements PronunciationPreviewPlayer {
  Player? _player;
  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  StreamSubscription<Duration>? _positionSubscription;

  @override
  Stream<Duration> get position => _position.stream;

  @override
  Future<void> playLocalFile(String path) async {
    final Player player = _player ??= Player();
    _positionSubscription ??= player.stream.position.listen(_position.add);
    _position.add(Duration.zero);
    await player.open(Media(Uri.file(path).toString()));
    await player.play();
  }

  @override
  Future<void> stop() async {
    await _player?.stop();
    if (!_position.isClosed) _position.add(Duration.zero);
  }

  @override
  Future<void> dispose() async {
    final Player? player = _player;
    _player = null;
    await _positionSubscription?.cancel();
    await player?.dispose();
    await _position.close();
  }
}

final Provider<PronunciationMicrophone Function()>
pronunciationMicrophoneFactoryProvider =
    Provider<PronunciationMicrophone Function()>(
      (Ref ref) => RecordPronunciationMicrophone.new,
    );

final Provider<PronunciationPreviewPlayer Function()>
pronunciationPreviewPlayerFactoryProvider =
    Provider<PronunciationPreviewPlayer Function()>(
      (Ref ref) => MediaKitPronunciationPreviewPlayer.new,
    );
