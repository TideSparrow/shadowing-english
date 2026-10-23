import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../growth/presentation/growth_provider.dart';
import '../../import_course/presentation/import_course_screen.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../library/presentation/widgets/library_course_poster.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../phrases/presentation/phrase_book_provider.dart';
import '../../player/presentation/learning_resume_provider.dart';
import '../../shared/presentation/app_loading_overlay.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import 'learning_dashboard_provider.dart';
import 'widgets/pad_home_hero.dart';

class PadHomeScreen extends ConsumerStatefulWidget {
  const PadHomeScreen({super.key});

  @override
  ConsumerState<PadHomeScreen> createState() => _PadHomeScreenState();
}

class _PadHomeScreenState extends ConsumerState<PadHomeScreen> {
  bool _isOpeningEpisode = false;

  @override
  Widget build(BuildContext context) {
    final LearningDashboardStats stats = ref.watch(learningDashboardProvider);
    final UserGrowth growth = ref.watch(userGrowthProvider);
    final List<LibraryCourseData> courses = ref.watch(
      recentLearningCoursesProvider,
    );
    final List<PhraseEntry> savedItems = ref.watch(phraseBookProvider);
    final ContinueLearningTarget? resumeTarget = ref.watch(
      continueLearningTargetProvider,
    );
    final double width = MediaQuery.sizeOf(context).width;
    final bool compact = width < 900;
    final double pagePadding = compact ? 20 : 32;

    void openCourse(
      LibraryCourseData? course, {
      LibraryEpisodeItem? episode,
      bool autoPlay = false,
    }) {
      if (course == null) {
        openImportCourseExperience(context);
        return;
      }
      if (course.episodes.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('该课程暂无可播放的剧集')));
        return;
      }
      final String episodeId = episode?.id ?? course.episodes.first.id;
      if (_isOpeningEpisode) {
        return;
      }
      setState(() {
        _isOpeningEpisode = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        context
            .pushNamed(
              SGRoute.player.name,
              pathParameters: <String, String>{'episodeId': episodeId},
              queryParameters: <String, String>{if (autoPlay) 'autoplay': '1'},
            )
            .then((_) {
              if (!mounted) {
                return;
              }
              setState(() {
                _isOpeningEpisode = false;
              });
            });
      });
    }

    return AppLoadingOverlay(
      isLoading: _isOpeningEpisode,
      message: '正在打开课程...',
      child: PadScaffold(
        currentDestination: AppNavDestination.home,
        topBar: const PadTopBar(title: '语言避难所', subtitle: '首页'),
        body: ListView(
          key: const ValueKey<String>('home-page-scroll'),
          padding: EdgeInsets.all(pagePadding),
          children: <Widget>[
            _GreetingHeader(stats: stats, growth: growth),
            SizedBox(height: compact ? 24 : 28),
            PadHomeHero(
              onTap: () => openCourse(
                resumeTarget?.course,
                episode: resumeTarget?.episode,
                autoPlay: true,
              ),
              course: resumeTarget?.course,
              episode: resumeTarget?.episode,
            ),
            SizedBox(height: compact ? 26 : 30),
            _SectionTitle(title: '今日挑战', compact: compact),
            SizedBox(height: compact ? 12 : 14),
            _TodayMission(stats: stats),
            SizedBox(height: compact ? 26 : 30),
            _SectionTitle(title: '英语成长', compact: compact),
            SizedBox(height: compact ? 12 : 14),
            _EnglishLevelCard(growth: growth),
            SizedBox(height: compact ? 26 : 30),
            _SectionTitle(title: '我的收藏', compact: compact),
            SizedBox(height: compact ? 12 : 14),
            _SavedCollectionCard(
              items: savedItems,
              onTap: () => context.go(AppNavDestination.phrases.route),
            ),
            SizedBox(height: compact ? 26 : 30),
            _SectionTitle(title: '最近学习的课程', compact: compact),
            SizedBox(height: compact ? 12 : 14),
            _RecentCourses(courses: courses, onTap: openCourse),
            SizedBox(height: compact ? 26 : 30),
            Text(
              '下一步想做什么？',
              style: TextStyle(
                fontSize: compact ? 18 : 20,
                fontWeight: FontWeight.w900,
                color: AppDesignTokens.textPrimary,
              ),
            ),
            SizedBox(height: compact ? 14 : 18),
            _QuickAccessRow(
              onOpenLibrary: () => context.go(AppNavDestination.library.route),
              onOpenPhrases: () => context.go(AppNavDestination.phrases.route),
              onOpenGuide: () => context.go(AppNavDestination.guide.route),
            ),
          ],
        ),
      ),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({required this.stats, required this.growth});

  final LearningDashboardStats stats;
  final UserGrowth growth;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '晚上好 Mark 👋',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
              SizedBox(height: 6),
              Text(
                '继续你的英语成长旅程',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1D6),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '🔥 连续 ${stats.streakDays} 天',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Lv.${growth.level} ${growth.title}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.compact});
  final String title;
  final bool compact;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: TextStyle(
      fontSize: compact ? 20 : 22,
      fontWeight: FontWeight.w900,
      color: AppDesignTokens.textPrimary,
    ),
  );
}

