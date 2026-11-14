import 'pronunciation_assessment.dart';

const double pronunciationReviewThreshold = 60;
typedef _LowPhone = ({String word, PronunciationPhoneResult phone});

({String text, String speech}) pronunciationFeedback(
  PronunciationAssessmentResult result,
) {
  final String? guidance = result.guidance;
  if (guidance != null) return (text: guidance, speech: guidance);

  final List<_LowPhone> tips =
      <_LowPhone>[
        for (final PronunciationWordResult word in result.words)
          if (word.matchTag != 2 && word.matchTag != 4)
            for (final PronunciationPhoneResult phone in word.phones)
              if ((phone.accuracy ?? 100) < pronunciationReviewThreshold)
                (word: _wordLabel(word), phone: phone),
      ]..sort(
        (_LowPhone a, _LowPhone b) =>
            a.phone.accuracy!.compareTo(b.phone.accuracy!),
      );
  if (tips.isNotEmpty) {
    final List<String> text = <String>[];
    final List<String> speech = <String>[];
    final Set<String> seen = <String>{};
    for (final (word: String word, phone: PronunciationPhoneResult phone)
        in tips) {
      final String? hint = _articulationHint(phone.label);
      if (hint == null || !seen.add(hint)) continue;
      text.add('$word /${phone.label}/：$hint');
      speech.add(
        text.length == 1 ? '$word 里有个音可以再练一下。 $hint' : '再听一下 $word。 $hint',
      );
      if (text.length == 2) break;
    }
    if (text.isNotEmpty) {
      return (text: text.join('\n'), speech: speech.join(' '));
    }
    final _LowPhone tip = tips.first;
    final String message = '${tip.word} 里有个音可以再练一下。先回听高亮的片段，再和原声对照。';
    return (text: message, speech: message);
  }

  for (final PronunciationWordResult word in result.words) {
    final String? message = switch (word.matchTag) {
      1 => '这句可能多读了词。听一下原声，再跟读一遍。',
      2 => '这句可能漏读了 ${_wordLabel(word)}。听一下原声，再把这个词补上。',
      3 => '${_wordLabel(word)} 可以再练一下。先听原声，再慢一点读。',
      _ when (word.accuracy ?? 100) < pronunciationReviewThreshold =>
        '${_wordLabel(word)} 可以再练一下。先听原声，再慢一点读。',
      _ => null,
    };
    if (message != null) return (text: message, speech: message);
  }

  final bool hasPronunciationScores =
      result.accuracy != null ||
      result.words.any(
        (PronunciationWordResult word) =>
            word.accuracy != null ||
            word.phones.any(
              (PronunciationPhoneResult phone) => phone.accuracy != null,
            ),
      );
  final String message = switch (result) {
    _ when !hasPronunciationScores => '这次评测的发音数据不够。可以先回听录音，再读一遍。',
    _ when (result.completion ?? 1) < 0.9 => '这句可以再读完整一点。听一下原声，留意有没有漏掉的词。',
    _ when (result.accuracy ?? 100) < pronunciationReviewThreshold =>
      '这句发音可以再练一下。先听原声，再慢一点读。',
    _ when (result.fluency ?? 1) < 0.6 => '再跟着原声读一遍，留意句中的停顿和连读。',
    _ => '这句发音没发现明显问题，继续保持。',
  };
  return (text: message, speech: message);
}

String _wordLabel(PronunciationWordResult word) {
  final String reference = word.referenceWord
      .replaceFirst(RegExp(r'_\d+$'), '')
      .trim();
  if (reference.isNotEmpty && reference != '*') return reference;
  return word.word.isEmpty || word.word == '*' ? '这个词' : word.word;
}

