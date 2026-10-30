import 'package:common_learn_english/features/player/presentation/player_graphics_cache.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('only trims after the last player releases its resources', (
    WidgetTester tester,
  ) async {
    final List<MethodCall> calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.skia,
      (MethodCall call) async => calls.add(call),
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.skia,
        null,
      );
    });
    final Future<void> Function() first = PlayerGraphicsCache.acquire();
    final Future<void> Function() second = PlayerGraphicsCache.acquire();
    await first();
    await first(); // Repeated cleanup must not release another screen's lease.
    expect(calls, isEmpty);
    final Future<void> finished = second();
    expect(calls, isEmpty); // The old texture is still in the rendered frame.
    await tester.pump();
    await finished;
    expect(
      calls.map((MethodCall call) => call.method),
      everyElement('Skia.setResourceCacheMaxBytes'),
    );
    expect(calls.map((MethodCall call) => call.arguments), <int>[0, 67108864]);
  });

  testWidgets('starting another player cancels a pending idle trim', (
    WidgetTester tester,
  ) async {
    final List<MethodCall> calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.skia,
      (MethodCall call) async => calls.add(call),
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.skia,
        null,
      );
    });
    final Future<void> Function() first = PlayerGraphicsCache.acquire();
    final Future<void> finished = first();
    final Future<void> Function() next = PlayerGraphicsCache.acquire();
    await tester.pump();
    await finished;
    expect(calls, isEmpty);
    final Future<void> nextFinished = next();
    await tester.pump();
    await nextFinished;
    expect(calls.length, 2);
  });

  testWidgets('unsupported renderer cache does not fail player cleanup', (
    WidgetTester tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.skia,
      (MethodCall call) async => throw PlatformException(code: 'unsupported'),
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.skia,
        null,
      );
    });
    final Future<void> Function() release = PlayerGraphicsCache.acquire();
    final Future<void> finished = release();
    await tester.pump();
    await finished;
  });
}
