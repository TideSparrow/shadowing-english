import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:common_learn_english/features/anki_export/data/anki_export_builder.dart';
import 'package:common_learn_english/features/anki_export/data/anki_export_service.dart';
import 'package:common_learn_english/features/anki_export/domain/anki_export_note.dart';
import 'package:common_learn_english/features/phrases/presentation/phrase_book_provider.dart';
import 'package:common_learn_english/features/words/data/offline_word_dictionary.dart';
import 'package:common_learn_english/features/words/presentation/word_book_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:html/parser.dart' as html;
import 'package:sqlite3/sqlite3.dart';

class _Dictionary extends OfflineWordDictionary {
  @override
  Future<OfflineWordDefinition?> lookup(String rawWord) async => null;
}

const String _raw = "OH, HERE'S SOME ANTACID.\nI'M HERE!";
const String _mixed = 'Another Case & <TAG>.';
const List<WordEntry> _words = <WordEntry>[
  WordEntry(
    word: 'antacid',
    favorite: true,
    definitionCn: '抗酸药 API',
    occurrences: <WordOccurrence>[
      WordOccurrence(
        episodeId: 'episode-1',
        course: 'Course S1',
        episode: 'Episode 01',
        time: '00:01',
        sentence: _raw,
        chinese: '原句翻译 API',
        count: 1,
        lineKeys: <String>['1000-2000'],
        contexts: <WordContext>[
          WordContext(
            lineKey: '1000-2000',
            time: '00:01',
            sentence: _raw,
            chinese: '原句翻译 API',
            count: 1,
          ),
        ],
      ),
      // Legacy data may have no per-line contexts.
      WordOccurrence(
        episodeId: 'episode-2',
        course: 'Course S1',
        episode: 'Episode 02',
        time: '00:02',
        sentence: _mixed,
        chinese: '历史翻译 API',
        count: 1,
        lineKeys: <String>[],
        contexts: <WordContext>[],
      ),
    ],
  ),
];
const List<PhraseEntry> _phrases = <PhraseEntry>[
  PhraseEntry(
    id: 'phrase-1',
    english: _raw,
    chinese: '短语翻译 API',
    course: 'Course S1',
    episode: 'Episode 01',
    time: '00:01',
    rating: 2,
    needsReview: true,
    today: false,
  ),
];

const Map<String, (String, String)> _expected = <String, (String, String)>{
  '保留原样': (_raw, _mixed),
  '全部大写': (_raw, 'ANOTHER CASE & <TAG>.'),
  '全部小写': ("oh, here's some antacid.\ni'm here!", 'another case & <tag>.'),
  '句首字母大写': ("Oh, here's some antacid.\nI'm here!", 'Another case & <tag>.'),
};

