import 'dart:convert';
import 'dart:ui' as ui;

import 'package:common_learn_english/features/library/presentation/library_catalog_provider.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:common_learn_english/features/player/presentation/player_screen.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestCatalog extends LibraryCatalogNotifier {
  @override
  List<LibraryCourseData> build() => const <LibraryCourseData>[
    LibraryCourseData(
      id: 'test-course',
      title: '测试课程',
      description: '',
      sourceLabel: '测试',
      coverImage: '',
      level: 'B1',
      category: '测试',
      progressPercent: 0,
      totalWords: 0,
      completedEpisodes: 0,
      totalEpisodes: 1,
      lastStudiedStr: '',
      rating: 0,
      episodes: <LibraryEpisodeItem>[
        LibraryEpisodeItem(
          id: 'intern-ep3',
          numberStr: '03',
          title: '测试剧集',
          durationMinutes: 20,
          hasChineseSubtitles: true,
          hasEnglishSubtitles: true,
          completed: false,
          progressPercent: 0,
          coverImage: '',
          enSubtitleAsset: 'assets/test/accessibility.words.json',
          cnSubtitleAsset: 'assets/test/accessibility.words.json',
        ),
      ],
    ),
  ];
}

// Inspect the actual updates sent to the engine. A widget semantics tree alone
// does not expose detached nodes serialized by an OverlayPortal during a route
// transition, which can crash the desktop accessibility bridge.
class _RecordingBinding extends AutomatedTestWidgetsFlutterBinding {
  final Map<int, List<int>> nodes = <int, List<int>>{};
  final Set<int> orphanNodes = <int>{};

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _RecordingBuilder(super.createSemanticsUpdateBuilder(), this);

  void record(Map<int, List<int>> update) {
    nodes.addAll(update);
    final Set<int> reachable = <int>{};
    void visit(int id) {
      if (!reachable.add(id)) return;
      (nodes[id] ?? const <int>[]).forEach(visit);
    }

    visit(0);
    orphanNodes.addAll(update.keys.where((int id) => !reachable.contains(id)));
    nodes.removeWhere((int id, List<int> _) => !reachable.contains(id));
  }
}

class _RecordingBuilder implements ui.SemanticsUpdateBuilder {
  _RecordingBuilder(this.delegate, this.binding);

  final ui.SemanticsUpdateBuilder delegate;
  final _RecordingBinding binding;
  final Map<int, List<int>> nodes = <int, List<int>>{};

  // Forward the SDK's full updateNode signature unchanged, including flags and
  // actions, while recording only the edges needed to validate reachability.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      nodes[invocation.namedArguments[#id]! as int] = List<int>.of(
        invocation.namedArguments[#childrenInTraversalOrder]! as List<int>,
      );
      return Function.apply(
        delegate.updateNode,
        const <dynamic>[],
        invocation.namedArguments,
      );
    }
    return super.noSuchMethod(invocation);
  }

  @override
  void updateCustomAction({
    required int id,
    String? label,
    String? hint,
    int overrideId = -1,
  }) => delegate.updateCustomAction(
    id: id,
    label: label,
    hint: hint,
    overrideId: overrideId,
  );

  @override
  ui.SemanticsUpdate build() {
    binding.record(nodes);
    return delegate.build();
  }
}

void main() {
  final _RecordingBinding binding = _RecordingBinding();

  testWidgets('player route and subtitle changes send no orphan semantics', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    final String subtitles = jsonEncode(<String, Object?>{
      'version': 1,
      'lines': List<Map<String, Object?>>.generate(
        418,
        (int index) => <String, Object?>{
          'startMs': index * 2000,
          'endMs': index * 2000 + 1000,
          'english': 'Sentence $index.',
          'chinese': '第 $index 句。',
        },
      ),
    });
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          ..setMockMessageHandler('flutter/assets', (ByteData? message) async {
            final String key = utf8.decode(message!.buffer.asUint8List());
            return key == 'assets/test/accessibility.words.json'
                ? ByteData.sublistView(utf8.encode(subtitles))
                : null;
          });
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));

    await tester.pumpWidget(
      ProviderScope(
        // ignore: always_specify_types
        overrides: [libraryCatalogProvider.overrideWith(_TestCatalog.new)],
        child: MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
            body: FilledButton(
              onPressed: () => navigator.currentState!.push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const PlayerScreen(episodeId: 'intern-ep3'),
                ),
              ),
              child: const Text('打开播放器'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开播放器'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpAndSettle();
    expect(binding.orphanNodes, isEmpty);

    for (final String mode in <String>['隐藏', '双语', '单英', '单中', '双语']) {
      await tester.tap(find.byTooltip('字幕模式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(mode).last, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(
        ProviderScope.containerOf(
          tester.element(find.byType(PlayerScreen)),
        ).read(learningSettingsProvider).subtitleMode,
        mode,
      );
    }

    expect(find.byType(Slider), findsOneWidget);
    expect(binding.orphanNodes, isEmpty);
    expect(tester.takeException(), isNull);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(binding.orphanNodes, isEmpty);
  });
}
