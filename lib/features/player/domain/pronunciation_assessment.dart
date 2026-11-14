import 'dart:math' as math;
import 'dart:typed_data';

class PronunciationAssessmentTarget {
  const PronunciationAssessmentTarget({
    required this.text,
    required this.videoSource,
    required this.startMs,
    required this.endMs,
    required this.videoDuration,
    this.subtitleStartMs,
    this.subtitleEndMs,
  });

  final String text;
  final String videoSource;
  final int startMs;
  final int endMs;
  final Duration videoDuration;
  final int? subtitleStartMs;
  final int? subtitleEndMs;

  String? get validationError {
    if (text.trim().isEmpty || !_containsEnglish(text)) {
      return '当前句没有可供跟读的英文字幕。';
    }
    if (startMs < 0 || endMs <= startMs) return '字幕时间无效，暂时无法跟读。';
    if (videoDuration <= Duration.zero) return '视频时长暂不可用。';
    if (startMs >= videoDuration.inMilliseconds) return '字幕超出视频范围。';
    if (endMs - startMs > 60000) return '单句片段超过 60 秒，暂不支持跟读。';
    if (wordCount > 120) return '这句超过 120 个英文单词，暂不支持跟读。';
    return null;
  }

  int get wordCount =>
      RegExp("[A-Za-z]+(?:['’][A-Za-z]+)?").allMatches(text).length;

  static bool _containsEnglish(String value) =>
      RegExp('[A-Za-z]').hasMatch(value);
}

class PronunciationCredentials {
  const PronunciationCredentials({this.apiKey = ''});

  final String apiKey;

  bool get isComplete => apiKey.trim().isNotEmpty;
}

class PronunciationWordResult {
  const PronunciationWordResult({
    required this.word,
    required this.referenceWord,
    required this.matchTag,
    this.accuracy,
    this.audioRange,
    this.phones = const <PronunciationPhoneResult>[],
  });

  final String word;
  final String referenceWord;
  final int matchTag;
  final double? accuracy;
  final PronunciationAudioRange? audioRange;
  final List<PronunciationPhoneResult> phones;
}

class PronunciationPhoneResult {
  const PronunciationPhoneResult({
    required this.label,
    this.accuracy,
    this.audioRange,
    this.detectedLabel,
  });

  final String label;
  final double? accuracy;
  final PronunciationAudioRange? audioRange;
  final String? detectedLabel;
}

class PronunciationAudioRange {
  const PronunciationAudioRange(this.startMs, this.endMs);

  final int startMs;
  final int endMs;

  static PronunciationAudioRange? fromTimestamps(Object? start, Object? end) {
    if (start is! int || end is! int || start < 0 || end <= start) return null;
    return PronunciationAudioRange(start, end);
  }

  bool fits(int durationMs) =>
      startMs >= 0 && startMs < durationMs && endMs > startMs;
}

class PronunciationAssessmentResult {
  const PronunciationAssessmentResult({
    this.guidance,
    this.suggestedScore,
    this.accuracy,
    this.fluency,
    this.completion,
    this.words = const <PronunciationWordResult>[],
  });

  final String? guidance;
  final double? suggestedScore;
  final double? accuracy;
  final double? fluency;
  final double? completion;
  final List<PronunciationWordResult> words;

  Map<String, Object?> toJson() => guidance != null
      ? <String, Object?>{'guidance': guidance}
      : <String, Object?>{
          'SuggestedScore': suggestedScore,
          'PronAccuracy': accuracy,
          'PronFluency': fluency,
          'PronCompletion': completion,
          'Words': <Object>[
            for (final PronunciationWordResult word in words)
              <String, Object?>{
                'Word': word.word,
                'ReferenceWord': word.referenceWord,
                'MatchTag': word.matchTag,
                'PronAccuracy': word.accuracy,
                'MemBeginTime': word.audioRange?.startMs,
                'MemEndTime': word.audioRange?.endMs,
                'PhoneInfos': <Object>[
                  for (final PronunciationPhoneResult phone in word.phones)
                    <String, Object?>{
                      'Phone': phone.detectedLabel ?? phone.label,
                      'ReferencePhone': phone.label,
                      'PronAccuracy': phone.accuracy,
                      'MemBeginTime': phone.audioRange?.startMs,
                      'MemEndTime': phone.audioRange?.endMs,
                    },
                ],
              },
          ],
        };

