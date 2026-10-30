import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/pronunciation_assessment.dart';
import '../presentation/desktop_ffmpeg.dart';
import 'pronunciation_audio_extractor_stub.dart';

const MethodChannel _pronunciationAudioChannel = MethodChannel(
  'com.shadowing.english/audio_tools',
);

class PronunciationAudioExtractor {
  Future<PronunciationAudioSegment> extract({
    required String source,
    required int startMs,
    required int endMs,
    required Duration videoDuration,
    void Function(Future<void> Function() cancel)? onCancelAvailable,
  }) async {
    final int boundedStart = startMs.clamp(0, videoDuration.inMilliseconds);
    final int boundedEnd = endMs.clamp(0, videoDuration.inMilliseconds);
    if (source.isEmpty || boundedEnd <= boundedStart) {
      throw const PronunciationAudioExtractionException('视频或字幕时间无效。');
    }
    if (boundedEnd - boundedStart > 60000) {
      throw const PronunciationAudioExtractionException(
        '单句片段超过 60 秒，暂不支持提取原声。',
      );
    }
    if (source.startsWith('http://') || source.startsWith('https://')) {
      throw const PronunciationAudioExtractionException('暂不支持从远程视频提取原声。');
    }
    if (Platform.isIOS) {
      throw const PronunciationAudioExtractionException('iOS 暂不支持提取视频原声。');
    }

    String localSource = source;
    String? stagedAsset;
    if (source.startsWith('assets/') || source.startsWith('asset:///')) {
      final String assetName = source.startsWith('asset:///')
          ? source.substring('asset:///'.length)
          : source;
      final ByteData bytes = await rootBundle.load(assetName);
      final Directory temp = await getTemporaryDirectory();
      await temp.create(recursive: true);
      stagedAsset = '${temp.path}/pronunciation-source-${_randomId()}.media';
      final File assetCopy = File(stagedAsset);
      await assetCopy.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
      localSource = stagedAsset;
    } else if (!File(source).existsSync()) {
      throw const PronunciationAudioExtractionException('本地视频文件不可用。');
    }

    String? generatedWav;
    bool returned = false;
    try {
      final String wavPath;
      if (Platform.isAndroid) {
        final String requestId = _randomId();
        bool cancelled = false;
        Future<void> cancelRequest() async {
          cancelled = true;
          try {
            await _pronunciationAudioChannel
                .invokeMethod<void>(
                  'cancelPronunciationAudioExtraction',
                  <String, Object?>{'requestId': requestId},
                )
                .timeout(const Duration(seconds: 2));
          } catch (_) {}
        }

        onCancelAvailable?.call(() async {
          await cancelRequest();
        });
        final Future<String?> extraction = _pronunciationAudioChannel
            .invokeMethod<String>(
              'extractPronunciationAudio',
              <String, Object?>{
                'requestId': requestId,
                'sourcePath': localSource,
                'startMs': boundedStart,
                'endMs': boundedEnd,
              },
            );
        if (cancelled) {
          await cancelRequest();
        }
        final String? result;
        try {
          result = await extraction.timeout(const Duration(seconds: 35));
        } on TimeoutException {
          await cancelRequest();
          throw TimeoutException('Audio extraction timed out.');
        }
        if (result == null || result.isEmpty) {
          throw const PronunciationAudioExtractionException('提取视频原声失败。');
        }
        wavPath = result;
        generatedWav = result;
      } else {
        final String? ffmpeg = await findDesktopFfmpeg();
        if (ffmpeg == null) {
          throw const PronunciationAudioExtractionException(
            '未找到桌面版 FFmpeg，无法提取视频原声。',
          );
        }
        final Directory temp = await getTemporaryDirectory();
        await temp.create(recursive: true);
        final String output =
            '${temp.path}/pronunciation-reference-${_randomId()}.wav';
        generatedWav = output;
        final Process process = await Process.start(ffmpeg, <String>[
          '-hide_banner',
          '-loglevel',
          'error',
          '-y',
          '-ss',
          (boundedStart / 1000).toStringAsFixed(3),
          '-i',
          localSource,
          '-t',
          ((boundedEnd - boundedStart) / 1000).toStringAsFixed(3),
          '-vn',
          '-ac',
          '1',
          '-ar',
          Pcm16MonoAudio.expectedSampleRate.toString(),
          '-c:a',
          'pcm_s16le',
          output,
        ]);
        onCancelAvailable?.call(() async {
          process.kill();
          try {
            await process.exitCode.timeout(const Duration(seconds: 2));
          } catch (_) {}
          final File outputFile = File(output);
          try {
            if (outputFile.existsSync()) await outputFile.delete();
          } catch (_) {
            debugPrint('Pronunciation temporary audio cleanup failed.');
          }
        });
        unawaited(process.stdout.drain<void>());
        unawaited(process.stderr.drain<void>());
        final int exitCode = await process.exitCode.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            process.kill();
            return -1;
          },
        );
        if (exitCode != 0) {
          throw const PronunciationAudioExtractionException('提取视频原声失败。');
        }
        wavPath = output;
      }

      final File wavFile = File(wavPath);
      final Pcm16MonoAudio audio = Pcm16MonoAudio.parseWav(
        await wavFile.readAsBytes(),
      );
      if (audio.durationMs == 0) {
        throw const PronunciationAudioExtractionException('这段视频没有可播放的原声。');
      }
      returned = true;
      return PronunciationAudioSegment(path: wavPath, audio: audio);
    } on PronunciationAudioExtractionException {
      rethrow;
    } on PlatformException {
      throw const PronunciationAudioExtractionException('提取视频原声失败，请检查视频编码。');
    } on TimeoutException {
      throw const PronunciationAudioExtractionException('提取视频原声超时。');
    } catch (_) {
      throw const PronunciationAudioExtractionException('当前视频暂时无法提取原声。');
    } finally {
      if (!returned && generatedWav != null) {
        await _deleteTemporaryFile(generatedWav);
      }
      if (stagedAsset != null) {
        await _deleteTemporaryFile(stagedAsset);
      }
    }
  }

  static String _randomId() {
    final Random random = Random.secure();
    return List<String>.generate(
      4,
      (_) => random.nextInt(0x100000000).toRadixString(16).padLeft(8, '0'),
    ).join();
  }

  static Future<void> _deleteTemporaryFile(String path) async {
    try {
      final File file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // Never include temporary paths or audio data in diagnostics.
      debugPrint('Pronunciation temporary audio cleanup failed.');
    }
  }
}
