import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../library_mock_data.dart';

class EpisodeListItem extends StatelessWidget {
  const EpisodeListItem({
    required this.item,
    required this.selected,
    required this.onTap,
    this.onViewTranscript,
    this.trailing,
    super.key,
  });

  final LibraryEpisodeItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onViewTranscript;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final bool inProgress = item.progressPercent > 0 && !item.completed;
    final bool notStarted = !item.completed && item.progressPercent == 0;
    final String statusText = item.completed
        ? '已完成'
        : inProgress
        ? _progressStatusText(item)
        : '开始学习';

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
            600;
        final Widget details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              item.title,
              maxLines: narrow ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: narrow ? 17 : 20,
                fontWeight: FontWeight.w900,
                color: AppDesignTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _StatusChip(
                  icon: item.completed
                      ? Icons.check_circle_rounded
                      : inProgress
                      ? Icons.play_circle_rounded
                      : Icons.bolt_rounded,
                  label: statusText,
                  backgroundColor: selected
                      ? const Color(0xFFDDF7E8)
                      : AppDesignTokens.softWhite,
                  textColor: AppDesignTokens.brandGreenDark,
                ),
                if (item.videoMissing)
                  const _InfoChip(
                    icon: Icons.warning_amber_rounded,
                    label: '文件缺失',
                    backgroundColor: Color(0xFFFFE1E1),
                    textColor: Color(0xFFBA1A1A),
                  ),
                _InfoChip(
                  icon: Icons.closed_caption_rounded,
                  label: item.hasEnglishSubtitles ? '英文字幕' : '无外部英文字幕',
                ),
                _InfoChip(
                  icon: item.hasChineseSubtitles
                      ? Icons.translate_rounded
                      : Icons.warning_rounded,
                  label: item.hasChineseSubtitles ? '中文字幕' : '无中文字幕',
                  backgroundColor: item.hasChineseSubtitles
                      ? AppDesignTokens.pinkLight
                      : const Color(0xFFFFE1E1),
                  textColor: item.hasChineseSubtitles
                      ? AppDesignTokens.textPrimary
                      : const Color(0xFFBA1A1A),
                ),
                _InfoChip(
                  icon: Icons.schedule_rounded,
                  label: '${item.durationMinutes} 分钟',
                  textColor: AppDesignTokens.textSecondary,
                ),
                if ((item.lastWatchedStr ?? '').isNotEmpty)
                  _InfoChip(
                    icon: Icons.history_rounded,
                    label: item.lastWatchedStr!,
                    backgroundColor: AppDesignTokens.purpleLight,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: item.progressPercent / 100,
                minHeight: 10,
                backgroundColor: AppDesignTokens.softGray,
                valueColor: AlwaysStoppedAnimation<Color>(
                  item.completed
                      ? AppDesignTokens.primaryBlue
                      : AppDesignTokens.brandGreen,
                ),
              ),
            ),
          ],
        );
        final Widget number = Container(
          width: narrow ? 48 : 64,
          height: narrow ? 48 : 64,
          decoration: BoxDecoration(
            color: selected
                ? AppDesignTokens.brandGreen
                : AppDesignTokens.skyLight,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Text(
              item.numberStr,
              style: TextStyle(
                fontSize: narrow ? 20 : 24,
                fontWeight: FontWeight.w900,
                color: selected
                    ? Colors.white
                    : AppDesignTokens.primaryBlueDark,
              ),
            ),
          ),
        );
        final Widget playIndicator = Icon(
          selected
              ? Icons.play_circle_fill_rounded
              : notStarted
              ? Icons.arrow_forward_rounded
              : Icons.chevron_right_rounded,
          size: 28,
          color: selected
              ? AppDesignTokens.brandGreenDark
              : AppDesignTokens.primaryBlueDark,
        );
        final Widget? transcriptButton = onViewTranscript == null
            ? null
            : OutlinedButton.icon(
                key: ValueKey<String>('episode-view-transcript-${item.id}'),
                onPressed: onViewTranscript,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                icon: const Icon(Icons.menu_book_rounded, size: 18),
                label: const Text('查看全文'),
              );
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(26),
          child: Ink(
            padding: EdgeInsets.all(narrow ? 14 : 18),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFFEFFFF5)
                  : AppDesignTokens.appWhite,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: selected
                    ? AppDesignTokens.brandGreen
                    : AppDesignTokens.borderGray,
                width: selected ? 2 : 1.2,
              ),
              boxShadow: AppDesignTokens.toyCardShadow,
            ),
            child: narrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          number,
                          const Spacer(),
                          trailing ?? playIndicator,
                        ],
                      ),
                      const SizedBox(height: 12),
                      details,
                      if (transcriptButton != null) ...<Widget>[
                        const SizedBox(height: 12),
                        transcriptButton,
                      ],
                    ],
                  )
                : Row(
                    children: <Widget>[
                      number,
                      const SizedBox(width: 16),
                      Expanded(child: details),
                      if (transcriptButton != null) ...<Widget>[
                        const SizedBox(width: 12),
                        transcriptButton,
                      ],
                      const SizedBox(width: 16),
                      trailing ?? playIndicator,
                    ],
                  ),
          ),
        );
      },
    );
  }

  String _progressStatusText(LibraryEpisodeItem item) {
    final int totalSeconds = item.durationMinutes * 60;
    final int progressSeconds = (totalSeconds * item.progressPercent / 100)
        .round();
    final String progress = (item.progressTimeStr?.isNotEmpty ?? false)
        ? item.progressTimeStr!
        : _formatSeconds(progressSeconds);
    final String total = (item.totalTimeStr?.isNotEmpty ?? false)
        ? item.totalTimeStr!
        : _formatSeconds(totalSeconds);
    return '$progress / $total';
  }

  String _formatSeconds(int totalSeconds) {
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    this.backgroundColor = AppDesignTokens.softWhite,
    this.textColor = AppDesignTokens.textPrimary,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
