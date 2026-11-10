import 'dart:convert';

import 'package:crypto/crypto.dart';

enum LessonCardKind {
  scene('场景理解'),
  expression('表达拆解'),
  usage('用法对照');

  const LessonCardKind(this.label);
  final String label;
}

class LessonTokenUsage {
  const LessonTokenUsage({this.input, this.output, this.total});

  static LessonTokenUsage? fromProvider(Object? raw) {
    if (raw is! Map<Object?, Object?>) return null;
    int? count(Object? value) => value is int && value >= 0 ? value : null;
    final int? input = count(raw['prompt_tokens'] ?? raw['input_tokens']);
    final int? output = count(raw['completion_tokens'] ?? raw['output_tokens']);
    final int? total =
        count(raw['total_tokens']) ??
        (input != null && output != null ? input + output : null);
    if (input == null && output == null && total == null) return null;
    return LessonTokenUsage(input: input, output: output, total: total);
  }

  final int? input;
  final int? output;
  final int? total;

  Map<String, int> toJson() => <String, int>{
    if (input != null) 'prompt_tokens': input!,
    if (output != null) 'completion_tokens': output!,
    if (total != null) 'total_tokens': total!,
  };
}

class LessonSource {
  const LessonSource({
    required this.episodeId,
    required this.courseTitle,
    required this.episodeTitle,
    required this.startMs,
    required this.endMs,
    required this.english,
    required this.context,
    required this.boundaryLimited,
  });

  factory LessonSource.fromJson(Map<String, dynamic> json) => LessonSource(
    episodeId: json['episodeId'] as String,
    courseTitle: json['courseTitle'] as String,
    episodeTitle: json['episodeTitle'] as String,
    startMs: json['startMs'] as int,
    endMs: json['endMs'] as int,
    english: json['english'] as String,
    context: json['context'] as String,
    boundaryLimited: json['boundaryLimited'] as bool,
  );

  final String episodeId;
  final String courseTitle;
  final String episodeTitle;
  final int startMs;
  final int endMs;
  final String english;
  final String context;
  final bool boundaryLimited;

  // Display preferences and file paths are deliberately absent. The same text
  // reuses its lesson after a directory move; changed context gets a new lesson.
  String get id => sha256
      .convert(
        utf8.encode(
          jsonEncode(<Object>[
            1,
            episodeId,
            startMs,
            endMs,
            english,
            context,
            boundaryLimited,
          ]),
        ),
      )
      .toString();

  String get timeLabel {
    final Duration time = Duration(milliseconds: startMs);
    return '${time.inMinutes.toString().padLeft(2, '0')}:'
        '${(time.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  String get seekTime => seekTimeWithDelay(0);

  String seekTimeWithDelay(int delayMs) {
    final int milliseconds = (startMs + delayMs).isNegative
        ? 0
        : startMs + delayMs;
    final Duration time = Duration(milliseconds: milliseconds);
    return '${time.inHours.toString().padLeft(2, '0')}:'
        '${(time.inMinutes % 60).toString().padLeft(2, '0')}:'
        '${(time.inSeconds % 60).toString().padLeft(2, '0')}.'
        '${(milliseconds % 1000).toString().padLeft(3, '0')}';
  }

  Map<String, Object> toJson() => <String, Object>{
    'episodeId': episodeId,
    'courseTitle': courseTitle,
    'episodeTitle': episodeTitle,
    'startMs': startMs,
    'endMs': endMs,
    'english': english,
    'context': context,
    'boundaryLimited': boundaryLimited,
  };
}

class LessonExample {
  const LessonExample({
    required this.english,
    required this.chinese,
    this.situation = '',
  });
  factory LessonExample.fromJson(Map<String, dynamic> json) => LessonExample(
    english: _text(json, 'english', 400),
    chinese: _text(json, 'chinese', 400),
    situation: _optionalText(json, 'situation', 200),
  );
  final String english;
  final String chinese;
  final String situation;
  Map<String, String> toJson() => <String, String>{
    'english': english,
    'chinese': chinese,
    if (situation.isNotEmpty) 'situation': situation,
  };
}

class LessonSpeech {
  const LessonSpeech({required this.language, required this.text});
  factory LessonSpeech.fromJson(Map<String, dynamic> json) {
    final String language = _text(json, 'language', 10);
    if (language != 'zh-CN' && language != 'en-US') {
      throw const FormatException('Unsupported narration language.');
    }
    return LessonSpeech(language: language, text: _text(json, 'text', 500));
  }
  final String language;
  final String text;
  Map<String, String> toJson() => <String, String>{
    'language': language,
    'text': text,
  };
}

class LessonCard {
  const LessonCard({
    required this.kind,
    required this.focus,
    required this.explanation,
    required this.tip,
    required this.examples,
    required this.speech,
    this.pattern = '',
    this.meaning = '',
  });

