import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:common_learn_english/features/anki_export/domain/anki_export_encoder.dart';
import 'package:common_learn_english/features/anki_export/domain/anki_export_note.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final AnkiExportEncoder encoder = AnkiExportEncoder();

  test('rejects empty exports and non-text formats', () {
    expect(
      () => encoder.encodeText(<AnkiExportNote>[], AnkiExportFormat.csv),
      throwsArgumentError,
    );
    expect(
      () => encoder.encodeText(<AnkiExportNote>[
        _sampleNote(),
      ], AnkiExportFormat.apkg),
      throwsArgumentError,
    );
    expect(
      () => encoder.encodePackage(
        <AnkiExportNote>[],
        sqlite: sqlite3,
        deckName: 'Shadowing English',
        now: DateTime.utc(2026, 10, 23),
      ),
      throwsArgumentError,
    );
  });

  test('writes plain-text CSV and TSV and preserves special field content', () {
    final AnkiExportNote note = _sampleNote();
    for (final AnkiExportFormat format in <AnkiExportFormat>[
      AnkiExportFormat.csv,
      AnkiExportFormat.tsv,
    ]) {
      final Uint8List bytes = encoder.encodeText(<AnkiExportNote>[
        note,
      ], format);
      final String text = utf8.decode(bytes);
      final String separator = format == AnkiExportFormat.csv ? ',' : '\t';
      expect(bytes.take(3), <int>[0xef, 0xbb, 0xbf]);
      expect(text, startsWith('"英文"$separator"音标"$separator"释义"'));
      for (final String directive in <String>[
        '#separator:',
        '#html:',
        '#tags:',
        '#columns:',
      ]) {
        expect(text, isNot(contains(directive)));
      }
      final List<List<String>> table = _parseDelimited(text, separator);
      expect(table, hasLength(2));
      expect(table.first, <String>[
        '英文',
        '音标',
        '释义',
        '原句语境',
        '原句翻译',
        '来源',
        '时间点',
        '类型',
      ]);
      expect(text, isNot(contains('guid')));

      final int firstDataOffset = text.indexOf('\r\n') + 2;
      final List<List<String>> rows = _parseDelimited(
        text.substring(firstDataOffset),
        separator,
      );
      expect(rows, hasLength(1));
      expect(rows.single, hasLength(8));
      expect(rows.single, <String>[
        'café & 茶 🐳',
        note.fields[1],
        note.fields[2],
        'Context: tea\n第二行\x1fboundary',
        ...note.fields.skip(4),
      ]);
      expect(text, isNot(contains('<b>')));
      expect(text, isNot(contains('<div')));
      expect(text, isNot(contains('&amp;')));
    }
  });

  test('plain-text tables preserve literal markup and every context', () {
    final AnkiExportNote note = AnkiExportNote(
      id: 'word:literal',
      isPhrase: false,
      fields: <String>[
        '&lt;word&gt; &amp; &lt;3',
        '&#47;wɜːd&#47;',
        '&quot;quoted&quot;, café &#x1F433;',
        '''
<div class="example"><div>First &amp; second<br>continued</div>
<div>第一句</div><div>剧集 A · 00:01</div></div>
<div class="example"><div>&lt;script&gt;literal&lt;/script&gt;</div>
<div>第二句</div><div>剧集 B · 00:02</div></div>
''',
        '第一句<br>第二句',
        '剧集 A<br>剧集 B',
        '00:01<br>00:02',
        '单词',
      ],
    );
    for (final AnkiExportFormat format in <AnkiExportFormat>[
      AnkiExportFormat.csv,
      AnkiExportFormat.tsv,
    ]) {
      final String text = utf8.decode(
        encoder.encodeText(<AnkiExportNote>[note], format),
      );
      final int dataOffset = text.indexOf('\r\n') + 2;
      final List<String> row = _parseDelimited(
        text.substring(dataOffset),
        format == AnkiExportFormat.csv ? ',' : '\t',
      ).single;
      expect(row[0], '<word> & <3');
      expect(row[1], '/wɜːd/');
      expect(row[2], '"quoted", café 🐳');
      expect(row[3], contains('First & second\ncontinued'));
      expect(row[3], contains('<script>literal</script>'));
      expect(row[3], contains('第一句'));
      expect(row[3], contains('剧集 A · 00:01'));
      expect(row[3], contains('第二句'));
      expect(row[3], contains('剧集 B · 00:02'));
      expect(row[4], '第一句\n第二句');
      expect(row[5], '剧集 A\n剧集 B');
      expect(row[6], '00:01\n00:02');
    }
  });

  test('writes a valid schema-11 package with stable IDs and fresh cards', () {
    final AnkiExportNote note = _sampleNote();
    final Uint8List first = _package(encoder, <AnkiExportNote>[note]);
    final _OpenedPackage parsed = _readPackage(first);
    final Archive archive = parsed.archive;

    expect(archive.files.map((ArchiveFile file) => file.name).toSet(), <String>{
      'collection.anki2',
      'media',
    });
    expect(
      jsonDecode(utf8.decode(archive.findFile('media')!.content as List<int>)),
      <String, Object?>{},
    );
    expect(
      parsed.database.select('PRAGMA integrity_check').single.values.first,
      'ok',
    );
    expect(parsed.database.select('SELECT ver FROM col').single['ver'], 11);

    final Row noteRow = parsed.database
        .select('SELECT id, guid, mid, mod, tags, flds, sfld FROM notes')
        .single;
    final List<String> storedFields = (noteRow['flds'] as String).split('\x1f');
    expect(storedFields, hasLength(8));
    expect(
      storedFields,
      note.fields
          .map((String field) => field.replaceAll('\x1f', '&#31;'))
          .toList(),
    );
    expect(noteRow['guid'], startsWith('shadowing-english-v1:'));
    expect(noteRow['tags'], ' shadowing_english ');

    final Row cardRow = parsed.database
        .select(
          'SELECT id, nid, did, ord, type, queue, ivl, factor, reps, lapses, odue, odid FROM cards',
        )
        .single;
    expect(cardRow['nid'], noteRow['id']);
    expect(cardRow['ord'], 0);
    expect(cardRow['type'], 0);
    expect(cardRow['queue'], 0);
    expect(cardRow['ivl'], 0);
    expect(cardRow['factor'], 0);
    expect(cardRow['reps'], 0);
    expect(cardRow['lapses'], 0);
    expect(cardRow['odue'], 0);
    expect(cardRow['odid'], 0);
    expect(
      parsed.database
          .select('SELECT COUNT(*) AS count FROM revlog')
          .single['count'],
      0,
    );

    final Map<String, dynamic> models =
        jsonDecode(
              parsed.database.select('SELECT models FROM col').single['models']
                  as String,
            )
            as Map<String, dynamic>;
    final Map<String, dynamic> model =
        models.values.single as Map<String, dynamic>;
    expect(model['name'], 'Shadowing English (TideSparrow)');
    expect(model['id'], '${noteRow['mid']}');
    expect(
      (model['flds'] as List<dynamic>).map(
        (dynamic field) => (field as Map<String, dynamic>)['name'],
      ),
      AnkiExportNote.fieldNames,
    );
    final Map<String, dynamic> template =
        (model['tmpls'] as List<dynamic>).single as Map<String, dynamic>;
    // Some mobile clients read the whole card rather than its TTS field.
    // Keep the type in note data, without a spoken "Word/Phrase" heading.
    expect(template['qfmt'], isNot(contains('{{Kind}}')));
    expect(template['afmt'], isNot(contains('{{Kind}}')));
    expect(template['qfmt'], contains('{{Expression}}'));
    expect(template['qfmt'], contains('{{Phonetic}}'));
    for (final String side in <String>['qfmt', 'afmt']) {
      final String content = template[side] as String;
      expect('{{tts en_US:Expression}}'.allMatches(content), hasLength(1));
      expect(content, contains('{{Expression}}'));
    }
    expect(template['afmt'], isNot(contains('{{FrontSide}}')));
    expect(template['afmt'], contains('{{Meaning}}'));
    expect(template['afmt'], contains('{{Context}}'));
    expect(template['afmt'], isNot(contains('{{Translation}}')));
    expect(template['qfmt'], contains('se-native-audio" hidden'));
    expect(template['qfmt'], contains('aria-label="朗读英文" hidden'));
    expect(template['qfmt'], contains('voice.localService'));
    expect(
      template['qfmt'],
      contains("card.querySelector('.se-expression').textContent"),
    );
    expect(template['qfmt'], isNot(contains('<script src=')));
    expect(template['qfmt'], isNot(contains('fetch(')));

    final AnkiExportNote changed = _sampleNote(
      expression: '<b>updated café 🐳</b>',
    );
    final Uint8List later = _package(encoder, <AnkiExportNote>[
      changed,
    ], now: DateTime.utc(2026, 10, 24));
    final _OpenedPackage updated = _readPackage(later);
    final Row updatedNote = updated.database
        .select('SELECT id, guid, mid, flds FROM notes')
        .single;
    final Row updatedCard = updated.database
        .select('SELECT id, nid, did FROM cards')
        .single;
    expect(updatedNote['id'], noteRow['id']);
    expect(updatedNote['guid'], noteRow['guid']);
    expect(updatedNote['mid'], noteRow['mid']);
    expect(updatedCard['id'], cardRow['id']);
    expect(updatedCard['nid'], cardRow['nid']);
    expect(updatedCard['did'], cardRow['did']);
    expect(updatedNote['flds'], contains('updated café 🐳'));

    parsed.close();
    updated.close();
  });

  test('keeps same-expression words and phrases separate', () {
    final List<AnkiExportNote> notes = <AnkiExportNote>[
      _sampleNote(id: 'same-source'),
      _sampleNote(id: 'same-source', isPhrase: true, kind: 'Phrase'),
    ];
    final _OpenedPackage parsed = _readPackage(_package(encoder, notes));
    final ResultSet rows = parsed.database.select(
      'SELECT guid, flds FROM notes ORDER BY guid',
    );
    expect(rows, hasLength(2));
    expect(rows[0]['guid'], isNot(rows[1]['guid']));
    expect(
      rows.map((Row row) => (row['flds'] as String).split('\x1f').last).toSet(),
      <String>{'Word', 'Phrase'},
    );
    expect(
      parsed.database
          .select('SELECT COUNT(*) AS count FROM cards')
          .single['count'],
      2,
    );
    parsed.close();
  });

  test('advances note modification time for rapid same-second exports', () {
    final DateTime sameSecond = DateTime.utc(2026, 10, 23, 9, 30);
    final _OpenedPackage first = _readPackage(
      _package(encoder, <AnkiExportNote>[_sampleNote()], now: sameSecond),
    );
    final _OpenedPackage updated = _readPackage(
      _package(encoder, <AnkiExportNote>[
        _sampleNote(expression: '<b>updated</b>'),
      ], now: sameSecond),
    );

    final Row firstNote = first.database
        .select('SELECT id, guid, mod FROM notes')
        .single;
    final Row updatedNote = updated.database
        .select('SELECT id, guid, mod FROM notes')
        .single;
    expect(updatedNote['id'], firstNote['id']);
    expect(updatedNote['guid'], firstNote['guid']);
    expect(updatedNote['mod'] as int, greaterThan(firstNote['mod'] as int));

    first.close();
    updated.close();
  });
}

