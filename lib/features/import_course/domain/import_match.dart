import 'package:flutter/foundation.dart' show compute, kIsWeb;

import 'import_file_system.dart';

class ImportSubtitleTrack {
  const ImportSubtitleTrack({
    required this.languageCode,
    required this.languageLabel,
    required this.path,
  });

  final String languageCode;
  final String languageLabel;
  final String path;
}

class ImportSubtitleCandidate {
  const ImportSubtitleCandidate({
    required this.path,
    required this.languageCode,
    required this.languageLabel,
  });

  final String path;
  final String languageCode;
  final String languageLabel;
}

class ImportMatchRow {
  ImportMatchRow({
    required this.episodeName,
    required this.videoFile,
    required this.videoPath,
    required Map<String, ImportSubtitleTrack> subtitleTracks,
    this.candidateSubtitles = const <ImportSubtitleCandidate>[],
  }) : subtitleTracks = Map<String, ImportSubtitleTrack>.unmodifiable(
         subtitleTracks,
       );

  final String episodeName;
  final String videoFile;
  final String videoPath;
  final Map<String, ImportSubtitleTrack> subtitleTracks;
  final List<ImportSubtitleCandidate> candidateSubtitles;

  String get englishSubtitlePath => subtitleTracks['en']?.path ?? '';
  String get chineseSubtitlePath => subtitleTracks['zh']?.path ?? '';
  String get englishSubtitle => subtitleLabel(englishSubtitlePath);
  String get chineseSubtitle => subtitleLabel(chineseSubtitlePath);
  bool get hasEnglish => englishSubtitlePath.isNotEmpty;
  bool get hasChinese => chineseSubtitlePath.isNotEmpty;
  bool get matched => hasEnglish;
  List<String> get candidateSubtitlePaths => candidateSubtitles
      .map((ImportSubtitleCandidate item) => item.path)
      .toList(growable: false);

  String get statusText {
    if (candidateSubtitles.isEmpty) {
      return '缺失字幕';
    }
    if (!hasEnglish) {
      return '待指定英文';
    }
    if (subtitleTracks.length == 1) {
      return '仅英文字幕';
    }
    return '匹配成功';
  }

  List<String> get visibleLanguageCodes {
    final Set<String> codes = <String>{'en'}
      ..addAll(subtitleTracks.keys.where((String code) => code != 'en'))
      ..addAll(
        candidateSubtitles
            .map((ImportSubtitleCandidate item) => item.languageCode)
            .where((String code) => code != 'en'),
      );
    return codes.toList(growable: false);
  }

  String languageLabel(String code) {
    final ImportSubtitleTrack? assignedTrack = subtitleTracks[code];
    if (assignedTrack != null) {
      return assignedTrack.languageLabel;
    }
    for (final ImportSubtitleCandidate item in candidateSubtitles) {
      if (item.languageCode == code && item.languageLabel.isNotEmpty) {
        return item.languageLabel;
      }
    }
    return _fallbackLanguageLabel(code);
  }

  List<ImportSubtitleCandidate> optionsForLanguage(String code) {
    final Set<String> usedPaths = subtitleTracks.entries
        .where(
          (MapEntry<String, ImportSubtitleTrack> entry) => entry.key != code,
        )
        .map((MapEntry<String, ImportSubtitleTrack> entry) => entry.value.path)
        .toSet();

    final List<ImportSubtitleCandidate> preferred = candidateSubtitles
        .where(
          (ImportSubtitleCandidate item) =>
              item.languageCode == code && !usedPaths.contains(item.path),
        )
        .toList(growable: false);
    final List<ImportSubtitleCandidate> fallback = candidateSubtitles
        .where(
          (ImportSubtitleCandidate item) =>
              item.languageCode != code && !usedPaths.contains(item.path),
        )
        .toList(growable: false);
    return <ImportSubtitleCandidate>[...preferred, ...fallback];
  }

