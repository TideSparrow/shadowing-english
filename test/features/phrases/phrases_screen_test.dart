import 'package:common_learn_english/features/library/presentation/library_catalog_provider.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:common_learn_english/features/phrases/presentation/phrase_book_provider.dart';
import 'package:common_learn_english/features/phrases/presentation/phrase_review_screen.dart';
import 'package:common_learn_english/features/phrases/presentation/phrases_screen.dart';
import 'package:common_learn_english/features/phrases/presentation/widgets/phrase_card.dart';
import 'package:common_learn_english/features/shared/data/word_pronunciation_service.dart';
import 'package:common_learn_english/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod/src/framework.dart' show Override;

class _PhraseSourceCatalogNotifier extends LibraryCatalogNotifier {
  @override
  List<LibraryCourseData> build() => const <LibraryCourseData>[
    LibraryCourseData(
      id: 'intern',
      title: '实习生',
      description: '',
      sourceLabel: '',
      coverImage: '',
      level: '',
      category: '',
      progressPercent: 0,
      totalWords: 0,
      completedEpisodes: 0,
      totalEpisodes: 1,
      lastStudiedStr: '',
      rating: 0,
      episodes: <LibraryEpisodeItem>[
        LibraryEpisodeItem(
          id: 'intern-ep3',
          numberStr: '03',
          title: '第三集',
          durationMinutes: 1,
          hasChineseSubtitles: false,
          hasEnglishSubtitles: false,
          completed: false,
          progressPercent: 0,
          coverImage: '',
        ),
      ],
    ),
  ];
}

class _PhraseBookNotifier extends PhraseBookNotifier {
  @override
  List<PhraseEntry> build() => const <PhraseEntry>[
    PhraseEntry(
      id: 'test-phrase-1',
      english: 'They sought a quiet sanctuary away from the noise.',
      chinese: '他们寻找一个远离喧嚣的安静避难所。',
      course: '实习生',
      episode: '第 3 集',
      time: '02:14',
      rating: 3,
      needsReview: true,
      today: true,
      courseId: 'intern',
      episodeId: 'intern-ep3',
      startTime: '02:14',
    ),
    PhraseEntry(
      id: 'test-phrase-2',
      english: 'The city was too chaotic for them.',
      chinese: '这座城市对他们来说太混乱了。',
      course: '实习生',
      episode: '第 3 集',
      time: '01:42',
      rating: 2,
      needsReview: true,
      today: true,
      courseId: 'intern',
      episodeId: 'intern-ep3',
      startTime: '01:42',
    ),
  ];
}

