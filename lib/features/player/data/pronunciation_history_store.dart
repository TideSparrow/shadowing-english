import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/pronunciation_assessment.dart';

final Provider<PronunciationHistoryStore> pronunciationHistoryStoreProvider =
    Provider<PronunciationHistoryStore>(
      (Ref ref) => const PronunciationHistoryStore(),
    );

class PronunciationHistoryEntry {
  const PronunciationHistoryEntry({
    required this.directory,
    required this.recordedAt,
    required this.result,
  });

  final Directory directory;
  final DateTime recordedAt;
  final PronunciationAssessmentResult result;

  File get recordingFile => File('${directory.path}/recording.wav');
}

class PronunciationHistoryStore {
  const PronunciationHistoryStore({
    this.supportDirectory = getApplicationSupportDirectory,
  });

  final Future<Directory> Function() supportDirectory;

  Future<Directory> _directory(PronunciationAssessmentTarget target) async {
    final Directory base = await supportDirectory();
    final String id = sha256
        .convert(
          utf8.encode(
            jsonEncode(<Object>[
              target.videoSource,
              target.subtitleStartMs ?? target.startMs,
              target.subtitleEndMs ?? target.endMs,
              target.text.trim(),
            ]),
          ),
        )
        .toString();
    return Directory('${base.path}/pronunciation_history_v1/$id');
  }

  Future<PronunciationHistoryEntry> save(
    PronunciationAssessmentTarget target,
    PronunciationAssessmentResult result,
    Pcm16MonoAudio audio,
  ) async {
    final Directory directory = await _directory(target);
    await directory.create(recursive: true);
    final DateTime now = DateTime.now();
    final Directory pending = await directory.createTemp('.pending-');
    final PronunciationHistoryEntry entry = PronunciationHistoryEntry(
      directory: pending,
      recordedAt: now,
      result: result,
    );
    try {
      await entry.recordingFile.writeAsBytes(audio.toWav(), flush: true);
      await File('${pending.path}/score.json').writeAsString(
        jsonEncode(<String, Object>{
          'recordedAt': now.toUtc().toIso8601String(),
          'result': result.toJson(),
        }),
        flush: true,
      );
      final String suffix = pending.path.split(Platform.pathSeparator).last;
      final Directory saved = await pending.rename(
        '${directory.path}/${now.microsecondsSinceEpoch}-${suffix.substring('.pending-'.length)}',
      );
      return PronunciationHistoryEntry(
        directory: saved,
        recordedAt: now,
        result: result,
      );
    } catch (_) {
      try {
        await pending.delete(recursive: true);
      } on FileSystemException {
        // Preserve the original write error.
      }
      rethrow;
    }
  }

  Future<List<PronunciationHistoryEntry>> load(
    PronunciationAssessmentTarget target,
  ) async {
    final Directory directory = await _directory(target);
    if (!directory.existsSync()) return const <PronunciationHistoryEntry>[];
    final List<PronunciationHistoryEntry> entries =
        <PronunciationHistoryEntry>[];
    await for (final FileSystemEntity file in directory.list(
      followLinks: false,
    )) {
      if (file is! Directory ||
          file.path.split(Platform.pathSeparator).last.startsWith('.')) {
        continue;
      }
      try {
        final Object? decoded = jsonDecode(
          await File('${file.path}/score.json').readAsString(),
        );
        if (decoded is! Map<String, dynamic>) continue;
        final Object? timestamp = decoded['recordedAt'];
        if (timestamp is! String) continue;
        final DateTime? recordedAt = DateTime.tryParse(timestamp);
        final PronunciationAssessmentResult? result =
            PronunciationAssessmentResult.tryParse(decoded['result']);
        if (recordedAt != null && result != null) {
          entries.add(
            PronunciationHistoryEntry(
              directory: file,
              recordedAt: recordedAt.toLocal(),
              result: result,
            ),
          );
        }
      } on FormatException {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    entries.sort(
      (PronunciationHistoryEntry a, PronunciationHistoryEntry b) =>
          b.recordedAt.compareTo(a.recordedAt),
    );
    return entries;
  }
}
