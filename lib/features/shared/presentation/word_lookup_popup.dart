import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../phrases/presentation/phrase_book_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../words/presentation/word_book_provider.dart';
import '../data/word_lookup_service.dart';
import '../data/word_pronunciation_service.dart';
import '../domain/word_lookup_entry.dart';
import 'pad/app_design_tokens.dart';

class WordLookupPopupCard extends ConsumerStatefulWidget {
  const WordLookupPopupCard({
    required this.rawWord,
    required this.contextSentence,
    required this.onClose,
    this.onCollect,
    this.onFavorite,
    this.onPronounce,
    this.episodeId,
    this.contextTime,
    this.fallbackDefinitionCn,
    this.showAbove = false,
    this.showSide = false,
    this.showRight = false,
    this.maxHeight,
    super.key,
  });

  static const double preferredWidth = 392;

  final String rawWord;
  final String contextSentence;
  final VoidCallback onClose;
  final VoidCallback? onCollect;
  final VoidCallback? onFavorite;
  final VoidCallback? onPronounce;
  final String? episodeId;
  final String? contextTime;
  final String? fallbackDefinitionCn;
  final bool showAbove;
  final bool showSide;
  final bool showRight;
  final double? maxHeight;

  @override
  ConsumerState<WordLookupPopupCard> createState() =>
      _WordLookupPopupCardState();
}

class _WordLookupPopupCardState extends ConsumerState<WordLookupPopupCard> {
  WordLookupEntry? _entry;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isPronouncing = false;

  @override
  void initState() {
    super.initState();
    _loadEntry();
  }

