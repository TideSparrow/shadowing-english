import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:common_learn_english/features/lessons/data/lesson_service.dart';
import 'package:common_learn_english/features/lessons/data/lesson_store.dart';
import 'package:common_learn_english/features/lessons/domain/intensive_lesson.dart';
import 'package:common_learn_english/features/lessons/domain/lesson_summary.dart';
import 'package:common_learn_english/features/lessons/presentation/lesson_card_view.dart';
import 'package:common_learn_english/features/lessons/presentation/lesson_dialog.dart';
import 'package:common_learn_english/features/lessons/presentation/lesson_narrator.dart';
import 'package:common_learn_english/features/lessons/presentation/lesson_preview_card.dart';
import 'package:common_learn_english/features/lessons/presentation/lessons_screen.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:common_learn_english/features/shared/data/word_pronunciation_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:riverpod/src/framework.dart' show Override;

import 'lesson_fixture.dart';

class _Settings extends LearningSettingsNotifier {
  @override
  LearningSettingsState build() => LearningSettingsState.defaults().copyWith(
    translationProvider: 'OpenAI',
    translationApiKey: 'test-only',
    translationModel: 'test',
  );
}

class _Service extends LessonService {
  int requests = 0;
  CancelToken? token;
  Completer<IntensiveLesson>? pending;
  @override
  Future<IntensiveLesson> generate({
    required LessonSource source,
    required LearningSettingsState settings,
    required CancelToken cancelToken,
  }) async {
    requests++;
    token = cancelToken;
    return pending == null
        ? fixtureLesson(
            source: source,
            usage: const LessonTokenUsage(input: 123, output: 45, total: 168),
          )
        : pending!.future;
  }
}

class _Store extends LessonStore {
  _Store(super.box);
  @override
  Future<void> delete(String id) async {
    items = items.where((IntensiveLesson item) => item.id != id).toList();
  }

  int detailReads = 0;
  bool failSave = false;
  List<IntensiveLesson> items = <IntensiveLesson>[];
  @override
  Future<List<LessonSummary>> loadSummaries() async =>
      items.map(LessonSummary.fromLesson).toList();
  @override
  Future<IntensiveLesson?> find(String id) async {
    detailReads++;
    for (final IntensiveLesson lesson in items) {
      if (lesson.id == id) return lesson;
    }
    return null;
  }

  @override
  Future<Uint8List?> image(String id) async => null;
  @override
  Future<void> save(IntensiveLesson lesson) async {
    if (failSave) throw const FileSystemException('test write failure');
    items = <IntensiveLesson>[
      lesson,
      ...items.where((IntensiveLesson item) => item.id != lesson.id),
    ];
  }
}

class _RateClient extends WordPronunciationTtsClient {
  final List<double> rates = <double>[];
  final Completer<void> first = Completer<void>();

  @override
  Future<void> speakText(
    String text, {
    String language = 'en-US',
    String engine = '',
    String voice = '',
    double rate = 0.75,
    Duration speechTimeout = const Duration(seconds: 8),
  }) async {
    rates.add(rate);
    if (rates.length == 1) await first.future;
  }

