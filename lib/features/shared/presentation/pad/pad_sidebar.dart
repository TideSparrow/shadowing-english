import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../growth/presentation/growth_provider.dart';
import '../../../navigation/presentation/navigation_destination.dart';
import '../../data/daily_english_service.dart';
import '../../data/word_pronunciation_service.dart';
import 'app_design_tokens.dart';

class PadSidebar extends ConsumerStatefulWidget {
  const PadSidebar({required this.current, super.key});

  final AppNavDestination current;

  @override
  ConsumerState<PadSidebar> createState() => _PadSidebarState();
}

class _PadSidebarState extends ConsumerState<PadSidebar> {
  List<DailyEnglishPhrase>? _dailyPhrases;
  int _dailyPhraseIndex = 0;
  bool _loadingDailyEnglish = false;
  final LayerLink _dailyBubbleLink = LayerLink();
  OverlayEntry? _dailyBubbleEntry;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadDailyEnglish);
  }

  Future<void> _loadDailyEnglish() async {
    if (!mounted || _loadingDailyEnglish || _dailyPhrases != null) return;
    setState(() => _loadingDailyEnglish = true);
    final List<DailyEnglishPhrase> phrases;
    try {
      phrases = await ref.read(dailyEnglishServiceProvider).loadToday();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingDailyEnglish = false);
      return;
    }
    if (!mounted) return;
    setState(() {
      _dailyPhrases = phrases;
      _loadingDailyEnglish = false;
    });
    _dailyBubbleEntry?.markNeedsBuild();
  }

  void _showNextDailyEnglish() {
    if (_dailyBubbleEntry == null) {
      _showDailyEnglishBubble();
      if (_dailyPhrases == null) {
        _loadDailyEnglish();
      }
      return;
    }
    if (_dailyPhrases != null) {
      setState(() => _dailyPhraseIndex = (_dailyPhraseIndex + 1) % 3);
      _dailyBubbleEntry?.markNeedsBuild();
    }
  }

  void _showDailyEnglishBubble() {
    final OverlayState overlay = Overlay.of(context);
    _dailyBubbleEntry = OverlayEntry(
      builder: (BuildContext context) => Stack(
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismissDailyEnglishBubble,
            ),
          ),
          CompositedTransformFollower(
            link: _dailyBubbleLink,
            followerAnchor: Alignment.bottomLeft,
            offset: const Offset(54, -4),
            child: _DailyEnglishBubble(
              compact: MediaQuery.sizeOf(context).width < 1180,
              phrase: _dailyPhrases == null
                  ? null
                  : _dailyPhrases![_dailyPhraseIndex],
              onTap: _dailyPhrases == null
                  ? null
                  : () => ref
                        .read(wordPronunciationServiceProvider)
                        .speak(_dailyPhrases![_dailyPhraseIndex].english),
              onNext: _showNextDailyEnglish,
              onClose: _dismissDailyEnglishBubble,
            ),
          ),
        ],
      ),
    );
    overlay.insert(_dailyBubbleEntry!);
  }

  void _dismissDailyEnglishBubble() {
    _dailyBubbleEntry?.remove();
    _dailyBubbleEntry = null;
  }

  @override
  void dispose() {
    _dailyBubbleEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final UserGrowth growth = ref.watch(userGrowthProvider);
    final double topInset = MediaQuery.paddingOf(context).top;
    final double width = MediaQuery.sizeOf(context).width;
    final bool compact = width < 1180;
    final double windowControlsInset =
        defaultTargetPlatform == TargetPlatform.macOS ? 28 : 0;
    final List<AppNavDestination> items = AppNavDestination.values
        .where(
          (AppNavDestination destination) =>
              destination.showInNav &&
              destination != AppNavDestination.settings,
        )
        .toList(growable: false);

    return Container(
      width: compact ? 196 : 220,
      margin: EdgeInsets.fromLTRB(
        14,
        topInset + windowControlsInset + 14,
        0,
        14,
      ),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(34),
        boxShadow: AppDesignTokens.toyCardShadow,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Column(
            children: <Widget>[
              Padding(
                key: const Key('pad-sidebar-header'),
                padding: EdgeInsets.fromLTRB(
                  compact ? 18 : 24,
                  topInset + (compact ? 20 : 24),
                  compact ? 18 : 24,
                  14,
                ),
                child: Row(
                  children: <Widget>[
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppDesignTokens.skyLight,
                        borderRadius: BorderRadius.all(
                          Radius.circular(compact ? 16 : 18),
                        ),
                        boxShadow: AppDesignTokens.toyCardShadow,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.all(
                          Radius.circular(compact ? 16 : 18),
                        ),
                        child: SizedBox(
                          width: compact ? 44 : 50,
                          height: compact ? 44 : 50,
                          child: Image.asset(
                            'assets/img/app_icon.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: compact ? 10 : 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '语言避难所',
                            style: TextStyle(
                              fontSize: compact ? 16 : 18,
                              fontWeight: FontWeight.w900,
                              color: AppDesignTokens.brandGreenDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '放映室入口',
                            style: TextStyle(
                              fontSize: compact ? 11 : 12,
                              color: AppDesignTokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 12 : 14,
                    16,
                    compact ? 12 : 14,
                    18,
                  ),
                  itemBuilder: (BuildContext context, int index) {
                    final AppNavDestination destination = items[index];
                    final bool selected = destination == widget.current;

                    return InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () {
                        if (!selected) {
                          context.go(destination.route);
                        }
                      },
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: selected
                              ? AppDesignTokens.brandGreen
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: selected
                              ? AppDesignTokens.toyButtonShadow
                              : const <BoxShadow>[],
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 14 : 16,
                            vertical: compact ? 12 : 13,
                          ),
                          child: Row(
                            children: <Widget>[
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: selected
                                      ? AppDesignTokens.appWhite
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: SizedBox(
                                  width: compact ? 36 : 40,
                                  height: compact ? 36 : 40,
                                  child: Icon(
                                    selected
                                        ? destination.activeIcon
                                        : destination.icon,
                                    color: selected
                                        ? AppDesignTokens.brandGreenDark
                                        : AppDesignTokens.textSecondary,
                                    size: compact ? 21 : 23,
                                  ),
                                ),
                              ),
                              SizedBox(width: compact ? 10 : 14),
                              Expanded(
                                child: Text(
                                  destination.label,
                                  style: TextStyle(
                                    fontSize: compact ? 14 : 15,
                                    fontWeight: selected
                                        ? FontWeight.w800
                                        : FontWeight.w700,
                                    color: selected
                                        ? AppDesignTokens.appWhite
                                        : AppDesignTokens.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemCount: items.length,
                ),
              ),
              InkWell(
                key: const Key('pad-sidebar-growth-entry'),
                borderRadius: BorderRadius.circular(24),
                onTap: () => context.go(AppNavDestination.growth.route),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 62 : 70,
                        12,
                        compact ? 18 : 22,
                        52,
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Lv.${growth.level} ${growth.title}',
                                  style: TextStyle(
                                    fontSize: compact ? 13 : 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppDesignTokens.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '连续 ${growth.streakDays} 天 · ${growth.currentXP}/${growth.nextLevelXP} XP',
                                  style: TextStyle(
                                    fontSize: compact ? 11 : 12,
                                    color: AppDesignTokens.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.star_rounded,
                            color: AppDesignTokens.yellow,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: compact ? -48 : -54,
                      bottom: -18,
                      child: CompositedTransformTarget(
                        link: _dailyBubbleLink,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _showNextDailyEnglish,
                          child: SizedBox(
                            key: const Key('pad-sidebar-daily-english-entry'),
                            child: Image.asset(
                              'assets/img/growth-level-${growth.level}.png',
                              key: Key(
                                'pad-sidebar-growth-avatar-${growth.level}',
                              ),
                              width: compact ? 140 : 160,
                              height: compact ? 140 : 160,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            right: 12,
            bottom: 8,
            child: IconButton(
              key: const Key('pad-sidebar-settings-entry'),
              tooltip: '设置',
              isSelected: widget.current == AppNavDestination.settings,
              onPressed: () {
                if (widget.current != AppNavDestination.settings) {
                  context.go(AppNavDestination.settings.route);
                }
              },
              icon: const Icon(Icons.settings_outlined, size: 22),
              selectedIcon: const Icon(Icons.settings_rounded, size: 22),
              style: IconButton.styleFrom(
                minimumSize: const Size(40, 40),
                foregroundColor: widget.current == AppNavDestination.settings
                    ? AppDesignTokens.brandGreenDark
                    : AppDesignTokens.textSecondary,
                backgroundColor: widget.current == AppNavDestination.settings
                    ? AppDesignTokens.brandGreen.withValues(alpha: 0.12)
                    : Colors.transparent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyEnglishBubble extends StatelessWidget {
  const _DailyEnglishBubble({
    required this.compact,
    required this.phrase,
    required this.onTap,
    required this.onNext,
    required this.onClose,
  });

  final bool compact;
  final DailyEnglishPhrase? phrase;
  final VoidCallback? onTap;
  final VoidCallback onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('pad-sidebar-daily-english-bubble'),
        borderRadius: BorderRadius.circular(18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppDesignTokens.appWhite,
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppDesignTokens.toyCardShadow,
          ),
          child: SizedBox(
            width: compact ? 280 : 300,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: phrase == null
                  ? const Text('正在准备今日英语…')
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Expanded(
                              child: Text(
                                '今日英语',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppDesignTokens.brandGreenDark,
                                ),
                              ),
                            ),
                            InkWell(
                              key: const Key('pad-sidebar-daily-english-close'),
                              onTap: onClose,
                              child: const Icon(Icons.close_rounded, size: 17),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          phrase!.english,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          phrase!.translation,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton.icon(
                                key: const Key(
                                  'pad-sidebar-daily-english-play',
                                ),
                                onPressed: onTap,
                                icon: const Icon(Icons.volume_up_rounded),
                                label: const Text('播放声音'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: onNext,
                              child: const Text('换一句'),
                            ),
                          ],
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
