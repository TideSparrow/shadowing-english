import 'dart:convert';

import 'package:common_learn_english/features/lessons/data/lesson_service.dart';
import 'package:common_learn_english/features/lessons/data/lesson_store.dart';
import 'package:common_learn_english/features/lessons/domain/intensive_lesson.dart';
import 'package:common_learn_english/features/lessons/domain/lesson_summary.dart';
import 'package:common_learn_english/features/library/presentation/library_catalog_provider.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:common_learn_english/features/player/presentation/player_screen.dart';
import 'package:common_learn_english/features/player/presentation/widgets/player_video_panel.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:common_learn_english/features/shared/data/word_pronunciation_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/src/framework.dart' show Override;

import 'lesson_fixture.dart';

class _Catalog extends LibraryCatalogNotifier {
  @override
  List<LibraryCourseData> build() => const <LibraryCourseData>[
    LibraryCourseData(
      id: 'test-course',
      title: '测试课程',
      description: '',
      sourceLabel: '',
      coverImage: '',
      level: 'B1',
      category: '',
      progressPercent: 0,
      totalWords: 0,
      completedEpisodes: 0,
      totalEpisodes: 1,
      lastStudiedStr: '',
      rating: 0,
      episodes: <LibraryEpisodeItem>[
        LibraryEpisodeItem(
          id: 'lesson-fixture-episode',
          numberStr: '01',
          title: '早餐时间',
          durationMinutes: 1,
          hasChineseSubtitles: false,
          hasEnglishSubtitles: true,
          completed: false,
          progressPercent: 0,
          coverImage: '',
          enSubtitleAsset: 'assets/test/lesson.srt',
        ),
      ],
    ),
  ];
}

class _Book extends LessonBook {
  @override
  Future<List<LessonSummary>> build() async => <LessonSummary>[];
  IntensiveLesson? saved;
  @override
  Future<IntensiveLesson?> find(String id) async =>
      saved?.id == id ? saved : null;
  @override
  Future<void> save(IntensiveLesson lesson) async {
    saved = lesson;
    state = AsyncData<List<LessonSummary>>(<LessonSummary>[
      LessonSummary.fromLesson(lesson),
    ]);
  }
}

class _Settings extends LearningSettingsNotifier {
  @override
  LearningSettingsState build() => LearningSettingsState.defaults().copyWith(
    translationProvider: 'OpenAI',
    translationApiKey: 'test-only',
    translationModel: 'test',
    subtitleDelayMs: 1000,
  );
}

class _Service extends LessonService {
  int requests = 0;
  LessonSource? received;
  @override
  Future<IntensiveLesson> generate({
    required LessonSource source,
    required LearningSettingsState settings,
    required CancelToken cancelToken,
  }) async {
    requests++;
    received = source;
    return fixtureLesson(source: source);
  }
}

void main() {
  for (final Size size in <Size>[const Size(1280, 900), const Size(390, 844)]) {
    testWidgets(
      'player opens current full sentence and retains it in episode tab at $size',
      (WidgetTester tester) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final ByteData dot = ByteData.sublistView(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a9WQAAAAASUVORK5CYII=',
          ),
        );
        final Map<String, ByteData> artwork = <String, ByteData>{
          'AssetManifest.bin': const StandardMessageCodec().encodeMessage(
            <String, Object>{},
          )!,
          'assets/img/lesson-tutor.png': dot,
          'assets/img/lesson-dialogue.png': dot,
          'assets/img/growth-level-3.png': dot,
          'assets/img/growth-companion-confident.png': dot,
        };
        final TestDefaultBinaryMessenger
        messenger = tester.binding.defaultBinaryMessenger
          ..setMockMessageHandler('flutter/assets', (ByteData? data) async {
            final String? path = const StringCodec().decodeMessage(data);
            if (path == 'assets/test/lesson.srt') {
              return ByteData.sublistView(
                utf8.encode(
                  '1\n00:00:50,000 --> 00:00:52,000\nBreakfast is ready.\n\n'
                  '2\n00:00:53,000 --> 00:00:54,000\nPhil, would you\n\n'
                  '3\n00:00:54,100 --> 00:00:56,500\nget them?\n',
                ),
              );
            }
            return artwork[path];
          });
        addTearDown(
          () => messenger.setMockMessageHandler('flutter/assets', null),
        );
        final _Service service = _Service();
        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              libraryCatalogProvider.overrideWith(_Catalog.new),
              lessonBookProvider.overrideWith(_Book.new),
              learningSettingsProvider.overrideWith(_Settings.new),
              lessonServiceProvider.overrideWithValue(service),
              wordPronunciationServiceProvider.overrideWithValue(
                WordPronunciationService(
                  speakOverride: (_) async {},
                  stopOverride: () async {},
                ),
              ),
            ],
            child: const MaterialApp(
              home: PlayerScreen(
                episodeId: 'lesson-fixture-episode',
                initialStartTime: '00:54.000',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('player-explain-current-line')));
        await tester.pumpAndSettle();
        expect(service.requests, 1);
        expect(service.received!.english, 'Phil, would you get them?');
        expect(service.received!.context, contains('Breakfast is ready.'));
        expect(service.received!.startMs, 53000);
        expect(find.textContaining('已自动保存'), findsOneWidget);
        await tester.tap(find.byTooltip('关闭精讲'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<PlayerVideoPanel>(find.byType(PlayerVideoPanel))
              .isPlaying,
          false,
        );
        await tester.tap(find.text('精讲'));
        await tester.pumpAndSettle();
        expect(find.text('Phil, would you get them?'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
