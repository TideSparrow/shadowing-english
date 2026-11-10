import 'dart:io';

import 'package:common_learn_english/features/lessons/data/lesson_speech_rate.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  test(
    'lesson rate persists separately and can return to system settings',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'lesson-rate-',
      );
      Hive.init(directory.path);
      Box<String> box = await Hive.openBox<String>('prefs');
      ProviderContainer container = ProviderContainer();
      try {
        expect(container.read(lessonSpeechRateProvider), isNull);
        container.read(learningSettingsProvider.notifier).setTtsRate(1.25);
        await container.read(lessonSpeechRateProvider.notifier).setRate(0.5);
        expect(container.read(learningSettingsProvider).ttsRate, 1.25);
        container.dispose();
        await box.close();
        box = await Hive.openBox<String>('prefs');
        container = ProviderContainer();
        expect(container.read(lessonSpeechRateProvider), 0.5);
        expect(container.read(learningSettingsProvider).ttsRate, 1.25);
        await container.read(lessonSpeechRateProvider.notifier).setRate(null);
        container.dispose();
        container = ProviderContainer();
        expect(container.read(lessonSpeechRateProvider), isNull);
        expect(container.read(learningSettingsProvider).ttsRate, 1.25);
      } finally {
        container.dispose();
        await box.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
