import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../../settings/presentation/settings_provider.dart';
import 'desktop_ffmpeg.dart';

const MethodChannel _audioToolsChannel = MethodChannel(
  'com.shadowing.english/audio_tools',
);

typedef AsrPostTranscriptionOverride =
    Future<Response<dynamic>> Function({
      required BaseOptions options,
      required FormData data,
    });
typedef AsrPostChatCompletionOverride =
    Future<Response<dynamic>> Function({
      required BaseOptions options,
      required Map<String, Object?> data,
    });
typedef AsrPostJsonOverride =
    Future<Response<dynamic>> Function({
      required BaseOptions options,
      required String path,
      required Map<String, Object?> data,
      required Map<String, String> headers,
    });
typedef AsrPostFormOverride =
    Future<Response<dynamic>> Function({
      required String url,
      required FormData data,
    });
typedef AsrGetJsonOverride =
    Future<Response<dynamic>> Function({
      required BaseOptions options,
      required String path,
      required Map<String, String> headers,
    });
typedef AsrPrepareAudioOverride = Future<File> Function(File file);
typedef AsrPrepareAudioChunksOverride =
    Future<List<AsrAudioChunk>> Function(File file);
typedef AsrProgressCallback = void Function(AsrSubtitleProgress progress);

class AsrAudioChunk {
  const AsrAudioChunk({required this.file, required this.offsetMs});

  final File file;
  final int offsetMs;
}

enum AsrSubtitlePhase { recognizing, translating, finalizing, completed }

class AsrSubtitleProgress {
  const AsrSubtitleProgress({
    required this.completedChunks,
    required this.totalChunks,
    this.currentMs,
    this.totalMs,
    this.previewText,
    this.phase = AsrSubtitlePhase.recognizing,
    this.completedTranslations = 0,
    this.totalTranslations = 0,
  });

  final int completedChunks;
  final int totalChunks;
  final int? currentMs;
  final int? totalMs;
  final String? previewText;
  final AsrSubtitlePhase phase;
  final int completedTranslations;
  final int totalTranslations;

  double get value {
    if (phase == AsrSubtitlePhase.translating) {
      return totalTranslations == 0
          ? 0
          : (completedTranslations / totalTranslations).clamp(0.0, 1.0);
    }
    if (phase == AsrSubtitlePhase.finalizing ||
        phase == AsrSubtitlePhase.completed) {
      return 1;
    }
    final int? current = currentMs;
    final int? total = totalMs;
    if (current != null && total != null && total > 0) {
      return (current / total).clamp(0.0, 1.0);
    }
    return totalChunks == 0 ? 0 : completedChunks / totalChunks;
  }

  String get label {
    switch (phase) {
      case AsrSubtitlePhase.translating:
        return '正在翻译中文字幕 $completedTranslations/$totalTranslations 句';
      case AsrSubtitlePhase.finalizing:
        return '正在校验并保存字幕...';
      case AsrSubtitlePhase.completed:
        return '字幕生成完成';
      case AsrSubtitlePhase.recognizing:
        break;
    }
    final int? current = currentMs;
    final int? total = totalMs;
    if (current != null && total != null && total > 0) {
      return '已识别到 ${_formatPosition(current)} / ${_formatPosition(total)}';
    }
    return totalChunks == 0
        ? '正在准备音频...'
        : '正在生成词级同步字幕 $completedChunks/$totalChunks';
  }

  String _formatPosition(int ms) {
    final int seconds = (ms / 1000).floor();
    final int minutes = seconds ~/ 60;
    final int rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }
}

class AsrSubtitleService {
  const AsrSubtitleService({
    this.postTranscriptionOverride,
    this.postChatCompletionOverride,
    this.postJsonOverride,
    this.postFormOverride,
    this.getJsonOverride,
    this.prepareAudioOverride,
    this.prepareAudioChunksOverride,
    this.now,
  });

  static const int _chunkMs = 58000;
  static const int _maxTencentLineWords = 12;
  static const int _maxTencentLineMs = 5000;

  final AsrPostTranscriptionOverride? postTranscriptionOverride;
  final AsrPostChatCompletionOverride? postChatCompletionOverride;
  final AsrPostJsonOverride? postJsonOverride;
  final AsrPostFormOverride? postFormOverride;
  final AsrGetJsonOverride? getJsonOverride;
  final AsrPrepareAudioOverride? prepareAudioOverride;
  final AsrPrepareAudioChunksOverride? prepareAudioChunksOverride;
  final DateTime Function()? now;

