// Native smoke-test entry point. Uses the production app and an isolated data
// directory, never the user's courses, credentials, or AI quota.
import 'dart:io';

import 'package:common_learn_english/features/lessons/data/lesson_store.dart';
import 'package:common_learn_english/features/lessons/domain/intensive_lesson.dart';
import 'package:common_learn_english/features/lessons/domain/lesson_context.dart';
import 'package:common_learn_english/features/library/presentation/library_catalog_provider.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:common_learn_english/features/player/presentation/player_subtitle_loader.dart';
import 'package:common_learn_english/flavors/app_flavor.dart';
import 'package:common_learn_english/main.dart' as production;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../test/features/lessons/lesson_fixture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final Directory directory = await Directory.systemTemp.createTemp(
    'shadowing-lessons-native-',
  );
  PathProviderPlatform.instance = _PreviewPaths(
    PathProviderPlatform.instance,
    directory.path,
  );
  Hive.init(directory.path);
  await Hive.openBox<String>('prefs');
  final String subtitlePath = '${directory.path}/demo.srt';
  const String subtitles =
      '1\n00:00:50,000 --> 00:00:52,000\nBreakfast is ready.\n\n'
      '2\n00:00:53,000 --> 00:00:54,000\nPhil, would you\n\n'
      '3\n00:00:54,100 --> 00:00:56,500\nget them?\n';
  await File(subtitlePath).writeAsString(subtitles);
  final ProviderContainer container = ProviderContainer();
  await container
      .read(libraryCatalogProvider.notifier)
      .importCourse(
        LibraryCourseData(
          id: 'native-preview',
          title: '样式验收 · 本地示例',
          description: '本地测试素材，未调用 AI。',
          sourceLabel: '本地示例',
          coverImage: '',
          level: 'B1',
          category: '本地示例',
          progressPercent: 0,
          totalWords: 0,
          completedEpisodes: 0,
          totalEpisodes: 1,
          lastStudiedStr: '',
          rating: 0,
          episodes: <LibraryEpisodeItem>[
            LibraryEpisodeItem(
              id: 'native-preview-episode',
              numberStr: '01',
              title: '本地对话示例',
              durationMinutes: 1,
              hasChineseSubtitles: false,
              hasEnglishSubtitles: true,
              completed: false,
              progressPercent: 0,
              coverImage: '',
              progressTimeStr: '00:53.000',
              enSubtitleAsset: subtitlePath,
              videoAsset: '/tmp/shadowing-lesson-native.mp4',
            ),
          ],
        ),
      );
  container.dispose();
  final LessonSource source = selectLessonContext(
    lines: parseSubtitleLines(subtitles),
    index: 1,
    episodeId: 'native-preview-episode',
    courseTitle: '样式验收 · 本地示例',
    episodeTitle: '本地对话示例',
  );
  final LazyBox<String> box = await Hive.openLazyBox<String>(
    'intensive_lessons_v1',
  );
  final LessonStore store = LessonStore(box);
  // ignore: do_not_use_environment
  final int count = const int.fromEnvironment(
    'LESSON_PREVIEW_COUNT',
    defaultValue: 1,
  ).clamp(1, 1000);
  for (int index = 0; index < count; index++) {
    await store.save(
      IntensiveLesson.fromContent(
        source: index == 0
            ? source
            : LessonSource(
                episodeId: index < 30
                    ? source.episodeId
                    : 'native-extra-episode',
                courseTitle: index < 30 ? source.courseTitle : '日常口语 · 本地示例',
                episodeTitle: '本地对话示例 ${index + 1}',
                startMs: 53000 + index * 1000,
                endMs: 56500 + index * 1000,
                english: source.english,
                context: source.context,
                boundaryLimited: false,
              ),
        json: lessonContent(),
        createdAt: DateTime.now().subtract(Duration(minutes: index)),
        model: '本地示例（无 API 调用）',
        usage: const LessonTokenUsage(input: 0, output: 0, total: 0),
      ),
    );
  }
  await box.close();
  await Hive.box<String>('prefs').close();
  FlavorConfig.setFlavor(AppFlavor.dev);
  await production.bootstrap();
}

class _PreviewPaths extends PathProviderPlatform {
  _PreviewPaths(this.delegate, this.path);
  final PathProviderPlatform delegate;
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getTemporaryPath() => delegate.getTemporaryPath();
  @override
  Future<String?> getApplicationDocumentsPath() =>
      delegate.getApplicationDocumentsPath();
  @override
  Future<String?> getDownloadsPath() => delegate.getDownloadsPath();
  @override
  Future<String?> getApplicationCachePath() =>
      delegate.getApplicationCachePath();
}
