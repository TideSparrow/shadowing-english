import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../import_course/domain/import_match.dart';
import '../../player/presentation/asr_subtitle_cache.dart';
import 'course_directory_relink.dart';
import 'library_mock_data.dart';

const String _libraryCatalogStorageKey = 'imported_library_courses_v1';

final NotifierProvider<LibraryCatalogNotifier, List<LibraryCourseData>>
libraryCatalogProvider =
    NotifierProvider<LibraryCatalogNotifier, List<LibraryCourseData>>(
      LibraryCatalogNotifier.new,
    );

final Provider<List<LibraryCourseData>> recentLearningCoursesProvider =
    Provider<List<LibraryCourseData>>((Ref ref) {
      final List<MapEntry<int, LibraryCourseData>> courses =
          ref.watch(libraryCatalogProvider).asMap().entries.toList()..sort((
            MapEntry<int, LibraryCourseData> a,
            MapEntry<int, LibraryCourseData> b,
          ) {
            final int byTime = (b.value.lastStudiedAtMs ?? 0).compareTo(
              a.value.lastStudiedAtMs ?? 0,
            );
            return byTime == 0 ? a.key.compareTo(b.key) : byTime;
          });
      return courses
          .map((MapEntry<int, LibraryCourseData> item) => item.value)
          .toList(growable: false);
    });

class LibraryCatalogNotifier extends Notifier<List<LibraryCourseData>> {
  String? _lastStudiedCourseId;

  @override
  List<LibraryCourseData> build() {
    const List<LibraryCourseData> baseCatalog = libraryCourses;

    if (!Hive.isBoxOpen('prefs')) {
      return baseCatalog;
    }

    final String? stored = Hive.box<String>(
      'prefs',
    ).get(_libraryCatalogStorageKey);
    if (stored == null || stored.isEmpty) {
      return baseCatalog;
    }

    return <LibraryCourseData>[...baseCatalog, ..._decodeCourses(stored)];
  }

  Future<bool> importCourse(LibraryCourseData course) async {
    if (libraryCourses.any((LibraryCourseData item) => item.id == course.id)) {
      return false;
    }
    state = <LibraryCourseData>[
      course,
      ...state.where((LibraryCourseData item) => item.id != course.id),
    ];
    await _persistImportedCourses();
    return true;
  }

  Future<void> relinkDirectory({
    required CourseDirectoryRelinkPlan plan,
    required Map<String, String> selections,
    required Set<String> addedVideoPaths,
    AsrSubtitleCache subtitleCache = const AsrSubtitleCache(),
  }) async {
    for (final String path in <String>{
      ...selections.values,
      ...addedVideoPaths,
    }) {
      if (!File(path).existsSync()) {
        throw StateError('部分文件已移动或无法访问，请重新扫描。');
      }
    }
    final int index = state.indexWhere(
      (LibraryCourseData item) => item.id == plan.course.id,
    );
    if (index < 0) throw StateError('课程已被删除，请重新打开。');
    final LibraryCourseData current = state[index];
    if (!plan.isCurrent(current)) throw StateError('课程资源已变化，请重新扫描。');
    final LibraryCourseData updated = plan.apply(
      current,
      selections,
      addedVideoPaths,
    );
    // Persist before publishing, so a failed write cannot leave a partial update.
    final List<LibraryCourseData> next = <LibraryCourseData>[...state];
    next[index] = updated;
    if (Hive.isBoxOpen('prefs')) {
      await Hive.box<String>('prefs').put(
        _libraryCatalogStorageKey,
        jsonEncode(next.map(_serializeCourse).toList()),
      );
    }
    state = next;
    for (final LibraryEpisodeItem episode in current.episodes) {
      final String? oldPath = episode.videoAsset;
      final String? newPath = selections[oldPath];
      if (oldPath == null || newPath == null || oldPath == newPath) continue;
      try {
        await subtitleCache.relinkVideo(
          episodeId: episode.id,
          oldPath: oldPath,
          newPath: newPath,
        );
      } catch (_) {
        // Optional cache metadata must never prevent a confirmed directory move.
      }
    }
  }

