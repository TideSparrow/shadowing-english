import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:sqlite3/common.dart';

import 'anki_export_note.dart';

/// Encodes Anki text imports and legacy collection packages.
class AnkiExportEncoder {
  static const String _modelNamespace = 'com.tidesparrow.shadowing-english.v1';
  static const String _modelName = 'Shadowing English (TideSparrow)';
  static const String _tag = 'shadowing_english';
  static const String _fieldSeparator = '\x1f';
  static int _vfsSequence = 0;
  static int _lastModifiedSeconds = 0;

  static const List<String> _tableColumns = <String>[
    '英文',
    '音标',
    '释义',
    '原句语境',
    '原句翻译',
    '来源',
    '时间点',
    '类型',
  ];

  /// Encodes plain-text spreadsheet CSV and TSV with the same Chinese headers.
  Uint8List encodeText(List<AnkiExportNote> notes, AnkiExportFormat format) {
    _validateNotes(notes);
    if (format != AnkiExportFormat.tsv && format != AnkiExportFormat.csv) {
      throw ArgumentError.value(
        format,
        'format',
        'Text export requires TSV or CSV.',
      );
    }

    final String separator = format == AnkiExportFormat.tsv ? '\t' : ',';
    // The UTF-8 BOM lets spreadsheet applications recognize Chinese text.
    final StringBuffer output = StringBuffer()
      ..write('\uFEFF')
      ..write(_tableColumns.map(_quoteDelimitedField).join(separator))
      ..write('\r\n');

    for (final AnkiExportNote note in notes) {
      final List<String> fields = note.fields.map(_plainText).toList();
      output
        ..write(fields.map(_quoteDelimitedField).join(separator))
        ..write('\r\n');
    }

    return Uint8List.fromList(utf8.encode(output.toString()));
  }

  /// Encodes a schema-11 Anki deck package without user collection state.
  Uint8List encodePackage(
    List<AnkiExportNote> notes, {
    required CommonSqlite3 sqlite,
    required String deckName,
    required DateTime now,
  }) {
    _validateNotes(notes);
    if (deckName.trim().isEmpty) {
      throw ArgumentError.value(
        deckName,
        'deckName',
        'Deck name must not be empty.',
      );
    }

    final DateTime utcNow = now.toUtc();
    final int requestedModifiedSeconds = utcNow.millisecondsSinceEpoch ~/ 1000;
    // Anki compares note modification times in whole seconds. Keep successive
    // exports newer within this app process so rapid edits can be imported.
    final int modifiedSeconds = requestedModifiedSeconds > _lastModifiedSeconds
        ? requestedModifiedSeconds
        : _lastModifiedSeconds + 1;
    _lastModifiedSeconds = modifiedSeconds;
    final int modifiedMillis = utcNow.millisecondsSinceEpoch;
    final int modelId = _stableId('model|$_modelNamespace');
    // The Default deck is a reserved entry in a legacy collection package.
    final int deckId = deckName == 'Default' ? 1 : _stableId('deck|$deckName');
    final InMemoryFileSystem vfs = InMemoryFileSystem(
      name: 'anki-export-${identityHashCode(this)}-${_vfsSequence++}',
    );
    CommonDatabase? database;
    bool registered = false;

    try {
      sqlite.registerVirtualFileSystem(vfs);
      registered = true;
      database = sqlite.open('/collection.anki2', vfs: vfs.name)
        ..execute('PRAGMA journal_mode=DELETE')
        ..execute('PRAGMA synchronous=OFF');
      _createSchema(database);

      database.execute('BEGIN IMMEDIATE');
      try {
        _insertCollection(
          database,
          deckName: deckName,
          deckId: deckId,
          modelId: modelId,
          modifiedSeconds: modifiedSeconds,
          modifiedMillis: modifiedMillis,
          nextPosition: notes.length + 1,
        );
        _insertNotes(
          database,
          notes: notes,
          deckId: deckId,
          modelId: modelId,
          modifiedSeconds: modifiedSeconds,
        );
        database.execute('COMMIT');
      } catch (_) {
        database.execute('ROLLBACK');
        rethrow;
      }

      database.close();
      database = null;

      final List<int>? file = vfs.fileData['/collection.anki2'];
      if (file == null || file.isEmpty) {
        throw StateError('SQLite did not produce collection.anki2.');
      }
      return _zipPackage(Uint8List.fromList(file.toList()));
    } finally {
      try {
        database?.close();
      } finally {
        if (registered) sqlite.unregisterVirtualFileSystem(vfs);
      }
    }
  }

