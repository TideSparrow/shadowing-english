import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../domain/intensive_lesson.dart';
import '../domain/lesson_summary.dart';

final FutureProvider<LessonStore> lessonStoreProvider =
    FutureProvider<LessonStore>(
      (Ref ref) async =>
          LessonStore(await Hive.openLazyBox<String>('intensive_lessons_v1')),
    );

class LessonStore {
  const LessonStore(this.box);
  final LazyBox<String> box;

  Future<List<LessonSummary>> loadSummaries() async {
    final List<LessonSummary> result = <LessonSummary>[];
    int visited = 0;
    for (final String key
        in box.keys
            .cast<String>()
            .where((String key) => key.startsWith('lesson:'))
            .toList()) {
      final String id = key.substring('lesson:'.length);
      final String? raw = await box.get('summary:$id');
      LessonSummary? summary;
      if (raw != null) {
        try {
          summary = LessonSummary.fromJson(
            jsonDecode(raw) as Map<String, dynamic>,
          );
          if (summary.id != id) summary = null;
        } catch (_) {
          // Only derived previews are rebuilt. Never erase the original lesson.
        }
      }
      if (summary == null) {
        final IntensiveLesson? lesson = await find(id);
        if (lesson == null) continue;
        summary = LessonSummary.fromLesson(lesson);
        await box.put('summary:$id', jsonEncode(summary.toJson()));
      }
      result.add(summary);
      // Legacy libraries migrate incrementally without a long UI-thread task.
      if (++visited % 32 == 0) await Future<void>.delayed(Duration.zero);
    }
    result.sort((LessonSummary a, LessonSummary b) {
      final int order = b.createdAt.compareTo(a.createdAt);
      return order == 0 ? a.id.compareTo(b.id) : order;
    });
    return result;
  }

  Future<IntensiveLesson?> find(String id) async {
    final String? raw = await box.get('lesson:$id');
    if (raw == null) return null;
    final IntensiveLesson lesson = IntensiveLesson.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    if (lesson.id != id) {
      throw const FormatException('Lesson identity mismatch.');
    }
    return lesson;
  }

  Future<void> save(IntensiveLesson lesson) => box.putAll(<String, String>{
    'lesson:${lesson.id}': jsonEncode(lesson.toJson()),
    'summary:${lesson.id}': jsonEncode(
      LessonSummary.fromLesson(lesson).toJson(),
    ),
  });

  Future<Uint8List?> image(String id) async {
    final String? encoded = await box.get('image:$id');
    return encoded == null ? null : base64Decode(encoded);
  }

  Future<void> saveImage(String id, Uint8List bytes) =>
      box.put('image:$id', base64Encode(bytes));

  Future<void> delete(String id) =>
      box.deleteAll(<String>['lesson:$id', 'summary:$id', 'image:$id']);
}

final AsyncNotifierProvider<LessonBook, List<LessonSummary>>
lessonBookProvider = AsyncNotifierProvider<LessonBook, List<LessonSummary>>(
  LessonBook.new,
);

class LessonBook extends AsyncNotifier<List<LessonSummary>> {
  Future<void> _writes = Future<void>.value();

  @override
  Future<List<LessonSummary>> build() async =>
      (await ref.watch(lessonStoreProvider.future)).loadSummaries();

  Future<IntensiveLesson?> find(String id) async =>
      (await ref.read(lessonStoreProvider.future)).find(id);

  Future<void> save(IntensiveLesson lesson) => _write(() async {
    await future;
    await (await ref.read(lessonStoreProvider.future)).save(lesson);
    state = AsyncData<List<LessonSummary>>(<LessonSummary>[
      LessonSummary.fromLesson(lesson),
      ...state.requireValue.where((LessonSummary item) => item.id != lesson.id),
    ]);
  });

  Future<void> delete(String id) => _write(() async {
    await future;
    await (await ref.read(lessonStoreProvider.future)).delete(id);
    state = AsyncData<List<LessonSummary>>(
      state.requireValue
          .where((LessonSummary item) => item.id != id)
          .toList(growable: false),
    );
  });

  Future<void> _write(Future<void> Function() action) {
    final Future<void> result = _writes.then((_) => action());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