  Future<void> updateCoursesMetadata({
    required Set<String> courseIds,
    String? title,
    String? sourceLabel,
    String? coverImage,
  }) async {
    if (courseIds.isEmpty) {
      return;
    }
    state = state
        .map((LibraryCourseData course) {
          if (!courseIds.contains(course.id)) {
            return course;
          }
          return course.copyWith(
            title: title == null || title.trim().isEmpty ? null : title.trim(),
            sourceLabel: sourceLabel == null || sourceLabel.trim().isEmpty
                ? null
                : sourceLabel.trim(),
            coverImage: coverImage == null || coverImage.trim().isEmpty
                ? null
                : coverImage.trim(),
          );
        })
        .toList(growable: false);
    await _persistImportedCourses();
  }

  Future<void> updateEpisodeProgress({
    required String episodeId,
    required Duration position,
    required Duration duration,
    DateTime? occurredAt,
  }) async {
    if (duration <= Duration.zero || position <= Duration.zero) {
      return;
    }
    final int nextProgress =
        ((position.inMilliseconds * 100) / duration.inMilliseconds)
            .round()
            .clamp(0, 100);
    final int studiedAtMs =
        (occurredAt ?? DateTime.now()).millisecondsSinceEpoch;
    bool changed = false;
    final List<LibraryCourseData> updated = state
        .map((LibraryCourseData course) {
          final LibraryEpisodeItem? current = course.episodes
              .where((LibraryEpisodeItem item) => item.id == episodeId)
              .firstOrNull;
          if (current == null) return course;
          final bool progressChanged = nextProgress > current.progressPercent;
          // Record rewatching too, without writing to disk on every video tick.
          final bool refreshRecency =
              _lastStudiedCourseId != course.id ||
              course.lastStudiedAtMs == null ||
              studiedAtMs - course.lastStudiedAtMs! >= 10000;
          _lastStudiedCourseId = course.id;
          if (!progressChanged && !refreshRecency) return course;
          changed = true;
          if (!progressChanged) {
            return course.copyWith(
              lastStudiedAtMs: studiedAtMs,
              lastStudiedStr: '刚刚学习',
            );
          }
          final List<LibraryEpisodeItem> episodes = course.episodes
              .map(
                (LibraryEpisodeItem item) => item.id == episodeId
                    ? item.copyWith(
                        progressPercent: nextProgress,
                        completed: nextProgress == 100,
                        lastWatchedStr: '刚刚学习',
                        progressTimeStr: _formatDuration(position),
                        totalTimeStr: _formatDuration(duration),
                      )
                    : item,
              )
              .toList(growable: false);
          final int completedEpisodes = episodes
              .where((LibraryEpisodeItem item) => item.completed)
              .length;
          final int courseProgress =
              (episodes.fold<int>(0, (int sum, LibraryEpisodeItem item) {
                        return sum + item.progressPercent;
                      }) /
                      episodes.length)
                  .round();
          return course.copyWith(
            episodes: episodes,
            progressPercent: courseProgress,
            completedEpisodes: completedEpisodes,
            lastStudiedStr: '刚刚学习',
            lastStudiedAtMs: studiedAtMs,
          );
        })
        .toList(growable: false);
    if (changed) {
      state = updated;
      await _persistImportedCourses();
    }
  }

