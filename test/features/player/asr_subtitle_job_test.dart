import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:common_learn_english/features/player/presentation/asr_subtitle_cache.dart';
import 'package:common_learn_english/features/player/presentation/asr_subtitle_job.dart';
import 'package:common_learn_english/features/player/presentation/asr_subtitle_service.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/player_subtitle_loader.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('batch Chinese subtitles', () {
    late Directory root;
    late File video;
    late List<String> source;
    final LearningSettingsState settings = _settings().copyWith(
      generateBilingualAsrSubtitles: true,
    );
    setUp(() {
      root = Directory.systemTemp.createTempSync('asr-job-batch-');
      video = File('${root.path}/lesson.mp4')..writeAsStringSync('video');
      source = List<String>.generate(418, (int i) => 'Sentence number $i.');
    });
    tearDown(() => root.deleteSync(recursive: true));

    AsrSubtitleJobRunner runner({
      AsrBatchTranslator? batch,
      AsrSentenceTranslator? sentence,
    }) => AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          for (int i = 0; i < source.length; i += 28)
            AsrAudioChunk(
              file: File('${root.path}/chunk$i.m4a')
                ..writeAsStringSync('audio'),
              offsetMs: i * 2000,
            ),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async => <String, Object?>{
            'version': 1,
            'language': 'en',
            'lines': <Map<String, Object?>>[
              for (
                int i = chunk.offsetMs ~/ 2000;
                i < source.length && i < chunk.offsetMs ~/ 2000 + 28;
                i += 1
              )
                _chunkLine(source[i], i * 2000),
            ],
          },
      translateSentences: batch,
      translateSentence: sentence,
    );

    test(
      '418 lines use 11 requests and preserve text and word timings',
      () async {
        final List<int> sizes = <int>[];
        final List<AsrSubtitleProgress> progress = <AsrSubtitleProgress>[];
        final String raw =
            await runner(
              batch:
                  ({
                    required List<String> sentences,
                    required LearningSettingsState settings,
                  }) async {
                    sizes.add(sentences.length);
                    return sentences.map((String text) => '翻译：$text').toList();
                  },
            ).run(
              episodeId: 'batch-episode',
              videoPath: video.path,
              settings: settings,
              onProgress: progress.add,
            );
        final List<PlayerSubtitleLine> lines = parseSubtitleLines(raw);
        expect(sizes, <int>[...List<int>.filled(10, 40), 18]);
        expect(lines.map((PlayerSubtitleLine line) => line.english), source);
        for (int i = 0; i < source.length; i += 1) {
          expect(lines[i].chinese, '翻译：${source[i]}');
          expect(lines[i].startMs, i * 2000);
          expect(lines[i].words.first.startMs, i * 2000);
          expect(lines[i].words.last.endMs, i * 2000 + 1000);
        }
        expect(
          progress
              .where(
                (AsrSubtitleProgress p) =>
                    p.phase == AsrSubtitlePhase.translating,
              )
              .map((AsrSubtitleProgress p) => p.completedTranslations),
          <int>[0, for (int i = 40; i <= 400; i += 40) i, 418],
        );
        expect(subtitleGenerationWarning(raw), isNull);
      },
    );

    test(
      'failed batch keeps completed lines and resumes only missing batches',
      () async {
        source = source.take(82).toList();
        int calls = 0;
        final List<List<String>> resumed = <List<String>>[];
        bool fail = true;
        final AsrSubtitleJobRunner job = runner(
          batch:
              ({
                required List<String> sentences,
                required LearningSettingsState settings,
              }) async {
                calls += 1;
                if (fail && calls == 2) throw StateError('network unavailable');
                if (!fail) resumed.add(sentences);
                return sentences.map((String text) => '翻译：$text').toList();
              },
        );
        final String partial = await job.run(
          episodeId: 'batch-episode',
          videoPath: video.path,
          settings: settings,
        );
        expect(subtitleGenerationWarning(partial), isNotNull);
        expect(
          parseSubtitleLines(
            partial,
          ).where((PlayerSubtitleLine line) => line.chinese.isNotEmpty).length,
          40,
        );
        fail = false;
        final String complete = await job.run(
          episodeId: 'batch-episode',
          videoPath: video.path,
          settings: settings,
        );
        expect(resumed.map((List<String> batch) => batch.length), <int>[40, 2]);
        expect(resumed.expand((List<String> batch) => batch), source.skip(40));
        expect(
          parseSubtitleLines(
            complete,
          ).every((PlayerSubtitleLine line) => line.chinese.isNotEmpty),
          isTrue,
        );
        expect(subtitleGenerationWarning(complete), isNull);
      },
    );

    test('old sentence checkpoints are reused by batch translation', () async {
      source = source.take(3).toList();
      final AsrSubtitleJobRunner old = runner(
        sentence:
            ({
              required String sentence,
              required LearningSettingsState settings,
            }) async => sentence == source.first ? '原有翻译' : null,
      );
      await old.run(
        episodeId: 'batch-episode',
        videoPath: video.path,
        settings: settings,
      );
      final String raw =
          await runner(
            batch:
                ({
                  required List<String> sentences,
                  required LearningSettingsState settings,
                }) async {
                  expect(sentences, source.skip(1));
                  return <String>['第二句', '第三句'];
                },
          ).run(
            episodeId: 'batch-episode',
            videoPath: video.path,
            settings: settings,
          );
      expect(
        parseSubtitleLines(raw).map((PlayerSubtitleLine line) => line.chinese),
        <String>['原有翻译', '第二句', '第三句'],
      );
    });

    test('long subtitles also bound each batch by character count', () async {
      source = List<String>.generate(9, (int i) => '$i ${'word ' * 200}');
      final List<int> sizes = <int>[];
      await runner(
        batch:
            ({
              required List<String> sentences,
              required LearningSettingsState settings,
            }) async {
              sizes.add(sentences.length);
              expect(
                sentences.fold<int>(
                  0,
                  (int sum, String text) => sum + text.length,
                ),
                lessThanOrEqualTo(6000),
              );
              return sentences.map((String text) => '翻译：$text').toList();
            },
      ).run(
        episodeId: 'batch-episode',
        videoPath: video.path,
        settings: settings,
      );
      expect(sizes, <int>[5, 4]);
    });

    test('cancellation saves the completed batch before stopping', () async {
      source = source.take(42).toList();
      final AsrSubtitleCancellationToken token = AsrSubtitleCancellationToken();
      final AsrSubtitleJobRunner job = runner(
        batch:
            ({
              required List<String> sentences,
              required LearningSettingsState settings,
            }) async {
              token.cancel();
              return sentences.map((String text) => '翻译：$text').toList();
            },
      );
      await expectLater(
        job.run(
          episodeId: 'batch-episode',
          videoPath: video.path,
          settings: settings,
          cancellationToken: token,
        ),
        throwsA(isA<AsrSubtitleGenerationException>()),
      );
      int calls = 0;
      await runner(
        batch:
            ({
              required List<String> sentences,
              required LearningSettingsState settings,
            }) async {
              calls += 1;
              expect(sentences, source.skip(40));
              return <String>['余下第一句', '余下第二句'];
            },
      ).run(
        episodeId: 'batch-episode',
        videoPath: video.path,
        settings: settings,
      );
      expect(calls, 1);
    });
  });

  test(
    'reference subtitles keep authoritative text while ASR supplies word timings',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'asr-job-reference-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File video = File('${root.path}/lesson.mp4')
        ..writeAsStringSync('v');
      final File chunk = File('${root.path}/chunk.m4a')..writeAsStringSync('a');
      final AsrSubtitleCache cache = AsrSubtitleCache(
        appSupportDirectory: () async => root,
      );
      final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
        supportDirectory: () async => root,
        cache: cache,
        service: AsrSubtitleService(
          prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
            AsrAudioChunk(file: chunk, offsetMs: 0),
          ],
        ),
        cloudTranscribeChunk:
            ({
              required AsrAudioChunk chunk,
              required LearningSettingsState settings,
            }) async => _chunkJson('I like go home', 1000),
      );

      final String raw = await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings().copyWith(generateBilingualAsrSubtitles: true),
        referenceSignatureOverride: 'original-reference-signature',
        referenceSubtitleLines: const <PlayerSubtitleLine>[
          PlayerSubtitleLine(
            startTime: '00:01',
            english: 'I would like to go home.',
            chinese: '我想回家。',
            startMs: 1000,
            endMs: 4000,
          ),
        ],
      );

      final PlayerSubtitleLine line = parseSubtitleLines(raw).single;
      expect(line.english, 'I would like to go home.');
      expect(line.chinese, '我想回家。');
      expect(subtitleGenerationWarning(raw), isNull);
      final Map<String, dynamic> decoded =
          jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['referenceLines'], isA<List<dynamic>>());
      final Map<String, dynamic> storedReference =
          (decoded['referenceLines'] as List<dynamic>).single
              as Map<String, dynamic>;
      expect(storedReference['english'], 'I would like to go home.');
      expect(storedReference['chinese'], '我想回家。');
      expect(line.words.map((PlayerSubtitleWord word) => word.text), <String>[
        'I',
        'would',
        'like',
        'to',
        'go',
        'home',
      ]);
      expect(
        await cache.read(
          episodeId: 'episode-1',
          videoPath: video.path,
          settings: _settings().copyWith(generateBilingualAsrSubtitles: true),
          referenceSignature: 'original-reference-signature',
        ),
        isNotNull,
      );
    },
  );

  test('reference subtitle overlap does not fail final validation', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-reference-overlap-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')..writeAsStringSync('v');
    final File chunk = File('${root.path}/chunk.m4a')..writeAsStringSync('a');
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async => _chunkJson('First line', 1000),
    );

    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
      referenceSubtitleLines: const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'First line.',
          chinese: '',
          startMs: 1000,
          endMs: 2500,
        ),
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Second line.',
          chinese: '',
          startMs: 1800,
          endMs: 3200,
        ),
      ],
    );

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(raw);
    expect(lines, hasLength(2));
    expect(lines.last.startMs, lessThan(lines.first.endMs - 250));
  });

  test('transcription retries after a transient provider failure', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-provider-retry-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')..writeAsStringSync('v');
    final File chunk = File('${root.path}/chunk.m4a')..writeAsStringSync('a');
    int calls = 0;
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async {
            calls += 1;
            if (calls == 1) throw StateError('temporary-provider-error');
            return _chunkJson('Recovered subtitle', 1000);
          },
    );

    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );

    expect(calls, 2);
    expect(parseSubtitleLines(raw).single.english, 'Recovered subtitle');
  });

  test(
    'reference subtitles survive persistent transcription failure',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'asr-job-reference-provider-fallback-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File video = File('${root.path}/lesson.mp4')
        ..writeAsStringSync('v');
      final File chunk = File('${root.path}/chunk.m4a')..writeAsStringSync('a');
      int calls = 0;
      final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
        supportDirectory: () async => root,
        cache: AsrSubtitleCache(appSupportDirectory: () async => root),
        service: AsrSubtitleService(
          prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
            AsrAudioChunk(file: chunk, offsetMs: 0),
          ],
        ),
        cloudTranscribeChunk:
            ({
              required AsrAudioChunk chunk,
              required LearningSettingsState settings,
            }) async {
              calls += 1;
              throw StateError('provider-unavailable');
            },
      );

      final String raw = await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
        referenceSubtitleLines: const <PlayerSubtitleLine>[
          PlayerSubtitleLine(
            startTime: '00:01',
            english: 'Authoritative subtitle.',
            chinese: '权威字幕。',
            startMs: 1000,
            endMs: 3000,
          ),
        ],
      );

      expect(calls, 2);
      final PlayerSubtitleLine line = parseSubtitleLines(raw).single;
      expect(line.english, 'Authoritative subtitle.');
      expect(line.words, hasLength(2));
      expect(subtitleGenerationWarning(raw), contains('本地估算'));
    },
  );

  test('reference subtitles survive audio preparation failure', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-reference-audio-fallback-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')..writeAsStringSync('v');
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async =>
            throw StateError('audio-tools-unavailable'),
      ),
    );

    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
      referenceSubtitleLines: const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Local fallback works.',
          chinese: '',
          startMs: 1000,
          endMs: 3000,
        ),
      ],
    );

    expect(parseSubtitleLines(raw).single.english, 'Local fallback works.');
    expect(subtitleGenerationWarning(raw), contains('本地估算'));
  });

  test(
    'bilingual option fills missing Chinese with translation provider',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'asr-job-bilingual-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File video = File('${root.path}/lesson.mp4')
        ..writeAsStringSync('v');
      final File chunk = File('${root.path}/chunk.m4a')..writeAsStringSync('a');
      final List<AsrSubtitleProgress> progress = <AsrSubtitleProgress>[];
      final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
        supportDirectory: () async => root,
        cache: AsrSubtitleCache(appSupportDirectory: () async => root),
        service: AsrSubtitleService(
          prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
            AsrAudioChunk(file: chunk, offsetMs: 0),
          ],
        ),
        cloudTranscribeChunk:
            ({
              required AsrAudioChunk chunk,
              required LearningSettingsState settings,
            }) async => _chunkJson('Hello there', 1000),
        translateSentence:
            ({
              required String sentence,
              required LearningSettingsState settings,
            }) async {
              expect(progress.last.phase, AsrSubtitlePhase.translating);
              expect(progress.last.label, '正在翻译中文字幕 0/1 句');
              return '你好。';
            },
      );

      final String raw = await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: LearningSettingsState.defaults().copyWith(
          generateBilingualAsrSubtitles: true,
        ),
        onProgress: progress.add,
      );

      expect(parseSubtitleLines(raw).single.chinese, '你好。');
      expect(
        progress
            .where(
              (AsrSubtitleProgress value) =>
                  value.phase == AsrSubtitlePhase.translating,
            )
            .map((AsrSubtitleProgress value) => value.completedTranslations),
        <int>[0, 1],
      );
      expect(progress[progress.length - 2].phase, AsrSubtitlePhase.finalizing);
      expect(progress.last.phase, AsrSubtitlePhase.completed);
      expect(progress.last.value, 1);
    },
  );

  test(
    'missing translation settings keep the generated English subtitles',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'asr-job-bilingual-config-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File video = File('${root.path}/lesson.mp4')
        ..writeAsStringSync('v');
      final File chunk = File('${root.path}/chunk.m4a')..writeAsStringSync('a');
      final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
        supportDirectory: () async => root,
        cache: AsrSubtitleCache(appSupportDirectory: () async => root),
        service: AsrSubtitleService(
          prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
            AsrAudioChunk(file: chunk, offsetMs: 0),
          ],
        ),
        cloudTranscribeChunk:
            ({
              required AsrAudioChunk chunk,
              required LearningSettingsState settings,
            }) async => _chunkJson('Hello there', 1000),
      );

      final String raw = await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: LearningSettingsState.defaults().copyWith(
          generateBilingualAsrSubtitles: true,
        ),
      );

      expect(parseSubtitleLines(raw).single.english, 'Hello there');
      expect(subtitleGenerationWarning(raw), contains('填写 API Key'));
    },
  );

  test('bilingual translation resumes from sentence checkpoint', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-translation-resume-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk = File('${root.path}/chunk.m4a')
      ..writeAsStringSync('audio');
    final Map<String, int> calls = <String, int>{};
    final List<AsrSubtitleProgress> resumedProgress = <AsrSubtitleProgress>[];
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async => _twoLineChunkJson(),
      translateSentence:
          ({
            required String sentence,
            required LearningSettingsState settings,
          }) async {
            calls.update(sentence, (int count) => count + 1, ifAbsent: () => 1);
            if (sentence == 'second line' && calls[sentence] == 1) return null;
            return '翻译：$sentence';
          },
    );
    final LearningSettingsState settings = _settings().copyWith(
      generateBilingualAsrSubtitles: true,
    );

    final String partialRaw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: settings,
    );
    expect(subtitleGenerationWarning(partialRaw), isNotNull);
    expect(
      parseSubtitleLines(
        partialRaw,
      ).map((PlayerSubtitleLine line) => line.chinese),
      <String>['翻译：first line', ''],
    );
    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: settings,
      onProgress: resumedProgress.add,
    );

    expect(calls['first line'], 1);
    expect(calls['second line'], 2);
    expect(
      parseSubtitleLines(raw).map((PlayerSubtitleLine line) => line.chinese),
      <String>['翻译：first line', '翻译：second line'],
    );
    expect(subtitleGenerationWarning(raw), isNull);
    expect(
      resumedProgress
          .where(
            (AsrSubtitleProgress value) =>
                value.phase == AsrSubtitlePhase.translating,
          )
          .map((AsrSubtitleProgress value) => value.completedTranslations),
      <int>[0, 1, 2],
    );
  });

  test('resume skips completed chunk files', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-resume-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk0 = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final File chunk1 = File('${root.path}/chunk1.m4a')..writeAsStringSync('1');
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk0, offsetMs: 0),
          AsrAudioChunk(file: chunk1, offsetMs: 300000),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async {
            return _chunkJson('chunk 1', chunk.offsetMs + 1000);
          },
    );
    final Directory jobDir = await runner.jobDirectory(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );
    await File('${jobDir.path}/chunks/00000.json')
        .create(recursive: true)
        .then((File file) => file.writeAsString(_rawChunk('chunk 0', 1000)));

    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(raw);
    expect(lines.map((PlayerSubtitleLine line) => line.english), <String>[
      'chunk 0',
      'chunk 1',
    ]);
  });

  test('empty chunks do not prevent other subtitles from completing', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-empty-chunk-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk0 = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final File chunk1 = File('${root.path}/chunk1.m4a')..writeAsStringSync('1');
    int calls = 0;
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk0, offsetMs: 0),
          AsrAudioChunk(file: chunk1, offsetMs: 58000),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async {
            calls += 1;
            return calls == 1
                ? <String, Object?>{
                    'version': 1,
                    'language': 'en',
                    'lines': const <Object?>[],
                  }
                : _chunkJson('recognized line', 59000);
          },
    );

    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );

    expect(calls, 2);
    expect(parseSubtitleLines(raw).single.english, 'recognized line');
  });

  test(
    'failed job does not write final cache until all chunks complete',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'asr-job-fail-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File video = File('${root.path}/lesson.mp4')
        ..writeAsStringSync('video');
      final File chunk0 = File('${root.path}/chunk0.m4a')
        ..writeAsStringSync('0');
      final File chunk1 = File('${root.path}/chunk1.m4a')
        ..writeAsStringSync('1');
      int calls = 0;
      final AsrSubtitleCache cache = AsrSubtitleCache(
        appSupportDirectory: () async => root,
      );
      final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
        supportDirectory: () async => root,
        cache: cache,
        service: AsrSubtitleService(
          prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
            AsrAudioChunk(file: chunk0, offsetMs: 0),
            AsrAudioChunk(file: chunk1, offsetMs: 300000),
          ],
        ),
        cloudTranscribeChunk:
            ({
              required AsrAudioChunk chunk,
              required LearningSettingsState settings,
            }) async {
              calls += 1;
              if (chunk.offsetMs == 300000) {
                throw StateError('asr failed');
              }
              return _chunkJson('chunk 0', 1000);
            },
      );

      await expectLater(
        runner.run(
          episodeId: 'episode-1',
          videoPath: video.path,
          settings: _settings(),
        ),
        throwsA(isA<StateError>()),
      );

      expect(calls, 3);

      expect(
        await cache.exists(episodeId: 'episode-1', videoPath: video.path),
        isFalse,
      );
    },
  );

  test('completed job writes final words json cache', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-complete-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk0 = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: cache,
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk0, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async {
            return _chunkJson('done', 1000);
          },
    );

    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );

    expect(
      await cache.read(episodeId: 'episode-1', videoPath: video.path),
      raw,
    );
    expect(parseSubtitleLines(raw).single.english, 'done');
    final Directory jobDir = await runner.jobDirectory(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );
    final Map<String, dynamic> report =
        jsonDecode(
              await File(
                '${jobDir.path}/subtitle_quality_report.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(report['finalStatus'], 'PASS');
    expect(report['chunks'], hasLength(1));
  });

  test('overlapping final subtitle is repaired and cached', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-invalid-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk0 = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    int calls = 0;
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: cache,
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk0, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async {
            calls += 1;
            return _overlappingChunkJson();
          },
    );

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(
      await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
      ),
    );
    expect(lines, hasLength(2));
    expect(lines.last.startMs, lines.first.endMs);
    expect(
      await cache.exists(episodeId: 'episode-1', videoPath: video.path),
      isTrue,
    );
    expect(calls, 1);
    final Directory jobDir = await runner.jobDirectory(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );
    final Map<String, dynamic> report =
        jsonDecode(
              await File(
                '${jobDir.path}/subtitle_quality_report.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(report['finalStatus'], 'PASS');
    expect(report['repairCount'], greaterThan(0));
    expect(report['sentenceOverlap'], greaterThan(0));
    final Map<String, dynamic> anomaly =
        (report['anomalies'] as List<dynamic>).first as Map<String, dynamic>;
    expect(anomaly, containsPair('provider', _settings().asrProvider));
    expect(anomaly, containsPair('sourceChunk', 0));
    final AsrSubtitleRepairSummary repairSummary = await runner
        .readRepairSummary(
          episodeId: 'episode-1',
          videoPath: video.path,
          settings: _settings(),
        );
    expect(repairSummary.itemCount, greaterThan(0));
    expect(repairSummary.appendTo('AI 字幕已生成'), contains('已自动修复'));
  });

  test('merge sorts, deduplicates, and repairs small overlaps', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-normalize-timeline-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async => <String, Object?>{
            'version': 1,
            'language': 'en',
            'lines': <Map<String, Object?>>[
              _chunkLine('second line', 1740),
              _chunkLine('first line', 1000),
              _chunkLine('first line', 1050),
            ],
          },
    );

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(
      await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
      ),
    );

    expect(lines.map((PlayerSubtitleLine line) => line.english), <String>[
      'first line',
      'second line',
    ]);
    expect(lines.map((PlayerSubtitleLine line) => line.startMs), <int>[
      1000,
      2000,
    ]);
  });

  test(
    'merge trims a previous chunk word that overruns the next chunk',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'asr-job-chunk-overrun-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File video = File('${root.path}/lesson.mp4')
        ..writeAsStringSync('video');
      final File chunk0 = File('${root.path}/chunk0.m4a')
        ..writeAsStringSync('0');
      final File chunk1 = File('${root.path}/chunk1.m4a')
        ..writeAsStringSync('1');
      final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
        supportDirectory: () async => root,
        cache: AsrSubtitleCache(appSupportDirectory: () async => root),
        service: AsrSubtitleService(
          prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
            AsrAudioChunk(file: chunk0, offsetMs: 0),
            AsrAudioChunk(file: chunk1, offsetMs: 290000),
          ],
        ),
        cloudTranscribeChunk:
            ({
              required AsrAudioChunk chunk,
              required LearningSettingsState settings,
            }) async => chunk.file.path == chunk0.path
            ? <String, Object?>{
                'version': 1,
                'language': 'en',
                'lines': <Map<String, Object?>>[
                  <String, Object?>{
                    'startMs': 273068,
                    'endMs': 294108,
                    'english': 'Ha ha',
                    'chinese': '',
                    'words': <Map<String, Object?>>[
                      <String, Object?>{
                        'text': 'Ha',
                        'startMs': 273068,
                        'endMs': 273488,
                      },
                      <String, Object?>{
                        'text': 'ha',
                        'startMs': 278508,
                        'endMs': 294108,
                      },
                    ],
                  },
                ],
              }
            : <String, Object?>{
                'version': 1,
                'language': 'en',
                'lines': <Map<String, Object?>>[
                  _chunkLine('Peppa Pig', 291000),
                ],
              },
      );

      final List<PlayerSubtitleLine> lines = parseSubtitleLines(
        await runner.run(
          episodeId: 'episode-1',
          videoPath: video.path,
          settings: _settings(),
        ),
      );

      expect(lines.map((PlayerSubtitleLine line) => line.english), <String>[
        'Ha ha',
        'Peppa Pig',
      ]);
      expect(lines.first.endMs, 290000);
      expect(lines.first.words.last.endMs, 290000);
      expect(lines.last.startMs, 291000);
    },
  );

  test('invalid chunk is retried once before finishing the job', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-retry-invalid-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    int calls = 0;
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async {
            calls += 1;
            return calls == 1
                ? _chunkJsonWithoutWords('', 1000)
                : _chunkJson('retried subtitle', 1000);
          },
    );

    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );

    expect(calls, 2);
    expect(parseSubtitleLines(raw).single.english, 'retried subtitle');
  });

  test('missing word timestamps are synthesized from usable text', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-no-words-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk0 = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: cache,
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk0, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async {
            return _chunkJsonWithoutWords('no words', 1000);
          },
    );

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(
      await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
      ),
    );
    expect(lines.single.english, 'no words');
    expect(
      lines.single.words.map((PlayerSubtitleWord word) => word.text),
      <String>['no', 'words'],
    );
    expect(
      await cache.exists(episodeId: 'episode-1', videoPath: video.path),
      isTrue,
    );
  });

  test('fully out-of-range timestamps are rebuilt inside the chunk', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-out-of-range-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async => _chunkJson('outside range', 70000),
    );

    final PlayerSubtitleLine line = parseSubtitleLines(
      await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
      ),
    ).single;

    expect(line.english, 'outside range');
    expect(line.startMs, 0);
    expect(line.endMs, lessThanOrEqualTo(58000));
    expect(line.words, hasLength(2));
  });

  test('valid short word timestamp is preserved', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-short-word-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async {
            final Map<String, Object?> result = _chunkJson('I agree', 1000);
            final Map<String, Object?> line =
                (result['lines']! as List<Map<String, Object?>>).single;
            final List<Map<String, Object?>> words =
                line['words']! as List<Map<String, Object?>>;
            words.first['endMs'] = 1020;
            words.last['startMs'] = 1020;
            return result;
          },
    );

    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );

    expect(
      parseSubtitleLines(
        raw,
      ).single.words.map((PlayerSubtitleWord word) => word.text),
      <String>['I', 'agree'],
    );
  });

  test('large word overlap is repaired locally', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-word-overlap-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async => <String, Object?>{
            'version': 1,
            'language': 'en',
            'lines': <Map<String, Object?>>[
              <String, Object?>{
                'startMs': 1000,
                'endMs': 2200,
                'english': 'one two',
                'chinese': '',
                'words': const <Map<String, Object?>>[
                  <String, Object?>{
                    'text': 'one',
                    'startMs': 1000,
                    'endMs': 2000,
                  },
                  <String, Object?>{
                    'text': 'two',
                    'startMs': 1200,
                    'endMs': 2200,
                  },
                ],
              },
            ],
          },
    );

    final PlayerSubtitleLine line = parseSubtitleLines(
      await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
      ),
    ).single;
    expect(line.words.first.endMs, line.words.last.startMs);
  });

  test('cancellation stops before the next cloud chunk', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-cancel-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk0 = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final File chunk1 = File('${root.path}/chunk1.m4a')..writeAsStringSync('1');
    final AsrSubtitleCancellationToken cancellationToken =
        AsrSubtitleCancellationToken();
    int calls = 0;
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk0, offsetMs: 0),
          AsrAudioChunk(file: chunk1, offsetMs: 58000),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async {
            calls += 1;
            return _chunkJson('chunk', chunk.offsetMs + 1000);
          },
    );

    await expectLater(
      runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
        cancellationToken: cancellationToken,
        onProgress: (AsrSubtitleProgress progress) {
          if (progress.completedChunks == 1) cancellationToken.cancel();
        },
      ),
      throwsA(isA<AsrSubtitleGenerationException>()),
    );
    expect(calls, 1);
  });

  test('same video cannot start two generation jobs', () async {
    final Directory root = Directory.systemTemp.createTempSync('asr-job-lock-');
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final Completer<void> started = Completer<void>();
    final Completer<void> release = Completer<void>();
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async {
            if (!started.isCompleted) started.complete();
            await release.future;
            return _chunkJson('locked', 1000);
          },
    );

    final Future<String> first = runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );
    await started.future;
    await expectLater(
      runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
      ),
      throwsA(
        isA<AsrSubtitleGenerationException>().having(
          (AsrSubtitleGenerationException error) => error.message,
          'message',
          contains('正在生成'),
        ),
      ),
    );
    release.complete();
    await first;
  });

  test('force regeneration ignores completed chunk checkpoints', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-force-regenerate-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    int calls = 0;
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async {
            calls += 1;
            return _chunkJson('generation $calls', 1000);
          },
    );

    await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );
    await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
      forceRegenerate: true,
    );

    expect(calls, 2);
  });

  test('failed force regeneration keeps the previous final cache', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-force-failure-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    final LearningSettingsState settings = _settings();
    final String previous = _rawChunk('old subtitle', 1000);
    await cache.write(
      episodeId: 'episode-1',
      videoPath: video.path,
      content: previous,
      settings: settings,
    );
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: cache,
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async => _chunkJsonWithoutWords('', 1000),
    );

    await expectLater(
      runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: settings,
        forceRegenerate: true,
      ),
      throwsA(anything),
    );

    expect(
      await cache.read(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: settings,
      ),
      previous,
    );
  });

  test('temporary audio chunks are cleaned after generation', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-temp-cleanup-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final Directory chunkDir = Directory('${root.path}/cle_asr_test')
      ..createSync();
    final File chunk = File('${chunkDir.path}/chunk0.m4a')
      ..writeAsStringSync('0');
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async => _chunkJson('cleaned', 1000),
    );

    await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );

    expect(chunkDir.existsSync(), isFalse);
  });

  test('progress follows recognized video timestamp', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-progress-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk0 = File('${root.path}/chunk0.wav')..writeAsStringSync('0');
    final File chunk1 = File('${root.path}/chunk1.wav')..writeAsStringSync('1');
    final List<AsrSubtitleProgress> progress = <AsrSubtitleProgress>[];
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk0, offsetMs: 0),
          AsrAudioChunk(file: chunk1, offsetMs: 60000),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async {
            return _chunkJson('chunk', chunk.offsetMs + 30000);
          },
    );

    await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
      onProgress: progress.add,
    );

    final AsrSubtitleProgress recognized = progress.lastWhere(
      (AsrSubtitleProgress value) =>
          value.phase == AsrSubtitlePhase.recognizing,
    );
    expect(recognized.label, '已识别到 1:31 / 2:00');
    expect(recognized.value, closeTo(91000 / 120000, 0.001));
    expect(recognized.previewText, 'chunk');
    expect(progress.last.label, '字幕生成完成');
  });

  test(
    'regenerates only the selected line and persists the replacement',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'asr-job-regenerate-line-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File video = File('${root.path}/lesson.mp4')
        ..writeAsStringSync('v');
      final File chunk = File('${root.path}/chunk.m4a')..writeAsStringSync('a');
      final AsrSubtitleCache cache = AsrSubtitleCache(
        appSupportDirectory: () async => root,
      );
      const List<PlayerSubtitleLine> original = <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Keep this line.',
          chinese: '保留这一句。',
          startMs: 1000,
          endMs: 2000,
        ),
        PlayerSubtitleLine(
          startTime: '00:03',
          english: 'Wrong sentence.',
          chinese: '错误的句子。',
          startMs: 3000,
          endMs: 4500,
        ),
      ];
      final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
        supportDirectory: () async => root,
        cache: cache,
        service: AsrSubtitleService(
          prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
            AsrAudioChunk(file: chunk, offsetMs: 0),
          ],
        ),
        cloudTranscribeChunk:
            ({
              required AsrAudioChunk chunk,
              required LearningSettingsState settings,
            }) async => _chunkJson('Correct sentence.', 3200),
      );

      final AsrRegeneratedLineResult result = await runner.regenerateLine(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
        currentLines: original,
        lineIndex: 1,
      );

      expect(result.line.english, 'Correct sentence.');
      expect(result.line.startMs, 3000);
      expect(result.line.endMs, 4500);
      expect(result.line.words, hasLength(2));
      final String cached = (await cache.read(
        episodeId: 'episode-1',
        videoPath: video.path,
      ))!;
      final List<PlayerSubtitleLine> cachedLines = parseSubtitleLines(cached);
      expect(cachedLines.first.english, 'Keep this line.');
      expect(cachedLines.last.english, 'Correct sentence.');
    },
  );

  test('keeps the cached sentence when line regeneration fails', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-regenerate-line-failure-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')..writeAsStringSync('v');
    final File chunk = File('${root.path}/chunk.m4a')..writeAsStringSync('a');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    const String cachedBefore =
        '{"version":1,"lines":[{"startMs":3000,"endMs":4500,'
        '"english":"Original sentence.","chinese":"原句。","words":[]}]}';
    await cache.write(
      episodeId: 'episode-1',
      videoPath: video.path,
      content: cachedBefore,
    );
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: cache,
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async => throw StateError('provider-down'),
    );

    await expectLater(
      runner.regenerateLine(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
        currentLines: const <PlayerSubtitleLine>[
          PlayerSubtitleLine(
            startTime: '00:03',
            english: 'Original sentence.',
            chinese: '原句。',
            startMs: 3000,
            endMs: 4500,
          ),
        ],
        lineIndex: 0,
      ),
      throwsA(isA<AsrSubtitleGenerationException>()),
    );
    expect(
      await cache.read(episodeId: 'episode-1', videoPath: video.path),
      cachedBefore,
    );
  });
}