  static PronunciationAssessmentResult? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final Object? guidance = raw['guidance'];
    if (guidance is String && guidance.trim().isNotEmpty) {
      return PronunciationAssessmentResult(guidance: guidance.trim());
    }
    final Map<String, Object?> value = <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in raw.entries)
        if (entry.key is String) entry.key! as String: entry.value,
    };
    double? number(Object? field, {double? max}) {
      if (field is! num) return null;
      final double parsed = field.toDouble();
      if (!parsed.isFinite || parsed < 0 || (max != null && parsed > max)) {
        return null;
      }
      return parsed;
    }

    final double? score = number(value['SuggestedScore'], max: 100);
    final double? accuracy = number(value['PronAccuracy'], max: 100);
    final double? fluency = number(value['PronFluency'], max: 1);
    final double? completion = number(value['PronCompletion'], max: 1);
    final List<PronunciationWordResult> words = <PronunciationWordResult>[];
    final Object? rawWords = value['Words'];
    if (rawWords is List) {
      for (final Object? item in rawWords) {
        if (item is! Map) continue;
        final Object? rawTag = item['MatchTag'];
        final int tag = rawTag is num ? rawTag.toInt() : -1;
        final Object? rawWord = item['Word'];
        final Object? rawReference = item['ReferenceWord'];
        final List<PronunciationPhoneResult> phones =
            <PronunciationPhoneResult>[];
        final Object? rawPhones = item['PhoneInfos'] ?? item['PhoneInfo'];
        if (rawPhones is List) {
          for (final Object? phone in rawPhones) {
            if (phone is! Map) continue;
            final Object? rawReference = phone['ReferencePhone'];
            final String reference = rawReference is String
                ? rawReference.trim()
                : '';
            final Object? rawActual = phone['Phone'];
            final String actual = rawActual is String ? rawActual.trim() : '';
            final String label = reference.isNotEmpty && reference != '*'
                ? reference
                : actual;
            if (label.isEmpty || label == '*') continue;
            phones.add(
              PronunciationPhoneResult(
                label: label,
                detectedLabel:
                    actual.isNotEmpty && actual != '*' && actual != label
                    ? actual
                    : null,
                accuracy: number(phone['PronAccuracy'], max: 100),
                audioRange: PronunciationAudioRange.fromTimestamps(
                  phone['MemBeginTime'] ?? phone['Mbtm'],
                  phone['MemEndTime'] ?? phone['Metm'],
                ),
              ),
            );
          }
        }
        words.add(
          PronunciationWordResult(
            word: rawWord is String ? rawWord : '',
            referenceWord: rawReference is String ? rawReference : '',
            matchTag: tag,
            accuracy: number(item['PronAccuracy'], max: 100),
            audioRange: tag == 2
                ? null
                : PronunciationAudioRange.fromTimestamps(
                    item['MemBeginTime'] ?? item['Mbtm'],
                    item['MemEndTime'] ?? item['Metm'],
                  ),
            phones: List<PronunciationPhoneResult>.unmodifiable(phones),
          ),
        );
      }
    }
    if (score == null &&
        accuracy == null &&
        fluency == null &&
        completion == null &&
        words.isEmpty) {
      return null;
    }
    return PronunciationAssessmentResult(
      suggestedScore: score,
      accuracy: accuracy,
      fluency: fluency,
      completion: completion,
      words: List<PronunciationWordResult>.unmodifiable(words),
    );
  }
}

class Pcm16MonoAudio {
  const Pcm16MonoAudio({required this.bytes, required this.sampleRate});

