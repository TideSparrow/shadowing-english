import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../settings/presentation/settings_provider.dart';
import '../../shared/data/word_lookup_service.dart';
import 'asr_subtitle_cache.dart';
import 'asr_subtitle_service.dart';
import 'player_mock_state.dart';
import 'player_subtitle_loader.dart';
import 'subtitle_word_alignment.dart';

typedef AsrChunkTranscriber =
    Future<Map<String, Object?>> Function({
      required AsrAudioChunk chunk,
      required LearningSettingsState settings,
    });
typedef AsrSentenceTranslator =
    Future<String?> Function({
      required String sentence,
      required LearningSettingsState settings,
    });

typedef AsrBatchTranslator =
    Future<List<String>> Function({
      required List<String> sentences,
      required LearningSettingsState settings,
    });

class AsrSubtitleGenerationException implements Exception {
  const AsrSubtitleGenerationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AsrSubtitleCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) {
      throw const AsrSubtitleGenerationException('AI 字幕生成已取消。');
    }
  }
}

class AsrSubtitleRepairSummary {
  const AsrSubtitleRepairSummary(this.itemCount);

  final int itemCount;

  String appendTo(String message) =>
      itemCount > 0 ? '$message，已自动修复 $itemCount 项时间轴数据' : message;
}

class AsrRegeneratedLineResult {
  const AsrRegeneratedLineResult({required this.line, required this.raw});

  final PlayerSubtitleLine line;
  final String raw;
}

String subtitleReferenceSignature(List<PlayerSubtitleLine> lines) {
  final List<PlayerSubtitleLine> usableLines = usableReferenceSubtitles(lines);
  if (usableLines.isEmpty) return '';
  final String value = usableLines
      .map(
        (PlayerSubtitleLine line) =>
            '${line.startMs}|${line.endMs}|${line.english}|${line.chinese}',
      )
      .join('\n');
  return sha1.convert(utf8.encode(value)).toString();
}

String? subtitleGenerationWarning(String raw) {
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final List<String> warnings = <String>[
      for (final String key in <String>['timingWarning', 'translationWarning'])
        if ((decoded[key] as String? ?? '').trim().isNotEmpty)
          (decoded[key] as String).trim(),
    ];
    return warnings.isEmpty ? null : warnings.join('；');
  } catch (_) {
    return null;
  }
}

class _SubtitleQualityReport {
  _SubtitleQualityReport(this.provider);

  final String provider;
  final List<Map<String, Object?>> anomalies = <Map<String, Object?>>[];
  final List<Map<String, Object?>> chunks = <Map<String, Object?>>[];
  int wordOverlap = 0;
  int sentenceOverlap = 0;
  int chunkBoundaryOverlap = 0;
  int wordFix = 0;
  int wordDeleted = 0;
  int chunkBoundaryFix = 0;
  int repairCount = 0;
  bool usedReferenceFallback = false;

  void addOverlap({
    required String kind,
    required String previousText,
    required int previousStart,
    required int previousEnd,
    required String currentText,
    required int currentStart,
    required int currentEnd,
    required int overlapMs,
    required int sourceChunk,
    required int previousSourceChunk,
  }) {
    if (kind == 'word') {
      wordOverlap += 1;
    } else if (kind == 'sentence') {
      sentenceOverlap += 1;
      if (sourceChunk != previousSourceChunk) {
        chunkBoundaryOverlap += 1;
      }
    } else if (kind == 'chunkBoundary') {
      chunkBoundaryOverlap += 1;
    }
    anomalies.add(<String, Object?>{
      'kind': kind,
      'previousText': previousText,
      'previousStart': previousStart,
      'previousEnd': previousEnd,
      'currentText': currentText,
      'currentStart': currentStart,
      'currentEnd': currentEnd,
      'overlapMs': overlapMs,
      'sourceChunk': sourceChunk,
      'previousSourceChunk': previousSourceChunk,
      'provider': provider,
    });
  }

  void addChunk({
    required int sourceChunk,
    required int startOffsetMs,
    required int endOffsetMs,
    required List<Map<String, Object?>> lines,
  }) {
    final List<Map<String, Object?>> words = lines
        .expand(
          (Map<String, Object?> line) =>
              (line['words'] as List<dynamic>? ?? const <dynamic>[])
                  .whereType<Map<String, dynamic>>()
                  .map(Map<String, Object?>.from),
        )
        .toList(growable: false);
    chunks.add(<String, Object?>{
      'sourceChunk': sourceChunk,
      'startOffsetMs': startOffsetMs,
      'endOffsetMs': endOffsetMs,
      'firstWord': words.isEmpty ? '' : words.first['text'],
      'actualStart': words.isEmpty ? null : words.first['startMs'],
      'lastWord': words.isEmpty ? '' : words.last['text'],
      'actualEnd': words.isEmpty ? null : words.last['endMs'],
    });
  }

  Future<void> write(Directory jobDir, String finalStatus) {
    return File(
      '${jobDir.path}${Platform.pathSeparator}subtitle_quality_report.json',
    ).writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'provider': provider,
        'wordOverlap': wordOverlap,
        'sentenceOverlap': sentenceOverlap,
        'chunkBoundaryOverlap': chunkBoundaryOverlap,
        'wordFix': wordFix,
        'wordDeleted': wordDeleted,
        'chunkBoundaryFix': chunkBoundaryFix,
        'repairCount': repairCount,
        'usedReferenceFallback': usedReferenceFallback,
        'chunks': chunks,
        'anomalies': anomalies,
        'finalStatus': finalStatus,
      }),
    );
  }
}

class AsrSubtitleJobRunner {
  const AsrSubtitleJobRunner({
    this.supportDirectory,
    this.cache = const AsrSubtitleCache(),
    this.service = const AsrSubtitleService(),
    this.cloudTranscribeChunk,
    this.translateSentence,
    this.translateSentences,
  });

  final Future<Directory> Function()? supportDirectory;
  final AsrSubtitleCache cache;
  final AsrSubtitleService service;
  final AsrChunkTranscriber? cloudTranscribeChunk;
  final AsrSentenceTranslator? translateSentence;
  final AsrBatchTranslator? translateSentences;

  static const int _translationBatchLines = 40;
  static const int _translationBatchCharacters = 6000;

  static const int _repairableOverlapMs = 500;
  static final Set<String> _activeJobs = <String>{};

