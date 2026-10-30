import 'dart:io';

import 'package:common_learn_english/features/import_course/domain/import_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'background parsing scans files and preserves detected subtitle tracks',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'background-import-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/lesson1.mkv').createSync();
      File(
        '${root.path}/lesson1.srt',
      ).writeAsStringSync('1\n00:00:01,000 --> 00:00:02,000\nHello world\n');
      final List<ImportMatchRow> rows = await ImportMatcher.parseInBackground(
        videoFolder: root.path,
        subtitleFolder: root.path,
      );
      expect(rows, hasLength(1));
      expect(rows.single.videoFile, 'lesson1.mkv');
      expect(rows.single.englishSubtitlePath, '${root.path}/lesson1.srt');
    },
  );

  test('parse should map video files to subtitle match status', () {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'import-match-test',
    );
    final Directory videoDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}videos',
    )..createSync();
    final Directory subtitleDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}subtitles',
    )..createSync();

    try {
      File(
        '${videoDir.path}${Platform.pathSeparator}Intern_S01E01.mp4',
      ).createSync();
      File(
        '${videoDir.path}${Platform.pathSeparator}Intern_S01E02.mp4',
      ).createSync();
      File(
        '${videoDir.path}${Platform.pathSeparator}Intern_S01E03.mp4',
      ).createSync();
      File(
        '${videoDir.path}${Platform.pathSeparator}Intern_S01E04.mp4',
      ).createSync();

      File(
        '${subtitleDir.path}${Platform.pathSeparator}Intern_S01E01_EN.srt',
      ).createSync();
      File(
        '${subtitleDir.path}${Platform.pathSeparator}Intern_S01E01_CN.srt',
      ).createSync();
      File(
        '${subtitleDir.path}${Platform.pathSeparator}Intern_S01E02_EN.srt',
      ).createSync();
      File(
        '${subtitleDir.path}${Platform.pathSeparator}Intern_S01E02.ENG.vtt',
      ).createSync();
      File(
        '${subtitleDir.path}${Platform.pathSeparator}Intern_S01E02_CN.srt',
      ).createSync();
      File(
        '${subtitleDir.path}${Platform.pathSeparator}Intern_S01E03_EN.srt',
      ).createSync();
      File(
        '${subtitleDir.path}${Platform.pathSeparator}Intern_S01E03.srt',
      ).createSync();
      File(
        '${subtitleDir.path}${Platform.pathSeparator}Intern_S01E04_EN.srt',
      ).createSync();
      File(
        '${subtitleDir.path}${Platform.pathSeparator}Intern_S01E04_CN.srt',
      ).createSync();

      final List<ImportMatchRow> rows = ImportMatcher.parse(
        videoFolder: videoDir.path,
        subtitleFolder: subtitleDir.path,
      );

      expect(rows.length, 4);
      expect(rows.first.videoFile, 'Intern_S01E01.mp4');
      expect(rows.first.matched, isTrue);
      final ImportMatchRow secondEpisode = rows.firstWhere(
        (ImportMatchRow row) => row.videoFile == 'Intern_S01E02.mp4',
      );
      final ImportMatchRow thirdEpisode = rows.firstWhere(
        (ImportMatchRow row) => row.videoFile == 'Intern_S01E03.mp4',
      );
      expect(secondEpisode.statusText, '匹配成功');
      expect(thirdEpisode.statusText, '仅英文字幕');
      expect(thirdEpisode.hasChinese, isFalse);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('supports required subtitle filename patterns', () {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'import-match-test2',
    );
    final Directory videoDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}videos',
    )..createSync();
    final Directory subtitleDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}subtitles',
    )..createSync();

    try {
      File(
        '${videoDir.path}${Platform.pathSeparator}Intern_S01E02.mp4',
      ).createSync();
      File(
        '${videoDir.path}${Platform.pathSeparator}Intern_S01E03.mp4',
      ).createSync();

      File(
        '${subtitleDir.path}${Platform.pathSeparator}Intern_S01E02.ENG.vtt',
      ).createSync();
      File(
        '${subtitleDir.path}${Platform.pathSeparator}Intern_S01E03.srt',
      ).createSync();

      final List<ImportMatchRow> rows = ImportMatcher.parse(
        videoFolder: videoDir.path,
        subtitleFolder: subtitleDir.path,
      );

      final ImportMatchRow secondEpisode = rows.firstWhere(
        (ImportMatchRow row) => row.episodeName.contains('02'),
      );
      final ImportMatchRow thirdEpisode = rows.firstWhere(
        (ImportMatchRow row) => row.episodeName.contains('03'),
      );

      expect(secondEpisode.englishSubtitle, 'Intern_S01E02.ENG.vtt');
      expect(secondEpisode.hasEnglish, isTrue);
      expect(thirdEpisode.englishSubtitle, 'Intern_S01E03.srt');
      expect(thirdEpisode.hasEnglish, isTrue);
      expect(thirdEpisode.hasChinese, isFalse);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('parse includes supported videos in import results', () {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'import-match-rm-test',
    );
    final Directory videoDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}videos',
    )..createSync();
    final Directory subtitleDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}subtitles',
    )..createSync();

    try {
      File(
        '${videoDir.path}${Platform.pathSeparator}movie_ep01.mp4',
      ).createSync();
      File(
        '${subtitleDir.path}${Platform.pathSeparator}movie_ep01_en.srt',
      ).createSync();
      File(
        '${subtitleDir.path}${Platform.pathSeparator}movie_ep01_cn.srt',
      ).createSync();

      final List<ImportMatchRow> rows = ImportMatcher.parse(
        videoFolder: videoDir.path,
        subtitleFolder: subtitleDir.path,
      );

      expect(rows, hasLength(1));
      expect(rows.single.videoFile, 'movie_ep01.mp4');
      expect(rows.single.matched, isTrue);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('parse keeps video rows when subtitles are skipped', () {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'import-match-video-only-test',
    );
    final Directory videoDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}videos',
    )..createSync();

    try {
      File(
        '${videoDir.path}${Platform.pathSeparator}lesson01.mp4',
      ).createSync();

      final List<ImportMatchRow> rows = ImportMatcher.parse(
        videoFolder: videoDir.path,
        subtitleFolder: null,
      );

      expect(rows, hasLength(1));
      expect(rows.single.videoFile, 'lesson01.mp4');
      expect(rows.single.hasEnglish, isFalse);
      expect(rows.single.hasChinese, isFalse);
      expect(rows.single.statusText, '缺失字幕');
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('parse can use explicit selected files without scanning folders', () {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'import-match-explicit-files-test',
    );

    try {
      final String videoPath =
          '${tempDir.path}${Platform.pathSeparator}lesson1.mp4';
      final String enSubtitlePath =
          '${tempDir.path}${Platform.pathSeparator}lesson1.en.srt';
      final String zhSubtitlePath =
          '${tempDir.path}${Platform.pathSeparator}lesson1.zh.srt';

      File(videoPath).createSync();
      File(enSubtitlePath).createSync();
      File(zhSubtitlePath).createSync();

      final List<ImportMatchRow> rows = ImportMatcher.parse(
        videoFolder: '',
        subtitleFolder: null,
        videoFiles: <String>[videoPath],
        subtitleFiles: <String>[enSubtitlePath, zhSubtitlePath],
      );

      expect(rows, hasLength(1));
      expect(rows.single.videoFile, 'lesson1.mp4');
      expect(rows.single.hasEnglish, isTrue);
      expect(rows.single.hasChinese, isTrue);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('parse keeps chinese subtitle when only chinese subtitle exists', () {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'import-match-chinese-only-test',
    );

    try {
      final String videoPath =
          '${tempDir.path}${Platform.pathSeparator}lesson1.mp4';
      final String zhSubtitlePath =
          '${tempDir.path}${Platform.pathSeparator}lesson1.zh.srt';

      File(videoPath).createSync();
      File(zhSubtitlePath).createSync();

      final List<ImportMatchRow> rows = ImportMatcher.parse(
        videoFolder: '',
        subtitleFolder: null,
        videoFiles: <String>[videoPath],
        subtitleFiles: <String>[zhSubtitlePath],
      );

      expect(rows, hasLength(1));
      expect(rows.single.hasChinese, isTrue);
      expect(rows.single.chineseSubtitle, 'lesson1.zh.srt');
      expect(rows.single.statusText, '待指定英文');
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('parse can smart-match similar video and subtitle names', () {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'import-match-smart-test',
    );

    try {
      final String videoPath =
          '${tempDir.path}${Platform.pathSeparator}The.Office.S01E02.1080p.mp4';
      final String enSubtitlePath =
          '${tempDir.path}${Platform.pathSeparator}The Office - S01E02 English.srt';
      final String zhSubtitlePath =
          '${tempDir.path}${Platform.pathSeparator}The Office - S01E02 中文字幕.srt';

      File(videoPath).createSync();
      File(enSubtitlePath).createSync();
      File(zhSubtitlePath).createSync();

      final List<ImportMatchRow> rows = ImportMatcher.parse(
        videoFolder: '',
        subtitleFolder: null,
        videoFiles: <String>[videoPath],
        subtitleFiles: <String>[enSubtitlePath, zhSubtitlePath],
      );

      expect(rows, hasLength(1));
      expect(rows.single.hasEnglish, isTrue);
      expect(rows.single.hasChinese, isTrue);
      expect(rows.single.statusText, '匹配成功');
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('parse can match dashed episode numbers with season-episode subtitles', () {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'import-match-dashed-season-test',
    );

    try {
      final String videoPath =
          '${tempDir.path}${Platform.pathSeparator}1-01.Muddy.Puddles [www.abc2022.cn].mp4';
      final String subtitlePath =
          '${tempDir.path}${Platform.pathSeparator}Peppa.Pig.S01E01.Muddy.Puddles.srt';

      File(videoPath).createSync();
      File(subtitlePath).writeAsStringSync('''
1
00:00:01,000 --> 00:00:02,000
Muddy puddles are the best.
''');

      final List<ImportMatchRow> rows = ImportMatcher.parse(
        videoFolder: '',
        subtitleFolder: null,
        videoFiles: <String>[videoPath],
        subtitleFiles: <String>[subtitlePath],
      );

      expect(rows, hasLength(1));
      expect(rows.single.hasEnglish, isTrue);
      expect(rows.single.englishSubtitlePath, subtitlePath);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('parse can match subtitles when episode number formats differ', () {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'import-match-number-format-test',
    );

    try {
      final String videoPath =
          '${tempDir.path}${Platform.pathSeparator}Peppa.012.mp4';
      final String subtitlePath =
          '${tempDir.path}${Platform.pathSeparator}Peppa.Pig.E12.srt';

      File(videoPath).createSync();
      File(subtitlePath).writeAsStringSync('''
1
00:00:01,000 --> 00:00:02,000
Episode twelve.
''');

      final List<ImportMatchRow> rows = ImportMatcher.parse(
        videoFolder: '',
        subtitleFolder: null,
        videoFiles: <String>[videoPath],
        subtitleFiles: <String>[subtitlePath],
      );

      expect(rows, hasLength(1));
      expect(rows.single.hasEnglish, isTrue);
      expect(rows.single.englishSubtitlePath, subtitlePath);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('parse does not match subtitles when episode numbers differ', () {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'import-match-number-mismatch-test',
    );

    try {
      final String videoPath =
          '${tempDir.path}${Platform.pathSeparator}Peppa.01.mp4';
      final String subtitlePath =
          '${tempDir.path}${Platform.pathSeparator}Peppa.Pig.S01E02.srt';

      File(videoPath).createSync();
      File(subtitlePath).writeAsStringSync('''
1
00:00:01,000 --> 00:00:02,000
Episode two.
''');

      final List<ImportMatchRow> rows = ImportMatcher.parse(
        videoFolder: '',
        subtitleFolder: null,
        videoFiles: <String>[videoPath],
        subtitleFiles: <String>[subtitlePath],
      );

      expect(rows, hasLength(1));
      expect(rows.single.hasEnglish, isFalse);
      expect(rows.single.candidateSubtitlePaths, isEmpty);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('parse does not match subtitles by partial episode prefix', () {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'import-match-prefix-mismatch-test',
    );

    try {
      final String videoPath =
          '${tempDir.path}${Platform.pathSeparator}lesson1.mp4';
      final String subtitlePath =
          '${tempDir.path}${Platform.pathSeparator}lesson10.srt';

      File(videoPath).createSync();
      File(subtitlePath).writeAsStringSync('''
1
00:00:01,000 --> 00:00:02,000
Episode ten.
''');

      final List<ImportMatchRow> rows = ImportMatcher.parse(
        videoFolder: '',
        subtitleFolder: null,
        videoFiles: <String>[videoPath],
        subtitleFiles: <String>[subtitlePath],
      );

      expect(rows, hasLength(1));
      expect(rows.single.hasEnglish, isFalse);
      expect(rows.single.candidateSubtitlePaths, isEmpty);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('parse ignores verification sample files under cle_verify', () {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'import-match-cle-verify-test',
    );

    try {
      final String realVideoPath =
          '${tempDir.path}${Platform.pathSeparator}03.rm';
      final String realSubtitlePath =
          '${tempDir.path}${Platform.pathSeparator}03.en.srt';
      final Directory verifyDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}cle_verify',
      )..createSync();

      File(realVideoPath).createSync();
      File(realSubtitlePath).createSync();
      File(
        '${verifyDir.path}${Platform.pathSeparator}lesson01.mp4',
      ).createSync();
      File(
        '${verifyDir.path}${Platform.pathSeparator}lesson01.en.srt',
      ).createSync();

      final List<ImportMatchRow> rows = ImportMatcher.parse(
        videoFolder: '',
        subtitleFolder: null,
        videoFiles: <String>[
          realVideoPath,
          '${verifyDir.path}${Platform.pathSeparator}lesson01.mp4',
        ],
        subtitleFiles: <String>[
          realSubtitlePath,
          '${verifyDir.path}${Platform.pathSeparator}lesson01.en.srt',
        ],
      );

      expect(rows, hasLength(1));
      expect(rows.single.videoFile, '03.rm');
      expect(rows.single.englishSubtitle, '03.en.srt');
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('parse keeps untyped same-episode subtitles for manual assignment', () {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'import-match-manual-assign-test',
    );

    try {
      final String videoPath = '${tempDir.path}${Platform.pathSeparator}01.mp4';
      final String subtitlePath =
          '${tempDir.path}${Platform.pathSeparator}01rm.srt';

      File(videoPath).createSync();
      File(subtitlePath).createSync();

      final List<ImportMatchRow> rows = ImportMatcher.parse(
        videoFolder: '',
        subtitleFolder: null,
        videoFiles: <String>[videoPath],
        subtitleFiles: <String>[subtitlePath],
      );

      expect(rows, hasLength(1));
      expect(rows.single.hasEnglish, isFalse);
      expect(rows.single.hasChinese, isFalse);
      expect(rows.single.candidateSubtitlePaths, <String>[subtitlePath]);
      expect(rows.single.statusText, '待指定英文');
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test(
    'parse can detect english subtitle content without filename markers',
    () {
      final Directory tempDir = Directory.systemTemp.createTempSync(
        'import-match-content-detect-test',
      );

      try {
        final String videoPath =
            '${tempDir.path}${Platform.pathSeparator}01.mp4';
        final String subtitlePath =
            '${tempDir.path}${Platform.pathSeparator}01rm.srt';

        File(videoPath).createSync();
        File(subtitlePath).writeAsStringSync('''
1
00:00:01,000 --> 00:00:02,000
Hello, how are you?

2
00:00:03,000 --> 00:00:04,000
I am fine.
''');

        final List<ImportMatchRow> rows = ImportMatcher.parse(
          videoFolder: '',
          subtitleFolder: null,
          videoFiles: <String>[videoPath],
          subtitleFiles: <String>[subtitlePath],
        );

        expect(rows, hasLength(1));
        expect(rows.single.hasEnglish, isTrue);
        expect(rows.single.englishSubtitlePath, subtitlePath);
        expect(rows.single.statusText, '仅英文字幕');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    },
  );

  test('parse treats bilingual subtitle content as english by default', () {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'import-match-bilingual-detect-test',
    );

    try {
      final String videoPath =
          '${tempDir.path}${Platform.pathSeparator}1-04.Polly.Parrot.mp4';
      final String subtitlePath =
          '${tempDir.path}${Platform.pathSeparator}Peppa.Pig.S01E04.Best.Friend.srt';

      File(videoPath).createSync();
      File(subtitlePath).writeAsStringSync('''
1
00:00:01,000 --> 00:00:02,000
Best friend.
最好的朋友。
''');

      final List<ImportMatchRow> rows = ImportMatcher.parse(
        videoFolder: '',
        subtitleFolder: null,
        videoFiles: <String>[videoPath],
        subtitleFiles: <String>[subtitlePath],
      );

      expect(rows, hasLength(1));
      expect(rows.single.hasEnglish, isTrue);
      expect(rows.single.englishSubtitlePath, subtitlePath);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });
}
