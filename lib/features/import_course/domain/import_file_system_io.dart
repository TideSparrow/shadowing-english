import 'dart:convert';
import 'dart:io';

List<String> listFilesSync(String folderPath, Set<String> allowedExtensions) {
  final Directory directory = Directory(folderPath);
  if (!directory.existsSync()) {
    return const <String>[];
  }

  return directory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .map((File file) => file.path)
      .where((String path) {
        final String lower = path.toLowerCase();
        return allowedExtensions.any(lower.endsWith);
      })
      .toList(growable: false);
}

String readTextFileSnippetSync(String filePath, {int maxChars = 1200}) {
  if (maxChars <= 0) return '';
  final File file = File(filePath);
  if (!file.existsSync()) {
    return '';
  }

  RandomAccessFile? handle;
  try {
    handle = file.openSync();
    // A UTF-8 character needs at most four bytes. Never load the entire file
    // just to identify the subtitle language; the last character may be cut.
    final String content = utf8.decode(
      handle.readSync(maxChars * 4),
      allowMalformed: true,
    );
    if (content.length <= maxChars) {
      return content;
    }
    return content.substring(0, maxChars);
  } catch (_) {
    return '';
  } finally {
    handle?.closeSync();
  }
}
