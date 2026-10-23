import 'package:flutter/material.dart';

import '../../../navigation/presentation/floating_bottom_nav.dart';
import '../../../navigation/presentation/navigation_destination.dart';
import '../continue_learning_button.dart';
import 'app_design_tokens.dart';
import 'pad_sidebar.dart';

class PadScaffold extends StatelessWidget {
  const PadScaffold({
    required this.currentDestination,
    required this.body,
    super.key,
    this.topBar,
    this.useBottomTabWhenPortrait = true,
    this.showNavigation = true,
    this.showContinueLearning = true,
  });

  final AppNavDestination currentDestination;
  final Widget body;
  final Widget? topBar;
  final bool useBottomTabWhenPortrait;
  final bool showNavigation;
  final bool showContinueLearning;

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final bool isPortrait = size.height > size.width;
    final bool useBottomNavigation = size.width < 840 || isPortrait;
    final Widget content = _PadBackdrop(
      child: Column(
        children: <Widget>[
          if (topBar != null) topBar!,
          Expanded(child: body),
        ],
      ),
    );

    if (showNavigation && useBottomNavigation && useBottomTabWhenPortrait) {
      return Scaffold(
        backgroundColor: AppDesignTokens.softWhite,
        floatingActionButton: showContinueLearning
            ? const ContinueLearningButton()
            : null,
        body: SafeArea(top: false, bottom: false, child: content),
        bottomNavigationBar: FloatingBottomNav(current: currentDestination),
      );
    }

    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      floatingActionButton: showContinueLearning
          ? const ContinueLearningButton()
          : null,
      body: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            if (showNavigation) PadSidebar(current: currentDestination),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

class _PadBackdrop extends StatelessWidget {
  const _PadBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 840;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFF9FBFF),
            Color(0xFFFFFCF5),
            AppDesignTokens.softWhite,
          ],
        ),
      ),
      child: Stack(
        children: <Widget>[
          if (!compact) ...<Widget>[
            Positioned(
              left: -36,
              top: 88,
              child: _BackdropBubble(
                size: 160,
                color: AppDesignTokens.skyLight.withValues(alpha: 0.72),
              ),
            ),
            Positioned(
              right: 36,
              top: 112,
              child: _BackdropBubble(
                size: 92,
                color: AppDesignTokens.pinkLight.withValues(alpha: 0.6),
              ),
            ),
            Positioned(
              right: -18,
              bottom: 42,
              child: _BackdropBubble(
                size: 144,
                color: AppDesignTokens.purpleLight.withValues(alpha: 0.42),
              ),
            ),
          ],
          child,
        ],
      ),
    );
  }
}

class _BackdropBubble extends StatelessWidget {
  const _BackdropBubble({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