  Future<AsrRegeneratedLineResult> regenerateLine({
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
    required List<PlayerSubtitleLine> currentLines,
    required int lineIndex,
    String? referenceSignature,
  }) async {
    if (lineIndex < 0 || lineIndex >= currentLines.length) {
      throw const AsrSubtitleGenerationException('当前句不存在，无法重新生成。');
    }
    final File video = File(videoPath);
    if (!video.existsSync()) {
      throw const AsrSubtitleGenerationException('当前视频不可用，无法重新生成这句话。');
    }
    final String jobKey = _jobKey(
      episodeId: episodeId,
      videoPath: videoPath,
      settings: settings,
    );
    if (!_activeJobs.add(jobKey)) {
      throw const AsrSubtitleGenerationException('这个视频的 AI 字幕正在生成，请等待当前任务完成。');
    }

    List<AsrAudioChunk> chunks = const <AsrAudioChunk>[];
    try {
      chunks = await service.prepareAudioChunks(video);
      if (chunks.isEmpty) {
        throw const AsrSubtitleGenerationException('没有提取到可识别的音频，原句已保留。');
      }
      final PlayerSubtitleLine currentLine = currentLines[lineIndex];
      final List<Map<String, Object?>> recognizedLines =
          <Map<String, Object?>>[];
      final _SubtitleQualityReport report = _SubtitleQualityReport(
        settings.asrProvider,
      );

      for (int index = 0; index < chunks.length; index += 1) {
        final int chunkEndMs = index + 1 < chunks.length
            ? chunks[index + 1].offsetMs
            : chunks[index].offsetMs + 58000;
        if (chunks[index].offsetMs >= currentLine.endMs ||
            chunkEndMs <= currentLine.startMs) {
          continue;
        }
        Map<String, Object?>? normalized;
        Object? lastError;
        for (int attempt = 0; attempt < 2; attempt += 1) {
          try {
            final Map<String, Object?> response =
                await _transcribe(
                  chunk: chunks[index],
                  settings: settings,
                ).timeout(
                  const Duration(minutes: 20),
                  onTimeout: () =>
                      throw TimeoutException('AI 重新识别当前句超时，请稍后重试。'),
                );
            normalized = _normalizeChunkTimeline(
              response,
              chunkStartMs: chunks[index].offsetMs,
              chunkEndMs: chunkEndMs,
              sourceChunk: index,
              report: report,
            );
            break;
          } catch (error) {
            lastError = error;
          }
        }
        if (normalized == null) {
          throw AsrSubtitleGenerationException(
            '当前句重新识别失败，原句已保留：${_errorMessage(lastError ?? 'unknown-error')}',
          );
        }
        recognizedLines.addAll(
          (normalized['lines'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(Map<String, Object?>.from),
        );
      }

      final List<PlayerSubtitleWord> words = _wordsForCurrentLine(
        recognizedLines,
        currentLine,
      );
      if (words.isEmpty) {
        throw const AsrSubtitleGenerationException(
          'AI 没有在当前句时间范围内识别到有效英文，原句已保留。',
        );
      }
      final String english = words
          .map((PlayerSubtitleWord word) => word.text)
          .join(' ')
          .trim();
      if (english.isEmpty) {
        throw const AsrSubtitleGenerationException('AI 返回了空字幕，原句已保留。');
      }
      final String chinese = await _translateRegeneratedLine(
        english: english,
        settings: settings,
      );
      final PlayerSubtitleLine regenerated = PlayerSubtitleLine(
        startTime: currentLine.startTime,
        english: english,
        chinese: chinese,
        startMs: currentLine.startMs,
        endMs: currentLine.endMs,
        words: words,
      );
      _validateFinalResult(
        jsonEncode(<String, Object?>{
          'version': 1,
          'lines': <Object?>[_lineToJson(regenerated)],
        }),
      );

      final String? cached = await cache.read(
        episodeId: episodeId,
        videoPath: videoPath,
      );
      final Map<String, dynamic> decoded = cached == null
          ? <String, dynamic>{'version': 1, 'language': 'en'}
          : Map<String, dynamic>.from(
              jsonDecode(cached) as Map<String, dynamic>,
            );
      final List<PlayerSubtitleLine> updatedLines = List<PlayerSubtitleLine>.of(
        currentLines,
      )..[lineIndex] = regenerated;
      decoded['lines'] = updatedLines.map(_lineToJson).toList(growable: false);
      final String raw = const JsonEncoder.withIndent('  ').convert(decoded);
      await cache.write(
        episodeId: episodeId,
        videoPath: videoPath,
        content: raw,
        settings: settings,
        referenceSignature: referenceSignature,
      );
      return AsrRegeneratedLineResult(line: regenerated, raw: raw);
    } finally {
      service.deleteTemporaryAudioChunks(chunks);
      _activeJobs.remove(jobKey);
    }
  }

  Future<String> run({
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
    List<PlayerSubtitleLine> referenceSubtitleLines =
        const <PlayerSubtitleLine>[],
    String? referenceSignatureOverride,
    bool forceRegenerate = false,
    AsrProgressCallback? onProgress,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    final File video = File(videoPath);
    if (!video.existsSync()) {
      throw StateError('missing-video-file');
    }
    final List<PlayerSubtitleLine> usableReferenceLines =
        usableReferenceSubtitles(referenceSubtitleLines);

    final String jobKey = _jobKey(
      episodeId: episodeId,
      videoPath: videoPath,
      settings: settings,
    );
    if (!_activeJobs.add(jobKey)) {
      throw const AsrSubtitleGenerationException('这个视频的 AI 字幕正在生成，请等待当前任务完成。');
    }
    List<AsrAudioChunk> chunks = const <AsrAudioChunk>[];
    try {
      cancellationToken?.throwIfCancelled();
      if (forceRegenerate) {
        final Directory previousJob = await jobDirectory(
          episodeId: episodeId,
          videoPath: videoPath,
          settings: settings,
        );
        if (previousJob.existsSync()) {
          await previousJob.delete(recursive: true);
        }
      }
      try {
        chunks = await service.prepareAudioChunks(video);
      } catch (_) {
        cancellationToken?.throwIfCancelled();
        if (usableReferenceLines.isEmpty) rethrow;
      }
      cancellationToken?.throwIfCancelled();
      return await _runPrepared(
        episodeId: episodeId,
        videoPath: videoPath,
        settings: settings,
        chunks: chunks,
        referenceSubtitleLines: usableReferenceLines,
        referenceSignature: referenceSignatureOverride?.isNotEmpty ?? false
            ? referenceSignatureOverride!
            : subtitleReferenceSignature(usableReferenceLines),
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
    } finally {
      service.deleteTemporaryAudioChunks(chunks);
      _activeJobs.remove(jobKey);
    }
  }

  Future<String> _runPrepared({
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
    required List<AsrAudioChunk> chunks,
    required List<PlayerSubtitleLine> referenceSubtitleLines,
    required String referenceSignature,
    AsrProgressCallback? onProgress,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    final Directory jobDir = await jobDirectory(
      episodeId: episodeId,
      videoPath: videoPath,
      settings: settings,
    );
    final Directory chunksDir = Directory(
      '${jobDir.path}${Platform.pathSeparator}chunks',
    );
    await chunksDir.create(recursive: true);
    final _SubtitleQualityReport report = _SubtitleQualityReport(
      settings.asrProvider,
    );

    final int totalMs = _estimatedTotalMs(chunks);
    await _writeJob(
      jobDir: jobDir,
      episodeId: episodeId,
      videoPath: videoPath,
      settings: settings,
      totalChunks: chunks.length,
      status: 'running',
      error: '',
    );
    int completed = 0;
    onProgress?.call(
      AsrSubtitleProgress(
        completedChunks: completed,
        totalChunks: chunks.length,
        currentMs: 0,
        totalMs: totalMs,
      ),
    );

    try {
      for (int index = 0; index < chunks.length; index += 1) {
        cancellationToken?.throwIfCancelled();
        final File chunkFile = File(
          '${chunksDir.path}${Platform.pathSeparator}${index.toString().padLeft(5, '0')}.json',
        );
        await _loadOrTranscribeValidChunk(
          chunkFile: chunkFile,
          chunk: chunks[index],
          chunkEndMs: index + 1 < chunks.length
              ? chunks[index + 1].offsetMs
              : chunks[index].offsetMs + 58000,
          settings: settings,
          sourceChunk: index,
          report: report,
          allowReferenceFallback: referenceSubtitleLines.isNotEmpty,
          cancellationToken: cancellationToken,
        );
        final Object? decoded = jsonDecode(await chunkFile.readAsString());
        final List<Map<String, Object?>> chunkLines =
            decoded is Map<String, dynamic>
            ? (decoded['lines'] as List<dynamic>? ?? const <dynamic>[])
                  .whereType<Map<String, dynamic>>()
                  .map(Map<String, Object?>.from)
                  .toList(growable: false)
            : const <Map<String, Object?>>[];
        report.addChunk(
          sourceChunk: index,
          startOffsetMs: chunks[index].offsetMs,
          endOffsetMs: index + 1 < chunks.length
              ? chunks[index + 1].offsetMs
              : chunks[index].offsetMs + 58000,
          lines: chunkLines,
        );
        completed += 1;
        onProgress?.call(
          AsrSubtitleProgress(
            completedChunks: completed,
            totalChunks: chunks.length,
            currentMs: await _currentMs(chunkFile, chunks[index].offsetMs),
            totalMs: totalMs,
            previewText: await _previewText(chunkFile),
          ),
        );
      }
    } catch (error) {
      await report.write(jobDir, 'FAILED');
      await _writeJob(
        jobDir: jobDir,
        episodeId: episodeId,
        videoPath: videoPath,
        settings: settings,
        totalChunks: chunks.length,
        status: 'failed',
        error: error.toString(),
      );
      rethrow;
    }

    String raw = await _mergeChunks(chunksDir, chunks.length, report: report);
    if (referenceSubtitleLines.isNotEmpty) {
      final bool hasRecognizedWords = parseSubtitleLines(
        raw,
      ).any((PlayerSubtitleLine line) => line.words.isNotEmpty);
      raw = _calibrateWithReference(raw, referenceSubtitleLines);
      if (report.usedReferenceFallback || !hasRecognizedWords) {
        raw = _addTimingWarning(raw);
      }
    }
    late final String completedRaw;
    try {
      final String translatedRaw = await _addChineseTranslations(
        raw: raw,
        settings: settings,
        jobDir: jobDir,
        cancellationToken: cancellationToken,
        onProgress: (int completed, int total, String? previewText) {
          onProgress?.call(
            AsrSubtitleProgress(
              completedChunks: chunks.length,
              totalChunks: chunks.length,
              phase: AsrSubtitlePhase.translating,
              completedTranslations: completed,
              totalTranslations: total,
              previewText: previewText ?? '英文识别已完成，正在逐句补齐中文。',
            ),
          );
        },
      );
      onProgress?.call(
        AsrSubtitleProgress(
          completedChunks: chunks.length,
          totalChunks: chunks.length,
          phase: AsrSubtitlePhase.finalizing,
          previewText: '正在整理时间轴并保存结果。',
        ),
      );
      completedRaw = _repairFinalWordTimelines(translatedRaw, report: report);
    } catch (error) {
      await report.write(jobDir, 'FAILED');
      await _writeJob(
        jobDir: jobDir,
        episodeId: episodeId,
        videoPath: videoPath,
        settings: settings,
        totalChunks: chunks.length,
        status: 'failed',
        error: error.toString(),
      );
      rethrow;
    }
    final File part = File(
      '${jobDir.path}${Platform.pathSeparator}final.words.json.part',
    );
    await part.writeAsString(completedRaw);
    try {
      _validateFinalResult(
        completedRaw,
        allowLineOverlap: referenceSubtitleLines.isNotEmpty,
      );
    } catch (error) {
      await report.write(jobDir, 'FAILED');
      await chunksDir.delete(recursive: true);
      await _writeJob(
        jobDir: jobDir,
        episodeId: episodeId,
        videoPath: videoPath,
        settings: settings,
        totalChunks: chunks.length,
        status: 'failed',
        error: error.toString(),
      );
      rethrow;
    }
    await cache.write(
      episodeId: episodeId,
      videoPath: videoPath,
      content: completedRaw,
      settings: settings,
      referenceSignature: referenceSignature.isEmpty
          ? null
          : referenceSignature,
    );
    await _writeJob(
      jobDir: jobDir,
      episodeId: episodeId,
      videoPath: videoPath,
      settings: settings,
      totalChunks: chunks.length,
      status: 'completed',
      error: '',
    );
    await report.write(jobDir, 'PASS');
    onProgress?.call(
      AsrSubtitleProgress(
        completedChunks: chunks.length,
        totalChunks: chunks.length,
        phase: AsrSubtitlePhase.completed,
      ),
    );
    return completedRaw;
  }

  String _calibrateWithReference(
    String raw,
    List<PlayerSubtitleLine> referenceSubtitleLines,
  ) {
    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    final SubtitleWordAlignmentResult aligned = alignReferenceSubtitles(
      reference: referenceSubtitleLines,
      recognition: parseSubtitleLines(raw),
    );
    decoded['referenceLines'] = usableReferenceSubtitles(
      referenceSubtitleLines,
    ).map(_lineToJson).toList(growable: false);
    decoded['lines'] = aligned.lines
        .map(
          (PlayerSubtitleLine line) => <String, Object?>{
            'startMs': line.startMs,
            'endMs': line.endMs,
            'english': line.english,
            'chinese': line.chinese,
            'words': line.words
                .map(
                  (PlayerSubtitleWord word) => <String, Object?>{
                    'text': word.text,
                    'startMs': word.startMs,
                    'endMs': word.endMs,
                    if (word.confidence != null) 'confidence': word.confidence,
                  },
                )
                .toList(growable: false),
          },
        )
        .toList(growable: false);
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  String _addTimingWarning(String raw) {
    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    decoded['timingWarning'] = '已使用原字幕保证正文完整；部分单词时间为本地估算，联网后重新生成可提高逐词同步精度。';
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  Future<String> _addChineseTranslations({
    required String raw,
    required LearningSettingsState settings,
    required Directory jobDir,
    AsrSubtitleCancellationToken? cancellationToken,
    void Function(int completed, int total, String? previewText)? onProgress,
  }) async {
    if (!settings.generateBilingualAsrSubtitles) {
      return raw;
    }

    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    final List<dynamic> lines =
        decoded['lines'] as List<dynamic>? ?? const <dynamic>[];
    final bool needsTranslation = lines.whereType<Map<String, dynamic>>().any(
      (Map<String, dynamic> line) =>
          (line['chinese'] as String? ?? '').trim().isEmpty &&
          (line['english'] as String? ?? '').trim().isNotEmpty,
    );
    if (!needsTranslation) return raw;
    final String? configurationError = _bilingualConfigurationError(settings);
    if (configurationError != null) {
      decoded['translationWarning'] = configurationError;
      return const JsonEncoder.withIndent('  ').convert(decoded);
    }
    final File checkpoint = File(
      '${jobDir.path}${Platform.pathSeparator}translations.json',
    );
    final String signature = _translationSignature(settings);
    final Map<String, String> translations = await _loadTranslations(
      checkpoint,
      signature,
    );
    final List<Map<String, dynamic>> englishLines = lines
        .whereType<Map<String, dynamic>>()
        .where(
          (Map<String, dynamic> line) =>
              (line['english'] as String? ?? '').trim().isNotEmpty,
        )
        .toList(growable: false);
    int completed = englishLines
        .where(
          (Map<String, dynamic> line) =>
              (line['chinese'] as String? ?? '').trim().isNotEmpty,
        )
        .length;
    onProgress?.call(completed, englishLines.length, null);
    final List<Map<String, dynamic>> pending = <Map<String, dynamic>>[];
    for (final Map<String, dynamic> line in englishLines) {
      cancellationToken?.throwIfCancelled();
      if ((line['chinese'] as String? ?? '').trim().isNotEmpty) continue;
      final String english = (line['english'] as String).trim();
      final String? cached = translations[_translationLineKey(line, english)];
      if (cached != null && cached.trim().isNotEmpty) {
        line['chinese'] = cached;
        completed += 1;
        onProgress?.call(completed, englishLines.length, english);
      } else {
        pending.add(line);
      }
    }

    final bool useBatch =
        translateSentences != null ||
        (translateSentence == null &&
            _isAiTranslationProvider(settings.translationProvider));
    int offset = 0;
    while (offset < pending.length) {
      cancellationToken?.throwIfCancelled();
      int end = offset;
      int characters = 0;
      final int limit = useBatch ? _translationBatchLines : 1;
      while (end < pending.length && end - offset < limit) {
        final int length = (pending[end]['english'] as String).length;
        if (end > offset && characters + length > _translationBatchCharacters) {
          break;
        }
        characters += length;
        end += 1;
      }
      final List<Map<String, dynamic>> batch = pending.sublist(offset, end);
      final List<String> sentences = batch
          .map(
            (Map<String, dynamic> line) => (line['english'] as String).trim(),
          )
          .toList(growable: false);
      List<String> chinese;
      try {
        if (useBatch) {
          chinese =
              await (translateSentences ??
                      const WordLookupService().translateSentences)(
                    sentences: sentences,
                    settings: settings,
                  )
                  .timeout(const Duration(seconds: 90));
        } else {
          final String? sentence =
              await (translateSentence ??
                      const WordLookupService().translateSentence)(
                    sentence: sentences.single,
                    settings: settings,
                  )
                  .timeout(const Duration(seconds: 45));
          chinese = <String>[sentence ?? ''];
        }
        if (chinese.length != batch.length ||
            chinese.any((String text) => text.trim().isEmpty)) {
          throw const FormatException('Incomplete subtitle translations.');
        }
      } catch (_) {
        cancellationToken?.throwIfCancelled();
        decoded['translationWarning'] = '英文词级字幕已生成，但中文翻译未全部完成；请检查翻译设置或网络后重新生成。';
        break;
      }
      for (int i = 0; i < batch.length; i += 1) {
        batch[i]['chinese'] = chinese[i].trim();
        translations[_translationLineKey(batch[i], sentences[i])] = chinese[i]
            .trim();
      }
      // Keep the existing per-line keys so old checkpoints remain resumable.
      await _writeJsonAtomically(checkpoint, <String, Object?>{
        'version': 1,
        'signature': signature,
        'translations': translations,
      });
      completed += batch.length;
      onProgress?.call(completed, englishLines.length, sentences.last);
      cancellationToken?.throwIfCancelled();
      offset = end;
    }
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  String? _bilingualConfigurationError(LearningSettingsState settings) {
    if (!settings.generateBilingualAsrSubtitles ||
        translateSentence != null ||
        translateSentences != null) {
      return null;
    }
    if (settings.translationApiKey.trim().isEmpty) {
      return '无法生成双语字幕：请先在“翻译”中填写 API Key。';
    }
    if ((settings.translationProvider == '百度翻译' ||
            settings.translationProvider == '阿里云翻译') &&
        settings.translationApiSecret.trim().isEmpty) {
      return '无法生成双语字幕：${settings.translationProvider} 还需要填写 Secret。';
    }
    if (settings.translationBaseUrl.trim().isEmpty) {
      return '无法生成双语字幕：请在“翻译”中填写服务地址。';
    }
    if (_isAiTranslationProvider(settings.translationProvider) &&
        settings.translationModel.trim().isEmpty) {
      return '无法生成双语字幕：请在“翻译”中填写模型名称。';
    }
    return null;
  }

  bool _isAiTranslationProvider(String provider) {
    return provider == 'OpenAI' ||
        provider == 'OpenRouter' ||
        provider == 'SiliconFlow' ||
        provider == 'DeepSeek';
  }

  Future<Directory> jobDirectory({
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
  }) async {
    final Directory support = supportDirectory == null
        ? await getApplicationSupportDirectory()
        : await supportDirectory!();
    final String key = _jobKey(
      episodeId: episodeId,
      videoPath: videoPath,
      settings: settings,
    );
    return Directory(
      '${support.path}${Platform.pathSeparator}asr_subtitles'
      '${Platform.pathSeparator}${_safe(episodeId)}'
      '${Platform.pathSeparator}jobs'
      '${Platform.pathSeparator}$key',
    );
  }

  Future<AsrSubtitleRepairSummary> readRepairSummary({
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
  }) async {
    final Directory jobDir = await jobDirectory(
      episodeId: episodeId,
      videoPath: videoPath,
      settings: settings,
    );
    final File reportFile = File(
      '${jobDir.path}${Platform.pathSeparator}subtitle_quality_report.json',
    );
    if (!reportFile.existsSync()) {
      return const AsrSubtitleRepairSummary(0);
    }
    try {
      final Object? decoded = jsonDecode(await reportFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return const AsrSubtitleRepairSummary(0);
      }
      final int count =
          decoded['repairCount'] as int? ??
          (decoded['wordFix'] as int? ?? 0) +
              (decoded['wordDeleted'] as int? ?? 0) +
              (decoded['chunkBoundaryFix'] as int? ?? 0);
      return AsrSubtitleRepairSummary(count);
    } catch (_) {
      return const AsrSubtitleRepairSummary(0);
    }
  }

  Future<Map<String, Object?>> _transcribe({
    required AsrAudioChunk chunk,
    required LearningSettingsState settings,
  }) async {
    if (cloudTranscribeChunk != null) {
      return cloudTranscribeChunk!(chunk: chunk, settings: settings);
    }
    return service.generateCloudChunk(chunk: chunk, settings: settings);
  }

  List<PlayerSubtitleWord> _wordsForCurrentLine(
    List<Map<String, Object?>> recognizedLines,
    PlayerSubtitleLine currentLine,
  ) {
    final String raw = jsonEncode(<String, Object?>{
      'version': 1,
      'lines': recognizedLines,
    });
    final List<PlayerSubtitleWord> candidates =
        parseSubtitleLines(raw)
            .expand((PlayerSubtitleLine line) => line.words)
            .where((PlayerSubtitleWord word) {
              final int midpoint =
                  word.startMs + ((word.endMs - word.startMs) ~/ 2);
              return midpoint >= currentLine.startMs &&
                  midpoint <= currentLine.endMs;
            })
            .toList(growable: false)
          ..sort(
            (PlayerSubtitleWord a, PlayerSubtitleWord b) =>
                a.startMs.compareTo(b.startMs),
          );
    final List<PlayerSubtitleWord> result = <PlayerSubtitleWord>[];
    for (final PlayerSubtitleWord word in candidates) {
      final int startMs = word.startMs.clamp(
        currentLine.startMs,
        currentLine.endMs,
      );
      final int endMs = word.endMs.clamp(
        currentLine.startMs,
        currentLine.endMs,
      );
      final int safeStartMs = result.isEmpty
          ? startMs
          : startMs < result.last.endMs
          ? result.last.endMs
          : startMs;
      if (endMs <= safeStartMs) continue;
      result.add(
        PlayerSubtitleWord(
          text: word.text,
          startMs: safeStartMs,
          endMs: endMs,
          confidence: word.confidence,
        ),
      );
    }
    return result;
  }

  Future<String> _translateRegeneratedLine({
    required String english,
    required LearningSettingsState settings,
  }) async {
    if (!settings.generateBilingualAsrSubtitles) return '';
    final String? configurationError = _bilingualConfigurationError(settings);
    if (configurationError != null) {
      throw AsrSubtitleGenerationException('$configurationError 原句已保留。');
    }
    Object? lastError;
    for (int attempt = 0; attempt < 2; attempt += 1) {
      try {
        final String? translated =
            await (translateSentence ??
                    const WordLookupService().translateSentence)(
                  sentence: english,
                  settings: settings,
                )
                .timeout(const Duration(seconds: 45));
        if (translated != null && translated.trim().isNotEmpty) {
          return translated.trim();
        }
        lastError = StateError('empty-translation');
      } catch (error) {
        lastError = error;
      }
    }
    throw AsrSubtitleGenerationException(
      '当前句英文已识别，但中文翻译失败，原句已保留：${_errorMessage(lastError ?? 'unknown-error')}',
    );
  }

  Map<String, Object?> _lineToJson(PlayerSubtitleLine line) {
    return <String, Object?>{
      'startMs': line.startMs,
      'endMs': line.endMs,
      'english': line.english,
      'chinese': line.chinese,
      'words': line.words
          .map(
            (PlayerSubtitleWord word) => <String, Object?>{
              'text': word.text,
              'startMs': word.startMs,
              'endMs': word.endMs,
              if (word.confidence != null) 'confidence': word.confidence,
            },
          )
          .toList(growable: false),
    };
  }

  Future<void> _loadOrTranscribeValidChunk({
    required File chunkFile,
    required AsrAudioChunk chunk,
    required int chunkEndMs,
    required LearningSettingsState settings,
    required int sourceChunk,
    required _SubtitleQualityReport report,
    required bool allowReferenceFallback,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    for (int attempt = 0; attempt < 2; attempt += 1) {
      try {
        cancellationToken?.throwIfCancelled();
        late final Map<String, Object?> chunkJson;
        if (attempt == 0 && chunkFile.existsSync()) {
          final Object? decoded = jsonDecode(await chunkFile.readAsString());
          if (decoded is! Map<String, dynamic>) {
            throw StateError('invalid-asr-chunk');
          }
          chunkJson = Map<String, Object?>.from(decoded);
        } else {
          chunkJson = await _transcribe(chunk: chunk, settings: settings)
              .timeout(
                const Duration(minutes: 20),
                onTimeout: () => throw TimeoutException('AI 字幕生成超时，请重试或换更小模型。'),
              );
        }
        final Map<String, Object?> normalized = _normalizeChunkTimeline(
          chunkJson,
          chunkStartMs: chunk.offsetMs,
          chunkEndMs: chunkEndMs,
          sourceChunk: sourceChunk,
          report: report,
        );
        final Object? lines = normalized['lines'];
        if (lines is! List<dynamic> || lines.isNotEmpty) {
          _validateFinalResult(jsonEncode(normalized));
        }
        await chunkFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert(normalized),
        );
        return;
      } catch (error) {
        cancellationToken?.throwIfCancelled();
        if (chunkFile.existsSync()) {
          await chunkFile.delete();
        }
        if (attempt == 1) {
          if (allowReferenceFallback) {
            report
              ..repairCount += 1
              ..usedReferenceFallback = true
              ..anomalies.add(<String, Object?>{
                'kind': 'referenceFallback',
                'sourceChunk': sourceChunk,
                'errorType': error.runtimeType.toString(),
              });
            await chunkFile.writeAsString(
              const JsonEncoder.withIndent(' ').convert(<String, Object?>{
                'version': 1,
                'language': 'en',
                'lines': const <Object?>[],
              }),
            );
            return;
          }
          throw StateError(
            '第 ${sourceChunk + 1} 段处理失败：${_errorMessage(error)}',
          );
        }
      }
    }
  }

  void _validateFinalResult(String raw, {bool allowLineOverlap = false}) {
    final List<PlayerSubtitleLine> lines = parseSubtitleLines(raw);
    if (lines.isEmpty) {
      throw StateError('字幕检查失败：没有识别到有效字幕。');
    }

    int previousEndMs = -1;
    for (int index = 0; index < lines.length; index += 1) {
      final PlayerSubtitleLine line = lines[index];
      final String location = '第 ${index + 1} 句';
      if (line.english.trim().isEmpty) {
        throw StateError('字幕检查失败：$location 存在空字幕。');
      }
      if (line.endMs <= line.startMs) {
        throw StateError('字幕检查失败：$location 存在无效时间轴。');
      }
      if (line.words.isEmpty) {
        throw StateError('字幕检查失败：$location 未返回词级时间戳，无法精准跟读单词。');
      }
      final int expectedWordCount = _wordCount(line.english);
      final int timedWordCount = line.words.fold<int>(
        0,
        (int count, PlayerSubtitleWord word) => count + _wordCount(word.text),
      );
      if (expectedWordCount > 0 && timedWordCount < expectedWordCount) {
        throw StateError('字幕检查失败：$location 不是每个英文单词都有词级时间戳。');
      }
      if (_comparableText(line.english) !=
          _comparableText(
            line.words.map((PlayerSubtitleWord word) => word.text).join(' '),
          )) {
        throw StateError('字幕检查失败：$location 的正文与词级时间戳文本不一致。');
      }
      int previousWordEndMs = -1;
      for (final PlayerSubtitleWord word in line.words) {
        if (previousWordEndMs >= 0 && word.startMs < previousWordEndMs) {
          throw StateError('字幕检查失败：$location 的单词时间轴乱序或重叠。');
        }
        previousWordEndMs = word.endMs;
      }
      if (!allowLineOverlap &&
          previousEndMs >= 0 &&
          line.startMs < previousEndMs - 250) {
        throw StateError('字幕检查失败：$location 时间轴乱序或重叠过多。');
      }
      previousEndMs = line.endMs;
    }
  }

  String _repairFinalWordTimelines(
    String raw, {
    required _SubtitleQualityReport report,
  }) {
    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    final List<dynamic> lines =
        decoded['lines'] as List<dynamic>? ?? const <dynamic>[];
    for (final Object? item in lines) {
      if (item is! Map<String, dynamic>) continue;
      final String english = (item['english'] as String? ?? '').trim();
      final int startMs = _timelineMs(item['startMs']);
      final int endMs = _timelineMs(item['endMs']);
      if (english.isEmpty || endMs <= startMs) continue;
      final List<Map<String, Object?>> words =
          (item['words'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(Map<String, Object?>.from)
              .toList(growable: false);
      final int expectedWordCount = _wordCount(english);
      final int timedWordCount = words.fold<int>(
        0,
        (int count, Map<String, Object?> word) =>
            count + _wordCount(word['text'] as String? ?? ''),
      );
      final bool hasValidCoverage =
          words.isNotEmpty &&
          timedWordCount >= expectedWordCount &&
          _comparableText(english) ==
              _comparableText(
                words
                    .map((Map<String, Object?> word) => word['text'] ?? '')
                    .join(' '),
              ) &&
          _hasValidWordTimeline(words) &&
          words.every(
            (Map<String, Object?> word) =>
                _timelineMs(word['startMs']) >= startMs &&
                _timelineMs(word['endMs']) <= endMs,
          );
      if (hasValidCoverage) continue;
      final List<Map<String, Object?>> repaired = _synthesizeWords(
        english,
        startMs,
        endMs,
      );
      if (repaired.isEmpty) continue;
      item['words'] = repaired;
      report
        ..wordFix += repaired.length
        ..repairCount += 1;
    }
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  int _wordCount(String text) {
    return RegExp("[A-Za-z0-9]+(?:[’'-][A-Za-z0-9]+)?").allMatches(text).length;
  }

  String _comparableText(String text) => RegExp(
    '[A-Za-z0-9]+',
  ).allMatches(text).map((Match match) => match.group(0)!.toLowerCase()).join();

  Future<String> _mergeChunks(
    Directory chunksDir,
    int totalChunks, {
    required _SubtitleQualityReport report,
  }) async {
    final List<Map<String, Object?>> lines = <Map<String, Object?>>[];
    final Map<String, String> glossary = <String, String>{};
    for (int index = 0; index < totalChunks; index += 1) {
      final File chunkFile = File(
        '${chunksDir.path}${Platform.pathSeparator}${index.toString().padLeft(5, '0')}.json',
      );
      final Object? decoded = jsonDecode(await chunkFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw StateError('invalid-asr-chunk');
      }
      lines.addAll(
        (decoded['lines'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(
              (Map<String, dynamic> line) => <String, Object?>{
                ...line,
                '_sourceChunk': index,
              },
            ),
      );
      for (final Object? item
          in decoded['glossary'] as List<dynamic>? ?? const <dynamic>[]) {
        if (item is! Map<String, dynamic>) continue;
        final String word = (item['word'] as String? ?? '')
            .trim()
            .toLowerCase();
        final String definition = (item['definitionCn'] as String? ?? '')
            .trim();
        if (RegExp(r'^[a-z]{2,}$').hasMatch(word) && definition.isNotEmpty) {
          glossary.putIfAbsent(word, () => definition);
        }
      }
    }
    final List<Map<String, Object?>> boundaryNormalized =
        _normalizeChunkBoundaries(lines, report: report);
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'version': 1,
      'language': '',
      'lines': _normalizeTimeline(
        boundaryNormalized,
        report: report,
      ).map(_withoutSourceChunk).toList(growable: false),
      'glossary': glossary.entries
          .map(
            (MapEntry<String, String> entry) => <String, String>{
              'word': entry.key,
              'definitionCn': entry.value,
            },
          )
          .toList(growable: false),
    });
  }

  List<Map<String, Object?>> _normalizeTimeline(
    List<Map<String, Object?>> lines, {
    _SubtitleQualityReport? report,
  }) {
    final List<Map<String, Object?>> sorted =
        lines.map(Map<String, Object?>.from).toList(growable: false)..sort(
          (Map<String, Object?> a, Map<String, Object?> b) =>
              _timelineMs(a['startMs']).compareTo(_timelineMs(b['startMs'])),
        );
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    for (Map<String, Object?> line in sorted) {
      if (result.isEmpty) {
        result.add(line);
        continue;
      }
      final Map<String, Object?> previous = result.last;
      if (_sameOverlappingLine(previous, line)) {
        continue;
      }
      final int overlapMs =
          _timelineMs(previous['endMs']) - _timelineMs(line['startMs']);
      if (overlapMs > 0) {
        final int previousSourceChunk = _sourceChunk(previous);
        final int currentSourceChunk = _sourceChunk(line);
        report?.addOverlap(
          kind: 'sentence',
          previousText: previous['english'] as String? ?? '',
          previousStart: _timelineMs(previous['startMs']),
          previousEnd: _timelineMs(previous['endMs']),
          currentText: line['english'] as String? ?? '',
          currentStart: _timelineMs(line['startMs']),
          currentEnd: _timelineMs(line['endMs']),
          overlapMs: overlapMs,
          sourceChunk: currentSourceChunk,
          previousSourceChunk: previousSourceChunk,
        );
      }
      if (overlapMs > 0) {
        report?.repairCount += 1;
        if (overlapMs <= _repairableOverlapMs) {
          line = _shiftLine(line, overlapMs);
        } else if (_trimLineAtBoundary(
          previous,
          _timelineMs(line['startMs']),
        )) {
          report?.wordFix += 1;
        } else {
          line = _shiftLine(line, overlapMs);
        }
        if (_sourceChunk(previous) != _sourceChunk(line)) {
          report?.chunkBoundaryFix += 1;
        }
      }
      result.add(line);
    }
    return result;
  }

  List<Map<String, Object?>> _normalizeChunkBoundaries(
    List<Map<String, Object?>> lines, {
    required _SubtitleQualityReport report,
  }) {
    final Map<int, List<Map<String, Object?>>> byChunk =
        <int, List<Map<String, Object?>>>{};
    for (final Map<String, Object?> line in lines) {
      byChunk
          .putIfAbsent(_sourceChunk(line), () => <Map<String, Object?>>[])
          .add(Map<String, Object?>.from(line));
    }
    Map<String, Object?>? previousLastWord;
    int previousChunk = -1;
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    for (final int sourceChunk in byChunk.keys.toList()..sort()) {
      List<Map<String, Object?>> chunkLines = byChunk[sourceChunk]!
        ..sort(
          (Map<String, Object?> a, Map<String, Object?> b) =>
              _timelineMs(a['startMs']).compareTo(_timelineMs(b['startMs'])),
        );
      final Map<String, Object?>? firstWord = _firstWord(chunkLines);
      if (previousLastWord != null && firstWord != null) {
        final int overlapMs =
            _timelineMs(previousLastWord['endMs']) -
            _timelineMs(firstWord['startMs']);
        if (overlapMs > 0) {
          report.addOverlap(
            kind: 'chunkBoundary',
            previousText: previousLastWord['text'] as String? ?? '',
            previousStart: _timelineMs(previousLastWord['startMs']),
            previousEnd: _timelineMs(previousLastWord['endMs']),
            currentText: firstWord['text'] as String? ?? '',
            currentStart: _timelineMs(firstWord['startMs']),
            currentEnd: _timelineMs(firstWord['endMs']),
            overlapMs: overlapMs,
            sourceChunk: sourceChunk,
            previousSourceChunk: previousChunk,
          );
          if (overlapMs <= _repairableOverlapMs) {
            chunkLines = chunkLines
                .map((Map<String, Object?> line) => _shiftLine(line, overlapMs))
                .toList(growable: false);
            report
              ..chunkBoundaryFix += 1
              ..repairCount += 1;
          } else if (_trimPreviousLineAtBoundary(
            result,
            _timelineMs(firstWord['startMs']),
          )) {
            report
              ..chunkBoundaryFix += 1
              ..repairCount += 1;
          }
        }
      }
      final Map<String, Object?>? lastWord = _lastWord(chunkLines);
      if (lastWord != null) {
        previousLastWord = lastWord;
        previousChunk = sourceChunk;
      }
      result.addAll(chunkLines);
    }
    return result;
  }

  bool _trimPreviousLineAtBoundary(
    List<Map<String, Object?>> lines,
    int boundaryMs,
  ) {
    for (int index = lines.length - 1; index >= 0; index -= 1) {
      final Map<String, Object?> line = lines[index];
      if (_lineWords(line).isEmpty) continue;
      return _trimLineAtBoundary(line, boundaryMs);
    }
    return false;
  }

  bool _trimLineAtBoundary(Map<String, Object?> line, int boundaryMs) {
    final List<Map<String, Object?>> words = _lineWords(line);
    if (words.isEmpty) return false;
    final Map<String, Object?> lastWord = words.last;
    if (_timelineMs(lastWord['startMs']) >= boundaryMs ||
        _timelineMs(lastWord['endMs']) <= boundaryMs) {
      return false;
    }
    lastWord['endMs'] = boundaryMs;
    line['words'] = words;
    line['endMs'] = boundaryMs;
    return true;
  }

  Map<String, Object?>? _firstWord(List<Map<String, Object?>> lines) {
    for (final Map<String, Object?> line in lines) {
      final List<Map<String, Object?>> words = _lineWords(line);
      if (words.isNotEmpty) return words.first;
    }
    return null;
  }

  Map<String, Object?>? _lastWord(List<Map<String, Object?>> lines) {
    for (final Map<String, Object?> line in lines.reversed) {
      final List<Map<String, Object?>> words = _lineWords(line);
      if (words.isNotEmpty) return words.last;
    }
    return null;
  }

  List<Map<String, Object?>> _lineWords(Map<String, Object?> line) =>
      (line['words'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(Map<String, Object?>.from)
          .toList(growable: false);

  Map<String, Object?> _normalizeChunkTimeline(
    Map<String, Object?> chunk, {
    required int chunkStartMs,
    required int chunkEndMs,
    required int sourceChunk,
    required _SubtitleQualityReport report,
  }) {
    final List<Map<String, Object?>> lines =
        (chunk['lines'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(
              (Map<String, dynamic> line) => <String, Object?>{
                ...line,
                '_sourceChunk': sourceChunk,
              },
            )
            .toList(growable: false);
    final List<Map<String, Object?>> constrained = _constrainChunkTimeline(
      lines,
      chunkStartMs: chunkStartMs,
      chunkEndMs: chunkEndMs,
      report: report,
    );
    final List<Map<String, Object?>> normalized = _normalizeWords(
      constrained,
      report: report,
    );
    return <String, Object?>{
      ...chunk,
      'lines': _normalizeTimeline(
        normalized,
        report: report,
      ).map(_withoutSourceChunk).toList(growable: false),
    };
  }

  List<Map<String, Object?>> _constrainChunkTimeline(
    List<Map<String, Object?>> lines, {
    required int chunkStartMs,
    required int chunkEndMs,
    required _SubtitleQualityReport report,
  }) {
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    for (final Map<String, Object?> original in lines) {
      bool repaired = false;
      final Map<String, Object?> line = Map<String, Object?>.from(original);
      final List<Map<String, Object?>> originalWords = _lineWords(line);
      final List<Map<String, Object?>> words = <Map<String, Object?>>[];
      for (final Map<String, Object?> originalWord in originalWords) {
        final int startMs = _timelineMs(originalWord['startMs']);
        final int endMs = _timelineMs(originalWord['endMs']);
        if (endMs <= chunkStartMs || startMs >= chunkEndMs) {
          report.wordDeleted += 1;
          repaired = true;
          continue;
        }
        final Map<String, Object?> word = Map<String, Object?>.from(
          originalWord,
        );
        word['startMs'] = startMs < chunkStartMs ? chunkStartMs : startMs;
        word['endMs'] = endMs > chunkEndMs ? chunkEndMs : endMs;
        repaired =
            repaired || word['startMs'] != startMs || word['endMs'] != endMs;
        if (_timelineMs(word['endMs']) > _timelineMs(word['startMs'])) {
          words.add(word);
        } else {
          report.wordDeleted += 1;
          repaired = true;
        }
      }
      if (words.length != originalWords.length) {
        words.clear();
      }
      if (words.isNotEmpty) {
        line['words'] = words;
        line['startMs'] = _timelineMs(words.first['startMs']);
        line['endMs'] = _timelineMs(words.last['endMs']);
      } else {
        line['words'] = const <Map<String, Object?>>[];
        int startMs = _timelineMs(line['startMs']);
        int endMs = _timelineMs(line['endMs']);
        if (startMs < chunkStartMs || startMs >= chunkEndMs) {
          startMs = chunkStartMs;
          repaired = true;
        }
        if (endMs <= startMs || endMs > chunkEndMs) {
          final int tokenCount = _wordCount(line['english'] as String? ?? '');
          final int fallbackEndMs =
              startMs + (tokenCount > 0 ? tokenCount * 400 : 1000);
          endMs = fallbackEndMs < chunkEndMs ? fallbackEndMs : chunkEndMs;
          repaired = true;
        }
        if (endMs <= startMs) continue;
        line['startMs'] = startMs;
        line['endMs'] = endMs;
      }
      if (repaired) report.repairCount += 1;
      result.add(line);
    }
    return result;
  }

  List<Map<String, Object?>> _normalizeWords(
    List<Map<String, Object?>> lines, {
    required _SubtitleQualityReport report,
  }) {
    final List<Map<String, Object?>> sorted =
        lines.map(Map<String, Object?>.from).toList(growable: false)..sort(
          (Map<String, Object?> a, Map<String, Object?> b) =>
              _timelineMs(a['startMs']).compareTo(_timelineMs(b['startMs'])),
        );
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    for (final Map<String, Object?> line in sorted) {
      if (result.isNotEmpty && _sameOverlappingLine(result.last, line)) {
        continue;
      }
      List<Map<String, Object?>> words =
          (line['words'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(Map<String, Object?>.from)
              .where(
                (Map<String, Object?> word) =>
                    _timelineMs(word['endMs']) > _timelineMs(word['startMs']),
              )
              .toList(growable: false)
            ..sort(
              (Map<String, Object?> a, Map<String, Object?> b) => _timelineMs(
                a['startMs'],
              ).compareTo(_timelineMs(b['startMs'])),
            );
      final int originalCount =
          (line['words'] as List<dynamic>? ?? const <dynamic>[]).length;
      report.wordDeleted += originalCount - words.length;
      final String english = line['english'] as String? ?? '';
      bool repaired = false;
      if (words.isEmpty ||
          _comparableText(english) !=
              _comparableText(
                words
                    .map((Map<String, Object?> word) => word['text'] ?? '')
                    .join(' '),
              )) {
        words = _synthesizeWords(
          english,
          _timelineMs(line['startMs']),
          _timelineMs(line['endMs']),
        );
        report.wordFix += words.length;
        repaired = true;
      }
      Map<String, Object?>? previousWord;
      for (final Map<String, Object?> word in words) {
        if (previousWord != null &&
            _timelineMs(word['startMs']) < _timelineMs(previousWord['endMs'])) {
          final int overlapMs =
              _timelineMs(previousWord['endMs']) - _timelineMs(word['startMs']);
          report.addOverlap(
            kind: 'word',
            previousText: previousWord['text'] as String? ?? '',
            previousStart: _timelineMs(previousWord['startMs']),
            previousEnd: _timelineMs(previousWord['endMs']),
            currentText: word['text'] as String? ?? '',
            currentStart: _timelineMs(word['startMs']),
            currentEnd: _timelineMs(word['endMs']),
            overlapMs: overlapMs,
            sourceChunk: _sourceChunk(line),
            previousSourceChunk: _sourceChunk(line),
          );
          final int currentStartMs = _timelineMs(word['startMs']);
          if (currentStartMs > _timelineMs(previousWord['startMs'])) {
            previousWord['endMs'] = currentStartMs;
          } else {
            final int latestEndMs =
                _timelineMs(previousWord['endMs']) > _timelineMs(word['endMs'])
                ? _timelineMs(previousWord['endMs'])
                : _timelineMs(word['endMs']);
            final int boundaryMs =
                _timelineMs(previousWord['startMs']) +
                ((latestEndMs - _timelineMs(previousWord['startMs'])) ~/ 2);
            previousWord['endMs'] = boundaryMs;
            word['startMs'] = boundaryMs;
          }
          report.wordFix += 1;
          repaired = true;
        }
        previousWord = word;
      }
      if (!_hasValidWordTimeline(words)) {
        words = _synthesizeWords(
          english,
          _timelineMs(line['startMs']),
          _timelineMs(line['endMs']),
        );
        report.wordFix += words.length;
        repaired = true;
      }
      if (words.isNotEmpty) {
        line['words'] = words;
        line['startMs'] = _timelineMs(words.first['startMs']);
        line['endMs'] = _timelineMs(words.last['endMs']);
      }
      if (repaired) report.repairCount += 1;
      result.add(line);
    }
    return result;
  }

  List<Map<String, Object?>> _synthesizeWords(
    String english,
    int startMs,
    int endMs,
  ) {
    final List<String> tokens = RegExp("[A-Za-z0-9]+(?:[’'-][A-Za-z0-9]+)?")
        .allMatches(english)
        .map((Match match) => match.group(0)!)
        .toList(growable: false);
    if (tokens.isEmpty || endMs <= startMs) {
      return const <Map<String, Object?>>[];
    }
    final int durationMs = endMs - startMs < tokens.length
        ? tokens.length
        : endMs - startMs;
    return <Map<String, Object?>>[
      for (int index = 0; index < tokens.length; index += 1)
        <String, Object?>{
          'text': tokens[index],
          'startMs': startMs + (durationMs * index ~/ tokens.length),
          'endMs': startMs + (durationMs * (index + 1) ~/ tokens.length),
        },
    ];
  }

  bool _hasValidWordTimeline(List<Map<String, Object?>> words) {
    int previousEndMs = -1;
    for (final Map<String, Object?> word in words) {
      final int startMs = _timelineMs(word['startMs']);
      final int endMs = _timelineMs(word['endMs']);
      if (endMs <= startMs || (previousEndMs >= 0 && startMs < previousEndMs)) {
        return false;
      }
      previousEndMs = endMs;
    }
    return true;
  }

  int _sourceChunk(Map<String, Object?> line) {
    final Object? value = line['_sourceChunk'];
    return value is int ? value : -1;
  }

  Map<String, Object?> _withoutSourceChunk(Map<String, Object?> line) =>
      <String, Object?>{
        for (final MapEntry<String, Object?> entry in line.entries)
          if (entry.key != '_sourceChunk') entry.key: entry.value,
      };

  bool _sameOverlappingLine(
    Map<String, Object?> previous,
    Map<String, Object?> current,
  ) {
    final String previousText = (previous['english'] as String? ?? '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    final String currentText = (current['english'] as String? ?? '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    return previousText.isNotEmpty &&
        previousText == currentText &&
        _timelineMs(current['startMs']) <= _timelineMs(previous['endMs']) &&
        _timelineMs(current['endMs']) >= _timelineMs(previous['startMs']);
  }

  Map<String, Object?> _shiftLine(Map<String, Object?> line, int offsetMs) {
    return <String, Object?>{
      ...line,
      'startMs': _timelineMs(line['startMs']) + offsetMs,
      'endMs': _timelineMs(line['endMs']) + offsetMs,
      'words': (line['words'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(
            (Map<String, dynamic> word) => <String, Object?>{
              ...word,
              'startMs': _timelineMs(word['startMs']) + offsetMs,
              'endMs': _timelineMs(word['endMs']) + offsetMs,
            },
          )
          .toList(growable: false),
    };
  }

  int _timelineMs(Object? value) => value is num ? value.round() : -1;

  Future<String?> _previewText(File chunkFile) async {
    final Object? decoded = jsonDecode(await chunkFile.readAsString());
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final List<dynamic> lines =
        decoded['lines'] as List<dynamic>? ?? const <dynamic>[];
    for (final Object? line in lines.reversed) {
      if (line is Map<String, dynamic>) {
        final String text = (line['english'] as String? ?? '').trim();
        if (text.isNotEmpty) {
          return text;
        }
      }
    }
    return null;
  }

  Future<int> _currentMs(File chunkFile, int fallbackMs) async {
    final Object? decoded = jsonDecode(await chunkFile.readAsString());
    if (decoded is! Map<String, dynamic>) {
      return fallbackMs;
    }
    int currentMs = fallbackMs;
    final List<dynamic> lines =
        decoded['lines'] as List<dynamic>? ?? const <dynamic>[];
    for (final Object? line in lines) {
      if (line is Map<String, dynamic>) {
        final int? endMs = line['endMs'] as int?;
        if (endMs != null && endMs > currentMs) {
          currentMs = endMs;
        }
      }
    }
    return currentMs;
  }

  int _estimatedTotalMs(List<AsrAudioChunk> chunks) {
    if (chunks.isEmpty) {
      return 0;
    }
    if (chunks.length == 1) {
      return chunks.first.offsetMs + 60000;
    }
    final int stepMs =
        chunks.last.offsetMs - chunks[chunks.length - 2].offsetMs;
    return chunks.last.offsetMs + stepMs;
  }

  Future<void> _writeJob({
    required Directory jobDir,
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
    required int totalChunks,
    required String status,
    required String error,
  }) async {
    await jobDir.create(recursive: true);
    await File('${jobDir.path}${Platform.pathSeparator}job.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'version': 1,
        'episodeId': episodeId,
        'videoPath': videoPath,
        'provider': settings.asrProvider,
        'model': settings.asrModel,
        'chunkMs': 58000,
        'totalChunks': totalChunks,
        'status': status,
        'error': error,
      }),
    );
  }

  String _jobKey({
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
  }) {
    final FileStat stat = File(videoPath).statSync();
    final String value =
        '$episodeId|${File(videoPath).absolute.path}|${stat.size}|'
        '${stat.modified.millisecondsSinceEpoch}|${settings.asrProvider}|'
        '${settings.asrBaseUrl}|${settings.asrModel}';
    return sha1.convert(utf8.encode(value)).toString();
  }

  String _translationSignature(LearningSettingsState settings) {
    final String value =
        '${settings.translationProvider}|${settings.translationBaseUrl}|'
        '${settings.translationModel}';
    return sha1.convert(utf8.encode(value)).toString();
  }

  String _translationLineKey(Map<String, dynamic> line, String english) {
    final String value = '${line['startMs']}|${line['endMs']}|$english';
    return sha1.convert(utf8.encode(value)).toString();
  }

  Future<Map<String, String>> _loadTranslations(
    File file,
    String signature,
  ) async {
    if (!file.existsSync()) return <String, String>{};
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['signature'] != signature ||
          decoded['translations'] is! Map<String, dynamic>) {
        return <String, String>{};
      }
      return (decoded['translations'] as Map<String, dynamic>).map(
        (String key, dynamic value) =>
            MapEntry<String, String>(key, value is String ? value : ''),
      )..removeWhere((String _, String value) => value.isEmpty);
    } catch (_) {
      await file.delete();
      return <String, String>{};
    }
  }

  Future<void> _writeJsonAtomically(
    File file,
    Map<String, Object?> value,
  ) async {
    final File part = File('${file.path}.part');
    try {
      await part.writeAsString(jsonEncode(value), flush: true);
      await part.rename(file.path);
    } finally {
      if (part.existsSync()) await part.delete();
    }
  }

  String _errorMessage(Object error) {
    if (error is StateError) return error.message;
    if (error is AsrSubtitleGenerationException) return error.message;
    return error.toString();
  }

  String _safe(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp('_+'), '_');
  }
}