  ImportMatchRow assignSubtitle({
    required String languageCode,
    required String languageLabel,
    required String path,
  }) {
    final Map<String, ImportSubtitleTrack> nextTracks =
        Map<String, ImportSubtitleTrack>.from(subtitleTracks);
    if (path.isEmpty) {
      nextTracks.remove(languageCode);
    } else {
      nextTracks.removeWhere(
        (_, ImportSubtitleTrack track) => track.path == path,
      );
      nextTracks[languageCode] = ImportSubtitleTrack(
        languageCode: languageCode,
        languageLabel: languageLabel,
        path: path,
      );
    }
    return ImportMatchRow(
      episodeName: episodeName,
      videoFile: videoFile,
      videoPath: videoPath,
      subtitleTracks: nextTracks,
      candidateSubtitles: candidateSubtitles,
    );
  }

  ImportMatchRow copyWith({
    String? videoPath,
    Map<String, ImportSubtitleTrack>? subtitleTracks,
    List<ImportSubtitleCandidate>? candidateSubtitles,
  }) {
    return ImportMatchRow(
      episodeName: episodeName,
      videoFile: videoFile,
      videoPath: videoPath ?? this.videoPath,
      subtitleTracks: subtitleTracks ?? this.subtitleTracks,
      candidateSubtitles: candidateSubtitles ?? this.candidateSubtitles,
    );
  }

  static String subtitleLabel(String path) {
    return path.isEmpty ? '未找到' : _fileName(path);
  }

  static String _fallbackLanguageLabel(String code) {
    return ImportMatcher.languageLabelFor(code);
  }

  static String _fileName(String value) {
    final int slash = value.lastIndexOf('/') + 1;
    final int backslash = value.lastIndexOf(String.fromCharCode(92)) + 1;
    final int index = slash > backslash ? slash : backslash;
    if (index <= 0) {
      return value;
    }
    return value.substring(index);
  }
}

class ImportMatcher {
  static Future<List<ImportMatchRow>> parseInBackground({
    required String videoFolder,
    required String? subtitleFolder,
    List<String>? videoFiles,
    List<String>? subtitleFiles,
  }) {
    // Capture only paths and file lists, never widget state or platform handles.
    return compute(
      (_) => parse(
        videoFolder: videoFolder,
        subtitleFolder: subtitleFolder,
        videoFiles: videoFiles,
        subtitleFiles: subtitleFiles,
      ),
      null,
    );
  }

  static const Set<String> _videoExtensions = <String>{
    '.mp4',
    '.mkv',
    '.mov',
    '.webm',
    '.rm',
    '.ts',
  };
  static const Set<String> _subtitleExtensions = <String>{'.srt', '.vtt'};

  static const String unknownLanguageCode = 'und';

  static const Map<String, String> _languageLabels = <String, String>{
    'en': '英文字幕',
    'zh': '中文字幕',
    'ja': '日语字幕',
    'ko': '韩语字幕',
    'es': '西班牙语字幕',
    'fr': '法语字幕',
    'de': '德语字幕',
    'pt': '葡萄牙语字幕',
    'it': '意大利语字幕',
    'ru': '俄语字幕',
    'ar': '阿拉伯语字幕',
    unknownLanguageCode: '未识别字幕',
  };

  static const Map<String, List<String>> _languageFileTokens =
      <String, List<String>>{
        'en': <String>[
          'english',
          '英文',
          '.en.',
          '_en.',
          '.eng.',
          '_eng.',
          '.en',
          '_en',
          '.eng',
          '_eng',
        ],
        'zh': <String>[
          'chinese',
          '中文',
          '中文字幕',
          '简中',
          '繁中',
          '.zh.',
          '_zh.',
          '.cn.',
          '_cn.',
          '.chs.',
          '_chs.',
          '.cht.',
          '_cht.',
          '.zh',
          '_zh',
        ],
        'ja': <String>['japanese', '日语', 'jp', '_jp', '.jp.'],
        'ko': <String>['korean', '韩语', 'kr', '_kr', '.kr.'],
        'es': <String>['spanish', '西班牙', '_es', '.es.'],
        'fr': <String>['french', '法语', '_fr', '.fr.'],
        'de': <String>['german', '德语', '_de', '.de.'],
        'pt': <String>['portuguese', '葡语', '_pt', '.pt.'],
        'it': <String>['italian', '意大利', '_it', '.it.'],
        'ru': <String>['russian', '俄语', '_ru', '.ru.'],
        'ar': <String>['arabic', '阿拉伯', '_ar', '.ar.'],
      };

