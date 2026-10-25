import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../import_course/presentation/import_course_screen.dart';
import '../../import_course/presentation/widgets/import_course_flow.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../player/presentation/asr_subtitle_cache.dart';
import '../../player/presentation/full_transcript_reader.dart';
import '../../player/presentation/learning_resume_provider.dart';
import '../../player/presentation/player_course_lookup.dart';
import '../../player/presentation/player_mock_state.dart';
import '../../player/presentation/player_subtitle_loader.dart';
import '../../player/presentation/transcript_reader_session.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/data/word_lookup_service.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_compact.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../../words/data/offline_word_dictionary.dart';
import 'library_catalog_provider.dart';
import 'library_mock_data.dart';
import 'widgets/course_overview_card.dart';
import 'widgets/course_resource_directory_dialog.dart';
import 'widgets/episode_list_item.dart';
import 'widgets/library_course_card.dart';
import 'widgets/library_course_list_item.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({
    super.key,
    this.initialView = LibraryScreenView.list,
    this.initialCourseId,
    this.initialEpisodeId,
    this.pickCoverImage,
    this.openTranscriptReader,
  });

  final LibraryScreenView initialView;
  final String? initialCourseId;
  final String? initialEpisodeId;
  final Future<String?> Function()? pickCoverImage;
  final Future<void> Function(
    LibraryCourseData course,
    LibraryEpisodeItem episode,
  )? openTranscriptReader;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}
enum LibraryScreenView { list, detail, import }

