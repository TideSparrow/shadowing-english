import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:common_learn_english/features/lessons/data/lesson_store.dart';
import 'package:common_learn_english/features/lessons/domain/intensive_lesson.dart';
import 'package:common_learn_english/features/lessons/domain/lesson_summary.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:riverpod/src/framework.dart' show Override;

import 'lesson_fixture.dart';

void main() {
  test(
    'lessons and images survive reopening; duplicate saves do not duplicate cards',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'lesson-store-test-',
      );
      Hive.init(directory.path);
      LazyBox<String> box = await Hive.openLazyBox<String>('lesson-test');
      final IntensiveLesson lesson = fixtureLesson();
      final LessonStore store = LessonStore(box);
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3]);
      await store.save(lesson);
      await store.save(lesson);
      await store.saveImage(lesson.id, bytes);
      await box.close();
      box = await Hive.openLazyBox<String>('lesson-test');
      final LessonStore reopened = LessonStore(box);
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          lessonStoreProvider.overrideWith((Ref ref) async => reopened),
        ],
      );
      try {
        expect(await container.read(lessonBookProvider.future), hasLength(1));
        expect(await reopened.image(lesson.id), bytes);
        await Future.wait<void>(<Future<void>>[
          container.read(lessonBookProvider.notifier).save(lesson),
          container.read(lessonBookProvider.notifier).save(lesson),
        ]);
        expect(await reopened.loadSummaries(), hasLength(1));
        await container.read(lessonBookProvider.notifier).delete(lesson.id);
        expect(await reopened.loadSummaries(), isEmpty);
        expect(await reopened.image(lesson.id), isNull);
      } finally {
        container.dispose();
        await box.close();
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    '1000 legacy lessons migrate once; previews never read full bodies again',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'lesson-index-test-',
      );
      Hive.init(directory.path);
      final LazyBox<String> box = await Hive.openLazyBox<String>(
        'lesson-index-test',
      );
      try {
        int fullBytes = 0;
        for (int index = 0; index < 1000; index++) {
          final IntensiveLesson lesson = numberedLesson(index);
          final String raw = jsonEncode(lesson.toJson());
          fullBytes += utf8.encode(raw).length;
          await box.put('lesson:${lesson.id}', raw);
        }
        final _CountingStore store = _CountingStore(box);
        final List<LessonSummary> migrated = await store.loadSummaries();
        expect(migrated, hasLength(1000));
        expect(store.detailReads, 1000);
        store.detailReads = 0;
        final List<LessonSummary> previews = await store.loadSummaries();
        expect(previews, hasLength(1000));
        expect(store.detailReads, 0);
        final int summaryBytes = previews.fold<int>(
          0,
          (int count, LessonSummary item) =>
              count + utf8.encode(jsonEncode(item.toJson())).length,
        );
        expect(summaryBytes, lessThan(fullBytes ~/ 4));
        expect(
          previews.map((LessonSummary item) => item.id),
          orderedEquals(migrated.map((LessonSummary item) => item.id)),
        );
        final IntensiveLesson? opened = await store.find(previews.first.id);
        expect(opened!.cards, hasLength(3));
        expect(store.detailReads, 1);
        await box.put('summary:${opened.id}', 'broken derived index');
        store.detailReads = 0;
        expect(await store.loadSummaries(), hasLength(1000));
        expect(store.detailReads, 1);
        expect(await store.find(opened.id), isNotNull);
      } finally {
        await box.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

class _CountingStore extends LessonStore {
  _CountingStore(super.box);
  int detailReads = 0;
  @override
  Future<IntensiveLesson?> find(String id) {
    detailReads++;
    return super.find(id);
  }
}
