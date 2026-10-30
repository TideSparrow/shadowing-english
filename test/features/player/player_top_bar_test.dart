import 'package:common_learn_english/features/player/presentation/widgets/player_top_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final double width in <double>[320, 390]) {
    testWidgets('phone actions fit at width $width with larger text', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      bool openedTranscript = false;
      bool openedGuide = false;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 844),
              textScaler: const TextScaler.linear(1.3),
            ),
            child: Scaffold(
              body: PlayerTopBar(
                courseTitle: '小谢尔顿第一季',
                episodeTitle: '第 1720 集',
                episodeName: 'A very long episode name',
                onBack: () {},
                onTranscriptPressed: () => openedTranscript = true,
                onLearningGuidePressed: () => openedGuide = true,
                onStatsPressed: () {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('第 1720 集'), findsOneWidget);
      await tester.tap(find.byTooltip('全文阅读'));
      await tester.tap(find.byTooltip('怎么学'));
      expect(openedTranscript, isTrue);
      expect(openedGuide, isTrue);
    });
  }

  testWidgets('clears the macOS window controls', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerTopBar(
              courseTitle: '课程',
              episodeTitle: '第 01 集',
              onBack: () {},
            ),
          ),
        ),
      );

      expect(
        tester.getTopLeft(find.byType(TextButton)).dy,
        greaterThanOrEqualTo(28),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