  void _validateNotes(List<AnkiExportNote> notes) {
    if (notes.isEmpty) {
      throw ArgumentError.value(
        notes,
        'notes',
        'Cannot export an empty Anki deck.',
      );
    }

    final Set<String> identities = <String>{};
    final Set<int> noteIds = <int>{};
    final Set<int> cardIds = <int>{};
    for (final AnkiExportNote note in notes) {
      if (note.id.isEmpty) {
        throw ArgumentError.value(
          note.id,
          'note.id',
          'Anki source id must not be empty.',
        );
      }
      if (note.fields.length != AnkiExportNote.fieldNames.length) {
        throw ArgumentError.value(
          note.fields.length,
          'note.fields.length',
          'Anki notes must contain exactly eight fields.',
        );
      }

      final String identity = _sourceIdentity(note);
      if (!identities.add(identity)) {
        throw ArgumentError.value(
          note.id,
          'notes',
          'Anki source ids must be unique.',
        );
      }
      if (!noteIds.add(_stableId('note|$identity'))) {
        throw ArgumentError.value(
          note.id,
          'notes',
          'Anki note id hash collision.',
        );
      }
      if (!cardIds.add(_stableId('card|$identity|0'))) {
        throw ArgumentError.value(
          note.id,
          'notes',
          'Anki card id hash collision.',
        );
      }
    }
  }

  String _sourceIdentity(AnkiExportNote note) =>
      '${note.isPhrase ? 'phrase' : 'word'}:${note.id}';

  String _guidFor(AnkiExportNote note) {
    final Digest digest = sha256.convert(utf8.encode(_sourceIdentity(note)));
    return 'shadowing-english-v1:$digest';
  }

  int _stableId(String input) {
    final String digest = sha256.convert(utf8.encode(input)).toString();
    final int value = int.parse(digest.substring(0, 13), radix: 16);
    // Stay in JavaScript's exact integer range for CommonSqlite3 on web.
    return value < 2 ? value + 2 : value;
  }

