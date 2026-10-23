import 'package:common_learn_english/features/growth/presentation/growth_screen.dart';
import 'package:common_learn_english/features/home/presentation/pad_home_screen.dart';
import 'package:common_learn_english/features/import_course/presentation/import_course_screen.dart';
import 'package:common_learn_english/features/library/presentation/library_catalog_provider.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:common_learn_english/features/library/presentation/library_screen.dart';
import 'package:common_learn_english/features/phrases/presentation/phrases_screen.dart';
import 'package:common_learn_english/features/player/presentation/player_screen.dart';
import 'package:common_learn_english/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod/misc.dart' show Override;

void main() {
  testWidgets(
    'recent course cards open their own episodes when switching courses',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1366, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final GoRouter router = GoRouter(
        routes: <GoRoute>[
          GoRoute(
            path: '/',
            builder: (BuildContext context, GoRouterState state) =>
                const PadHomeScreen(),
          ),
          GoRoute(
            path: '/episodes/:episodeId',
            name: SGRoute.player.name,
            builder: (BuildContext context, GoRouterState state) =>
                PlayerScreen(episodeId: state.pathParameters['episodeId']!),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            libraryCatalogProvider.overrideWith(
              _RecentCoursesCatalogNotifier.new,
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      for (final String courseId in <String>['sheldon', 'peppa', 'sheldon']) {
        final Finder card = find.byKey(
          ValueKey<String>('recent-course-$courseId'),
        );
        await tester.scrollUntilVisible(
          card,
          400,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey<String>('home-page-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        await tester.tap(card);
        await tester.pumpAndSettle();
        expect(
          GoRouterState.of(tester.element(find.byType(PlayerScreen))).uri.path,
          '/episodes/$courseId-ep1',
        );
        expect(
          tester.widget<PlayerScreen>(find.byType(PlayerScreen)).episodeId,
          '$courseId-ep1',
        );
        expect(
          find.text(courseId == 'sheldon' ? '小谢尔顿' : '小猪佩奇'),
          findsOneWidget,
        );
        router.pop();
        await tester.pumpAndSettle();
      }

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(PadHomeScreen)),
      );
      final LibraryCatalogNotifier catalog = container.read(
        libraryCatalogProvider.notifier,
      );
      final DateTime studiedAt = DateTime.utc(2026, 10, 23);
      await catalog.updateEpisodeProgress(
        episodeId: 'sheldon-ep1',
        position: const Duration(seconds: 10),
        duration: const Duration(seconds: 100),
        occurredAt: studiedAt,
      );
      await tester.pumpAndSettle();
      final Finder sheldonCard = find.byKey(
        const ValueKey<String>('recent-course-sheldon'),
      );
      final Finder peppaCard = find.byKey(
        const ValueKey<String>('recent-course-peppa'),
      );
      await tester.scrollUntilVisible(
        sheldonCard,
        400,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey<String>('home-page-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(sheldonCard).dx,
        lessThan(tester.getTopLeft(peppaCard).dx),
      );
      await catalog.updateEpisodeProgress(
        episodeId: 'peppa-ep1',
        position: const Duration(seconds: 10),
        duration: const Duration(seconds: 100),
        occurredAt: studiedAt.add(const Duration(seconds: 1)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(peppaCard).dx,
        lessThan(tester.getTopLeft(sheldonCard).dx),
      );
      await tester.tap(sheldonCard);
      await tester.pumpAndSettle();
      expect(
        tester.widget<PlayerScreen>(find.byType(PlayerScreen)).episodeId,
        'sheldon-ep1',
      );
      router.pop();
      await tester.pumpAndSettle();

      final Finder emptyCourse = find.byKey(
        const ValueKey<String>('recent-course-empty'),
      );
      await tester.scrollUntilVisible(
        emptyCourse,
        400,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey<String>('home-page-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(emptyCourse);
      await tester.pumpAndSettle();
      await tester.tap(emptyCourse);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(find.text('该课程暂无可播放的剧集'), findsOneWidget);
      expect(find.byType(PlayerScreen), findsNothing);
    },
  );

  testWidgets('home quick entries and hero navigate to prototype targets', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final GoRouter router = GoRouter(
      initialLocation: SGRoute.home.route,
      routes: <GoRoute>[
        GoRoute(
          path: SGRoute.home.route,
          builder: (BuildContext context, GoRouterState state) =>
              const PadHomeScreen(),
        ),
        GoRoute(
          path: SGRoute.phrases.route,
          builder: (BuildContext context, GoRouterState state) =>
              const PhrasesScreen(),
        ),
        GoRoute(
          path: SGRoute.library.route,
          builder: (BuildContext context, GoRouterState state) =>
              const LibraryScreen(),
        ),
        GoRoute(
          path: SGRoute.growth.route,
          builder: (BuildContext context, GoRouterState state) =>
              const GrowthScreen(),
        ),
        GoRoute(
          path: SGRoute.importCourse.route,
          builder: (BuildContext context, GoRouterState state) =>
              const ImportCourseScreen(),
        ),
        GoRoute(
          path: '/episodes/:episodeId',
          name: SGRoute.player.name,
          builder: (BuildContext context, GoRouterState state) =>
              PlayerScreen(episodeId: state.pathParameters['episodeId']!),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    expect(find.text('晚上好 Mark 👋'), findsOneWidget);
    expect(find.text('继续你的英语成长旅程'), findsOneWidget);
    expect(find.text('今日挑战'), findsOneWidget);
    expect(find.text('英语成长'), findsWidgets);
    await tester.tap(find.text('英语成长').last);
    await tester.pumpAndSettle();
    expect(find.text('英语成长之旅'), findsOneWidget);

    router.go(SGRoute.home.route);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('复习我的短语'),
      400,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey<String>('home-page-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('复习我的短语'), findsOneWidget);
    await tester.ensureVisible(find.text('复习我的短语'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复习我的短语'));
    await tester.pumpAndSettle();

    expect(find.text('新增短语'), findsOneWidget);

    router.go(SGRoute.home.route);
    await tester.pumpAndSettle();

    await tester.tap(find.text('导入你的第一套英语视频课程'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, SGRoute.home.route);
    expect(find.text('导入影视'), findsOneWidget);
    expect(find.text('选择视频文件夹'), findsWidgets);
  });
}

class _RecentCoursesCatalogNotifier extends LibraryCatalogNotifier {
  @override
  List<LibraryCourseData> build() => <LibraryCourseData>[
    _recentCourse('peppa', '小猪佩奇'),
    _recentCourse('sheldon', '小谢尔顿'),
    _recentCourse('empty', '空课程', hasEpisode: false),
  ];
}

LibraryCourseData _recentCourse(
  String id,
  String title, {
  bool hasEpisode = true,
}) => LibraryCourseData(
  id: id,
  title: title,
  description: '',
  sourceLabel: '本地资源',
  coverImage: '',
  level: 'A1',
  category: '自定义',
  progressPercent: 0,
  totalWords: 0,
  completedEpisodes: 0,
  totalEpisodes: hasEpisode ? 1 : 0,
  lastStudiedStr: '刚刚学习',
  rating: 0,
  episodes: hasEpisode
      ? <LibraryEpisodeItem>[
          LibraryEpisodeItem(
            id: '$id-ep1',
            numberStr: '01',
            title: '$title 第一集',
            durationMinutes: 10,
            hasChineseSubtitles: false,
            hasEnglishSubtitles: false,
            completed: false,
            progressPercent: 0,
            coverImage: '',
          ),
        ]
      : const <LibraryEpisodeItem>[],
);
