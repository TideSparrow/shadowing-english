const List<String> subtitleLetterCaseOptions = <String>[
  '保留原样',
  '全部大写',
  '全部小写',
  '句首字母大写',
];

/// Formats display text only; source subtitles and word timings stay intact.
String formatSubtitleLetterCase(String text, String mode) {
  switch (mode) {
    case '全部大写':
      return text.toUpperCase();
    case '全部小写':
      return text.toLowerCase();
    case '句首字母大写':
      bool sentenceStart = true;
      final StringBuffer result = StringBuffer();
      for (final int rune in text.toLowerCase().runes) {
        final String character = String.fromCharCode(rune);
        if (rune >= 97 && rune <= 122) {
          result.write(sentenceStart ? character.toUpperCase() : character);
          sentenceStart = false;
        } else {
          result.write(character);
          if ('.!?\n'.contains(character)) sentenceStart = true;
        }
      }
      // English first-person pronouns remain capitalized, including I'm/I'd.
      return result.toString().replaceAllMapped(
        RegExp(r'\bi\b'),
        (Match match) => 'I',
      );
    default:
      return text;
  }
}
