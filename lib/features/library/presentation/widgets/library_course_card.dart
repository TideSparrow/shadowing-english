import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../library_mock_data.dart';
import 'library_course_poster.dart';

class LibraryCourseCard extends StatelessWidget {
  const LibraryCourseCard({
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              height: 176,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                      child: LibraryCoursePoster(
                        title: course.title,
                        path: course.coverImage,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(32),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(32),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            AppDesignTokens.appWhite.withValues(alpha: 0.02),
                            Colors.black.withValues(alpha: 0.45),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 14,
                    left: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppDesignTokens.appWhite.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          course.level,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppDesignTokens.primaryBlueDark,
                          ),
                        ),
                      ),
                  ),
                  if (selectionMode)
                    Positioned(
                      top: 14,
                      right: 14,
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
                    Positioned(
                      top: 14,
                      right: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppDesignTokens.yellow,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          '新',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 14,
                    child: Row(
                      children: <Widget>[
                        Container(
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
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
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
                            color: AppDesignTokens.appWhite.withValues(alpha: 0.92),
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
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  const SizedBox(height: 10),
                  Text(
                    course.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
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
          ],
        ),
      ),
    );
  }
}
