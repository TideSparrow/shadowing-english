import 'dart:io';

import 'package:common_learn_english/features/library/presentation/library_catalog_provider.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:common_learn_english/features/library/presentation/library_screen.dart';
import 'package:common_learn_english/features/library/presentation/widgets/library_course_card.dart';
import 'package:common_learn_english/features/library/presentation/widgets/library_course_poster.dart';
import 'package:common_learn_english/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _TestLibraryCatalogNotifier extends LibraryCatalogNotifier {
  @override
  List<LibraryCourseData> build() => const <LibraryCourseData>[_testCourse];
}
const LibraryCourseData _testCourse = LibraryCourseData(
  id: 'custom-course',
  title: '我的课程',
  description: '测试课程',
  sourceLabel: '本地资源',
  coverImage: '',
  level: 'B1',
  category: '自定义',
  progressPercent: 25,
  totalWords: 12,
  completedEpisodes: 0,
  totalEpisodes: 1,
  lastStudiedStr: '刚刚',
  rating: 4.5,
  episodes: <LibraryEpisodeItem>[
    LibraryEpisodeItem(
      id: 'custom-course-ep01',
      numberStr: '01',
      title: '第一集',
      durationMinutes: 10,
      hasChineseSubtitles: true,
      hasEnglishSubtitles: true,
      completed: false,
      progressPercent: 25,
      coverImage: '',
      enSubtitleAsset: '',
    ),
  ],
);

void main() {
  GoRouter buildRouterWithScreen(LibraryScreen screen) {
    return GoRouter(
      initialLocation: SGRoute.library.route,
      routes: <GoRoute>[
        GoRoute(
          path: SGRoute.library.route,
          builder: (BuildContext context, GoRouterState state) => screen,
        ),
        GoRoute(
          path: '/episodes/:episodeId',
          name: SGRoute.player.name,
          builder: (BuildContext context, GoRouterState state) =>
              Scaffold(
                body: Text('player:${state.pathParameters['episodeId']!}'),
              ),
        ),
      ],
    );
  }

  GoRouter buildRouter() {
    return buildRouterWithScreen(const LibraryScreen());
  }

  for (final double width in <double>[320, 390]) {
    testWidgets('phone detail keeps episode actions usable at width $width', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      bool openedTranscript = false;
      final GoRouter router = buildRouterWithScreen(
        LibraryScreen(
          initialView: LibraryScreenView.detail,
          initialCourseId: _testCourse.id,
          openTranscriptReader:
              (LibraryCourseData course, LibraryEpisodeItem episode) async {
                openedTranscript = true;
              },
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          // ignore: always_specify_types
          overrides: [
            libraryCatalogProvider.overrideWith(
              _TestLibraryCatalogNotifier.new,
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final Finder button = find.byKey(
        const ValueKey<String>('episode-view-transcript-custom-course-ep01'),
      );
      await tester.scrollUntilVisible(
        button,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(openedTranscript, isTrue);
    });
  }

  testWidgets('library list shows empty state when no built-in courses remain', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final GoRouter router = buildRouter();

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    expect(find.text('影视库'), findsWidgets);
    expect(find.text('导入新课程'), findsOneWidget);
    expect(find.text('还没有导入任何课程'), findsOneWidget);
    expect(find.text('先导入你自己的视频和字幕资源，再开始精听。'), findsOneWidget);
  });

  testWidgets('library detail cover play entry opens player', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final GoRouter router = buildRouter();

    await tester.pumpWidget(
      ProviderScope(
        // ignore: always_specify_types
        overrides: [
          libraryCatalogProvider.overrideWith(_TestLibraryCatalogNotifier.new),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(LibraryCourseCard).first);
    await tester.pumpAndSettle();

    expect(find.text('2:30 / 10:00'), findsOneWidget);

    await tester.tap(find.text('第 1 集 · 第一集'));
    await tester.pumpAndSettle();

    expect(find.text('player:custom-course-ep01'), findsOneWidget);
  });

  testWidgets('episode list can open the independent full transcript', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? openedEpisodeId;
    final GoRouter router = buildRouterWithScreen(
      LibraryScreen(
        initialView: LibraryScreenView.detail,
        initialCourseId: _testCourse.id,
        openTranscriptReader:
            (LibraryCourseData course, LibraryEpisodeItem episode) async {
              openedEpisodeId = episode.id;
            },
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        // ignore: always_specify_types
        overrides: [
          libraryCatalogProvider.overrideWith(_TestLibraryCatalogNotifier.new),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('查看全文'));
    await tester.pumpAndSettle();

    expect(openedEpisodeId, 'custom-course-ep01');
    expect(find.text('player:custom-course-ep01'), findsNothing);
  });

  testWidgets('library list shows source label for imported course', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final GoRouter router = buildRouter();

    await tester.pumpWidget(
      ProviderScope(
        // ignore: always_specify_types
        overrides: [
          libraryCatalogProvider.overrideWith(_TestLibraryCatalogNotifier.new),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('来源：本地资源'), findsOneWidget);
  });

  testWidgets('library list renders placeholder poster text when no cover image', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final GoRouter router = buildRouter();

    await tester.pumpWidget(
      ProviderScope(
        // ignore: always_specify_types
        overrides: [
          libraryCatalogProvider.overrideWith(_TestLibraryCatalogNotifier.new),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LibraryCoursePosterTitle), findsOneWidget);
    expect(find.text('我的课程'), findsNWidgets(2));
  });

  testWidgets('library edit mode supports batch delete', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final GoRouter router = buildRouter();

    await tester.pumpWidget(
      ProviderScope(
        // ignore: always_specify_types
        overrides: [
          libraryCatalogProvider.overrideWith(_TestLibraryCatalogNotifier.new),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '编辑'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认删除'));
    await tester.pumpAndSettle();

    expect(find.text('我的课程'), findsNothing);
    expect(find.text('还没有导入任何课程'), findsOneWidget);
  });

  testWidgets('library edit mode updates title and source for one course', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final GoRouter router = buildRouter();

    await tester.pumpWidget(
      ProviderScope(
        // ignore: always_specify_types
        overrides: [
          libraryCatalogProvider.overrideWith(_TestLibraryCatalogNotifier.new),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '编辑'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '影视名'), '新的影视名');
    await tester.enterText(find.widgetWithText(TextField, '来源'), '本地视频');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('新的影视名'), findsWidgets);
    expect(find.textContaining('来源：本地视频'), findsOneWidget);
  });

  testWidgets('library edit mode uploads custom cover image for one course', (
    WidgetTester tester,
  ) async {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'library-cover-upload-',
    );
    final File cover = File('${tempDir.path}/cover.jpg')
      ..writeAsBytesSync(<int>[1, 2, 3]);
    addTearDown(() => tempDir.deleteSync(recursive: true));

    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final GoRouter router = buildRouterWithScreen(
      LibraryScreen(
        pickCoverImage: () => Future<String?>.value(cover.path),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        // ignore: always_specify_types
        overrides: [
          libraryCatalogProvider.overrideWith(_TestLibraryCatalogNotifier.new),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('上传封面'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.byType(LibraryCoursePosterTitle), findsNothing);
  });
}
