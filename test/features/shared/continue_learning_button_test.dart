import 'dart:io';

import 'package:common_learn_english/features/home/presentation/pad_home_screen.dart';
import 'package:common_learn_english/features/home/presentation/widgets/pad_home_hero.dart';
import 'package:common_learn_english/features/library/presentation/library_catalog_provider.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:common_learn_english/features/library/presentation/library_screen.dart';
import 'package:common_learn_english/features/navigation/presentation/floating_bottom_nav.dart';
import 'package:common_learn_english/features/navigation/presentation/navigation_destination.dart';
import 'package:common_learn_english/features/player/presentation/learning_resume_provider.dart';
import 'package:common_learn_english/features/player/presentation/pad_landscape_player_screen.dart';
import 'package:common_learn_english/features/player/presentation/player_screen.dart';
import 'package:common_learn_english/features/shared/presentation/pad/pad_scaffold.dart';
import 'package:common_learn_english/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:riverpod/misc.dart' show Override;

const ValueKey<String> _buttonKey = ValueKey<String>(
  'continue-learning-button',
);

void main() {
  group('resume history', () {
    late Directory storage;
    setUp(() async {
      storage = Directory.systemTemp.createTempSync('learning-resume-test-');
      Hive.init(storage.path);
      await Hive.openBox<String>('prefs');
    });
    tearDown(() async {
      await Hive.close();
      storage.deleteSync(recursive: true);
    });

    test('last opened episode survives a provider restart', () async {
      final ProviderContainer first = ProviderContainer();
      first.read(lastLearningEpisodeProvider.notifier).record('sheldon-02');
      await Hive.box<String>('prefs').flush();
      first.dispose();
      final ProviderContainer restored = ProviderContainer();
      addTearDown(restored.dispose);
      expect(restored.read(lastLearningEpisodeProvider), 'sheldon-02');
    });
  });

  test(
    'history wins over catalog order; deleted episodes fall back safely',
    () {
      final ProviderContainer container = _container();
      addTearDown(container.dispose);
      container.read(lastLearningEpisodeProvider.notifier).record('sheldon-02');
      expect(
        container.read(continueLearningTargetProvider)?.episode.id,
        'sheldon-02',
      );
      container.read(libraryCatalogProvider.notifier).state =
          <LibraryCourseData>[_courses.first];
      expect(
        container.read(continueLearningTargetProvider)?.episode.id,
        'peppa-01',
      );
      container.read(libraryCatalogProvider.notifier).state =
          const <LibraryCourseData>[];
      expect(container.read(continueLearningTargetProvider), isNull);
    },
  );

  testWidgets(
    'home hero follows recent history and resumes the displayed episode',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1366, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ProviderContainer container = _container();
      addTearDown(container.dispose);
      container.read(lastLearningEpisodeProvider.notifier).record('sheldon-02');
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
                PlayerScreen(
                  episodeId: state.pathParameters['episodeId']!,
                  autoPlay: state.uri.queryParameters['autoplay'] == '1',
                ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      PadHomeHero hero = tester.widget<PadHomeHero>(find.byType(PadHomeHero));
      expect(hero.course?.id, 'sheldon');
      expect(hero.episode?.id, 'sheldon-02');
      expect(find.text('上次学习：2:21'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(PadHomeHero),
          matching: find.text('继续播放'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<PlayerScreen>(find.byType(PlayerScreen)).episodeId,
        'sheldon-02',
      );
      expect(
        tester.widget<PlayerScreen>(find.byType(PlayerScreen)).autoPlay,
        isTrue,
      );
      expect(
        tester
            .state<PadLandscapePlayerScreenState>(
              find.byType(PadLandscapePlayerScreen),
            )
            .state
            .positionMs,
        141000,
      );
      router.pop();
      await tester.pumpAndSettle();
      router.go('/episodes/peppa-01');
      await tester.pumpAndSettle();
      router.go('/');
      await tester.pumpAndSettle();
      hero = tester.widget<PadHomeHero>(find.byType(PadHomeHero));
      expect(hero.course?.id, 'peppa');
      expect(hero.episode?.id, 'peppa-01');
      expect(find.text('上次学习：从第 1 句开始'), findsOneWidget);
      container.read(lastLearningEpisodeProvider.notifier).record('sheldon-02');
      await tester.pumpAndSettle();
      expect(
        tester.widget<PadHomeHero>(find.byType(PadHomeHero)).episode?.id,
        'sheldon-02',
      );
      expect(find.text('上次学习：2:21'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'button resumes the last episode and its saved position, and hides in the player',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1366, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ProviderContainer container = _container();
      addTearDown(container.dispose);
      container.read(lastLearningEpisodeProvider.notifier).record('sheldon-02');
      final GoRouter router = GoRouter(
        routes: <GoRoute>[
          GoRoute(
            path: '/',
            builder: (BuildContext context, GoRouterState state) =>
                const PadScaffold(
                  currentDestination: AppNavDestination.settings,
                  body: Center(child: Text('设置页面')),
                ),
          ),
          GoRoute(
            path: '/episodes/:episodeId',
            name: SGRoute.player.name,
            builder: (BuildContext context, GoRouterState state) {
              return PlayerScreen(
                episodeId: state.pathParameters['episodeId']!,
                autoPlay: state.uri.queryParameters['autoplay'] == '1',
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_buttonKey), findsOneWidget);
      await tester.tap(find.byKey(_buttonKey));
      await tester.tap(find.byKey(_buttonKey));
      await tester.pumpAndSettle();
      final PlayerScreen player = tester.widget<PlayerScreen>(
        find.byType(PlayerScreen),
      );
      expect(player.episodeId, 'sheldon-02');
      expect(player.autoPlay, isTrue);
      expect(find.byKey(_buttonKey), findsNothing);
      expect(
        tester
            .state<PadLandscapePlayerScreenState>(
              find.byType(PadLandscapePlayerScreen),
            )
            .state
            .positionMs,
        141000,
      );
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsNothing);
      expect(find.text('设置页面'), findsOneWidget);
      expect(find.byKey(_buttonKey), findsOneWidget);
      expect(
        tester.widget<FloatingActionButton>(find.byKey(_buttonKey)).onPressed,
        isNotNull,
      );
      final FloatingActionButton button = tester.widget<FloatingActionButton>(
        find.byKey(_buttonKey),
      );
      expect(button.foregroundColor, Colors.white);
      router.go('/episodes/peppa-01');
      await tester.pumpAndSettle();
      expect(container.read(lastLearningEpisodeProvider), 'peppa-01');
      router.go('/');
      await tester.pumpAndSettle();
      expect(
        container.read(continueLearningTargetProvider)?.episode.id,
        'peppa-01',
      );
    },
  );

  testWidgets(
    'course details keep their own play button; the library list shows the global button',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1366, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ProviderContainer container = _container();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: LibraryScreen(
              initialView: LibraryScreenView.detail,
              initialCourseId: 'sheldon',
              initialEpisodeId: 'sheldon-02',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_buttonKey), findsNothing);
      expect(find.text('继续播放第 02 集'), findsOneWidget);
      await tester.tap(find.byTooltip('返回影视库'));
      await tester.pumpAndSettle();
      expect(find.byKey(_buttonKey), findsOneWidget);
    },
  );

  testWidgets(
    'portrait button sits above bottom navigation and disappears for an empty library',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ProviderContainer container = _container();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: PadScaffold(
              currentDestination: AppNavDestination.settings,
              body: SizedBox(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(_buttonKey)).bottom,
        lessThan(tester.getRect(find.byType(FloatingBottomNav)).top),
      );
      container.read(libraryCatalogProvider.notifier).state =
          const <LibraryCourseData>[];
      await tester.pumpAndSettle();
      expect(find.byKey(_buttonKey), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

ProviderContainer _container() => ProviderContainer(
  overrides: <Override>[libraryCatalogProvider.overrideWith(_TestCatalog.new)],
);

class _TestCatalog extends LibraryCatalogNotifier {
  @override
  List<LibraryCourseData> build() => _courses;
}

final List<LibraryCourseData> _courses = <LibraryCourseData>[
  _course('peppa', '小猪佩奇', <LibraryEpisodeItem>[_episode('peppa-01', '01')]),
  _course('sheldon', '小谢尔顿', <LibraryEpisodeItem>[
    _episode('sheldon-01', '01'),
    _episode('sheldon-02', '02', position: '2:21'),
  ]),
];

LibraryCourseData _course(
  String id,
  String title,
  List<LibraryEpisodeItem> episodes,
) => LibraryCourseData(
  id: id,
  title: title,
  description: '',
  sourceLabel: '本地资源',
  coverImage: '',
  level: '自定义',
  category: '自选课程',
  progressPercent: 0,
  totalWords: 0,
  completedEpisodes: 0,
  totalEpisodes: episodes.length,
  lastStudiedStr: '刚刚学习',
  rating: 0,
  episodes: episodes,
);

LibraryEpisodeItem _episode(String id, String number, {String? position}) =>
    LibraryEpisodeItem(
      id: id,
      numberStr: number,
      title: '第 $number 集',
      durationMinutes: 5,
      hasChineseSubtitles: false,
      hasEnglishSubtitles: false,
      completed: false,
      progressPercent: position == null ? 0 : 40,
      coverImage: '',
      progressTimeStr: position,
    );
