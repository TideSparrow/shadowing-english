import 'dart:typed_data';

import 'package:common_learn_english/features/anki_export/data/anki_export_builder.dart';
import 'package:common_learn_english/features/anki_export/data/anki_export_service.dart';
import 'package:common_learn_english/features/anki_export/domain/anki_export_note.dart';
import 'package:common_learn_english/features/anki_export/presentation/anki_export_sheet.dart';
import 'package:common_learn_english/features/phrases/presentation/phrase_book_provider.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:common_learn_english/features/words/data/offline_word_dictionary.dart';
import 'package:common_learn_english/features/words/presentation/word_book_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/src/framework.dart';

class Words extends WordBookNotifier {
  @override
  List<WordEntry> build() => const <WordEntry>[
    WordEntry(word: 'saved', favorite: true, occurrences: <WordOccurrence>[]),
    WordEntry(
      word: 'unsaved',
      favorite: false,
      occurrences: <WordOccurrence>[],
    ),
  ];
}

class EmptyWords extends Words {
  @override
  List<WordEntry> build() => <WordEntry>[];
}

class Phrases extends PhraseBookNotifier {
  @override
  List<PhraseEntry> build() => <PhraseEntry>[];
}

class Exporter extends AnkiExportService {
  Exporter() : super(AnkiExportBuilder(OfflineWordDictionary()));
  bool fail = false;
  int calls = 0;
  String? lastLetterCase;
  @override
  Future<AnkiExportFile> generate({
    required List<WordEntry> words,
    required List<PhraseEntry> phrases,
    required AnkiExportFormat format,
    required String deckName,
    String subtitleLetterCase = '保留原样',
  }) async {
    calls++;
    lastLetterCase = subtitleLetterCase;
    expect(words.map((WordEntry w) => w.word), <String>['saved']);
    expect(format, AnkiExportFormat.apkg);
    if (fail) throw StateError('test');
    return AnkiExportFile(
      bytes: Uint8List(0),
      name: 'test.apkg',
      mimeType: 'application/octet-stream',
      noteCount: 1,
    );
  }
}

class Saver extends AnkiExportSaver {
  AnkiSaveResult result = AnkiSaveResult.cancelled;
  @override
  Future<AnkiSaveResult> save(
    AnkiExportFile file, {
    required Rect origin,
  }) async => result;
}

void main() {
  Future<ProviderContainer> mount(
    WidgetTester tester,
    Exporter exporter,
    Saver saver, {
    bool empty = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        wordBookProvider.overrideWith(empty ? EmptyWords.new : Words.new),
        phraseBookProvider.overrideWith(Phrases.new),
        ankiExportServiceProvider.overrideWithValue(exporter),
        ankiExportSaverProvider.overrideWithValue(saver),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () => showAnkiExportSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('default package, favorites snapshot, cancellation and retry', (
    WidgetTester tester,
  ) async {
    final Exporter exporter = Exporter();
    final Saver saver = Saver();
    await mount(tester, exporter, saver);
    expect(find.text('收藏单词 · 1'), findsOneWidget);
    await tester.ensureVisible(find.text('导出文件'));
    await tester.tap(find.text('导出文件'));
    await tester.pumpAndSettle();
    expect(find.byType(AnkiExportSheet), findsOneWidget);
    exporter.fail = true;
    await tester.tap(find.text('导出文件'));
    await tester.pumpAndSettle();
    expect(find.text('导出未完成，请重试或改用 TSV 格式。'), findsOneWidget);
    exporter.fail = false;
    saver.result = AnkiSaveResult.saved;
    await tester.ensureVisible(find.text('导出文件'));
    await tester.tap(find.text('导出文件'));
    await tester.pumpAndSettle();
    expect(find.byType(AnkiExportSheet), findsNothing);
    expect(find.text('已导出 1 张卡片，请在 Anki 中导入文件。'), findsOneWidget);
    expect(exporter.calls, 3);
    expect(tester.takeException(), isNull);
  });
  testWidgets('export reads the latest letter-case setting when clicked', (
    WidgetTester tester,
  ) async {
    final Exporter exporter = Exporter();
    final ProviderContainer container = await mount(tester, exporter, Saver());
    container
        .read(learningSettingsProvider.notifier)
        .setSubtitleLetterCase('全部大写');
    await tester.pumpAndSettle();
    expect(find.textContaining('大小写：全部大写'), findsOneWidget);
    container
        .read(learningSettingsProvider.notifier)
        .setSubtitleLetterCase('全部小写');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('导出文件'));
    await tester.tap(find.text('导出文件'));
    await tester.pumpAndSettle();
    expect(exporter.lastLetterCase, '全部小写');
    container
        .read(learningSettingsProvider.notifier)
        .setSubtitleLetterCase('句首字母大写');
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出文件'));
    await tester.pumpAndSettle();
    expect(exporter.lastLetterCase, '句首字母大写');
  });

  testWidgets('empty collection disables export', (WidgetTester tester) async {
    await mount(tester, Exporter(), Saver(), empty: true);
    final FilledButton button = tester.widget<FilledButton>(
      find.byType(FilledButton),
    );
    expect(button.onPressed, isNull);
    expect(find.text('还没有收藏内容，先去收藏单词或短语吧。'), findsOneWidget);
  });
}
