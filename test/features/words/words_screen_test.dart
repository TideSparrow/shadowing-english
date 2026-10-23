import 'package:common_learn_english/features/words/data/offline_word_dictionary.dart';
import 'package:common_learn_english/features/words/presentation/word_book_provider.dart';
import 'package:common_learn_english/features/words/presentation/word_detail_screen.dart';
import 'package:common_learn_english/features/words/presentation/words_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class TestWords extends WordBookNotifier {
  @override
  List<WordEntry> build() => const <WordEntry>[
    WordEntry(
      word: 'apple',
      favorite: false,
      definitionCn: '苹果',
      occurrences: <WordOccurrence>[],
    ),
    WordEntry(
      word: 'apricot',
      favorite: true,
      definitionCn: '杏',
      occurrences: <WordOccurrence>[],
    ),
  ];

  @override
  void refreshOfflineDefinitions() {}
}

class TestDictionary extends OfflineWordDictionary {
  @override
  Future<OfflineWordDefinition?> lookup(String rawWord) async => null;
}

Finder wordLabel(String word) => find.byWidgetPredicate(
  (Widget widget) => widget is Text && widget.data == word,
);

void main() {
  for (final Size size in <Size>[const Size(390, 844), const Size(1366, 900)]) {
    testWidgets('word tabs preserve search and update favorites at $size', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ProviderContainer container = ProviderContainer(
        // ignore: always_specify_types
        overrides: [
          wordBookProvider.overrideWith(TestWords.new),
          offlineWordDictionaryProvider.overrideWithValue(TestDictionary()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: WordsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(wordLabel('apple'), findsNothing);
      expect(wordLabel('apricot'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('words-view-tabs'))).width,
        tester.getSize(find.byType(TextField)).width,
      );
      expect(
        tester.getCenter(find.text('已收藏')).dx,
        lessThan(tester.getCenter(find.text('全部单词')).dx),
      );
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      expect(find.text('查看详情'), findsOneWidget);
      expect(find.text('编辑'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      await tester.tap(find.text('查看详情'));
      await tester.pumpAndSettle();
      expect(find.text('单词详情'), findsOneWidget);
      expect(
        tester.widget<WordDetailDialog>(find.byType(WordDetailDialog)).word,
        'apricot',
      );
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部单词'));
      await tester.pumpAndSettle();
      expect(wordLabel('apple'), findsOneWidget);
      expect(wordLabel('apricot'), findsOneWidget);
      expect(find.text('仅收藏'), findsNothing);
      await tester.tap(find.text('已收藏'));
      await tester.pumpAndSettle();
      expect(wordLabel('apple'), findsNothing);
      expect(wordLabel('apricot'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'apple');
      await tester.pumpAndSettle();
      expect(find.text('没有找到匹配的单词，换个关键词试试。'), findsOneWidget);
      await tester.tap(find.text('全部单词'));
      await tester.pumpAndSettle();
      expect(wordLabel('apple'), findsOneWidget);
      expect(wordLabel('apricot'), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      await tester.tap(find.text('已收藏'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('取消收藏'));
      await tester.pumpAndSettle();
      expect(find.text('还没有收藏单词，点击单词旁的收藏图标就能加入。'), findsOneWidget);
      expect(container.read(wordBookProvider), hasLength(2));
      expect(
        container
            .read(wordBookProvider)
            .every((WordEntry item) => !item.favorite),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