  @override
  void didUpdateWidget(covariant WordLookupPopupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rawWord != widget.rawWord ||
        oldWidget.contextSentence != widget.contextSentence ||
        oldWidget.fallbackDefinitionCn != widget.fallbackDefinitionCn) {
      _loadEntry();
    }
  }

  Future<void> _loadEntry() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    try {
      final WordLookupEntry entry = await ref
          .read(wordLookupServiceProvider)
          .lookupWord(
            rawWord: widget.rawWord,
            contextSentence: widget.contextSentence,
            settings: settings,
          );
      final String fallbackDefinition =
          widget.fallbackDefinitionCn?.trim() ?? '';
      final WordLookupEntry resolvedEntry =
          entry.sourceLabel == '未配置' && fallbackDefinition.isNotEmpty
          ? WordLookupEntry(
              word: entry.word,
              phonetic: entry.phonetic,
              type: entry.type,
              definitionEn: '',
              usageEn: entry.usageEn,
              exampleSentenceEn: '',
              definitionCn: fallbackDefinition,
              sourceLabel: '字幕词义',
              contextMeaningCn: fallbackDefinition,
            )
          : entry;
      if (!mounted) {
        return;
      }
      setState(() {
        _entry = resolvedEntry;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _entry = null;
        _isLoading = false;
        _errorMessage = '查词失败，请稍后重试。';
      });
    }
  }

  Future<void> _handlePronounce(
    String text, {
    String language = 'en-US',
    bool preferSource = false,
  }) async {
    final WordLookupEntry? entry = _entry;
    if (entry == null || _isPronouncing) {
      return;
    }

    setState(() {
      _isPronouncing = true;
    });
    widget.onPronounce?.call();

    try {
      await ref
          .read(wordPronunciationServiceProvider)
          .speak(text, language: language);
    } on WordPronunciationException catch (error) {
      if (mounted) {
        _showMessage(error.message);
      }
    } catch (_) {
      if (mounted) {
        _showMessage(const WordPronunciationException().message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPronouncing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String word = normalizeWord(widget.rawWord);
    final bool isFavorite =
        widget.onFavorite != null &&
        ref.watch(
          wordBookProvider.select(
            (List<WordEntry> entries) => entries.any(
              (WordEntry entry) => entry.word == word && entry.favorite,
            ),
          ),
        );
    final String sentence = widget.contextSentence.trim().toLowerCase();
    final PhraseEntry? collectedPhrase = widget.onCollect == null
        ? null
        : ref.watch(
            phraseBookProvider.select(
              (List<PhraseEntry> entries) => entries
                  .where(
                    (PhraseEntry entry) =>
                        entry.english.trim().toLowerCase() == sentence &&
                        (widget.episodeId == null ||
                            entry.episodeId == widget.episodeId) &&
                        (widget.contextTime == null ||
                            entry.time == widget.contextTime),
                  )
                  .firstOrNull,
            ),
          );
    final bool isCollected = collectedPhrase != null;
    final Widget body;
    if (_isLoading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_errorMessage != null) {
      body = Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          _errorMessage!,
          style: const TextStyle(
            height: 1.45,
            color: AppDesignTokens.textSecondary,
          ),
        ),
      );
    } else if (_entry != null) {
      body = _WordLookupPopupBody(
        entry: _entry!,
        contextSentence: widget.contextSentence,
        isPronouncing: _isPronouncing,
        onPronounce: _handlePronounce,
      );
    } else {
      body = const SizedBox.shrink();
    }
    final Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _entry?.word ?? widget.rawWord,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
            ),
            if (widget.onFavorite != null)
              IconButton(
                tooltip: isFavorite ? '取消收藏' : '收藏单词',
                onPressed: () {
                  if (isFavorite) {
                    ref
                        .read(wordBookProvider.notifier)
                        .toggleFavorite(widget.rawWord);
                    _showMessage('已取消收藏单词 "${widget.rawWord}"');
                  } else {
                    widget.onFavorite!();
                  }
                },
                isSelected: isFavorite,
                color: isFavorite
                    ? AppDesignTokens.brandGreenDark
                    : AppDesignTokens.textSecondary,
                style: IconButton.styleFrom(
                  backgroundColor: isFavorite ? const Color(0xFFEAF5E5) : null,
                ),
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                icon: Icon(isFavorite ? Icons.bookmark : Icons.bookmark_border),
              ),
            if (widget.onCollect != null)
              IconButton(
                tooltip: isCollected ? '从短语库移除' : '加入短语库',
                onPressed: () {
                  if (collectedPhrase != null) {
                    ref
                        .read(phraseBookProvider.notifier)
                        .deletePhrase(collectedPhrase.id);
                    _showMessage('已从短语库移除');
                  } else {
                    widget.onCollect!();
                  }
                },
                isSelected: isCollected,
                color: isCollected
                    ? AppDesignTokens.brandGreenDark
                    : AppDesignTokens.textSecondary,
                style: IconButton.styleFrom(
                  backgroundColor: isCollected ? const Color(0xFFEAF5E5) : null,
                ),
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                icon: Icon(
                  isCollected
                      ? Icons.library_add_check
                      : Icons.library_add_outlined,
                ),
              ),
            IconButton(
              tooltip: _isPronouncing ? '播放中...' : '播放发音',
              onPressed: _isLoading || _entry == null || _isPronouncing
                  ? null
                  : () => _handlePronounce(_entry!.word),
              visualDensity: VisualDensity.compact,
              iconSize: 20,
              disabledColor: _isPronouncing
                  ? AppDesignTokens.brandGreenDark
                  : null,
              style: IconButton.styleFrom(
                backgroundColor: _isPronouncing
                    ? const Color(0xFFEAF5E5)
                    : null,
              ),
              icon: Icon(
                _isPronouncing
                    ? Icons.graphic_eq_rounded
                    : Icons.volume_up_outlined,
              ),
            ),
            IconButton(
              onPressed: widget.onClose,
              tooltip: '关闭',
              visualDensity: VisualDensity.compact,
              iconSize: 20,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        if (widget.maxHeight == null)
          body
        else
          Flexible(child: SingleChildScrollView(child: body)),
      ],
    );

    return Container(
      key: const ValueKey<String>('word-lookup-popup-card'),
      constraints: BoxConstraints(
        maxWidth: WordLookupPopupCard.preferredWidth,
        maxHeight: widget.maxHeight ?? double.infinity,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1E7E1)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: content,
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _WordLookupPopupBody extends StatelessWidget {
  const _WordLookupPopupBody({
    required this.entry,
    required this.contextSentence,
    required this.isPronouncing,
    required this.onPronounce,
  });

  final WordLookupEntry entry;
  final String contextSentence;
  final bool isPronouncing;
  final Future<void> Function(String text, {String language, bool preferSource})
  onPronounce;

  @override
  Widget build(BuildContext context) {
    final String englishDefinition = _englishDefinition(entry);
    final String usageNote = _usageNote(entry);
    final String exampleSentence = _exampleSentence(entry);
    final String trimmedContext = contextSentence.trim();
    final String? contextMeaning = _contextMeaning(entry);
    final bool hasEnglishExplanation = englishDefinition.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            if (entry.phonetic.trim().isNotEmpty)
              _InfoChip(
                label: entry.phonetic.trim(),
                foregroundColor: AppDesignTokens.textSecondary,
                backgroundColor: const Color(0xFFF4F6F4),
              ),
            _InfoChip(
              label: entry.type,
              foregroundColor: AppDesignTokens.textSecondary,
              backgroundColor: const Color(0xFFF4F6F4),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _MeaningCard(
              label: '中文义项',
              pronunciationKey: const ValueKey<String>(
                'word-lookup-pronounce-cn',
              ),
              backgroundColor: const Color(0xFFF2FBEA),
              labelColor: AppDesignTokens.brandGreenDark,
              onPronounce: () {
                onPronounce(entry.definitionCn, language: 'zh-CN');
              },
              child: Text(
                entry.definitionCn,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
            ),
            if (hasEnglishExplanation) ...<Widget>[
              const SizedBox(height: 10),
              _MeaningCard(
                label: '英文说明',
                pronunciationKey: const ValueKey<String>(
                  'word-lookup-pronounce-en',
                ),
                backgroundColor: const Color(0xFFF7F8FA),
                labelColor: AppDesignTokens.textSecondary,
                onPronounce: () {
                  onPronounce(
                    <String>[
                      englishDefinition,
                      if (usageNote.isNotEmpty) usageNote,
                    ].join('\n\n'),
                  );
                },
                child: Text(
                  <String>[
                    englishDefinition,
                    if (usageNote.isNotEmpty) usageNote,
                  ].join('\n\n'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      contextMeaning != null &&
                              contextMeaning != entry.definitionCn
                          ? '当前句子里更接近'
                          : '原句上下文',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ),
                  _PronounceIconButton(
                    key: const ValueKey<String>(
                      'word-lookup-pronounce-context',
                    ),
                    onPressed: isPronouncing
                        ? null
                        : () {
                            onPronounce(
                              trimmedContext.isNotEmpty
                                  ? trimmedContext
                                  : usageNote,
                            );
                          },
                  ),
                ],
              ),
              if (contextMeaning != null &&
                  contextMeaning != entry.definitionCn) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  contextMeaning,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
              ],
              if (trimmedContext.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  trimmedContext,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              ] else if (!hasEnglishExplanation &&
                  usageNote.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  usageNote,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              ],
              if (exampleSentence.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        '新句子',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppDesignTokens.textSecondary,
                        ),
                      ),
                    ),
                    _PronounceIconButton(
                      key: const ValueKey<String>(
                        'word-lookup-pronounce-example',
                      ),
                      onPressed: isPronouncing
                          ? null
                          : () {
                              onPronounce(exampleSentence);
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  exampleSentence,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '翻译来源：${entry.sourceLabel}',
          style: const TextStyle(
            fontSize: 12,
            color: AppDesignTokens.textSecondary,
          ),
        ),
      ],
    );
  }

  String _englishDefinition(WordLookupEntry entry) {
    return entry.definitionEn.trim();
  }

  String _usageNote(WordLookupEntry entry) {
    final String value = entry.usageEn.trim();
    if (value.startsWith('Context: ')) {
      return value.substring('Context: '.length).trim();
    }
    return value;
  }

  String _exampleSentence(WordLookupEntry entry) {
    return entry.exampleSentenceEn.trim();
  }

  String? _contextMeaning(WordLookupEntry entry) {
    final String? value = entry.contextMeaningCn?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }
}

class _MeaningCard extends StatelessWidget {
  const _MeaningCard({
    required this.label,
    required this.backgroundColor,
    required this.labelColor,
    required this.child,
    this.pronunciationKey,
    this.onPronounce,
  });

  final String label;
  final Color backgroundColor;
  final Color labelColor;
  final Widget child;
  final Key? pronunciationKey;
  final VoidCallback? onPronounce;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: labelColor,
                  ),
                ),
              ),
              _PronounceIconButton(
                key: pronunciationKey,
                onPressed: onPronounce,
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _PronounceIconButton extends StatelessWidget {
  const _PronounceIconButton({this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        tooltip: '朗读',
        icon: const Icon(
          Icons.volume_up_rounded,
          size: 18,
          color: AppDesignTokens.primaryBlueDark,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.foregroundColor,
    required this.backgroundColor,
  });

  final String label;
  final Color foregroundColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: foregroundColor,
        ),
      ),
    );
  }
}
