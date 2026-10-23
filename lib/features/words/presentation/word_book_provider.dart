import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../data/offline_word_dictionary.dart';

const String _wordBookStorageKey = 'word_book_v1';

final NotifierProvider<WordBookNotifier, List<WordEntry>> wordBookProvider =
    NotifierProvider<WordBookNotifier, List<WordEntry>>(WordBookNotifier.new);

class WordOccurrence {
  const WordOccurrence({
    required this.episodeId,
    required this.course,
    required this.episode,
    required this.time,
    required this.sentence,
    required this.chinese,
    required this.count,
    required this.lineKeys,
    required this.contexts,
  });

  factory WordOccurrence.fromJson(Map<String, Object?> json) => WordOccurrence(
    episodeId: json['episodeId']! as String,
    course: json['course']! as String,
    episode: json['episode']! as String,
    time: json['time']! as String,
    sentence: json['sentence']! as String,
    chinese: json['chinese'] as String? ?? '',
    count: json['count'] as int? ?? 1,
    lineKeys: (json['lineKeys'] as List<Object?>? ?? <Object?>[json['time']])
        .cast<String>(),
    contexts:
        (json['contexts'] as List<Object?>?)
            ?.cast<Map<String, Object?>>()
            .map(WordContext.fromJson)
            .toList(growable: false) ??
        <WordContext>[
          WordContext(
            lineKey:
                ((json['lineKeys'] as List<Object?>? ?? <Object?>[json['time']])
                        .first
                    as String?) ??
                json['time']! as String,
            time: json['time']! as String,
            sentence: json['sentence']! as String,
            chinese: json['chinese'] as String? ?? '',
            count: json['count'] as int? ?? 1,
          ),
        ],
  );

  final String episodeId;
  final String course;
  final String episode;
  final String time;
  final String sentence;
  final String chinese;
  final int count;
  final List<String> lineKeys;
  final List<WordContext> contexts;

  WordOccurrence copyWith({
    int? count,
    List<String>? lineKeys,
    List<WordContext>? contexts,
  }) => WordOccurrence(
    episodeId: episodeId,
    course: course,
    episode: episode,
    time: time,
    sentence: sentence,
    chinese: chinese,
    count: count ?? this.count,
    lineKeys: lineKeys ?? this.lineKeys,
    contexts: contexts ?? this.contexts,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'episodeId': episodeId,
    'course': course,
    'episode': episode,
    'time': time,
    'sentence': sentence,
    'chinese': chinese,
    'count': count,
    'lineKeys': lineKeys,
    'contexts': contexts.map((WordContext item) => item.toJson()).toList(),
  };
}

class WordContext {
  const WordContext({
    required this.lineKey,
    required this.time,
    required this.sentence,
    required this.chinese,
    required this.count,
    this.apiTranslationCn,
  });

  factory WordContext.fromJson(Map<String, Object?> json) => WordContext(
    lineKey: json['lineKey']! as String,
    time: json['time']! as String,
    sentence: json['sentence']! as String,
    chinese: json['chinese'] as String? ?? '',
    count: json['count'] as int? ?? 1,
    apiTranslationCn: json['apiTranslationCn'] as String?,
  );

  final String lineKey;
  final String time;
  final String sentence;
  final String chinese;
  final int count;
  final String? apiTranslationCn;

  WordContext copyWith({String? apiTranslationCn}) => WordContext(
    lineKey: lineKey,
    time: time,
    sentence: sentence,
    chinese: chinese,
    count: count,
    apiTranslationCn: apiTranslationCn ?? this.apiTranslationCn,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'lineKey': lineKey,
    'time': time,
    'sentence': sentence,
    'chinese': chinese,
    'count': count,
    'apiTranslationCn': apiTranslationCn,
  };
}

class WordEntry {
  const WordEntry({
    required this.word,
    required this.favorite,
    required this.occurrences,
    this.definitionCn,
    this.offlineDefinitionCn,
  });

