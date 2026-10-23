import 'dart:async';

import 'package:alphabet_list_view/alphabet_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../anki_export/presentation/anki_export_sheet.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../../shared/presentation/pill_segmented_control.dart';
import 'word_book_provider.dart';
import 'word_detail_screen.dart';

class WordsScreen extends ConsumerStatefulWidget {
  const WordsScreen({super.key});

  @override
  ConsumerState<WordsScreen> createState() => _WordsScreenState();
}

class _WordsScreenState extends ConsumerState<WordsScreen> {
  String _query = '';
  bool _favoritesOnly = true;

  @override
  void initState() {
    super.initState();
    ref.read(wordBookProvider.notifier).refreshOfflineDefinitions();
  }

  Future<void> _editWord(WordEntry entry) async {
    final TextEditingController wordController = TextEditingController(
      text: entry.word,
    );
    final TextEditingController definitionController = TextEditingController(
      text: entry.definitionCn ?? entry.offlineDefinitionCn ?? '',
    );
    final bool? shouldSave = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('编辑单词'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: wordController,
              autofocus: true,
              decoration: const InputDecoration(labelText: '英文单词'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: definitionController,
              decoration: const InputDecoration(labelText: '中文释义'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (!mounted || shouldSave != true) {
      wordController.dispose();
      definitionController.dispose();
      return;
    }
    final bool saved = ref
        .read(wordBookProvider.notifier)
        .editWord(
          rawWord: entry.word,
          nextWord: wordController.text,
          definitionCn: definitionController.text,
        );
    wordController.dispose();
    definitionController.dispose();
    if (!saved && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('单词不能为空，也不能与已有单词重复。')));
    }
  }

  Future<void> _deleteWord(WordEntry entry) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除单词？'),
        content: Text('“${entry.word}”及其影片语境将被删除。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if ((shouldDelete ?? false) && mounted) {
      ref.read(wordBookProvider.notifier).deleteWord(entry.word);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<WordEntry> entries = ref.watch(wordBookProvider);
    final List<WordEntry> filtered = entries
        .where((WordEntry entry) {
          return (!_favoritesOnly || entry.favorite) &&
              entry.word.contains(_query.trim().toLowerCase());
        })
        .toList(growable: false);
    final int coveredVideos = entries
        .expand((WordEntry item) => item.occurrences)
        .map((WordOccurrence item) => item.episodeId)
        .toSet()
        .length;

    return PadScaffold(
      currentDestination: AppNavDestination.words,
      topBar: const PadTopBar(
        title: '单词本',
        actions: <Widget>[AnkiExportButton()],
      ),
      body: Padding(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              children: <Widget>[
                _Summary(
                  entries: entries.length,
                  videos: coveredVideos,
                  favorites: entries
                      .where((WordEntry item) => item.favorite)
                      .length,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  key: const Key('words-view-tabs'),
                  width: double.infinity,
                  child: PillSegmentedControl<bool>(
                    value: _favoritesOnly,
                    options: const <SegmentOption<bool>>[
                      SegmentOption<bool>(value: true, label: '已收藏'),
                      SegmentOption<bool>(value: false, label: '全部单词'),
                    ],
                    onValueChanged: (bool value) =>
                        setState(() => _favoritesOnly = value),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  onChanged: (String value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: _favoritesOnly ? '搜索收藏的单词' : '搜索学过的单词',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            _query.trim().isNotEmpty
                                ? '没有找到匹配的单词，换个关键词试试。'
                                : _favoritesOnly
                                ? '还没有收藏单词，点击单词旁的收藏图标就能加入。'
                                : '播放带英文字幕的视频后，单词会自动出现在这里。',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : AlphabetListView(
                          key: ValueKey<bool>(_favoritesOnly),
                          items: _buildGroups(filtered),
                          options: AlphabetListViewOptions(
                            listOptions: ListOptions(
                              padding: const EdgeInsets.only(
                                right: 12,
                                bottom: 24,
                              ),
                              listHeaderBuilder:
                                  (BuildContext context, String tag) => Padding(
                                    padding: const EdgeInsets.only(
                                      top: 12,
                                      bottom: 8,
                                    ),
                                    child: Text(
                                      tag,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: AppDesignTokens.brandGreenDark,
                                      ),
                                    ),
                                  ),
                            ),
                            scrollbarOptions: ScrollbarOptions(
                              width: 22,
                              padding: const EdgeInsets.only(left: 4),
                              symbolBuilder:
                                  (
                                    BuildContext context,
                                    String symbol,
                                    AlphabetScrollbarItemState state,
                                  ) => Text(
                                    symbol,
                                    style: TextStyle(
                                      color:
                                          state ==
                                              AlphabetScrollbarItemState.active
                                          ? AppDesignTokens.brandGreenDark
                                          : AppDesignTokens.textSecondary
                                                .withValues(alpha: 0.68),
                                      fontSize: 12,
                                      fontWeight:
                                          state ==
                                              AlphabetScrollbarItemState.active
                                          ? FontWeight.w900
                                          : FontWeight.w700,
                                    ),
                                  ),
                            ),
                            overlayOptions: const OverlayOptions(
                              showOverlay: false,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<AlphabetListViewItemGroup> _buildGroups(List<WordEntry> entries) {
    final Map<String, List<WordEntry>> groups = <String, List<WordEntry>>{};
    for (final WordEntry entry in entries) {
      final String tag = entry.word.substring(0, 1).toUpperCase();
      (groups[tag] ??= <WordEntry>[]).add(entry);
    }
    return groups.entries
        .map(
          (MapEntry<String, List<WordEntry>> group) =>
              AlphabetListViewItemGroup(
                tag: group.key,
                children: group.value
                    .map(
                      (WordEntry entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _WordCard(
                          entry: entry,
                          onEdit: () => _editWord(entry),
                          onDelete: () => _deleteWord(entry),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
        )
        .toList(growable: false);
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.entries,
    required this.videos,
    required this.favorites,
  });
  final int entries;
  final int videos;
  final int favorites;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppDesignTokens.brandGreen,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      children: <Widget>[
        _Metric(value: '$entries', label: '已见单词'),
        _Metric(value: '$videos', label: '覆盖视频'),
        _Metric(value: '$favorites', label: '收藏单词'),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: <Widget>[
        Text(
          value,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _WordCard extends ConsumerWidget {
  const _WordCard({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });
  final WordEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  void _openDetails(BuildContext context) => unawaited(
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => WordDetailDialog(word: entry.word),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String translation =
        entry.definitionCn ?? entry.offlineDefinitionCn ?? '暂无释义';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openDetails(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.word,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      translation,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, height: 1.2),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 66,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '${entry.occurrenceCount} 次',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${entry.videoCount} 个视频',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: entry.favorite ? '取消收藏' : '收藏单词',
                onPressed: () => ref
                    .read(wordBookProvider.notifier)
                    .toggleFavorite(entry.word),
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  entry.favorite
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                ),
              ),
              PopupMenuButton<_WordAction>(
                tooltip: '更多操作',
                onSelected: (_WordAction action) {
                  switch (action) {
                    case _WordAction.details:
                      _openDetails(context);
                    case _WordAction.edit:
                      onEdit();
                    case _WordAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<_WordAction>>[
                      const PopupMenuItem<_WordAction>(
                        value: _WordAction.details,
                        child: Text('查看详情'),
                      ),
                      const PopupMenuItem<_WordAction>(
                        value: _WordAction.edit,
                        child: Text('编辑'),
                      ),
                      const PopupMenuItem<_WordAction>(
                        value: _WordAction.delete,
                        child: Text('删除'),
                      ),
                    ],
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _WordAction { details, edit, delete }