  factory Pcm16MonoAudio.parseWav(Uint8List wav) {
    if (wav.length < 12 ||
        String.fromCharCodes(wav.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(wav.sublist(8, 12)) != 'WAVE') {
      throw const FormatException('Unsupported WAV file');
    }
    final ByteData data = ByteData.sublistView(wav);
    int? sampleRate;
    int? channels;
    int? bitsPerSample;
    int? format;
    Uint8List? pcm;
    int offset = 12;
    while (offset + 8 <= wav.length) {
      final String id = String.fromCharCodes(wav.sublist(offset, offset + 4));
      final int size = data.getUint32(offset + 4, Endian.little);
      final int start = offset + 8;
      final int end = start + size;
      if (end > wav.length) throw const FormatException('Invalid WAV chunk');
      if (id == 'fmt ' && size >= 16) {
        format = data.getUint16(start, Endian.little);
        channels = data.getUint16(start + 2, Endian.little);
        sampleRate = data.getUint32(start + 4, Endian.little);
        bitsPerSample = data.getUint16(start + 14, Endian.little);
      } else if (id == 'data') {
        pcm = Uint8List.fromList(wav.sublist(start, end));
      }
      offset = end + (size.isOdd ? 1 : 0);
    }
    if (format != 1 ||
        channels != 1 ||
        bitsPerSample != 16 ||
        sampleRate == null ||
        pcm == null) {
      throw const FormatException('WAV must contain PCM16 mono audio');
    }
    if (sampleRate != expectedSampleRate) {
      throw const FormatException('WAV sample rate must be 16000 Hz');
    }
    return Pcm16MonoAudio(bytes: pcm, sampleRate: sampleRate);
  }

  static const int expectedSampleRate = 16000;

  final Uint8List bytes;
  final int sampleRate;

  int get durationMs =>
      sampleRate <= 0 ? 0 : (bytes.length * 1000) ~/ (sampleRate * 2);

  Pcm16MonoAudio? excerpt(PronunciationAudioRange range, {int paddingMs = 0}) {
    if (!range.fits(durationMs)) return null;
    final int padding = math.max(0, paddingMs);
    final int startMs = math.max(0, range.startMs - padding);
    final int endMs = math.min(durationMs, range.endMs + padding);
    final int start = (startMs * sampleRate ~/ 1000) * 2;
    final int end = (endMs * sampleRate ~/ 1000) * 2;
    return Pcm16MonoAudio(
      bytes: Uint8List.sublistView(bytes, start, end),
      sampleRate: sampleRate,
    );
  }

  /// Discards only leading quiet audio. Internal pauses and real timing remain.
  /// Three active 10 ms frames reject isolated clicks; 20 ms of pre-roll
  /// protects the beginning of soft consonants. This is energy gating, not ASR.
  Pcm16MonoAudio trimLeadingSilence() {
    final int count = bytes.length ~/ 2;
    final int frame = math.max(1, sampleRate ~/ 100);
    final ByteData data = ByteData.sublistView(bytes);
    int activeFrames = 0;
    for (int start = 0; start + frame <= count; start += frame) {
      double squares = 0;
      for (int i = start; i < start + frame; i++) {
        final int sample = data.getInt16(i * 2, Endian.little);
        squares += sample * sample;
      }
      activeFrames = squares / frame > 90000 ? activeFrames + 1 : 0;
      if (activeFrames >= 3) {
        final int first = math.max(0, start - frame * 4);
        if (first == 0) return this;
        return Pcm16MonoAudio(
          bytes: Uint8List.sublistView(bytes, first * 2, count * 2),
          sampleRate: sampleRate,
        );
      }
    }
    return Pcm16MonoAudio(bytes: Uint8List(0), sampleRate: sampleRate);
  }

  bool get hasSpeechEnergy {
    if (bytes.length < sampleRate * 2 ~/ 5) return false;
    final int sampleCount = bytes.length ~/ 2;
    final int windowSize = sampleRate ~/ 5;
    int activeWindows = 0;
    int windowCount = 0;
    int maximum = 0;
    final ByteData data = ByteData.sublistView(bytes);
    for (int start = 0; start < sampleCount; start += windowSize) {
      final int end = (start + windowSize).clamp(0, sampleCount);
      double squares = 0;
      for (int i = start; i < end; i++) {
        final int sample = data.getInt16(i * 2, Endian.little);
        final int magnitude = sample.abs();
        if (magnitude > maximum) maximum = magnitude;
        squares += sample * sample;
      }
      if (end > start && (squares / (end - start)) > 90000) activeWindows++;
      windowCount++;
    }
    return maximum >= 700 &&
        windowCount > 0 &&
        activeWindows / windowCount >= 0.03;
  }

  List<double> get waveform {
    if (bytes.length < 2) return const <double>[];
    const int buckets = 192;
    final int count = bytes.length ~/ 2;
    final int window = (count / buckets).ceil();
    final ByteData data = ByteData.sublistView(bytes);
    final List<double> values = <double>[];
    for (int start = 0; start < count; start += window) {
      final int end = (start + window).clamp(0, count);
      double squares = 0;
      for (int i = start; i < end; i++) {
        final int sample = data.getInt16(i * 2, Endian.little);
        squares += sample * sample;
      }
      values.add(end == start ? 0 : math.sqrt(squares / (end - start)) / 32768);
      if (values.length == buckets) break;
    }
    return List<double>.unmodifiable(values);
  }

  Uint8List toWav() {
    final int dataLength = bytes.length - (bytes.length % 2);
    final ByteData header = ByteData(44);
    void writeText(int offset, String text) {
      for (int i = 0; i < text.length; i++) {
        header.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    writeText(0, 'RIFF');
    writeText(8, 'WAVE');
    writeText(12, 'fmt ');
    writeText(36, 'data');
    header
      ..setUint32(4, 36 + dataLength, Endian.little)
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, sampleRate, Endian.little)
      ..setUint32(28, sampleRate * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little)
      ..setUint32(40, dataLength, Endian.little);
    return Uint8List.fromList(<int>[
      ...header.buffer.asUint8List(),
      ...bytes.take(dataLength),
    ]);
  }
}
