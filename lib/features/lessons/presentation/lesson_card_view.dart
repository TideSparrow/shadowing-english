import 'package:flutter/material.dart';

import '../domain/intensive_lesson.dart';

const List<String> lessonIllustrationAssets = <String>[
  'assets/img/lesson-tutor.png',
  'assets/img/lesson-dialogue.png',
  'assets/img/growth-level-3.png',
  'assets/img/growth-companion-confident.png',
];

const Color _paper = Color(0xFFFFFBF3);
const Color _ink = Color(0xFF30291F);
const Color _red = Color(0xFFC83B2E);
const Color _gold = Color(0xFFF3C760);
const Color _green = Color(0xFF4B772C);
const Color _muted = Color(0xFF776A59);

class LessonUsageHeader extends StatelessWidget {
  const LessonUsageHeader({
    required this.usage,
    required this.saved,
    required this.hasLesson,
    this.model,
    super.key,
  });
  final LessonTokenUsage? usage;
  final String? model;
  final bool saved;
  final bool hasLesson;

  @override
  Widget build(BuildContext context) {
    final LessonTokenUsage? value = usage;
    final String label = value == null
        ? (hasLesson ? '解析 Token：接口未返回用量' : '解析 Token：暂无用量')
        : '解析 Token：输入 ${value.input ?? '—'} · 输出 ${value.output ?? '—'} · 总计 ${value.total ?? '—'}';
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: <Widget>[
          Text(
            label,
            key: const Key('lesson-token-usage'),
            style: const TextStyle(fontSize: 12, height: 1.5, color: _muted),
          ),
          if (saved)
            const Text(
              '已保存 · 复看不请求 AI',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: Color(0xFF49722D),
              ),
            ),
          if (model != null && model!.isNotEmpty)
            Text(
              model!,
              style: const TextStyle(fontSize: 12, height: 1.5, color: _muted),
            ),
        ],
      ),
    );
  }
}

/// Cream paper, red focus words, yellow emphasis and dialogue bubbles mirror
/// the supplied teaching-card reference. Art stays small and decorative.
class LessonCardView extends StatelessWidget {
  const LessonCardView({
    required this.lesson,
    required this.card,
    required this.decorationAsset,
    super.key,
  });
  final IntensiveLesson lesson;
  final LessonCard card;
  final String decorationAsset;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final bool wide =
          constraints.maxWidth >= 850 &&
          MediaQuery.textScalerOf(context).scale(1) < 1.4;
      return Container(
        key: const Key('lesson-illustrated-paper'),
        padding: EdgeInsets.all(wide ? 28 : 18),
        decoration: BoxDecoration(
          color: _paper,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFEEDFC5), width: 1.5),
        ),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(flex: 3, child: _source(context, wide: true)),
                  const SizedBox(width: 30),
                  Expanded(flex: 7, child: _teaching(context)),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _focus(context),
                  const SizedBox(height: 18),
                  _source(context, wide: false),
                  const SizedBox(height: 24),
                  _teaching(context, showFocus: false),
                ],
              ),
      );
    },
  );

  Widget _source(BuildContext context, {required bool wide}) {
    final Widget bubble = _SpeechBubble(
      color: Colors.white,
      borderColor: const Color(0xFFEBCF97),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _HighlightedText(
            text: lesson.source.english,
            focus: card.focus,
            fontSize: wide ? 27 : 22,
            color: _red,
          ),
          const SizedBox(height: 14),
          Text(
            lesson.meaning,
            style: const TextStyle(
              fontSize: 18,
              height: 1.65,
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        bubble,
        const SizedBox(height: 10),
        if (wide)
          Align(
            alignment: Alignment.centerRight,
            child: _decoration(height: 136),
          )
        else
          Align(
            alignment: Alignment.centerRight,
            child: _decoration(height: 82),
          ),
        if (card.kind == LessonCardKind.scene) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            lesson.scene,
            style: const TextStyle(fontSize: 14, height: 1.7, color: _muted),
          ),
        ],
      ],
    );
  }

  Widget _decoration({required double height}) => Semantics(
    label: '学习装饰插画',
    image: true,
    child: Image.asset(
      decorationAsset,
      key: const Key('lesson-decorative-illustration'),
      height: height,
      width: height * 1.25,
      fit: BoxFit.contain,
      cacheWidth: 300,
      excludeFromSemantics: true,
    ),
  );

  Widget _focus(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        card.focus,
        style: TextStyle(
          fontSize: MediaQuery.sizeOf(context).width < 600 ? 34 : 46,
          fontWeight: FontWeight.w900,
          height: 1.1,
          color: _red,
        ),
      ),
      const SizedBox(height: 9),
      Container(
        width: 150,
        height: 5,
        decoration: BoxDecoration(
          color: _gold,
          borderRadius: BorderRadius.circular(5),
        ),
      ),
      const SizedBox(height: 10),
      const Divider(color: Color(0xFFEBCF97), thickness: 1),
    ],
  );

  Widget _teaching(BuildContext context, {bool showFocus = true}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      if (showFocus) _focus(context),
      const SizedBox(height: 14),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: _red,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.priority_high_rounded,
              color: Colors.white,
              size: 27,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              card.tip,
              style: const TextStyle(
                fontSize: 18,
                height: 1.65,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      Text(
        card.explanation,
        style: const TextStyle(
          fontSize: 18,
          height: 1.75,
          fontWeight: FontWeight.w500,
          color: _ink,
        ),
      ),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF2CF),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.star_rounded, color: Color(0xFFC18A13), size: 25),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: card.pattern.isEmpty ? card.focus : card.pattern,
                    ),
                    if (card.meaning.isNotEmpty) ...<InlineSpan>[
                      const TextSpan(
                        text: '  可以表示：',
                        style: TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      TextSpan(text: card.meaning),
                    ],
                  ],
                ),
                key: const Key('lesson-pattern-meaning'),
                style: const TextStyle(
                  fontSize: 20,
                  height: 1.5,
                  color: _red,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 26),
      Row(
        children: <Widget>[
          const Icon(Icons.check_circle_rounded, color: _green, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              card.kind == LessonCardKind.usage ? '换个场景，也能这样说' : '把这个表达放进对话里',
              style: const TextStyle(
                fontSize: 18,
                height: 1.4,
                color: _ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      ...List<Widget>.generate(
        card.examples.length,
        (int index) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _ExampleMessage(
            example: card.examples[index],
            focus: card.focus,
            reply: index.isOdd,
            green: card.kind == LessonCardKind.usage,
          ),
        ),
      ),
      const Text(
        '例句由 AI 编写，用来练习迁移表达。',
        style: TextStyle(fontSize: 12, height: 1.6, color: _muted),
      ),
    ],
  );
}

