import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:common_learn_english/features/shared/presentation/media/cover_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('large covers decode as sharp thumbnails without distortion', (
    WidgetTester tester,
  ) async {
    final Directory temporary = Directory.systemTemp.createTempSync(
      'cover-size-',
    );
    addTearDown(() => temporary.deleteSync(recursive: true));
    final File source = File('${temporary.path}/large.png');
    await tester.runAsync(() => _writeImage(source, 4000, 3000));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 2),
          child: Center(
            child: SizedBox(
              width: 200,
              height: 150,
              child: CoverImage(path: source.path, fit: BoxFit.cover),
            ),
          ),
        ),
      ),
    );

    final Image image = tester.widget<Image>(find.byType(Image));
    final ui.Size decoded = (await tester.runAsync(
      () => _decodedSize(image.image),
    ))!;
    expect(decoded.width, greaterThanOrEqualTo(400));
    expect(decoded.width, lessThanOrEqualTo(448));
    expect(decoded.aspectRatio, closeTo(4 / 3, 0.01));
    expect(decoded.width * decoded.height * 4, lessThan(650000));
    // The same 4000 x 3000 source used to occupy 48,000,000 decoded bytes.
    await tester.pumpWidget(const SizedBox.shrink());
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('small covers are not enlarged in the decoded cache', (
    WidgetTester tester,
  ) async {
    final Directory temporary = Directory.systemTemp.createTempSync(
      'cover-small-',
    );
    addTearDown(() => temporary.deleteSync(recursive: true));
    final File source = File('${temporary.path}/small.png');
    await tester.runAsync(() => _writeImage(source, 40, 30));
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 150,
            child: CoverImage(path: source.path, fit: BoxFit.cover),
          ),
        ),
      ),
    );
    final Image image = tester.widget<Image>(find.byType(Image));
    expect(
      await tester.runAsync(() => _decodedSize(image.image)),
      const ui.Size(40, 30),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
}

Future<void> _writeImage(File file, int width, int height) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(width, height);
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  await file.writeAsBytes(data!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
}

Future<ui.Size> _decodedSize(ImageProvider<Object> provider) async {
  await provider.evict();
  final Completer<ui.Size> result = Completer<ui.Size>();
  final ImageStream stream = provider.resolve(ImageConfiguration.empty);
  final ImageStreamListener listener = ImageStreamListener(
    (ImageInfo info, bool synchronousCall) {
      if (!result.isCompleted) {
        result.complete(
          ui.Size(info.image.width.toDouble(), info.image.height.toDouble()),
        );
      }
      info.dispose();
    },
    onError: result.completeError,
  );
  stream.addListener(listener);
  try {
    return await result.future.timeout(const Duration(seconds: 10));
  } finally {
    stream.removeListener(listener);
  }
}