  String _formatDuration(Duration duration) {
    final int totalSeconds = duration.inSeconds;
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> deleteCourses(Set<String> courseIds) async {
    if (courseIds.isEmpty) {
      return;
    }
    final List<LibraryCourseData> removedCourses = state
        .where((LibraryCourseData course) => courseIds.contains(course.id))
        .toList(growable: false);
    state = state
        .where((LibraryCourseData course) => !courseIds.contains(course.id))
        .toList(growable: false);
    await _deleteManagedImportDirectories(removedCourses);
    await _persistImportedCourses();
  }

  Future<bool> importCourseFromMatches({
    required List<ImportMatchRow> rows,
    required String videoFolder,
    required String subtitleFolder,
    String sourceLabel = '本地资源',
    String? targetCourseId,
    String? courseTitle,
  }) async {
    if (rows.isEmpty) {
      return false;
    }

    final LibraryCourseData? targetCourse = targetCourseId == null
        ? null
        : state
              .where((LibraryCourseData item) => item.id == targetCourseId)
              .firstOrNull;
    if (targetCourseId != null && targetCourse == null) {
      return false;
    }

    final String courseId =
        targetCourse?.id ?? _buildCourseId(videoFolder, rows);
    final List<ImportMatchRow> newRows = targetCourse == null
        ? rows
        : rows
              .where(
                (ImportMatchRow row) => !targetCourse.episodes.any(
                  (LibraryEpisodeItem episode) =>
                      episode.videoAsset == row.videoPath,
                ),
              )
              .toList(growable: false);
    if (newRows.isEmpty) {
      return false;
    }
    final Set<String> occupiedIds =
        targetCourse?.episodes.map((LibraryEpisodeItem e) => e.id).toSet() ??
        <String>{};
    final List<LibraryEpisodeItem> episodes = <LibraryEpisodeItem>[
      for (int index = 0; index < newRows.length; index++)
        _buildEpisodeItem(
          newRows[index],
          courseId: courseId,
          episodeId: _buildEpisodeId(
            courseId,
            newRows[index],
            (targetCourse?.episodes.length ?? 0) + index,
            occupiedIds,
          ),
          coverImage: '',
        ),
    ];

    if (targetCourse != null) {
      final List<LibraryEpisodeItem> mergedEpisodes = <LibraryEpisodeItem>[
        ...targetCourse.episodes,
        ...episodes,
      ];
      state = state
          .map(
            (LibraryCourseData course) => course.id == targetCourse.id
                ? course.copyWith(
                    description: '已导入课程 ${mergedEpisodes.length} 集',
                    totalEpisodes: mergedEpisodes.length,
                    episodes: mergedEpisodes,
                    videoDirectories: <String>{
                      ...course.videoDirectories,
                      videoFolder,
                    }.where((String path) => path.isNotEmpty).toList(),
                    subtitleDirectories: <String>{
                      ...course.subtitleDirectories,
                      subtitleFolder,
                    }.where((String path) => path.isNotEmpty).toList(),
                  )
                : course,
          )
          .toList(growable: false);
      await _persistImportedCourses();
      return true;
    }

    return importCourse(
      LibraryCourseData(
        id: courseId,
        videoDirectories: videoFolder.isEmpty
            ? const <String>[]
            : <String>[videoFolder],
        subtitleDirectories: subtitleFolder.isEmpty
            ? const <String>[]
            : <String>[subtitleFolder],
        title: courseTitle == null || courseTitle.trim().isEmpty
            ? _buildCourseTitle(videoFolder, rows)
            : courseTitle.trim(),
        description: '已导入课程 ${episodes.length} 集',
        sourceLabel: sourceLabel,
        coverImage: '',
        level: '自定义',
        category: '自选课程',
        progressPercent: 0,
        totalWords: 0,
        completedEpisodes: 0,
        totalEpisodes: episodes.length,
        lastStudiedStr: '刚刚导入',
        rating: 4.7,
        episodes: episodes,
      ),
    );
  }

  Future<void> _persistImportedCourses() async {
    if (!Hive.isBoxOpen('prefs')) {
      return;
    }

    final List<Map<String, Object?>> importedCourses = state
        .where(
          (LibraryCourseData course) => !libraryCourses.any(
            (LibraryCourseData base) => base.id == course.id,
          ),
        )
        .map(_serializeCourse)
        .toList(growable: false);

    if (importedCourses.isEmpty) {
      await Hive.box<String>('prefs').delete(_libraryCatalogStorageKey);
      return;
    }

    await Hive.box<String>(
      'prefs',
    ).put(_libraryCatalogStorageKey, jsonEncode(importedCourses));
  }

  Map<String, Object?> _serializeCourse(LibraryCourseData course) {
    return <String, Object?>{
      'id': course.id,
      'videoDirectories': course.videoDirectories,
      'subtitleDirectories': course.subtitleDirectories,
      'title': course.title,
      'description': course.description,
      'sourceLabel': course.sourceLabel,
      'coverImage': course.coverImage,
      'level': course.level,
      'category': course.category,
      'progressPercent': course.progressPercent,
      'totalWords': course.totalWords,
      'completedEpisodes': course.completedEpisodes,
      'totalEpisodes': course.totalEpisodes,
      'lastStudiedStr': course.lastStudiedStr,
      'lastStudiedAtMs': course.lastStudiedAtMs,
      'rating': course.rating,
      'episodes': course.episodes
          .map(
            (LibraryEpisodeItem item) => <String, Object?>{
              'id': item.id,
              'numberStr': item.numberStr,
              'title': item.title,
              'durationMinutes': item.durationMinutes,
              'hasChineseSubtitles': item.hasChineseSubtitles,
              'hasEnglishSubtitles': item.hasEnglishSubtitles,
              'completed': item.completed,
              'progressPercent': item.progressPercent,
              'coverImage': item.coverImage,
              'lastWatchedStr': item.lastWatchedStr,
              'progressTimeStr': item.progressTimeStr,
              'totalTimeStr': item.totalTimeStr,
              'videoAsset': item.videoAsset,
              'videoMissing': item.videoMissing,
              'enSubtitleAsset': item.enSubtitleAsset,
              'cnSubtitleAsset': item.cnSubtitleAsset,
              'subtitleTracks': item.subtitleTracks
                  .map(
                    (LibrarySubtitleTrackItem track) => <String, Object?>{
                      'languageCode': track.languageCode,
                      'languageLabel': track.languageLabel,
                      'path': track.path,
                    },
                  )
                  .toList(growable: false),
            },
          )
          .toList(growable: false),
    };
  }

  List<LibraryCourseData> _decodeCourses(String raw) {
    try {
      final List<Object?> parsed = jsonDecode(raw) as List<Object?>;
      return parsed
          .cast<Map<String, Object?>>()
          .map((Map<String, Object?> courseJson) {
            final List<LibraryEpisodeItem> episodes = _decodeEpisodes(
              courseId: courseJson['id']! as String,
              episodesJson: courseJson['episodes'] as List<Object?>?,
            );

            return LibraryCourseData(
              id: courseJson['id']! as String,
              videoDirectories:
                  (courseJson['videoDirectories'] as List<Object?>? ??
                          const <Object?>[])
                      .cast<String>(),
              subtitleDirectories:
                  (courseJson['subtitleDirectories'] as List<Object?>? ??
                          const <Object?>[])
                      .cast<String>(),
              title: courseJson['title']! as String,
              description: courseJson['description']! as String,
              sourceLabel: courseJson['sourceLabel'] as String? ?? '本地资源',
              coverImage: courseJson['coverImage']! as String,
              level: courseJson['level']! as String,
              category: courseJson['category']! as String,
              progressPercent: courseJson['progressPercent']! as int,
              totalWords: courseJson['totalWords']! as int,
              completedEpisodes: courseJson['completedEpisodes']! as int,
              totalEpisodes: episodes.length,
              lastStudiedStr: courseJson['lastStudiedStr']! as String,
              lastStudiedAtMs: (courseJson['lastStudiedAtMs'] as num?)?.toInt(),
              rating: (courseJson['rating'] as num?)?.toDouble() ?? 0.0,
              episodes: episodes,
            );
          })
          .toList(growable: false);
    } catch (_) {
      return const <LibraryCourseData>[];
    }
  }

  List<LibraryEpisodeItem> _decodeEpisodes({
    required String courseId,
    required List<Object?>? episodesJson,
  }) {
    if (episodesJson == null) {
      return const <LibraryEpisodeItem>[];
    }

    final Set<String> seenIds = <String>{};
    final List<Map<String, Object?>> items = episodesJson
        .cast<Map<String, Object?>>()
        .where(_shouldKeepStoredEpisode)
        .toList(growable: false);
    return <LibraryEpisodeItem>[
      for (int index = 0; index < items.length; index++)
        _decodeEpisodeItem(
          courseId: courseId,
          json: items[index],
          index: index,
          seenIds: seenIds,
        ),
    ];
  }

  LibraryEpisodeItem _decodeEpisodeItem({
    required String courseId,
    required Map<String, Object?> json,
    required int index,
    required Set<String> seenIds,
  }) {
    final String storedId = json['id'] as String? ?? '';
    final String resolvedId = storedId.isNotEmpty && seenIds.add(storedId)
        ? storedId
        : '$courseId-ep${(index + 1).toString().padLeft(2, '0')}';
    seenIds.add(resolvedId);

    return LibraryEpisodeItem(
      id: resolvedId,
      videoMissing: json['videoMissing'] as bool? ?? false,
      numberStr: json['numberStr']! as String,
      title: json['title']! as String,
      durationMinutes: json['durationMinutes']! as int,
      hasChineseSubtitles: json['hasChineseSubtitles']! as bool,
      hasEnglishSubtitles: json['hasEnglishSubtitles']! as bool,
      completed: json['completed']! as bool,
      progressPercent: json['progressPercent']! as int,
      coverImage: json['coverImage'] as String? ?? '',
      lastWatchedStr: json['lastWatchedStr'] as String?,
      progressTimeStr: json['progressTimeStr'] as String?,
      totalTimeStr: json['totalTimeStr'] as String?,
      videoAsset: _sanitizeStoredPath(json['videoAsset'] as String?),
      enSubtitleAsset: _sanitizeStoredPath(json['enSubtitleAsset'] as String?),
      cnSubtitleAsset: _sanitizeStoredPath(json['cnSubtitleAsset'] as String?),
      subtitleTracks:
          ((json['subtitleTracks'] as List<Object?>?) ?? const <Object?>[])
              .cast<Map<String, Object?>>()
              .where(
                (Map<String, Object?> track) => ImportMatcher.isImportablePath(
                  track['path'] as String? ?? '',
                ),
              )
              .map(
                (Map<String, Object?> track) => LibrarySubtitleTrackItem(
                  languageCode: track['languageCode']! as String,
                  languageLabel: track['languageLabel']! as String,
                  path: track['path']! as String,
                ),
              )
              .toList(growable: false),
    );
  }

  String _buildCourseId(String videoFolder, List<ImportMatchRow> rows) {
    final String prefix = videoFolder.isNotEmpty
        ? _slug(videoFolder.split(RegExp(r'[\\/]')).last.replaceAll('-', '_'))
        : rows.isNotEmpty
        ? _slug(_stripExtension(rows.first.videoFile))
        : 'imported_course';
    return rows.isNotEmpty && rows.first.videoFile.isNotEmpty
        ? '$prefix-${_slug(rows.first.videoFile)}'
        : 'imported_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _buildCourseTitle(String videoFolder, List<ImportMatchRow> rows) {
    final List<String> segments = videoFolder
        .split(RegExp(r'[\\/]'))
        .where((String item) => item.trim().isNotEmpty)
        .toList(growable: false);
    if (segments.isNotEmpty && segments.last.trim().isNotEmpty) {
      return segments.last.trim();
    }
    if (rows.isNotEmpty) {
      return _stripExtension(rows.first.videoFile).trim();
    }
    return '已导入课程';
  }

  bool _shouldKeepStoredEpisode(Map<String, Object?> json) {
    final String videoPath = json['videoAsset'] as String? ?? '';
    if (!ImportMatcher.isImportablePath(videoPath)) {
      return false;
    }

    final List<String> subtitlePaths = <String>[
      json['enSubtitleAsset'] as String? ?? '',
      json['cnSubtitleAsset'] as String? ?? '',
      ...(((json['subtitleTracks'] as List<Object?>?) ?? const <Object?>[])
          .cast<Map<String, Object?>>()
          .map((Map<String, Object?> track) => track['path'] as String? ?? '')),
    ].where((String path) => path.trim().isNotEmpty).toList(growable: false);

    final bool containsVerifySubtitle = subtitlePaths.any(
      (String path) => !ImportMatcher.isImportablePath(path),
    );
    if (!containsVerifySubtitle) {
      return true;
    }

    final String normalizedVideoName = videoPath
        .replaceAll(r'\', '/')
        .split('/')
        .last
        .toLowerCase();
    final String normalizedTitle = (json['title'] as String? ?? '')
        .trim()
        .toLowerCase();
    return !normalizedVideoName.startsWith('lesson') &&
        !normalizedTitle.startsWith('lesson');
  }

  String? _sanitizeStoredPath(String? path) {
    if (path == null || path.trim().isEmpty) {
      return path;
    }
    return ImportMatcher.isImportablePath(path) ? path : null;
  }

  String _buildEpisodeId(
    String courseId,
    ImportMatchRow row,
    int index,
    Set<String> occupiedIds,
  ) {
    int episodeNumber = index + 1;
    String id;
    do {
      id = '$courseId-ep${(episodeNumber++).toString().padLeft(2, '0')}';
    } while (!occupiedIds.add(id));
    return id;
  }

  LibraryEpisodeItem _buildEpisodeItem(
    ImportMatchRow row, {
    required String courseId,
    required String episodeId,
    required String coverImage,
  }) {
    final String number = _extractEpisodeNumber(
      row.episodeName,
    ).toString().padLeft(2, '0');
    return LibraryEpisodeItem(
      subtitleTracks: row.subtitleTracks.values
          .map(
            (ImportSubtitleTrack track) => LibrarySubtitleTrackItem(
              languageCode: track.languageCode,
              languageLabel: track.languageLabel,
              path: track.path,
            ),
          )
          .toList(growable: false),
      id: episodeId,
      numberStr: number,
      title: row.episodeName,
      durationMinutes: 30,
      hasChineseSubtitles: row.hasChinese,
      hasEnglishSubtitles: row.hasEnglish,
      completed: false,
      progressPercent: 0,
      coverImage: coverImage,
      videoAsset: row.videoPath,
      enSubtitleAsset: row.englishSubtitlePath,
      cnSubtitleAsset: row.chineseSubtitlePath,
    );
  }

  int _extractEpisodeNumber(String name) {
    final RegExp matcher = RegExp(r'(\d+)');
    final Match? match = matcher.firstMatch(name);
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(1) ?? '0') ?? 0;
  }

  String _stripExtension(String value) {
    final int index = value.lastIndexOf('.');
    if (index <= 0) {
      return value;
    }
    return value.substring(0, index);
  }

  String _slug(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll(RegExp('[^a-z0-9]+'), '_')
        .replaceAll(RegExp('_+'), '_')
        .replaceAll(RegExp(r'^_|_\$'), '');
  }

  Future<void> _deleteManagedImportDirectories(
    List<LibraryCourseData> courses,
  ) async {
    final Set<String> directories = <String>{};
    for (final LibraryCourseData course in courses) {
      for (final LibraryEpisodeItem episode in course.episodes) {
        for (final String? path in <String?>[
          episode.videoAsset,
          episode.enSubtitleAsset,
          episode.cnSubtitleAsset,
          ...episode.subtitleTracks.map(
            (LibrarySubtitleTrackItem item) => item.path,
          ),
        ]) {
          final String? managedDirectory = _managedImportDirectoryForPath(path);
          if (managedDirectory != null) {
            directories.add(managedDirectory);
          }
        }
      }
    }

    final List<String> sortedDirectories = directories.toList(growable: false)
      ..sort((String a, String b) => b.length.compareTo(a.length));
    for (final String directoryPath in sortedDirectories) {
      final Directory directory = Directory(directoryPath);
      if (!directory.existsSync()) {
        continue;
      }
      try {
        await directory.delete(recursive: true);
      } catch (_) {
        // ponytail: best-effort cleanup; stale files are less bad than blocked deletion.
      }
    }
  }

  String? _managedImportDirectoryForPath(String? rawPath) {
    if (rawPath == null || rawPath.trim().isEmpty) {
      return null;
    }
    final String normalized = rawPath.replaceAll(r'\', '/');
    const String marker = '/imported_sources/';
    final int markerIndex = normalized.indexOf(marker);
    if (markerIndex < 0) {
      return null;
    }

    final String prefix = normalized.substring(0, markerIndex + marker.length);
    final List<String> segments = normalized
        .substring(markerIndex + marker.length)
        .split('/')
        .where((String segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return null;
    }

    final List<String> managedSegments =
        segments.first == 'confirmed_imports' && segments.length >= 2
        ? <String>['confirmed_imports', segments[1]]
        : <String>[segments.first];
    return '$prefix${managedSegments.join('/')}';
  }
}