AnkiExportNote _sampleNote({
  String id = 'word:naïve',
  bool isPhrase = false,
  String kind = 'Word',
  String expression = '<b>café &amp; 茶 🐳</b>',
}) => AnkiExportNote(
  id: id,
  isPhrase: isPhrase,
  fields: <String>[
    expression,
    '/ˈnaɪˌiːv/\t"say it"\n二\x1fphonetic',
    'Meaning: "bright", café, \x1f separator',
    'Context: <b>tea</b>\r\n第二行\x1fboundary',
    'BACK_DO_NOT_DUPLICATE_TRANSLATION',
    'Source:引用，逗号\t制表符',
    '2026-10-23\n09:30',
    kind,
  ],
);

Uint8List _package(
  AnkiExportEncoder encoder,
  List<AnkiExportNote> notes, {
  DateTime? now,
}) => encoder.encodePackage(
  notes,
  sqlite: sqlite3,
  deckName: 'Shadowing::Vocabulary',
  now: now ?? DateTime.utc(2026, 10, 23, 9, 30),
);

_OpenedPackage _readPackage(Uint8List bytes) {
  final Archive archive = ZipDecoder().decodeBytes(bytes);
  final ArchiveFile? collection = archive.findFile('collection.anki2');
  expect(collection, isNotNull);
  final Directory directory = Directory.systemTemp.createTempSync(
    'anki-export-test-',
  );
  final String path = '${directory.path}/collection.anki2';
  File(path).writeAsBytesSync(collection!.content as List<int>);
  final Database database = sqlite3.open(path);
  return _OpenedPackage(archive, database, directory);
}