  factory WordEntry.fromJson(Map<String, Object?> json) => WordEntry(
    word: json['word']! as String,
    favorite: json['favorite'] as bool? ?? false,
    definitionCn: json['definitionCn'] as String?,
    offlineDefinitionCn: json['offlineDefinitionCn'] as String?,
    occurrences: (json['occurrences'] as List<Object?>? ?? const <Object?>[])
        .cast<Map<String, Object?>>()
        .map(WordOccurrence.fromJson)
        .toList(growable: false),
  );

  final String word;
  final bool favorite;
  final String? definitionCn;
  final String? offlineDefinitionCn;
  final List<WordOccurrence> occurrences;

  int get videoCount => occurrences.length;
  int get occurrenceCount => occurrences.fold<int>(
    0,
    (int total, WordOccurrence item) => total + item.count,
  );

  WordEntry copyWith({
    bool? favorite,
    List<WordOccurrence>? occurrences,
    String? definitionCn,
    String? offlineDefinitionCn,
  }) => WordEntry(
    word: word,
    favorite: favorite ?? this.favorite,
    occurrences: occurrences ?? this.occurrences,
    definitionCn: definitionCn ?? this.definitionCn,
    offlineDefinitionCn: offlineDefinitionCn ?? this.offlineDefinitionCn,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'word': word,
    'favorite': favorite,
    'definitionCn': definitionCn,
    'offlineDefinitionCn': offlineDefinitionCn,
    'occurrences': occurrences
        .map((WordOccurrence item) => item.toJson())
        .toList(),
  };
}

