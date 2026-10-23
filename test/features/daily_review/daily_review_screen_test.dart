import 'dart:convert';

import 'package:common_learn_english/features/daily_review/domain/daily_review.dart';
import 'package:common_learn_english/features/daily_review/presentation/daily_review_provider.dart';
import 'package:common_learn_english/features/daily_review/presentation/daily_review_screen.dart';
import 'package:common_learn_english/features/navigation/presentation/navigation_destination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:go_router/go_router.dart';

const List<ReviewSource> sources = <ReviewSource>[
  ReviewSource(
    key: 'word:hello',
    kind: ReviewKind.word,
    question: 'hello',
    answer: '你好',
    english: 'Hello there.',
    chinese: '你好。',
    sourceLabel: '课程 · 01',
  ),
  ReviewSource(
    key: 'phrase:1',
    kind: ReviewKind.phrase,
    question: '很高兴见到你。',
    answer: 'Nice to meet you.',
    english: 'Nice to meet you.',
    chinese: '很高兴见到你。',
    sourceLabel: '课程 · 02',
  ),
];

ProviderContainer makeContainer([List<ReviewSource> items = sources]) =>
    ProviderContainer(
      // ignore: always_specify_types
      overrides: [
        reviewSourcesProvider.overrideWithValue(items),
        reviewClockProvider.overrideWithValue(() => DateTime(2026, 10, 23, 9)),
      ],
    );
