import 'package:common_learn_english/features/anki_export/data/anki_export_builder.dart';
import 'package:common_learn_english/features/anki_export/domain/anki_export_note.dart';
import 'package:common_learn_english/features/phrases/presentation/phrase_book_provider.dart';
import 'package:common_learn_english/features/words/data/offline_word_dictionary.dart';
import 'package:common_learn_english/features/words/presentation/word_book_provider.dart';
import 'package:flutter_test/flutter_test.dart';

class Dictionary extends OfflineWordDictionary {
  @override
  Future<OfflineWordDefinition?> lookup(String rawWord) async =>
      const OfflineWordDefinition(
        translation: '词典释义',
        phonetic: '/wɜːd/',
        partOfSpeech: 'n.',
      );
}

PhraseEntry phrase(String id, String time) => PhraseEntry(
  id: id,
  english: 'Keep going.',
  chinese: '继续。',
  course: '课程',
  episode: '第二集',
  time: time,
  rating: 1,
  needsReview: true,
  today: false,
);

void main() {
  test(
    'exports favorites only, dictionary phonetics and all distinct safe contexts',
    () async {
      const WordContext context = WordContext(
        lineKey: '1',
        time: '00:01',
        sentence: '<script>alert(1)</script> & "word"\nnext',
        chinese: '原翻译',
        apiTranslationCn: '新翻译',
        count: 1,
      );
      final List<AnkiExportNote> notes = await AnkiExportBuilder(Dictionary()).build(
        words: const <WordEntry>[
          WordEntry(
            word: 'word',
            favorite: true,
            definitionCn: '自定义\n释义',
            occurrences: <WordOccurrence>[
              WordOccurrence(
                episodeId: 'e1',
                course: '课程',
                episode: '第一集',
                time: '00:01',
                sentence: 'fallback',
                chinese: '',
                count: 2,
                lineKeys: <String>['1'],
                contexts: <WordContext>[
                  context,
                  context,
                  WordContext(
                    lineKey: '2',
                    time: '00:02',
                    sentence: 'Another word.',
                    chinese: '另一句',
                    count: 1,
                  ),
                ],
              ),
            ],
          ),
          WordEntry(word: 'hidden', favorite: false, occurrences: <WordOccurrence>[]),
        ],
        phrases: <PhraseEntry>[],
      );
      expect(notes, hasLength(1));
      expect(notes.single.id, 'word:word');
      expect(notes.single.fields[1], '&#47;wɜːd&#47;');
      expect(notes.single.fields[2], '自定义<br>释义');
      expect(notes.single.fields[3], isNot(contains('<script>')));
      expect(notes.single.fields[3], contains('&lt;script&gt;'));
      expect(
        RegExp('class="example"').allMatches(notes.single.fields[3]),
        hasLength(2),
      );
      expect(notes.single.fields[3], contains('新翻译'));
      expect(notes.single.fields[3], contains('00:02'));
      expect(notes.single.fields[5], '课程 · 第一集');
    },
  );

  test(
    'identical phrases merge contexts with stable identity as new contexts arrive',
    () async {
      final AnkiExportBuilder builder = AnkiExportBuilder(Dictionary());
      final List<AnkiExportNote> first = await builder.build(
        words: <WordEntry>[],
        phrases: <PhraseEntry>[phrase('one', '00:01')],
      );
      final List<AnkiExportNote> next = await builder.build(
        words: <WordEntry>[],
        phrases: <PhraseEntry>[phrase('one', '00:01'), phrase('two', '00:02')],
      );
      expect(next, hasLength(1));
      expect(first.single.id, next.single.id);
      expect(next.single.fields[2], '继续。');
      expect(next.single.fields[3], contains('00:01'));
      expect(next.single.fields[3], contains('00:02'));
    },
  );

  test('uses legacy occurrence fallback and omits empty expressions', () async {
    final List<AnkiExportNote> notes = await AnkiExportBuilder(Dictionary()).build(
      words: const <WordEntry>[
        WordEntry(
          word: 'word',
          favorite: true,
          occurrences: <WordOccurrence>[
            WordOccurrence(
              episodeId: 'e',
              course: '课程',
              episode: '',
              time: '01:00',
              sentence: 'Legacy sentence',
              chinese: '旧语境',
              count: 1,
              lineKeys: <String>[],
              contexts: <WordContext>[],
            ),
          ],
        ),
        WordEntry(word: '', favorite: true, occurrences: <WordOccurrence>[]),
      ],
      phrases: <PhraseEntry>[],
    );
    expect(notes, hasLength(1));
    expect(notes.single.fields[2], '词典释义');
    expect(notes.single.fields[3], contains('Legacy sentence'));
  });
}
