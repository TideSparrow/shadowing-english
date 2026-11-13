import 'package:flutter/material.dart';

import 'pad_landscape_player_screen.dart';
import 'pad_portrait_player_screen.dart';
import 'player_mock_state.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    required this.episodeId,
    this.initialStartTime,
    this.autoPlay = false,
    this.autoOpenFullscreen = false,
    super.key,
  });

  final String episodeId;
  final String? initialStartTime;
  final bool autoPlay;
  final bool autoOpenFullscreen;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool? _portraitLayout;
  late PlayerMockState _playerState = PlayerMockState(
    initialStartTime: widget.initialStartTime,
  );

  @override
  void didUpdateWidget(covariant PlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episodeId != widget.episodeId) {
      _playerState = PlayerMockState(initialStartTime: widget.initialStartTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    // A fullscreen route still owns this layout's video player and callbacks.
    // Apply rotation after it closes, rather than disposing its player beneath it.
    if (_portraitLayout == null ||
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      _portraitLayout = size.height > size.width;
    }
    final bool isPortrait = _portraitLayout!;

    if (isPortrait) {
      return PadPortraitPlayerScreen(
        key: ValueKey<String>(widget.episodeId),
        episodeId: widget.episodeId,
        playerState: _playerState,
        initialStartTime: widget.initialStartTime,
        autoPlay: widget.autoPlay,
        autoOpenFullscreen: widget.autoOpenFullscreen,
      );
    }

    return PadLandscapePlayerScreen(
      key: ValueKey<String>(widget.episodeId),
      episodeId: widget.episodeId,
      playerState: _playerState,
      initialStartTime: widget.initialStartTime,
      autoPlay: widget.autoPlay,
      autoOpenFullscreen: widget.autoOpenFullscreen,
    );
  }
}
