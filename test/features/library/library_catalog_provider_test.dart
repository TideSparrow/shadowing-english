import 'dart:convert';
import 'dart:io';

import 'package:common_learn_english/features/import_course/domain/import_match.dart';
import 'package:common_learn_english/features/import_course/domain/video_cover_extractor.dart';
import 'package:common_learn_english/features/library/presentation/library_catalog_provider.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:common_learn_english/features/shared/presentation/media/cover_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

class _FakeVideoCoverExtractor implements VideoCoverExtractor {
  _FakeVideoCoverExtractor({
    this.courseCoverPath,
    this.failCourseCover = false,
    Map<String, String>? episodeCoverPaths,
  }) : episodeCoverPaths = episodeCoverPaths ?? <String, String>{};

  final String? courseCoverPath;
  final bool failCourseCover;
  final Map<String, String> episodeCoverPaths;
  int courseCoverCallCount = 0;
  int episodeCoverCallCount = 0;

  @override
  Future<String?> extractCourseCover({
    required String courseId,
    required String videoPath,
    String? fallbackEpisodeCoverPath,
  }) async {
    courseCoverCallCount += 1;
    if (failCourseCover) {
      return fallbackEpisodeCoverPath;
    }
    return courseCoverPath;
  }

  @override
  Future<String?> extractEpisodeCover({
    required String courseId,
    required String episodeId,
    required String videoPath,
  }) async {
    episodeCoverCallCount += 1;
    return episodeCoverPaths[videoPath];
  }
}