class WordBookNotifier extends Notifier<List<WordEntry>> {
  final Set<String> _pendingOfflineDefinitions = <String>{};
  @override
  List<WordEntry> build() {
    if (!Hive.isBoxOpen('prefs')) return const <WordEntry>[];
    final String? stored = Hive.box<String>('prefs').get(_wordBookStorageKey);
    if (stored == null || stored.isEmpty) return const <WordEntry>[];
    try {
      return (jsonDecode(stored) as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(WordEntry.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const <WordEntry>[];
    }
  }

  Future<void> recordLine({
    required String english,
    required String episodeId,
    required String course,
    required String episode,
    required String time,
    required String lineKey,
    required String chinese,
    Map<String, String> generatedDefinitions = const <String, String>{},
  }) async {
    final Map<String, int> rawWordCounts = <String, int>{};
    for (final String word in tokenizeWords(english)) {
      rawWordCounts[word] = (rawWordCounts[word] ?? 0) + 1;
    }
    if (rawWordCounts.isEmpty) return;
    final OfflineWordDictionary dictionary = ref.read(
      offlineWordDictionaryProvider,
    );
    final List<OfflineWordDefinition?> definitions = await Future.wait(
      rawWordCounts.keys.map(dictionary.lookup),
    );
    final Map<String, int> wordCounts = <String, int>{
      for (int index = 0; index < rawWordCounts.length; index++)
        if (definitions[index] != null)
          rawWordCounts.keys.elementAt(index): rawWordCounts.values.elementAt(
            index,
          ),
    };
    if (wordCounts.isEmpty) return;
    final Map<String, WordEntry> entries = <String, WordEntry>{
      for (final WordEntry item in state) item.word: item,
    };
    bool changed = false;
    for (final MapEntry<String, int> entry in wordCounts.entries) {
      final String word = entry.key;
      final WordEntry? current = entries[word];
      final int occurrenceIndex =
          current?.occurrences.indexWhere(
            (WordOccurrence item) => item.episodeId == episodeId,
          ) ??
          -1;
      if (occurrenceIndex >= 0 &&
          current!.occurrences[occurrenceIndex].lineKeys.contains(lineKey)) {
        continue;
      }
      if (occurrenceIndex < 0) {
        final WordOccurrence occurrence = WordOccurrence(
          episodeId: episodeId,
          course: course,
          episode: episode,
          time: time,
          sentence: english.trim(),
          chinese: chinese.trim(),
          count: entry.value,
          lineKeys: <String>[lineKey],
          contexts: <WordContext>[
            WordContext(
              lineKey: lineKey,
              time: time,
              sentence: english.trim(),
              chinese: chinese.trim(),
              count: entry.value,
            ),
          ],
        );
        entries[word] = current == null
            ? WordEntry(
                word: word,
                favorite: false,
                occurrences: <WordOccurrence>[occurrence],
              )
            : current.copyWith(
                occurrences: <WordOccurrence>[
                  ...current.occurrences,
                  occurrence,
                ],
              );
      } else {
        final List<WordOccurrence> occurrences = <WordOccurrence>[
          ...current!.occurrences,
        ];
        final WordOccurrence previous = occurrences[occurrenceIndex];
        occurrences[occurrenceIndex] = previous.copyWith(
          count: previous.count + entry.value,
          lineKeys: <String>[...previous.lineKeys, lineKey],
          contexts: <WordContext>[
            ...previous.contexts,
            WordContext(
              lineKey: lineKey,
              time: time,
              sentence: english.trim(),
              chinese: chinese.trim(),
              count: entry.value,
            ),
          ],
        );
        entries[word] = current.copyWith(occurrences: occurrences);
      }
      changed = true;
    }
    bool definitionsChanged = false;
    for (final String word in wordCounts.keys) {
      final String? definition = generatedDefinitions[word]?.trim();
      final WordEntry? entry = entries[word];
      if (entry != null &&
          entry.definitionCn == null &&
          definition != null &&
          definition.isNotEmpty) {
        entries[word] = entry.copyWith(definitionCn: definition);
        definitionsChanged = true;
      }
    }
    if (!changed && !definitionsChanged) return;
    state = entries.values.toList()
      ..sort((WordEntry a, WordEntry b) => a.word.compareTo(b.word));
    unawaited(_persist());
    unawaited(_fillOfflineDefinitions(wordCounts.keys));
  }

  bool? toggleFavorite(String rawWord) {
    final String word = normalizeWord(rawWord);
    if (word.isEmpty) return null;
    final int index = state.indexWhere((WordEntry item) => item.word == word);
    if (index < 0) return null;
    final List<WordEntry> next = <WordEntry>[...state];
    next[index] = next[index].copyWith(favorite: !next[index].favorite);
    state = next;
    unawaited(_persist());
    return state[index].favorite;
  }

  bool addFavoriteWord({
    required String rawWord,
    required String episodeId,
    required String course,
    required String episode,
    required String time,
    required String lineKey,
    required String sentence,
    required String chinese,
    String? generatedDefinition,
  }) {
    final String word = normalizeWord(rawWord);
    if (!_isIndependentEnglishWord(word)) return false;
    final String? definition = generatedDefinition?.trim();
    final String? validDefinition = definition == null || definition.isEmpty
        ? null
        : definition;
    final int count = tokenizeWords(
      sentence,
    ).where((String item) => item == word).length;
    final int entryIndex = state.indexWhere(
      (WordEntry item) => item.word == word,
    );
    final WordContext context = WordContext(
      lineKey: lineKey,
      time: time,
      sentence: sentence.trim(),
      chinese: chinese.trim(),
      count: count == 0 ? 1 : count,
    );
    if (entryIndex < 0) {
      state = <WordEntry>[
        WordEntry(
          word: word,
          favorite: true,
          definitionCn: validDefinition,
          occurrences: <WordOccurrence>[
            WordOccurrence(
              episodeId: episodeId,
              course: course,
              episode: episode,
              time: time,
              sentence: sentence.trim(),
              chinese: chinese.trim(),
              count: context.count,
              lineKeys: <String>[lineKey],
              contexts: <WordContext>[context],
            ),
          ],
        ),
        ...state,
      ];
    } else {
      final WordEntry entry = state[entryIndex];
      final List<WordOccurrence> occurrences = entry.occurrences
          .map((WordOccurrence occurrence) {
            if (occurrence.episodeId != episodeId ||
                occurrence.lineKeys.contains(lineKey)) {
              return occurrence;
            }
            return occurrence.copyWith(
              count: occurrence.count + context.count,
              lineKeys: <String>[...occurrence.lineKeys, lineKey],
              contexts: <WordContext>[...occurrence.contexts, context],
            );
          })
          .toList(growable: false);
      if (!occurrences.any(
        (WordOccurrence item) => item.episodeId == episodeId,
      )) {
        occurrences.add(
          WordOccurrence(
            episodeId: episodeId,
            course: course,
            episode: episode,
            time: time,
            sentence: sentence.trim(),
            chinese: chinese.trim(),
            count: context.count,
            lineKeys: <String>[lineKey],
            contexts: <WordContext>[context],
          ),
        );
      }
      final List<WordEntry> next = <WordEntry>[...state];
      next[entryIndex] = WordEntry(
        word: entry.word,
        favorite: true,
        occurrences: occurrences,
        definitionCn: entry.definitionCn ?? validDefinition,
        offlineDefinitionCn: entry.offlineDefinitionCn,
      );
      state = next;
    }
    unawaited(_persist());
    unawaited(_fillOfflineDefinitions(<String>[word]));
    return true;
  }

  void setDefinition(String rawWord, String definitionCn) {
    final String word = normalizeWord(rawWord);
    final String definition = definitionCn.trim();
    final int index = state.indexWhere((WordEntry item) => item.word == word);
    if (definition.isEmpty ||
        index < 0 ||
        state[index].definitionCn == definition) {
      return;
    }
    final List<WordEntry> next = <WordEntry>[...state];
    next[index] = next[index].copyWith(definitionCn: definition);
    state = next;
    unawaited(_persist());
  }

  bool editWord({
    required String rawWord,
    required String nextWord,
    required String definitionCn,
  }) {
    final String word = normalizeWord(rawWord);
    final String updatedWord = normalizeWord(nextWord);
    final int index = state.indexWhere((WordEntry entry) => entry.word == word);
    if (updatedWord.isEmpty || index < 0) return false;
    if (updatedWord != word &&
        state.any((WordEntry item) => item.word == updatedWord)) {
      return false;
    }
    final WordEntry entry = state[index];
    final List<WordEntry> next = <WordEntry>[...state];
    next[index] = WordEntry(
      word: updatedWord,
      favorite: entry.favorite,
      occurrences: entry.occurrences,
      definitionCn: definitionCn.trim().isEmpty ? null : definitionCn.trim(),
      offlineDefinitionCn: updatedWord == word
          ? entry.offlineDefinitionCn
          : null,
    );
    next.sort((WordEntry a, WordEntry b) => a.word.compareTo(b.word));
    state = next;
    unawaited(_persist());
    if (updatedWord != word) {
      unawaited(_fillOfflineDefinitions(<String>[updatedWord]));
    }
    return true;
  }

  bool deleteWord(String rawWord) {
    final String word = normalizeWord(rawWord);
    final List<WordEntry> next = state
        .where((WordEntry entry) => entry.word != word)
        .toList(growable: false);
    if (next.length == state.length) return false;
    state = next;
    unawaited(_persist());
    return true;
  }

  void refreshOfflineDefinitions() {
    unawaited(
      _removeInvalidWords().then((_) {
        return _fillOfflineDefinitions(
          state.map((WordEntry entry) => entry.word),
        );
      }),
    );
  }

  Future<void> _removeInvalidWords() async {
    final List<WordEntry> candidates = state
        .where((WordEntry entry) => _isIndependentEnglishWord(entry.word))
        .toList(growable: false);
    try {
      final OfflineWordDictionary dictionary = ref.read(
        offlineWordDictionaryProvider,
      );
      final List<OfflineWordDefinition?> definitions = await Future.wait(
        candidates.map((WordEntry entry) => dictionary.lookup(entry.word)),
      );
      final Set<String> validWords = <String>{
        for (int index = 0; index < candidates.length; index++)
          if (definitions[index] != null) candidates[index].word,
      };
      final List<WordEntry> next = state
          .where((WordEntry entry) => validWords.contains(entry.word))
          .toList(growable: false);
      if (next.length == state.length) return;
      state = next;
      unawaited(_persist());
    } catch (_) {
      // Keep existing entries if the optional offline dictionary is unavailable.
    }
  }

  Future<void> _fillOfflineDefinitions(Iterable<String> words) async {
    final List<String> pending = words
        .where(
          (String word) =>
              state.any(
                (WordEntry entry) =>
                    entry.word == word && entry.offlineDefinitionCn == null,
              ) &&
              _pendingOfflineDefinitions.add(word),
        )
        .toList(growable: false);
    if (pending.isEmpty) return;
    try {
      final OfflineWordDictionary dictionary = ref.read(
        offlineWordDictionaryProvider,
      );
      final List<OfflineWordDefinition?> definitions = await Future.wait(
        pending.map(dictionary.lookup),
      );
      final Map<String, String> translations = <String, String>{
        for (int index = 0; index < pending.length; index++)
          if (definitions[index]?.translation.isNotEmpty ?? false)
            pending[index]: definitions[index]!.translation,
      };
      if (translations.isEmpty) return;
      state = state
          .map(
            (WordEntry entry) => translations.containsKey(entry.word)
                ? entry.copyWith(offlineDefinitionCn: translations[entry.word])
                : entry,
          )
          .toList(growable: false);
      unawaited(_persist());
    } catch (_) {
      // The word is still saved even if the optional offline dictionary is unavailable.
    } finally {
      _pendingOfflineDefinitions.removeAll(pending);
    }
  }

  void setContextTranslation({
    required String rawWord,
    required String episodeId,
    required String lineKey,
    required String translation,
  }) {
    final int wordIndex = state.indexWhere(
      (WordEntry item) => item.word == normalizeWord(rawWord),
    );
    if (wordIndex < 0 || translation.trim().isEmpty) return;
    final WordEntry entry = state[wordIndex];
    final List<WordOccurrence> occurrences = entry.occurrences
        .map((WordOccurrence occurrence) {
          if (occurrence.episodeId != episodeId) return occurrence;
          return occurrence.copyWith(
            contexts: occurrence.contexts
                .map((WordContext context) {
                  return context.lineKey == lineKey
                      ? context.copyWith(apiTranslationCn: translation.trim())
                      : context;
                })
                .toList(growable: false),
          );
        })
        .toList(growable: false);
    final List<WordEntry> next = <WordEntry>[...state];
    next[wordIndex] = entry.copyWith(occurrences: occurrences);
    state = next;
    unawaited(_persist());
  }

  Future<void> _persist() async {
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>('prefs').put(
      _wordBookStorageKey,
      jsonEncode(state.map((WordEntry item) => item.toJson()).toList()),
    );
  }
}

List<String> tokenizeWords(String sentence) =>
    RegExp("(?<![A-Za-z'’])[A-Za-z]{2,}(?![A-Za-z'’])")
        .allMatches(sentence)
        .map((Match match) => normalizeWord(match.group(0)!))
        .where(_isIndependentEnglishWord)
        .toList(growable: false);

String normalizeWord(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('’', "'")
    .replaceAll(RegExp(r'^[^A-Za-z0-9_]+|[^A-Za-z0-9_]+$'), '');

bool _isIndependentEnglishWord(String word) =>
    RegExp(r'^[a-z]{2,}$').hasMatch(word);