  static const Map<String, String> _episodeNameMap = <String, String>{
    'Intern_S01E01': 'Ep 01 -\nThe Beginning',
    'Intern_S01E02': 'Ep 02 -\nFirst Day',
    'Intern_S01E03': 'Ep 03 -\nThe\nCoffee\nRun',
    'Intern_S01E04': 'Ep 04 -\nLate Shift',
  };

  static List<ImportMatchRow> parse({
    required String videoFolder,
    required String? subtitleFolder,
    List<String>? videoFiles,
    List<String>? subtitleFiles,
  }) {
    if (kIsWeb) {
      return const <ImportMatchRow>[];
    }

    final List<String> resolvedVideoFiles =
        (videoFiles ?? listFilesSync(videoFolder, _videoExtensions))
            .where(isImportablePath)
            .toList(growable: false);
    final List<String> resolvedSubtitleFiles =
        (subtitleFiles ??
                (subtitleFolder == null || subtitleFolder.isEmpty
                    ? const <String>[]
                    : listFilesSync(subtitleFolder, _subtitleExtensions)))
            .where(isImportablePath)
            .toList(growable: false);

    if (resolvedVideoFiles.isEmpty) {
      return const <ImportMatchRow>[];
    }

    final Map<String, ImportSubtitleCandidate> detectionCache =
        <String, ImportSubtitleCandidate>{};
    resolvedVideoFiles.sort(_compareEpisodeByFilename);

    return <ImportMatchRow>[
      for (final String videoPath in resolvedVideoFiles)
        _buildRow(
          videoPath: videoPath,
          subtitleFiles: resolvedSubtitleFiles,
          detectionCache: detectionCache,
        ),
    ];
  }

  static String languageLabelFor(String code) {
    return _languageLabels[code] ?? '其他字幕';
  }

