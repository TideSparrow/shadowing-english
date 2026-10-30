import 'dart:convert';
import 'dart:io';

import 'package:common_learn_english/features/import_course/domain/import_file_system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads a bounded UTF-8 prefix without decoding the rest of a file', () {
    final Directory root = Directory.systemTemp.createTempSync(
      'subtitle-snippet-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File file = File('${root.path}/large.srt');
    file.openSync(mode: FileMode.write)
      ..writeFromSync(utf8.encode('Hello 世界\n'))
      ..setPositionSync(4 * 1024 * 1024)
      ..writeByteSync(255)
      ..closeSync();
    expect(readTextFileSnippetSync(file.path, maxChars: 8), 'Hello 世界');
    expect(readTextFileSnippetSync(file.path, maxChars: 0), isEmpty);
    expect(readTextFileSnippetSync('${root.path}/missing'), isEmpty);
  });

  test('does not traverse linked directories outside the selected folder', () {
    if (Platform.isWindows) {
      return; // Windows link creation may require elevation.
    }
    final Directory root = Directory.systemTemp.createTempSync('import-links-');
    addTearDown(() => root.deleteSync(recursive: true));
    final Directory selected = Directory('${root.path}/selected')..createSync();
    final Directory outside = Directory('${root.path}/outside')..createSync();
    File('${outside.path}/lesson.mkv').createSync();
    Link('${selected.path}/linked').createSync(outside.path);
    expect(listFilesSync(selected.path, <String>{'.mkv'}), isEmpty);
  });
}
