import 'package:flutter/material.dart';

import '../../../shared/domain/subtitle_letter_case.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../shared/presentation/word_lookup_popup.dart';
import '../player_mock_state.dart';

class PlayerCurrentLineCard extends StatefulWidget {
  const PlayerCurrentLineCard({
    required this.line,
    required this.subtitleMode,
    this.subtitleLetterCase = '保留原样',
    required this.currentWordIndex,
    required this.fontScale,
    required this.highlightWords,
    required this.onBookmark,
    required this.onCollectWord,
    this.onPronounce,
    super.key,
  });

  final PlayerSubtitleLine line;
  final String subtitleMode;
  final String subtitleLetterCase;
  final int currentWordIndex;
  final double fontScale;
  final bool highlightWords;
  final VoidCallback onBookmark;
  final ValueChanged<String> onCollectWord;
  final VoidCallback? onPronounce;

  @override
  State<PlayerCurrentLineCard> createState() => _PlayerCurrentLineCardState();
}

class _PlayerCurrentLineCardState extends State<PlayerCurrentLineCard> {
  String? selectedWord;
  List<String> _tokens = const <String>[];

  @override
  void initState() {
    super.initState();
    _tokens = _buildTokens(
      formatSubtitleLetterCase(widget.line.english, widget.subtitleLetterCase),
    );
  }

  @override
  void didUpdateWidget(covariant PlayerCurrentLineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.english != widget.line.english ||
        oldWidget.subtitleLetterCase != widget.subtitleLetterCase) {
      selectedWord = null;
      _tokens = _buildTokens(
        formatSubtitleLetterCase(
          widget.line.english,
          widget.subtitleLetterCase,
        ),
      );
    }
  }

  List<String> _buildTokens(String lineText) {
    return lineText
        .split(' ')
        .where((String word) => word.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final bool showEnglish = widget.subtitleMode != '单中';
    final bool showChinese = widget.subtitleMode != '单英';
    final bool highlightEnabled = widget.highlightWords;
    final double englishFontSize = 30 * widget.fontScale;
    final double chineseFontSize = 18 * widget.fontScale;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE5E5E5), width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7D6),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    '当前',
                    style: TextStyle(
                      color: AppDesignTokens.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '今日句子 · 点单词可打开学习卡',
                    style: TextStyle(
                      color: AppDesignTokens.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: widget.onBookmark,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppDesignTokens.skyLight,
                    foregroundColor: AppDesignTokens.primaryBlueDark,
                    minimumSize: const Size(48, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Icon(Icons.bookmark_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (showEnglish)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _tokens
                    .asMap()
                    .entries
                    .map((MapEntry<int, String> wordEntry) {
                      final int index = wordEntry.key;
                      final String token = wordEntry.value;
                      final bool selectedToken = selectedWord == token;
                      final bool highlighted =
                          highlightEnabled &&
                          widget.line.words.isNotEmpty &&
                          index == widget.currentWordIndex;

                      return InkWell(
                        onTap: () {
                          setState(() {
                            selectedWord = token;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: selectedToken || highlighted
                                ? const Color(0xFFDFF8C8)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: highlighted
                                  ? AppDesignTokens.brandGreen
                                  : const Color(0x000F7A43),
                              width: highlighted ? 1.5 : 0,
                            ),
                          ),
                          child: Text(
                            token,
                            style: TextStyle(
                              fontSize: englishFontSize,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                              color: AppDesignTokens.textPrimary,
                            ),
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            if (showEnglish && showChinese) const SizedBox(height: 14),
            if (showChinese)
              Text(
                widget.line.chinese,
                style: TextStyle(
                  fontSize: chineseFontSize,
                  height: 1.4,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
            if (selectedWord != null) ...<Widget>[
              const SizedBox(height: 18),
              WordLookupPopupCard(
                rawWord: selectedWord!,
                contextSentence: widget.line.english,
                onCollect: () => widget.onCollectWord(selectedWord!),
                onPronounce: widget.onPronounce,
                onClose: () {
                  setState(() {
                    selectedWord = null;
                  });
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