  static bool isImportablePath(String path) {
    final String normalized = path.replaceAll(r'\', '/').toLowerCase();
    return !normalized.contains('/cle_verify/');
  }

  static ImportMatchRow _buildRow({
    required String videoPath,
    required List<String> subtitleFiles,
    required Map<String, ImportSubtitleCandidate> detectionCache,
  }) {
    final String videoFile = _fileName(videoPath);
    final String baseName = _stripExtension(videoFile);
    final List<String> candidatePaths = _candidateSubtitlePaths(
      baseName,
      subtitleFiles,
    );
    final List<ImportSubtitleCandidate> candidates = candidatePaths
        .map(
          (String path) =>
              detectionCache[path] ??= _detectSubtitleCandidate(path),
        )
        .toList(growable: false);

    final Map<String, ImportSubtitleTrack> subtitleTracks = _autoAssignTracks(
      candidates,
    );
    if (!subtitleTracks.containsKey('en')) {
      final String plainEnglishPath = _plainEnglishSubtitlePath(
        baseName,
        candidatePaths,
      );
      if (plainEnglishPath.isNotEmpty) {
        subtitleTracks['en'] = ImportSubtitleTrack(
          languageCode: 'en',
          languageLabel: languageLabelFor('en'),
          path: plainEnglishPath,
        );
      }
    }

    return ImportMatchRow(
      episodeName: _episodeNameMap[baseName] ?? baseName.replaceAll('_', ' '),
      videoFile: videoFile,
      videoPath: videoPath,
      subtitleTracks: subtitleTracks,
      candidateSubtitles: candidates,
    );
  }

  static Map<String, ImportSubtitleTrack> _autoAssignTracks(
    List<ImportSubtitleCandidate> candidates,
  ) {
    final Map<String, ImportSubtitleTrack> tracks =
        <String, ImportSubtitleTrack>{};
    final List<ImportSubtitleCandidate> sortedCandidates =
        <ImportSubtitleCandidate>[...candidates]
          ..sort((ImportSubtitleCandidate a, ImportSubtitleCandidate b) {
            final int priorityDiff =
                _candidatePriority(a) - _candidatePriority(b);
            if (priorityDiff != 0) {
              return priorityDiff;
            }
            return a.path.toLowerCase().compareTo(b.path.toLowerCase());
          });

    for (final ImportSubtitleCandidate candidate in sortedCandidates) {
      if (candidate.languageCode == unknownLanguageCode) {
        continue;
      }
      tracks.putIfAbsent(
        candidate.languageCode,
        () => ImportSubtitleTrack(
          languageCode: candidate.languageCode,
          languageLabel: candidate.languageLabel,
          path: candidate.path,
        ),
      );
    }

    return tracks;
  }

  static int _candidatePriority(ImportSubtitleCandidate candidate) {
    final String lowerFileName = _fileName(candidate.path).toLowerCase();
    if (candidate.languageCode == unknownLanguageCode) {
      return 1000;
    }
    final List<String> patterns =
        _languageFileTokens[candidate.languageCode] ?? const <String>[];
    final int index = patterns.indexWhere(lowerFileName.contains);
    if (index >= 0) {
      return index;
    }
    return 500;
  }

  static ImportSubtitleCandidate _detectSubtitleCandidate(String path) {
    final String fileName = _fileName(path);
    final String lowerFileName = fileName.toLowerCase();
    String languageCode = _detectLanguageFromFileName(lowerFileName);
    if (languageCode == unknownLanguageCode) {
      languageCode = _detectLanguageFromContent(path);
    }
    return ImportSubtitleCandidate(
      path: path,
      languageCode: languageCode,
      languageLabel: languageLabelFor(languageCode),
    );
  }

  static String _detectLanguageFromFileName(String lowerFileName) {
    for (final MapEntry<String, List<String>> entry
        in _languageFileTokens.entries) {
      if (entry.value.any(lowerFileName.contains)) {
        return entry.key;
      }
    }
    return unknownLanguageCode;
  }

  static String _detectLanguageFromContent(String path) {
    final String sample = _meaningfulSubtitleSample(
      readTextFileSnippetSync(path, maxChars: 1600),
    );
    if (sample.isEmpty) {
      return unknownLanguageCode;
    }

    final bool hasLatinLetters = RegExp('[A-Za-z]').hasMatch(sample);
    final bool hasChineseChars = RegExp(r'[\u4e00-\u9fff]').hasMatch(sample);
    if (hasLatinLetters && hasChineseChars) {
      return 'en';
    }

    if (RegExp(r'[\u3040-\u30ff]').hasMatch(sample)) {
      return 'ja';
    }
    if (RegExp(r'[\uac00-\ud7af]').hasMatch(sample)) {
      return 'ko';
    }
    if (hasChineseChars) {
      return 'zh';
    }
    if (RegExp(r'[\u0400-\u04ff]').hasMatch(sample)) {
      return 'ru';
    }
    if (RegExp(r'[\u0600-\u06ff]').hasMatch(sample)) {
      return 'ar';
    }

    final String lower = sample.toLowerCase();
    if (RegExp('[a-z]').hasMatch(lower)) {
      if (_containsAny(lower, const <String>[
        '¿',
        '¡',
        ' que ',
        ' de ',
        ' la ',
        ' el ',
        ' y ',
      ])) {
        return 'es';
      }
      if (_containsAny(lower, const <String>[
        ' je ',
        ' pas ',
        ' vous ',
        ' est ',
        ' à ',
        'é',
        'ç',
      ])) {
        return 'fr';
      }
      if (_containsAny(lower, const <String>[
        ' ich ',
        ' nicht ',
        ' und ',
        ' ist ',
        'ß',
        'ä',
        'ö',
        'ü',
      ])) {
        return 'de';
      }
      if (_containsAny(lower, const <String>[
        ' não ',
        ' você ',
        ' para ',
        ' uma ',
        'ção',
        'ã',
      ])) {
        return 'pt';
      }
      if (_containsAny(lower, const <String>[
        ' che ',
        ' non ',
        ' sono ',
        ' una ',
        ' per ',
      ])) {
        return 'it';
      }
      return 'en';
    }

    return unknownLanguageCode;
  }

  static String _meaningfulSubtitleSample(String raw) {
    final List<String> lines = raw
        .split(RegExp(r'\r?\n'))
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .where((String line) => !RegExp(r'^\d+$').hasMatch(line))
        .where((String line) => !RegExp(r'^\d{2}:\d{2}:\d{2}').hasMatch(line))
        .take(6)
        .toList(growable: false);
    return lines.join(' ');
  }

  static bool _containsAny(String value, List<String> needles) {
    return needles.any(value.contains);
  }

  static int _compareEpisodeByFilename(String a, String b) {
    final String fileNameA = _fileName(a);
    final String fileNameB = _fileName(b);
    return _compareEpisodeFiles(
      _stripExtension(fileNameA),
      _stripExtension(fileNameB),
    );
  }

  static String _plainEnglishSubtitlePath(
    String baseName,
    List<String> candidatePaths,
  ) {
    final String lowerBaseName = baseName.toLowerCase();
    for (final String path in candidatePaths) {
      final String lowerFileName = _fileName(path).toLowerCase();
      if (lowerFileName == '$lowerBaseName.srt' ||
          lowerFileName == '$lowerBaseName.vtt') {
        return path;
      }
    }
    return '';
  }

  static List<String> _candidateSubtitlePaths(
    String baseName,
    List<String> subtitleFiles,
  ) {
    final String lowerBaseName = baseName.toLowerCase();
    return subtitleFiles
        .where((String file) {
          final String lowerFile = _fileName(file).toLowerCase();
          return _looksLikeSameEpisode(lowerBaseName, lowerFile);
        })
        .toList(growable: false);
  }

  static bool _looksLikeSameEpisode(
    String videoBaseName,
    String subtitleFileName,
  ) {
    final String subtitleBaseName = _stripExtension(subtitleFileName);
    if (_hasPrefixWithBoundary(subtitleBaseName, videoBaseName) ||
        _hasPrefixWithBoundary(videoBaseName, subtitleBaseName)) {
      return true;
    }

    final List<String> videoNumberTokens = _numberTokens(videoBaseName);
    final List<String> subtitleNumberTokens = _numberTokens(subtitleBaseName);
    if (videoNumberTokens.isNotEmpty && subtitleNumberTokens.isNotEmpty) {
      return _numberTokensMatch(videoNumberTokens, subtitleNumberTokens);
    }

    final String videoMarker = _episodeMarker(videoBaseName);
    final String subtitleMarker = _episodeMarker(subtitleBaseName);
    if (videoMarker.isNotEmpty &&
        subtitleMarker.isNotEmpty &&
        videoMarker != subtitleMarker) {
      return false;
    }
    if (videoMarker.isNotEmpty && videoMarker == subtitleMarker) {
      return true;
    }

    final String videoKey = _normalizedMatchKey(videoBaseName);
    final String subtitleKey = _normalizedMatchKey(subtitleBaseName);
    if (videoKey.isEmpty || subtitleKey.isEmpty) {
      return false;
    }
    return subtitleKey.contains(videoKey) || videoKey.contains(subtitleKey);
  }

  static bool _hasPrefixWithBoundary(String value, String prefix) {
    if (!value.startsWith(prefix)) {
      return false;
    }
    if (value.length == prefix.length) {
      return true;
    }
    return !RegExp('[a-z0-9]').hasMatch(value[prefix.length]);
  }

  static bool _numberTokensMatch(
    List<String> videoTokens,
    List<String> subtitleTokens,
  ) {
    if (videoTokens.length == 1 && subtitleTokens.length == 1) {
      return videoTokens.first == subtitleTokens.first;
    }
    if (videoTokens.length == 1) {
      return videoTokens.first == subtitleTokens.last;
    }
    if (subtitleTokens.length == 1) {
      return subtitleTokens.first == videoTokens.last;
    }
    if (videoTokens.length <= subtitleTokens.length) {
      return _sameTokens(
        videoTokens,
        subtitleTokens.sublist(0, videoTokens.length),
      );
    }
    return _sameTokens(
      videoTokens.sublist(0, subtitleTokens.length),
      subtitleTokens,
    );
  }

  static bool _sameTokens(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int index = 0; index < a.length; index++) {
      if (a[index] != b[index]) {
        return false;
      }
    }
    return true;
  }

