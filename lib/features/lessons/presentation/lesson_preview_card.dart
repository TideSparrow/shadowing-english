import 'package:flutter/material.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../domain/lesson_summary.dart';

class LessonPreviewCard extends StatelessWidget {
  const LessonPreviewCard({
    required this.lesson,
    required this.onOpen,
    required this.onDelete,
    super.key,
  });
  final LessonSummary lesson;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFFFFBF3),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xFFEEDFC5)),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    lesson.focuses.isEmpty ? '这句，讲明白' : lesson.focuses.first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 24,
                      height: 1.3,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFC83B2E),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${lesson.cardCount} 张卡片',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF52652E),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(width: 60, height: 3, color: const Color(0xFFF3C760)),
            const SizedBox(height: 10),
            Text(
              lesson.english,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 17,
                height: 1.35,
                fontWeight: FontWeight.w800,
                color: AppDesignTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              lesson.meaning,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Color(0xFF665644),
              ),
            ),
            const Spacer(),
            const Divider(color: Color(0xFFEEDFC5), height: 16),
            Text(
              '${lesson.courseTitle} · ${lesson.episodeTitle}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF776A59)),
            ),
            const SizedBox(height: 2),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.volume_up_outlined,
                  size: 16,
                  color: Color(0xFF52652E),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '含讲解稿 · ${lesson.timeLabel}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF52652E),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onDelete,
                  tooltip: '删除精讲',
                  icon: const Icon(Icons.delete_outline, size: 19),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