  factory LessonCard.fromJson(Map<String, dynamic> json) {
    final LessonCardKind kind = LessonCardKind.values.byName(
      _text(json, 'kind', 20),
    );
    final List<LessonExample> examples = _objects(
      json,
      'examples',
      1,
      3,
    ).map(LessonExample.fromJson).toList(growable: false);
    final List<LessonSpeech> speech = _objects(
      json,
      'speech',
      2,
      14,
    ).map(LessonSpeech.fromJson).toList(growable: false);
    if (!speech.any((LessonSpeech item) => item.language == 'zh-CN') ||
        !speech.any((LessonSpeech item) => item.language == 'en-US')) {
      throw const FormatException('Bilingual narration is missing.');
    }
    return LessonCard(
      kind: kind,
      focus: _text(json, 'focus', 200),
      pattern: _optionalText(json, 'pattern', 200),
      meaning: _optionalText(json, 'meaning', 400),
      explanation: _text(json, 'explanation', 1200),
      tip: _text(json, 'tip', 500),
      examples: examples,
      speech: speech,
    );
  }

  final LessonCardKind kind;
  final String focus;
  final String pattern;
  final String meaning;
  final String explanation;
  final String tip;
  final List<LessonExample> examples;
  final List<LessonSpeech> speech;
  Map<String, Object> toJson() => <String, Object>{
    'kind': kind.name,
    'focus': focus,
    if (pattern.isNotEmpty) 'pattern': pattern,
    if (meaning.isNotEmpty) 'meaning': meaning,
    'explanation': explanation,
    'tip': tip,
    'examples': examples.map((LessonExample e) => e.toJson()).toList(),
    'speech': speech.map((LessonSpeech s) => s.toJson()).toList(),
  };
}

class IntensiveLesson {
  const IntensiveLesson({
    required this.source,
    required this.meaning,
    required this.scene,
    required this.cards,
    required this.createdAt,
    this.usage,
    this.model,
  });

  factory IntensiveLesson.fromContent({
    required LessonSource source,
    required Map<String, dynamic> json,
    DateTime? createdAt,
    LessonTokenUsage? usage,
    String? model,
    bool requireTeachingFields = false,
  }) {
    final List<LessonCard> cards = _objects(
      json,
      'cards',
      3,
      3,
    ).map(LessonCard.fromJson).toList(growable: false);
    if (cards.map((LessonCard card) => card.kind).toSet().length != 3) {
      throw const FormatException('Three distinct lesson cards are required.');
    }
    if (requireTeachingFields &&
        cards.any(
          (LessonCard card) =>
              card.pattern.isEmpty ||
              card.meaning.isEmpty ||
              card.examples.any(
                (LessonExample example) => example.situation.isEmpty,
              ),
        )) {
      throw const FormatException('Contextual teaching details are missing.');
    }
    cards.sort(
      (LessonCard a, LessonCard b) => a.kind.index.compareTo(b.kind.index),
    );
    return IntensiveLesson(
      source: source,
      meaning: _text(json, 'meaning', 600),
      scene: _text(json, 'scene', 800),
      cards: cards,
      createdAt: createdAt ?? DateTime.now(),
      usage: usage,
      model: model,
    );
  }

  factory IntensiveLesson.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unknown lesson version.');
    }
    return IntensiveLesson.fromContent(
      source: LessonSource.fromJson(json['source'] as Map<String, dynamic>),
      json: json,
      createdAt: DateTime.parse(json['createdAt'] as String),
      usage: LessonTokenUsage.fromProvider(json['usage']),
      model: json['model'] as String?,
    );
  }

  final LessonSource source;
  final String meaning;
  final String scene;
  final List<LessonCard> cards;
  final DateTime createdAt;
  final LessonTokenUsage? usage;
  final String? model;
  String get id => source.id;

  Map<String, Object> toJson() => <String, Object>{
    'version': 1,
    'source': source.toJson(),
    'meaning': meaning,
    'scene': scene,
    'cards': cards.map((LessonCard card) => card.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    if (usage != null) 'usage': usage!.toJson(),
    if (model != null) 'model': model!,
  };
}

String _optionalText(Map<String, dynamic> json, String key, int limit) {
  final Object? value = json[key];
  if (value == null || value == '') return '';
  return _text(json, key, limit);
}

String _text(Map<String, dynamic> json, String key, int limit) {
  final Object? value = json[key];
  if (value is! String || value.trim().isEmpty || value.length > limit) {
    throw FormatException('Invalid lesson field: $key.');
  }
  return value.trim();
}

List<Map<String, dynamic>> _objects(
  Map<String, dynamic> json,
  String key,
  int minimum,
  int maximum,
) {
  final Object? value = json[key];
  if (value is! List || value.length < minimum || value.length > maximum) {
    throw FormatException('Invalid lesson list: $key.');
  }
  return value.cast<Map<String, dynamic>>();
}