  static int _compareEpisodeFiles(String a, String b) {
    final int aNum = _extractEpisodeNumber(a);
    final int bNum = _extractEpisodeNumber(b);
    if (aNum != bNum) {
      return aNum.compareTo(bNum);
    }
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  static int _extractEpisodeNumber(String name) {
    final Match? match = RegExp(r'(\d+)').firstMatch(name);
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(1) ?? '0') ?? 0;
  }

  static String _stripExtension(String value) {
    final int index = value.lastIndexOf('.');
    if (index <= 0) {
      return value;
    }
    return value.substring(0, index);
  }

  static String _fileName(String value) {
    final int slash = value.lastIndexOf('/') + 1;
    final int backslash = value.lastIndexOf(String.fromCharCode(92)) + 1;
    final int index = slash > backslash ? slash : backslash;
    if (index <= 0) {
      return value;
    }
    return value.substring(index);
  }

  static String _episodeMarker(String value) {
    final String lower = value.toLowerCase();
    final Match? seasonEpisode = RegExp(r's\d{1,2}e\d{1,3}').firstMatch(lower);
    if (seasonEpisode != null) {
      return seasonEpisode.group(0) ?? '';
    }

    final Match? dashedSeasonEpisode = RegExp(
      r'(^|[^a-z0-9])(\d{1,2})[\-_. ](\d{1,3})([^a-z0-9]|$)',
    ).firstMatch(lower);
    if (dashedSeasonEpisode != null) {
      final String season = dashedSeasonEpisode.group(2) ?? '';
      final String episode = dashedSeasonEpisode.group(3) ?? '';
      if (season.isNotEmpty && episode.isNotEmpty) {
        return 's${season.padLeft(2, '0')}e${episode.padLeft(2, '0')}';
      }
    }

    final Match? episodeOnly = RegExp(r'ep?\d{1,3}').firstMatch(lower);
    if (episodeOnly != null) {
      return episodeOnly.group(0) ?? '';
    }

    final Match? number = RegExp(r'\d{1,3}').firstMatch(lower);
    return number?.group(0) ?? '';
  }

  static List<String> _numberTokens(String value) {
    return RegExp(r'\d+')
        .allMatches(value.toLowerCase())
        .map((Match match) => match.group(0) ?? '')
        .where((String token) => token.isNotEmpty)
        .map((String token) => int.tryParse(token)?.toString() ?? token)
        .toList(growable: false);
  }

  static String _normalizedMatchKey(String value) {
    String normalized = value.toLowerCase();
    normalized = normalized.replaceAll(RegExp(r's\d{1,2}e\d{1,3}'), ' ');
    normalized = normalized.replaceAll(RegExp(r'ep?\d{1,3}'), ' ');
    normalized = normalized.replaceAll(
      RegExp(
        '(english|chinese|japanese|korean|spanish|french|german|portuguese|italian|russian|arabic|subtitle|subtitles|sub|英文|中文|中文字幕|日语|韩语|西班牙|法语|德语|葡语|意大利|俄语|阿拉伯|双语|简中|繁中|1080p|720p|2160p|x264|x265|h264|h265)',
      ),
      ' ',
    );
    normalized = normalized.replaceAll(RegExp('[^a-z0-9]+'), ' ');
    normalized = normalized.trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalized.replaceAll(' ', '');
  }
}
