import 'dart:io';

import 'package:common_learn_english/features/library/presentation/course_directory_relink.dart';
import 'package:common_learn_english/features/library/presentation/library_catalog_provider.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

LibraryEpisodeItem episode(
  String id,
  String path, {
  String? subtitle,
  int progress = 40,
}) => LibraryEpisodeItem(
  id: id,
  numberStr: '01',
  title: resourceFileName(path),
  durationMinutes: 10,
  hasChineseSubtitles: false,
  hasEnglishSubtitles: subtitle != null,
  completed: false,
  progressPercent: progress,
  coverImage: '',
  videoAsset: path,
  enSubtitleAsset: subtitle,
  subtitleTracks: subtitle == null
      ? const <LibrarySubtitleTrackItem>[]
      : <LibrarySubtitleTrackItem>[
          LibrarySubtitleTrackItem(
            languageCode: 'en',
            languageLabel: '英文',
            path: subtitle,
          ),
        ],
);

LibraryCourseData courseWith(List<LibraryEpisodeItem> episodes) =>
    LibraryCourseData(
      id: 'peppa',
      title: '小猪佩奇',
      description: '',
      sourceLabel: '本地资源',
      coverImage: '',
      level: '',
      category: '',
      progressPercent: 40,
      totalWords: 8,
      completedEpisodes: 0,
      totalEpisodes: episodes.length,
      lastStudiedStr: '昨天',
      lastStudiedAtMs: 123,
      rating: 0,
      episodes: episodes,
      videoDirectories: const <String>['/old'],
    );