  Future<String> generateWordsJson({
    required String videoPath,
    required LearningSettingsState settings,
    AsrProgressCallback? onProgress,
  }) async {
    if (settings.asrApiKey.trim().isEmpty ||
        settings.asrBaseUrl.trim().isEmpty ||
        settings.asrModel.trim().isEmpty) {
      throw StateError('missing-asr-settings');
    }
    final File file = File(videoPath);
    if (!file.existsSync()) {
      throw StateError('missing-video-file');
    }

    final List<AsrAudioChunk> chunks = await prepareAudioChunks(file);
    final int totalMs = _estimatedTotalMs(chunks);
    onProgress?.call(
      AsrSubtitleProgress(
        completedChunks: 0,
        totalChunks: chunks.length,
        currentMs: 0,
        totalMs: totalMs,
      ),
    );

    final BaseOptions options = BaseOptions(
      baseUrl: settings.asrBaseUrl,
      headers: <String, String>{
        'Authorization': 'Bearer ${settings.asrApiKey}',
        'Accept': 'application/json',
      },
    );
    final List<Map<String, Object?>> lines = <Map<String, Object?>>[];
    try {
      for (int index = 0; index < chunks.length; index += 1) {
        final AsrAudioChunk chunk = chunks[index];
        final Map<String, Object?> normalized = await generateCloudChunk(
          chunk: chunk,
          settings: settings,
          options: options,
        );
        lines.addAll(_linesFromNormalized(normalized));
        onProgress?.call(
          AsrSubtitleProgress(
            completedChunks: index + 1,
            totalChunks: chunks.length,
            currentMs: _currentMs(normalized, chunk.offsetMs),
            totalMs: totalMs,
          ),
        );
      }
    } finally {
      deleteTemporaryAudioChunks(chunks);
    }

    return const JsonEncoder.withIndent(
      '  ',
    ).convert(<String, Object?>{'version': 1, 'language': '', 'lines': lines});
  }

  Future<List<AsrAudioChunk>> prepareAudioChunks(File file) async {
    return _prepareAudioChunks(file);
  }

  Future<Map<String, Object?>> generateCloudChunk({
    required AsrAudioChunk chunk,
    required LearningSettingsState settings,
    BaseOptions? options,
  }) async {
    final BaseOptions resolvedOptions =
        options ??
        BaseOptions(
          baseUrl: settings.asrBaseUrl,
          headers: <String, String>{
            'Authorization': 'Bearer ${settings.asrApiKey}',
            'Accept': 'application/json',
          },
        );
    final Object? normalized = _usesAlibabaCloudAsr(settings)
        ? await _generateAlibabaQwenChunk(
            file: chunk.file,
            settings: settings,
            offsetMs: chunk.offsetMs,
          )
        : _usesTencentCloudAsr(settings)
        ? await _generateTencentSentenceChunk(
            file: chunk.file,
            settings: settings,
            offsetMs: chunk.offsetMs,
          )
        : _usesMimoChatAsr(settings)
        ? await _generateMimoChunk(
            file: chunk.file,
            settings: settings,
            offsetMs: chunk.offsetMs,
          )
        : await _generateTranscriptionChunk(
            file: chunk.file,
            settings: settings,
            options: resolvedOptions,
            offsetMs: chunk.offsetMs,
          );
    if (normalized is! Map<String, dynamic>) {
      throw StateError('invalid-asr-response');
    }
    return Map<String, Object?>.from(normalized);
  }

  Future<Object?> _generateTranscriptionChunk({
    required File file,
    required LearningSettingsState settings,
    required BaseOptions options,
    required int offsetMs,
  }) async {
    final FormData data = FormData.fromMap(<String, dynamic>{
      'model': settings.asrModel,
      'file': await MultipartFile.fromFile(file.path),
      'response_format': 'verbose_json',
      'timestamp_granularities[]': 'word',
    });

    try {
      final Response<dynamic> response = postTranscriptionOverride != null
          ? await postTranscriptionOverride!(options: options, data: data)
          : await Dio(
              options,
            ).post<dynamic>('/audio/transcriptions', data: data);

      final Object? normalized = _normalizeResponse(response.data);
      return _offsetNormalized(normalized, offsetMs);
    } on DioException catch (error) {
      throw StateError(_dioErrorMessage(error));
    }
  }

