import 'dart:convert';
import 'dart:typed_data';

import 'package:common_learn_english/features/player/data/doubao_pronunciation_service.dart';
import 'package:common_learn_english/features/player/domain/pronunciation_assessment.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const PronunciationAssessmentTarget _target = PronunciationAssessmentTarget(
  text: 'Alone and happy.',
  videoSource: '/local/video.mp4',
  startMs: 0,
  endMs: 2000,
  videoDuration: Duration(seconds: 10),
);

Pcm16MonoAudio _speech(int amplitude) {
  final Uint8List bytes = Uint8List(16000);
  final ByteData data = ByteData.sublistView(bytes);
  for (int i = 0; i < bytes.length ~/ 2; i++) {
    data.setInt16(i * 2, i.isEven ? amplitude : -amplitude, Endian.little);
  }
  return Pcm16MonoAudio(bytes: bytes, sampleRate: 16000);
}

void main() {
  test(
    'each request sends reference and current recording and returns guidance',
    () async {
      final Dio dio = Dio();
      final DoubaoPronunciationService service = DoubaoPronunciationService(
        dio: dio,
      );
      addTearDown(service.close);
      final List<RequestOptions> requests = <RequestOptions>[];
      const String guidance = '快乐这个词可以再练一遍，嘴巴再张开一点。';
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                requests.add(options);
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: options,
                    data: <String, Object>{
                      'choices': <Object>[
                        <String, Object>{
                          'finish_reason': 'stop',
                          'message': <String, String>{'content': guidance},
                        },
                      ],
                    },
                  ),
                );
              },
        ),
      );
      final Pcm16MonoAudio reference = _speech(4000);
      final List<Pcm16MonoAudio> recordings = <Pcm16MonoAudio>[
        _speech(4500),
        _speech(4900),
      ];
      for (final Pcm16MonoAudio recording in recordings) {
        final PronunciationAssessmentResult result = await service.evaluate(
          credentials: const PronunciationCredentials(apiKey: ' test-key '),
          target: _target,
          audio: recording,
          reference: reference,
        );
        expect(result.guidance, guidance);
        expect(result.suggestedScore, isNull);
      }
      expect(requests, hasLength(2));
      for (final (int index, RequestOptions request) in requests.indexed) {
        expect(request.uri.host, 'ark.cn-beijing.volces.com');
        expect(request.uri.path, '/api/v3/chat/completions');
        expect(request.headers['Authorization'], 'Bearer test-key');
        final Map<String, Object> payload = request.data as Map<String, Object>;
        expect(payload['model'], DoubaoPronunciationService.model);
        expect(payload['thinking'], <String, String>{'type': 'disabled'});
        final List<Map<String, Object>> messages =
            (payload['messages']! as List<Object>).cast<Map<String, Object>>();
        expect(
          messages.map((Map<String, Object> message) => message['role']),
          <String>['system', 'user'],
        );
        final List<Map<String, Object>> content =
            (messages.last['content']! as List<Object>)
                .cast<Map<String, Object>>();
        expect(content.first['text'], contains(_target.text));
        final List<Map<String, Object>> audioBlocks = content
            .where((Map<String, Object> item) => item['type'] == 'input_audio')
            .toList();
        expect(audioBlocks, hasLength(2));
        final List<Pcm16MonoAudio> expectedAudio = <Pcm16MonoAudio>[
          reference,
          recordings[index],
        ];
        for (final (int clipIndex, Map<String, Object> block)
            in audioBlocks.indexed) {
          final Map<String, String> audio =
              block['input_audio']! as Map<String, String>;
          expect(audio['format'], 'wav');
          expect(
            base64Decode(audio['data']!),
            expectedAudio[clipIndex].toWav(),
          );
        }
      }
    },
  );
}