void main() {
  test(
    'relative paths distinguish seasons; missing records and learning data survive',
    () {
      final LibraryCourseData original = courseWith(<LibraryEpisodeItem>[
        episode(
          'one',
          '/old/Season1/ep01.mp4',
          subtitle: '/old/Season1/ep01.en.srt',
        ),
        episode('two', '/old/Season2/ep01.mp4'),
        episode('three', '/old/missing.mp4'),
      ]);
      final CourseDirectoryRelinkPlan plan = buildCourseDirectoryRelinkPlan(
        course: original,
        oldRoot: '/old',
        newRoot: '/new',
        subtitlesOnly: false,
        videoFiles: <String>[
          '/new/Season1/ep01.mp4',
          '/new/Season2/ep01.mp4',
          '/new/extra.mp4',
        ],
        subtitleFiles: <String>['/new/Season1/ep01.en.srt'],
      );
      final LibraryCourseData updated = plan.apply(
        original,
        plan.initialSelections,
        <String>{},
      );
      expect(updated.episodes.map((LibraryEpisodeItem e) => e.id), <String>[
        'one',
        'two',
        'three',
      ]);
      expect(updated.episodes.first.videoAsset, '/new/Season1/ep01.mp4');
      expect(updated.episodes[1].videoAsset, '/new/Season2/ep01.mp4');
      expect(
        updated.episodes.first.enSubtitleAsset,
        '/new/Season1/ep01.en.srt',
      );
      expect(
        updated.episodes.first.subtitleTracks.single.path,
        '/new/Season1/ep01.en.srt',
      );
      expect(updated.episodes.last.videoMissing, isTrue);
      expect(updated.episodes.last.videoAsset, '/old/missing.mp4');
      expect(updated.episodes.first.progressPercent, 40);
      expect(updated.totalWords, 8);
      expect(updated.lastStudiedAtMs, 123);
      expect(updated.videoDirectories, containsAll(<String>['/old', '/new']));
      expect(plan.newVideos.single.videoFile, 'extra.mp4');
      expect(updated.episodes.length, 3);
      expect(
        plan
            .apply(original, plan.initialSelections, <String>{'/new/extra.mp4'})
            .episodes
            .length,
        4,
      );
    },
  );

  test(
    'ambiguous filenames require a selection; a file cannot replace two old files',
    () {
      final LibraryCourseData original = courseWith(<LibraryEpisodeItem>[
        episode('one', '/old/ep01.mp4'),
      ]);
      final CourseDirectoryRelinkPlan ambiguous =
          buildCourseDirectoryRelinkPlan(
            course: original,
            oldRoot: '/old',
            newRoot: '/new',
            subtitlesOnly: false,
            videoFiles: <String>['/new/a/ep01.mp4', '/new/b/ep01.mp4'],
            subtitleFiles: <String>[],
          );
      expect(ambiguous.initialSelections, isEmpty);
      expect(ambiguous.files.single.candidates.length, 2);
      expect(ambiguous.newVideos, isEmpty);
      final LibraryCourseData duplicate = courseWith(<LibraryEpisodeItem>[
        episode('one', '/old/a/ep01.mp4'),
        episode('two', '/old/b/ep01.mp4'),
      ]);
      final CourseDirectoryRelinkPlan collision =
          buildCourseDirectoryRelinkPlan(
            course: duplicate,
            oldRoot: '/old',
            newRoot: '/new',
            subtitlesOnly: false,
            videoFiles: <String>['/new/ep01.mp4'],
            subtitleFiles: <String>[],
          );
      expect(collision.initialSelections, isEmpty);
      expect(
        () => collision.apply(duplicate, <String, String>{
          '/old/a/ep01.mp4': '/new/ep01.mp4',
          '/old/b/ep01.mp4': '/new/ep01.mp4',
        }, <String>{}),
        throwsStateError,
      );
    },
  );

  test(
    'subtitle-only relink leaves video and ID unchanged, and supports old catalogs',
    () {
      final LibraryCourseData original = courseWith(<LibraryEpisodeItem>[
        episode('one', '/video/ep01.mp4', subtitle: '/subs/ep01.en.srt'),
      ]).copyWith(videoDirectories: <String>[]);
      expect(courseResourceDirectories(original, subtitles: false), <String>[
        '/video',
      ]);
      expect(courseResourceDirectories(original, subtitles: true), <String>[
        '/subs',
      ]);
      final CourseDirectoryRelinkPlan plan = buildCourseDirectoryRelinkPlan(
        course: original,
        oldRoot: '/subs',
        newRoot: '/new',
        subtitlesOnly: true,
        videoFiles: <String>['/new/extra.mp4'],
        subtitleFiles: <String>['/new/ep01.en.srt'],
      );
      final LibraryCourseData updated = plan.apply(
        original,
        plan.initialSelections,
        <String>{},
      );
      expect(updated.episodes.single.videoAsset, '/video/ep01.mp4');
      expect(updated.episodes.single.id, 'one');
      expect(updated.episodes.single.enSubtitleAsset, '/new/ep01.en.srt');
      expect(plan.newVideos, isEmpty);
      expect(
        plan.isCurrent(
          original.copyWith(
            episodes: <LibraryEpisodeItem>[
              original.episodes.single.copyWith(videoAsset: '/another.mp4'),
            ],
          ),
        ),
        isFalse,
      );
      expect(
        plan.isCurrent(
          original.copyWith(
            episodes: <LibraryEpisodeItem>[
              original.episodes.single.copyWith(progressPercent: 80),
            ],
          ),
        ),
        isTrue,
      );
    },
  );

  test('real scan, persist, reopen and recover a missing file', () async {
    final Directory temp = Directory.systemTemp.createTempSync(
      'directory-relink-',
    );
    Hive.init('${temp.path}/prefs');
    await Hive.openBox<String>('prefs');
    addTearDown(() async {
      await Hive.close();
      temp.deleteSync(recursive: true);
    });
    final Directory oldRoot = Directory('${temp.path}/old')..createSync();
    final Directory newRoot = Directory('${temp.path}/new')..createSync();
    File('${newRoot.path}/ep01.mp4').writeAsStringSync('video');
    final LibraryCourseData original = courseWith(<LibraryEpisodeItem>[
      episode('one', '${oldRoot.path}/ep01.mp4'),
      episode('two', '${oldRoot.path}/ep02.mp4'),
    ]).copyWith(videoDirectories: <String>[oldRoot.path]);
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(libraryCatalogProvider.notifier)
        .importCourse(original);
    final CourseDirectoryRelinkPlan plan = await scanCourseDirectory(
      course: original,
      oldRoot: oldRoot.path,
      newRoot: newRoot.path,
      subtitlesOnly: false,
    );
    await container
        .read(libraryCatalogProvider.notifier)
        .relinkDirectory(
          plan: plan,
          selections: plan.initialSelections,
          addedVideoPaths: <String>{},
        );
    container.invalidate(libraryCatalogProvider);
    final LibraryCourseData loaded = container
        .read(libraryCatalogProvider)
        .single;
    expect(loaded.episodes.first.videoAsset, '${newRoot.path}/ep01.mp4');
    expect(loaded.episodes.last.videoMissing, isTrue);
    expect(loaded.videoDirectories, contains(newRoot.path));
    File('${newRoot.path}/ep02.mp4').writeAsStringSync('restored');
    final CourseDirectoryRelinkPlan repair = await scanCourseDirectory(
      course: loaded,
      oldRoot: oldRoot.path,
      newRoot: newRoot.path,
      subtitlesOnly: false,
    );
    await container
        .read(libraryCatalogProvider.notifier)
        .relinkDirectory(
          plan: repair,
          selections: repair.initialSelections,
          addedVideoPaths: <String>{},
        );
    expect(
      container.read(libraryCatalogProvider).single.episodes.last.videoMissing,
      isFalse,
    );
    expect(
      container
          .read(libraryCatalogProvider)
          .single
          .episodes
          .last
          .progressPercent,
      40,
    );
  });
}
