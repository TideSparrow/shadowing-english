import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../data/lesson_store.dart';
import '../domain/intensive_lesson.dart';
import '../domain/lesson_summary.dart';
import 'lesson_dialog.dart';
import 'lesson_preview_card.dart';

class LessonsScreen extends ConsumerStatefulWidget {
  const LessonsScreen({super.key});
  @override
  ConsumerState<LessonsScreen> createState() => _LessonsScreenState();
}

class _LessonsScreenState extends ConsumerState<LessonsScreen> {
  static const int _pageSize = 24;
  final ScrollController _scroll = ScrollController();
  Timer? _searchTimer;
  String _query = '';
  String? _course;
  bool _cards = true;
  bool _opening = false;
  int _page = 0;

  @override
  void dispose() {
    _searchTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _search(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _query = value.trim().toLowerCase();
        _page = 0;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  void _changePage(int page) {
    setState(() => _page = page);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<LessonSummary>> book = ref.watch(lessonBookProvider);
    final List<LessonSummary> all = book.asData?.value ?? <LessonSummary>[];
    final List<String> courses =
        all.map((LessonSummary item) => item.courseTitle).toSet().toList()
          ..sort();
    final String? course = courses.contains(_course) ? _course : null;
    final List<LessonSummary> filtered = all
        .where(
          (LessonSummary lesson) =>
              (course == null || lesson.courseTitle == course) &&
              (_query.isEmpty || lesson.searchText.contains(_query)),
        )
        .toList(growable: false);
    final int pageCount = max(1, (filtered.length / _pageSize).ceil());
    final int page = _page.clamp(0, pageCount - 1);
    final List<LessonSummary> visible = filtered
        .skip(page * _pageSize)
        .take(_pageSize)
        .toList(growable: false);
    final double padding = MediaQuery.sizeOf(context).width < 600 ? 16 : 28;
    Widget pagination(String prefix) => LessonPagination(
      page: page,
      pageCount: pageCount,
      onChanged: _changePage,
      prefix: prefix,
    );
    return PadScaffold(
      currentDestination: AppNavDestination.lessons,
      topBar: const PadTopBar(title: '精讲', description: '回到那些终于听明白的句子，再听、再理解。'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: CustomScrollView(
            controller: _scroll,
            slivers: <Widget>[
              SliverPadding(
                padding: EdgeInsets.all(padding),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Text(
                        '让表达留在场景里',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '播放器生成的卡片会自动保存在这里，复习时无需再次调用 AI。',
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          color: AppDesignTokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        key: const Key('lesson-search'),
                        onChanged: _search,
                        decoration: const InputDecoration(
                          hintText: '搜索原句、表达或中文含义',
                          prefixIcon: Icon(Icons.search_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(16)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 48 * MediaQuery.textScalerOf(context).scale(1),
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: courses.length + 1,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, int index) {
                            final String? name = index == 0
                                ? null
                                : courses[index - 1];
                            return ChoiceChip(
                              label: Text(name ?? '全部课程'),
                              selected: course == name,
                              onSelected: (_) {
                                setState(() {
                                  _course = name;
                                  _page = 0;
                                });
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 16,
                        runSpacing: 12,
                        children: <Widget>[
                          Text(
                            '共 ${filtered.length} 组精讲',
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppDesignTokens.textSecondary,
                            ),
                          ),
                          SegmentedButton<bool>(
                            key: const Key('lesson-view-mode'),
                            showSelectedIcon: false,
                            segments: const <ButtonSegment<bool>>[
                              ButtonSegment<bool>(
                                value: true,
                                icon: Icon(Icons.grid_view_rounded),
                                label: Text('卡片'),
                              ),
                              ButtonSegment<bool>(
                                value: false,
                                icon: Icon(Icons.view_list_rounded),
                                label: Text('列表'),
                              ),
                            ],
                            selected: <bool>{_cards},
                            onSelectionChanged: (Set<bool> value) =>
                                setState(() => _cards = value.single),
                          ),
                        ],
                      ),
                      if (pageCount > 1) ...<Widget>[
                        const SizedBox(height: 18),
                        pagination('lesson-top'),
                      ],
                    ],
                  ),
                ),
              ),
              book.when(
                loading: () => const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => SliverFillRemaining(
                  child: LessonReadError(
                    onRetry: () => ref.invalidate(lessonBookProvider),
                  ),
                ),
                data: (_) => filtered.isEmpty
                    ? SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyLessons(
                          filtered: all.isNotEmpty,
                          onLibrary: () => context.go(SGRoute.library.route),
                        ),
                      )
                    : SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: padding),
                        sliver: _cards
                            ? SliverLayoutBuilder(
                                builder:
                                    (
                                      BuildContext context,
                                      SliverConstraints constraints,
                                    ) {
                                      final double scale =
                                          MediaQuery.textScalerOf(
                                            context,
                                          ).scale(1);
                                      final int columns =
                                          ((constraints.crossAxisExtent + 16) /
                                                  (320 * scale))
                                              .floor()
                                              .clamp(1, 3);
                                      return SliverGrid.builder(
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: columns,
                                              mainAxisSpacing: 16,
                                              crossAxisSpacing: 16,
                                              mainAxisExtent: 360 * scale,
                                            ),
                                        itemCount: visible.length,
                                        itemBuilder: (_, int index) =>
                                            LessonPreviewCard(
                                              key: ValueKey<String>(
                                                visible[index].id,
                                              ),
                                              lesson: visible[index],
                                              onOpen: () => unawaited(
                                                _open(visible[index]),
                                              ),
                                              onDelete: () => unawaited(
                                                _delete(visible[index]),
                                              ),
                                            ),
                                      );
                                    },
                              )
                            : SliverList.separated(
                                itemCount: visible.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (_, int index) => LessonListTile(
                                  key: ValueKey<String>(visible[index].id),
                                  lesson: visible[index],
                                  onOpen: () =>
                                      unawaited(_open(visible[index])),
                                  onDelete: () =>
                                      unawaited(_delete(visible[index])),
                                ),
                              ),
                      ),
              ),
              if (filtered.isNotEmpty)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(padding, 24, padding, 100),
                  sliver: SliverToBoxAdapter(
                    child: pageCount > 1
                        ? pagination('lesson-bottom')
                        : const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(LessonSummary summary) async {
    if (_opening) return;
    _opening = true;
    try {
      final IntensiveLesson? lesson = await ref
          .read(lessonBookProvider.notifier)
          .find(summary.id);
      if (!mounted) return;
      if (lesson == null) throw const FormatException('Missing saved lesson.');
      final List<LibraryCourseData> catalog = ref.read(libraryCatalogProvider);
      final bool hasSource = catalog.any(
        (LibraryCourseData course) => course.episodes.any(
          (LibraryEpisodeItem episode) =>
              episode.id == lesson.source.episodeId &&
              (episode.videoAsset?.isNotEmpty ?? false),
        ),
      );
      final LessonDialogAction? action = await showLessonDialog(
        context,
        source: lesson.source,
        savedLesson: lesson,
        canOpenSource: hasSource,
      );
      if (!mounted) return;
      if (action == LessonDialogAction.settings) {
        await context.push(SGRoute.settings.route);
      } else if (action == LessonDialogAction.source) {
        await context.pushNamed<void>(
          SGRoute.player.name,
          pathParameters: <String, String>{
            'episodeId': lesson.source.episodeId,
          },
          queryParameters: <String, String>{
            'startTime': lesson.source.seekTimeWithDelay(
              ref.read(learningSettingsProvider).subtitleDelayMs,
            ),
            'autoplay': '1',
          },
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂时无法打开这组精讲，请重试。')));
      }
    } finally {
      _opening = false;
    }
  }

  Future<void> _delete(LessonSummary lesson) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除这组精讲？'),
        content: const Text('将删除本机保存的卡片和讲解稿。以后重新解析可能产生费用。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(lessonBookProvider.notifier).delete(lesson.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('删除失败，请重试。')));
      }
    }
  }
}

/// Reused inside the player's subtitle sidebar, scoped to the current episode.
class EpisodeLessonList extends ConsumerStatefulWidget {
  const EpisodeLessonList({
    required this.episodeId,
    required this.onOpen,
    super.key,
  });
  final String episodeId;
  final ValueChanged<IntensiveLesson> onOpen;

  @override
  ConsumerState<EpisodeLessonList> createState() => _EpisodeLessonListState();
}

class _EpisodeLessonListState extends ConsumerState<EpisodeLessonList> {
  static const int _pageSize = 24;
  int _page = 0;

  @override
  void didUpdateWidget(EpisodeLessonList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episodeId != widget.episodeId) _page = 0;
  }

  Future<void> _open(LessonSummary summary) async {
    try {
      final IntensiveLesson? lesson = await ref
          .read(lessonBookProvider.notifier)
          .find(summary.id);
      if (!mounted) return;
      if (lesson == null) throw const FormatException('Missing saved lesson.');
      widget.onOpen(lesson);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂时无法打开这组精讲，请重试。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(lessonBookProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            LessonReadError(onRetry: () => ref.invalidate(lessonBookProvider)),
        data: (List<LessonSummary> all) {
          final List<LessonSummary> lessons = all
              .where((LessonSummary item) => item.episodeId == widget.episodeId)
              .toList(growable: false);
          if (lessons.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '这一集还没有精讲\n点击视频中的「精讲这句」，卡片会自动保存在这里。',
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 1.8),
                ),
              ),
            );
          }
          final int pageCount = max(1, (lessons.length / _pageSize).ceil());
          final int page = _page.clamp(0, pageCount - 1);
          final List<LessonSummary> visible = lessons
              .skip(page * _pageSize)
              .take(_pageSize)
              .toList(growable: false);
          return Column(
            children: <Widget>[
              Expanded(
                child: ListView.separated(
                  key: ValueKey<String>('${widget.episodeId}-$page'),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, int index) => LessonListTile(
                    lesson: visible[index],
                    onOpen: () => unawaited(_open(visible[index])),
                    compact: true,
                  ),
                ),
              ),
              if (pageCount > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: LessonPagination(
                    page: page,
                    pageCount: pageCount,
                    prefix: 'episode-lesson',
                    onChanged: (int value) => setState(() => _page = value),
                  ),
                ),
            ],
          );
        },
      );
}

