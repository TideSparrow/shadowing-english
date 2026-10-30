import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/widgets/player_video_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('current sentence action stays above controls and is tappable', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final ({Size size, bool fullscreen}) example
        in <({Size size, bool fullscreen})>[
          (size: const Size(320, 180), fullscreen: false),
          (size: const Size(800, 474), fullscreen: false),
          (size: const Size(1280, 720), fullscreen: true),
        ]) {
      int assessments = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox.fromSize(
                size: example.size,
                child: PlayerVideoPanel(
                  line: const PlayerSubtitleLine(
                    startTime: '00:00',
                    english: 'Take a break.',
                    chinese: '',
                    startMs: 600,
                    endMs: 1551,
                  ),
                  isPlaying: false,
                  subtitleMode: '单英',
                  subtitleModes: const <String>['单英'],
                  speed: '1.0×',
                  isShadowing: false,
                  isLooping: false,
                  isMuted: false,
                  volumeLevel: 1,
                  activeIndex: 0,
                  totalLines: 1,
                  isFullscreen: example.fullscreen,
                  onAssessVisibleLine: () => assessments++,
                  onTogglePlaying: () {},
                  onPreviousLine: () {},
                  onReplayLine: () {},
                  onNextLine: () {},
                  onSeekBackward: () {},
                  onSeekForward: () {},
                  onSelectLine: (int _) {},
                  onSeek: (double _) {},
                  onSpeedSelected: (String _) {},
                  onSelectSubtitleMode: (String _) {},
                  onToggleShadowing: () {},
                  onToggleLoop: () {},
                  onToggleMuted: () {},
                  onVolumeChanged: (double _) {},
                  onToggleFullscreen: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final Finder action = find.byKey(
        ValueKey<String>(
          example.fullscreen
              ? 'fullscreen-visible-pronunciation-assessment'
              : 'player-visible-pronunciation-assessment',
        ),
      );
      expect(
        tester.getRect(action).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(Slider)).top),
      );
      expect(
        tester
            .widget<Icon>(
              find.descendant(of: action, matching: find.byType(Icon)),
            )
            .icon,
        Icons.mic_rounded,
      );
      expect(tester.getSize(action).width, lessThanOrEqualTo(56));
      await tester.tap(action);
      await tester.pump();
      expect(assessments, 1);
      expect(tester.takeException(), isNull);
    }
  });
}
