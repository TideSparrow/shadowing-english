import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../library_mock_data.dart';
import 'library_course_poster.dart';

class CourseOverviewCard extends StatelessWidget {
  const CourseOverviewCard({
    required this.course,
    required this.activeEpisode,
    required this.onPlayTap,
    super.key,
  });

  final LibraryCourseData course;
  final LibraryEpisodeItem activeEpisode;
  final VoidCallback onPlayTap;

  @override
  Widget build(BuildContext context) {
    final int episodeNumber = int.tryParse(activeEpisode.numberStr) ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppDesignTokens.borderGray),
        boxShadow: AppDesignTokens.toyCardShadow,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool compact = constraints.maxWidth < 980;

          final bool narrow =
              constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
              560;
          final Widget poster = ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              width: compact ? 176 : 220,
              height: compact ? 224 : 272,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  LibraryCoursePoster(
                    title: course.title,
                    path: course.coverImage,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.36),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 14,
                    left: 14,
                    child: _PillLabel(
                      label: course.level,
                      backgroundColor: AppDesignTokens.appWhite.withValues(
                        alpha: 0.94,
                      ),
                      textColor: AppDesignTokens.primaryBlueDark,
                    ),
                  ),
                  Positioned(
                    top: 14,
                    right: 14,
                    child: _PillLabel(
                      label: course.category,
                      backgroundColor: AppDesignTokens.yellow,
                      textColor: AppDesignTokens.textPrimary,
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 14,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onPlayTap,
                        borderRadius: BorderRadius.circular(18),
                        child: Ink(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppDesignTokens.appWhite.withValues(
                              alpha: 0.94,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: <Widget>[
                              Container(
                                width: 34,
                                height: 34,
                                decoration: const BoxDecoration(
                                  color: AppDesignTokens.brandGreen,
                                  shape: BoxShape.circle,
                                  boxShadow: AppDesignTokens.toyButtonShadow,
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '第 $episodeNumber 集 · ${activeEpisode.title}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: AppDesignTokens.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
          final Widget details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                course.title,
                style: TextStyle(
                  fontSize: compact ? 30 : 34,
                  fontWeight: FontWeight.w900,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                course.description,
                maxLines: compact ? 2 : 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.55,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '来源：${course.sourceLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppDesignTokens.softWhite,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppDesignTokens.borderGray),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Text(
                          '学习进度',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${course.progressPercent}%',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: AppDesignTokens.brandGreenDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: course.progressPercent / 100,
                        minHeight: 12,
                        backgroundColor: AppDesignTokens.softGray,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppDesignTokens.brandGreen,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: <Widget>[
                        _StatBlock(
                          label: '已完成',
                          value:
                              '${course.completedEpisodes}/${course.totalEpisodes} 集',
                        ),
                        _StatBlock(
                          label: '词汇储备',
                          value: '${course.totalWords} 个',
                        ),
                        _StatBlock(
                          label: '评分',
                          value: course.rating.toStringAsFixed(1),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppDesignTokens.purpleLight,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.lightbulb_rounded,
                      color: AppDesignTokens.primaryBlueDark,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '当前继续：第 $episodeNumber 集 ${activeEpisode.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[poster, const SizedBox(height: 18), details],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              poster,
              SizedBox(width: compact ? 18 : 24),
              Expanded(child: details),
            ],
          );
        },
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppDesignTokens.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PillLabel extends StatelessWidget {
  const _PillLabel({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  final String label;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
      ),
    );
  }
}
