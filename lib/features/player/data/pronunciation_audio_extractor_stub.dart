import '../domain/pronunciation_assessment.dart';

class PronunciationAudioSegment {
  const PronunciationAudioSegment({required this.path, required this.audio});

  final String path;
  final Pcm16MonoAudio audio;
}

class PronunciationAudioExtractor {
  Future<PronunciationAudioSegment> extract({
    required String source,
    required int startMs,
    required int endMs,
    required Duration videoDuration,
    void Function(Future<void> Function() cancel)? onCancelAvailable,
  }) async {
    throw const PronunciationAudioExtractionException('此平台暂不支持提取视频原声。');
  }
}

class PronunciationAudioExtractionException implements Exception {
  const PronunciationAudioExtractionException(this.message);

  final String message;

  @override
  String toString() => message;
}