class LessonPagination extends StatelessWidget {
  const LessonPagination({
    required this.page,
    required this.pageCount,
    required this.onChanged,
    required this.prefix,
    super.key,
  });
  final int page;
  final int pageCount;
  final ValueChanged<int> onChanged;
  final String prefix;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12,
    runSpacing: 8,
    children: <Widget>[
      OutlinedButton(
        key: ValueKey<String>('$prefix-previous'),
        onPressed: page > 0 ? () => onChanged(page - 1) : null,
        child: const Text('上一页'),
      ),
      Text(
        '第 ${page + 1} / $pageCount 页',
        style: const TextStyle(
          fontSize: 13,
          color: AppDesignTokens.textSecondary,
        ),
      ),
      OutlinedButton(
        key: ValueKey<String>('$prefix-next'),
        onPressed: page + 1 < pageCount ? () => onChanged(page + 1) : null,
        child: const Text('下一页'),
      ),
    ],
  );
}

class LessonListTile extends StatelessWidget {
  const LessonListTile({
    required this.lesson,
    required this.onOpen,
    this.onDelete,
    this.compact = false,
    super.key,
  });
  final LessonSummary lesson;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  final bool compact;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: AppDesignTokens.borderGray),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onOpen,
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 22),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    lesson.english,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 18 : 22,
                      height: 1.4,
                      fontWeight: FontWeight.w800,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    lesson.meaning,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '${lesson.courseTitle} · ${lesson.episodeTitle} · ${lesson.timeLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${lesson.cardCount} 张卡片 · 含讲解稿',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF367300),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (onDelete != null)
              IconButton(
                onPressed: onDelete,
                tooltip: '删除精讲',
                icon: const Icon(Icons.delete_outline),
              ),
            if (onDelete == null)
              const Icon(
                Icons.chevron_right_rounded,
                color: AppDesignTokens.textSecondary,
              ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyLessons extends StatelessWidget {
  const _EmptyLessons({required this.filtered, required this.onLibrary});
  final bool filtered;
  final VoidCallback onLibrary;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(
          Icons.auto_stories_outlined,
          size: 48,
          color: AppDesignTokens.primaryBlueDark,
        ),
        const SizedBox(height: 18),
        Text(
          filtered ? '没有找到匹配的精讲' : '从一句没听懂的台词开始',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Text(
          filtered ? '试试其他词，或切换课程。' : '播放视频时点击「精讲这句」，这里就会留下它的解释。',
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.7),
        ),
        if (!filtered) ...<Widget>[
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onLibrary,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('去看视频'),
          ),
        ],
      ],
    ),
  );
}

class LessonReadError extends StatelessWidget {
  const LessonReadError({required this.onRetry, super.key});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text('暂时无法读取本地精讲。', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('重新读取')),
      ],
    ),
  );
}
