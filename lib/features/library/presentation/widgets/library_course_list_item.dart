import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../library_mock_data.dart';
import 'library_course_poster.dart';

class LibraryCourseListItem extends StatelessWidget {
  const LibraryCourseListItem({
    required this.course,
    required this.onTap,
    this.onResourceDirectory,
    this.selected = false,
    this.selectionMode = false,
    super.key,
  });

  final LibraryCourseData course;
  final VoidCallback onTap;
  final VoidCallback? onResourceDirectory;
  final bool selected;
  final bool selectionMode;

  @override
  Widget build(BuildContext context) {
    final bool isNewCourse = course.id == 'ted-imported';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: Ink(
        decoration: BoxDecoration(
          color: AppDesignTokens.appWhite,
          borderRadius: BorderRadius.circular(32),
          boxShadow: AppDesignTokens.toyCardShadow,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: SizedBox(
                  width: 138,
                  height: 150,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: LibraryCoursePoster(
                          title: course.title,
                          path: course.coverImage,
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                AppDesignTokens.appWhite.withValues(alpha: 0.04),
                                Colors.black.withValues(alpha: 0.42),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        top: 10,
                        child: _PosterBadge(
                          label: course.level,
                          color: AppDesignTokens.appWhite.withValues(alpha: 0.96),
                          textColor: AppDesignTokens.primaryBlueDark,
                        ),
                      ),
                      if (selectionMode)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Checkbox(
                            value: selected,
                            onChanged: (_) => onTap(),
                            visualDensity: VisualDensity.compact,
                            activeColor: AppDesignTokens.brandGreen,
                            checkColor: AppDesignTokens.appWhite,
                            side: const BorderSide(
                              color: AppDesignTokens.borderGray,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        )
                      else if (onResourceDirectory != null)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: IconButton.filledTonal(
                            tooltip: '资源目录',
                            onPressed: onResourceDirectory,
                            icon: const Icon(Icons.folder_open_outlined),
                          ),
                        )
                      else if (isNewCourse)
                        const Positioned(
                          right: 10,
                          top: 10,
                          child: _PosterBadge(
                            label: '新',
                            color: AppDesignTokens.yellow,
                            textColor: AppDesignTokens.textPrimary,
                          ),
                        ),
                      Positioned(
                        left: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppDesignTokens.brandGreen,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: AppDesignTokens.toyButtonShadow,
                          ),
                          child: Text(
                            '${course.episodes.length} 集',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppDesignTokens.appWhite,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, right: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppDesignTokens.pinkLight,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              course.category,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppDesignTokens.textPrimary,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AppDesignTokens.appWhite,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              children: <Widget>[
                                const Icon(
                                  Icons.star_rounded,
                                  size: 14,
                                  color: AppDesignTokens.orange,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  course.rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppDesignTokens.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        course.title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        course.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: AppDesignTokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '来源：${course.sourceLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppDesignTokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: <Widget>[
                          const Text(
                            '学习进度',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppDesignTokens.textSecondary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '已完成 ${course.progressPercent}%',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppDesignTokens.brandGreenDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: course.progressPercent / 100,
                          minHeight: 10,
                          backgroundColor: AppDesignTokens.softGray,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppDesignTokens.brandGreen,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          const Icon(
                            Icons.history_rounded,
                            size: 14,
                            color: AppDesignTokens.primaryBlueDark,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '最近学习：${course.lastStudiedStr}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppDesignTokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosterBadge extends StatelessWidget {
  const _PosterBadge({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
      ),
    );
  }
}
