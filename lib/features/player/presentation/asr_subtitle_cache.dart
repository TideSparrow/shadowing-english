import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../settings/presentation/settings_provider.dart';

class AiSubtitleCacheEntry {
  const AiSubtitleCacheEntry({
    required this.episodeId,
    required this.videoPath,
    required this.cacheFile,
    required this.lineCount,
    required this.provider,
    required this.model,
    required this.generatedAt,
    required this.sizeBytes,
    this.referenceSignature,
  });

  final String episodeId;
  final String videoPath;
  final File cacheFile;
  final int lineCount;
  final String provider;
  final String model;
  final DateTime generatedAt;
  final int sizeBytes;
  final String? referenceSignature;
}

class AsrSubtitleCache {
  const AsrSubtitleCache({
    this.appSupportDirectory = getApplicationSupportDirectory,
    this.downloadsDirectory = getDownloadsDirectory,
  });

  final Future<Directory> Function() appSupportDirectory;
  final Future<Directory?> Function() downloadsDirectory;

  Future<File> cacheFileFor({
    required String episodeId,
    required String videoPath,
  }) async {
    final Directory root = await appSupportDirectory();
    return File(
      '${root.path}${Platform.pathSeparator}asr_subtitles'
      '${Platform.pathSeparator}${_safeSegment(episodeId)}'
      '${Platform.pathSeparator}${_wordsFileName(videoPath)}',
    );
  }

  Future<bool> exists({
    required String episodeId,
    required String videoPath,
  }) async => await read(episodeId: episodeId, videoPath: videoPath) != null;

  /// Retain generated subtitles after an explicitly confirmed directory move.
  /// Different media must continue to fail normal cache validation.
  Future<void> relinkVideo({
    required String episodeId,
    required String oldPath,
    required String newPath,
  }) async {
    final File oldCache = await cacheFileFor(
      episodeId: episodeId,
      videoPath: oldPath,
    );
    final File newCache = await cacheFileFor(
      episodeId: episodeId,
      videoPath: newPath,
    );
    if (oldCache.path != newCache.path || !oldCache.existsSync()) return;
    final File metadata = _metadataFile(oldCache);
    if (!metadata.existsSync()) return;
    final Object? decoded = jsonDecode(await metadata.readAsString());
    if (decoded is! Map<String, dynamic>) return;
    final File video = File(newPath);
    final FileStat stat = video.statSync();
    if (decoded['videoPath'] != File(oldPath).absolute.path ||
        decoded['videoSize'] != stat.size ||
        decoded['videoModifiedMs'] != stat.modified.millisecondsSinceEpoch) {
      return;
    }
    decoded['videoPath'] = video.absolute.path;
    _writeAtomically(metadata, jsonEncode(decoded));
  }

