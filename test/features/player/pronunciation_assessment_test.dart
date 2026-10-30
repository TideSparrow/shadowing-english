import 'dart:typed_data';

import 'package:common_learn_english/features/player/domain/pronunciation_assessment.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/pronunciation_target_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'sound alignment removes leading silence and clicks, preserves pauses',
    () {
      final Uint8List bytes = Uint8List(16000 * 2);
      // A brief click at 100 ms must not start the sentence.
      final ByteData data = ByteData.sublistView(bytes)
        ..setInt16(1600 * 2, 24000, Endian.little);
      for (int i = 4800; i < 8000; i++) {
        data.setInt16(i * 2, i.isEven ? 4000 : -4000, Endian.little);
      }
      for (int i = 11200; i < 14400; i++) {
        data.setInt16(i * 2, i.isEven ? 3000 : -3000, Endian.little);
      }
      final Pcm16MonoAudio original = Pcm16MonoAudio(
        bytes: bytes,
        sampleRate: 16000,
      );
      final Pcm16MonoAudio aligned = original.trimLeadingSilence();
      expect(aligned.durationMs, 720); // 300 ms onset minus 20 ms pre-roll.
      expect(aligned.bytes, orderedEquals(bytes.sublist(4480 * 2)));
      expect(aligned.trimLeadingSilence().bytes, orderedEquals(aligned.bytes));
      expect(
        Pcm16MonoAudio(
          bytes: Uint8List(32000),
          sampleRate: 16000,
        ).trimLeadingSilence().durationMs,
        0,
      );
    },
  );

  PlayerMockState stateWithLines() {
    return PlayerMockState()
      ..loadLines(const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:00',
          english: 'Take a break.',
          chinese: '休息一下。',
          startMs: 600,
          endMs: 1551,
          words: <PlayerSubtitleWord>[
            PlayerSubtitleWord(text: 'Take', startMs: 600, endMs: 850),
            PlayerSubtitleWord(text: 'a', startMs: 850, endMs: 1000),
            PlayerSubtitleWord(text: 'break.', startMs: 1000, endMs: 1551),
          ],
        ),
        PlayerSubtitleLine(
          startTime: '00:02',
          english: 'Listen.',
          chinese: '听。',
          startMs: 2151,
          endMs: 2841,
        ),
        PlayerSubtitleLine(
          startTime: '00:03',
          english: '',
          chinese: '没有英文。',
          startMs: 3441,
          endMs: 4393,
        ),
      ])
      ..subtitleDelayMs = 120;
  }

  test('visible sentence and exact row use delayed video timestamps', () {
    final PlayerMockState state = stateWithLines()..positionMs = 900;
    final PronunciationTargetSelection visible = selectPronunciationTarget(
      state: state,
      videoSource: '/course/Practice.mp4',
      videoReady: true,
      videoDuration: const Duration(milliseconds: 5393),
    );
    expect(visible.target?.text, 'Take a break.');
    expect(visible.target?.startMs, 720);
    expect(visible.target?.endMs, 1671);

    final PronunciationTargetSelection selectedRow = selectPronunciationTarget(
      state: state,
      videoSource: '/course/Practice.mp4',
      videoReady: true,
      videoDuration: const Duration(milliseconds: 5393),
      subtitleIndex: 1,
    );
    expect(selectedRow.target?.text, 'Listen.');
    expect(selectedRow.target?.startMs, 2271);
    expect(selectedRow.target?.endMs, 2961);
  });

  test(
    'subtitle gap, non-English row, and unavailable media disable selection',
    () {
      final PlayerMockState state = stateWithLines()..positionMs = 1900;
      final PronunciationTargetSelection gap = selectPronunciationTarget(
        state: state,
        videoSource: '/course/Practice.mp4',
        videoReady: true,
        videoDuration: const Duration(milliseconds: 5393),
      );
      expect(gap.target, isNull);
      expect(gap.unavailableReason, contains('没有正在显示'));

      final PronunciationTargetSelection nonEnglish = selectPronunciationTarget(
        state: state,
        videoSource: '/course/Practice.mp4',
        videoReady: true,
        videoDuration: const Duration(milliseconds: 5393),
        subtitleIndex: 2,
      );
      expect(nonEnglish.target, isNull);
      expect(nonEnglish.unavailableReason, contains('英文字幕'));

      final PronunciationTargetSelection noMedia = selectPronunciationTarget(
        state: state,
        videoSource: '/missing/Practice.mp4',
        videoReady: false,
        videoDuration: const Duration(milliseconds: 5393),
        subtitleIndex: 1,
      );
      expect(noMedia.target, isNull);
      expect(noMedia.unavailableReason, contains('视频'));
    },
  );

  test('PCM waveform uses measured amplitude and WAV parser scans chunks', () {
    final Uint8List samples = Uint8List(3200);
    final ByteData sampleData = ByteData.sublistView(samples);
    for (int offset = 0; offset < samples.length; offset += 2) {
      sampleData.setInt16(offset, 10000, Endian.little);
    }
    final Pcm16MonoAudio audio = Pcm16MonoAudio(
      bytes: samples,
      sampleRate: Pcm16MonoAudio.expectedSampleRate,
    );
    expect(audio.durationMs, 100);
    expect(audio.waveform.first, closeTo(10000 / 32768, 0.0001));

    final Uint8List wav = audio.toWav();
    final Uint8List withJunkChunk = Uint8List.fromList(<int>[
      ...wav.sublist(0, 12),
      ...'JUNK'.codeUnits,
      4,
      0,
      0,
      0,
      1,
      2,
      3,
      4,
      ...wav.sublist(12),
    ]);
    ByteData.sublistView(
      withJunkChunk,
    ).setUint32(4, withJunkChunk.length - 8, Endian.little);
    final Pcm16MonoAudio parsed = Pcm16MonoAudio.parseWav(withJunkChunk);
    expect(parsed.bytes, samples);
    expect(parsed.sampleRate, 16000);
  });
}