class _ExampleMessage extends StatelessWidget {
  const _ExampleMessage({
    required this.example,
    required this.focus,
    required this.reply,
    required this.green,
  });
  final LessonExample example;
  final String focus;
  final bool reply;
  final bool green;

  @override
  Widget build(BuildContext context) {
    const double avatarSize = 44;
    final Widget avatar = Semantics(
      label: reply ? '对话头像二' : '对话头像一',
      image: true,
      child: Container(
        width: avatarSize,
        height: avatarSize,
        decoration: const BoxDecoration(
          color: Color(0xFFF7E7C8),
          shape: BoxShape.circle,
        ),
        clipBehavior: Clip.antiAlias,
        child: Transform.scale(
          scale: reply ? 1.7 : 1.8,
          alignment: reply
              ? const Alignment(.7, -.6)
              : const Alignment(0, -.65),
          child: Image.asset(
            reply
                ? 'assets/img/lesson-dialogue.png'
                : 'assets/img/lesson-tutor.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            cacheWidth: 180,
            excludeFromSemantics: true,
          ),
        ),
      ),
    );
    final Widget bubble = Expanded(
      child: _SpeechBubble(
        reply: reply,
        color: green ? const Color(0xFFF0F5E7) : const Color(0xFFFFFDF8),
        borderColor: green ? const Color(0xFFD3DDBB) : const Color(0xFFEDDCB7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (example.situation.isNotEmpty) ...<Widget>[
              Text(
                example.situation,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: _muted,
                ),
              ),
              const SizedBox(height: 5),
            ],
            _HighlightedText(
              text: example.english,
              focus: focus,
              fontSize: 22,
              color: green ? _green : _red,
            ),
            const SizedBox(height: 7),
            Text(
              example.chinese,
              style: const TextStyle(fontSize: 16, height: 1.6, color: _ink),
            ),
          ],
        ),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (!reply) ...<Widget>[avatar, const SizedBox(width: 13)],
        bubble,
        if (reply) ...<Widget>[const SizedBox(width: 13), avatar],
      ],
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({
    required this.child,
    required this.color,
    required this.borderColor,
    this.reply = false,
  });
  final Widget child;
  final Color color;
  final Color borderColor;
  final bool reply;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _BubbleTail(color: color, borderColor: borderColor, reply: reply),
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: child,
    ),
  );
}

class _BubbleTail extends CustomPainter {
  const _BubbleTail({
    required this.color,
    required this.borderColor,
    required this.reply,
  });
  final Color color;
  final Color borderColor;
  final bool reply;
  @override
  void paint(Canvas canvas, Size size) {
    final double x = reply ? size.width - 1 : 1;
    final double direction = reply ? 1 : -1;
    final Path path = Path()
      ..moveTo(x, 20)
      ..lineTo(x + direction * 10, 27)
      ..lineTo(x, 36)
      ..close();
    canvas
      ..drawPath(path, Paint()..color = color)
      ..drawPath(
        Path()
          ..moveTo(x, 20)
          ..lineTo(x + direction * 10, 27)
          ..lineTo(x, 36),
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
  }

  @override
  bool shouldRepaint(_BubbleTail oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.reply != reply;
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.focus,
    required this.fontSize,
    required this.color,
  });
  final String text;
  final String focus;
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const Set<String> stopWords = <String>{
      'you',
      'someone',
      'something',
      'would',
      'the',
      'a',
      'an',
      'to',
      'for',
      'and',
      'or',
      'in',
    };
    final Set<String> focusWords = RegExp(
      '[A-Za-z]+',
    ).allMatches(focus).map((Match m) => m.group(0)!.toLowerCase()).toSet();
    final Set<String> words = focusWords.difference(stopWords);
    if (words.isEmpty) words.addAll(focusWords);
    final List<InlineSpan> spans = <InlineSpan>[];
    int end = 0;
    for (final Match match in RegExp('[A-Za-z]+').allMatches(text)) {
      spans.add(TextSpan(text: text.substring(end, match.start)));
      final String word = match.group(0)!;
      spans.add(
        TextSpan(
          text: word,
          style: words.contains(word.toLowerCase())
              ? TextStyle(color: color)
              : null,
        ),
      );
      end = match.end;
    }
    spans.add(TextSpan(text: text.substring(end)));
    return Text.rich(
      TextSpan(children: spans),
      style: TextStyle(
        fontSize: fontSize,
        height: 1.45,
        fontWeight: FontWeight.w800,
        color: _ink,
      ),
    );
  }
}
