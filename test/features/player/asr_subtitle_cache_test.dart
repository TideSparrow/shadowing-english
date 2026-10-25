import 'dart:io';

import 'package:common_learn_english/features/player/presentation/asr_subtitle_cache.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'confirmed move preserves AI subtitles only when media metadata matches',
    () async {
      final Directory root = Directory.systemTemp.createTempSync('asr-relink-');
      addTearDown(() => root.deleteSync(recursive: true));
      final Directory oldRoot = Directory('${root.path}/old')..createSync();
      final Directory newRoot = Directory('${root.path}/new')..createSync();
      final AsrSubtitleCache cache = AsrSubtitleCache(
        appSupportDirectory: () async => root,
      );
      final LearningSettingsState settings = LearningSettingsState.defaults();
      final File oldVideo = File('${oldRoot.path}/video.mp4')
        ..writeAsStringSync('video');
      await cache.write(
        episodeId: 'ep01',
        videoPath: oldVideo.path,
        content: '{"version":1,"lines":[]}',
        settings: settings,
      );
      final File moved = oldVideo.renameSync('${newRoot.path}/video.mp4');
      await cache.relinkVideo(
        episodeId: 'ep01',
        oldPath: oldVideo.path,
        newPath: moved.path,
      );
      expect(
        await cache.read(
          episodeId: 'ep01',
          videoPath: moved.path,
          settings: settings,
        ),
        isNotNull,
      );
      final File different = File('${oldRoot.path}/video.mp4')
        ..writeAsStringSync('different content');
      await cache.relinkVideo(
        episodeId: 'ep01',
        oldPath: moved.path,
        newPath: different.path,
      );
      expect(
        await cache.read(
          episodeId: 'ep01',
          videoPath: different.path,
          settings: settings,
        ),
        isNull,
      );
    },
  );

  test('cache file uses episode folder and video base name', () async {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'asr-cache-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => tempDir,
      downloadsDirectory: () async => tempDir,
    );

    final File file = await cache.cacheFileFor(
      episodeId: 'episode/01',
      videoPath: '${tempDir.path}${Platform.pathSeparator}My Movie.mp4',
    );

    expect(file.path, contains('asr_subtitles'));
    expect(file.path, contains('episode_01'));
    expect(file.path.endsWith('My Movie.words.json'), isTrue);
  });

  test('export copies cached words json to downloads folder', () async {
    final Directory supportDir = Directory.systemTemp.createTempSync(
      'asr-cache-support-',
    );
    final Directory downloadsDir = Directory.systemTemp.createTempSync(
      'asr-cache-downloads-',
    );
    addTearDown(() {
      supportDir.deleteSync(recursive: true);
      downloadsDir.deleteSync(recursive: true);
    });

    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => supportDir,
      downloadsDirectory: () async => downloadsDir,
    );

    await cache.write(
      episodeId: 'ep01',
      videoPath: '/videos/Lesson01.mp4',
      content: '{"lines":[]}',
    );

    final File exported = await cache.exportOne(
      episodeId: 'ep01',
      videoPath: '/videos/Lesson01.mp4',
    );

    expect(exported.path, contains('Shadowing English'));
    expect(exported.path, contains('AI Subtitles'));
    expect(exported.path.endsWith('Lesson01.words.json'), isTrue);
    expect(exported.readAsStringSync(), '{"lines":[]}');
  });

  test('delete removes cached words json for current video', () async {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'asr-cache-delete-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => tempDir,
      downloadsDirectory: () async => tempDir,
    );

    await cache.write(
      episodeId: 'ep01',
      videoPath: '/videos/Lesson01.mp4',
      content: '{"lines":[]}',
    );
    await cache.delete(episodeId: 'ep01', videoPath: '/videos/Lesson01.mp4');

    expect(
      await cache.exists(episodeId: 'ep01', videoPath: '/videos/Lesson01.mp4'),
      isFalse,
    );
  });

  test('export all copies existing cached words files', () async {
    final Directory supportDir = Directory.systemTemp.createTempSync(
      'asr-cache-support-all-',
    );
    final Directory downloadsDir = Directory.systemTemp.createTempSync(
      'asr-cache-downloads-all-',
    );
    addTearDown(() {
      supportDir.deleteSync(recursive: true);
      downloadsDir.deleteSync(recursive: true);
    });

    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => supportDir,
      downloadsDirectory: () async => downloadsDir,
    );
    await cache.write(
      episodeId: 'ep01',
      videoPath: '/videos/Lesson01.mp4',
      content: '{"lines":[]}',
    );

    final int count = await cache.exportAll();

    expect(count, 1);
    expect(
      File(
        '${downloadsDir.path}${Platform.pathSeparator}Shadowing English'
        '${Platform.pathSeparator}AI Subtitles'
        '${Platform.pathSeparator}Lesson01.words.json',
      ).existsSync(),
      isTrue,
    );
  });

  test('cache rejects changed generation settings', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-cache-identity-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    final LearningSettingsState settings = LearningSettingsState.defaults()
        .copyWith(
          asrProvider: '腾讯云',
          asrBaseUrl: 'https://asr.tencentcloudapi.com',
          asrModel: '16k_en',
        );
    await cache.write(
      episodeId: 'ep01',
      videoPath: video.path,
      content: '{"version":1,"lines":[]}',
      settings: settings,
    );

    expect(
      await cache.read(
        episodeId: 'ep01',
        videoPath: video.path,
        settings: settings,
      ),
      isNotNull,
    );
    expect(
      await cache.read(
        episodeId: 'ep01',
        videoPath: video.path,
        settings: settings.copyWith(asrModel: 'changed-model'),
      ),
      isNull,
    );
  });

  test('cache and management entry preserve reference identity', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-cache-reference-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    final LearningSettingsState settings = LearningSettingsState.defaults();
    await cache.write(
      episodeId: 'ep01',
      videoPath: video.path,
      content: '{"version":1,"lines":[]}',
      settings: settings,
      referenceSignature: 'reference-v1',
    );

    expect(
      await cache.read(
        episodeId: 'ep01',
        videoPath: video.path,
        settings: settings,
        referenceSignature: 'reference-v1',
      ),
      isNotNull,
    );
    expect(
      (await cache.listEntries()).single.referenceSignature,
      'reference-v1',
    );
  });

  test(
    'cache can validate settings when reference identity is unavailable',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'asr-cache-unknown-reference-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File video = File('${root.path}/lesson.mp4')
        ..writeAsStringSync('video');
      final AsrSubtitleCache cache = AsrSubtitleCache(
        appSupportDirectory: () async => root,
      );
      final LearningSettingsState settings = LearningSettingsState.defaults();
      await cache.write(
        episodeId: 'ep01',
        videoPath: video.path,
        content: '{"version":1,"lines":[]}',
        settings: settings,
        referenceSignature: 'embedded-reference',
      );

      expect(
        await cache.read(
          episodeId: 'ep01',
          videoPath: video.path,
          settings: settings,
          validateReferenceSignature: false,
        ),
        isNotNull,
      );
      expect(
        await cache.read(
          episodeId: 'ep01',
          videoPath: video.path,
          settings: settings.copyWith(asrModel: 'changed-model'),
          validateReferenceSignature: false,
        ),
        isNull,
      );
    },
  );

  test('cache removes old adopted reference subtitles', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-cache-adopted-reference-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    final LearningSettingsState settings = LearningSettingsState.defaults();
    await cache.write(
      episodeId: 'ep01',
      videoPath: video.path,
      content: '{"lines":[]}',
      settings: settings,
    );

    expect(
      await cache.read(
        episodeId: 'ep01',
        videoPath: video.path,
        settings: settings,
      ),
      isNull,
    );
  });

  test('cache rejects changed video and removes corrupt json', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-cache-video-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    final LearningSettingsState settings = LearningSettingsState.defaults();
    await cache.write(
      episodeId: 'ep01',
      videoPath: video.path,
      content: '{"version":1,"lines":[]}',
      settings: settings,
    );
    video.writeAsStringSync('replaced-video-content');

    expect(
      await cache.read(
        episodeId: 'ep01',
        videoPath: video.path,
        settings: settings,
      ),
      isNull,
    );

    final File cacheFile = await cache.cacheFileFor(
      episodeId: 'ep01',
      videoPath: video.path,
    );
    await cacheFile.create(recursive: true);
    await cacheFile.writeAsString('{broken');
    expect(await cache.read(episodeId: 'ep01', videoPath: video.path), isNull);
    expect(cacheFile.existsSync(), isFalse);
  });

  test('management lists, edits, exports, and deletes a cache entry', () async {
    final Directory supportDir = Directory.systemTemp.createTempSync(
      'asr-cache-management-',
    );
    final Directory downloadsDir = Directory.systemTemp.createTempSync(
      'asr-cache-management-downloads-',
    );
    addTearDown(() {
      supportDir.deleteSync(recursive: true);
      downloadsDir.deleteSync(recursive: true);
    });
    final File video = File('${supportDir.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => supportDir,
      downloadsDirectory: () async => downloadsDir,
    );
    final LearningSettingsState settings = LearningSettingsState.defaults()
        .copyWith(asrProvider: '腾讯云', asrModel: '16k_en');
    await cache.write(
      episodeId: 'episode-1',
      videoPath: video.path,
      content:
          '{"version":1,"lines":[{"english":"hello","chinese":"你好","words":[]}]}',
      settings: settings,
    );

    final AiSubtitleCacheEntry entry = (await cache.listEntries()).single;
    expect(entry.episodeId, 'episode-1');
    expect(entry.videoPath, video.absolute.path);
    expect(entry.lineCount, 1);
    expect(entry.provider, '腾讯云');
    expect(entry.model, '16k_en');

    final Map<String, dynamic> content = await cache.readEntry(entry);
    final List<dynamic> lines = content['lines'] as List<dynamic>;
    (lines.single as Map<String, dynamic>)['chinese'] = '您好';
    await cache.updateEntry(entry, content);
    expect(await entry.cacheFile.readAsString(), contains('您好'));
    expect((await cache.exportEntry(entry)).existsSync(), isTrue);

    await cache.deleteEntry(entry);
    expect(await cache.listEntries(), isEmpty);
  });

  test('management can delete all subtitle caches and checkpoints', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-cache-delete-all-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    await cache.write(
      episodeId: 'episode-1',
      videoPath: '/videos/lesson.mp4',
      content: '{"version":1,"lines":[]}',
    );

    await cache.deleteAll();

    expect(await cache.listEntries(), isEmpty);
  });
}
