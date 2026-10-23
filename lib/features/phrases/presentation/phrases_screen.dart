import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../anki_export/presentation/anki_export_sheet.dart';
import '../../daily_review/presentation/daily_review_provider.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/data/word_pronunciation_service.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../../shared/presentation/pill_segmented_control.dart';
import 'phrase_book_provider.dart';
import 'widgets/phrase_card.dart';

enum _PhraseView { due, all, mastered }

class PhrasesScreen extends ConsumerStatefulWidget {
  const PhrasesScreen({super.key});

  @override
  ConsumerState<PhrasesScreen> createState() => _PhrasesScreenState();
}

class _PhrasesScreenState extends ConsumerState<PhrasesScreen> {
  String query = '';
  String selectedCourse = '全部课程';
  _PhraseView selectedView = _PhraseView.due;
  String? speakingPhraseId;
  WordPronunciationService? pronunciationService;

  @override
  void dispose() {
    if (speakingPhraseId != null && pronunciationService != null) {
      unawaited(pronunciationService!.stop());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<PhraseEntry> phrases = ref.watch(phraseBookProvider);
    final List<LibraryCourseData> catalog = ref.watch(libraryCatalogProvider);
    final List<PhraseEntry> due = phrases
        .where((PhraseEntry item) => item.isDue())
        .toList(growable: false);
    final List<String> courseOptions = <String>[
      '全部课程',
      ...phrases.map((PhraseEntry item) => item.course).toSet(),
    ];
    if (!courseOptions.contains(selectedCourse)) {
      selectedCourse = '全部课程';
    }
    final List<PhraseEntry> filtered = _filterPhrases(phrases);

    return PadScaffold(
      currentDestination: AppNavDestination.phrases,
      topBar: PadTopBar(
        title: '短语库',
        actions: const <Widget>[AnkiExportButton()],
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              onPressed: _showReviewHelp,
              tooltip: '复习说明',
              icon: const Icon(Icons.help_outline_rounded),
            ),
            const SizedBox(width: 6),
            TextButton.icon(
              onPressed: _showPhraseDialog,
              icon: const Icon(Icons.add_rounded),
              style: TextButton.styleFrom(
                foregroundColor: AppDesignTokens.brandGreenDark,
              ),
              label: Text(
                MediaQuery.sizeOf(context).width < 840 ? '添加' : '新增短语',
              ),
            ),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: ListView(
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
            ),
            children: <Widget>[
              _TodayReviewBanner(
                reviewCount: due.length,
                onPressed: phrases.isEmpty
                    ? null
                    : () => context.pushNamed(SGRoute.phraseReview.name),
              ),
              const SizedBox(height: 22),
              _LibraryControls(
                query: query,
                selectedCourse: selectedCourse,
                courseOptions: courseOptions,
                selectedView: selectedView,
                dueCount: due.length,
                allCount: phrases.length,
                masteredCount: phrases
                    .where((PhraseEntry item) => item.isMastered)
                    .length,
                onQueryChanged: (String value) => setState(() => query = value),
                onCourseChanged: (String value) =>
                    setState(() => selectedCourse = value),
                onViewChanged: (_PhraseView value) =>
                    setState(() => selectedView = value),
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      '短语',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '${filtered.length} 条',
                    style: const TextStyle(
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (filtered.isEmpty)
                _EmptyPhraseList(
                  hasPhrases: phrases.isNotEmpty,
                  onClear: () => setState(() {
                    query = '';
                    selectedCourse = '全部课程';
                    selectedView = _PhraseView.all;
                  }),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (BuildContext context, int index) {
                    final PhraseEntry phrase = filtered[index];
                    return PhraseCard(
                      phrase: phrase,
                      isSpeaking: speakingPhraseId == phrase.id,
                      onSpeak: () => _toggleSpeak(phrase),
                      onEdit: () => _showPhraseDialog(phrase),
                      onDelete: () => _confirmDelete(phrase),
                      onMarkForReview: () async {
                        try {
                          await ref
                              .read(dailyReviewProvider.notifier)
                              .reviewToday('phrase:${phrase.id}');
                          if (mounted) _showMessage('已加入每日复习，新内容按每日额度安排');
                        } catch (_) {
                          if (mounted) _showMessage('未能保存，请重试');
                        }
                      },
                      onOpenSource: () =>
                          _jumpToSource(context, catalog, phrase),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<PhraseEntry> _filterPhrases(List<PhraseEntry> phrases) {
    final String keyword = query.trim().toLowerCase();
    return phrases
        .where((PhraseEntry item) {
          final bool matchesQuery =
              keyword.isEmpty ||
              item.english.toLowerCase().contains(keyword) ||
              item.chinese.toLowerCase().contains(keyword);
          final bool matchesCourse =
              selectedCourse == '全部课程' || item.course == selectedCourse;
          final bool matchesView = switch (selectedView) {
            _PhraseView.due => item.isDue(),
            _PhraseView.all => true,
            _PhraseView.mastered => item.isMastered,
          };
          return matchesQuery && matchesCourse && matchesView;
        })
        .toList(growable: false);
  }

  Future<void> _showPhraseDialog([PhraseEntry? phrase]) async {
    final TextEditingController english = TextEditingController(
      text: phrase?.english,
    );
    final TextEditingController chinese = TextEditingController(
      text: phrase?.chinese,
    );
    final TextEditingController note = TextEditingController(
      text: phrase?.note,
    );
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(phrase == null ? '新增短语' : '编辑短语'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: english,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '英文短语或例句',
                    hintText:
                        '例如: They sought a quiet sanctuary away from the noise.',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: chinese,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '中文翻译或提示',
                    hintText: '例如: 他们寻找一个远离喧嚣的安静避难所。',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: note,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '学习笔记（可选）'),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final String englishValue = english.text.trim();
              final String chineseValue = chinese.text.trim();
              if (englishValue.isEmpty || chineseValue.isEmpty) {
                _showMessage('请填写英文短语与中文提示');
                return;
              }
              final PhraseBookNotifier notifier = ref.read(
                phraseBookProvider.notifier,
              );
              if (phrase == null) {
                notifier.addPhrase(
                  english: englishValue,
                  chinese: chineseValue,
                  course: '自定义添加',
                  episode: '手动导入',
                  time: '00:00',
                  note: note.text.trim(),
                );
              } else {
                notifier.updatePhrase(
                  phrase.id,
                  (PhraseEntry item) => item.copyWith(
                    english: englishValue,
                    chinese: chineseValue,
                    note: note.text.trim(),
                  ),
                );
              }
              Navigator.of(dialogContext).pop();
              _showMessage(phrase == null ? '已加入短语库' : '短语已更新');
            },
            child: Text(phrase == null ? '加入短语库' : '保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(PhraseEntry phrase) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('删除短语？'),
        content: Text('“${phrase.english}” 删除后无法恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(phraseBookProvider.notifier).deletePhrase(phrase.id);
    _showMessage('短语已删除');
  }

  Future<void> _showReviewHelp() {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('短语库怎么用'),
        content: const SizedBox(
          width: 500,
          child: Text(
            '先在播放器收藏值得反复使用的表达。复习时先看中文回忆英文，再显示答案并开口跟读。复习结果会自动安排下次复习时间。',
            style: TextStyle(height: 1.6),
          ),
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleSpeak(PhraseEntry phrase) async {
    final WordPronunciationService service = ref.read(
      wordPronunciationServiceProvider,
    );
    pronunciationService = service;
    if (speakingPhraseId == phrase.id) {
      setState(() => speakingPhraseId = null);
      try {
        await service.stop();
      } on WordPronunciationException catch (error) {
        if (mounted) _showMessage(error.message);
      }
      return;
    }
    setState(() => speakingPhraseId = phrase.id);
    try {
      await service.speak(phrase.english);
    } on WordPronunciationException catch (error) {
      if (mounted) _showMessage(error.message);
    } finally {
      if (mounted && speakingPhraseId == phrase.id) {
        setState(() => speakingPhraseId = null);
      }
    }
  }

  void _jumpToSource(
    BuildContext context,
    List<LibraryCourseData> catalog,
    PhraseEntry phrase,
  ) {
    final String? episodeId = _resolveEpisodeId(catalog, phrase);
    if (episodeId == null) {
      _showMessage('该短语来源的影片或剧集已不存在，可继续复习或编辑短语。');
      return;
    }
    context.pushNamed(
      SGRoute.player.name,
      pathParameters: <String, String>{'episodeId': episodeId},
      queryParameters: <String, String>{
        'startTime': phrase.startTime ?? phrase.time,
        'autoplay': '1',
      },
    );
  }

  String? _resolveEpisodeId(
    List<LibraryCourseData> catalog,
    PhraseEntry phrase,
  ) {
    if (phrase.episodeId != null &&
        catalog.any(
          (LibraryCourseData course) => course.episodes.any(
            (LibraryEpisodeItem episode) => episode.id == phrase.episodeId,
          ),
        )) {
      return phrase.episodeId;
    }
    for (final LibraryCourseData course in catalog) {
      if (course.title != phrase.course) continue;
      for (final LibraryEpisodeItem episode in course.episodes) {
        if (phrase.episode.contains(episode.numberStr)) return episode.id;
      }
    }
    return null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TodayReviewBanner extends StatelessWidget {
  const _TodayReviewBanner({
    required this.reviewCount,
    required this.onPressed,
  });

  final int reviewCount;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final bool compact = width < 840;
    final bool phone = width < 520;
    final bool stacked = width < 340;
    final Widget copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          reviewCount == 0
              ? '今天没有到期短语'
              : phone
              ? '$reviewCount 条短语待复习'
              : '今日有 $reviewCount 条待复习',
          style: TextStyle(
            fontSize: compact ? 18 : 20,
            fontWeight: FontWeight.w900,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          reviewCount == 0
              ? '每日复习会统一安排收藏的单词和短语。'
              : phone
              ? '约 ${reviewCount * 2} 分钟'
              : '预计 ${reviewCount * 2} 分钟，把看懂变成会用。',
          style: const TextStyle(color: AppDesignTokens.textSecondary),
        ),
      ],
    );
    final Widget action = FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.play_arrow_rounded),
      label: const Text('每日复习'),
      style: FilledButton.styleFrom(
        backgroundColor: AppDesignTokens.brandGreen,
        foregroundColor: Colors.white,
      ),
    );
    return Container(
      padding: EdgeInsets.all(compact ? 18 : 22),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FAE8),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppDesignTokens.brandGreen, width: 2),
        boxShadow: AppDesignTokens.toyCardShadow,
      ),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const _ReviewIcon(),
                    const SizedBox(width: 14),
                    Expanded(child: copy),
                  ],
                ),
                const SizedBox(height: 16),
                action,
              ],
            )
          : Row(
              children: <Widget>[
                const _ReviewIcon(),
                const SizedBox(width: 16),
                Expanded(child: copy),
                const SizedBox(width: 16),
                action,
              ],
            ),
    );
  }
}

class _ReviewIcon extends StatelessWidget {
  const _ReviewIcon();

  @override
  Widget build(BuildContext context) {
    return const CircleAvatar(
      radius: 28,
      backgroundColor: AppDesignTokens.brandGreen,
      child: Icon(Icons.headphones_rounded, color: Colors.white, size: 28),
    );
  }
}

class _LibraryControls extends StatelessWidget {
  const _LibraryControls({
    required this.query,
    required this.selectedCourse,
    required this.courseOptions,
    required this.selectedView,
    required this.dueCount,
    required this.allCount,
    required this.masteredCount,
    required this.onQueryChanged,
    required this.onCourseChanged,
    required this.onViewChanged,
  });

  final String query;
  final String selectedCourse;
  final List<String> courseOptions;
  final _PhraseView selectedView;
  final int dueCount;
  final int allCount;
  final int masteredCount;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onCourseChanged;
  final ValueChanged<_PhraseView> onViewChanged;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final bool compact = width < 360;
    final bool phone = width < 840;
    final Widget search = _ControlSurface(
      child: TextField(
        onChanged: onQueryChanged,
        textAlignVertical: TextAlignVertical.center,
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: '搜索英文或中文',
          prefixIcon: Icon(Icons.search_rounded),
        ),
      ),
    );
    final Widget course = _ControlSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selectedCourse,
            isExpanded: true,
            items: courseOptions
                .map(
                  (String item) =>
                      DropdownMenuItem<String>(value: item, child: Text(item)),
                )
                .toList(growable: false),
            onChanged: (String? value) {
              if (value != null) onCourseChanged(value);
            },
          ),
        ),
      ),
    );
    final Widget views = PillSegmentedControl<_PhraseView>(
      value: selectedView,
      options: <SegmentOption<_PhraseView>>[
        SegmentOption<_PhraseView>(
          value: _PhraseView.due,
          label: '待复习 $dueCount',
        ),
        SegmentOption<_PhraseView>(
          value: _PhraseView.all,
          label: '全部 $allCount',
        ),
        SegmentOption<_PhraseView>(
          value: _PhraseView.mastered,
          label: '已掌握 $masteredCount',
        ),
      ],
      onValueChanged: onViewChanged,
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          search,
          const SizedBox(height: 12),
          course,
          const SizedBox(height: 12),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: views),
        ],
      );
    }
    if (phone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(flex: 2, child: search),
              const SizedBox(width: 12),
              Expanded(child: course),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: views),
        ],
      );
    }
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(flex: 3, child: search),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: course),
            const Spacer(),
            views,
          ],
        ),
      ],
    );
  }
}

class _ControlSurface extends StatelessWidget {
  const _ControlSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppDesignTokens.borderGray, width: 2),
      ),
      child: SizedBox(height: 56, child: child),
    );
  }
}

class _EmptyPhraseList extends StatelessWidget {
  const _EmptyPhraseList({required this.hasPhrases, required this.onClear});

  final bool hasPhrases;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: <Widget>[
          const Icon(
            Icons.menu_book_rounded,
            size: 44,
            color: AppDesignTokens.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(hasPhrases ? '没有找到符合条件的短语。' : '先在播放器里收藏一句值得练习的表达。'),
          if (hasPhrases) ...<Widget>[
            const SizedBox(height: 12),
            TextButton(onPressed: onClear, child: const Text('清除筛选')),
          ],
        ],
      ),
    );
  }
}
