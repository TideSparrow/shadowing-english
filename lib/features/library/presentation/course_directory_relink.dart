import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../import_course/domain/import_match.dart';
import 'library_mock_data.dart';

String resourcePath(String path) {
  final String normalized = path.replaceAll(r'\', '/');
  return normalized == '/'
      ? normalized
      : normalized.replaceFirst(RegExp(r'/+$'), '');
}

String resourceFileName(String path) => resourcePath(path).split('/').last;
bool isLocalResource(String path) =>
    path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
String _directoryPrefix(String root) => resourcePath(root).endsWith('/')
    ? resourcePath(root)
    : '${resourcePath(root)}/';
bool resourceIsIn(String path, String root) =>
    resourcePath(path).startsWith(_directoryPrefix(root));
String resourceRelativePath(String path, String root) =>
    resourceIsIn(path, root)
    ? resourcePath(path).substring(_directoryPrefix(root).length)
    : resourcePath(path);

List<String> courseResourceDirectories(
  LibraryCourseData course, {
  required bool subtitles,
}) {
  final List<String> roots = <String>{
    ...(subtitles ? course.subtitleDirectories : course.videoDirectories),
  }.where(isLocalResource).toList();
  for (final LibraryEpisodeItem episode in course.episodes) {
    final Iterable<String?> paths = subtitles
        ? <String?>[
            episode.enSubtitleAsset,
            episode.cnSubtitleAsset,
            ...episode.subtitleTracks.map(
              (LibrarySubtitleTrackItem t) => t.path,
            ),
          ]
        : <String?>[episode.videoAsset];
    for (final String? path in paths) {
      if (path == null ||
          !isLocalResource(path) ||
          roots.any((String root) => resourceIsIn(path, root))) {
        continue;
      }
      roots.add(
        resourcePath(path).lastIndexOf('/') == 0
            ? '/'
            : resourcePath(
                path,
              ).substring(0, resourcePath(path).lastIndexOf('/')),
      );
    }
  }
  return roots.toSet().toList();
}

class ResourceRelinkFile {
  const ResourceRelinkFile({
    required this.oldPath,
    required this.candidates,
    required this.isVideo,
  });
  final String oldPath;
  final List<String> candidates;
  final bool isVideo;
}

class CourseDirectoryRelinkPlan {
  const CourseDirectoryRelinkPlan({
    required this.course,
    required this.oldRoot,
    required this.newRoot,
    required this.subtitlesOnly,
    required this.files,
    this.newVideos = const <ImportMatchRow>[],
  });
  final LibraryCourseData course;
  final String oldRoot;
  final String newRoot;
  final bool subtitlesOnly;
  final List<ResourceRelinkFile> files;
  final List<ImportMatchRow> newVideos;

  Map<String, String> get initialSelections {
    final Map<String, String> selections = <String, String>{};
    final Map<String, int> counts = <String, int>{};
    for (final ResourceRelinkFile file in files) {
      if (file.candidates.length == 1) {
        counts.update(
          file.candidates.single,
          (int n) => n + 1,
          ifAbsent: () => 1,
        );
      }
    }
    for (final ResourceRelinkFile file in files) {
      if (file.candidates.length == 1 && counts[file.candidates.single] == 1) {
        selections[file.oldPath] = file.candidates.single;
      }
    }
    return selections;
  }

  bool isCurrent(LibraryCourseData current) {
    if (current.episodes.length != course.episodes.length) return false;
    for (int i = 0; i < current.episodes.length; i++) {
      final LibraryEpisodeItem a = current.episodes[i];
      final LibraryEpisodeItem b = course.episodes[i];
      if (a.id != b.id ||
          a.videoAsset != b.videoAsset ||
          a.enSubtitleAsset != b.enSubtitleAsset ||
          a.cnSubtitleAsset != b.cnSubtitleAsset ||
          !listEquals(
            a.subtitleTracks
                .map(
                  (LibrarySubtitleTrackItem t) => '${t.languageCode}:${t.path}',
                )
                .toList(),
            b.subtitleTracks
                .map(
                  (LibrarySubtitleTrackItem t) => '${t.languageCode}:${t.path}',
                )
                .toList(),
          )) {
        return false;
      }
    }
    return true;
  }

  LibraryCourseData apply(
    LibraryCourseData current,
    Map<String, String> selections,
    Set<String> addedVideoPaths,
  ) {
    final Set<String> used = <String>{};
    for (final MapEntry<String, String> entry in selections.entries) {
      final ResourceRelinkFile file = files.firstWhere(
        (ResourceRelinkFile f) => f.oldPath == entry.key,
      );
      if (!file.candidates.contains(entry.value) || !used.add(entry.value)) {
        throw StateError('同一个文件不能关联到多个原文件。');
      }
    }
    if (addedVideoPaths.any(
      (String path) =>
          !newVideos.any((ImportMatchRow row) => row.videoPath == path),
    )) {
      throw StateError('新增视频已变化，请重新扫描。');
    }
    String? relocated(String? path) => selections[path] ?? path;
    final Set<String> videoPaths = files
        .where((ResourceRelinkFile f) => f.isVideo)
        .map((ResourceRelinkFile f) => f.oldPath)
        .toSet();
    final List<LibraryEpisodeItem> episodes = current.episodes
        .map(
          (LibraryEpisodeItem episode) => episode.copyWith(
            videoAsset: relocated(episode.videoAsset),
            videoMissing: videoPaths.contains(episode.videoAsset)
                ? !selections.containsKey(episode.videoAsset)
                : episode.videoMissing,
            enSubtitleAsset: relocated(episode.enSubtitleAsset),
            cnSubtitleAsset: relocated(episode.cnSubtitleAsset),
            subtitleTracks: episode.subtitleTracks
                .map(
                  (LibrarySubtitleTrackItem t) => LibrarySubtitleTrackItem(
                    languageCode: t.languageCode,
                    languageLabel: t.languageLabel,
                    path: relocated(t.path)!,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
    final Set<String> ids = episodes
        .map((LibraryEpisodeItem e) => e.id)
        .toSet();
    int number = episodes.length + 1;
    for (final ImportMatchRow row in newVideos.where(
      (ImportMatchRow row) => addedVideoPaths.contains(row.videoPath),
    )) {
      String id;
      do {
        id = '${current.id}-ep${(number++).toString().padLeft(2, '0')}';
      } while (ids.contains(id));
      ids.add(id);
      episodes.add(
        LibraryEpisodeItem(
          id: id,
          numberStr:
              RegExp(r'\d+').firstMatch(row.episodeName)?.group(0) ??
              '${number - 1}',
          title: row.episodeName,
          durationMinutes: 30,
          hasChineseSubtitles: row.hasChinese,
          hasEnglishSubtitles: row.hasEnglish,
          completed: false,
          progressPercent: 0,
          coverImage: '',
          videoAsset: row.videoPath,
          enSubtitleAsset: row.englishSubtitlePath,
          cnSubtitleAsset: row.chineseSubtitlePath,
          subtitleTracks: row.subtitleTracks.values
              .map(
                (ImportSubtitleTrack t) => LibrarySubtitleTrackItem(
                  languageCode: t.languageCode,
                  languageLabel: t.languageLabel,
                  path: t.path,
                ),
              )
              .toList(),
        ),
      );
    }
    // Keep roots containing unresolved files so they can be retried later.
    List<String> roots({required bool subtitles}) {
      final List<String> original = courseResourceDirectories(
        current,
        subtitles: subtitles,
      );
      final List<String> paths = episodes
          .expand(
            (LibraryEpisodeItem e) => subtitles
                ? <String?>[
                    e.enSubtitleAsset,
                    e.cnSubtitleAsset,
                    ...e.subtitleTracks.map(
                      (LibrarySubtitleTrackItem t) => t.path,
                    ),
                  ]
                : <String?>[e.videoAsset],
          )
          .whereType<String>()
          .where((String path) => path.isNotEmpty)
          .toList();
      final Set<String> result = original
          .where(
            (String root) =>
                paths.any((String path) => resourceIsIn(path, root)),
          )
          .toSet();
      if (paths.any((String path) => resourceIsIn(path, newRoot))) {
        result.add(newRoot);
      }
      return result.toList();
    }

    return current.copyWith(
      episodes: episodes,
      totalEpisodes: episodes.length,
      progressPercent: episodes.isEmpty
          ? 0
          : (episodes.fold<int>(
                      0,
                      (int n, LibraryEpisodeItem e) => n + e.progressPercent,
                    ) /
                    episodes.length)
                .round(),
      videoDirectories: roots(subtitles: false),
      subtitleDirectories: roots(subtitles: true),
    );
  }
}

Future<CourseDirectoryRelinkPlan> scanCourseDirectory({
  required LibraryCourseData course,
  required String oldRoot,
  required String newRoot,
  required bool subtitlesOnly,
}) => compute(_scanDirectory, (
  course: course,
  oldRoot: oldRoot,
  newRoot: newRoot,
  subtitlesOnly: subtitlesOnly,
));

CourseDirectoryRelinkPlan _scanDirectory(
  ({
    LibraryCourseData course,
    String oldRoot,
    String newRoot,
    bool subtitlesOnly,
  })
  request,
) {
  final Directory directory = Directory(request.newRoot);
  if (!directory.existsSync()) {
    throw FileSystemException('目录不存在或无法访问', request.newRoot);
  }
  final List<String> paths =
      directory
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .map((File f) => f.path)
          .where(ImportMatcher.isImportablePath)
          .toList()
        ..sort();
  final List<String> videos = paths
      .where(
        (String path) => RegExp(
          r'\.(mp4|mkv|mov|webm|rm|ts)$',
          caseSensitive: false,
        ).hasMatch(path),
      )
      .toList();
  final List<String> subtitles = paths
      .where(
        (String path) =>
            RegExp(r'\.(srt|vtt)$', caseSensitive: false).hasMatch(path),
      )
      .toList();
  return buildCourseDirectoryRelinkPlan(
    course: request.course,
    oldRoot: request.oldRoot,
    newRoot: request.newRoot,
    subtitlesOnly: request.subtitlesOnly,
    videoFiles: videos,
    subtitleFiles: subtitles,
  );
}

@visibleForTesting
CourseDirectoryRelinkPlan buildCourseDirectoryRelinkPlan({
  required LibraryCourseData course,
  required String oldRoot,
  required String newRoot,
  required bool subtitlesOnly,
  required List<String> videoFiles,
  required List<String> subtitleFiles,
}) {
  final Map<String, bool> original = <String, bool>{};
  final Set<String> occupied = course.episodes
      .map((LibraryEpisodeItem e) => e.videoAsset)
      .whereType<String>()
      .where((String path) => !resourceIsIn(path, oldRoot))
      .toSet();
  for (final LibraryEpisodeItem episode in course.episodes) {
    if (!subtitlesOnly &&
        episode.videoAsset != null &&
        resourceIsIn(episode.videoAsset!, oldRoot)) {
      original[episode.videoAsset!] = true;
    }
    for (final String? path in <String?>[
      episode.enSubtitleAsset,
      episode.cnSubtitleAsset,
      ...episode.subtitleTracks.map((LibrarySubtitleTrackItem t) => t.path),
    ]) {
      if (path != null && resourceIsIn(path, oldRoot)) original[path] = false;
    }
  }
  final List<ResourceRelinkFile> files = original.entries.map((
    MapEntry<String, bool> entry,
  ) {
    final List<String> pool = entry.value
        ? videoFiles.where((String p) => !occupied.contains(p)).toList()
        : subtitleFiles;
    final String relative = resourceRelativePath(entry.key, oldRoot);
    final List<String> exact = pool
        .where(
          (String path) =>
              resourcePath(path) == '${_directoryPrefix(newRoot)}$relative',
        )
        .toList();
    final List<String> candidates = exact.isNotEmpty
        ? exact
        : pool
              .where(
                (String path) =>
                    resourceFileName(path) == resourceFileName(entry.key),
              )
              .toList();
    return ResourceRelinkFile(
      oldPath: entry.key,
      candidates: candidates,
      isVideo: entry.value,
    );
  }).toList();
  final Set<String> reserved = <String>{
    ...occupied,
    ...course.episodes
        .map((LibraryEpisodeItem e) => e.videoAsset)
        .whereType<String>(),
    ...files
        .where((ResourceRelinkFile f) => f.isVideo)
        .expand((ResourceRelinkFile f) => f.candidates),
  };
  return CourseDirectoryRelinkPlan(
    course: course,
    oldRoot: oldRoot,
    newRoot: newRoot,
    subtitlesOnly: subtitlesOnly,
    files: files,
    newVideos: subtitlesOnly
        ? const <ImportMatchRow>[]
        : ImportMatcher.parse(
            videoFolder: newRoot,
            subtitleFolder: newRoot,
            videoFiles: videoFiles
                .where((String path) => !reserved.contains(path))
                .toList(),
            subtitleFiles: subtitleFiles,
          ),
  );
}
