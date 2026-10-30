import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../home/presentation/learning_dashboard_provider.dart';
import 'app_design_tokens.dart';

class PadTopBar extends ConsumerWidget {
  const PadTopBar({
    required this.title,
    super.key,
    this.leading,
    this.trailing,
    this.actions = const <Widget>[],
    this.subtitle,
    this.description,
    this.onTimerPressed,
    this.onStreakPressed,
  });

  final String title;
  final String? subtitle;
  final String? description;
  final Widget? leading;
  final Widget? trailing;
  final List<Widget> actions;
  final VoidCallback? onTimerPressed;
  final VoidCallback? onStreakPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LearningDashboardStats dashboard = ref.watch(
      learningDashboardProvider,
    );
    final double topInset = MediaQuery.paddingOf(context).top;
    final double windowControlsInset =
        defaultTargetPlatform == TargetPlatform.macOS ? 28 : 0;
    final double width = MediaQuery.sizeOf(context).width;
    final bool compact = width < 1180;

    final bool hasDescription = description != null;
    final double contentHeight = hasDescription
        ? (compact ? 88 : 96)
        : subtitle != null
        ? (compact ? 72 : 80)
        : (compact ? 64 : 72);

    return Container(
      height:
          contentHeight *
              MediaQuery.textScalerOf(
                context,
              ).scale(1).clamp(1.0, double.infinity) +
          topInset +
          windowControlsInset,
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 22,
        topInset + windowControlsInset + 6,
        compact ? 16 : 22,
        0,
      ),
      color: Colors.transparent,
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading!,
            SizedBox(width: compact ? 10 : 12),
          ],
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (subtitle != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppDesignTokens.skyLight,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppDesignTokens.primaryBlueDark,
                        ),
                      ),
                    ),
                  if (subtitle != null) const SizedBox(height: 6),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 20 : 24,
                      fontWeight: FontWeight.w900,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                  if (hasDescription) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 13 : 14,
                        fontWeight: FontWeight.w600,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          ...actions,
          if (actions.isNotEmpty) const SizedBox(width: 8),
          if (trailing != null)
            trailing!
          else
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 12,
                vertical: compact ? 8 : 10,
              ),
              decoration: BoxDecoration(
                color: AppDesignTokens.appWhite.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(999),
                boxShadow: AppDesignTokens.toyCardShadow,
              ),
              child: _DefaultStatusChips(
                streakLabel: '${dashboard.streakDays}',
                timerLabel: '${dashboard.todayStudyMinutes}m',
                onStreakPressed:
                    onStreakPressed ??
                    () => _showLearningStatus(context, dashboard),
                onTimerPressed:
                    onTimerPressed ??
                    () => _showLearningStatus(context, dashboard),
              ),
            ),
        ],
      ),
    );
  }
}

void _showLearningStatus(
  BuildContext context,
  LearningDashboardStats dashboard,
) {
  showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('今日学习状态'),
      content: Text(
        '今日学习 ${dashboard.todayStudyMinutes} 分钟 · '
        '${dashboard.todaySentenceCount} 句 · '
        '收藏 ${dashboard.todaySavedPhrases} 条\n\n'
        '连续学习 ${dashboard.streakDays} 天\n'
        '累计学习 ${dashboard.totalStudyMinutes} 分钟\n\n'
        '${dashboard.checkedIn ? '今天已完成打卡。' : '再学习 ${dashboard.remainingMinutesToCheckIn} 分钟可通过时长完成今日打卡。'}',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

class PadBackButton extends StatelessWidget {
  const PadBackButton({
    required this.onPressed,
    this.tooltip = '返回上一页',
    super.key,
  });

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: AppDesignTokens.appWhite,
          foregroundColor: AppDesignTokens.brandGreenDark,
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          side: const BorderSide(color: AppDesignTokens.borderGray),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: const Icon(Icons.arrow_back_rounded, size: 18),
      ),
    );
  }
}

class _DefaultStatusChips extends StatelessWidget {
  const _DefaultStatusChips({
    required this.streakLabel,
    required this.timerLabel,
    this.onStreakPressed,
    this.onTimerPressed,
  });

  final String streakLabel;
  final String timerLabel;
  final VoidCallback? onStreakPressed;
  final VoidCallback? onTimerPressed;

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 1180;
    return Row(
      children: <Widget>[
        _StatusAction(
          key: const Key('pad-status-streak'),
          icon: Icons.local_fire_department_rounded,
          color: AppDesignTokens.orange,
          background: const Color(0xFFFFF1D6),
          label: streakLabel,
          onPressed: onStreakPressed,
        ),
        SizedBox(width: compact ? 8 : 10),
        _StatusAction(
          key: const Key('pad-status-timer'),
          icon: Icons.timer_outlined,
          color: AppDesignTokens.primaryBlueDark,
          background: AppDesignTokens.skyLight,
          label: timerLabel,
          onPressed: onTimerPressed,
        ),
      ],
    );
  }
}

class _StatusAction extends StatelessWidget {
  const _StatusAction({
    super.key,
    required this.icon,
    required this.color,
    required this.background,
    required this.label,
    this.onPressed,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 1180;
    final Widget child = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: compact ? 16 : 18, color: color),
          SizedBox(width: compact ? 4 : 6),
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
    if (onPressed == null) {
      return child;
    }
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(999),
      child: child,
    );
  }
}