LearningSettingsState _settings() {
  return LearningSettingsState.defaults().copyWith(
    asrApiKey: 'demo-key',
    asrBaseUrl: 'https://api.example.com/v1',
    asrModel: 'whisper-1',
    generateBilingualAsrSubtitles: false,
  );
}

Map<String, Object?> _chunkJson(String english, int startMs) {
  final List<String> words = english
      .split(RegExp(r'\s+'))
      .where((String word) => word.isNotEmpty)
      .toList(growable: false);
  final int wordMs = (1000 / words.length).round();
  return <String, Object?>{
    'version': 1,
    'language': 'en',
    'lines': <Map<String, Object?>>[
      <String, Object?>{
        'startMs': startMs,
        'endMs': startMs + 1000,
        'english': english,
        'chinese': '',
        'words': words
            .asMap()
            .entries
            .map((MapEntry<int, String> entry) {
              final int wordStartMs = startMs + entry.key * wordMs;
              return <String, Object?>{
                'text': entry.value,
                'startMs': wordStartMs,
                'endMs': entry.key == words.length - 1
                    ? startMs + 1000
                    : wordStartMs + wordMs,
              };
            })
            .toList(growable: false),
      },
    ],
  };
}

Map<String, Object?> _chunkJsonWithoutWords(String english, int startMs) {
  return <String, Object?>{
    'version': 1,
    'language': 'en',
    'lines': <Map<String, Object?>>[
      <String, Object?>{
        'startMs': startMs,
        'endMs': startMs + 1000,
        'english': english,
        'chinese': '',
        'words': const <Object?>[],
      },
    ],
  };
}

