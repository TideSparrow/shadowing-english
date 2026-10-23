import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/presentation/asr_subtitle_cache.dart';
import '../../player/presentation/asr_subtitle_job.dart';
import '../../player/presentation/player_mock_state.dart';
import '../../player/presentation/player_subtitle_loader.dart';
import '../../shared/presentation/continue_learning_button.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import 'settings_provider.dart';

class AiSubtitleManagementScreen extends ConsumerStatefulWidget {
  const AiSubtitleManagementScreen({
    this.cache = const AsrSubtitleCache(),
    super.key,
  });

  final AsrSubtitleCache cache;

  @override
  ConsumerState<AiSubtitleManagementScreen> createState() =>
      _AiSubtitleManagementScreenState();
}

class _AiSubtitleManagementScreenState
    extends ConsumerState<AiSubtitleManagementScreen> {
  late Future<List<AiSubtitleCacheEntry>> _entries;
  String? _regeneratingPath;
  final Set<String> _selectedPaths = <String>{};
  bool _selectionMode = false;

  AsrSubtitleCache get _cache => widget.cache;

  @override
  void initState() {
    super.initState();
    _entries = _cache.listEntries();
  }

  void _reload() {
    setState(() {
      _selectedPaths.clear();
      _selectionMode = false;
      _entries = _cache.listEntries();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: const ContinueLearningButton(),
      backgroundColor: AppDesignTokens.softWhite,
      body: Column(
        children: <Widget>[
          PadTopBar(
            title: '管理 AI 字幕',
            description: '修正内容、备份文件，或在识别不理想时重新生成。',
            leading: _RoundIconButton(
              tooltip: '返回设置',
              onPressed: () => Navigator.of(context).pop(),
              icon: Icons.arrow_back_rounded,
            ),
            trailing: _SecondaryButton(
              icon: _selectionMode
                  ? Icons.close_rounded
                  : Icons.checklist_rounded,
              label: _selectionMode ? '取消选择' : '批量选择',
              onPressed: _selectionMode
                  ? _leaveSelectionMode
                  : () => setState(() => _selectionMode = true),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<AiSubtitleCacheEntry>>(
              future: _entries,
              builder:
                  (
                    BuildContext context,
                    AsyncSnapshot<List<AiSubtitleCacheEntry>> snapshot,
                  ) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _EmptyState(
                        icon: Icons.error_outline_rounded,
                        title: '读取 AI 字幕失败',
                        actionLabel: '重试',
                        onAction: _reload,
                      );
                    }
                    final List<AiSubtitleCacheEntry> entries =
                        snapshot.data ?? const <AiSubtitleCacheEntry>[];
                    if (entries.isEmpty) {
                      return const _EmptyState(
                        icon: Icons.subtitles_off_outlined,
                        title: '还没有生成过 AI 字幕',
                        description: '在视频播放页生成后，会显示在这里。',
                      );
                    }
                    return Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 840),
                        child: Column(
                          children: <Widget>[
                            _ManagementIntro(
                              count: entries.length,
                              selectionMode: _selectionMode,
                              selectedCount: _selectedPaths.length,
                              allSelected:
                                  _selectedPaths.length == entries.length,
                              onToggleAll: () => _toggleAll(entries),
                              onExportSelected: _selectedPaths.isEmpty
                                  ? null
                                  : () => _exportSelected(entries),
                              onDeleteSelected: _selectedPaths.isEmpty
                                  ? null
                                  : () => _deleteSelected(entries),
                            ),
                            Expanded(
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  32,
                                  16,
                                  32,
                                  40,
                                ),
                                itemCount: entries.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 16),
                                itemBuilder: (BuildContext context, int index) {
                                  final AiSubtitleCacheEntry entry =
                                      entries[index];
                                  return _SubtitleCard(
                                    entry: entry,
                                    selected: _selectedPaths.contains(
                                      entry.cacheFile.path,
                                    ),
                                    selectionMode: _selectionMode,
                                    regenerating:
                                        _regeneratingPath ==
                                        entry.cacheFile.path,
                                    onToggleSelection: () =>
                                        _toggleSelection(entry),
                                    onEdit: () => _edit(entry),
                                    onExport: () => _export(entry),
                                    onRegenerate: () => _regenerate(entry),
                                    onDelete: () => _delete(entry),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(AiSubtitleCacheEntry entry) async {
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AiSubtitleEditorScreen(entry: entry, cache: _cache),
      ),
    );
    if ((changed ?? false) && mounted) _reload();
  }

  void _leaveSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedPaths.clear();
    });
  }

  void _toggleSelection(AiSubtitleCacheEntry entry) {
    setState(() {
      _selectionMode = true;
      final String path = entry.cacheFile.path;
      if (!_selectedPaths.add(path)) _selectedPaths.remove(path);
    });
  }

  void _toggleAll(List<AiSubtitleCacheEntry> entries) {
    setState(() {
      if (_selectedPaths.length == entries.length) {
        _selectedPaths.clear();
      } else {
        _selectedPaths
          ..clear()
          ..addAll(
            entries.map((AiSubtitleCacheEntry entry) => entry.cacheFile.path),
          );
      }
    });
  }

  Future<void> _exportSelected(List<AiSubtitleCacheEntry> entries) async {
    final List<AiSubtitleCacheEntry> selected = entries
        .where(
          (AiSubtitleCacheEntry entry) =>
              _selectedPaths.contains(entry.cacheFile.path),
        )
        .toList(growable: false);
    try {
      for (final AiSubtitleCacheEntry entry in selected) {
        await _cache.exportEntry(entry);
      }
      _message('已导出 ${selected.length} 份 AI 字幕。');
      _leaveSelectionMode();
    } catch (_) {
      _message('批量导出失败，请稍后重试。');
    }
  }

  Future<void> _deleteSelected(List<AiSubtitleCacheEntry> entries) async {
    final List<AiSubtitleCacheEntry> selected = entries
        .where(
          (AiSubtitleCacheEntry entry) =>
              _selectedPaths.contains(entry.cacheFile.path),
        )
        .toList(growable: false);
    final bool confirmed = await _confirm(
      title: '删除所选 ${selected.length} 份字幕？',
      content: '所选字幕和对应生成断点都会被删除，此操作无法恢复。',
      action: '删除所选',
      danger: true,
    );
    if (!confirmed) return;
    for (final AiSubtitleCacheEntry entry in selected) {
      await _cache.deleteEntry(entry);
    }
    if (mounted) _reload();
  }

  Future<void> _export(AiSubtitleCacheEntry entry) async {
    try {
      await _cache.exportEntry(entry);
      _message('已导出到 Downloads/Shadowing English/AI Subtitles。');
    } catch (_) {
      _message('导出失败，请稍后重试。');
    }
  }

  Future<void> _regenerate(AiSubtitleCacheEntry entry) async {
    if (!File(entry.videoPath).existsSync()) {
      _message('原视频文件已移动或删除，无法重新生成。');
      return;
    }
    final bool confirmed = await _confirm(
      title: '重新生成 AI 字幕？',
      content: '这会再次调用当前设置中的 AI 服务，可能产生费用。生成失败时会保留现有字幕。',
      action: '重新生成',
    );
    if (!confirmed || !mounted) return;
    setState(() => _regeneratingPath = entry.cacheFile.path);
    try {
      const AsrSubtitleJobRunner runner = AsrSubtitleJobRunner();
      final LearningSettingsState settings = ref.read(learningSettingsProvider);
      List<PlayerSubtitleLine> referenceSubtitleLines =
          const <PlayerSubtitleLine>[];
      if (entry.referenceSignature != null) {
        final Map<String, dynamic> cached = await _cache.readEntry(entry);
        final Object? storedReferenceLines = cached['referenceLines'];
        if (storedReferenceLines is! List) {
          throw const FormatException('缺少原字幕快照，请先在播放器中重新生成一次。');
        }
        referenceSubtitleLines = parseSubtitleLines(
          jsonEncode(<String, Object?>{
            'version': 1,
            'lines': storedReferenceLines,
          }),
        );
        if (referenceSubtitleLines.isEmpty) {
          throw const FormatException('原字幕快照无效，请先在播放器中重新生成一次。');
        }
      }
      final String raw = await runner.run(
        episodeId: entry.episodeId,
        videoPath: entry.videoPath,
        settings: settings,
        referenceSubtitleLines: referenceSubtitleLines,
        referenceSignatureOverride: entry.referenceSignature,
        forceRegenerate: true,
      );
      final AsrSubtitleRepairSummary repairSummary = await runner
          .readRepairSummary(
            episodeId: entry.episodeId,
            videoPath: entry.videoPath,
            settings: settings,
          );
      final String? warning = subtitleGenerationWarning(raw);
      _message(
        repairSummary.appendTo(
          warning == null ? 'AI 字幕已重新生成' : 'AI 字幕已重新生成；$warning',
        ),
      );
      _reload();
    } catch (error) {
      _message('重新生成失败：$error');
    } finally {
      if (mounted) setState(() => _regeneratingPath = null);
    }
  }

  Future<void> _delete(AiSubtitleCacheEntry entry) async {
    final bool confirmed = await _confirm(
      title: '删除这份 AI 字幕？',
      content: '删除后无法恢复，但可以从视频播放页重新生成。',
      action: '删除',
      danger: true,
    );
    if (!confirmed) return;
    await _cache.deleteEntry(entry);
    if (mounted) _reload();
  }

  Future<bool> _confirm({
    required String title,
    required String content,
    required String action,
    bool danger = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: danger
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                      )
                    : null,
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}

class _SubtitleCard extends StatelessWidget {
  const _SubtitleCard({
    required this.entry,
    required this.selected,
    required this.selectionMode,
    required this.regenerating,
    required this.onToggleSelection,
    required this.onEdit,
    required this.onExport,
    required this.onRegenerate,
    required this.onDelete,
  });

  final AiSubtitleCacheEntry entry;
  final bool selected;
  final bool selectionMode;
  final bool regenerating;
  final VoidCallback onToggleSelection;
  final VoidCallback onEdit;
  final VoidCallback onExport;
  final VoidCallback onRegenerate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFF4FFEC) : AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: selected
              ? AppDesignTokens.brandGreen
              : AppDesignTokens.borderGray,
          width: selected ? 3 : 2,
        ),
        boxShadow: AppDesignTokens.toyCardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: selectionMode ? onToggleSelection : null,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppDesignTokens.skyLight,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.closed_caption_rounded,
                        color: AppDesignTokens.primaryBlueDark,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            _fileName(entry.videoPath),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              height: 1.35,
                              fontWeight: FontWeight.w800,
                              color: AppDesignTokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${entry.lineCount} 句 · ${entry.provider} / ${entry.model}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: AppDesignTokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selectionMode)
                      Checkbox(
                        key: ValueKey<String>(
                          'ai-subtitle-select-${entry.cacheFile.path}',
                        ),
                        value: selected,
                        activeColor: AppDesignTokens.brandGreen,
                        onChanged: (_) => onToggleSelection(),
                      )
                    else
                      _InfoBadge(
                        label:
                            '${_formatDate(entry.generatedAt)} · ${_formatSize(entry.sizeBytes)}',
                      ),
                  ],
                ),
                if (!selectionMode) ...<Widget>[
                  const SizedBox(height: 18),
                  const Divider(height: 2, color: AppDesignTokens.borderGray),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: <Widget>[
                      _CardAction(
                        icon: Icons.edit_rounded,
                        label: '编辑字幕',
                        prominent: true,
                        onPressed: onEdit,
                      ),
                      _CardAction(
                        icon: Icons.download_rounded,
                        label: '导出',
                        onPressed: onExport,
                      ),
                      _CardAction(
                        icon: Icons.refresh_rounded,
                        label: regenerating ? '生成中' : '重新生成',
                        loading: regenerating,
                        onPressed: regenerating ? null : onRegenerate,
                      ),
                      _CardAction(
                        icon: Icons.delete_outline_rounded,
                        label: '删除',
                        danger: true,
                        onPressed: regenerating ? null : onDelete,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ManagementIntro extends StatelessWidget {
  const _ManagementIntro({
    required this.count,
    required this.selectionMode,
    required this.selectedCount,
    required this.allSelected,
    required this.onToggleAll,
    required this.onExportSelected,
    required this.onDeleteSelected,
  });

  final int count;
  final bool selectionMode;
  final int selectedCount;
  final bool allSelected;
  final VoidCallback onToggleAll;
  final VoidCallback? onExportSelected;
  final VoidCallback? onDeleteSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: selectionMode
              ? const Color(0xFFF4FFEC)
              : AppDesignTokens.skyLight,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selectionMode
                ? AppDesignTokens.brandGreen
                : const Color(0xFFBDEBFF),
            width: 2,
          ),
        ),
        child: selectionMode
            ? Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '已选择 $selectedCount 项',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: onToggleAll,
                          child: Text(allSelected ? '取消全选' : '全选 $count 项'),
                        ),
                      ],
                    ),
                  ),
                  _SecondaryButton(
                    icon: Icons.download_rounded,
                    label: '导出所选',
                    onPressed: onExportSelected,
                  ),
                  const SizedBox(width: 12),
                  _SecondaryButton(
                    icon: Icons.delete_outline_rounded,
                    label: '删除所选',
                    danger: true,
                    onPressed: onDeleteSelected,
                  ),
                ],
              )
            : Row(
                children: <Widget>[
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppDesignTokens.appWhite,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: AppDesignTokens.primaryBlue,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '$count 份 AI 字幕',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '编辑时会保护单词时间轴；重新生成失败也不会覆盖当前字幕。',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.prominent = false,
    this.danger = false,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool prominent;
  final bool danger;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final Color color = danger
        ? const Color(0xFFFF4B4B)
        : prominent
        ? AppDesignTokens.brandGreenDark
        : AppDesignTokens.primaryBlueDark;
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: color,
        backgroundColor: prominent ? const Color(0xFFF4FFEC) : Colors.white,
        side: BorderSide(
          color: prominent
              ? AppDesignTokens.brandGreen
              : AppDesignTokens.borderGray,
          width: 2,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
      onPressed: onPressed,
      icon: loading
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      label: Text(label),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppDesignTokens.softGray,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppDesignTokens.textSecondary,
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(56),
        backgroundColor: AppDesignTokens.appWhite,
        foregroundColor: AppDesignTokens.primaryBlue,
        side: const BorderSide(color: AppDesignTokens.borderGray, width: 2),
      ),
      icon: Icon(icon),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        foregroundColor: danger
            ? const Color(0xFFFF4B4B)
            : AppDesignTokens.primaryBlueDark,
        backgroundColor: AppDesignTokens.appWhite,
        side: const BorderSide(color: AppDesignTokens.borderGray, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class AiSubtitleEditorScreen extends StatefulWidget {
  const AiSubtitleEditorScreen({
    required this.entry,
    required this.cache,
    super.key,
  });

  final AiSubtitleCacheEntry entry;
  final AsrSubtitleCache cache;

  @override
  State<AiSubtitleEditorScreen> createState() => _AiSubtitleEditorScreenState();
}

class _AiSubtitleEditorScreenState extends State<AiSubtitleEditorScreen> {
  Map<String, dynamic>? _content;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final Map<String, dynamic> content = await widget.cache.readEntry(
        widget.entry,
      );
      if (mounted) setState(() => _content = content);
    } catch (_) {
      if (mounted) Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<dynamic>? lines = _content?['lines'] as List<dynamic>?;
    return Scaffold(
      floatingActionButton: const ContinueLearningButton(),
      backgroundColor: AppDesignTokens.softWhite,
      body: Column(
        children: <Widget>[
          PadTopBar(
            title: '编辑 AI 字幕',
            description: _fileName(widget.entry.videoPath),
            leading: _RoundIconButton(
              tooltip: '返回字幕管理',
              onPressed: () => Navigator.of(context).pop(_changed),
              icon: Icons.arrow_back_rounded,
            ),
            trailing: const _InfoBadge(label: '自动保存'),
          ),
          Expanded(
            child: lines == null
                ? const Center(child: CircularProgressIndicator())
                : Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 840),
                      child: Column(
                        children: <Widget>[
                          const _EditorGuide(),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                32,
                                16,
                                32,
                                40,
                              ),
                              itemCount: lines.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 16),
                              itemBuilder: (BuildContext context, int index) {
                                final Map<String, dynamic> line =
                                    lines[index] as Map<String, dynamic>;
                                return _EditorLineCard(
                                  index: index,
                                  line: line,
                                  onEdit: () => _editLine(line, index),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _editLine(Map<String, dynamic> line, int lineIndex) async {
    final TextEditingController english = TextEditingController(
      text: line['english'] as String? ?? '',
    );
    final TextEditingController chinese = TextEditingController(
      text: line['chinese'] as String? ?? '',
    );
    final List<dynamic> words =
        line['words'] as List<dynamic>? ?? const <dynamic>[];
    final List<String> wordTexts = words
        .map(
          (dynamic word) =>
              (word as Map<String, dynamic>)['text'] as String? ?? '',
        )
        .toList(growable: false);
    String? error;
    final bool saved =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              return AlertDialog(
                title: Text('编辑第 ${lineIndex + 1} 句'),
                content: SizedBox(
                  width: 620,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (wordTexts.isNotEmpty) ...<Widget>[
                          const Text(
                            '单词级编辑',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppDesignTokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '点击单词即可修改文字，原有开始和结束时间会保留。',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppDesignTokens.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: List<Widget>.generate(
                              wordTexts.length,
                              (int index) => ActionChip(
                                key: ValueKey<String>(
                                  'ai-subtitle-word-$lineIndex-$index',
                                ),
                                avatar: const Icon(
                                  Icons.edit_rounded,
                                  size: 16,
                                  color: AppDesignTokens.primaryBlueDark,
                                ),
                                label: Text(wordTexts[index]),
                                side: const BorderSide(
                                  color: AppDesignTokens.borderGray,
                                  width: 2,
                                ),
                                backgroundColor: AppDesignTokens.skyLight,
                                onPressed: () async {
                                  final String? next = await _editWord(
                                    context,
                                    wordTexts[index],
                                  );
                                  if (next == null ||
                                      next == wordTexts[index]) {
                                    return;
                                  }
                                  setDialogState(() {
                                    wordTexts[index] = next;
                                    english.text = _replaceTokens(
                                      english.text,
                                      wordTexts,
                                    );
                                    error = null;
                                  });
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        TextField(
                          controller: english,
                          maxLines: 3,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: const InputDecoration(
                            labelText: '英文整句',
                            helperText: '整句修改时，英文单词数量必须保持不变。',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: chinese,
                          maxLines: 3,
                          style: const TextStyle(fontSize: 16),
                          decoration: const InputDecoration(
                            labelText: '中文翻译',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        if (error != null) ...<Widget>[
                          const SizedBox(height: 12),
                          Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () {
                      final String? validation = _validateEnglishEdit(
                        line,
                        english.text,
                      );
                      if (validation != null) {
                        setDialogState(() => error = validation);
                        return;
                      }
                      Navigator.of(context).pop(true);
                    },
                    child: const Text('保存'),
                  ),
                ],
              );
            },
          ),
        ) ??
        false;
    if (!saved || !mounted) {
      return;
    }
    final String nextEnglish = english.text.trim();
    line['english'] = nextEnglish;
    line['chinese'] = chinese.text.trim();
    final List<String> tokens = _tokens(nextEnglish);
    for (int index = 0; index < words.length; index += 1) {
      (words[index] as Map<String, dynamic>)['text'] = tokens[index];
    }
    await widget.cache.updateEntry(widget.entry, _content!);
    if (mounted) {
      setState(() => _changed = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('字幕已保存。')));
    }
  }

  String? _validateEnglishEdit(Map<String, dynamic> line, String nextEnglish) {
    final String currentEnglish = line['english'] as String? ?? '';
    if (nextEnglish.trim() == currentEnglish.trim()) return null;
    final List<dynamic> words = line['words'] as List<dynamic>? ?? <dynamic>[];
    if (words.isEmpty) return '这句字幕没有单词时间轴，只能修改中文。';
    if (_tokens(nextEnglish).length != words.length) {
      return '修改后的英文必须保持 ${words.length} 个单词；如需改写整句，请重新生成字幕。';
    }
    return null;
  }

  Future<String?> _editWord(BuildContext context, String current) async {
    String nextValue = current;
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('修改单词'),
        content: TextFormField(
          key: const ValueKey<String>('ai-subtitle-word-field'),
          initialValue: current,
          autofocus: true,
          onChanged: (String value) => nextValue = value,
          decoration: const InputDecoration(
            labelText: '单词',
            helperText: '只修改文字，单词时间保持不变。',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final String next = nextValue.trim();
              if (_tokens(next).length != 1) return;
              Navigator.of(context).pop(next);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return result;
  }
}

class _EditorGuide extends StatelessWidget {
  const _EditorGuide();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppDesignTokens.skyLight,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFBDEBFF), width: 2),
        ),
        child: const Row(
          children: <Widget>[
            Icon(
              Icons.touch_app_rounded,
              color: AppDesignTokens.primaryBlue,
              size: 32,
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '点开一句字幕开始校对',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '可以逐个修改英文单词，也可以修改整句和中文；所有单词时间都会保留。',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorLineCard extends StatelessWidget {
  const _EditorLineCard({
    required this.index,
    required this.line,
    required this.onEdit,
  });

  final int index;
  final Map<String, dynamic> line;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final int wordCount =
        (line['words'] as List<dynamic>? ?? const <dynamic>[]).length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppDesignTokens.borderGray, width: 2),
        boxShadow: AppDesignTokens.toyCardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          key: ValueKey<String>('ai-subtitle-line-$index'),
          borderRadius: BorderRadius.circular(24),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppDesignTokens.purpleLight,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF6B3FE8),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        line['english'] as String? ?? '',
                        style: const TextStyle(
                          fontSize: 20,
                          height: 1.45,
                          fontWeight: FontWeight.w700,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        (line['chinese'] as String? ?? '').trim().isEmpty
                            ? '暂无中文翻译'
                            : line['chinese'] as String,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                          color: AppDesignTokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          _InfoBadge(
                            label:
                                '${_formatTimestamp(line['startMs'])} - ${_formatTimestamp(line['endMs'])}',
                          ),
                          _InfoBadge(label: '$wordCount 个单词时间点'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4FFEC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppDesignTokens.brandGreen,
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    color: AppDesignTokens.brandGreenDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          if (description != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(description!),
          ],
          if (onAction != null) ...<Widget>[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

List<String> _tokens(String value) => RegExp(
  "[A-Za-z0-9]+(?:[’'-][A-Za-z0-9]+)?",
).allMatches(value).map((RegExpMatch match) => match.group(0)!).toList();

String _replaceTokens(String source, List<String> replacements) {
  final RegExp pattern = RegExp("[A-Za-z0-9]+(?:[’'-][A-Za-z0-9]+)?");
  final List<RegExpMatch> matches = pattern.allMatches(source).toList();
  if (matches.length != replacements.length) return replacements.join(' ');
  final StringBuffer result = StringBuffer();
  int cursor = 0;
  for (int index = 0; index < matches.length; index += 1) {
    final RegExpMatch match = matches[index];
    result
      ..write(source.substring(cursor, match.start))
      ..write(replacements[index]);
    cursor = match.end;
  }
  result.write(source.substring(cursor));
  return result.toString();
}

String _fileName(String path) => path.replaceAll(r'\', '/').split('/').last;

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

String _formatTimestamp(Object? value) {
  final int milliseconds = value is int ? value : 0;
  final Duration duration = Duration(milliseconds: milliseconds);
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(duration.inMinutes)}:${two(duration.inSeconds.remainder(60))}';
}
