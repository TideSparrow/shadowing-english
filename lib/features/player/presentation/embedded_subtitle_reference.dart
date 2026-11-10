import 'dart:convert';
import 'dart:io';

import 'package:media_kit/media_kit.dart';

import 'desktop_ffmpeg.dart';
import 'player_mock_state.dart';
import 'player_subtitle_loader.dart';

Future<List<PlayerSubtitleLine>> extractEmbeddedEnglishSubtitles({
  required String videoPath,
  required List<SubtitleTrack> tracks,
  String? trackId,
}) async {
  try {
    final int index = tracks.indexWhere(
      (SubtitleTrack track) => trackId == null
          ? track.language == 'eng' || track.language == 'en'
          : track.id == trackId &&
                (track.language == 'eng' || track.language == 'en'),
    );
    if (index < 0) return const <PlayerSubtitleLine>[];
    final String? ffmpeg = await findDesktopFfmpeg();
    if (ffmpeg == null) return const <PlayerSubtitleLine>[];
    final Process process = await Process.start(ffmpeg, <String>[
      '-v',
      'error',
      '-i',
      videoPath,
      '-map',
      '0:s:$index',
      '-f',
      'srt',
      '-',
    ]);
    try {
      final Future<String> output = process.stdout
          .transform(utf8.decoder)
          .join();
      // Drain stderr concurrently to avoid filling the process pipe.
      final Future<void> errors = process.stderr.drain<void>();
      final List<Object?> result = await Future.wait<Object?>(<Future<Object?>>[
        output,
        process.exitCode,
        errors,
      ]).timeout(const Duration(seconds: 30));
      if (result[1] != 0) return const <PlayerSubtitleLine>[];
      return parseSubtitleLines(result[0]! as String);
    } finally {
      process.kill();
    }
  } catch (_) {
    // Embedded subtitles are optional and must not prevent video playback.
    return const <PlayerSubtitleLine>[];
  }
}
