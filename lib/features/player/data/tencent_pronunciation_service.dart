import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../domain/pronunciation_assessment.dart';

abstract interface class PronunciationAssessmentSocket {
  Stream<Object?> get messages;
  void add(Object data);
  Future<void> close();
}

typedef PronunciationSocketConnector =
    Future<PronunciationAssessmentSocket> Function(Uri uri);

class PronunciationAssessmentException implements Exception {
  const PronunciationAssessmentException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TencentPronunciationService {
  TencentPronunciationService({
    PronunciationSocketConnector? connector,
    DateTime Function()? now,
    String Function()? nonce,
    String Function()? voiceId,
  }) : _connector = connector ?? _connect,
       _now = now ?? DateTime.now,
       _nonce = nonce ?? _createNonce,
       _voiceId = voiceId ?? _createVoiceId;

  static const String host = 'soe.cloud.tencent.com';
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration resultTimeout = Duration(seconds: 45);

  final PronunciationSocketConnector _connector;
  final DateTime Function() _now;
  final String Function() _nonce;
  final String Function() _voiceId;

  Uri createSignedUri({
    required PronunciationCredentials credentials,
    required PronunciationAssessmentTarget target,
    required String secretKey,
    required int timestamp,
    required String nonce,
    required String voiceId,
  }) {
    final Map<String, String> parameters = <String, String>{
      'secretid': credentials.secretId.trim(),
      'timestamp': '$timestamp',
      'expired': '${timestamp + 1800}',
      'nonce': nonce,
      'server_engine_type': '16k_en',
      'voice_id': voiceId,
      'voice_format': '0',
      'eval_mode': '${target.evaluationMode}',
      'score_coeff': '4.0',
      'ref_text': target.text.trim(),
      'rec_mode': '1',
      'sentence_info_enabled': '0',
    };
    final List<String> keys = parameters.keys.toList()..sort();
    final String path = '/soe/api/${credentials.appId.trim()}';
    final String canonical = keys
        .map((String key) => '$key=${parameters[key]}')
        .join('&');
    final String signingText = 'soe.cloud.tencent.com$path?$canonical';
    final List<int> digest = Hmac(
      sha1,
      utf8.encode(secretKey.trim()),
    ).convert(utf8.encode(signingText)).bytes;
    parameters['signature'] = base64.encode(digest);
    return Uri(
      scheme: 'wss',
      host: host,
      path: path,
      queryParameters: parameters,
    );
  }

  Future<PronunciationAssessmentResult> evaluate({
    required PronunciationCredentials credentials,
    required PronunciationAssessmentTarget target,
    required Pcm16MonoAudio audio,
    void Function(Future<void> Function() cancel)? onCancelAvailable,
  }) async {
    if (!credentials.isComplete) {
      throw const PronunciationAssessmentException('请先在设置中配置跟读评测密钥。');
    }
    final String? targetError = target.validationError;
    if (targetError != null) {
      throw PronunciationAssessmentException(targetError);
    }
    if (audio.sampleRate != Pcm16MonoAudio.expectedSampleRate ||
        audio.bytes.isEmpty ||
        audio.bytes.length.isOdd ||
        audio.durationMs <= 0 ||
        audio.durationMs > 60000) {
      throw const PronunciationAssessmentException('录音长度或音频格式无效，请重新录制。');
    }
    if (!audio.hasSpeechEnergy) {
      throw const PronunciationAssessmentException('未检测到有效语音，请靠近麦克风后重录。');
    }

    final DateTime now = _now();
    final Uri uri = createSignedUri(
      credentials: credentials,
      target: target,
      secretKey: credentials.secretKey,
      timestamp: now.millisecondsSinceEpoch ~/ 1000,
      nonce: _nonce(),
      voiceId: _voiceId(),
    );
    bool cancelled = false;
    final Completer<void> cancelSignal = Completer<void>();
    PronunciationAssessmentSocket? socket;
    onCancelAvailable?.call(() async {
      cancelled = true;
      await socket?.close();
      if (!cancelSignal.isCompleted) cancelSignal.complete();
    });
    late final PronunciationAssessmentSocket connectedSocket;
    try {
      final Future<PronunciationAssessmentSocket> connection = _connector(uri)
          .timeout(connectTimeout)
          .then((PronunciationAssessmentSocket connected) async {
            socket = connected;
            if (cancelled) {
              await connected.close();
              throw const PronunciationAssessmentException('评测已取消。');
            }
            return connected;
          });
      connectedSocket = await Future.any<PronunciationAssessmentSocket>(
        <Future<PronunciationAssessmentSocket>>[
          connection,
          cancelSignal.future.then<PronunciationAssessmentSocket>(
            (_) => throw const PronunciationAssessmentException('评测已取消。'),
          ),
        ],
      );
    } catch (_) {
      if (cancelled) {
        throw const PronunciationAssessmentException('评测已取消。');
      }
      throw const PronunciationAssessmentException('连接腾讯云失败，请检查网络与评测配置。');
    }
    if (cancelled) {
      await connectedSocket.close();
      throw const PronunciationAssessmentException('评测已取消。');
    }

    final Completer<PronunciationAssessmentResult> completion =
        Completer<PronunciationAssessmentResult>();
    PronunciationAssessmentResult? latestResult;
    bool handshaken = false;
    final StreamSubscription<Object?> subscription = connectedSocket.messages
        .listen(
          (Object? message) {
            try {
              final Map<String, Object?> response = _decodeResponse(message);
              final Object? code = response['code'];
              if (code is num && code != 0) {
                _completeError(completion);
                return;
              }
              if (!handshaken) {
                if (code != 0) {
                  _completeError(completion);
                  return;
                }
                if (cancelled) {
                  _completeError(completion);
                  return;
                }
                handshaken = true;
                connectedSocket
                  ..add(audio.bytes)
                  ..add(jsonEncode(<String, String>{'type': 'end'}));
              }

              final PronunciationAssessmentResult? parsed =
                  PronunciationAssessmentResult.tryParse(
                    _decodeResultValue(response['result']),
                  );
              if (parsed != null) latestResult = parsed;
              if (response['final'] == 1) {
                final PronunciationAssessmentResult? result = latestResult;
                if (result == null) {
                  _completeError(completion);
                } else if (!completion.isCompleted) {
                  completion.complete(result);
                }
              }
            } catch (_) {
              _completeError(completion);
            }
          },
          onError: (Object _) => _completeError(completion),
          onDone: () => _completeError(completion),
          cancelOnError: true,
        );

    try {
      return await completion.future.timeout(resultTimeout);
    } on TimeoutException {
      throw const PronunciationAssessmentException('评分响应超时，请稍后重试。');
    } catch (error) {
      if (error is PronunciationAssessmentException) rethrow;
      throw const PronunciationAssessmentException('评分失败，请检查网络与腾讯云配置。');
    } finally {
      await subscription.cancel();
      await connectedSocket.close();
    }
  }

  static void _completeError(
    Completer<PronunciationAssessmentResult> completion,
  ) {
    if (!completion.isCompleted) {
      completion.completeError(
        const PronunciationAssessmentException('腾讯云未返回有效评分，请检查网络与评测配置。'),
      );
    }
  }

  static Map<String, Object?> _decodeResponse(Object? message) {
    final Object? decoded = message is String ? jsonDecode(message) : message;
    if (decoded is! Map) {
      throw const FormatException('Invalid service response');
    }
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in decoded.entries)
        if (entry.key is String) entry.key! as String: entry.value,
    };
  }

  static Object? _decodeResultValue(Object? value) {
    if (value is String) {
      try {
        return jsonDecode(value);
      } on FormatException {
        return null;
      }
    }
    return value;
  }

  static String _createNonce() =>
      (Random.secure().nextInt(0x7fffffff) + 1).toString();

  static String _createVoiceId() {
    final Random random = Random.secure();
    String bytes(int count) => List<String>.generate(
      count,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '${bytes(4)}-${bytes(2)}-4${bytes(2).substring(1)}'
        '-${(random.nextInt(64) | 0x80).toRadixString(16).padLeft(2, '0')}${bytes(1)}'
        '-${bytes(6)}';
  }

  static Future<PronunciationAssessmentSocket> _connect(Uri uri) async {
    final HttpClient client = HttpClient()..connectionTimeout = connectTimeout;
    try {
      // Ownership transfers to the wrapper, which closes the socket on release.
      // ignore: close_sinks
      final WebSocket webSocket = await WebSocket.connect(
        uri.toString(),
        customClient: client,
      ).timeout(connectTimeout);
      return _IoPronunciationAssessmentSocket(webSocket, client);
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }
}

class _IoPronunciationAssessmentSocket
    implements PronunciationAssessmentSocket {
  const _IoPronunciationAssessmentSocket(this._socket, this._client);

  final WebSocket _socket;
  final HttpClient _client;

  @override
  Stream<Object?> get messages => _socket.cast<Object?>();

  @override
  void add(Object data) => _socket.add(data);

  @override
  Future<void> close() async {
    try {
      await _socket.close();
    } finally {
      _client.close(force: true);
    }
  }
}