enum LibraryCourseViewMode { grid, list }

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final TranscriptReaderSession transcriptReaderSession =
      TranscriptReaderSession();
  late bool showDetail;
  late bool showImport;
  final ImportCourseFlowController importFlowController =
      ImportCourseFlowController();
  late final TextEditingController queryController;
  late final ScrollController listScrollController;
  bool appliedInitialSelection = false;
  LibraryCourseViewMode viewMode = LibraryCourseViewMode.grid;
  String query = '';
  bool editMode = false;
  bool showScrollToTop = false;
  LibraryCourseData selectedCourse = emptyLibraryCourse;
  String selectedEpisodeId = '';
  String episodeSort = '自然排序';
  final Set<String> selectedCourseIds = <String>{};
  final Map<String, List<String>> customEpisodeOrders =
      <String, List<String>>{};

  @override
  void initState() {
    super.initState();
    showImport = widget.initialView == LibraryScreenView.import;
    showDetail = widget.initialView == LibraryScreenView.detail;
    queryController = TextEditingController()
      ..addListener(() {
        setState(() {});
      });
    listScrollController = ScrollController()
      ..addListener(() {
        final bool nextVisible = listScrollController.offset > 320;
        if (nextVisible != showScrollToTop) {
          setState(() {
            showScrollToTop = nextVisible;
          });
        }
      });
  }

  @override
  void dispose() {
    transcriptReaderSession.dispose();
    importFlowController.dispose();
    queryController.dispose();
    listScrollController.dispose();
    super.dispose();
  }

  Future<void> _openTranscriptReader(
    LibraryCourseData course,
    LibraryEpisodeItem episode,
  ) async {
    final Future<void> Function(LibraryCourseData, LibraryEpisodeItem)?
    override = widget.openTranscriptReader;
    if (override != null) {
      await override(course, episode);
      return;
    }

    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    final PlayerCourseLookupResult resource = resolvePlayerCourseForEpisode(
      courses: <LibraryCourseData>[course],
      episodeId: episode.id,
    );
    List<PlayerSubtitleLine> lines = const <PlayerSubtitleLine>[];
    Map<String, String> generatedMeanings = const <String, String>{};
    try {
      if ((resource.englishSubtitleAsset ?? '').isNotEmpty) {
        final List<PlayerSubtitleLine> englishLines = await loadSubtitleLines(
          resource.englishSubtitleAsset!,
        );
        final List<PlayerSubtitleLine> chineseLines =
            (resource.chineseSubtitleAsset ?? '').isEmpty
            ? const <PlayerSubtitleLine>[]
            : await loadSubtitleLines(resource.chineseSubtitleAsset!);
        lines = mergeSubtitleLines(
          englishLines: englishLines,
          chineseLines: chineseLines,
        );
      }
      if (lines.isEmpty && (resource.videoAsset ?? '').isNotEmpty) {
        final String? cached = await const AsrSubtitleCache().read(
          episodeId: episode.id,
          videoPath: resource.videoAsset!,
          settings: settings,
          validateReferenceSignature: false,
        );
        if (cached != null) {
          lines = parseSubtitleLines(cached);
          generatedMeanings = parseSubtitleGlossary(cached);
        }
      }
    } catch (_) {
      lines = const <PlayerSubtitleLine>[];
    }
    if (!mounted) return;
    if (lines.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前剧集没有可查看的全文字幕')));
      return;
    }

    final TranscriptReaderSnapshot snapshot =
        await buildTranscriptReaderSnapshot(
          courseTitle: course.title,
          episodeTitle: episode.title,
          lines: lines,
          activeLineIndex: 0,
          currentWordIndex: 0,
          generatedMeanings: generatedMeanings,
          dictionary: ref.read(offlineWordDictionaryProvider),
        );
    if (!mounted) return;
    final WordLookupService lookupService = ref.read(wordLookupServiceProvider);
    try {
      await transcriptReaderSession.open(
        context: context,
        snapshot: snapshot,
        lookupWord:
            ({required String rawWord, required String contextSentence}) =>
                lookupService.lookupWord(
                  rawWord: rawWord,
                  contextSentence: contextSentence,
                  settings: settings,
                ),
        translateSentence: (String sentence) => lookupService.translateSentence(
          sentence: sentence,
          settings: settings,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开全文，请稍后重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool compact = context.isPadCompact;
    final double pagePadding = context.padPagePadding;
    final List<LibraryCourseData> courses = ref.watch(libraryCatalogProvider);
    if (!appliedInitialSelection) {
      if (widget.initialCourseId != null) {
        for (final LibraryCourseData course in courses) {
          if (course.id == widget.initialCourseId) {
            selectedCourse = course;
            break;
          }
        }
      }
      if (widget.initialEpisodeId != null) {
        selectedEpisodeId = widget.initialEpisodeId!;
      }
      appliedInitialSelection = true;
    }
    final LibraryCourseData currentCourse = courses.firstWhere(
      (LibraryCourseData course) => course.id == selectedCourse.id,
      orElse: () => courses.isEmpty ? emptyLibraryCourse : courses.first,
    );
    selectedCourse = currentCourse;

    final List<LibraryCourseData> filteredCourses = courses
        .where((LibraryCourseData course) {
          final String keyword = query.trim().toLowerCase();
          if (keyword.isEmpty) {
            return true;
          }
          return course.title.toLowerCase().contains(keyword) ||
              course.description.toLowerCase().contains(keyword);
        })
        .toList(growable: false);
    selectedCourseIds.removeWhere(
      (String id) => !courses.any((LibraryCourseData course) => course.id == id),
    );
    final List<LibraryEpisodeItem> visibleEpisodes = _visibleEpisodes(
      selectedCourse,
    );
    final LibraryEpisodeItem? activeEpisode = visibleEpisodes.isEmpty
        ? null
        : visibleEpisodes.firstWhere(
            (LibraryEpisodeItem item) => item.id == selectedEpisodeId,
            orElse: () => visibleEpisodes.first,
          );

    final bool canContinueLearning =
        ref.watch(continueLearningTargetProvider) != null;
    return PadScaffold(
      showContinueLearning: !showDetail,
      currentDestination: AppNavDestination.library,
      topBar: PadTopBar(
        title: showImport
            ? '导入影视'
            : showDetail
            ? selectedCourse.title
            : '影视库',
        subtitle: showImport
            ? '影视库'
            : showDetail
            ? activeEpisode == null
                  ? '暂无剧集'
                  : '第 ${activeEpisode.numberStr} 集'
            : null,
        description: showImport
            ? '把本地视频和字幕整理成新的学习片库。'
            : showDetail
            ? null
            : '挑一部继续放映，去新的场景里练耳朵。',
        leading: showImport
            ? AnimatedBuilder(
                animation: importFlowController,
                builder: (BuildContext context, _) {
                  return Tooltip(
                    message: importFlowController.canGoBack ? '返回上一步' : '返回影视库',
                    child: TextButton(
                      onPressed: importFlowController.canGoBack
                          ? importFlowController.goBack
                          : () {
                              setState(() {
                                showImport = false;
                                showDetail = false;
                              });
                            },
                      style: TextButton.styleFrom(
                        backgroundColor: AppDesignTokens.appWhite,
                        foregroundColor: AppDesignTokens.brandGreenDark,
                        minimumSize: const Size(44, 44),
                        padding: EdgeInsets.zero,
                        side: const BorderSide(
                          color: AppDesignTokens.borderGray,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: const Icon(Icons.arrow_back_rounded, size: 18),
                    ),
                  );
                },
              )
            : showDetail
            ? Tooltip(
                message: '返回影视库',
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      showDetail = false;
                    });
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: AppDesignTokens.appWhite,
                    foregroundColor: AppDesignTokens.brandGreenDark,
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    side: const BorderSide(
                      color: AppDesignTokens.borderGray,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Icon(Icons.arrow_back_rounded, size: 18),
                ),
              )
            : null,
        trailing: showDetail
            ? _LibraryDetailTopStatus(
                courseMeta: '${selectedCourse.level} · ${selectedCourse.category}',
                episodeName: activeEpisode?.title,
              )
            : null,
      ),
      body: showImport
          ? ImportCourseFlow(
              controller: importFlowController,
              showHeader: false,
              onCancel: () {
                setState(() {
                  showImport = false;
                  showDetail = false;
                });
              },
              onImportCompleted: () {
                setState(() {
                  showImport = false;
                  showDetail = false;
                });
              },
            )
          : showDetail
          ? Stack(
              children: <Widget>[
                ListView(
                  padding: EdgeInsets.fromLTRB(
                    pagePadding,
                    compact ? 22 : 28,
                    pagePadding,
                    120,
                  ),
                  children: <Widget>[
                    CourseOverviewCard(
                      course: selectedCourse,
                      activeEpisode:
                          activeEpisode ??
                          const LibraryEpisodeItem(
                            id: '',
                            numberStr: '--',
                            title: '暂无可播放剧集',
                            durationMinutes: 0,
                            hasChineseSubtitles: false,
                            hasEnglishSubtitles: false,
                            completed: false,
                            progressPercent: 0,
                            coverImage: '',
                          ),
                      onPlayTap: activeEpisode == null
                          ? () {}
                          : () => context.pushNamed(
                              SGRoute.player.name,
                              pathParameters: <String, String>{
                                'episodeId': activeEpisode.id,
                              },
                            ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _showResourceDirectory(selectedCourse),
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('资源目录'),
                      ),
                    ),
                    SizedBox(height: compact ? 20 : 28),
                    Container(
                      padding: EdgeInsets.all(compact ? 18 : 20),
                      decoration: BoxDecoration(
                        color: AppDesignTokens.appWhite,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: AppDesignTokens.toyCardShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      '全部剧集',
                                      style: TextStyle(
                                        fontSize: compact ? 24 : 28,
                                        fontWeight: FontWeight.w900,
                                        color: AppDesignTokens.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '挑一集继续练耳朵，保留当前排序和重排能力。',
                                      style: TextStyle(
                                        fontSize: compact ? 13 : 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppDesignTokens.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: AppDesignTokens.pinkLight,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${visibleEpisodes.length} 集',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: AppDesignTokens.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: compact ? 14 : 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: <Widget>[
                              _EpisodeSortChip(
                                value: episodeSort,
                                onChanged: (String? value) {
                                  if (value == null) {
                                    return;
                                  }
                                  setState(() {
                                    episodeSort = value;
                                  });
                                },
                              ),
                              OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    episodeSort = '手动排序';
                                    customEpisodeOrders.putIfAbsent(
                                      selectedCourse.id,
                                      () => selectedCourse.episodes
                                          .map((LibraryEpisodeItem item) => item.id)
                                          .toList(growable: false),
                                    );
                                  });
                                },
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: AppDesignTokens.borderGray,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  backgroundColor: AppDesignTokens.softWhite,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.swap_vert_rounded,
                                  size: 18,
                                  color: AppDesignTokens.primaryBlueDark,
                                ),
                                label: const Text(
                                  '手动重排',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppDesignTokens.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: compact ? 14 : 18),
                          if (visibleEpisodes.isEmpty)
                            const _EmptyEpisodesState()
                          else if (episodeSort == '手动排序')
                            ReorderableListView.builder(
                              shrinkWrap: true,
                              buildDefaultDragHandles: false,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: visibleEpisodes.length,
                              onReorderItem: _handleReorderEpisodes,
                              itemBuilder: (BuildContext context, int index) {
                                final LibraryEpisodeItem item =
                                    visibleEpisodes[index];
                                return Padding(
                                  key: ValueKey<String>(item.id),
                                  padding: EdgeInsets.only(
                                    bottom: compact ? 12 : 16,
                                  ),
                                  child: EpisodeListItem(
                                    item: item,
                                    selected: item.id == selectedEpisodeId,
                                    onTap: () {
                                      setState(() {
                                        selectedEpisodeId = item.id;
                                      });
                                      context.pushNamed(
                                        SGRoute.player.name,
                                        pathParameters: <String, String>{
                                          'episodeId': item.id,
                                        },
                                      );
                                    },
                                    onViewTranscript: () =>
                                        _openTranscriptReader(
                                          selectedCourse,
                                          item,
                                        ),
                                    trailing: ReorderableDragStartListener(
                                      index: index,
                                      child: const Icon(
                                        Icons.drag_indicator_rounded,
                                        color: AppDesignTokens.textSecondary,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            )
                          else
                            ...List<Widget>.generate(visibleEpisodes.length, (
                              int index,
                            ) {
                              final LibraryEpisodeItem item =
                                  visibleEpisodes[index];
                              return Padding(
                                padding: EdgeInsets.only(
                                  bottom: compact ? 12 : 16,
                                ),
                                child: EpisodeListItem(
                                  item: item,
                                  selected: item.id == selectedEpisodeId,
                                  onTap: () {
                                    setState(() {
                                      selectedEpisodeId = item.id;
                                    });
                                    context.pushNamed(
                                      SGRoute.player.name,
                                      pathParameters: <String, String>{
                                        'episodeId': item.id,
                                      },
                                    );
                                  },
                                  onViewTranscript: () => _openTranscriptReader(
                                    selectedCourse,
                                    item,
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ],
                ),
                Positioned(
                  right: pagePadding,
                  bottom: compact ? 24 : 28,
                  child: FilledButton.icon(
                    onPressed: activeEpisode == null
                        ? null
                        : () => context.pushNamed(
                            SGRoute.player.name,
                            pathParameters: <String, String>{
                              'episodeId': activeEpisode.id,
                            },
                          ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppDesignTokens.brandGreen,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 18,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.play_circle_fill_rounded, size: 26),
                    label: Text(
                      activeEpisode == null
                          ? '暂无可播放剧集'
                          : '继续播放第 ${activeEpisode.numberStr} 集',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            )
          : LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double contentWidth = constraints.maxWidth - pagePadding * 2;
                final int gridColumns = contentWidth >= 900
                    ? 3
                    : contentWidth >= 560
                    ? 2
                    : 1;
                final double gridItemWidth =
                    (contentWidth - 20 * (gridColumns - 1)) / gridColumns;

                return Stack(
                  children: <Widget>[
                    ListView(
                  controller: listScrollController,
                  padding: EdgeInsets.all(pagePadding),
                  children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppDesignTokens.appWhite.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: AppDesignTokens.toyCardShadow,
                        ),
                        child: TextField(
                          controller: queryController,
                          onChanged: (String value) {
                            setState(() {
                              query = value;
                            });
                          },
                          onSubmitted: (_) => _applySearch(),
                          decoration: InputDecoration(
                            hintText: '搜索想继续看的内容...',
                            hintStyle: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppDesignTokens.textSecondary,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: AppDesignTokens.primaryBlueDark,
                            ),
                            filled: true,
                            fillColor: Colors.transparent,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 18,
                            ),
                            suffixIcon: queryController.text.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: _clearSearch,
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      color: AppDesignTokens.textSecondary,
                                    ),
                                    tooltip: '清空搜索',
                                  ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(999),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(999),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(999),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    _CourseViewModeToggle(
                      value: viewMode,
                      onChanged: (LibraryCourseViewMode nextValue) {
                        setState(() {
                          viewMode = nextValue;
                        });
                      },
                    ),
                    const SizedBox(width: 12),
                    if (editMode)
                      _LibraryEditToolbar(
                        selectedCount: selectedCourseIds.length,
                        onEdit: selectedCourseIds.isEmpty
                            ? null
                            : _showBatchEditDialog,
                        onDelete: selectedCourseIds.isEmpty
                            ? null
                            : _confirmDeleteSelectedCourses,
                        onDone: _exitEditMode,
                      )
                    else ...<Widget>[
                      FilledButton.tonal(
                        onPressed: filteredCourses.isEmpty ? null : _enterEditMode,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppDesignTokens.appWhite.withValues(
                            alpha: 0.92,
                          ),
                          foregroundColor: AppDesignTokens.primaryBlueDark,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 18,
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          '编辑',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    FilledButton.icon(
                      onPressed: editMode
                          ? null
                          : () {
                        openImportCourseExperience(context);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppDesignTokens.brandGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        elevation: 0,
                      ),
                      icon: const DecoratedBox(
                        decoration: BoxDecoration(
                          boxShadow: AppDesignTokens.toyButtonShadow,
                        ),
                        child: Icon(Icons.add_rounded, size: 18),
                      ),
                      label: const Text(
                        '导入新课程',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (filteredCourses.isEmpty)
                  _EmptyLibraryState(query: query)
                else if (viewMode == LibraryCourseViewMode.grid)
                  Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    children: filteredCourses
                        .map((LibraryCourseData course) {
                          return SizedBox(
                            width: gridItemWidth,
                            child: LibraryCourseCard(
                              course: course,
                              selected: selectedCourseIds.contains(course.id),
                              selectionMode: editMode,
                              onTap: () => _handleCourseTap(course),
                              onResourceDirectory: () => _showResourceDirectory(course),
                            ),
                          );
                        })
                        .toList(growable: false),
                  )
                else
                  Column(
                    children: filteredCourses
                        .map((LibraryCourseData course) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: LibraryCourseListItem(
                              course: course,
                              selected: selectedCourseIds.contains(course.id),
                              selectionMode: editMode,
                              onTap: () => _handleCourseTap(course),
                              onResourceDirectory: () => _showResourceDirectory(course),
                            ),
                          );
                        })
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 88),
                ],
              ),
                    if (showScrollToTop)
                      Positioned(
                        right: pagePadding,
                        bottom: canContinueLearning
                            ? (compact ? 96 : 100)
                            : (compact ? 24 : 28),
                        child: FloatingActionButton.small(
                          onPressed: () {
                            listScrollController.animateTo(
                              0,
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeOutCubic,
                            );
                          },
                          backgroundColor: AppDesignTokens.primaryBlue,
                          foregroundColor: AppDesignTokens.appWhite,
                          elevation: 6,
                          child: const Icon(Icons.keyboard_arrow_up_rounded),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }

  Future<void> _showResourceDirectory(LibraryCourseData course) async {
    final bool? updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) =>
          CourseResourceDirectoryDialog(courseId: course.id),
    );
    if ((updated ?? false) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('资源目录已更新，学习进度和生词已保留。')),
      );
    }
  }

  void _openCourse(LibraryCourseData course) {
    setState(() {
      selectedCourse = course;
      selectedEpisodeId = course.episodes.isEmpty ? '' : course.episodes.first.id;
      showDetail = true;
    });
  }

  void _handleCourseTap(LibraryCourseData course) {
    if (!editMode) {
      _openCourse(course);
      return;
    }
    setState(() {
      if (selectedCourseIds.contains(course.id)) {
        selectedCourseIds.remove(course.id);
      } else {
        selectedCourseIds.add(course.id);
      }
    });
  }

  void _enterEditMode() {
    setState(() {
      editMode = true;
      selectedCourseIds.clear();
    });
  }

  void _exitEditMode() {
    setState(() {
      editMode = false;
      selectedCourseIds.clear();
    });
  }

  Future<void> _showBatchEditDialog() async {
    final List<LibraryCourseData> selectedCourses = ref
        .read(libraryCatalogProvider)
        .where((LibraryCourseData course) => selectedCourseIds.contains(course.id))
        .toList(growable: false);
    if (selectedCourses.isEmpty) {
      return;
    }
    final bool single = selectedCourses.length == 1;
    final TextEditingController titleController = TextEditingController(
      text: single ? selectedCourses.first.title : '',
    );
    final String initialSource = selectedCourses
            .map((LibraryCourseData course) => course.sourceLabel)
            .toSet()
            .length ==
        1
        ? selectedCourses.first.sourceLabel
        : '';
    final TextEditingController sourceController = TextEditingController(
      text: initialSource,
    );
    String selectedCoverImage = single ? selectedCourses.first.coverImage : '';
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              backgroundColor: AppDesignTokens.appWhite,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              title: Text(single ? '编辑课程' : '批量编辑'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: '影视名',
                      hintText: single ? null : '留空则不修改',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: sourceController,
                    decoration: InputDecoration(
                      labelText: '来源',
                      hintText: initialSource.isEmpty ? '留空则不修改' : null,
                    ),
                  ),
                  if (single) ...<Widget>[
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: () async {
                          final String? coverImage = await _pickCoverImage();
                          if (coverImage == null || coverImage.isEmpty) {
                            return;
                          }
                          setDialogState(() {
                            selectedCoverImage = coverImage;
                          });
                        },
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('上传封面'),
                      ),
                    ),
                    if (selectedCoverImage.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          selectedCoverImage.split(RegExp(r'[\\/]')).last,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: AppDesignTokens.textSecondary,
                  ),
                  child: const Text(
                    '取消',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppDesignTokens.brandGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: const Text(
                    '保存',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (saved != true || !mounted) {
      return;
    }
    await ref.read(libraryCatalogProvider.notifier).updateCoursesMetadata(
      courseIds: selectedCourseIds,
      title: titleController.text,
      sourceLabel: sourceController.text,
      coverImage: single ? selectedCoverImage : null,
    );
    if (!mounted) {
      return;
    }
    _exitEditMode();
  }

  Future<String?> _pickCoverImage() async {
    if (widget.pickCoverImage != null) {
      return widget.pickCoverImage!();
    }
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'images',
          extensions: <String>['jpg', 'jpeg', 'png', 'webp'],
        ),
      ],
      confirmButtonText: '选择封面',
    );
    return file?.path;
  }

  Future<void> _confirmDeleteSelectedCourses() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppDesignTokens.appWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: const Text('删除已选课程'),
          content: Text('将删除 ${selectedCourseIds.length} 个已选课程。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: AppDesignTokens.textSecondary,
              ),
              child: const Text(
                '取消',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppDesignTokens.brandGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: const Text(
                '确认删除',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await ref.read(libraryCatalogProvider.notifier).deleteCourses(selectedCourseIds);
    if (!mounted) {
      return;
    }
    _exitEditMode();
  }

  List<LibraryEpisodeItem> _visibleEpisodes(LibraryCourseData course) {
    final List<LibraryEpisodeItem> episodes = List<LibraryEpisodeItem>.from(
      course.episodes,
    );
    switch (episodeSort) {
      case '最近学习':
        episodes.sort((LibraryEpisodeItem a, LibraryEpisodeItem b) {
          return _recentScore(b).compareTo(_recentScore(a));
        });
      case '学习进度':
        episodes.sort((LibraryEpisodeItem a, LibraryEpisodeItem b) {
          return b.progressPercent.compareTo(a.progressPercent);
        });
      case '手动排序':
        final List<String> order =
            customEpisodeOrders[course.id] ??
            course.episodes
                .map((LibraryEpisodeItem item) => item.id)
                .toList(growable: false);
        episodes.sort((LibraryEpisodeItem a, LibraryEpisodeItem b) {
          return order.indexOf(a.id).compareTo(order.indexOf(b.id));
        });
      default:
        episodes.sort((LibraryEpisodeItem a, LibraryEpisodeItem b) {
          return int.parse(a.numberStr).compareTo(int.parse(b.numberStr));
        });
    }
    return episodes;
  }

  int _recentScore(LibraryEpisodeItem item) {
    if (item.progressPercent > 0 && !item.completed) {
      return 300 + item.progressPercent;
    }
    if (item.completed) {
      return 200 + item.progressPercent;
    }
    return item.progressPercent;
  }

  void _handleReorderEpisodes(int oldIndex, int newIndex) {
    final int targetIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final List<String> order = List<String>.from(
      customEpisodeOrders[selectedCourse.id] ??
          selectedCourse.episodes
              .map((LibraryEpisodeItem item) => item.id)
              .toList(growable: false),
    );
    final String item = order.removeAt(oldIndex);
    order.insert(targetIndex, item);
    setState(() {
      customEpisodeOrders[selectedCourse.id] = order;
      episodeSort = '手动排序';
    });
  }

  void _applySearch() {
    setState(() {
      query = queryController.text;
    });
  }

  void _clearSearch() {
    queryController.clear();
    setState(() {
      query = '';
    });
  }
}

class _EmptyLibraryState extends StatelessWidget {
  const _EmptyLibraryState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final bool hasQuery = query.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppDesignTokens.borderGray),
        boxShadow: AppDesignTokens.toyCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            hasQuery ? '没有找到匹配课程' : '还没有导入任何课程',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            hasQuery
                ? '换个关键词试试，或者直接导入你自己的视频和字幕资源。'
                : '先导入你自己的视频和字幕资源，再开始精听。',
            style: const TextStyle(
              fontSize: 14,
              height: 1.55,
              color: AppDesignTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseViewModeToggle extends StatelessWidget {
  const _CourseViewModeToggle({
    required this.value,
    required this.onChanged,
  });

  final LibraryCourseViewMode value;
  final ValueChanged<LibraryCourseViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        boxShadow: AppDesignTokens.toyCardShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _CourseViewModeButton(
            icon: Icons.grid_view_rounded,
            selected: value == LibraryCourseViewMode.grid,
            onTap: () => onChanged(LibraryCourseViewMode.grid),
          ),
          const SizedBox(width: 6),
          _CourseViewModeButton(
            icon: Icons.view_agenda_rounded,
            selected: value == LibraryCourseViewMode.list,
            onTap: () => onChanged(LibraryCourseViewMode.list),
          ),
        ],
      ),
    );
  }
}

class _CourseViewModeButton extends StatelessWidget {
  const _CourseViewModeButton({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: selected ? AppDesignTokens.brandGreen : AppDesignTokens.skyLight,
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected ? AppDesignTokens.toyButtonShadow : null,
        ),
        child: Icon(
          icon,
          size: 20,
          color: selected
              ? AppDesignTokens.appWhite
              : AppDesignTokens.primaryBlueDark,
        ),
      ),
    );
  }
}

class _LibraryEditToolbar extends StatelessWidget {
  const _LibraryEditToolbar({
    required this.selectedCount,
    required this.onEdit,
    required this.onDelete,
    required this.onDone,
  });

  final int selectedCount;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        boxShadow: AppDesignTokens.toyCardShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppDesignTokens.skyLight,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              selectedCount == 0 ? '选择课程' : '已选 $selectedCount 项',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppDesignTokens.primaryBlueDark,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _LibraryEditActionButton(
            label: '编辑',
            icon: Icons.edit_rounded,
            color: AppDesignTokens.primaryBlueDark,
            background: AppDesignTokens.skyLight,
            onTap: onEdit,
          ),
          const SizedBox(width: 8),
          _LibraryEditActionButton(
            label: '删除',
            icon: Icons.delete_outline_rounded,
            color: const Color(0xFFC74A4A),
            background: const Color(0xFFFFECEC),
            onTap: onDelete,
          ),
          const SizedBox(width: 8),
          _LibraryEditActionButton(
            label: '完成',
            icon: Icons.check_rounded,
            color: AppDesignTokens.appWhite,
            background: AppDesignTokens.brandGreen,
            onTap: onDone,
          ),
        ],
      ),
    );
  }
}

class _LibraryEditActionButton extends StatelessWidget {
  const _LibraryEditActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.background,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            boxShadow: background == AppDesignTokens.brandGreen
                ? AppDesignTokens.toyButtonShadow
                : null,
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryDetailTopStatus extends StatelessWidget {
  const _LibraryDetailTopStatus({
    required this.courseMeta,
    this.episodeName,
  });

  final String courseMeta;
  final String? episodeName;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
        Text(
          courseMeta,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F7A43),
          ),
        ),
          if (episodeName != null && episodeName!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              episodeName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF191C1E),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyEpisodesState extends StatelessWidget {
  const _EmptyEpisodesState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: AppDesignTokens.softWhite,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppDesignTokens.borderGray),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '这个课程还没有可播放剧集',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '请先完成资源导入，或者返回影视库选择已有剧集。',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppDesignTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeSortChip extends StatelessWidget {
  const _EpisodeSortChip({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    const List<String> options = <String>['自然排序', '最近学习', '学习进度', '手动排序'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE4DA)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          borderRadius: BorderRadius.circular(16),
          onChanged: onChanged,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF53625A),
          ),
          items: options
              .map((String item) {
                return DropdownMenuItem<String>(value: item, child: Text(item));
              })
              .toList(growable: false),
        ),
      ),
    );
  }
}