void main() {
  Future<GoRouter> pumpPhrases(
    WidgetTester tester,
    Size size, {
    List<Override> overrides = const <Override>[],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final GoRouter router = GoRouter(
      initialLocation: SGRoute.phrases.route,
      routes: <GoRoute>[
        GoRoute(
          path: SGRoute.phrases.route,
          builder: (_, __) => const PhrasesScreen(),
        ),
        GoRoute(
          path: SGRoute.phraseReview.route,
          name: SGRoute.phraseReview.name,
          builder: (_, __) => const PhraseReviewScreen(),
        ),
        GoRoute(
          path: '/episodes/:episodeId',
          name: SGRoute.player.name,
          builder: (_, GoRouterState state) => Scaffold(
            body: Text(
              'start=${state.uri.queryParameters['startTime']};'
              'autoplay=${state.uri.queryParameters['autoplay']}',
            ),
          ),
        ),
      ],
    );
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        phraseBookProvider.overrideWith(_PhraseBookNotifier.new),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('Pad library uses sidebar and opens focused recall', (
    WidgetTester tester,
  ) async {
    await pumpPhrases(tester, const Size(1366, 1024));

    expect(find.byKey(const Key('pad-sidebar-header')), findsOneWidget);
    expect(find.text('今日有 2 条待复习'), findsOneWidget);
    expect(find.text('待复习 2'), findsOneWidget);
    expect(find.text('今天复习'), findsWidgets);

    await tester.tap(find.text('每日复习'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pad-sidebar-header')), findsNothing);
    expect(find.text('他们寻找一个远离喧嚣的安静避难所。'), findsOneWidget);
    expect(
      find.text('They sought a quiet sanctuary away from the noise.'),
      findsNothing,
    );

    await tester.tap(find.text('显示英文答案'));
    await tester.pumpAndSettle();

    expect(
      find.text('They sought a quiet sanctuary away from the noise.'),
      findsOneWidget,
    );
    expect(find.text('需要再练'), findsOneWidget);
    expect(find.text('差不多'), findsOneWidget);
    expect(find.text('能用上'), findsOneWidget);
  });

  testWidgets('expanded Pad recall scrolls instead of overflowing', (
    WidgetTester tester,
  ) async {
    await pumpPhrases(tester, const Size(1280, 800));

    await tester.tap(find.text('每日复习'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示英文答案'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('review dock keeps navigation and scoring actions available', (
    WidgetTester tester,
  ) async {
    await pumpPhrases(tester, const Size(1280, 800));

    await tester.tap(find.text('每日复习'));
    await tester.pumpAndSettle();

    expect(find.text('上一条'), findsOneWidget);
    expect(find.text('暂时跳过'), findsOneWidget);
    expect(find.text('显示英文答案'), findsOneWidget);

    await tester.tap(find.text('暂时跳过'));
    await tester.pumpAndSettle();
    expect(find.text('这座城市对他们来说太混乱了。'), findsOneWidget);

    await tester.tap(find.text('上一条'));
    await tester.pumpAndSettle();
    expect(find.text('他们寻找一个远离喧嚣的安静避难所。'), findsOneWidget);

    await tester.tap(find.text('显示英文答案'));
    await tester.pumpAndSettle();
    expect(find.text('需要再练'), findsOneWidget);
    expect(find.text('差不多'), findsOneWidget);
    expect(find.text('能用上'), findsOneWidget);
  });

  testWidgets('recall plays the English phrase through TTS', (
    WidgetTester tester,
  ) async {
    String? spoken;
    await pumpPhrases(
      tester,
      const Size(1280, 800),
      overrides: <Override>[
        wordPronunciationServiceProvider.overrideWith(
          (Ref ref) => WordPronunciationService(
            speakOverride: (String text) async => spoken = text,
          ),
        ),
      ],
    );

    await tester.tap(find.text('每日复习'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('播放原句'));
    await tester.pumpAndSettle();

    expect(spoken, 'They sought a quiet sanctuary away from the noise.');
    expect(find.byType(PhraseReviewScreen), findsOneWidget);
  });

  testWidgets('opening a source video seeks and starts at the phrase time', (
    WidgetTester tester,
  ) async {
    await pumpPhrases(
      tester,
      const Size(1280, 800),
      overrides: <Override>[
        libraryCatalogProvider.overrideWith(_PhraseSourceCatalogNotifier.new),
      ],
    );

    await tester.tap(find.text('每日复习'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开原视频'));
    await tester.pumpAndSettle();

    expect(find.text('start=02:14;autoplay=1'), findsOneWidget);
  });

  testWidgets('phone library uses bottom navigation and supports add', (
    WidgetTester tester,
  ) async {
    await pumpPhrases(tester, const Size(390, 844));

    expect(find.byKey(const Key('pad-sidebar-header')), findsNothing);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('短语库'), findsWidgets);
    expect(find.text('添加'), findsOneWidget);

    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(
        TextField,
        '例如: They sought a quiet sanctuary away from the noise.',
      ),
      'New phrase',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '例如: 他们寻找一个远离喧嚣的安静避难所。'),
      '新的翻译',
    );
    await tester.tap(find.text('加入短语库'));
    await tester.pumpAndSettle();

    expect(find.text('New phrase'), findsOneWidget);
  });

  testWidgets('player route carries phrase time and autoplay', (
    WidgetTester tester,
  ) async {
    final GoRouter router = await pumpPhrases(tester, const Size(1366, 1024));

    router.go('/episodes/intern-ep3?startTime=00%3A34&autoplay=1');
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/episodes/intern-ep3?startTime=00%3A34&autoplay=1',
    );
    expect(find.text('start=00:34;autoplay=1'), findsOneWidget);
  });

  testWidgets('active phrase playback uses pause button', (
    WidgetTester tester,
  ) async {
    const PhraseEntry phrase = PhraseEntry(
      id: 'phrase',
      english: 'Hello there.',
      chinese: '你好。',
      course: '测试课程',
      episode: '第 1 集',
      time: '00:00',
      rating: 1,
      needsReview: true,
      today: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PhraseCard(
          phrase: phrase,
          isSpeaking: true,
          onSpeak: () {},
          onEdit: () {},
          onDelete: () {},
          onMarkForReview: () {},
          onOpenSource: () {},
        ),
      ),
    );
    expect(find.byTooltip('停止朗读'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
  });
}
