import '../../library/presentation/course_directory_relink.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../player/presentation/player_media_source.dart';
import 'word_book_provider.dart';

class WordVideoCandidate {
  const WordVideoCandidate({required this.course, required this.episode});
  final LibraryCourseData course;
  final LibraryEpisodeItem episode;
}

List<WordVideoCandidate> availableWordVideos(
  List<LibraryCourseData> courses, {
  bool Function(String) available = playerMediaAvailable,
}) => <WordVideoCandidate>[
  for (final LibraryCourseData course in courses)
    for (final LibraryEpisodeItem episode in course.episodes)
      if ((episode.videoAsset ?? '').isNotEmpty &&
          available(episode.videoAsset!))
        WordVideoCandidate(course: course, episode: episode),
];

String _name(String value) => value.trim().toLowerCase();
// Imported IDs contain a directory prefix followed by the first video filename.
// This legacy hint survives moving the same course to a differently named folder.
String _legacyCourseKey(String id) {
  final String courseId = id.replaceFirst(RegExp(r'-ep\d+$'), '');
  final int separator = courseId.indexOf('-');
  return separator < 0 ? '' : courseId.substring(separator + 1);
}

List<WordVideoCandidate> resolveWordVideoCandidates({
  required List<LibraryCourseData> courses,
  required WordOccurrence occurrence,
  bool Function(String) available = playerMediaAvailable,
}) {
  final List<WordVideoCandidate> all = availableWordVideos(
    courses,
    available: available,
  );
  final String fileName = occurrence.videoFileName ?? '';
  final List<WordVideoCandidate> exact = all
      .where(
        (WordVideoCandidate c) =>
            c.episode.id == occurrence.episodeId &&
            (fileName.isEmpty ||
                resourceFileName(c.episode.videoAsset!) == fileName),
      )
      .toList();
  if (exact.isNotEmpty) return exact;

  List<WordVideoCandidate> narrowByCourse(List<WordVideoCandidate> candidates) {
    final List<WordVideoCandidate> sameName = candidates
        .where(
          (WordVideoCandidate c) =>
              _name(c.course.title) == _name(occurrence.course),
        )
        .toList();
    if (sameName.isNotEmpty) return sameName;
    final String legacyKey = _legacyCourseKey(occurrence.episodeId);
    final List<WordVideoCandidate> sameKey = legacyKey.isEmpty
        ? <WordVideoCandidate>[]
        : candidates
              .where(
                (WordVideoCandidate c) =>
                    _legacyCourseKey('${c.course.id}-ep01') == legacyKey,
              )
              .toList();
    return sameKey;
  }

  if (fileName.isNotEmpty) {
    final List<WordVideoCandidate> byFile = all
        .where(
          (WordVideoCandidate c) =>
              resourceFileName(c.episode.videoAsset!) == fileName,
        )
        .toList();
    if (byFile.length <= 1) return byFile;
    final List<WordVideoCandidate> narrowed = narrowByCourse(byFile);
    return narrowed.isNotEmpty ? narrowed : byFile;
  }
  final List<WordVideoCandidate> sameCourse = narrowByCourse(all);
  final Match? number = RegExp(
    r'^第\s*(\d+)\s*集$',
  ).firstMatch(occurrence.episode.trim());
  if (number != null) {
    final int? episodeNumber = int.tryParse(number.group(1)!);
    return sameCourse
        .where(
          (WordVideoCandidate c) =>
              int.tryParse(c.episode.numberStr) == episodeNumber,
        )
        .toList();
  }
  // Some historical imports saved the episode title instead of its number.
  return sameCourse
      .where(
        (WordVideoCandidate c) =>
            _name(c.episode.title) == _name(occurrence.episode),
      )
      .toList();
}
