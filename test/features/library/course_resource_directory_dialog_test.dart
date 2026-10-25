import 'dart:io';

import 'package:common_learn_english/features/library/presentation/course_directory_relink.dart';
import 'package:common_learn_english/features/library/presentation/library_catalog_provider.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:common_learn_english/features/library/presentation/library_screen.dart';
import 'package:common_learn_english/features/library/presentation/widgets/course_resource_directory_dialog.dart';
import 'package:common_learn_english/features/player/presentation/asr_subtitle_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'course_directory_relink_test.dart' as fixtures;

class _Catalog extends LibraryCatalogNotifier {
  _Catalog(this.course);
  final LibraryCourseData course;
  @override
  List<LibraryCourseData> build() => <LibraryCourseData>[course];
  @override
  Future<void> relinkDirectory({
    required CourseDirectoryRelinkPlan plan,
    required Map<String, String> selections,
    required Set<String> addedVideoPaths,
    AsrSubtitleCache subtitleCache = const AsrSubtitleCache(),
  }) => super.relinkDirectory(
    plan: plan,
    selections: selections,
    addedVideoPaths: addedVideoPaths,
    subtitleCache: const _NoCache(),
  );
}

class _NoCache extends AsrSubtitleCache {
  const _NoCache();
  @override
  Future<void> relinkVideo({
    required String episodeId,
    required String oldPath,
    required String newPath,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final String captureDirectory =
      Platform.environment['SHADOWING_CAPTURE_DIR'] ?? '';
  setUpAll(() async {
    if (captureDirectory.isEmpty) return;
    final String fontPath = Platform.environment['SHADOWING_CAPTURE_FONT']!;
    final FontLoader font = FontLoader('Evidence')
      ..addFont(
        Future<ByteData>.value(
          ByteData.sublistView(File(fontPath).readAsBytesSync()),
        ),
      );
    await font.load();
    final FontLoader icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final Size size in <Size>[const Size(1200, 900), const Size(390, 844)]) {
    testWidgets(
      'view directories, preview, cancel and confirm at $size',
      (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final Directory temp = Directory.systemTemp.createTempSync(
          'resource-dialog-',
        );
        addTearDown(() => temp.deleteSync(recursive: true));
        File('${temp.path}/Peppa.S01E01.mp4').writeAsStringSync('video');
        final LibraryCourseData original = fixtures
            .courseWith(<LibraryEpisodeItem>[
              fixtures.episode('one', '/old/Peppa.S01E01.mp4'),
              fixtures.episode('two', '/old/Peppa.S01E02.mp4'),
            ]);
        final ProviderContainer container = ProviderContainer(
          // ignore: always_specify_types
          overrides: [
            libraryCatalogProvider.overrideWith(() => _Catalog(original)),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: captureDirectory.isEmpty
                  ? null
                  : ThemeData(
                      fontFamily: 'Evidence',
                      colorScheme: ColorScheme.fromSeed(
                        seedColor: const Color(0xFF0875D8),
                        primary: const Color(0xFF0875D8),
                        surface: Colors.white,
                      ),
                    ),
              home: Builder(
                builder: (BuildContext context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (BuildContext context) =>
                          CourseResourceDirectoryDialog(
                            courseId: original.id,
                            pickDirectory: () async => temp.path,
                            scanDirectory:
                                ({
                                  required LibraryCourseData course,
                                  required String oldRoot,
                                  required String newRoot,
                                  required bool subtitlesOnly,
                                }) async => buildCourseDirectoryRelinkPlan(
                                  course: course,
                                  oldRoot: oldRoot,
                                  newRoot: newRoot,
                                  subtitlesOnly: subtitlesOnly,
                                  videoFiles: <String>[
                                    '${temp.path}/Peppa.S01E01.mp4',
                                    '${temp.path}/Peppa.S01E03.mp4',
                                  ],
                                  subtitleFiles: <String>[],
                                ),
                          ),
                    ),
                    child: const Text('打开目录'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开目录'));
        await tester.pumpAndSettle();
        expect(find.text('/old'), findsOneWidget);
        expect(find.text('字幕目录'), findsOneWidget);
        if (captureDirectory.isNotEmpty) {
          await expectLater(
            find.byType(AlertDialog),
            matchesGoldenFile(
              Uri.file(
                '$captureDirectory/directories-${size.width.toInt()}.png',
              ),
            ),
          );
        }
        await tester.tap(find.text('重新关联目录'));
        await tester.pumpAndSettle();
        expect(find.text('确认重新关联'), findsOneWidget);
        expect(find.text('未关联 1 个文件；新增 1 个视频'), findsOneWidget);
        expect(
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
          isFalse,
        );
        expect(container.read(libraryCatalogProvider).single, same(original));
        if (captureDirectory.isNotEmpty) {
          await expectLater(
            find.byType(AlertDialog),
            matchesGoldenFile(
              Uri.file(
                '$captureDirectory/relink-preview-${size.width.toInt()}.png',
              ),
            ),
          );
        }
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(container.read(libraryCatalogProvider).single, same(original));
        await tester.tap(find.text('打开目录'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('重新关联目录'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认更新'));
        await tester.pumpAndSettle();
        final LibraryCourseData updated = container
            .read(libraryCatalogProvider)
            .single;
        expect(updated.episodes.first.id, 'one');
        expect(
          updated.episodes.first.videoAsset,
          '${temp.path}/Peppa.S01E01.mp4',
        );
        expect(updated.episodes.last.videoMissing, isTrue);
        expect(updated.episodes.length, 2);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'course list and detail expose resource directories',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1366, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final LibraryCourseData original = fixtures.courseWith(
        <LibraryEpisodeItem>[fixtures.episode('one', '/old/ep01.mp4')],
      );
      await tester.pumpWidget(
        ProviderScope(
          // ignore: always_specify_types
          overrides: [
            libraryCatalogProvider.overrideWith(() => _Catalog(original)),
          ],
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('资源目录'));
      await tester.pumpAndSettle();
      expect(find.text('/old'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('小猪佩奇').last);
      await tester.pumpAndSettle();
      expect(find.text('资源目录'), findsOneWidget);
      await tester.tap(find.text('资源目录'));
      await tester.pumpAndSettle();
      expect(find.text('/old'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
