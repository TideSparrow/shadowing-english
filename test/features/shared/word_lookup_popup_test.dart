import 'dart:async';

import 'package:common_learn_english/features/phrases/presentation/phrase_book_provider.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/widgets/player_subtitle_list.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:common_learn_english/features/shared/data/word_lookup_service.dart';
import 'package:common_learn_english/features/shared/data/word_pronunciation_service.dart';
import 'package:common_learn_english/features/shared/domain/word_lookup_entry.dart';
import 'package:common_learn_english/features/shared/presentation/word_lookup_popup.dart';
import 'package:common_learn_english/features/words/data/offline_word_dictionary.dart';
import 'package:common_learn_english/features/words/presentation/word_book_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'all primary actions stay visible while long definitions scroll',
    (WidgetTester tester) async {
      final ProviderContainer container = _container();
      addTearDown(container.dispose);
      await tester.pumpWidget(_popup(container));
      await tester.pumpAndSettle();

      final Finder favorite = find.byTooltip('收藏单词');
      expect(find.text('收藏单词'), findsNothing);
      expect(find.text('加入短语库'), findsNothing);
      expect(find.text('播放发音'), findsNothing);
      expect(favorite.hitTestable(), findsOneWidget);
      expect(
        tester.getTopLeft(favorite).dy,
        lessThan(tester.getTopLeft(find.text('中文义项')).dy),
      );
      final Offset headerPosition = tester.getTopLeft(favorite);
      final Offset collectPosition = tester.getTopLeft(find.byTooltip('加入短语库'));
      final Offset playPosition = tester.getTopLeft(find.byTooltip('播放发音'));
      expect(find.byTooltip('加入短语库').hitTestable(), findsOneWidget);
      expect(find.byTooltip('播放发音').hitTestable(), findsOneWidget);
      expect(
        collectPosition.dy,
        lessThan(tester.getTopLeft(find.text('中文义项')).dy),
      );

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -1000),
      );
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(favorite), headerPosition);
      expect(favorite.hitTestable(), findsOneWidget);
      expect(find.byTooltip('加入短语库').hitTestable(), findsOneWidget);
      expect(find.byTooltip('播放发音').hitTestable(), findsOneWidget);
      expect(tester.getTopLeft(find.byTooltip('加入短语库')), collectPosition);
      expect(tester.getTopLeft(find.byTooltip('播放发音')), playPosition);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saved state follows word book and survives reopening', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = _container();
    addTearDown(container.dispose);
    await tester.pumpWidget(_popup(container, rawWord: 'Sanctuary,'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('收藏单词'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('取消收藏'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton).first).onPressed,
      isNotNull,
    );
    final WordEntry entry = container.read(wordBookProvider).single;
    expect(entry.favorite, isTrue);
    expect(entry.occurrences.single.sentence, 'They found a sanctuary nearby.');

    await tester.pumpWidget(
      _popup(
        container,
        key: const ValueKey<String>('reopen'),
        rawWord: 'Sanctuary,',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('取消收藏'), findsOneWidget);

    await tester.tap(find.byTooltip('取消收藏'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('收藏单词'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    expect(container.read(wordBookProvider).single.favorite, isFalse);
    expect(container.read(wordBookProvider).single.occurrences, hasLength(1));

    await tester.tap(find.byTooltip('收藏单词'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('取消收藏'), findsOneWidget);
    expect(container.read(wordBookProvider).single.favorite, isTrue);

    container.read(wordBookProvider.notifier).toggleFavorite('sanctuary');
    await tester.pumpAndSettle();
    expect(find.byTooltip('收藏单词'), findsOneWidget);
  });

  testWidgets('lookup without a favorite action keeps existing controls', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = _container();
    addTearDown(container.dispose);
    await tester.pumpWidget(_popup(container, canFavorite: false));
    await tester.pumpAndSettle();

    expect(find.byTooltip('收藏单词'), findsNothing);
    expect(find.byTooltip('取消收藏'), findsNothing);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('加入短语库').hitTestable(), findsOneWidget);
    expect(find.byTooltip('播放发音').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phrase state remains visible and follows saved data on reopen', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = _container();
    addTearDown(container.dispose);
    await tester.pumpWidget(_popup(container));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('加入短语库'));
    await tester.pumpAndSettle();

    expect(find.byType(WordLookupPopupCard), findsOneWidget);
    expect(find.byTooltip('从短语库移除'), findsOneWidget);
    expect(find.byIcon(Icons.library_add_check), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton).at(1)).onPressed,
      isNotNull,
    );
    expect(container.read(phraseBookProvider), hasLength(1));

    await tester.pumpWidget(
      _popup(container, key: const ValueKey<String>('reopen')),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('从短语库移除'), findsOneWidget);

    await tester.tap(find.byTooltip('从短语库移除'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('加入短语库'), findsOneWidget);
    expect(find.byIcon(Icons.library_add_outlined), findsOneWidget);
    expect(container.read(phraseBookProvider), isEmpty);

    await tester.tap(find.byTooltip('加入短语库'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('从短语库移除'), findsOneWidget);
    expect(container.read(phraseBookProvider), hasLength(1));

    container
        .read(phraseBookProvider.notifier)
        .deletePhrase(container.read(phraseBookProvider).single.id);
    await tester.pumpAndSettle();
    expect(find.byTooltip('加入短语库'), findsOneWidget);
  });

  testWidgets('phrase state distinguishes episode and subtitle time', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = _container();
    addTearDown(container.dispose);
    container.read(phraseBookProvider.notifier)
      ..addPhrase(
        english: 'They found a sanctuary nearby.',
        chinese: '',
        course: '课程',
        episode: '第 2 集',
        episodeId: 'episode-2',
        time: '00:10',
      )
      ..addPhrase(
        english: 'They found a sanctuary nearby.',
        chinese: '',
        course: '课程',
        episode: '第 1 集',
        episodeId: 'episode-1',
        time: '00:20',
      );
    await tester.pumpWidget(_popup(container));
    await tester.pumpAndSettle();
    expect(find.byTooltip('加入短语库'), findsOneWidget);

    await tester.tap(find.byTooltip('加入短语库'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('从短语库移除'), findsOneWidget);
    expect(container.read(phraseBookProvider), hasLength(3));
  });

  testWidgets('pronunciation has a visible playing state until completion', (
    WidgetTester tester,
  ) async {
    final Completer<void> playback = Completer<void>();
    final ProviderContainer container = ProviderContainer(
      // ignore: always_specify_types
      overrides: [
        wordLookupServiceProvider.overrideWith((Ref ref) => _LookupService()),
        wordPronunciationServiceProvider.overrideWith(
          (Ref ref) => WordPronunciationService(
            speakOverride: (String text) => playback.future,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_popup(container));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('播放发音'));
    await tester.pump();

    expect(find.byTooltip('播放中...'), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton).at(2)).onPressed,
      isNull,
    );

    playback.complete();
    await tester.pumpAndSettle();
    expect(find.byTooltip('播放发音'), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsNothing);
  });

  testWidgets('popup supports the wider layout', (WidgetTester tester) async {
    final ProviderContainer container = _container();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      _popup(container, width: WordLookupPopupCard.preferredWidth),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(WordLookupPopupCard)).width,
      WordLookupPopupCard.preferredWidth,
    );
    expect(find.byTooltip('收藏单词').hitTestable(), findsOneWidget);
    expect(find.byTooltip('加入短语库').hitTestable(), findsOneWidget);
    expect(find.byTooltip('播放发音').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'collecting from another subtitle keeps the correct saved state',
    (WidgetTester tester) async {
      final ProviderContainer container = _container();
      addTearDown(container.dispose);
      String? collectedTime;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: PlayerSubtitleList(
                episodeId: 'episode-1',
                lines: const <PlayerSubtitleLine>[
                  PlayerSubtitleLine(
                    startTime: '00:01',
                    english: 'Hello there.',
                    chinese: '你好。',
                    startMs: 1000,
                    endMs: 2000,
                  ),
                  PlayerSubtitleLine(
                    startTime: '00:10',
                    english: 'They found a sanctuary nearby.',
                    chinese: '他们在附近找到了庇护所。',
                    startMs: 10000,
                    endMs: 12000,
                  ),
                ],
                activeIndex: 0,
                subtitleMode: '双语',
                currentWordIndex: 0,
                fontScale: 1,
                highlightWords: false,
                onTapLine: (_) {},
                onCollectWord: (_) => fail('Use the selected subtitle context'),
                onCollectWordAtTime: (String word, String time) {
                  collectedTime = time;
                  container
                      .read(phraseBookProvider.notifier)
                      .addPhraseIfMissing(
                        english: 'They found a sanctuary nearby.',
                        chinese: '',
                        course: '课程',
                        episode: '第 1 集',
                        episodeId: 'episode-1',
                        time: time,
                      );
                },
                onBookmarkLine: (_) {},
                onLoopFromLine: (_) {},
                onDictationLine: (_) {},
                onAiExplain: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('sanctuary'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('加入短语库'));
      await tester.pumpAndSettle();

      expect(collectedTime, '00:10');
      expect(find.byType(WordLookupPopupCard), findsOneWidget);
      expect(find.byTooltip('从短语库移除'), findsOneWidget);

      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('sanctuary'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('从短语库移除'), findsOneWidget);
    },
  );
}

ProviderContainer _container() => ProviderContainer(
  // ignore: always_specify_types
  overrides: [
    wordLookupServiceProvider.overrideWith((Ref ref) => _LookupService()),
    offlineWordDictionaryProvider.overrideWith((Ref ref) => _Dictionary()),
  ],
);

Widget _popup(
  ProviderContainer container, {
  Key? key,
  bool canFavorite = true,
  double width = 300,
  String rawWord = 'Sanctuary',
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: WordLookupPopupCard(
            key: key,
            rawWord: rawWord,
            contextSentence: 'They found a sanctuary nearby.',
            episodeId: 'episode-1',
            contextTime: '00:10',
            maxHeight: 320,
            onClose: () {},
            onCollect: () => container
                .read(phraseBookProvider.notifier)
                .addPhraseIfMissing(
                  english: 'They found a sanctuary nearby.',
                  chinese: '他们在附近找到了庇护所。',
                  course: '课程',
                  episode: '第 1 集',
                  episodeId: 'episode-1',
                  time: '00:10',
                ),
            onFavorite: !canFavorite
                ? null
                : () => container
                      .read(wordBookProvider.notifier)
                      .addFavoriteWord(
                        rawWord: rawWord,
                        episodeId: 'episode-1',
                        course: '课程',
                        episode: '第 1 集',
                        time: '00:10',
                        lineKey: '10-12',
                        sentence: 'They found a sanctuary nearby.',
                        chinese: '他们在附近找到了庇护所。',
                      ),
          ),
        ),
      ),
    ),
  ),
);

class _LookupService extends WordLookupService {
  @override
  Future<WordLookupEntry> lookupWord({
    required String rawWord,
    String? contextSentence,
    required LearningSettingsState settings,
  }) async => WordLookupEntry(
    word: rawWord,
    phonetic: '/test/',
    type: 'noun',
    definitionEn: List<String>.filled(20, 'A place of safety.').join(' '),
    usageEn: 'Used to describe a safe place.',
    exampleSentenceEn: 'The island became a sanctuary.',
    definitionCn: '避难所；圣所；庇护所',
    sourceLabel: '测试',
  );
}

class _Dictionary extends OfflineWordDictionary {
  @override
  Future<OfflineWordDefinition?> lookup(String rawWord) async => null;
}