void main() {
  group('LibraryCatalogNotifier', () {
    late Directory hiveDir;

    setUp(() async {
      hiveDir = Directory.systemTemp.createTempSync('library-cover-test-');
      Hive.init(hiveDir.path);
      await Hive.openBox<String>('prefs');
    });

    tearDown(() async {
      await Hive.box<String>('prefs').close();
      await Hive.deleteBoxFromDisk('prefs');
      hiveDir.deleteSync(recursive: true);
    });

    test(
      'imported course skips all cover extraction and uses placeholder art',
      () async {
        final _FakeVideoCoverExtractor extractor = _FakeVideoCoverExtractor(
          courseCoverPath: '/tmp/course.jpg',
          episodeCoverPaths: <String, String>{'/tmp/video1.rm': '/tmp/ep1.jpg'},
        );
        final ProviderContainer container = ProviderContainer(
          // ignore: always_specify_types
          overrides: [videoCoverExtractorProvider.overrideWithValue(extractor)],
        );
        addTearDown(container.dispose);

        final LibraryCatalogNotifier notifier = container.read(
          libraryCatalogProvider.notifier,
        );

        final bool imported = await notifier.importCourseFromMatches(
          rows: <ImportMatchRow>[
            _makeRow(videoPath: '/tmp/video1.rm', videoFile: 'video1.rm'),
          ],
          videoFolder: '/tmp/videos',
          subtitleFolder: '/tmp/subtitles',
        );

        expect(imported, isTrue);
        expect(container.read(libraryCatalogProvider).first.coverImage, '');
        expect(
          container
              .read(libraryCatalogProvider)
              .first
              .episodes
              .first
              .coverImage,
          '',
        );
        expect(extractor.courseCoverCallCount, 0);
        expect(extractor.episodeCoverCallCount, 0);
        expect(
          container
              .read(libraryCatalogProvider)
              .first
              .episodes
              .first
              .cnSubtitleAsset,
          '/tmp/cn.srt',
        );
        expect(
          container
              .read(libraryCatalogProvider)
              .first
              .episodes
              .first
              .subtitleTracks
              .map((LibrarySubtitleTrackItem item) => item.languageCode),
          <String>['en', 'zh'],
        );
      },
    );

    test(
      'import still succeeds when extractor would fail because extractor is unused',
      () async {
        final _FakeVideoCoverExtractor extractor = _FakeVideoCoverExtractor(
          failCourseCover: true,
          episodeCoverPaths: <String, String>{'/tmp/video1.rm': '/tmp/ep1.jpg'},
        );
        final ProviderContainer container = ProviderContainer(
          // ignore: always_specify_types
          overrides: [videoCoverExtractorProvider.overrideWithValue(extractor)],
        );
        addTearDown(container.dispose);

        final LibraryCatalogNotifier notifier = container.read(
          libraryCatalogProvider.notifier,
        );

        final bool imported = await notifier.importCourseFromMatches(
          rows: <ImportMatchRow>[
            _makeRow(videoPath: '/tmp/video1.rm', videoFile: 'video1.rm'),
          ],
          videoFolder: '/tmp/videos',
          subtitleFolder: '/tmp/subtitles',
        );

        expect(imported, isTrue);
        expect(container.read(libraryCatalogProvider).first.coverImage, '');
        expect(extractor.courseCoverCallCount, 0);
        expect(extractor.episodeCoverCallCount, 0);
      },
    );

    test('import uses folder name and local source metadata', () async {
      final ProviderContainer container = ProviderContainer(
        // ignore: always_specify_types
        overrides: [
          videoCoverExtractorProvider.overrideWithValue(
            _FakeVideoCoverExtractor(
              courseCoverPath: '/tmp/course.jpg',
              episodeCoverPaths: <String, String>{
                '/tmp/My.Show/video1.rm': '/tmp/ep1.jpg',
              },
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final LibraryCatalogNotifier notifier = container.read(
        libraryCatalogProvider.notifier,
      );

      final bool imported = await notifier.importCourseFromMatches(
        rows: <ImportMatchRow>[
          _makeRow(videoPath: '/tmp/My.Show/video1.rm', videoFile: 'video1.rm'),
        ],
        videoFolder: '/tmp/My.Show',
        subtitleFolder: '/tmp/subtitles',
      );

      expect(imported, isTrue);
      final LibraryCourseData course = container
          .read(libraryCatalogProvider)
          .first;
      expect(course.title, 'My.Show');
      expect(course.description, '已导入课程 1 集');
      expect(course.sourceLabel, '本地资源');
      expect(course.coverImage, '');
    });

    test(
      'recent courses follow actual playback time, including rewatches, and survive restart',
      () async {
        final ProviderContainer container = ProviderContainer();
        addTearDown(container.dispose);
        final LibraryCatalogNotifier notifier = container.read(
          libraryCatalogProvider.notifier,
        );
        await notifier.importCourseFromMatches(
          rows: <ImportMatchRow>[
            _makeRow(videoPath: '/tmp/peppa/01.mp4', videoFile: '01.mp4'),
          ],
          videoFolder: '/tmp/peppa',
          subtitleFolder: '/tmp/peppa',
        );
        final LibraryCourseData peppa = container
            .read(libraryCatalogProvider)
            .first;
        await notifier.importCourseFromMatches(
          rows: <ImportMatchRow>[
            _makeRow(videoPath: '/tmp/sheldon/01.mp4', videoFile: '01.mp4'),
          ],
          videoFolder: '/tmp/sheldon',
          subtitleFolder: '/tmp/sheldon',
        );
        final LibraryCourseData sheldon = container
            .read(libraryCatalogProvider)
            .first;
        expect(
          container
              .read(recentLearningCoursesProvider)
              .map((LibraryCourseData course) => course.id),
          <String>[sheldon.id, peppa.id],
        );
        expect(
          container
              .read(libraryCatalogProvider)
              .every(
                (LibraryCourseData course) => course.lastStudiedAtMs == null,
              ),
          isTrue,
        );
        final DateTime start = DateTime.utc(2026, 10, 23);
        await notifier.updateEpisodeProgress(
          episodeId: peppa.episodes.first.id,
          position: const Duration(seconds: 50),
          duration: const Duration(seconds: 100),
          occurredAt: start,
        );
        await notifier.updateEpisodeProgress(
          episodeId: sheldon.episodes.first.id,
          position: const Duration(seconds: 50),
          duration: const Duration(seconds: 100),
          occurredAt: start.add(const Duration(seconds: 1)),
        );
        expect(
          container.read(recentLearningCoursesProvider).first.id,
          sheldon.id,
        );
        final DateTime replayedAt = start.add(const Duration(seconds: 2));
        await notifier.updateEpisodeProgress(
          episodeId: peppa.episodes.first.id,
          position: const Duration(seconds: 10),
          duration: const Duration(seconds: 100),
          occurredAt: replayedAt,
        );
        expect(
          container.read(recentLearningCoursesProvider).first.id,
          peppa.id,
        );
        expect(container.read(libraryCatalogProvider).first.id, sheldon.id);
        final LibraryCourseData replayed = container
            .read(recentLearningCoursesProvider)
            .first;
        expect(replayed.lastStudiedAtMs, replayedAt.millisecondsSinceEpoch);
        expect(replayed.episodes.first.progressPercent, 50);
        // Equal timestamps keep the catalog order, instead of shuffling cards.
        await notifier.updateEpisodeProgress(
          episodeId: sheldon.episodes.first.id,
          position: const Duration(seconds: 10),
          duration: const Duration(seconds: 100),
          occurredAt: replayedAt,
        );
        expect(
          container
              .read(recentLearningCoursesProvider)
              .map((LibraryCourseData course) => course.id),
          <String>[sheldon.id, peppa.id],
        );
        final ProviderContainer restored = ProviderContainer();
        addTearDown(restored.dispose);
        expect(
          restored
              .read(libraryCatalogProvider)
              .every(
                (LibraryCourseData course) =>
                    course.lastStudiedAtMs == replayedAt.millisecondsSinceEpoch,
              ),
          isTrue,
        );
        expect(
          restored
              .read(recentLearningCoursesProvider)
              .map((LibraryCourseData course) => course.id),
          <String>[sheldon.id, peppa.id],
        );
        // Older saved libraries remain readable without the new field.
        final List<dynamic> oldData =
            jsonDecode(
                  Hive.box<String>('prefs').get('imported_library_courses_v1')!,
                )
                as List<dynamic>;
        for (final dynamic course in oldData) {
          (course as Map<String, dynamic>).remove('lastStudiedAtMs');
        }
        await Hive.box<String>(
          'prefs',
        ).put('imported_library_courses_v1', jsonEncode(oldData));
        final ProviderContainer legacy = ProviderContainer();
        addTearDown(legacy.dispose);
        expect(legacy.read(libraryCatalogProvider).length, 2);
        expect(
          legacy
              .read(libraryCatalogProvider)
              .every(
                (LibraryCourseData course) => course.lastStudiedAtMs == null,
              ),
          isTrue,
        );
        expect(
          legacy
              .read(recentLearningCoursesProvider)
              .map((LibraryCourseData course) => course.id),
          <String>[sheldon.id, peppa.id],
        );
      },
    );

    test('playing an episode updates its course completion', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final LibraryCatalogNotifier notifier = container.read(
        libraryCatalogProvider.notifier,
      );

      await notifier.importCourseFromMatches(
        rows: <ImportMatchRow>[
          _makeRow(videoPath: '/tmp/videos/video1.rm', videoFile: 'video1.rm'),
          _makeRow(videoPath: '/tmp/videos/video2.rm', videoFile: 'video2.rm'),
        ],
        videoFolder: '/tmp/videos',
        subtitleFolder: '/tmp/subtitles',
      );
      final String episodeId = container
          .read(libraryCatalogProvider)
          .first
          .episodes
          .first
          .id;

      await notifier.updateEpisodeProgress(
        episodeId: episodeId,
        position: const Duration(seconds: 50),
        duration: const Duration(seconds: 100),
      );

      final LibraryCourseData course = container
          .read(libraryCatalogProvider)
          .first;
      expect(course.episodes.first.progressPercent, 50);
      expect(course.episodes.first.progressTimeStr, '0:50');
      expect(course.episodes.first.totalTimeStr, '1:40');
      expect(course.progressPercent, 25);
      expect(course.lastStudiedStr, '刚刚学习');
    });

    test('import can append new episodes to an existing course', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final LibraryCatalogNotifier notifier = container.read(
        libraryCatalogProvider.notifier,
      );

      await notifier.importCourseFromMatches(
        rows: <ImportMatchRow>[
          _makeRow(
            episodeName: 'Peppa Pig S01E01',
            videoPath: '/tmp/peppa/01.mp4',
            videoFile: '01.mp4',
          ),
        ],
        videoFolder: '/tmp/peppa',
        subtitleFolder: '/tmp/subtitles',
        courseTitle: '小猪佩奇·第一季',
      );
      final String courseId = container.read(libraryCatalogProvider).first.id;

      final bool imported = await notifier.importCourseFromMatches(
        rows: <ImportMatchRow>[
          _makeRow(
            episodeName: 'Peppa Pig S01E02',
            videoPath: '/tmp/peppa/02.mp4',
            videoFile: '02.mp4',
          ),
        ],
        videoFolder: '/tmp/another-folder',
        subtitleFolder: '/tmp/subtitles',
        targetCourseId: courseId,
      );

      final LibraryCourseData course = container
          .read(libraryCatalogProvider)
          .first;
      expect(imported, isTrue);
      expect(course.title, '小猪佩奇·第一季');
      expect(course.totalEpisodes, 2);
      expect(
        course.episodes.map((LibraryEpisodeItem item) => item.videoAsset),
        <String?>['/tmp/peppa/01.mp4', '/tmp/peppa/02.mp4'],
      );
    });

    test(
      'importing same resource overwrites existing imported course',
      () async {
        final ProviderContainer firstContainer = ProviderContainer(
          // ignore: always_specify_types
          overrides: [
            videoCoverExtractorProvider.overrideWithValue(
              _FakeVideoCoverExtractor(
                courseCoverPath: '/tmp/course-v1.jpg',
                episodeCoverPaths: <String, String>{
                  '/tmp/videos/video1.rm': '/tmp/ep1-v1.jpg',
                },
              ),
            ),
          ],
        );
        addTearDown(firstContainer.dispose);

        final LibraryCatalogNotifier notifier = firstContainer.read(
          libraryCatalogProvider.notifier,
        );

        await notifier.importCourseFromMatches(
          rows: <ImportMatchRow>[
            _makeRow(
              videoPath: '/tmp/videos/video1.rm',
              videoFile: 'video1.rm',
            ),
          ],
          videoFolder: '/tmp/videos',
          subtitleFolder: '/tmp/subtitles',
        );

        final ProviderContainer secondContainer = ProviderContainer(
          // ignore: always_specify_types
          overrides: [
            videoCoverExtractorProvider.overrideWithValue(
              _FakeVideoCoverExtractor(
                courseCoverPath: '/tmp/course-v2.jpg',
                episodeCoverPaths: <String, String>{
                  '/tmp/videos/video1.rm': '/tmp/ep1-v2.jpg',
                  '/tmp/videos/video2.rm': '/tmp/ep2-v2.jpg',
                },
              ),
            ),
          ],
        );
        addTearDown(secondContainer.dispose);
        final LibraryCatalogNotifier secondNotifier = secondContainer.read(
          libraryCatalogProvider.notifier,
        );

        final bool imported = await secondNotifier.importCourseFromMatches(
          rows: <ImportMatchRow>[
            _makeRow(
              videoPath: '/tmp/videos/video1.rm',
              videoFile: 'video1.rm',
            ),
            _makeRow(
              videoPath: '/tmp/videos/video2.rm',
              videoFile: 'video2.rm',
            ),
          ],
          videoFolder: '/tmp/videos',
          subtitleFolder: '/tmp/subtitles',
        );

        expect(imported, isTrue);
        final LibraryCourseData course = secondContainer
            .read(libraryCatalogProvider)
            .first;
        expect(course.coverImage, '');
        expect(course.episodes, hasLength(2));
        expect(course.episodes.first.coverImage, '');
      },
    );

    test(
      'imported episodes keep unique ids when file names share same number',
      () async {
        final ProviderContainer firstContainer = ProviderContainer(
          // ignore: always_specify_types
          overrides: [
            videoCoverExtractorProvider.overrideWithValue(
              _FakeVideoCoverExtractor(),
            ),
          ],
        );
        addTearDown(firstContainer.dispose);

        final LibraryCatalogNotifier notifier = firstContainer.read(
          libraryCatalogProvider.notifier,
        );

        final bool imported = await notifier.importCourseFromMatches(
          rows: <ImportMatchRow>[
            _makeRow(
              episodeName: '01',
              videoPath: '/tmp/videos/01.rm',
              videoFile: '01.rm',
            ),
            _makeRow(
              episodeName: 'lesson01',
              videoPath: '/tmp/videos/lesson01.mp4',
              videoFile: 'lesson01.mp4',
            ),
          ],
          videoFolder: '/tmp/videos',
          subtitleFolder: '/tmp/subtitles',
        );

        expect(imported, isTrue);
        final List<LibraryEpisodeItem> firstEpisodes = firstContainer
            .read(libraryCatalogProvider)
            .first
            .episodes;
        final List<String> firstEpisodeIds = firstEpisodes
            .map((LibraryEpisodeItem item) => item.id)
            .toList(growable: false);
        expect(firstEpisodeIds, hasLength(2));
        expect(firstEpisodeIds.toSet(), hasLength(2));

        final ProviderContainer secondContainer = ProviderContainer(
          // ignore: always_specify_types
          overrides: [
            videoCoverExtractorProvider.overrideWithValue(
              _FakeVideoCoverExtractor(),
            ),
          ],
        );
        addTearDown(secondContainer.dispose);

        final List<LibraryEpisodeItem> reloadedEpisodes = secondContainer
            .read(libraryCatalogProvider)
            .first
            .episodes;
        final List<String> reloadedEpisodeIds = reloadedEpisodes
            .map((LibraryEpisodeItem item) => item.id)
            .toList(growable: false);
        expect(reloadedEpisodeIds, hasLength(2));
        expect(reloadedEpisodeIds.toSet(), hasLength(2));
      },
    );

    test('reload sanitizes imported verification sample episodes', () async {
      await Hive.box<String>('prefs').put(
        'imported_library_courses_v1',
        jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'id': 'imported-course',
            'title': '走遍美国',
            'description': '已导入课程 2 集',
            'sourceLabel': '本地资源',
            'coverImage': '',
            'level': '自定义',
            'category': '自选课程',
            'progressPercent': 0,
            'totalWords': 0,
            'completedEpisodes': 0,
            'totalEpisodes': 2,
            'lastStudiedStr': '刚刚导入',
            'rating': 4.7,
            'episodes': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'imported-course-ep01',
                'numberStr': '01',
                'title': '01',
                'durationMinutes': 30,
                'hasChineseSubtitles': true,
                'hasEnglishSubtitles': true,
                'completed': false,
                'progressPercent': 0,
                'coverImage': '',
                'videoAsset': '/tmp/videos/01.rm',
                'enSubtitleAsset': '/tmp/cle_verify/lesson01.en.srt',
                'cnSubtitleAsset': '/tmp/cle_verify/lesson01.zh.srt',
                'subtitleTracks': <Map<String, Object?>>[
                  <String, Object?>{
                    'languageCode': 'en',
                    'languageLabel': '英文字幕',
                    'path': '/tmp/cle_verify/lesson01.en.srt',
                  },
                ],
              },
              <String, Object?>{
                'id': 'imported-course-ep02',
                'numberStr': '02',
                'title': 'lesson01',
                'durationMinutes': 30,
                'hasChineseSubtitles': true,
                'hasEnglishSubtitles': true,
                'completed': false,
                'progressPercent': 0,
                'coverImage': '',
                'videoAsset': '/tmp/videos/lesson01.mp4',
                'enSubtitleAsset': '/tmp/cle_verify/lesson01.en.srt',
                'cnSubtitleAsset': '/tmp/cle_verify/lesson01.zh.srt',
                'subtitleTracks': <Map<String, Object?>>[
                  <String, Object?>{
                    'languageCode': 'en',
                    'languageLabel': '英文字幕',
                    'path': '/tmp/cle_verify/lesson01.en.srt',
                  },
                ],
              },
            ],
          },
        ]),
      );

      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final LibraryCourseData importedCourse = container
          .read(libraryCatalogProvider)
          .firstWhere((LibraryCourseData item) => item.id == 'imported-course');

      expect(importedCourse.totalEpisodes, 1);
      expect(importedCourse.episodes, hasLength(1));
      expect(importedCourse.episodes.single.title, '01');
      expect(importedCourse.episodes.single.videoAsset, '/tmp/videos/01.rm');
      expect(importedCourse.episodes.single.enSubtitleAsset, isNull);
      expect(importedCourse.episodes.single.cnSubtitleAsset, isNull);
      expect(importedCourse.episodes.single.subtitleTracks, isEmpty);
    });

    test('deleteCourses removes managed imported media directories', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync(
        'library-managed-import-delete-',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final Directory subtitleRoot = Directory(
        '${tempDir.path}/imported_sources/subtitles-batch',
      )..createSync(recursive: true);
      final Directory videoRoot = Directory(
        '${tempDir.path}/imported_sources/confirmed_imports/video-batch',
      )..createSync(recursive: true);
      final File englishSubtitle = File('${subtitleRoot.path}/01.srt')
        ..writeAsStringSync('hello');
      final File chineseSubtitle = File('${subtitleRoot.path}/01.zh.srt')
        ..writeAsStringSync('你好');
      final File videoFile = File('${videoRoot.path}/01.mp4')
        ..writeAsStringSync('video');

      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final LibraryCatalogNotifier notifier = container.read(
        libraryCatalogProvider.notifier,
      );

      final bool imported = await notifier.importCourseFromMatches(
        rows: <ImportMatchRow>[
          _makeRow(
            videoPath: videoFile.path,
            videoFile: '01.mp4',
            englishSubtitlePath: englishSubtitle.path,
            chineseSubtitlePath: chineseSubtitle.path,
          ),
        ],
        videoFolder: videoRoot.path,
        subtitleFolder: subtitleRoot.path,
      );

      expect(imported, isTrue);
      final String importedCourseId = container
          .read(libraryCatalogProvider)
          .first
          .id;

      await notifier.deleteCourses(<String>{importedCourseId});

      expect(videoRoot.existsSync(), isFalse);
      expect(subtitleRoot.existsSync(), isFalse);
    });
  });

  testWidgets('cover image renders a local file path without crashing', (
    WidgetTester tester,
  ) async {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'cover-image-widget-',
    );
    final File cover = File('${tempDir.path}/cover.jpg')
      ..writeAsBytesSync(<int>[0]);
    addTearDown(() => tempDir.deleteSync(recursive: true));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoverImage(
            path: cover.path,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Placeholder(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CoverImage), findsOneWidget);
  });
}

ImportMatchRow _makeRow({
  String episodeName = 'Ep 01',
  required String videoPath,
  required String videoFile,
  String englishSubtitlePath = '/tmp/en.srt',
  String chineseSubtitlePath = '/tmp/cn.srt',
}) {
  return ImportMatchRow(
    episodeName: episodeName,
    videoFile: videoFile,
    videoPath: videoPath,
    subtitleTracks: <String, ImportSubtitleTrack>{
      'en': ImportSubtitleTrack(
        languageCode: 'en',
        languageLabel: '英文字幕',
        path: englishSubtitlePath,
      ),
      'zh': ImportSubtitleTrack(
        languageCode: 'zh',
        languageLabel: '中文字幕',
        path: chineseSubtitlePath,
      ),
    },
    candidateSubtitles: <ImportSubtitleCandidate>[
      ImportSubtitleCandidate(
        path: englishSubtitlePath,
        languageCode: 'en',
        languageLabel: '英文字幕',
      ),
      ImportSubtitleCandidate(
        path: chineseSubtitlePath,
        languageCode: 'zh',
        languageLabel: '中文字幕',
      ),
    ],
  );
}