  Future<String?> read({
    required String episodeId,
    required String videoPath,
    LearningSettingsState? settings,
    String? referenceSignature,
    bool validateReferenceSignature = true,
  }) async {
    final File file = await cacheFileFor(
      episodeId: episodeId,
      videoPath: videoPath,
    );
    if (!file.existsSync()) {
      return null;
    }
    try {
      final String content = await file.readAsString();
      final Object? decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic> || decoded['lines'] is! List) {
        throw const FormatException('invalid-asr-subtitle-cache');
      }
      if (settings != null && decoded['version'] != 1) {
        throw const FormatException('obsolete-asr-subtitle-cache');
      }
      if (settings != null &&
          !await _metadataMatches(
            file: file,
            videoPath: videoPath,
            settings: settings,
            referenceSignature: referenceSignature,
            validateReferenceSignature: validateReferenceSignature,
          )) {
        _deleteFiles(file);
        return null;
      }
      return content;
    } catch (_) {
      _deleteFiles(file);
      return null;
    }
  }

  Future<File> write({
    required String episodeId,
    required String videoPath,
    required String content,
    LearningSettingsState? settings,
    String? referenceSignature,
  }) async {
    final File file = await cacheFileFor(
      episodeId: episodeId,
      videoPath: videoPath,
    );
    await file.parent.create(recursive: true);
    final Object? decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic> || decoded['lines'] is! List) {
      throw const FormatException('invalid-asr-subtitle-cache');
    }
    _writeAtomically(file, content);
    if (settings != null) {
      _writeAtomically(
        _metadataFile(file),
        jsonEncode(<String, Object?>{
          ..._metadata(
            videoPath: videoPath,
            settings: settings,
            referenceSignature: referenceSignature,
          ),
          'episodeId': episodeId,
          'generatedAtMs': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    }
    return file;
  }

  Future<void> delete({
    required String episodeId,
    required String videoPath,
  }) async {
    final File file = await cacheFileFor(
      episodeId: episodeId,
      videoPath: videoPath,
    );
    _deleteFiles(file);
  }

  Future<List<AiSubtitleCacheEntry>> listEntries() async {
    final Directory root = await _cacheRoot();
    if (!root.existsSync()) return const <AiSubtitleCacheEntry>[];
    final List<AiSubtitleCacheEntry> entries = <AiSubtitleCacheEntry>[];
    for (final FileSystemEntity entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.words.json')) continue;
      try {
        final Object? raw = jsonDecode(entity.readAsStringSync());
        if (raw is! Map<String, dynamic> || raw['lines'] is! List) continue;
        final File metadataFile = _metadataFile(entity);
        Map<String, dynamic> metadata = <String, dynamic>{};
        if (metadataFile.existsSync()) {
          final Object? decoded = jsonDecode(metadataFile.readAsStringSync());
          if (decoded is Map<String, dynamic>) metadata = decoded;
        }
        final FileStat stat = entity.statSync();
        final int? generatedAtMs = metadata['generatedAtMs'] as int?;
        entries.add(
          AiSubtitleCacheEntry(
            episodeId:
                metadata['episodeId'] as String? ??
                entity.parent.path.split(Platform.pathSeparator).last,
            videoPath: metadata['videoPath'] as String? ?? entity.path,
            cacheFile: entity,
            lineCount: (raw['lines'] as List<dynamic>).length,
            provider: metadata['asrProvider'] as String? ?? '未知服务',
            model: metadata['asrModel'] as String? ?? '未知模型',
            generatedAt: generatedAtMs == null
                ? stat.modified
                : DateTime.fromMillisecondsSinceEpoch(generatedAtMs),
            sizeBytes: stat.size,
            referenceSignature: metadata['referenceSignature'] as String?,
          ),
        );
      } catch (_) {
        // A damaged cache is ignored here and cleaned when the player reads it.
      }
    }
    entries.sort(
      (AiSubtitleCacheEntry a, AiSubtitleCacheEntry b) =>
          b.generatedAt.compareTo(a.generatedAt),
    );
    return entries;
  }

  Future<Map<String, dynamic>> readEntry(AiSubtitleCacheEntry entry) async {
    final Object? decoded = jsonDecode(entry.cacheFile.readAsStringSync());
    if (decoded is! Map<String, dynamic> || decoded['lines'] is! List) {
      throw const FormatException('invalid-asr-subtitle-cache');
    }
    return decoded;
  }

  Future<void> updateEntry(
    AiSubtitleCacheEntry entry,
    Map<String, dynamic> content,
  ) async {
    if (content['lines'] is! List) {
      throw const FormatException('invalid-asr-subtitle-cache');
    }
    _writeAtomically(entry.cacheFile, jsonEncode(content));
  }

  Future<File> exportEntry(AiSubtitleCacheEntry entry) async {
    if (!entry.cacheFile.existsSync()) {
      throw StateError('missing-asr-subtitle-cache');
    }
    final Directory targetDir = await _exportDirectory();
    return entry.cacheFile.copySync(
      _availableExportPath(targetDir, _fileName(entry.cacheFile.path)),
    );
  }

  Future<void> deleteEntry(AiSubtitleCacheEntry entry) async {
    _deleteFiles(entry.cacheFile);
    final Directory jobs = Directory(
      '${entry.cacheFile.parent.path}${Platform.pathSeparator}jobs',
    );
    if (jobs.existsSync()) jobs.deleteSync(recursive: true);
  }

  Future<void> deleteAll() async {
    final Directory root = await _cacheRoot();
    if (root.existsSync()) root.deleteSync(recursive: true);
  }

  Future<File> exportOne({
    required String episodeId,
    required String videoPath,
  }) async {
    final File source = await cacheFileFor(
      episodeId: episodeId,
      videoPath: videoPath,
    );
    if (!source.existsSync()) {
      throw StateError('missing-asr-subtitle-cache');
    }
    final Directory targetDir = await _exportDirectory();
    return source.copy(
      '${targetDir.path}${Platform.pathSeparator}${_wordsFileName(videoPath)}',
    );
  }

  Future<int> exportAll() async {
    final Directory sourceRoot = await _cacheRoot();
    if (!sourceRoot.existsSync()) {
      return 0;
    }
    final Directory targetDir = await _exportDirectory();
    int count = 0;
    for (final FileSystemEntity entity in sourceRoot.listSync(
      recursive: true,
    )) {
      if (entity is! File || !entity.path.endsWith('.words.json')) {
        continue;
      }
      await entity.copy(
        '${targetDir.path}${Platform.pathSeparator}${_fileName(entity.path)}',
      );
      count += 1;
    }
    return count;
  }

  Future<Directory> _exportDirectory() async {
    final Directory? downloads = await downloadsDirectory();
    final Directory targetDir = Directory(
      '${(downloads ?? await appSupportDirectory()).path}'
      '${Platform.pathSeparator}Shadowing English'
      '${Platform.pathSeparator}AI Subtitles',
    )..createSync(recursive: true);
    return targetDir;
  }

  Future<bool> _metadataMatches({
    required File file,
    required String videoPath,
    required LearningSettingsState settings,
    String? referenceSignature,
    bool validateReferenceSignature = true,
  }) async {
    final File metadataFile = _metadataFile(file);
    if (!metadataFile.existsSync()) return false;
    final Object? decoded = jsonDecode(await metadataFile.readAsString());
    if (decoded is! Map<String, dynamic>) return false;
    final Map<String, Object?> expected = _metadata(
      videoPath: videoPath,
      settings: settings,
      referenceSignature: referenceSignature,
    );
    if (validateReferenceSignature &&
        (decoded['referenceSignature'] as String? ?? '') !=
            (referenceSignature ?? '')) {
      return false;
    }
    return expected.entries.every(
      (MapEntry<String, Object?> entry) => decoded[entry.key] == entry.value,
    );
  }

  Future<Directory> _cacheRoot() async {
    final Directory root = await appSupportDirectory();
    return Directory('${root.path}${Platform.pathSeparator}asr_subtitles');
  }

  Map<String, Object?> _metadata({
    required String videoPath,
    required LearningSettingsState settings,
    String? referenceSignature,
  }) {
    final File video = File(videoPath);
    final FileStat stat = video.statSync();
    return <String, Object?>{
      'version': 1,
      'videoPath': video.absolute.path,
      'videoSize': stat.size,
      'videoModifiedMs': stat.modified.millisecondsSinceEpoch,
      'asrProvider': settings.asrProvider,
      'asrBaseUrl': settings.asrBaseUrl,
      'asrModel': settings.asrModel,
      'bilingual': settings.generateBilingualAsrSubtitles,
      if (referenceSignature?.isNotEmpty ?? false)
        'referenceSignature': referenceSignature,
      if (settings.generateBilingualAsrSubtitles) ...<String, Object?>{
        'translationProvider': settings.translationProvider,
        'translationBaseUrl': settings.translationBaseUrl,
        'translationModel': settings.translationModel,
      },
    };
  }

  File _metadataFile(File file) => File('${file.path}.meta.json');

  void _deleteFiles(File file) {
    for (final File target in <File>[file, _metadataFile(file)]) {
      if (target.existsSync()) target.deleteSync();
    }
  }

  void _writeAtomically(File file, String content) {
    final File part = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.part',
    );
    try {
      part
        ..writeAsStringSync(content, flush: true)
        ..renameSync(file.path);
    } finally {
      if (part.existsSync()) part.deleteSync();
    }
  }

  String _wordsFileName(String videoPath) {
    final String fileName = _fileName(videoPath);
    final int dot = fileName.lastIndexOf('.');
    final String baseName = dot <= 0 ? fileName : fileName.substring(0, dot);
    return '$baseName.words.json';
  }

  String _availableExportPath(Directory directory, String fileName) {
    final String direct = '${directory.path}${Platform.pathSeparator}$fileName';
    if (!File(direct).existsSync()) return direct;
    final bool isWordsJson = fileName.endsWith('.words.json');
    final int dot = fileName.lastIndexOf('.');
    final String extension = isWordsJson
        ? '.words.json'
        : dot <= 0
        ? ''
        : fileName.substring(dot);
    final String baseName = fileName.substring(
      0,
      fileName.length - extension.length,
    );
    int suffix = 2;
    while (true) {
      final String candidate =
          '${directory.path}${Platform.pathSeparator}$baseName ($suffix)$extension';
      if (!File(candidate).existsSync()) return candidate;
      suffix += 1;
    }
  }

  String _fileName(String path) {
    return path
        .replaceAll(String.fromCharCode(92), Platform.pathSeparator)
        .split(Platform.pathSeparator)
        .last;
  }

  String _safeSegment(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp('_+'), '_');
  }
}
