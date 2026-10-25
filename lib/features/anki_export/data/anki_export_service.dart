import 'dart:ui' show Rect;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../phrases/presentation/phrase_book_provider.dart';
import '../../words/data/offline_word_dictionary.dart';
import '../../words/presentation/word_book_provider.dart';
import '../domain/anki_export_encoder.dart';
import '../domain/anki_export_note.dart';
import 'anki_export_builder.dart';
import 'anki_sqlite.dart';

final Provider<AnkiExportService> ankiExportServiceProvider =
    Provider<AnkiExportService>(
      (Ref ref) => AnkiExportService(
        AnkiExportBuilder(ref.watch(offlineWordDictionaryProvider)),
      ),
    );
final Provider<AnkiExportSaver> ankiExportSaverProvider =
    Provider<AnkiExportSaver>((Ref ref) => AnkiExportSaver());

class AnkiExportFile {
  const AnkiExportFile({
    required this.bytes,
    required this.name,
    required this.mimeType,
    required this.noteCount,
  });
  final Uint8List bytes;
  final String name;
  final String mimeType;
  final int noteCount;
}

class AnkiExportService {
  AnkiExportService(this.builder);
  final AnkiExportBuilder builder;

  Future<AnkiExportFile> generate({
    required List<WordEntry> words,
    required List<PhraseEntry> phrases,
    required AnkiExportFormat format,
    required String deckName,
    String subtitleLetterCase = '保留原样',
  }) async {
    final List<AnkiExportNote> notes = await builder.build(
      words: words,
      phrases: phrases,
      subtitleLetterCase: subtitleLetterCase,
    );
    if (notes.isEmpty) throw StateError('没有可导出的收藏内容。');
    final DateTime now = DateTime.now();
    final AnkiExportEncoder encoder = AnkiExportEncoder();
    final Uint8List bytes = format == AnkiExportFormat.apkg
        ? encoder.encodePackage(
            notes,
            sqlite: await loadAnkiSqlite(),
            deckName: deckName.trim().isEmpty
                ? 'Shadowing English'
                : deckName.trim(),
            now: now,
          )
        : encoder.encodeText(notes, format);
    final String stamp = now
        .toIso8601String()
        .split('.')
        .first
        .replaceAll(RegExp('[-:T]'), '');
    return AnkiExportFile(
      bytes: bytes,
      name: 'Shadowing-English-$stamp.${format.name}',
      mimeType: switch (format) {
        AnkiExportFormat.apkg => 'application/octet-stream',
        AnkiExportFormat.tsv => 'text/tab-separated-values',
        AnkiExportFormat.csv => 'text/csv',
      },
      noteCount: notes.length,
    );
  }
}

enum AnkiSaveResult { saved, shared, cancelled, handedOff }

class AnkiExportSaver {
  Future<AnkiSaveResult> save(
    AnkiExportFile file, {
    required Rect origin,
  }) async {
    final XFile xfile = XFile.fromData(
      file.bytes,
      name: file.name,
      mimeType: file.mimeType,
    );
    if (kIsWeb) {
      await xfile.saveTo(file.name);
      return AnkiSaveResult.saved;
    }
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      final ShareResult result = await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[xfile],
          fileNameOverrides: <String>[file.name],
          sharePositionOrigin: origin,
        ),
      );
      return switch (result.status) {
        ShareResultStatus.dismissed => AnkiSaveResult.cancelled,
        ShareResultStatus.success => AnkiSaveResult.shared,
        ShareResultStatus.unavailable => AnkiSaveResult.handedOff,
      };
    }
    final FileSaveLocation? location = await getSaveLocation(
      suggestedName: file.name,
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(
          label: 'Anki 导出文件',
          extensions: <String>[file.name.split('.').last],
        ),
      ],
    );
    if (location == null) return AnkiSaveResult.cancelled;
    await xfile.saveTo(location.path);
    return AnkiSaveResult.saved;
  }
}