  // Parse before decoding entities so literal subtitle text such as "<3" or
  // "<word>" survives, while generated layout tags become readable line breaks.
  String _plainText(String value) {
    String render(dom.Node node) {
      if (node is dom.Text) return node.data;
      if (node is dom.Element) {
        if (<String>{'script', 'style', 'template'}.contains(node.localName)) {
          return '';
        }
        if (node.localName == 'br') return '\n';
        final String content = node.nodes.map(render).join();
        if (<String>{'div', 'p', 'li', 'section'}.contains(node.localName)) {
          return '\n$content\n';
        }
        return content;
      }
      return node.nodes.map(render).join();
    }

    return render(html.parseFragment(value))
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _quoteDelimitedField(String value) =>
      '"${value.replaceAll('"', '""')}"';

  void _createSchema(CommonDatabase database) {
    database.execute('''
      CREATE TABLE col (
        id INTEGER PRIMARY KEY,
        crt INTEGER NOT NULL,
        mod INTEGER NOT NULL,
        scm INTEGER NOT NULL,
        ver INTEGER NOT NULL,
        dty INTEGER NOT NULL,
        usn INTEGER NOT NULL,
        ls INTEGER NOT NULL,
        conf TEXT NOT NULL,
        models TEXT NOT NULL,
        decks TEXT NOT NULL,
        dconf TEXT NOT NULL,
        tags TEXT NOT NULL
      );
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY,
        guid TEXT NOT NULL,
        mid INTEGER NOT NULL,
        mod INTEGER NOT NULL,
        usn INTEGER NOT NULL,
        tags TEXT NOT NULL,
        flds TEXT NOT NULL,
        sfld INTEGER NOT NULL,
        csum INTEGER NOT NULL,
        flags INTEGER NOT NULL,
        data TEXT NOT NULL
      );
      CREATE TABLE cards (
        id INTEGER PRIMARY KEY,
        nid INTEGER NOT NULL,
        did INTEGER NOT NULL,
        ord INTEGER NOT NULL,
        mod INTEGER NOT NULL,
        usn INTEGER NOT NULL,
        type INTEGER NOT NULL,
        queue INTEGER NOT NULL,
        due INTEGER NOT NULL,
        ivl INTEGER NOT NULL,
        factor INTEGER NOT NULL,
        reps INTEGER NOT NULL,
        lapses INTEGER NOT NULL,
        left INTEGER NOT NULL,
        odue INTEGER NOT NULL,
        odid INTEGER NOT NULL,
        flags INTEGER NOT NULL,
        data TEXT NOT NULL
      );
      CREATE TABLE revlog (
        id INTEGER PRIMARY KEY,
        cid INTEGER NOT NULL,
        usn INTEGER NOT NULL,
        ease INTEGER NOT NULL,
        ivl INTEGER NOT NULL,
        lastIvl INTEGER NOT NULL,
        factor INTEGER NOT NULL,
        time INTEGER NOT NULL,
        type INTEGER NOT NULL
      );
      CREATE TABLE graves (
        usn INTEGER NOT NULL,
        oid INTEGER NOT NULL,
        type INTEGER NOT NULL
      );
      CREATE INDEX ix_notes_usn ON notes (usn);
      CREATE INDEX ix_cards_usn ON cards (usn);
      CREATE INDEX ix_revlog_usn ON revlog (usn);
      CREATE INDEX ix_cards_nid ON cards (nid);
      CREATE INDEX ix_cards_sched ON cards (did, queue, due);
      CREATE INDEX ix_revlog_cid ON revlog (cid);
      CREATE INDEX ix_notes_csum ON notes (csum);
    ''');
  }

  void _insertCollection(
    CommonDatabase database, {
    required String deckName,
    required int deckId,
    required int modelId,
    required int modifiedSeconds,
    required int modifiedMillis,
    required int nextPosition,
  }) {
    final Map<String, Object?> model = <String, Object?>{
      'css': _cardCss,
      'did': deckId,
      'flds': <Map<String, Object?>>[
        for (int index = 0; index < AnkiExportNote.fieldNames.length; index++)
          <String, Object?>{
            'name': AnkiExportNote.fieldNames[index],
            'ord': index,
            'sticky': false,
            'rtl': false,
            'font': 'Arial',
            'size': 20,
            'media': <Object?>[],
          },
      ],
      'id': '$modelId',
      'latexPost': r'\end{document}',
      'latexPre':
          r'\documentclass[12pt]{article}'
          '\n'
          r'\usepackage[utf8]{inputenc}'
          '\n'
          r'\begin{document}',
      'latexsvg': false,
      'mod': modifiedSeconds,
      'name': _modelName,
      'req': <Object?>[
        <Object?>[
          0,
          'all',
          <int>[0],
        ],
      ],
      'sortf': 0,
      'tags': <Object?>[],
      'tmpls': <Map<String, Object?>>[
        <String, Object?>{
          'name': 'Card 1',
          'ord': 0,
          'qfmt': _questionTemplate,
          'afmt': _answerTemplate,
          'bqfmt': '',
          'bafmt': '',
          'bfont': '',
          'bsize': 0,
          'did': null,
        },
      ],
      'type': 0,
      'usn': -1,
      'vers': <Object?>[],
    };

    final Map<String, Object?> decks = <String, Object?>{
      if (deckId != 1)
        '1': _deckJson(id: 1, name: 'Default', modifiedSeconds: 0),
      '$deckId': _deckJson(
        id: deckId,
        name: deckName,
        modifiedSeconds: modifiedSeconds,
      ),
    };

    final Map<String, Object?> collectionConfig = <String, Object?>{
      'activeDecks': <int>[deckId],
      'addToCur': true,
      'collapseTime': 1200,
      'curDeck': deckId,
      'curModel': '$modelId',
      'dueCounts': true,
      'estTimes': true,
      'newBury': true,
      'newSpread': 0,
      'nextPos': nextPosition,
      'sortBackwards': false,
      'sortType': 'noteFld',
      'timeLim': 0,
    };

    database.execute(
      'INSERT INTO col VALUES (NULL, ?, ?, ?, 11, 0, 0, 0, ?, ?, ?, ?, ?)',
      <Object?>[
        modifiedSeconds,
        modifiedMillis,
        modifiedMillis,
        jsonEncode(collectionConfig),
        jsonEncode(<String, Object?>{'$modelId': model}),
        jsonEncode(decks),
        jsonEncode(_defaultDeckConfig),
        '{}',
      ],
    );
  }

  Map<String, Object?> _deckJson({
    required int id,
    required String name,
    required int modifiedSeconds,
  }) => <String, Object?>{
    'id': id,
    'name': name,
    'desc': '',
    'mod': modifiedSeconds,
    'usn': -1,
    'dyn': 0,
    'collapsed': false,
    'browserCollapsed': false,
    'conf': 1,
    'extendNew': 10,
    'extendRev': 50,
    'newToday': <int>[0, 0],
    'revToday': <int>[0, 0],
    'lrnToday': <int>[0, 0],
    'timeToday': <int>[0, 0],
  };

  void _insertNotes(
    CommonDatabase database, {
    required List<AnkiExportNote> notes,
    required int deckId,
    required int modelId,
    required int modifiedSeconds,
  }) {
    final CommonPreparedStatement noteInsert = database.prepare(
      'INSERT INTO notes VALUES (?, ?, ?, ?, -1, ?, ?, ?, 0, 0, ?)',
    );
    final CommonPreparedStatement cardInsert = database.prepare(
      'INSERT INTO cards VALUES (?, ?, ?, 0, ?, -1, 0, 0, ?, 0, 0, 0, 0, 0, 0, 0, 0, ?)',
    );
    try {
      for (int index = 0; index < notes.length; index++) {
        final AnkiExportNote note = notes[index];
        final String identity = _sourceIdentity(note);
        final int noteId = _stableId('note|$identity');
        final int cardId = _stableId('card|$identity|0');
        final String fields = note.fields
            .map(_escapeFieldSeparator)
            .join(_fieldSeparator);
        noteInsert.execute(<Object?>[
          noteId,
          _guidFor(note),
          modelId,
          modifiedSeconds,
          ' $_tag ',
          fields,
          note.fields.first,
          '',
        ]);
        cardInsert.execute(<Object?>[
          cardId,
          noteId,
          deckId,
          modifiedSeconds,
          index,
          '',
        ]);
      }
    } finally {
      noteInsert.close();
      cardInsert.close();
    }
  }

  String _escapeFieldSeparator(String value) =>
      value.replaceAll(_fieldSeparator, '&#31;');

  Uint8List _zipPackage(Uint8List collection) {
    final Archive archive = Archive()
      ..addFile(ArchiveFile.bytes('collection.anki2', collection))
      ..addFile(ArchiveFile.string('media', '{}'));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static const String _questionTemplate =
      '''
<div class="se-card">
  <div class="se-expression">{{Expression}}</div>
  {{#Phonetic}}<div class="se-phonetic">{{Phonetic}}</div>{{/Phonetic}}
  <div class="se-audio se-native-audio" hidden>{{tts en_US:Expression}}</div>
  <button type="button" class="se-browser-audio" aria-label="朗读英文" hidden>▶ 朗读</button>
  <div class="se-speech-status" role="status" hidden></div>
</div>
$_speechScript
''';

  // FrontSide does not replay front-side audio on the answer. Render the same
  // header explicitly so each side has its own native TTS replay control.
  static const String _answerTemplate =
      '''
$_questionTemplate
<hr id="answer">
<div class="se-card se-answer">
  <div class="se-section-label">Meaning</div>
  <div class="se-meaning">{{Meaning}}</div>
  <div class="se-context">{{Context}}</div>
</div>
''';

  // Only fixed code belongs in this script. Card text is read from the DOM,
  // never interpolated into JavaScript or sent to an external speech service.
  static const String _speechScript = '''
<script>
(function () {
  document.querySelectorAll('.se-card').forEach(function (card) {
    var nativeAudio = card.querySelector('.se-native-audio');
    var button = card.querySelector('.se-browser-audio');
    var status = card.querySelector('.se-speech-status');
    if (!nativeAudio || !button || card.dataset.seSpeechReady) return;
    card.dataset.seSpeechReady = 'true';
    if (nativeAudio.querySelector('a, button, audio')) {
      nativeAudio.hidden = false;
      return;
    }
    function message(text) {
      status.textContent = text;
      status.hidden = !text;
    }
    if (!window.speechSynthesis || !window.SpeechSynthesisUtterance) {
      message('当前客户端不支持实时朗读。');
      return;
    }
    var speech = window.speechSynthesis;
    speech.getVoices();
    button.hidden = false;
    var active;
    button.addEventListener('click', function () {
      var text = card.querySelector('.se-expression').textContent.trim();
      if (!text) return;
      var voices = speech.getVoices().filter(function (voice) {
        return voice.localService && /^en[-_]/i.test(voice.lang);
      });
      var voice = voices.find(function (item) {
        return item.lang.replace('_', '-').toLowerCase() === 'en-us';
      }) || voices[0];
      if (!voice) {
        message('请启用设备上的英语语音后重试。');
        return;
      }
      var utterance = new SpeechSynthesisUtterance(text);
      utterance.voice = voice;
      utterance.lang = voice.lang;
      utterance.rate = 1;
      active = utterance;
      utterance.onstart = function () {
        if (active === utterance) message('正在朗读…');
      };
      utterance.onend = function () {
        if (active === utterance) message('已朗读');
      };
      utterance.onerror = function () {
        if (active === utterance) message('朗读失败，请检查设备英语语音。');
      };
      speech.cancel();
      speech.speak(utterance);
    });
  });
})();
</script>
''';

  static const String _cardCss = '''
.card {
  box-sizing: border-box;
  margin: 0;
  padding: 24px 18px;
  background: #f7f8fb;
  color: #222936;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Arial, sans-serif;
  font-size: 18px;
  text-align: left;
}
.se-card {
  box-sizing: border-box;
  width: 100%;
  max-width: 720px;
  margin: 0 auto;
  overflow-wrap: anywhere;
  word-break: break-word;
}
.se-kind, .se-section-label {
  color: #687286;
  font-size: 12px;
  font-weight: 700;
  letter-spacing: .09em;
  line-height: 1.4;
  text-transform: uppercase;
}
.se-expression {
  margin: 18px 0 10px;
  font-size: clamp(30px, 6vw, 46px);
  font-weight: 700;
  line-height: 1.2;
}
.se-phonetic { color: #7b8494; font-size: 16px; line-height: 1.5; }
.se-card [hidden] { display: none !important; }
.se-audio { margin-top: 12px; }
.se-browser-audio {
  margin-top: 12px;
  padding: 8px 14px;
  border: 1px solid #dce0e8;
  border-radius: 8px;
  background: transparent;
  color: inherit;
  font: inherit;
  cursor: pointer;
}
.se-browser-audio:focus-visible { outline: 2px solid #0f7a43; outline-offset: 3px; }
.se-speech-status { margin-top: 8px; font-size: 13px; color: #687286; }
.se-audio .replay-button svg { width: 36px; height: 36px; }
#answer { max-width: 720px; margin: 24px auto; border: 0; border-top: 1px solid #dce0e8; }
.se-answer { line-height: 1.65; }
.se-meaning { margin-top: 6px; font-size: 20px; line-height: 1.5; }
.se-context { margin-top: 22px; color: #495365; line-height: 1.75; }
.nightMode .card, .card.nightMode {
  background: #171a21;
  color: #edf0f7;
}
.nightMode .se-kind, .nightMode .se-section-label,
.card.nightMode .se-kind, .card.nightMode .se-section-label { color: #aab4c7; }
.nightMode .se-phonetic, .card.nightMode .se-phonetic { color: #adb7c8; }
.nightMode .se-context, .card.nightMode .se-context { color: #c7ceda; }
.nightMode #answer, .card.nightMode #answer { border-color: #3c4350; }
@media (max-width: 480px) {
  .card { padding: 18px 14px; font-size: 17px; }
  .se-expression { font-size: 32px; }
}
''';

  static const Map<String, Object?> _defaultDeckConfig = <String, Object?>{
    '1': <String, Object?>{
      'autoplay': true,
      'id': 1,
      'lapse': <String, Object?>{
        'delays': <int>[10],
        'leechAction': 0,
        'leechFails': 8,
        'minInt': 1,
        'mult': 0,
      },
      'maxTaken': 60,
      'mod': 0,
      'name': 'Default',
      'new': <String, Object?>{
        'bury': true,
        'delays': <int>[1, 10],
        'initialFactor': 2500,
        'ints': <int>[1, 4, 7],
        'order': 1,
      },
      'rev': <String, Object?>{
        'bury': true,
        'ease4': 1.3,
        'ivlFct': 1.0,
        'maxIvl': 36500,
        'perDay': 200,
      },
      'timer': 0,
      'replayq': true,
      'usn': 0,
    },
  };
}
