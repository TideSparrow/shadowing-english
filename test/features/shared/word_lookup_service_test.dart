import 'dart:convert';

import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:common_learn_english/features/shared/data/word_lookup_service.dart';
import 'package:common_learn_english/features/shared/domain/word_lookup_entry.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('batch subtitle translation', () {
    final LearningSettingsState settings = LearningSettingsState.defaults()
        .copyWith(translationApiKey: 'test-key');

    test('one request preserves IDs and restores reordered results', () async {
      int requests = 0;
      final WordLookupService service = WordLookupService(
        httpRequestOverride:
            ({
              required BaseOptions options,
              required String method,
              required String path,
              Map<String, dynamic>? queryParameters,
              Object? data,
            }) async {
              requests += 1;
              expect(method, 'POST');
              expect(path, '/chat/completions');
              expect(options.receiveTimeout, const Duration(seconds: 90));
              final Map<String, dynamic> body = data! as Map<String, dynamic>;
              expect(body.containsKey('response_format'), isFalse);
              final List<Map<String, String>> messages =
                  body['messages'] as List<Map<String, String>>;
              expect(
                jsonDecode(messages.last['content']!),
                <Map<String, Object>>[
                  <String, Object>{'id': 0, 'text': 'Hello.'},
                  <String, Object>{'id': 1, 'text': 'Goodbye.'},
                ],
              );
              return _translationResponse(path, <Map<String, Object>>[
                <String, Object>{'id': 1, 'text': '再见。'},
                <String, Object>{'id': 0, 'text': ' 你好。 '},
              ], fenced: true);
            },
      );
      expect(
        await service.translateSentences(
          sentences: <String>['Hello.', 'Goodbye.'],
          settings: settings,
        ),
        <String>['你好。', '再见。'],
      );
      expect(requests, 1);
      expect(
        await service.translateSentences(
          sentences: <String>[],
          settings: settings,
        ),
        isEmpty,
      );
      expect(requests, 1);
    });

    final Map<String, List<Map<String, Object>>> invalid =
        <String, List<Map<String, Object>>>{
          'missing ID': <Map<String, Object>>[
            <String, Object>{'id': 0, 'text': '你好'},
          ],
          'duplicate ID': <Map<String, Object>>[
            <String, Object>{'id': 0, 'text': '你好'},
            <String, Object>{'id': 0, 'text': '再见'},
          ],
          'unknown ID': <Map<String, Object>>[
            <String, Object>{'id': 0, 'text': '你好'},
            <String, Object>{'id': 2, 'text': '再见'},
          ],
          'empty text': <Map<String, Object>>[
            <String, Object>{'id': 0, 'text': '你好'},
            <String, Object>{'id': 1, 'text': ' '},
          ],
        };
    for (final MapEntry<String, List<Map<String, Object>>> entry
        in invalid.entries) {
      test(
        'rejects ${entry.key} without assigning subtitles by position',
        () async {
          final WordLookupService service = WordLookupService(
            httpRequestOverride:
                ({
                  required BaseOptions options,
                  required String method,
                  required String path,
                  Map<String, dynamic>? queryParameters,
                  Object? data,
                }) async => _translationResponse(path, entry.value),
          );
          await expectLater(
            service.translateSentences(
              sentences: <String>['Hello.', 'Goodbye.'],
              settings: settings,
            ),
            throwsFormatException,
          );
        },
      );
    }
    test(
      'rejects truncated output even if JSON happens to be complete',
      () async {
        final WordLookupService service = WordLookupService(
          httpRequestOverride:
              ({
                required BaseOptions options,
                required String method,
                required String path,
                Map<String, dynamic>? queryParameters,
                Object? data,
              }) async => _translationResponse(path, <Map<String, Object>>[
                <String, Object>{'id': 0, 'text': '你好'},
              ], finishReason: 'length'),
        );
        await expectLater(
          service.translateSentences(
            sentences: <String>['Hello.'],
            settings: settings,
          ),
          throwsFormatException,
        );
      },
    );
  });

  test('preserves the full lookup result when sent between windows', () {
    const WordLookupEntry entry = WordLookupEntry(
      word: 'Guess',
      phonetic: '/ɡes/',
      type: 'verb',
      definitionEn: 'To answer without knowing all the facts.',
      usageEn: 'Used when an answer is uncertain.',
      exampleSentenceEn: 'Can you guess who called?',
      definitionCn: '猜测；猜想',
      sourceLabel: 'API',
      contextMeaningCn: '猜一猜',
    );

    final WordLookupEntry restored = WordLookupEntry.fromJson(entry.toJson());

    expect(restored.word, entry.word);
    expect(restored.phonetic, entry.phonetic);
    expect(restored.type, entry.type);
    expect(restored.definitionEn, entry.definitionEn);
    expect(restored.usageEn, entry.usageEn);
    expect(restored.exampleSentenceEn, entry.exampleSentenceEn);
    expect(restored.definitionCn, entry.definitionCn);
    expect(restored.sourceLabel, entry.sourceLabel);
    expect(restored.contextMeaningCn, entry.contextMeaningCn);
  });

  test('uses api result first when api key is configured', () async {
    int remoteCallCount = 0;
    final WordLookupService service = WordLookupService(
      remoteLookupOverride:
          ({
            required String rawWord,
            String? contextSentence,
            required LearningSettingsState settings,
          }) async {
            remoteCallCount += 1;
            return const WordLookupEntry(
              word: 'Sanctuary',
              phonetic: '/test/',
              type: 'noun',
              definitionEn: 'API definition',
              usageEn: 'API usage',
              exampleSentenceEn: 'This is an API example sentence.',
              definitionCn: 'API 中文',
              sourceLabel: 'API',
            );
          },
    );

    final WordLookupEntry entry = await service.lookupWord(
      rawWord: 'sanctuary',
      contextSentence: 'They found a sanctuary nearby.',
      settings: LearningSettingsState.defaults().copyWith(
        translationProvider: 'OpenAI',
        translationApiKey: 'demo-key',
        translationBaseUrl: 'https://api.openai.com/v1',
        translationModel: 'gpt-4o-mini',
      ),
    );

    expect(remoteCallCount, 1);
    expect(entry.definitionEn, 'API definition');
    expect(entry.sourceLabel, 'API');
  });

  test('shows unavailable message when api lookup fails', () async {
    final WordLookupService service = WordLookupService(
      remoteLookupOverride:
          ({
            required String rawWord,
            String? contextSentence,
            required LearningSettingsState settings,
          }) async {
            throw Exception('boom');
          },
    );

    final WordLookupEntry entry = await service.lookupWord(
      rawWord: 'sanctuary',
      contextSentence: 'They found a sanctuary nearby.',
      settings: LearningSettingsState.defaults().copyWith(
        translationProvider: 'OpenAI',
        translationApiKey: 'demo-key',
        translationBaseUrl: 'https://api.openai.com/v1',
        translationModel: 'gpt-4o-mini',
      ),
    );

    expect(entry.sourceLabel, '未配置');
    expect(entry.definitionCn, '翻译服务当前不可用，请检查 API 配置后重试。');
  });

  test('shows setup message when api key is missing', () async {
    int remoteCallCount = 0;
    final WordLookupService service = WordLookupService(
      remoteLookupOverride:
          ({
            required String rawWord,
            String? contextSentence,
            required LearningSettingsState settings,
          }) async {
            remoteCallCount += 1;
            return const WordLookupEntry(
              word: 'Sanctuary',
              phonetic: '/test/',
              type: 'noun',
              definitionEn: 'API definition',
              usageEn: 'API usage',
              exampleSentenceEn: 'This is an API example sentence.',
              definitionCn: 'API 中文',
              sourceLabel: 'API',
            );
          },
    );

    final WordLookupEntry entry = await service.lookupWord(
      rawWord: 'sanctuary',
      contextSentence: 'They found a sanctuary nearby.',
      settings: LearningSettingsState.defaults(),
    );

    expect(remoteCallCount, 0);
    expect(entry.sourceLabel, '未配置');
    expect(entry.definitionCn, '请先在设置中配置可用的翻译 API。');
  });

  test('uses google translate direct provider when configured', () async {
    final WordLookupService service = WordLookupService(
      httpRequestOverride:
          ({
            required BaseOptions options,
            required String method,
            required String path,
            Map<String, dynamic>? queryParameters,
            Object? data,
          }) async {
            expect(options.baseUrl, 'https://translation.googleapis.com');
            expect(method, 'POST');
            expect(path, '/language/translate/v2');
            expect(queryParameters?['q'], 'sanctuary');
            return Response<dynamic>(
              requestOptions: RequestOptions(path: path),
              data: <String, dynamic>{
                'data': <String, dynamic>{
                  'translations': <Map<String, dynamic>>[
                    <String, dynamic>{'translatedText': '避难所'},
                  ],
                },
              },
            );
          },
    );

    final WordLookupEntry entry = await service.lookupWord(
      rawWord: 'sanctuary',
      settings: LearningSettingsState.defaults().copyWith(
        translationProvider: 'Google 翻译',
        translationApiKey: 'google-key',
        translationBaseUrl: 'https://translation.googleapis.com',
        translationModel: '',
      ),
    );

    expect(entry.sourceLabel, 'Google 翻译');
    expect(entry.definitionCn, '避难所');
    expect(entry.contextMeaningCn, isNull);
    expect(entry.definitionEn, isEmpty);
  });

  test(
    'keeps generic meaning and context meaning separate for direct provider',
    () async {
      final WordLookupService service = WordLookupService(
        httpRequestOverride:
            ({
              required BaseOptions options,
              required String method,
              required String path,
              Map<String, dynamic>? queryParameters,
              Object? data,
            }) async {
              return Response<dynamic>(
                requestOptions: RequestOptions(path: path),
                data: <String, dynamic>{
                  'Data': <String, dynamic>{'Translated': '已导入'},
                },
              );
            },
      );

      final WordLookupEntry entry = await service.lookupWord(
        rawWord: 'imported',
        contextSentence: 'Hello from imported file.',
        settings: LearningSettingsState.defaults().copyWith(
          translationProvider: '阿里云翻译',
          translationApiKey: 'aliyun-key',
          translationApiSecret: 'aliyun-secret',
          translationBaseUrl: 'https://mt.cn-hangzhou.aliyuncs.com',
          translationModel: '',
        ),
      );

      expect(entry.definitionCn, '已导入');
      expect(entry.contextMeaningCn, '已导入');
      expect(entry.definitionEn, isEmpty);
    },
  );

  test(
    'ai provider returns english explanation and new example sentence',
    () async {
      final WordLookupService service = WordLookupService(
        remoteLookupOverride:
            ({
              required String rawWord,
              String? contextSentence,
              required LearningSettingsState settings,
            }) async {
              return const WordLookupEntry(
                word: 'Have',
                phonetic: '/hæv/',
                type: 'verb',
                definitionEn:
                    'Have means to own, hold, take, or experience something.',
                usageEn:
                    'Use have for possession, relationships, meals, activities, or experiences.',
                exampleSentenceEn:
                    'We usually have dinner around seven in the evening.',
                definitionCn: '有；拥有；进行',
                sourceLabel: 'API',
              );
            },
      );

      final WordLookupEntry entry = await service.lookupWord(
        rawWord: 'have',
        contextSentence: 'I have two books.',
        settings: LearningSettingsState.defaults().copyWith(
          translationProvider: 'OpenAI',
          translationApiKey: 'demo-key',
          translationBaseUrl: 'https://api.openai.com/v1',
          translationModel: 'gpt-4o-mini',
        ),
      );

      expect(entry.definitionEn, contains('own, hold'));
      expect(entry.usageEn, contains('possession'));
      expect(entry.exampleSentenceEn, contains('have dinner'));
    },
  );

  test('uses baidu translate only when secret is configured', () async {
    int requestCount = 0;
    final WordLookupService service = WordLookupService(
      httpRequestOverride:
          ({
            required BaseOptions options,
            required String method,
            required String path,
            Map<String, dynamic>? queryParameters,
            Object? data,
          }) async {
            requestCount += 1;
            expect(path, '/api/trans/vip/translate');
            expect(queryParameters?['appid'], 'baidu-app-id');
            expect(queryParameters?['q'], 'chaotic');
            return Response<dynamic>(
              requestOptions: RequestOptions(path: path),
              data: <String, dynamic>{
                'trans_result': <Map<String, dynamic>>[
                  <String, dynamic>{'dst': '混乱的'},
                ],
              },
            );
          },
    );

    final LearningSettingsState withoutSecret = LearningSettingsState.defaults()
        .copyWith(
          translationProvider: '百度翻译',
          translationApiKey: 'baidu-app-id',
          translationBaseUrl: 'https://fanyi-api.baidu.com',
          translationModel: '',
        );
    final WordLookupEntry localEntry = await service.lookupWord(
      rawWord: 'chaotic',
      settings: withoutSecret,
    );
    expect(requestCount, 0);
    expect(localEntry.sourceLabel, '未配置');
    expect(localEntry.definitionCn, '请先在设置中配置可用的翻译 API。');

    final WordLookupEntry entry = await service.lookupWord(
      rawWord: 'chaotic',
      settings: withoutSecret.copyWith(translationApiSecret: 'baidu-secret'),
    );
    expect(requestCount, 1);
    expect(entry.sourceLabel, '百度翻译');
    expect(entry.definitionCn, '混乱的');
    expect(entry.contextMeaningCn, isNull);
    expect(entry.definitionEn, isEmpty);
  });
}

Response<dynamic> _translationResponse(
  String path,
  List<Map<String, Object>> translations, {
  bool fenced = false,
  String finishReason = 'stop',
}) {
  final String content = jsonEncode(<String, Object>{
    'translations': translations,
  });
  return Response<dynamic>(
    requestOptions: RequestOptions(path: path),
    data: <String, Object>{
      'choices': <Map<String, Object>>[
        <String, Object>{
          'finish_reason': finishReason,
          'message': <String, String>{
            'content': fenced ? '```json\n$content\n```' : content,
          },
        },
      ],
    },
  );
}
