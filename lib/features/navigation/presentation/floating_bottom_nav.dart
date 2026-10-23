import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import 'navigation_destination.dart';

class FloatingBottomNav extends StatelessWidget {
  const FloatingBottomNav({required this.current, super.key});

  final AppNavDestination current;

  static const List<AppNavDestination> _primaryDestinations =
      <AppNavDestination>[
        AppNavDestination.home,
        AppNavDestination.library,
        AppNavDestination.growth,
        AppNavDestination.review,
      ];

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final double width = size.width;
    final bool compact = width < 768;
    final bool useMoreMenu = size.height > size.width;
    final List<AppNavDestination> allDestinations = AppNavDestination.values
        .where((AppNavDestination destination) => destination.showInNav)
        .toList(growable: false);
    final List<AppNavDestination> destinations = allDestinations
        .where((AppNavDestination destination) => destination.showInBottomNav)
        .toList(growable: false);
    final List<AppNavDestination> secondaryDestinations = allDestinations
        .where(
          (AppNavDestination destination) =>
              !_primaryDestinations.contains(destination),
        )
        .toList(growable: false);
    final List<AppNavDestination> visibleDestinations = useMoreMenu
        ? _primaryDestinations
        : destinations;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 16,
        compact ? 8 : 12,
        compact ? 10 : 16,
        compact ? 10 : 16,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(compact ? 22 : 28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppDesignTokens.appWhite.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(compact ? 22 : 28),
              boxShadow: AppDesignTokens.toyCardShadow,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 4 : 8,
                vertical: compact ? 6 : 8,
              ),
              child: Row(
                children: <Widget>[
                  ...visibleDestinations.map<Widget>(
                    (AppNavDestination destination) => Expanded(
                      child: _NavItem(
                        destination: destination,
                        selected: destination == current,
                      ),
                    ),
                  ),
                  if (useMoreMenu)
                    Expanded(
                      child: _MoreNavItem(
                        selected: secondaryDestinations.contains(current),
                        destinations: secondaryDestinations,
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

class _MoreNavItem extends StatelessWidget {
  const _MoreNavItem({required this.selected, required this.destinations});

  final bool selected;
  final List<AppNavDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 768;
    return InkWell(
      key: const Key('bottom-nav-more'),
      borderRadius: BorderRadius.circular(compact ? 16 : 20),
      onTap: () => _showMoreMenu(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 2 : 4,
          vertical: compact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: selected ? AppDesignTokens.brandGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(compact ? 16 : 20),
          boxShadow: selected ? AppDesignTokens.toyButtonShadow : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: compact ? 30 : 34,
              height: compact ? 30 : 34,
              child: selected
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppDesignTokens.appWhite,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.grid_view_rounded,
                        size: compact ? 18 : 20,
                        color: AppDesignTokens.brandGreenDark,
                      ),
                    )
                  : Icon(
                      Icons.grid_view_outlined,
                      size: compact ? 18 : 20,
                      color: AppDesignTokens.textSecondary,
                    ),
            ),
            SizedBox(height: compact ? 3 : 4),
            Text(
              '更多',
              style: TextStyle(
                color: selected
                    ? AppDesignTokens.appWhite
                    : AppDesignTokens.textSecondary,
                fontSize: compact ? 10 : 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMoreMenu(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '更多功能',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              ...destinations.map(
                (AppNavDestination destination) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(destination.icon),
                  title: Text(destination.label),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    context.go(destination.route);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.destination, required this.selected});

  final AppNavDestination destination;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final bool compact = width < 768;

    return InkWell(
      borderRadius: BorderRadius.circular(compact ? 16 : 20),
      onTap: () => context.go(destination.route),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 2 : 4,
          vertical: compact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: selected ? AppDesignTokens.brandGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(compact ? 16 : 20),
          boxShadow: selected ? AppDesignTokens.toyButtonShadow : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: compact ? 30 : 34,
              height: compact ? 30 : 34,
              child: selected
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppDesignTokens.appWhite,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        destination.activeIcon,
                        size: compact ? 18 : 20,
                        color: AppDesignTokens.brandGreenDark,
                      ),
                    )
                  : Icon(
                      destination.icon,
                      size: compact ? 18 : 20,
                      color: AppDesignTokens.textSecondary,
                    ),
            ),
            SizedBox(height: compact ? 3 : 4),
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? AppDesignTokens.appWhite
                    : AppDesignTokens.textSecondary,
                fontSize: compact ? 10 : 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