  @override
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LazyBox<String> box;
  late _Store store;
  late _Service service;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lesson-flow-test-');
    Hive.init(directory.path);
    box = await Hive.openLazyBox<String>('lesson-flow-test');
    store = _Store(box);
    service = _Service();
  });
  tearDown(() async {
    await box.close();
    await directory.delete(recursive: true);
  });

  Future<void> host(
    WidgetTester tester, {
    bool configured = false,
    bool saved = false,
    Size size = const Size(1280, 900),
    double scale = 1,
    WordPronunciationService? voice,
    Widget? screen,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (saved) await tester.runAsync(() => store.save(fixtureLesson()));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          lessonStoreProvider.overrideWith((Ref ref) async => store),
          lessonServiceProvider.overrideWithValue(service),
          if (configured) learningSettingsProvider.overrideWith(_Settings.new),
          wordPronunciationServiceProvider.overrideWithValue(
            voice ??
                WordPronunciationService(
                  speakOverride: (_) async {},
                  stopOverride: () async {},
                ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(
            fontFamily: 'Nunito',
            fontFamilyFallback: const <String>['LessonCJK'],
          ),
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: RepaintBoundary(
                key: const Key('capture'),
                child: Builder(
                  builder: (BuildContext context) =>
                      screen ??
                      Center(
                        child: FilledButton(
                          onPressed: () =>
                              showLessonDialog(context, source: lessonSource),
                          child: const Text('打开精讲'),
                        ),
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (screen == null) await tester.tap(find.text('打开精讲'));
    await settle(tester);
  }

  testWidgets('without AI no request is sent', (WidgetTester tester) async {
    await host(tester);
    expect(find.text('配置 AI'), findsOneWidget);
    expect(service.requests, 0);
    expect(await tester.runAsync(store.loadSummaries), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'generation saves all cards and reopening works with AI disabled',
    (WidgetTester tester) async {
      await host(tester, configured: true);
      expect(service.requests, 1);
      expect(find.textContaining('输入 123 · 输出 45 · 总计 168'), findsOneWidget);
      expect(await tester.runAsync(store.loadSummaries), hasLength(1));
      expect(find.textContaining('已自动保存'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭精讲'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开精讲'));
      await settle(tester);
      expect(service.requests, 1);
      expect(
        find.descendant(
          of: find.byType(LessonDialog),
          matching: find.text('get them'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'bundled art stays stable during interaction and differs between cards',
    (WidgetTester tester) async {
      await host(tester, saved: true);
      String artwork() => tester
          .widget<LessonCardView>(find.byType(LessonCardView))
          .decorationAsset;
      final String first = artwork();
      expect(lessonIllustrationAssets, contains(first));
      expect(find.textContaining('生成插画'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, '表达拆解'));
      await tester.pumpAndSettle();
      expect(artwork(), isNot(first));
      expect(lessonIllustrationAssets, contains(artwork()));
      await tester.tap(find.widgetWithText(ChoiceChip, '场景理解'));
      await tester.pumpAndSettle();
      expect(artwork(), first);
      final Text pattern = tester.widget<Text>(
        find.byKey(const Key('lesson-pattern-meaning')),
      );
      expect(pattern.textSpan!.toPlainText(), 'get someone  可以表示：去叫某人／把某人找来');
      expect(service.requests, 0);
    },
  );

  testWidgets(
    'a write failure retains the generated card and retries saving only',
    (WidgetTester tester) async {
      store.failSave = true;
      await host(tester, configured: true);
      expect(service.requests, 1);
      expect(find.text('重试保存'), findsOneWidget);
      store.failSave = false;
      await tester.tap(find.text('重试保存'));
      await settle(tester);
      expect(await tester.runAsync(store.loadSummaries), hasLength(1));
      expect(service.requests, 1);
      expect(find.textContaining('已自动保存'), findsOneWidget);
    },
  );

  testWidgets('closing cancels an outstanding request', (
    WidgetTester tester,
  ) async {
    service.pending = Completer<IntensiveLesson>();
    await host(tester, configured: true);
    expect(service.requests, 1);
    await tester.tap(find.byTooltip('关闭精讲'));
    await tester.pumpAndSettle();
    expect(service.token!.isCancelled, true);
    service.pending!.complete(fixtureLesson());
    await settle(tester);
    expect(await tester.runAsync(store.loadSummaries), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saved lessons open without AI and all three layouts fit small screens',
    (WidgetTester tester) async {
      await host(tester, saved: true, size: const Size(390, 844), scale: 1.3);
      expect(service.requests, 0);
      expect(find.text('配置 AI'), findsNothing);
      expect(find.textContaining('接口未返回用量'), findsOneWidget);
      for (final LessonCardKind kind in LessonCardKind.values) {
        await tester.tap(find.widgetWithText(ChoiceChip, kind.label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: kind.name);
      }
      final Rect bounds = tester.getRect(
        find.byKey(const Key('lesson-dialog-surface')),
      );
      expect(bounds.width, lessThan(390));
      expect(bounds.height, lessThan(844));
    },
  );

  testWidgets(
    'speech rate follows global settings and can change during narration',
    (WidgetTester tester) async {
      final _RateClient client = _RateClient();
      await host(
        tester,
        saved: true,
        voice: WordPronunciationService(ttsClient: client),
      );
      expect(find.text('跟随系统（0.75×）'), findsOneWidget);
      await tester.tap(find.byKey(const Key('lesson-speak')));
      await tester.pumpAndSettle();
      expect(client.rates, <double>[0.75]);
      await tester.tap(find.byKey(const Key('lesson-speech-rate')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('0.5×').last);
      await tester.pumpAndSettle();
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(LessonDialog)),
      );
      expect(container.read(learningSettingsProvider).ttsRate, 0.75);
      client.first.complete();
      await tester.pumpAndSettle();
      expect(client.rates, hasLength(20));
      expect(client.rates.skip(1), everyElement(0.5));

      container.read(learningSettingsProvider.notifier).setTtsRate(1.25);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lesson-speech-rate')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('跟随系统（1.25×）').last);
      await tester.pumpAndSettle();
      client.rates.clear();
      await tester.tap(find.byKey(const Key('lesson-speak')));
      await tester.pumpAndSettle();
      expect(client.rates, isNotEmpty);
      expect(client.rates, everyElement(1.25));
      expect(service.requests, 0);
    },
  );

  testWidgets('speech advances cards and closing stops the remaining script', (
    WidgetTester tester,
  ) async {
    final List<String> texts = <String>[];
    final Completer<void> firstSpeech = Completer<void>();
    int stops = 0;
    final WordPronunciationService voice = WordPronunciationService(
      speakOverride: (String text) async {
        texts.add(text);
        await firstSpeech.future;
      },
      stopOverride: () async {
        stops++;
      },
    );
    await host(tester, saved: true, voice: voice);
    await tester.tap(find.byKey(const Key('lesson-speak')));
    await tester.pump();
    expect(texts, hasLength(1));
    await tester.tap(find.byTooltip('关闭精讲'));
    await tester.pumpAndSettle();
    firstSpeech.complete();
    await tester.pump();
    expect(stops, greaterThanOrEqualTo(2));
    expect(texts, hasLength(1));
  });

  testWidgets(
    'global lesson library searches, reopens offline, and deletes saved cards',
    (WidgetTester tester) async {
      await host(tester, saved: true, screen: const LessonsScreen());
      expect(find.text(lessonSource.english), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'no-match');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('没有找到匹配的精讲'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(find.text(lessonSource.english));
      await settle(tester);
      expect(
        find.descendant(
          of: find.byType(LessonDialog),
          matching: find.text('get them'),
        ),
        findsOneWidget,
      );
      expect(service.requests, 0);
      await tester.tap(find.byTooltip('关闭精讲'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('删除精讲'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await settle(tester);
      expect(find.text('从一句没听懂的台词开始'), findsOneWidget);
      expect(store.items, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'card and list modes paginate, search all pages, and reset filters',
    (WidgetTester tester) async {
      store.items = List<IntensiveLesson>.generate(
        53,
        (int index) =>
            numberedLesson(index, course: index < 27 ? '基础口语' : '日常对话'),
      );
      await host(tester, screen: const LessonsScreen());
      expect(find.byType(SliverGrid), findsOneWidget);
      expect(
        tester
            .widget<SegmentedButton<bool>>(
              find.byKey(const Key('lesson-view-mode')),
            )
            .selected,
        <bool>{true},
      );
      int cardCount() =>
          (tester.widget<SliverGrid>(find.byType(SliverGrid)).delegate
                  as SliverChildBuilderDelegate)
              .childCount!;
      expect(cardCount(), 24);
      expect(store.detailReads, 0);
      await tester.tap(find.byKey(const Key('lesson-top-next')));
      await tester.pumpAndSettle();
      expect(find.text('Example sentence 24.'), findsOneWidget);
      await tester.tap(find.text('列表'));
      await tester.pumpAndSettle();
      expect(find.byType(LessonPreviewCard), findsNothing);
      expect(find.text('Example sentence 24.'), findsOneWidget);
      await tester.tap(find.text('卡片'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lesson-top-next')));
      await tester.pumpAndSettle();
      expect(cardCount(), 5);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('lesson-top-next')))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byKey(const Key('lesson-search')), 'needle');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(cardCount(), 1);
      expect(
        find.text('A searchable needle on the last page.'),
        findsOneWidget,
      );
      expect(find.byType(LessonPagination), findsNothing);
      expect(store.detailReads, 0);
      await tester.enterText(find.byKey(const Key('lesson-search')), '');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '基础口语'));
      await tester.pumpAndSettle();
      expect(find.text('共 27 组精讲'), findsOneWidget);
      expect(cardCount(), 24);
      await tester.tap(find.byKey(const Key('lesson-top-next')));
      await tester.pumpAndSettle();
      expect(cardCount(), 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('deleting the last item on a page returns to a valid page', (
    WidgetTester tester,
  ) async {
    store.items = List<IntensiveLesson>.generate(25, numberedLesson);
    await host(tester, screen: const LessonsScreen());
    await tester.tap(find.byKey(const Key('lesson-top-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除精讲'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await settle(tester);
    expect(find.text('共 24 组精讲'), findsOneWidget);
    expect(find.byType(LessonPagination), findsNothing);
    expect(find.text('Example sentence 0.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card and list modes fit narrow screens with larger text', (
    WidgetTester tester,
  ) async {
    store.items = List<IntensiveLesson>.generate(26, numberedLesson);
    await host(
      tester,
      screen: const LessonsScreen(),
      size: const Size(390, 844),
      scale: 1.3,
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('列表'));
    await tester.tap(find.text('列表'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test(
    'narrator reads all segments in order and changes card indexes',
    () async {
      final List<String> texts = <String>[];
      final List<int> cards = <int>[];
      final LessonNarrator narrator = LessonNarrator(
        service: WordPronunciationService(
          speakOverride: (String text) async => texts.add(text),
          stopOverride: () async {},
        ),
      );
      await narrator.play(
        lesson: fixtureLesson(),
        fromCard: 0,
        onSegment: (int card, int segment) => cards.add(card),
      );
      expect(texts, hasLength(20));
      expect(cards, containsAllInOrder(<int>[0, 1, 2]));
    },
  );

  testWidgets('visual captures show desktop and phone card layouts', (
    WidgetTester tester,
  ) async {
    // ignore: do_not_use_environment
    if (!const bool.fromEnvironment('LESSON_CAPTURE')) return;
    final FontLoader font = FontLoader('Nunito')
      ..addFont(rootBundle.load('assets/fonts/Nunito-Regular.ttf'));
    await font.load();
    final File chinese = File('/System/Library/Fonts/STHeiti Medium.ttc');
    if (chinese.existsSync()) {
      final FontLoader cjk = FontLoader('LessonCJK')
        ..addFont(
          Future<ByteData>.value(
            ByteData.sublistView(chinese.readAsBytesSync()),
          ),
        );
      await cjk.load();
    }
    final File icons = File(
      '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      final FontLoader iconFont = FontLoader('MaterialIcons')
        ..addFont(
          Future<ByteData>.value(ByteData.sublistView(icons.readAsBytesSync())),
        );
      await iconFont.load();
    }
    await host(tester, saved: true);
    for (final LessonCardKind kind in LessonCardKind.values) {
      await tester.tap(find.widgetWithText(ChoiceChip, kind.label));
      await tester.pumpAndSettle();
      await capture(tester, 'desktop-${kind.name}');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await host(tester, saved: true, size: const Size(390, 844));
    await capture(tester, 'phone-scene');
    expect(tester.takeException(), isNull);
  });
}

Future<void> settle(WidgetTester tester) async {
  // Hive uses real file I/O; let it finish outside the fake animation clock.
  for (int i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  final Finder dialogBoundary = find.ancestor(
    of: find.byType(LessonDialog),
    matching: find.byType(RepaintBoundary),
  );
  final RenderRepaintBoundary target = tester
      .renderObject<RenderRepaintBoundary>(dialogBoundary.first);
  await tester.runAsync(() async {
    final ui.Image image = await target.toImage();
    final ByteData data = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!;
    final Directory output = Directory('/tmp/shadowing-lesson-preview')
      ..createSync(recursive: true);
    await File(
      '${output.path}/$name.png',
    ).writeAsBytes(data.buffer.asUint8List());
    image.dispose();
  });
}
