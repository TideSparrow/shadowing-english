import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:common_learn_english/features/player/data/tencent_pronunciation_service.dart';
import 'package:common_learn_english/features/player/domain/pronunciation_assessment.dart';
import 'package:flutter_test/flutter_test.dart';

const PronunciationCredentials _credentials = PronunciationCredentials(
  appId: '1250000000',
  secretId: 'test-id',
  secretKey: 'test-key',
);
const PronunciationAssessmentTarget _target = PronunciationAssessmentTarget(
  text: "Let's take a break & listen.",
  videoSource: '/local/fixture.mp4',
  startMs: 600,
  endMs: 1551,
  videoDuration: Duration(seconds: 5),
);

class _FakeSocket implements PronunciationAssessmentSocket {
  final StreamController<Object?> controller = StreamController<Object?>();
  final List<Object> sent = <Object>[];
  int closes = 0;

  @override
  Stream<Object?> get messages => controller.stream;

  @override
  void add(Object data) {
    sent.add(data);
    if (data is String) {
      controller
        ..add(
          jsonEncode(<String, Object?>{
            'code': 0,
            'result': jsonEncode(<String, Object?>{
              'SuggestedScore': 68.5,
              'PronAccuracy': 80,
              'PronFluency': 0.9,
              'PronCompletion': 0.75,
            }),
          }),
        )
        ..add(jsonEncode(<String, Object?>{'code': 0, 'final': 1}));
    }
  }

  @override
  Future<void> close() async {
    closes++;
    if (!controller.isClosed) await controller.close();
  }
}

Pcm16MonoAudio _speech({int length = 16000}) {
  final Uint8List bytes = Uint8List(length);
  final ByteData data = ByteData.sublistView(bytes);
  for (int i = 0; i < bytes.length ~/ 2; i++) {
    data.setInt16(i * 2, i.isEven ? 4000 : -4000, Endian.little);
  }
  return Pcm16MonoAudio(bytes: bytes, sampleRate: 16000);
}

void main() {
  test('signs raw query values and uses WSS', () {
    final Uri uri = TencentPronunciationService().createSignedUri(
      credentials: _credentials,
      target: _target,
      secretKey: ' test-key ',
      timestamp: 1000000,
      nonce: '123',
      voiceId: 'review-test',
    );
    expect(uri.scheme, 'wss');
    expect(uri.host, 'soe.cloud.tencent.com');
    expect(uri.queryParameters['ref_text'], _target.text);
    expect(uri.queryParameters['signature'], '3d9CVBSAw76lWim6Gg+liYZSiB4=');
  });

  test('retains the last score until final frame without a result', () async {
    final _FakeSocket socket = _FakeSocket();
    final TencentPronunciationService service = TencentPronunciationService(
      connector: (Uri uri) async {
        expect(uri.scheme, 'wss');
        scheduleMicrotask(() => socket.controller.add('{"code":0}'));
        return socket;
      },
    );
    final PronunciationAssessmentResult result = await service.evaluate(
      credentials: _credentials,
      target: _target,
      audio: _speech(),
    );
    expect(result.suggestedScore, 68.5);
    expect(result.completion, 0.75);
    expect(socket.sent.whereType<Uint8List>(), hasLength(1));
    expect(socket.sent.whereType<String>().single, '{"type":"end"}');
    expect(socket.closes, greaterThanOrEqualTo(1));
  });

  test('rejects odd PCM byte count before connecting', () async {
    bool connected = false;
    final TencentPronunciationService service = TencentPronunciationService(
      connector: (_) async {
        connected = true;
        return _FakeSocket();
      },
    );
    await expectLater(
      service.evaluate(
        credentials: _credentials,
        target: _target,
        audio: _speech(length: 16001),
      ),
      throwsA(isA<PronunciationAssessmentException>()),
    );
    expect(connected, isFalse);
  });

  test(
    'cancelling while connecting closes the late socket without audio',
    () async {
      final Completer<PronunciationAssessmentSocket> pending =
          Completer<PronunciationAssessmentSocket>();
      final _FakeSocket socket = _FakeSocket();
      Future<void> Function()? cancel;
      final TencentPronunciationService service = TencentPronunciationService(
        connector: (_) => pending.future,
        nonce: () => '123',
      );
      final Future<PronunciationAssessmentResult> evaluation = service.evaluate(
        credentials: _credentials,
        target: _target,
        audio: _speech(),
        onCancelAvailable: (Future<void> Function() callback) =>
            cancel = callback,
      );
      final Future<void> failure = expectLater(
        evaluation,
        throwsA(isA<PronunciationAssessmentException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cancel, isNotNull);
      await cancel!();
      pending.complete(socket);
      await Future<void>.delayed(Duration.zero);
      await failure;
      expect(socket.sent, isEmpty);
      expect(socket.closes, greaterThanOrEqualTo(1));
    },
  );
}