  Future<Object?> _generateMimoChunk({
    required File file,
    required LearningSettingsState settings,
    required int offsetMs,
  }) async {
    final String chineseInstruction = settings.generateBilingualAsrSubtitles
        ? 'Fill chinese with natural Simplified Chinese translation.'
        : 'Keep chinese empty.';
    final String chineseExample = settings.generateBilingualAsrSubtitles
        ? '中文翻译'
        : '';
    final String glossaryInstruction = settings.generateBilingualAsrSubtitles
        ? 'Include up to 10 useful independent English content words in glossary, each with a concise Simplified Chinese definition. Do not include pronouns, articles, contractions, or names.'
        : 'Keep glossary empty.';
    final String prompt =
        'Transcribe the audio into JSON only. Schema: '
        '{"version":1,"language":"en","lines":[{"startMs":0,'
        '"endMs":1000,"english":"text","chinese":"$chineseExample",'
        '"words":[{"text":"word","startMs":0,"endMs":100}]}],'
        '"glossary":[{"word":"word","definitionCn":"中文释义"}]}. '
        '$chineseInstruction $glossaryInstruction';
    final BaseOptions options = BaseOptions(
      baseUrl: settings.asrBaseUrl,
      headers: <String, String>{
        'Authorization': 'Bearer ${settings.asrApiKey}',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    );
    final Map<String, Object?> data = <String, Object?>{
      'model': settings.asrModel,
      'messages': <Map<String, Object?>>[
        <String, Object?>{
          'role': 'user',
          'content': <Map<String, Object?>>[
            <String, Object?>{'type': 'text', 'text': prompt},
            <String, Object?>{
              'type': 'input_audio',
              'input_audio': <String, Object?>{
                'data':
                    'data:${_mimeType(file.path)};base64,${base64Encode(file.readAsBytesSync())}',
              },
            },
          ],
        },
      ],
      'asr_options': <String, Object?>{'language': 'auto'},
      'stream': false,
    };

    try {
      final Response<dynamic> response;
      response = postChatCompletionOverride != null
          ? await postChatCompletionOverride!(options: options, data: data)
          : await Dio(options).post<dynamic>('/chat/completions', data: data);
      final Object? normalized = _normalizeResponse(response.data);
      if (normalized == null) {
        throw StateError('invalid-asr-response');
      }
      return _offsetNormalized(normalized, offsetMs);
    } on DioException catch (error) {
      throw StateError(_dioErrorMessage(error));
    }
  }

  Future<Object?> _generateTencentSentenceChunk({
    required File file,
    required LearningSettingsState settings,
    required int offsetMs,
  }) async {
    final ({String secretId, String secretKey}) credentials =
        _tencentCredentials(settings.asrApiKey);
    final String audioBase64 = base64Encode(file.readAsBytesSync());
    if (audioBase64.length > 3 * 1024 * 1024) {
      throw StateError('腾讯云单段音频超过 3MB，请缩短分段时长后重试。');
    }
    final Map<String, Object?> data = <String, Object?>{
      'SubServiceType': 2,
      'ProjectId': 0,
      'EngSerViceType': settings.asrModel.trim().isEmpty
          ? '16k_en'
          : settings.asrModel.trim(),
      'VoiceFormat': _tencentVoiceFormat(file.path),
      'SourceType': 1,
      'Data': audioBase64,
      'DataLen': file.lengthSync(),
      'WordInfo': 2,
    };
    final String payload = jsonEncode(data);
    final Map<String, String> headers = _tencentHeaders(
      secretId: credentials.secretId,
      secretKey: credentials.secretKey,
      payload: payload,
      timestamp:
          ((now?.call() ?? DateTime.now()).toUtc().millisecondsSinceEpoch /
                  1000)
              .floor(),
    );
    final BaseOptions options = BaseOptions(baseUrl: settings.asrBaseUrl);

    try {
      final Response<dynamic> response = postJsonOverride != null
          ? await postJsonOverride!(
              options: options,
              path: '/',
              data: data,
              headers: headers,
            )
          : await Dio(options).post<dynamic>(
              '/',
              data: data,
              options: Options(headers: headers),
            );
      return _normalizeTencentSentenceResponse(response.data, offsetMs);
    } on DioException catch (error) {
      throw StateError(_dioErrorMessage(error));
    }
  }

  Future<Object?> _generateAlibabaQwenChunk({
    required File file,
    required LearningSettingsState settings,
    required int offsetMs,
  }) async {
    final BaseOptions options = BaseOptions(
      baseUrl: settings.asrBaseUrl,
      headers: <String, String>{
        'Authorization': 'Bearer ${settings.asrApiKey}',
        'Accept': 'application/json',
      },
    );
    final Map<String, String> headers = <String, String>{
      'Authorization': 'Bearer ${settings.asrApiKey}',
      'Content-Type': 'application/json',
    };
    try {
      final Response<dynamic> policyResponse = await _getJson(
        options: options,
        path: '/api/v1/uploads?action=getPolicy&model=${settings.asrModel}',
        headers: headers,
      );
      final Map<String, dynamic> policyBody = _asMap(policyResponse.data);
      final Map<String, dynamic> policy = _asMap(policyBody['data']);
      final String uploadHost = policy['upload_host'] as String? ?? '';
      final String uploadDir = policy['upload_dir'] as String? ?? '';
      if (uploadHost.isEmpty || uploadDir.isEmpty) {
        throw StateError('阿里云 ASR 文件上传凭证无效。');
      }
      final String key = '$uploadDir/${_fileName(file.path)}';
      final FormData uploadData = FormData.fromMap(<String, dynamic>{
        'OSSAccessKeyId': policy['oss_access_key_id'],
        'policy': policy['policy'],
        'Signature': policy['signature'],
        'x-oss-object-acl': policy['x_oss_object_acl'],
        'x-oss-forbid-overwrite': policy['x_oss_forbid_overwrite'],
        'key': key,
        'success_action_status': '200',
        'file': await MultipartFile.fromFile(file.path),
      });
      if (postFormOverride != null) {
        await postFormOverride!(url: uploadHost, data: uploadData);
      } else {
        await Dio().post<dynamic>(uploadHost, data: uploadData);
      }

      final Response<dynamic> submitted = await _postJson(
        options: options,
        path: '/api/v1/services/audio/asr/transcription',
        data: <String, Object?>{
          'model': settings.asrModel,
          'input': <String, Object?>{'file_url': 'oss://$key'},
          'parameters': <String, Object?>{
            'channel_id': <int>[0],
            'enable_itn': false,
            'enable_words': true,
            'language': 'en',
          },
        },
        headers: <String, String>{
          ...headers,
          'X-DashScope-Async': 'enable',
          'X-DashScope-OssResourceResolve': 'enable',
        },
      );
      final String taskId =
          _asMap(_asMap(submitted.data)['output'])['task_id'] as String? ?? '';
      if (taskId.isEmpty) {
        throw StateError('阿里云 ASR 未返回任务 ID。');
      }

      for (int attempt = 0; attempt < 240; attempt += 1) {
        final Response<dynamic> taskResponse = await _getJson(
          options: options,
          path: '/api/v1/tasks/$taskId',
          headers: headers,
        );
        final Map<String, dynamic> output = _asMap(
          _asMap(taskResponse.data)['output'],
        );
        final String status = output['task_status'] as String? ?? '';
        if (status == 'SUCCEEDED') {
          final String resultUrl =
              _asMap(output['result'])['transcription_url'] as String? ?? '';
          if (resultUrl.isEmpty) {
            throw StateError('阿里云 ASR 未返回识别结果。');
          }
          final Response<dynamic> resultResponse = await _getJson(
            options: BaseOptions(),
            path: resultUrl,
            headers: const <String, String>{},
          );
          return _offsetNormalized(
            _normalizeAlibabaQwenResult(resultResponse.data),
            offsetMs,
          );
        }
        if (status == 'FAILED' || status == 'CANCELED') {
          final String message = output['message'] as String? ?? '未知错误';
          throw StateError('阿里云 ASR 失败：$message');
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      throw StateError('阿里云 ASR 任务超时，请重试。');
    } on DioException catch (error) {
      throw StateError(_dioErrorMessage(error));
    }
  }

  Future<Response<dynamic>> _postJson({
    required BaseOptions options,
    required String path,
    required Map<String, Object?> data,
    required Map<String, String> headers,
  }) {
    if (postJsonOverride != null) {
      return postJsonOverride!(
        options: options,
        path: path,
        data: data,
        headers: headers,
      );
    }
    return Dio(options).post<dynamic>(
      path,
      data: data,
      options: Options(headers: headers),
    );
  }

  Future<Response<dynamic>> _getJson({
    required BaseOptions options,
    required String path,
    required Map<String, String> headers,
  }) {
    if (getJsonOverride != null) {
      return getJsonOverride!(options: options, path: path, headers: headers);
    }
    return Dio(options).get<dynamic>(path, options: Options(headers: headers));
  }

  Map<String, dynamic> _asMap(Object? value) =>
      value is Map<String, dynamic> ? value : <String, dynamic>{};

  Map<String, Object?> _normalizeAlibabaQwenResult(Object? data) {
    final List<Map<String, Object?>> lines = <Map<String, Object?>>[];
    for (final Object? transcript
        in _asMap(data)['transcripts'] as List<dynamic>? ?? const <dynamic>[]) {
      if (transcript is! Map<String, dynamic>) continue;
      for (final Object? sentence
          in transcript['sentences'] as List<dynamic>? ?? const <dynamic>[]) {
        if (sentence is! Map<String, dynamic>) continue;
        final List<Map<String, Object?>> words =
            (sentence['words'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<Map<String, dynamic>>()
                .map((Map<String, dynamic> word) {
                  final String text = (word['text'] as String? ?? '').trim();
                  final int? startMs = _intMs(word['begin_time']);
                  final int? endMs = _intMs(word['end_time']);
                  if (text.isEmpty ||
                      startMs == null ||
                      endMs == null ||
                      endMs <= startMs) {
                    return null;
                  }
                  return <String, Object?>{
                    'text': text,
                    'startMs': startMs,
                    'endMs': endMs,
                  };
                })
                .whereType<Map<String, Object?>>()
                .toList(growable: false);
        if (words.isEmpty) continue;
        lines.add(<String, Object?>{
          'startMs': words.first['startMs'],
          'endMs': words.last['endMs'],
          'english': _joinTencentWords(words),
          'chinese': '',
          'words': words,
        });
      }
    }
    return <String, Object?>{'version': 1, 'language': 'en', 'lines': lines};
  }

  ({String secretId, String secretKey}) _tencentCredentials(String value) {
    final String trimmed = value.trim();
    int separator = trimmed.indexOf(':');
    if (separator < 0) {
      separator = trimmed.indexOf('：');
    }
    if (separator <= 0 || separator == trimmed.length - 1) {
      throw StateError('腾讯云 ASR Key 需要填写为 SecretId:SecretKey，中间用英文冒号。');
    }
    final String secretId = trimmed.substring(0, separator).trim();
    final String secretKey = trimmed.substring(separator + 1).trim();
    if (secretId.isEmpty || secretKey.isEmpty) {
      throw StateError('腾讯云 ASR Key 需要填写为 SecretId:SecretKey，中间用英文冒号。');
    }
    return (secretId: secretId, secretKey: secretKey);
  }

  Map<String, String> _tencentHeaders({
    required String secretId,
    required String secretKey,
    required String payload,
    required int timestamp,
  }) {
    const String algorithm = 'TC3-HMAC-SHA256';
    const String service = 'asr';
    const String host = 'asr.tencentcloudapi.com';
    final DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(
      timestamp * 1000,
      isUtc: true,
    );
    final String date =
        '${dateTime.year.toString().padLeft(4, '0')}-'
        '${dateTime.month.toString().padLeft(2, '0')}-'
        '${dateTime.day.toString().padLeft(2, '0')}';
    final String canonicalRequest =
        'POST\n'
        '/\n'
        '\n'
        'content-type:application/json; charset=utf-8\n'
        'host:$host\n'
        '\n'
        'content-type;host\n'
        '${sha256.convert(utf8.encode(payload))}';
    final String credentialScope = '$date/$service/tc3_request';
    final String stringToSign =
        '$algorithm\n'
        '$timestamp\n'
        '$credentialScope\n'
        '${sha256.convert(utf8.encode(canonicalRequest))}';
    final List<int> secretDate = _hmacSha256(
      utf8.encode('TC3$secretKey'),
      date,
    );
    final List<int> secretService = _hmacSha256(secretDate, service);
    final List<int> secretSigning = _hmacSha256(secretService, 'tc3_request');
    final String signature = Hmac(
      sha256,
      secretSigning,
    ).convert(utf8.encode(stringToSign)).toString();

    return <String, String>{
      'Authorization':
          '$algorithm Credential=$secretId/$credentialScope, '
          'SignedHeaders=content-type;host, Signature=$signature',
      'Content-Type': 'application/json; charset=utf-8',
      'Host': host,
      'X-TC-Action': 'SentenceRecognition',
      'X-TC-Version': '2019-06-14',
      'X-TC-Timestamp': '$timestamp',
      'X-TC-Region': 'ap-shanghai',
    };
  }

  List<int> _hmacSha256(List<int> key, String value) {
    return Hmac(sha256, key).convert(utf8.encode(value)).bytes;
  }

  Object? _normalizeTencentSentenceResponse(Object? data, int offsetMs) {
    if (data is! Map<String, dynamic>) {
      return null;
    }
    final Object? rawResponse = data['Response'];
    if (rawResponse is! Map<String, dynamic>) {
      return null;
    }
    final Object? error = rawResponse['Error'];
    if (error is Map<String, dynamic>) {
      final String code = error['Code'] as String? ?? 'Unknown';
      final String message = error['Message'] as String? ?? '';
      throw StateError('腾讯云 ASR 失败：$code $message');
    }

    final List<Map<String, Object?>> words =
        (rawResponse['WordList'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map((Map<String, dynamic> word) {
              final String text = (word['Word'] as String? ?? '').trim();
              final int? startMs = _intMs(word['StartTime']);
              final int? endMs = _intMs(word['EndTime']);
              if (text.isEmpty ||
                  startMs == null ||
                  endMs == null ||
                  endMs <= startMs) {
                return null;
              }
              return <String, Object?>{
                'text': text,
                'startMs': startMs + offsetMs,
                'endMs': endMs + offsetMs,
              };
            })
            .whereType<Map<String, Object?>>()
            .toList(growable: false);
    if (words.isEmpty) {
      return <String, Object?>{
        'version': 1,
        'language': 'en',
        'lines': const <Object?>[],
      };
    }

    return <String, Object?>{
      'version': 1,
      'language': 'en',
      'lines': _tencentLinesFromWords(words),
    };
  }

  List<Map<String, Object?>> _tencentLinesFromWords(
    List<Map<String, Object?>> words,
  ) {
    final List<Map<String, Object?>> lines = <Map<String, Object?>>[];
    List<Map<String, Object?>> currentTokens = <Map<String, Object?>>[];
    for (final Map<String, Object?> word in words) {
      currentTokens.add(word);
      if (_isSentenceBoundary(word['text'] as String? ?? '')) {
        _appendTencentLine(lines, currentTokens);
        currentTokens.clear();
      } else if (_shouldSplitTencentLine(currentTokens)) {
        final int phraseBreak = currentTokens.lastIndexWhere(
          (Map<String, Object?> token) =>
              _isPhraseBoundary(token['text'] as String? ?? ''),
        );
        if (phraseBreak >= 0) {
          _appendTencentLine(lines, currentTokens.sublist(0, phraseBreak + 1));
          currentTokens = currentTokens.sublist(phraseBreak + 1);
        } else {
          _appendTencentLine(lines, currentTokens);
          currentTokens.clear();
        }
      }
    }
    _appendTencentLine(lines, currentTokens);
    return lines;
  }

  bool _shouldSplitTencentLine(List<Map<String, Object?>> tokens) {
    if (tokens.length >= _maxTencentLineWords) {
      return true;
    }
    return _intMs(tokens.last['endMs'])! - _intMs(tokens.first['startMs'])! >=
        _maxTencentLineMs;
  }

  void _appendTencentLine(
    List<Map<String, Object?>> lines,
    List<Map<String, Object?>> tokens,
  ) {
    if (tokens.isEmpty) {
      return;
    }
    final List<Map<String, Object?>> lineWords = tokens
        .map((Map<String, Object?> token) {
          final String text = _stripWordPunctuation(
            token['text'] as String? ?? '',
          );
          if (text.isEmpty) {
            return null;
          }
          return <String, Object?>{...token, 'text': text};
        })
        .whereType<Map<String, Object?>>()
        .toList(growable: false);
    if (lineWords.isEmpty) {
      return;
    }
    lines.add(<String, Object?>{
      'startMs': tokens.first['startMs'],
      'endMs': tokens.last['endMs'],
      'english': _joinTencentWords(tokens),
      'chinese': '',
      'words': lineWords,
    });
  }

  String _joinTencentWords(List<Map<String, Object?>> words) {
    final StringBuffer buffer = StringBuffer();
    for (final Map<String, Object?> word in words) {
      final String text = (word['text'] as String? ?? '').trim();
      if (text.isEmpty) {
        continue;
      }
      if (buffer.isEmpty || _isPunctuationOnly(text)) {
        buffer.write(text);
      } else {
        buffer.write(' $text');
      }
    }
    return buffer.toString().trim();
  }

  bool _isSentenceBoundary(String value) {
    final String text = value.trim();
    return text == '.' ||
        text == '?' ||
        text == '!' ||
        text == '。' ||
        text == '？' ||
        text == '！' ||
        text.endsWith('.') ||
        text.endsWith('?') ||
        text.endsWith('!');
  }

  bool _isPunctuationOnly(String value) {
    return RegExp(r'^[,.!?;:]+$').hasMatch(value.trim());
  }

  bool _isPhraseBoundary(String value) {
    final String text = value.trim();
    return text == ',' ||
        text == ';' ||
        text == ':' ||
        text.endsWith(',') ||
        text.endsWith(';') ||
        text.endsWith(':');
  }

  String _stripWordPunctuation(String value) {
    return value.trim().replaceAll(RegExp(r'^[^\w]+|[^\w]+$'), '');
  }

  int? _intMs(Object? value) {
    if (value is num) {
      return value.round();
    }
    return null;
  }

  Object? _normalizeResponse(Object? data) {
    if (data is! Map<String, dynamic>) {
      return null;
    }
    if (data['lines'] is List<dynamic>) {
      return data;
    }

    final String chatText = _chatCompletionText(data);
    if (chatText.isNotEmpty) {
      final Object? chatJson = _decodeJsonObject(chatText);
      if (chatJson is Map<String, dynamic> &&
          chatJson['lines'] is List<dynamic>) {
        return chatJson;
      }
      return <String, Object?>{
        'version': 1,
        'language': '',
        'lines': <Map<String, Object?>>[
          <String, Object?>{
            'startMs': 0,
            'endMs': 1000,
            'english': chatText,
            'chinese': '',
            'words': const <Object?>[],
          },
        ],
      };
    }

    final List<dynamic> segments =
        data['segments'] as List<dynamic>? ?? <dynamic>[];
    if (segments.isEmpty) {
      return null;
    }

    return <String, Object?>{
      'version': 1,
      'language': data['language'] as String? ?? '',
      'lines': segments
          .whereType<Map<String, dynamic>>()
          .map(_segmentToLine)
          .whereType<Map<String, Object?>>()
          .toList(growable: false),
    };
  }

  Map<String, Object?>? _segmentToLine(Map<String, dynamic> segment) {
    final int? startMs = _secondsToMs(segment['start']);
    final int? endMs = _secondsToMs(segment['end']);
    final String english = (segment['text'] as String? ?? '').trim();
    if (startMs == null ||
        endMs == null ||
        endMs <= startMs ||
        english.isEmpty) {
      return null;
    }
    return <String, Object?>{
      'startMs': startMs,
      'endMs': endMs,
      'english': english,
      'chinese': '',
      'words': (segment['words'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map((Map<String, dynamic> word) {
            final int? wordStartMs = _secondsToMs(word['start']);
            final int? wordEndMs = _secondsToMs(word['end']);
            final String text =
                (word['word'] as String? ?? word['text'] as String? ?? '')
                    .trim();
            if (text.isEmpty ||
                wordStartMs == null ||
                wordEndMs == null ||
                wordEndMs <= wordStartMs) {
              return null;
            }
            return <String, Object?>{
              'text': text,
              'startMs': wordStartMs,
              'endMs': wordEndMs,
              'confidence': (word['confidence'] ?? word['probability']) as num?,
            };
          })
          .whereType<Map<String, Object?>>()
          .toList(growable: false),
    };
  }

  List<Map<String, Object?>> _linesFromNormalized(Object? data) {
    if (data is! Map<String, dynamic>) {
      return const <Map<String, Object?>>[];
    }
    return (data['lines'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(Map<String, Object?>.from)
        .toList(growable: false);
  }

  int _currentMs(Object? data, int fallbackMs) {
    if (data is! Map<String, dynamic>) {
      return fallbackMs;
    }
    int currentMs = fallbackMs;
    final List<dynamic> lines =
        data['lines'] as List<dynamic>? ?? const <dynamic>[];
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
      return chunks.first.offsetMs + _chunkMs;
    }
    final int stepMs =
        chunks.last.offsetMs - chunks[chunks.length - 2].offsetMs;
    return chunks.last.offsetMs + stepMs;
  }

  Object? _offsetNormalized(Object? data, int offsetMs) {
    if (offsetMs == 0 || data is! Map<String, dynamic>) {
      return data;
    }
    return <String, Object?>{
      ...data,
      'lines': (data['lines'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map((Map<String, dynamic> line) {
            return <String, Object?>{
              ...line,
              'startMs': (line['startMs'] as int? ?? 0) + offsetMs,
              'endMs': (line['endMs'] as int? ?? 0) + offsetMs,
              'words': (line['words'] as List<dynamic>? ?? const <dynamic>[])
                  .whereType<Map<String, dynamic>>()
                  .map(
                    (Map<String, dynamic> word) => <String, Object?>{
                      ...word,
                      'startMs': (word['startMs'] as int? ?? 0) + offsetMs,
                      'endMs': (word['endMs'] as int? ?? 0) + offsetMs,
                    },
                  )
                  .toList(growable: false),
            };
          })
          .toList(growable: false),
    };
  }

  int? _secondsToMs(Object? value) {
    if (value is num) {
      return (value * 1000).round();
    }
    return null;
  }

  bool _usesMimoChatAsr(LearningSettingsState settings) {
    return settings.asrProvider == 'MiMo Token Plan' ||
        settings.asrModel.toLowerCase().startsWith('mimo-v2.5-asr');
  }

  bool _usesAlibabaCloudAsr(LearningSettingsState settings) {
    return settings.asrProvider == '阿里云百炼' ||
        settings.asrProvider == 'Alibaba Cloud';
  }

  bool _usesTencentCloudAsr(LearningSettingsState settings) {
    return settings.asrProvider == '腾讯云' ||
        settings.asrProvider == 'Tencent Cloud';
  }

  String _chatCompletionText(Map<String, dynamic> data) {
    final List<dynamic> choices =
        data['choices'] as List<dynamic>? ?? const <dynamic>[];
    if (choices.isEmpty) {
      return '';
    }
    final Object? firstChoice = choices.first;
    if (firstChoice is! Map<String, dynamic>) {
      return '';
    }
    final Object? message = firstChoice['message'];
    if (message is! Map<String, dynamic>) {
      return '';
    }
    final Object? content = message['content'];
    if (content is String) {
      return content.trim();
    }
    return '';
  }

  Object? _decodeJsonObject(String value) {
    final int start = value.indexOf('{');
    final int end = value.lastIndexOf('}');
    if (start < 0 || end <= start) {
      return null;
    }
    try {
      return jsonDecode(value.substring(start, end + 1));
    } catch (_) {
      return null;
    }
  }

  String _dioErrorMessage(DioException error) {
    final int? statusCode = error.response?.statusCode;
    final Object? data = error.response?.data;
    final String text = data == null ? error.message ?? '' : data.toString();
    final String safeText = text.length > 160 ? text.substring(0, 160) : text;
    return statusCode == null ? safeText : 'HTTP $statusCode $safeText';
  }

  Future<List<AsrAudioChunk>> _prepareAudioChunks(File file) async {
    if (prepareAudioChunksOverride != null) {
      return prepareAudioChunksOverride!(file);
    }
    if (prepareAudioOverride != null) {
      return <AsrAudioChunk>[
        AsrAudioChunk(file: await prepareAudioOverride!(file), offsetMs: 0),
      ];
    }
    if (Platform.isAndroid) {
      final List<dynamic>? chunks = await _audioToolsChannel
          .invokeMethod<List<dynamic>>('splitAudio', <String, Object?>{
            'sourcePath': file.path,
            'chunkMs': _chunkMs,
          });
      return (chunks ?? const <dynamic>[])
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (Map<dynamic, dynamic> chunk) => AsrAudioChunk(
              file: File(chunk['path'] as String),
              offsetMs: chunk['offsetMs'] as int,
            ),
          )
          .toList(growable: false);
    }
    final String? ffmpeg = await findDesktopFfmpeg();
    if (ffmpeg == null) {
      throw StateError('应用内置音频组件缺失或无法运行，请重新安装最新版本。');
    }
    final Directory dir = await Directory.systemTemp.createTemp('cle_asr_');
    final ProcessResult result = await Process.run(ffmpeg, <String>[
      '-y',
      '-i',
      file.path,
      '-vn',
      '-ac',
      '1',
      '-ar',
      '16000',
      '-b:a',
      '24k',
      '-f',
      'segment',
      '-segment_time',
      '${_chunkMs ~/ 1000}',
      '-reset_timestamps',
      '1',
      '${dir.path}${Platform.pathSeparator}chunk_%05d.m4a',
    ]);
    final List<FileSystemEntity> files = dir.listSync()
      ..sort(
        (FileSystemEntity a, FileSystemEntity b) => a.path.compareTo(b.path),
      );
    final List<File> chunks = files.whereType<File>().toList(growable: false);
    if (result.exitCode != 0 || chunks.isEmpty) {
      dir.deleteSync(recursive: true);
      throw StateError('音频提取失败：${result.stderr}');
    }
    return <AsrAudioChunk>[
      for (int index = 0; index < chunks.length; index += 1)
        AsrAudioChunk(file: chunks[index], offsetMs: index * _chunkMs),
    ];
  }

  void deleteTemporaryAudioChunks(List<AsrAudioChunk> chunks) {
    final Set<String> parents = chunks
        .map((AsrAudioChunk chunk) => chunk.file.parent.path)
        .where((String path) => _fileName(path).startsWith('cle_asr_'))
        .toSet();
    for (final String parent in parents) {
      try {
        Directory(parent).deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  String _fileName(String path) {
    final int slash = path.lastIndexOf('/') + 1;
    final int backslash = path.lastIndexOf(String.fromCharCode(92)) + 1;
    final int index = slash > backslash ? slash : backslash;
    return index <= 0 ? path : path.substring(index);
  }

  String _mimeType(String path) {
    final String lower = path.toLowerCase();
    if (lower.endsWith('.mp3')) {
      return 'audio/mpeg';
    }
    if (lower.endsWith('.wav')) {
      return 'audio/wav';
    }
    if (lower.endsWith('.m4a') || lower.endsWith('.mp4')) {
      return 'audio/mp4';
    }
    if (lower.endsWith('.webm')) {
      return 'audio/webm';
    }
    if (lower.endsWith('.aac')) {
      return 'audio/aac';
    }
    if (lower.endsWith('.flac')) {
      return 'audio/flac';
    }
    if (lower.endsWith('.ogg')) {
      return 'audio/ogg';
    }
    return 'audio/mp4';
  }

  String _tencentVoiceFormat(String path) {
    final String lower = path.toLowerCase();
    if (lower.endsWith('.wav')) {
      return 'wav';
    }
    if (lower.endsWith('.mp3')) {
      return 'mp3';
    }
    if (lower.endsWith('.m4a') || lower.endsWith('.mp4')) {
      return 'm4a';
    }
    if (lower.endsWith('.aac')) {
      return 'aac';
    }
    if (lower.endsWith('.pcm')) {
      return 'pcm';
    }
    return 'wav';
  }
}
