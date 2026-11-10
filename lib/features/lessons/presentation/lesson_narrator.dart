import '../../shared/data/word_pronunciation_service.dart';
import '../domain/intensive_lesson.dart';

/// One owned speech session. Invalidation happens before stopping native TTS,
/// so a late completion cannot start another sentence after close/navigation.
class LessonNarrator {
  LessonNarrator({required this.service});
  final WordPronunciationService service;
  int _session = 0;

  Future<void> play({
    required IntensiveLesson lesson,
    required int fromCard,
    required void Function(int card, int segment) onSegment,
    double Function()? rate,
  }) async {
    final int session = ++_session;
    await service.stop();
    for (int card = fromCard; card < lesson.cards.length; card++) {
      final List<LessonSpeech> script = lesson.cards[card].speech;
      for (int segment = 0; segment < script.length; segment++) {
        if (_session != session) return;
        onSegment(card, segment);
        await service.speak(
          script[segment].text,
          language: script[segment].language,
          speechTimeout: const Duration(seconds: 60),
          rate: rate?.call(),
        );
      }
    }
  }

  Future<void> stop() {
    _session++;
    return service.stop();
  }
}