// Accept both Tencent's phoneme codes and the IPA it returns in sentence mode.
String? _articulationHint(String label) => switch (label
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r"[\s/'\[\]ˈˌː:]"), '')) {
  'θ' || 'th' => '舌尖轻搭在上下门牙之间，留一点缝送气，声带不用振动。',
  'ð' || 'dh' => '舌尖轻搭在上下门牙之间，留一点缝送气，同时让声带振动。',
  'f' => '上门牙轻碰下唇，让气流从缝里出来，声带不用振动。',
  'v' => '上门牙轻碰下唇，让气流从缝里出来，同时让声带振动。',
  's' => '舌尖靠近上门牙后面的牙龈，留细缝送气，嘴唇放松，声带不用振动。',
  'z' => '舌尖靠近上门牙后面的牙龈，留细缝送气，同时让声带振动。',
  'ʃ' || 'sh' => '嘴唇略圆，舌头前部靠近上牙龈后方，留缝送气，声带不用振动。',
  'ʒ' || 'zh' => '嘴唇略圆，舌头前部靠近上牙龈后方，留缝送气，同时让声带振动。',
  'tʃ' || 't͡ʃ' || 'ch' => '嘴唇略圆，舌头前部先堵住气流，再从上牙龈后方的缝隙放气。',
  'dʒ' || 'd͡ʒ' || 'jh' => '嘴唇略圆，舌头前部先堵住气流，再从上牙龈后方的缝隙放气，同时让声带振动。',
  'p' || 'b' => '双唇先合拢，再轻轻打开释放气流，词尾后面别另加一个元音。',
  't' || 'd' => '舌尖抵住上门牙后面的牙龈，再松开，词尾后面别另加一个元音。',
  'k' || 'g' || 'ɡ' => '舌根抬起贴住软腭，再放开，词尾后面别另加一个元音。',
  'm' => '双唇轻轻合拢，让声音从鼻子出来。',
  'n' => '嘴唇放松，舌尖抵住上门牙后面的牙龈，让声音从鼻子出来。',
  'ŋ' || 'ng' => '舌尖放下，舌根抬起贴住软腭，让声音从鼻子出来。',
  'l' || 'ɫ' => '舌尖轻抵上门牙后面的牙龈，让气流从舌头两侧通过。',
  'r' || 'ɹ' => '把舌头稍往后收，舌尖别碰上颚，也不用弹舌。',
  'h' || 'hh' => '嘴巴保持接下来那个元音的嘴形，从喉咙轻轻送气。',
  'j' || 'y' => '把舌头前部抬高，靠近硬腭，再很快滑到后面的元音。',
  'w' => '嘴唇先收圆，舌头后部略抬高，再很快滑到后面的元音。',
  'æ' || 'ae' => '嘴张大一些，舌头放低并靠前，嘴唇别收圆。',
  'ɪ' || 'ih' => '嘴微张，舌头靠前并略抬高，嘴唇放松，把音读短一些。',
  'i' || 'iy' => '嘴角略向两侧拉开，舌头前部抬高，保持嘴形。',
  'ɛ' || 'e' || 'eh' => '嘴适度张开，舌头靠前，比发长衣音时放低一点。',
  'ə' || 'ә' => '嘴微张，舌头放松在中间。这个音轻轻带过。',
  'ʌ' => '嘴适度张开，舌头放在口腔中间偏低，嘴唇别收圆。',
  'ah' => '舌头放在口腔中间，嘴唇别收圆，留意原声里这个音的轻重。',
  'ɑ' || 'aa' => '下巴放低，舌头放低并往后收一点，嘴唇放松。',
  'ɒ' || 'ɔ' || 'ao' => '舌头往后收，嘴唇略收圆，和原声对照嘴巴张开的幅度。',
  'ʊ' || 'uh' => '嘴唇稍微收圆，舌头后部略抬高，把音读短一点。',
  'u' || 'uw' => '嘴唇收圆，舌头抬高，保持嘴形。',
  'ɚ' || 'ɝ' || 'ɜ' || 'er' => '嘴微张，先听原声有没有卷舌。带卷舌时，舌头后收，舌尖别碰上颚。',
  'eɪ' || 'ey' => '嘴先略张，舌头从靠前的中间位置向前上方滑，嘴慢慢收窄。',
  'aɪ' || 'ay' => '先张开嘴，舌头从低处向前上方滑，下巴同时收起一点。',
  'ɔɪ' || 'oy' => '先收圆嘴唇，舌头靠后，再把嘴唇放开，舌头往前上方滑。',
  'aʊ' || 'aw' => '先张开嘴，舌头放低，收尾时舌头后部抬起，嘴唇略收圆。',
  'oʊ' || 'əʊ' || 'әʊ' || 'ow' => '嘴先微张，收尾时舌头后部略抬高，嘴唇逐渐收圆。',
  _ => null,
};
