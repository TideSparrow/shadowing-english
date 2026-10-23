import 'dart:convert';

import 'package:common_learn_english/features/daily_review/domain/daily_review.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

final DateTime now = DateTime(2026, 10, 23, 9);

ReviewSource source(
  String key, {
  ReviewKind kind = ReviewKind.word,
  DateTime? due,
  DateTime? last,
}) => ReviewSource(
  key: key,
  kind: kind,
  question: key,
  answer: '答案',
  english: 'A sentence.',
  chinese: '例句。',
  sourceLabel: '课程',
  legacyLastReview: last,
  legacyDue: due,
  legacyReviewCount: last == null ? 0 : 3,
);
DailyReviewState roundTrip(DailyReviewState state) => DailyReviewState.fromJson(
  jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
);

void main() {
  test(
    'uses the upstream FSRS scheduler and preserves immutable prior state',
    () {
      final List<ReviewSource> sources = <ReviewSource>[source('word:a')];
      final DailyReviewState initial = const DailyReviewState().synchronize(
        sources,
        now,
      );
      final ({fsrs.Card card, fsrs.ReviewLog reviewLog}) expected =
          fsrs.Scheduler(enableFuzzing: false).reviewCard(
            fsrs.Card(cardId: 1, due: now.toUtc()),
            fsrs.Rating.good,
            reviewDateTime: now.toUtc(),
          );
      final DailyReviewState graded = initial.grade(
        'word:a',
        fsrs.Rating.good,
        now,
        expectedReviews: 0,
      );
      expect(graded.records['word:a']!.card.toMap(), expected.card.toMap());
      expect(graded.records['word:a']!.card.stability, isPositive);
      expect(initial.records['word:a']!.card.lastReview, isNull);
      expect(initial.records['word:a']!.isNew, isTrue);
    },
  );

  test(
    'previewing all ratings preserves progress and matches a real submission',
    () {
      final DailyReviewState initial = const DailyReviewState().synchronize(
        <ReviewSource>[source('word:a')],
        now,
      );
      final String original = jsonEncode(initial.toJson());
      final ReviewRecord record = initial.records['word:a']!;
      for (final fsrs.Rating rating in fsrs.Rating.values) {
        final fsrs.Card preview = record.scheduledCard(rating, now);
        expect(jsonEncode(initial.toJson()), original);
        expect(preview.due.isAfter(now), isTrue);
        final DailyReviewState submitted = initial.grade(
          'word:a',
          rating,
          now,
          expectedReviews: 0,
        );
        expect(submitted.records['word:a']!.card.toMap(), preview.toMap());
      }
    },
  );

  test('mixed new items share one limit, across sessions and restart', () {
    final List<ReviewSource> sources = <ReviewSource>[
      source('word:a'),
      source('phrase:b', kind: ReviewKind.phrase),
      source('word:c'),
    ];
    DailyReviewState state = const DailyReviewState(
      dailyNewLimit: 2,
    ).synchronize(sources, now);
    for (int i = 0; i < 2; i++) {
      final ReviewRecord next = state.plan(sources, now).next!;
      state = roundTrip(
        state.grade(next.key, fsrs.Rating.easy, now, expectedReviews: 0),
      );
    }
    final ReviewPlan plan = state.plan(sources, now);
    expect(plan.today.newLearned, 2);
    expect(plan.newAvailable, 0);
    expect(plan.waiting.single.key, 'word:c');
    expect(plan.next, isNull);
    expect(
      () => state.grade('word:c', fsrs.Rating.good, now, expectedReviews: 0),
      throwsStateError,
    );
    expect(
      state.plan(sources, now.add(const Duration(days: 1))).newAvailable,
      1,
    );
  });

  test(
    'unfinished new items survive rollover and newer additions never jump ahead',
    () {
      final List<ReviewSource> sources = <ReviewSource>[
        source('old-a'),
        source('old-b'),
      ];
      DailyReviewState state = const DailyReviewState().synchronize(
        sources,
        now,
      );
      state = roundTrip(
        state.grade('old-a', fsrs.Rating.easy, now, expectedReviews: 0),
      );
      final DateTime tomorrow = now.add(const Duration(days: 1));
      final List<ReviewSource> expanded = <ReviewSource>[
        source('new-c'),
        ...sources,
      ];
      state = state.synchronize(expanded, tomorrow);
      expect(
        state
            .plan(expanded, tomorrow)
            .waiting
            .map((ReviewRecord item) => item.key),
        <String>['old-b', 'new-c'],
      );
      expect(state.plan(expanded, tomorrow).today.reviews, 0);
    },
  );

  test(
    'new-item fairness credit survives midnight and repeated short sessions',
    () {
      final List<ReviewSource> sources = <ReviewSource>[
        for (int i = 0; i < 7; i++)
          source(
            'due-$i',
            last: now.subtract(const Duration(days: 20)),
            due: now.subtract(Duration(days: 10 - i)),
          ),
        source('waiting'),
      ];
      DailyReviewState state = const DailyReviewState(
        dailyNewLimit: 1,
      ).synchronize(sources, now);
      for (int i = 0; i < 4; i++) {
        final DateTime day = now.add(Duration(days: i));
        final ReviewRecord next = state.plan(sources, day).next!;
        expect(next.isNew, isFalse);
        state = roundTrip(
          state.grade(next.key, fsrs.Rating.easy, day, expectedReviews: 3),
        );
      }
      expect(
        state.plan(sources, now.add(const Duration(days: 4))).next!.key,
        'waiting',
      );
    },
  );

  test(
    'failed recall reschedules instead of trapping the session on one item',
    () {
      final List<ReviewSource> sources = <ReviewSource>[
        source(
          'due-a',
          last: now.subtract(const Duration(days: 20)),
          due: now.subtract(const Duration(days: 10)),
        ),
        source(
          'due-b',
          last: now.subtract(const Duration(days: 20)),
          due: now.subtract(const Duration(days: 8)),
        ),
      ];
      DailyReviewState state = const DailyReviewState().synchronize(
        sources,
        now,
      );
      state = state.grade('due-a', fsrs.Rating.again, now, expectedReviews: 3);
      expect(state.records['due-a']!.card.due.isAfter(now), isTrue);
      expect(state.plan(sources, now).next!.key, 'due-b');
      expect(
        () => state.grade('due-a', fsrs.Rating.again, now, expectedReviews: 4),
        throwsStateError,
      );
    },
  );

  test(
    'new learning and later relearning do not consume the new limit twice',
    () {
      final List<ReviewSource> sources = <ReviewSource>[source('a')];
      DailyReviewState state = const DailyReviewState(
        dailyNewLimit: 1,
      ).synchronize(sources, now);
      state = state.grade('a', fsrs.Rating.again, now, expectedReviews: 0);
      final DateTime due = state.records['a']!.card.due;
      state = state.grade('a', fsrs.Rating.good, due, expectedReviews: 1);
      expect(state.plan(sources, due).today.newLearned, 1);
      expect(state.plan(sources, due).today.reviews, 2);
    },
  );

  test(
    'removing a source hides it, while restoring it preserves memory state',
    () {
      final List<ReviewSource> sources = <ReviewSource>[source('a')];
      final DailyReviewState state = const DailyReviewState()
          .synchronize(sources, now)
          .grade('a', fsrs.Rating.easy, now, expectedReviews: 0);
      expect(state.plan(const <ReviewSource>[], now).remaining, 0);
      final DailyReviewState restored = state.synchronize(
        sources,
        now.add(const Duration(days: 1)),
      );
      expect(restored.records['a']!.reviews, 1);
      expect(
        restored.records['a']!.card.toMap(),
        state.records['a']!.card.toMap(),
      );
    },
  );

  test(
    'legacy phrases keep due dates without fabricating a memory history',
    () {
      final DateTime due = now.add(const Duration(days: 3));
      final List<ReviewSource> sources = <ReviewSource>[
        source(
          'phrase:a',
          due: due,
          last: now.subtract(const Duration(days: 2)),
        ),
      ];
      final DailyReviewState state = const DailyReviewState().synchronize(
        sources,
        now,
      );
      expect(state.plan(sources, now).next, isNull);
      expect(state.plan(sources, now).waiting, isEmpty);
      expect(state.records['phrase:a']!.card.stability, isNull);
      expect(state.records['phrase:a']!.card.due, due.toUtc());
      expect(
        state
            .grade('phrase:a', fsrs.Rating.good, due, expectedReviews: 3)
            .records['phrase:a']!
            .card
            .stability,
        isPositive,
      );
    },
  );

  test('pausing new items does not hide due reviews or clear progress', () {
    final List<ReviewSource> sources = <ReviewSource>[
      source('a'),
      source('b', last: now.subtract(const Duration(days: 2)), due: now),
    ];
    final DailyReviewState state = const DailyReviewState()
        .synchronize(sources, now)
        .withLimit(0);
    expect(state.plan(sources, now).newAvailable, 0);
    expect(state.plan(sources, now).next!.key, 'b');
    expect(state.records, hasLength(2));
  });

  test('duplicate grades cannot consume quota or update the memory twice', () {
    final DailyReviewState state = const DailyReviewState()
        .synchronize(<ReviewSource>[source('a')], now)
        .grade('a', fsrs.Rating.good, now, expectedReviews: 0);
    expect(
      () => state.grade('a', fsrs.Rating.good, now, expectedReviews: 0),
      throwsStateError,
    );
    expect(state.records['a']!.reviews, 1);
  });
}
