import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../phrases/presentation/phrase_book_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../words/presentation/word_book_provider.dart';
import '../data/anki_export_service.dart';
import '../domain/anki_export_note.dart';

Future<void> showAnkiExportSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppDesignTokens.appWhite,
      constraints: const BoxConstraints(maxWidth: 600),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const AnkiExportSheet(),
    );

class AnkiExportButton extends StatelessWidget {
  const AnkiExportButton({super.key});
  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => showAnkiExportSheet(context),
    icon: const Icon(Icons.ios_share_rounded, size: 19),
    label: const Text('导出'),
    style: TextButton.styleFrom(
      foregroundColor: AppDesignTokens.brandGreenDark,
    ),
  );
}

class AnkiExportSheet extends ConsumerStatefulWidget {
  const AnkiExportSheet({super.key});
  @override
  ConsumerState<AnkiExportSheet> createState() => _AnkiExportSheetState();
}

class _AnkiExportSheetState extends ConsumerState<AnkiExportSheet> {
  final TextEditingController _deck = TextEditingController(
    text: 'Shadowing English',
  );
  bool _words = true;
  bool _phrases = true;
  bool _busy = false;
  AnkiExportFormat _format = AnkiExportFormat.apkg;
  String? _error;

  @override
  void dispose() {
    _deck.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final List<WordEntry> words = _words
        ? ref.read(wordBookProvider).where((WordEntry w) => w.favorite).toList()
        : <WordEntry>[];
    final List<PhraseEntry> phrases = _phrases
        ? List<PhraseEntry>.of(ref.read(phraseBookProvider))
        : <PhraseEntry>[];
    if (words.isEmpty && phrases.isEmpty || _busy) return;
    final String letterCase = ref
        .read(learningSettingsProvider)
        .subtitleLetterCase;
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    final Rect origin = box == null
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : box.localToGlobal(Offset.zero) & box.size;
    final AnkiExportService service = ref.read(ankiExportServiceProvider);
    final AnkiExportSaver saver = ref.read(ankiExportSaverProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final AnkiExportFile file = await service.generate(
        words: words,
        phrases: phrases,
        format: _format,
        deckName: _deck.text,
        subtitleLetterCase: letterCase,
      );
      final AnkiSaveResult result = await saver.save(file, origin: origin);
      if (!mounted) return;
      if (result == AnkiSaveResult.cancelled) {
        setState(() => _busy = false);
        return;
      }
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (result) {
            AnkiSaveResult.saved => '已导出 ${file.noteCount} 张卡片，请在 Anki 中导入文件。',
            AnkiSaveResult.shared => '已分享 ${file.noteCount} 张卡片的导出文件。',
            _ => '文件已交给系统，请选择保存或导入 Anki。',
          }),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '导出未完成，请重试或改用 TSV 格式。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final int words = ref
        .watch(wordBookProvider)
        .where((WordEntry w) => w.favorite)
        .length;
    final int phrases = ref.watch(phraseBookProvider).length;
    final int selected = (_words ? words : 0) + (_phrases ? phrases : 0);
    final String letterCase = ref.watch(
      learningSettingsProvider.select(
        (LearningSettingsState settings) => settings.subtitleLetterCase,
      ),
    );
    return PopScope(
      canPop: !_busy,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      '导出',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    tooltip: '关闭',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '导出收藏的单词、短语和台词语境。英文语境和短语大小写：$letterCase（跟随设置）。',
                style: const TextStyle(
                  color: AppDesignTokens.textPrimary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              const Text('导出内容', style: TextStyle(fontWeight: FontWeight.w800)),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('收藏单词 · $words'),
                subtitle: const Text('不包含自动记录的未收藏单词'),
                controlAffinity: ListTileControlAffinity.leading,
                value: _words,
                onChanged: _busy
                    ? null
                    : (bool? v) => setState(() => _words = v!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('收藏短语 · $phrases'),
                controlAffinity: ListTileControlAffinity.leading,
                value: _phrases,
                onChanged: _busy
                    ? null
                    : (bool? v) => setState(() => _phrases = v!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<AnkiExportFormat>(
                isExpanded: true,
                initialValue: _format,
                decoration: const InputDecoration(
                  labelText: '文件格式',
                  border: OutlineInputBorder(),
                ),
                items: const <DropdownMenuItem<AnkiExportFormat>>[
                  DropdownMenuItem<AnkiExportFormat>(
                    value: AnkiExportFormat.apkg,
                    child: Text('Anki 牌组 (.apkg) · 推荐'),
                  ),
                  DropdownMenuItem<AnkiExportFormat>(
                    value: AnkiExportFormat.tsv,
                    child: Text('TSV 表格 (.tsv)'),
                  ),
                  DropdownMenuItem<AnkiExportFormat>(
                    value: AnkiExportFormat.csv,
                    child: Text('CSV 表格 (.csv)'),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (AnkiExportFormat? v) => setState(() => _format = v!),
              ),
              const SizedBox(height: 16),
              if (_format == AnkiExportFormat.apkg)
                TextField(
                  controller: _deck,
                  enabled: !_busy,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: '牌组名称',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
              const SizedBox(height: 14),
              Text(
                _format == AnkiExportFormat.apkg
                    ? '自带卡片样式，导入即可复习；重复导入可更新同一张卡片。'
                    : '普通表格，包含英文、音标、释义、原句语境等独立字段。',
                style: const TextStyle(
                  color: AppDesignTokens.textPrimary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '相同表达合并语境，不会改变应用内的复习进度。',
                style: TextStyle(
                  fontSize: 12,
                  color: AppDesignTokens.textPrimary,
                  height: 1.5,
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (words + phrases == 0)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('还没有收藏内容，先去收藏单词或短语吧。'),
                ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy || selected == 0 ? null : _export,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppDesignTokens.brandGreen,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(_busy ? '正在准备…' : '导出文件'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