class _TodayMission extends StatelessWidget {
  const _TodayMission({required this.stats});
  final LearningDashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final List<_MissionItem> items = <_MissionItem>[
      _MissionItem(
        Icons.headphones_rounded,
        '精听 10 分钟',
        stats.todayStudyMinutes,
        10,
        AppDesignTokens.primaryBlueDark,
      ),
      _MissionItem(
        Icons.chat_bubble_rounded,
        '学习 5 个句子',
        stats.todaySentenceCount,
        5,
        AppDesignTokens.brandGreenDark,
      ),
      _MissionItem(
        Icons.bookmark_rounded,
        '收藏 1 个短语',
        stats.todaySavedPhrases,
        1,
        const Color(0xFF8B5CF6),
      ),
    ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool horizontal = constraints.maxWidth >= 700;
        if (!horizontal) {
          return Column(
            children: <Widget>[
              for (int index = 0; index < items.length; index++) ...<Widget>[
                _MissionProgress(item: items[index]),
                if (index < items.length - 1) const SizedBox(height: 14),
              ],
            ],
          );
        }
        return Row(
          children: <Widget>[
            for (int index = 0; index < items.length; index++) ...<Widget>[
              Expanded(child: _MissionProgress(item: items[index])),
              if (index < items.length - 1) const SizedBox(width: 18),
            ],
          ],
        );
      },
    );
  }
}

class _MissionItem {
  const _MissionItem(
    this.icon,
    this.label,
    this.progress,
    this.target,
    this.color,
  );
  final IconData icon;
  final String label;
  final int progress;
  final int target;
  final Color color;

  int get rewardXP => target == 10
      ? 10
      : target == 5
      ? 15
      : 5;
}

class _MissionProgress extends StatelessWidget {
  const _MissionProgress({required this.item});
  final _MissionItem item;