Widget app(ProviderContainer container, {bool session = false}) {
  final GoRouter router = GoRouter(
    initialLocation: session ? '/review/session' : '/review',
    routes: <GoRoute>[
      GoRoute(path: '/review', builder: (_, __) => const DailyReviewScreen()),
      GoRoute(
        path: '/review/session',
        builder: (_, GoRouterState state) => DailyReviewScreen(
          session: true,
          practice: state.uri.queryParameters['practice'] == '1',
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  test('navigation places review between growth and phrases', () {
    const List<AppNavDestination> nav = AppNavDestination.values;
    expect(
      nav.indexOf(AppNavDestination.review),
      nav.indexOf(AppNavDestination.growth) + 1,
    );
    expect(
      nav.indexOf(AppNavDestination.phrases),
      nav.indexOf(AppNavDestination.review) + 1,
    );
  });

  for (final Size size in <Size>[const Size(390, 844), const Size(1366, 900)]) {
    testWidgets(
      'responsive review flow hides answers and saves before advancing at $size',
      (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final ProviderContainer container = makeContainer();
        addTearDown(container.dispose);
        await tester.pumpWidget(app(container));
        await tester.pumpAndSettle();
        expect(find.text('每日复习'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('daily-review-start')));
        await tester.tap(find.byKey(const Key('daily-review-start')));
        await tester.pumpAndSettle();
        expect(find.text('正在复习'), findsOneWidget);
        expect(find.byKey(const Key('pad-sidebar-header')), findsNothing);
        expect(
          find.byKey(const Key('daily-review-session-progress')),
          findsOneWidget,
        );
        expect(find.text('hello'), findsOneWidget);
        expect(find.text('你好'), findsNothing);
        expect(find.byKey(const Key('daily-review-rate-good')), findsNothing);
        await tester.ensureVisible(
          find.byKey(const Key('daily-review-reveal')),
        );
        await tester.tap(find.byKey(const Key('daily-review-reveal')));
        await tester.pumpAndSettle();
        expect(find.text('你好'), findsOneWidget);
        expect(find.text('没想起 · 重学'), findsOneWidget);
        expect(find.text('想对了，但吃力'), findsOneWidget);
        expect(find.textContaining('预计 '), findsNWidgets(4));
        expect(
          container.read(dailyReviewProvider).records['word:hello']!.reviews,
          0,
        );
        await tester.ensureVisible(
          find.byKey(const Key('daily-review-rate-good')),
        );
        await tester.tap(find.byKey(const Key('daily-review-rate-good')));
        await tester.pumpAndSettle();
        expect(
          container.read(dailyReviewProvider).records['word:hello']!.reviews,
          1,
        );
        expect(find.text('很高兴见到你。'), findsOneWidget);
        expect(find.text('Nice to meet you.'), findsNothing);
        await tester.tap(find.text('稍后继续'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(app(container));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('daily-review-start')));
        await tester.tap(find.byKey(const Key('daily-review-start')));
        await tester.pumpAndSettle();
        expect(find.text('很高兴见到你。'), findsOneWidget);
        expect(
          container
              .read(dailyReviewProvider)
              .plan(sources, DateTime(2026, 10, 23, 9))
              .today
              .newLearned,
          1,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'carousel browsing never grades, completed cards cannot be graded twice',
    (WidgetTester tester) async {
      final ProviderContainer container = makeContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, session: true));
      await tester.pumpAndSettle();
      expect(find.text('hello'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('daily-review-previous')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('daily-review-next')));
      await tester.pumpAndSettle();
      expect(find.text('很高兴见到你。'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('daily-review-next')))
            .onPressed,
        isNull,
      );
      expect(
        container
            .read(dailyReviewProvider)
            .plan(sources, DateTime(2026, 10, 23, 9))
            .today
            .reviews,
        0,
      );
      await tester.tap(find.byKey(const Key('daily-review-previous')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('daily-review-reveal')));
      await tester.tap(find.byKey(const Key('daily-review-reveal')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('daily-review-rate-good')),
      );
      await tester.tap(find.byKey(const Key('daily-review-rate-good')));
      await tester.pumpAndSettle();
      expect(find.text('已完成 1 / 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('daily-review-previous')));
      await tester.pumpAndSettle();
      expect(find.text('你好'), findsOneWidget);
      expect(find.text('已完成，这张卡片的进度已保存'), findsOneWidget);
      expect(find.byKey(const Key('daily-review-rate-good')), findsNothing);
      expect(
        container.read(dailyReviewProvider).records['word:hello']!.reviews,
        1,
      );
      await tester.tap(find.byKey(const Key('daily-review-next')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('daily-review-reveal')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'direct session entry returns to overview with source and scheduling guidance',
    (WidgetTester tester) async {
      final ProviderContainer container = makeContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, session: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('返回每日概览'));
      await tester.pumpAndSettle();
      expect(find.text('每日复习'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('内容从哪里来？'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('内容从哪里来？'), findsOneWidget);
      expect(find.text('为什么不用每天全部重学？'), findsOneWidget);
      expect(
        container
            .read(dailyReviewProvider)
            .plan(sources, DateTime(2026, 10, 23, 9))
            .today
            .reviews,
        0,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'long cards scroll while carousel controls stay available on small screens',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ProviderContainer container = makeContainer(<ReviewSource>[
        ReviewSource(
          key: 'phrase:long',
          kind: ReviewKind.phrase,
          question: List<String>.filled(12, '这是一句需要慢慢回忆的表达。').join(),
          answer: List<String>.filled(
            12,
            'Take your time to recall this expression.',
          ).join(' '),
          english: 'Take your time.',
          chinese: '慢慢来',
          sourceLabel: '较长的课程标题和原句来源',
        ),
        sources.first,
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, session: true));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('daily-review-next')).hitTestable(),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const Key('daily-review-reveal')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('daily-review-reveal')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('daily-review-rate-good')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('daily-review-rate-good')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('daily-review-next')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('daily-review-next')));
      await tester.pumpAndSettle();
      final ListView sessionList = tester.widget<ListView>(
        find.byKey(const Key('daily-review-session-scroll')),
      );
      expect(sessionList.controller!.offset, 0);
      expect(find.text('hello').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'finished overview can repeat learned cards without changing FSRS or quota',
    (WidgetTester tester) async {
      final ProviderContainer container = makeContainer();
      addTearDown(container.dispose);
      final DailyReviewNotifier notifier = container.read(
        dailyReviewProvider.notifier,
      );
      await notifier.setDailyNewLimit(1);
      await notifier.grade(
        sources.first.key,
        fsrs.Rating.easy,
        expectedReviews: 0,
      );
      final String saved = jsonEncode(
        container.read(dailyReviewProvider).toJson(),
      );
      await tester.pumpWidget(app(container));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('daily-review-again')));
      await tester.tap(find.byKey(const Key('daily-review-again')));
      await tester.pumpAndSettle();
      expect(find.text('自由复习'), findsOneWidget);
      expect(find.text('很高兴见到你。'), findsNothing);
      expect(
        container.read(dailyReviewProvider).records['phrase:1']!.isNew,
        isTrue,
      );
      await tester.ensureVisible(find.byKey(const Key('daily-review-reveal')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('daily-review-reveal')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('daily-review-rate-good')), findsNothing);
      await tester.ensureVisible(
        find.byKey(const Key('daily-review-practice-done')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('daily-review-practice-done')));
      await tester.pumpAndSettle();
      expect(jsonEncode(container.read(dailyReviewProvider).toJson()), saved);
      expect(find.text('这轮自由复习完成了'), findsOneWidget);
      await tester.tap(find.text('再练一轮'));
      await tester.pumpAndSettle();
      expect(find.text('hello'), findsOneWidget);
      expect(jsonEncode(container.read(dailyReviewProvider).toJson()), saved);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a later due review can be graded again on the same day without using new quota',
    (WidgetTester tester) async {
      DateTime time = DateTime(2026, 10, 23, 9);
      final ProviderContainer container = ProviderContainer(
        // ignore: always_specify_types
        overrides: [
          reviewSourcesProvider.overrideWithValue(<ReviewSource>[
            sources.first,
          ]),
          reviewClockProvider.overrideWithValue(() => time),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(dailyReviewProvider.notifier)
          .grade('word:hello', fsrs.Rating.good, expectedReviews: 0);
      time = time.add(const Duration(minutes: 11));
      await tester.pumpWidget(app(container));
      await tester.pumpAndSettle();
      expect(find.text('再次复习'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('daily-review-start')));
      await tester.tap(find.byKey(const Key('daily-review-start')));
      await tester.pumpAndSettle();
      expect(find.text('正在复习'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('daily-review-reveal')));
      await tester.tap(find.byKey(const Key('daily-review-reveal')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('daily-review-rate-good')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('daily-review-rate-good')));
      await tester.pumpAndSettle();
      final DailyReviewState state = container.read(dailyReviewProvider);
      expect(state.records['word:hello']!.reviews, 2);
      expect(
        state.plan(<ReviewSource>[sources.first], time).today.newLearned,
        1,
      );
      expect(state.plan(<ReviewSource>[sources.first], time).today.reviews, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('new limit validates, persists, and can pause new learning', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = makeContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(app(container));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('复习设置'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('daily-review-new-limit')),
      '101',
    );
    await tester.tap(find.text('保存设置'));
    await tester.pumpAndSettle();
    expect(find.text('请输入 0–100 的整数'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('daily-review-new-limit')),
      '0',
    );
    await tester.tap(find.text('保存设置'));
    await tester.pumpAndSettle();
    expect(container.read(dailyReviewProvider).dailyNewLimit, 0);
    expect(find.textContaining('新学已暂停'), findsOneWidget);
    expect(container.read(dailyReviewProvider).records, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('empty state explains where the review content comes from', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = makeContainer(const <ReviewSource>[]);
    addTearDown(container.dispose);
    await tester.pumpWidget(app(container));
    await tester.pumpAndSettle();
    expect(find.text('把想记住的表达带到这里'), findsOneWidget);
    expect(find.byKey(const Key('daily-review-start')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
