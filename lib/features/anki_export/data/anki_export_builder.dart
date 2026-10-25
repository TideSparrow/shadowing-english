import 'dart:convert';

import '../../phrases/presentation/phrase_book_provider.dart';
import '../../shared/domain/subtitle_letter_case.dart';
import '../../words/data/offline_word_dictionary.dart';
import '../../words/presentation/word_book_provider.dart';
import '../domain/anki_export_note.dart';

/// A read-only snapshot of saved learning content. No review state is exported.
class AnkiExportBuilder {
  AnkiExportBuilder(this.dictionary);

  final OfflineWordDictionary dictionary;

  Future<List<AnkiExportNote>> build({
    required List<WordEntry> words,
    required List<PhraseEntry> phrases,
    String subtitleLetterCase = '保留原样',
  }) async {
    final List<AnkiExportNote> notes = <AnkiExportNote>[];
    final List<WordEntry> savedWords =
        words.where((WordEntry word) => word.favorite).toList()
          ..sort((WordEntry a, WordEntry b) => a.word.compareTo(b.word));
    for (final WordEntry word in savedWords) {
      final String expression = normalizeWord(word.word);
      if (expression.isEmpty) continue;
      final OfflineWordDefinition? definition = await dictionary.lookup(
        expression,
      );
      final List<_Context> contexts = <_Context>[];
      for (final WordOccurrence occurrence in word.occurrences) {
        if (occurrence.contexts.isEmpty) {
          contexts.add(
            _Context(
              occurrence.sentence,
              occurrence.chinese,
              occurrence.course,
              occurrence.episode,
              occurrence.time,
              occurrence.episodeId,
            ),
          );
        } else {
          for (final WordContext context in occurrence.contexts) {
            contexts.add(
              _Context(
                context.sentence,
                _first(<String?>[context.apiTranslationCn, context.chinese]),
                occurrence.course,
                occurrence.episode,
                context.time,
                occurrence.episodeId,
              ),
            );
          }
        }
      }
      notes.add(
        _note(
          id: 'word:$expression',
          expression: expression,
          phonetic: definition?.phonetic ?? '',
          meaning: _first(<String?>[
            word.definitionCn,
            word.offlineDefinitionCn,
            definition?.translation,
          ]).replaceAll(r'\n', '\n'),
          isPhrase: false,
          contexts: contexts,
          subtitleLetterCase: subtitleLetterCase,
        ),
      );
    }
    final Map<String, List<PhraseEntry>> phraseGroups =
        <String, List<PhraseEntry>>{};
    for (final PhraseEntry phrase in phrases) {
      final String expression = phrase.english.trim();
      if (expression.isNotEmpty) {
        (phraseGroups[expression] ??= <PhraseEntry>[]).add(phrase);
      }
    }
    final List<String> expressions = phraseGroups.keys.toList()..sort();
    for (final String expression in expressions) {
      final List<PhraseEntry> group = phraseGroups[expression]!;
      notes.add(
        _note(
          id: 'phrase:$expression',
          expression: expression,
          phonetic: '',
          meaning: group
              .map(
                (PhraseEntry item) => item.chinese
                    .replaceFirst(RegExp(r'\s*[（(]生词[:：].*?[）)]\s*$'), '')
                    .trim(),
              )
              .where((String value) => value.isNotEmpty)
              .toSet()
              .join('\n'),
          isPhrase: true,
          subtitleLetterCase: subtitleLetterCase,
          contexts: group
              .map(
                (PhraseEntry item) => _Context(
                  item.english,
                  item.chinese,
                  item.course,
                  item.episode,
                  _first(<String?>[item.startTime, item.time]),
                  item.episodeId ?? '',
                ),
              )
              .toList(),
        ),
      );
    }
    return notes;
  }
}

AnkiExportNote _note({
  required String id,
  required String expression,
  required String phonetic,
  required String meaning,
  required bool isPhrase,
  required List<_Context> contexts,
  required String subtitleLetterCase,
}) {
  final Map<String, _Context> unique = <String, _Context>{};
  for (final _Context context in contexts) {
    unique.putIfAbsent(
      jsonEncode(<String>[
        context.episodeId,
        context.course,
        context.episode,
        context.time,
        context.english,
        context.chinese,
      ]),
      () => context,
    );
  }
  final List<_Context> examples = unique.values.toList();
  String values(String Function(_Context) value) => examples
      .map(value)
      .where((String value) => value.isNotEmpty)
      .toSet()
      .map(_html)
      .join('<br>');
  return AnkiExportNote(
    id: id,
    isPhrase: isPhrase,
    fields: <String>[
      _html(
        isPhrase
            ? formatSubtitleLetterCase(expression, subtitleLetterCase)
            : expression,
      ),
      _html(phonetic),
      _html(meaning),
      examples
          .map(
            (_Context item) =>
                '<div class="example"> '
                '${item.english.isEmpty ? '' : '<div class="sentence">${_html(formatSubtitleLetterCase(item.english, subtitleLetterCase))}</div>'} '
                '${item.chinese.isEmpty ? '' : '<div class="translation">${_html(item.chinese)}</div>'} '
                '<div class="source">${_html(<String>[item.source, item.time].where((String v) => v.isNotEmpty).join(' · '))}</div> '
                '</div>',
          )
          .join(),
      values((_Context item) => item.chinese),
      values((_Context item) => item.source),
      values((_Context item) => item.time),
      if (isPhrase) '短语' else '单词',
    ],
  );
}

String _html(String value) => const HtmlEscape()
    .convert(
      value
          .replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'), '')
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n'),
    )
    .replaceAll('\n', '<br>');

String _first(List<String?> values) => values
    .firstWhere(
      (String? value) => value != null && value.trim().isNotEmpty,
      orElse: () => '',
    )!
    .trim();

class _Context {
  const _Context(
    this.english,
    this.chinese,
    this.course,
    this.episode,
    this.time,
    this.episodeId,
  );
  final String english;
  final String chinese;
  final String course;
  final String episode;
  final String time;
  final String episodeId;
  String get source => <String>[
    course,
    episode,
  ].where((String v) => v.trim().isNotEmpty).join(' · ');
}