List<List<String>> _parseDelimited(String input, String separator) {
  final List<List<String>> rows = <List<String>>[];
  List<String> row = <String>[];
  final StringBuffer field = StringBuffer();
  bool quoted = false;

  for (int index = 0; index < input.length; index++) {
    final String character = input[index];
    if (quoted) {
      if (character == '"') {
        if (index + 1 < input.length && input[index + 1] == '"') {
          field.write('"');
          index++;
        } else {
          quoted = false;
        }
      } else {
        field.write(character);
      }
      continue;
    }

    if (character == '"' && field.isEmpty) {
      quoted = true;
    } else if (character == separator) {
      row.add(field.toString());
      field.clear();
    } else if (character == '\r' &&
        index + 1 < input.length &&
        input[index + 1] == '\n') {
      row.add(field.toString());
      rows.add(row);
      row = <String>[];
      field.clear();
      index++;
    } else {
      field.write(character);
    }
  }

  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  expect(
    quoted,
    isFalse,
    reason: 'The final delimited field must close its quote.',
  );
  return rows;
}

class _OpenedPackage {
  _OpenedPackage(this.archive, this.database, this.directory);

  final Archive archive;
  final Database database;
  final Directory directory;

  void close() {
    database.close();
    directory.deleteSync(recursive: true);
  }
}
