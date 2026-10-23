class LibrarySubtitleTrackItem {
  const LibrarySubtitleTrackItem({
    required this.languageCode,
    required this.languageLabel,
    required this.path,
  });

  final String languageCode;
  final String languageLabel;
  final String path;
}

class LibraryEpisodeItem {
  const LibraryEpisodeItem({
    required this.id,
    required this.numberStr,
    required this.title,
    required this.durationMinutes,
    required this.hasChineseSubtitles,
    required this.hasEnglishSubtitles,
    required this.completed,
    required this.progressPercent,
    required this.coverImage,
    this.lastWatchedStr,
    this.progressTimeStr,
    this.totalTimeStr,
    this.videoAsset,
    this.enSubtitleAsset,
    this.cnSubtitleAsset,
    this.subtitleTracks = const <LibrarySubtitleTrackItem>[],
  });

  final String id;
  final String numberStr;
  final String title;
  final int durationMinutes;
  final bool hasChineseSubtitles;
  final bool hasEnglishSubtitles;
  final bool completed;
  final int progressPercent;
  final String coverImage;
  final String? lastWatchedStr;
  final String? progressTimeStr;
  final String? totalTimeStr;
  final String? videoAsset;
  final String? enSubtitleAsset;
  final String? cnSubtitleAsset;
  final List<LibrarySubtitleTrackItem> subtitleTracks;

  LibraryEpisodeItem copyWith({
    bool? completed,
    int? progressPercent,
    String? lastWatchedStr,
    String? progressTimeStr,
    String? totalTimeStr,
  }) {
    return LibraryEpisodeItem(
      id: id,
      numberStr: numberStr,
      title: title,
      durationMinutes: durationMinutes,
      hasChineseSubtitles: hasChineseSubtitles,
      hasEnglishSubtitles: hasEnglishSubtitles,
      completed: completed ?? this.completed,
      progressPercent: progressPercent ?? this.progressPercent,
      coverImage: coverImage,
      lastWatchedStr: lastWatchedStr ?? this.lastWatchedStr,
      progressTimeStr: progressTimeStr ?? this.progressTimeStr,
      totalTimeStr: totalTimeStr ?? this.totalTimeStr,
      videoAsset: videoAsset,
      enSubtitleAsset: enSubtitleAsset,
      cnSubtitleAsset: cnSubtitleAsset,
      subtitleTracks: subtitleTracks,
    );
  }
}

class LibraryCourseData {
  const LibraryCourseData({
    required this.id,
    required this.title,
    required this.description,
    required this.sourceLabel,
    required this.coverImage,
    required this.level,
    required this.category,
    required this.progressPercent,
    required this.totalWords,
    required this.completedEpisodes,
    required this.totalEpisodes,
    required this.lastStudiedStr,
    this.lastStudiedAtMs,
    required this.rating,
    required this.episodes,
  });

  final String id;
  final String title;
  final String description;
  final String sourceLabel;
  final String coverImage;
  final String level;
  final String category;
  final int progressPercent;
  final int totalWords;
  final int completedEpisodes;
  final int totalEpisodes;
  final String lastStudiedStr;
  final int? lastStudiedAtMs;
  final double rating;
  final List<LibraryEpisodeItem> episodes;

  LibraryCourseData copyWith({
    String? title,
    String? description,
    String? sourceLabel,
    String? coverImage,
    String? level,
    String? category,
    int? progressPercent,
    int? totalWords,
    int? completedEpisodes,
    int? totalEpisodes,
    String? lastStudiedStr,
    int? lastStudiedAtMs,
    double? rating,
    List<LibraryEpisodeItem>? episodes,
  }) {
    return LibraryCourseData(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      coverImage: coverImage ?? this.coverImage,
      level: level ?? this.level,
      category: category ?? this.category,
      progressPercent: progressPercent ?? this.progressPercent,
      totalWords: totalWords ?? this.totalWords,
      completedEpisodes: completedEpisodes ?? this.completedEpisodes,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      lastStudiedStr: lastStudiedStr ?? this.lastStudiedStr,
      lastStudiedAtMs: lastStudiedAtMs ?? this.lastStudiedAtMs,
      rating: rating ?? this.rating,
      episodes: episodes ?? this.episodes,
    );
  }
}

const LibraryCourseData emptyLibraryCourse = LibraryCourseData(
  id: '',
  title: '',
  description: '',
  sourceLabel: '',
  coverImage: '',
  level: '',
  category: '',
  progressPercent: 0,
  totalWords: 0,
  completedEpisodes: 0,
  totalEpisodes: 0,
  lastStudiedStr: '',
  rating: 0,
  episodes: <LibraryEpisodeItem>[],
);

const List<LibraryCourseData> libraryCourses = <LibraryCourseData>[];
