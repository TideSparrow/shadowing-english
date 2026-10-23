import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';

const String _lastLearningEpisodeKey = 'last_learning_episode_v1';

final NotifierProvider<LastLearningEpisodeNotifier, String?>
lastLearningEpisodeProvider =
    NotifierProvider<LastLearningEpisodeNotifier, String?>(
      LastLearningEpisodeNotifier.new,
    );

class LastLearningEpisodeNotifier extends Notifier<String?> {
  @override
  String? build() => Hive.isBoxOpen('prefs')
      ? Hive.box<String>('prefs').get(_lastLearningEpisodeKey)
      : null;

  void record(String episodeId) {
    if (episodeId.trim().isEmpty || state == episodeId) return;
    state = episodeId;
    if (Hive.isBoxOpen('prefs')) {
      unawaited(
        Hive.box<String>('prefs').put(_lastLearningEpisodeKey, episodeId),
      );
    }
  }
}

class ContinueLearningTarget {
  const ContinueLearningTarget({required this.course, required this.episode});

  final LibraryCourseData course;
  final LibraryEpisodeItem episode;
}

final Provider<ContinueLearningTarget?> continueLearningTargetProvider =
    Provider<ContinueLearningTarget?>((Ref ref) {
      final List<LibraryCourseData> courses = ref.watch(libraryCatalogProvider);
      final String? lastEpisode = ref.watch(lastLearningEpisodeProvider);
      for (final LibraryCourseData course in courses) {
        for (final LibraryEpisodeItem episode in course.episodes) {
          if (episode.id == lastEpisode) {
            return ContinueLearningTarget(course: course, episode: episode);
          }
        }
      }
      // Existing libraries have no global history yet. Prefer an unfinished
      // episode with progress, then the first available episode.
      for (final LibraryCourseData course in courses) {
        for (final LibraryEpisodeItem episode in course.episodes) {
          if (!episode.completed && episode.progressPercent > 0) {
            return ContinueLearningTarget(course: course, episode: episode);
          }
        }
      }
      for (final LibraryCourseData course in courses) {
        if (course.episodes.isNotEmpty) {
          return ContinueLearningTarget(
            course: course,
            episode: course.episodes.first,
          );
        }
      }
      return null;
    });
