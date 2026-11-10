import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../settings/presentation/settings_provider.dart';

final NotifierProvider<LessonSpeechRate, double?> lessonSpeechRateProvider =
    NotifierProvider<LessonSpeechRate, double?>(LessonSpeechRate.new);

/// Null follows the app's speech setting; an override belongs only to lessons.
class LessonSpeechRate extends Notifier<double?> {
  static const String _storageKey = 'lesson_speech_rate';

  @override
  double? build() {
    if (!Hive.isBoxOpen('prefs')) return null;
    final double? rate = double.tryParse(
      Hive.box<String>('prefs').get(_storageKey) ?? '',
    );
    return ttsRateOptions.contains(rate) ? rate : null;
  }

  Future<void> setRate(double? rate) async {
    if (rate != null && !ttsRateOptions.contains(rate)) return;
    if (Hive.isBoxOpen('prefs')) {
      final Box<String> box = Hive.box<String>('prefs');
      if (rate == null) {
        await box.delete(_storageKey);
      } else {
        await box.put(_storageKey, rate.toString());
      }
    }
    state = rate;
  }
}
