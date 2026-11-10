import 'dart:convert';

import 'package:common_learn_english/features/lessons/data/lesson_service.dart';
import 'package:common_learn_english/features/lessons/domain/intensive_lesson.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'lesson_fixture.dart';

void main() {
  final LearningSettingsState settings = LearningSettingsState.defaults()
      .copyWith(
        translationApiKey: 'test-only',
        translationModel: 'test-model',
        translationBaseUrl: 'https://lesson.invalid/v1',
        translationProvider: 'OpenAI',
      );

  test('usage metadata supports missing fields and never invents counts', () {
    expect(LessonTokenUsage.fromProvider(null), isNull);
    expect(
      LessonTokenUsage.fromProvider(<String, Object>{'prompt_tokens': '123'}),
      isNull,
    );
    final LessonTokenUsage partial = LessonTokenUsage.fromProvider(
      <String, int>{'total_tokens': 42},
    )!;
    expect(partial.total, 42);
    expect(partial.input, isNull);
    expect(partial.output, isNull);
    expect(
      LessonTokenUsage.fromProvider(<String, int>{
        'input_tokens': 10,
        'output_tokens': 4,
      })!.total,
      14,
    );
    expect(fixtureLesson().usage, isNull);
  });

  test(
    'unconfigured and direct translation providers never issue HTTP requests',
    () async {
      final Dio dio = Dio();
      int requests = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                requests++;
                handler.reject(DioException(requestOptions: options));
              },
        ),
      );
      final LessonService service = LessonService(client: dio);
      for (final LearningSettingsState unavailable in <LearningSettingsState>[
        LearningSettingsState.defaults(),
        settings.copyWith(translationProvider: 'Google 翻译'),
      ]) {
        await expectLater(
          service.generate(
            source: lessonSource,
            settings: unavailable,
            cancelToken: CancelToken(),
          ),
          throwsFormatException,
        );
      }
      expect(requests, 0);
    },
  );

  test(
    'one request carries context and yields three cards with bilingual scripts',
    () async {
      final Dio dio = Dio();
      int requests = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                requests++;
                expect(
                  options.path,
                  'https://lesson.invalid/v1/chat/completions',
                );
                final Map<String, dynamic> request =
                    options.data as Map<String, dynamic>;
                final List<Map<String, String>> messages =
                    request['messages'] as List<Map<String, String>>;
                expect(
                  messages.last['content'],
                  contains('Breakfast is ready.'),
                );
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: options,
                    data: <String, Object>{
                      'model': 'test-reported-model',
                      'usage': <String, int>{
                        'prompt_tokens': 123,
                        'completion_tokens': 45,
                        'total_tokens': 168,
                      },
                      'choices': <Object>[
                        <String, Object>{
                          'finish_reason': 'stop',
                          'message': <String, String>{
                            'content':
                                '```json\n${jsonEncode(lessonContent())}\n```',
                          },
                        },
                      ],
                    },
                  ),
                );
              },
        ),
      );
      final IntensiveLesson lesson = await LessonService(client: dio).generate(
        source: lessonSource,
        settings: settings,
        cancelToken: CancelToken(),
      );
      expect(requests, 1);
      expect(lesson.cards, hasLength(3));
      expect(lesson.usage!.input, 123);
      expect(lesson.usage!.output, 45);
      expect(lesson.usage!.total, 168);
      expect(lesson.model, 'test-reported-model');
      final IntensiveLesson reloaded = IntensiveLesson.fromJson(
        jsonDecode(jsonEncode(lesson.toJson())) as Map<String, dynamic>,
      );
      expect(reloaded.usage!.total, 168);
      expect(lesson.cards.last.speech.last.language, 'zh-CN');
      expect(lesson.cards.first.pattern, 'get someone');
      expect(lesson.cards.first.meaning, '去叫某人／把某人找来');
      expect(reloaded.cards.first.examples.first.situation, '饭做好了，请家人叫孩子过来');
      expect(
        IntensiveLesson.fromJson(
          jsonDecode(jsonEncode(lesson.toJson())) as Map<String, dynamic>,
        ).id,
        lesson.id,
      );
    },
  );

  test(
    'malformed card groups and truncated replies are rejected without retry',
    () async {
      final Map<String, dynamic> invalid = lessonContent();
      invalid['cards'] = <Object>[];
      expect(
        () => IntensiveLesson.fromContent(source: lessonSource, json: invalid),
        throwsFormatException,
      );
      final Dio dio = Dio();
      int requests = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                requests++;
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: options,
                    data: <String, Object>{
                      'model': 'test-reported-model',
                      'usage': <String, int>{
                        'prompt_tokens': 123,
                        'completion_tokens': 45,
                        'total_tokens': 168,
                      },
                      'choices': <Object>[
                        <String, Object>{'finish_reason': 'length'},
                      ],
                    },
                  ),
                );
              },
        ),
      );
      await expectLater(
        LessonService(client: dio).generate(
          source: lessonSource,
          settings: settings,
          cancelToken: CancelToken(),
        ),
        throwsA(
          isA<LessonGenerationException>().having(
            (LessonGenerationException e) => e.usage?.total,
            'returned token usage',
            168,
          ),
        ),
      );
      expect(requests, 1);
    },
  );

  test('new AI cards require phrase meanings and situated examples', () {
    final Map<String, dynamic> content = lessonContent();
    final List<Map<String, dynamic>> cards =
        content['cards'] as List<Map<String, dynamic>>;
    cards.first.remove('meaning');
    expect(
      () => IntensiveLesson.fromContent(
        source: lessonSource,
        json: content,
        requireTeachingFields: true,
      ),
      throwsFormatException,
    );
  });

  test('older saved lessons still open without the new teaching fields', () {
    final Map<String, dynamic> legacy = fixtureLesson().toJson();
    for (final Map<String, dynamic> card
        in legacy['cards'] as List<Map<String, dynamic>>) {
      card
        ..remove('pattern')
        ..remove('meaning');
      for (final Map<String, dynamic> example
          in card['examples'] as List<Map<String, dynamic>>) {
        example.remove('situation');
      }
    }
    legacy['imagePrompt'] = 'Legacy image prompt is ignored.';
    final IntensiveLesson lesson = IntensiveLesson.fromJson(legacy);
    expect(lesson.cards, hasLength(3));
    expect(lesson.cards.first.meaning, isEmpty);
    expect(lesson.meaning, '菲尔，你去叫他们过来，好吗？');
  });
}