  @override
  Widget build(BuildContext context) {
    final int progress = item.progress.clamp(0, item.target);
    final bool completed = progress >= item.target;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            item.color.withValues(alpha: 0.17),
            item.color.withValues(alpha: 0.055),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: item.color.withValues(alpha: 0.12)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1423385B),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  completed ? Icons.check_rounded : item.icon,
                  color: item.color,
                  size: 23,
                ),
              ),
              const Spacer(),
              Text(
                '+${item.rewardXP} XP',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: item.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            item.label,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress / item.target,
                    minHeight: 8,
                    color: item.color,
                    backgroundColor: AppDesignTokens.appWhite.withValues(
                      alpha: 0.8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$progress / ${item.target}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: item.color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EnglishLevelCard extends StatelessWidget {
  const _EnglishLevelCard({required this.growth});
  final UserGrowth growth;

  @override
  Widget build(BuildContext context) {
    final int remainingXP = (growth.nextLevelXP - growth.currentXP).clamp(
      0,
      growth.nextLevelXP,
    );
    final String nextTitle = growth.level == 10
        ? '最高等级'
        : 'Lv.${growth.level + 1} ${growthLevelProfile(growth.level + 1).title}';
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: () => context.go(AppNavDestination.growth.route),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFFE4F6DD), Color(0xFFE6F0FF)],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x1A24385B),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[
                    AppDesignTokens.brandGreen,
                    Color(0xFF8DDA46),
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: const Icon(
                Icons.explore_rounded,
                color: Colors.white,
                size: 31,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '英语成长',
                    style: TextStyle(
                      color: AppDesignTokens.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Lv.${growth.level} ${growth.title}',
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '下一阶段 · $nextTitle',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppDesignTokens.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: Stack(
                      children: <Widget>[
                        Container(
                          height: 12,
                          color: AppDesignTokens.appWhite.withValues(
                            alpha: 0.82,
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: growth.levelProgress,
                          child: Container(
                            height: 12,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: <Color>[
                                  AppDesignTokens.brandGreen,
                                  Color(0xFF9CE753),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '还差 $remainingXP XP 升级',
                    style: const TextStyle(
                      color: AppDesignTokens.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedCollectionCard extends StatelessWidget {
  const _SavedCollectionCard({required this.items, required this.onTap});

  final List<PhraseEntry> items;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final int wordCount = items.fold<int>(
      0,
      (int total, PhraseEntry item) =>
          total +
          item.english
              .split(RegExp(r'\s+'))
              .where((String word) => word.isNotEmpty)
              .length,
    );
    return Material(
      color: AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Text(
                    '最近收藏，随时温习',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.menu_book_rounded, size: 18),
                    label: const Text('去复习'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _CollectionMetric(
                      icon: Icons.format_quote_rounded,
                      label: '句子',
                      value: '${items.length} 个句子',
                      color: AppDesignTokens.primaryBlueDark,
                      background: AppDesignTokens.skyLight,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 58,
                    color: AppDesignTokens.borderGray,
                  ),
                  Expanded(
                    child: _CollectionMetric(
                      icon: Icons.abc_rounded,
                      label: '单词',
                      value: '$wordCount 个单词',
                      color: const Color(0xFF8B5CF6),
                      background: AppDesignTokens.purpleLight,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollectionMetric extends StatelessWidget {
  const _CollectionMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: const TextStyle(
                color: AppDesignTokens.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 17,
                color: AppDesignTokens.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RecentCourses extends StatelessWidget {
  const _RecentCourses({required this.courses, required this.onTap});
  final List<LibraryCourseData> courses;
  final ValueChanged<LibraryCourseData> onTap;

  @override
  Widget build(BuildContext context) {
    if (courses.isEmpty) return const _EmptyCourses();
    return SizedBox(
      height: 188,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: courses.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (BuildContext context, int index) => SizedBox(
          key: ValueKey<String>('recent-course-${courses[index].id}'),
          width: 260,
          child: _RecentCourseCard(
            course: courses[index],
            onTap: () => onTap(courses[index]),
          ),
        ),
      ),
    );
  }
}

class _RecentCourseCard extends StatelessWidget {
  const _RecentCourseCard({required this.course, required this.onTap});
  final LibraryCourseData course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppDesignTokens.primaryBlueDark,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            LibraryCoursePoster(
              title: course.title,
              path: course.coverImage,
              borderRadius: BorderRadius.circular(24),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0x00000000), Color(0xBB000000)],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Text(
                course.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCourses extends StatelessWidget {
  const _EmptyCourses();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(28),
    ),
    child: const Text(
      '导入课程后，这里会保留你的学习足迹。',
      style: TextStyle(color: AppDesignTokens.textSecondary),
    ),
  );
}

class _QuickAccessRow extends StatelessWidget {
  const _QuickAccessRow({
    required this.onOpenLibrary,
    required this.onOpenPhrases,
    required this.onOpenGuide,
  });

  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenPhrases;
  final VoidCallback onOpenGuide;

  @override
  Widget build(BuildContext context) {
    final List<_QuickAccessCard> items = <_QuickAccessCard>[
      _QuickAccessCard(
        icon: Icons.movie_outlined,
        title: '挑一集新课程',
        body: '去影视库选一集，开始新的精听。',
        onTap: onOpenLibrary,
      ),
      _QuickAccessCard(
        icon: Icons.menu_book_outlined,
        title: '复习我的短语',
        body: '把保存的单词和句子再练一遍。',
        onTap: onOpenPhrases,
      ),
      _QuickAccessCard(
        icon: Icons.school_outlined,
        title: '看看学习小妙招',
        body: '用简单方法，让听力进步更快。',
        onTap: onOpenGuide,
      ),
    ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool oneRow = constraints.maxWidth >= 700;
        final double itemWidth = oneRow
            ? (constraints.maxWidth - 36) / 3
            : double.infinity;
        return Wrap(
          spacing: 18,
          runSpacing: 18,
          children: items
              .map(
                (_QuickAccessCard item) =>
                    SizedBox(width: itemWidth, child: item),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _QuickAccessCard extends StatelessWidget {
  const _QuickAccessCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppDesignTokens.toyCardShadow,
      ),
      child: Material(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 182,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppDesignTokens.skyLight,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      icon,
                      color: AppDesignTokens.primaryBlueDark,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    body,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.55,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