void main() {
  for (final AnkiExportFormat format in AnkiExportFormat.values) {
    test(
      '${format.name} applies each case mode and keeps saved originals intact',
      () async {
        final Directory root = Directory.systemTemp.createTempSync(
          'anki-case-',
        );
        Hive.init(root.path);
        final Box<String> prefs = await Hive.openBox<String>('prefs');
        addTearDown(() async {
          await Hive.close();
          root.deleteSync(recursive: true);
        });
        final String savedWords = jsonEncode(
          _words.map((WordEntry w) => w.toJson()).toList(),
        );
        final String savedPhrases = jsonEncode(
          _phrases.map((PhraseEntry p) => p.toJson()).toList(),
        );
        await prefs.put('word_book_v1', savedWords);
        await prefs.put('phrase_book_v2', savedPhrases);
        final List<WordEntry> words =
            (jsonDecode(prefs.get('word_book_v1')!) as List<dynamic>)
                .map(
                  (dynamic w) => WordEntry.fromJson(
                    Map<String, Object?>.from(w as Map<String, dynamic>),
                  ),
                )
                .toList();
        final List<PhraseEntry> phrases =
            (jsonDecode(prefs.get('phrase_book_v2')!) as List<dynamic>)
                .map(
                  (dynamic p) => PhraseEntry.fromJson(
                    Map<String, Object?>.from(p as Map<String, dynamic>),
                  ),
                )
                .toList();
        final AnkiExportService service = AnkiExportService(
          AnkiExportBuilder(_Dictionary()),
        );
        List<String>? packageIdentities;
        for (final MapEntry<String, (String, String)> mode
            in _expected.entries) {
          final AnkiExportFile file = await service.generate(
            words: words,
            phrases: phrases,
            format: format,
            deckName: 'Case test',
            subtitleLetterCase: mode.key,
          );
          late List<List<String>> fields;
          if (format == AnkiExportFormat.apkg) {
            final Archive package = ZipDecoder().decodeBytes(file.bytes);
            final File dbFile = File('${root.path}/export.anki2')
              ..writeAsBytesSync(
                package.findFile('collection.anki2')!.content as List<int>,
              );
            final Database database = sqlite3.open(dbFile.path);
            try {
              final ResultSet rows = database.select(
                'SELECT id, guid, flds FROM notes ORDER BY id',
              );
              final List<String> identities = rows
                  .map((Row row) => '${row['id']}:${row['guid']}')
                  .toList();
              if (packageIdentities == null) {
                packageIdentities = identities;
              } else {
                expect(
                  identities,
                  packageIdentities,
                  reason: 'A case change must update existing Anki notes',
                );
              }
              fields = rows
                  .map(
                    (Row row) => (row['flds'] as String)
                        .split('\x1f')
                        .map(
                          (String field) =>
                              html.parseFragment(field).text ?? '',
                        )
                        .toList(),
                  )
                  .toList();
              expect(
                database.select('PRAGMA integrity_check').single.values.first,
                'ok',
              );
            } finally {
              database.close();
            }
          } else {
            fields = _parseTable(
              utf8.decode(file.bytes),
              format == AnkiExportFormat.csv ? ',' : '\t',
            ).skip(1).toList();
          }
          expect(fields, hasLength(2));
          final List<String> word = fields.singleWhere(
            (List<String> row) => row.last == '单词',
          );
          final List<String> phrase = fields.singleWhere(
            (List<String> row) => row.last == '短语',
          );
          expect(word[0], 'antacid');
          expect(word[2], '抗酸药 API');
          for (final String line in mode.value.$1.split('\n')) {
            expect(word[3], contains(line));
            expect(phrase[0], contains(line));
            expect(phrase[3], contains(line));
          }
          expect(word[3], contains(mode.value.$2));
          expect(word[4], contains('原句翻译 API'));
          expect(word[4], contains('历史翻译 API'));
          expect(word[5], contains('Course S1 · Episode 01'));
          expect(word[6], contains('00:01'));
          expect(word[6], contains('00:02'));
          expect(phrase[2], '短语翻译 API');
          expect(
            jsonEncode(words.map((WordEntry w) => w.toJson()).toList()),
            savedWords,
          );
          expect(
            jsonEncode(phrases.map((PhraseEntry p) => p.toJson()).toList()),
            savedPhrases,
          );
          expect(prefs.get('word_book_v1'), savedWords);
          expect(prefs.get('phrase_book_v2'), savedPhrases);
        }
      },
    );
  }
}

List<List<String>> _parseTable(String text, String separator) {
  final List<List<String>> rows = <List<String>>[];
  List<String> row = <String>[];
  final StringBuffer field = StringBuffer();
  bool quoted = false;
  for (int i = 0; i < text.length; i++) {
    final String ch = text[i];
    if (ch == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted && ch == separator) {
      row.add(field.toString());
      field.clear();
    } else if (!quoted &&
        ch == '\r' &&
        i + 1 < text.length &&
        text[i + 1] == '\n') {
      row.add(field.toString());
      rows.add(row);
      row = <String>[];
      field.clear();
      i++;
    } else {
      field.write(ch);
    }
  }
  expect(quoted, isFalse);
  if (row.isNotEmpty || field.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}
