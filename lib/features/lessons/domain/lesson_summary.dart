import 'intensive_lesson.dart';

/// The library keeps previews in memory, never narration or subtitle context.
class LessonSummary {
  LessonSummary({
    required this.id,
    required this.episodeId,
    required this.courseTitle,
    required this.episodeTitle,
    required this.startMs,
    required this.english,
    required this.meaning,
    required this.focuses,
    required this.cardCount,
    required this.createdAt,
  });

  factory LessonSummary.fromLesson(IntensiveLesson lesson) => LessonSummary(
    id: lesson.id,
    episodeId: lesson.source.episodeId,
    courseTitle: lesson.source.courseTitle,
    episodeTitle: lesson.source.episodeTitle,
    startMs: lesson.source.startMs,
    english: lesson.source.english,
    meaning: lesson.meaning,
    focuses: lesson.cards
        .map((LessonCard card) => card.focus)
        .toList(growable: false),
    cardCount: lesson.cards.length,
    createdAt: lesson.createdAt,
  );

  factory LessonSummary.fromJson(Map<String, dynamic> json) => LessonSummary(
    id: json['id'] as String,
    episodeId: json['episodeId'] as String,
    courseTitle: json['courseTitle'] as String,
    episodeTitle: json['episodeTitle'] as String,
    startMs: json['startMs'] as int,
    english: json['english'] as String,
    meaning: json['meaning'] as String,
    focuses: (json['focuses'] as List<dynamic>).cast<String>(),
    cardCount: json['cardCount'] as int,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  final String id;
  final String episodeId;
  final String courseTitle;
  final String episodeTitle;
  final int startMs;
  final String english;
  final String meaning;
  final List<String> focuses;
  final int cardCount;
  final DateTime createdAt;

  late final String searchText =
      '$english $meaning $courseTitle ${focuses.join(' ')}'.toLowerCase();

  String get timeLabel =>
      '${(startMs ~/ 60000).toString().padLeft(2, '0')}:'
      '${(startMs ~/ 1000 % 60).toString().padLeft(2, '0')}';

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'episodeId': episodeId,
    'courseTitle': courseTitle,
    'episodeTitle': episodeTitle,
    'startMs': startMs,
    'english': english,
    'meaning': meaning,
    'focuses': focuses,
    'cardCount': cardCount,
    'createdAt': createdAt.toIso8601String(),
  };
}