Map<String, Object?> _twoLineChunkJson() {
  return <String, Object?>{
    'version': 1,
    'language': 'en',
    'lines': <Map<String, Object?>>[
      _chunkLine('first line', 1000),
      _chunkLine('second line', 2000),
    ],
  };
}

Map<String, Object?> _chunkLine(String english, int startMs) {
  return (_chunkJson(english, startMs)['lines']! as List<Map<String, Object?>>)
      .single;
}

Map<String, Object?> _overlappingChunkJson() {
  return <String, Object?>{
    'version': 1,
    'language': 'en',
    'lines': <Map<String, Object?>>[
      <String, Object?>{
        'startMs': 1000,
        'endMs': 3000,
        'english': 'first line',
        'chinese': '',
        'words': const <Map<String, Object?>>[
          <String, Object?>{'text': 'first', 'startMs': 1000, 'endMs': 2000},
          <String, Object?>{'text': 'line', 'startMs': 2000, 'endMs': 3000},
        ],
      },
      <String, Object?>{
        'startMs': 2000,
        'endMs': 4000,
        'english': 'second line',
        'chinese': '',
        'words': const <Map<String, Object?>>[
          <String, Object?>{'text': 'second', 'startMs': 2000, 'endMs': 3000},
          <String, Object?>{'text': 'line', 'startMs': 3000, 'endMs': 4000},
        ],
      },
    ],
  };
}

String _rawChunk(String english, int startMs) {
  return const JsonEncoder().convert(_chunkJson(english, startMs));
}
