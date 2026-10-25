import 'dart:convert';
import 'dart:io';

import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:common_learn_english/features/words/presentation/word_book_provider.dart';
import 'package:common_learn_english/features/words/presentation/word_video_relink.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

WordOccurrence occurrence({
  String id = 'a-peppa_s01e01_mp4-ep01',
  String course = 'A',
  String? file,
  String line = '1000-2000',
  String? translation,
}) => WordOccurrence(
  episodeId: id,
  course: course,
  episode: '第 01 集',
  videoFileName: file,
  time: '00:01',
  sentence: "OH, HERE'S SOME ANTACID.",
  chinese: '有些抗酸药。',
  count: 1,
  lineKeys: <String>[line],
  contexts: <WordContext>[
    WordContext(
      lineKey: line,
      time: '00:01',
      sentence: "OH, HERE'S SOME ANTACID.",
      chinese: '有些抗酸药。',
      count: 1,
      apiTranslationCn: translation,
    ),
  ],
);

LibraryCourseData videoCourse({
  String id = 'b-peppa_s01e01_mp4',
  String title = 'B',
  String file = '/B/Peppa.S01E01.mp4',
}) => LibraryCourseData(
  id: id,
  title: title,
  description: '',
  sourceLabel: '',
  coverImage: '',
  level: '',
  category: '',
  progressPercent: 0,
  totalWords: 0,
  completedEpisodes: 0,
  totalEpisodes: 1,
  lastStudiedStr: '',
  rating: 0,
  episodes: <LibraryEpisodeItem>[
    LibraryEpisodeItem(
      id: '$id-ep01',
      numberStr: '01',
      title: 'Peppa.S01E01',
      durationMinutes: 10,
      hasChineseSubtitles: false,
      hasEnglishSubtitles: false,
      completed: false,
      progressPercent: 0,
      coverImage: '',
      videoAsset: file,
    ),
  ],
);

void main() {
  test(
    'legacy course hints survive renamed directories; unrelated episode numbers do not match',
    () {
      final LibraryCourseData moved = videoCourse();
      final LibraryCourseData unrelated = videoCourse(
        id: 'other-unrelated_mp4',
        title: '其他课程',
        file: '/other/video.mp4',
      );
      final List<WordVideoCandidate> matches = resolveWordVideoCandidates(
        courses: <LibraryCourseData>[moved, unrelated],
        occurrence: occurrence(),
        available: (String _) => true,
      );
      expect(matches.single.episode.id, moved.episodes.single.id);
      expect(
        resolveWordVideoCandidates(
          courses: <LibraryCourseData>[unrelated],
          occurrence: occurrence(),
          available: (String _) => true,
        ),
        isEmpty,
      );
      expect(
        resolveWordVideoCandidates(
          courses: <LibraryCourseData>[moved],
          occurrence: occurrence(),
          available: (String _) => false,
        ),
        isEmpty,
      );
    },
  );

  test(
    'unique filename reconnects; duplicate filenames stay ambiguous or narrow by course',
    () {
      final LibraryCourseData first = videoCourse();
      final LibraryCourseData second = videoCourse(
        id: 'c-copy_mp4',
        title: 'C',
        file: '/C/Peppa.S01E01.mp4',
      );
      expect(
        resolveWordVideoCandidates(
          courses: <LibraryCourseData>[first],
          occurrence: occurrence(file: 'Peppa.S01E01.mp4'),
          available: (String _) => true,
        ).single.course.id,
        first.id,
      );
      expect(
        resolveWordVideoCandidates(
          courses: <LibraryCourseData>[first, second],
          occurrence: occurrence(id: 'unknown', file: 'Peppa.S01E01.mp4'),
          available: (String _) => true,
        ).length,
        2,
      );
      expect(
        resolveWordVideoCandidates(
          courses: <LibraryCourseData>[first, second],
          occurrence: occurrence(
            id: 'unknown',
            course: 'C',
            file: 'Peppa.S01E01.mp4',
          ),
          available: (String _) => true,
        ).single.course.id,
        second.id,
      );
      // A reused ID with a different filename must not silently open the wrong video.
      expect(
        resolveWordVideoCandidates(
          courses: <LibraryCourseData>[first],
          occurrence: occurrence(
            id: first.episodes.single.id,
            file: 'other.mp4',
          ),
          available: (String _) => true,
        ),
        isEmpty,
      );
    },
  );

  test(
    'relink persists every old word, merges contexts and preserves favorites and translations',
    () async {
      final Directory temp = Directory.systemTemp.createTempSync(
        'word-relink-',
      );
      Hive.init(temp.path);
      await Hive.openBox<String>('prefs');
      addTearDown(() async {
        await Hive.close();
        temp.deleteSync(recursive: true);
      });
      final WordOccurrence old = occurrence(translation: '旧翻译');
      const String nextId = 'new-ep01';
      final List<WordEntry> entries = <WordEntry>[
        WordEntry(
          word: 'antacid',
          favorite: true,
          definitionCn: '抗酸药',
          occurrences: <WordOccurrence>[
            old,
            occurrence(id: nextId),
            occurrence(id: nextId, line: '3000-4000'),
          ],
        ),
        WordEntry(
          word: 'some',
          favorite: false,
          occurrences: <WordOccurrence>[old],
        ),
      ];
      await Hive.box<String>('prefs').put(
        'word_book_v1',
        jsonEncode(entries.map((WordEntry e) => e.toJson()).toList()),
      );
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(wordBookProvider.notifier)
          .relinkEpisode(
            oldEpisodeId: old.episodeId,
            newEpisodeId: nextId,
            course: '小猪佩奇',
            episode: '第 01 集',
            videoFileName: 'Peppa.S01E01.mp4',
          );
      container.invalidate(wordBookProvider);
      final List<WordEntry> loaded = container.read(wordBookProvider);
      final WordEntry word = loaded.first;
      expect(word.favorite, isTrue);
      expect(word.definitionCn, '抗酸药');
      expect(word.occurrences.single.episodeId, nextId);
      expect(word.occurrences.single.contexts.length, 2);
      expect(word.occurrences.single.count, 2);
      expect(word.occurrences.single.contexts.first.apiTranslationCn, '旧翻译');
      expect(
        word.occurrences.single.contexts.first.sentence,
        "OH, HERE'S SOME ANTACID.",
      );
      expect(loaded.last.occurrences.single.episodeId, nextId);
      expect(loaded.last.occurrences.single.videoFileName, 'Peppa.S01E01.mp4');
      expect(loaded.last.favorite, isFalse);
    },
  );
}
