import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/presentation/settings_provider.dart';
import '../../shared/data/word_pronunciation_service.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/lesson_service.dart';
import '../data/lesson_speech_rate.dart';
import '../data/lesson_store.dart';
import '../domain/intensive_lesson.dart';
import 'lesson_card_view.dart';
import 'lesson_narrator.dart';

export 'lesson_card_view.dart' show LessonCardView;

enum LessonDialogAction { source, settings, resume }

Future<LessonDialogAction?> showLessonDialog(
  BuildContext context, {
  required LessonSource source,
  IntensiveLesson? savedLesson,
  bool canResume = false,
  bool canOpenSource = true,
}) => showDialog<LessonDialogAction>(
  context: context,
  builder: (BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        brightness: Brightness.light,
        colorScheme: theme.colorScheme.copyWith(
          brightness: Brightness.light,
          surface: Colors.white,
          onSurface: AppDesignTokens.textPrimary,
          primary: const Color(0xFF0875D8),
        ),
        textTheme: theme.textTheme.apply(
          bodyColor: AppDesignTokens.textPrimary,
          displayColor: AppDesignTokens.textPrimary,
        ),
      ),
      child: LessonDialog(
        source: source,
        savedLesson: savedLesson,
        canResume: canResume,
        canOpenSource: canOpenSource,
      ),
    );
  },
);

class LessonDialog extends ConsumerStatefulWidget {
  const LessonDialog({
    required this.source,
    this.savedLesson,
    this.canResume = false,
    this.canOpenSource = true,
    super.key,
  });
  final LessonSource source;
  final IntensiveLesson? savedLesson;
  final bool canResume;
  final bool canOpenSource;

  @override
  ConsumerState<LessonDialog> createState() => _LessonDialogState();
}

class _LessonDialogState extends ConsumerState<LessonDialog> {
  CancelToken _cancel = CancelToken();
  final ScrollController _scroll = ScrollController();
  late final LessonNarrator _narrator;
  final List<String> _illustrations = List<String>.of(lessonIllustrationAssets)
    ..shuffle();
  IntensiveLesson? _lesson;
  bool _loading = true;
  bool _saved = false;
  bool _saving = false;
  bool _speaking = false;
  bool _showScript = false;
  int _card = 0;
  int _segment = -1;
  int _speechSession = 0;
  String? _error;
  LessonTokenUsage? _requestUsage;
  String? _requestModel;

  @override
  void initState() {
    super.initState();
    _narrator = LessonNarrator(
      service: ref.read(wordPronunciationServiceProvider),
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    _cancel.cancel('dialog closed');
    _speechSession++;
    unawaited(_narrator.stop().catchError((Object _) {}));
    _scroll.dispose();
    super.dispose();
  }

  bool _opening = false;
  Future<void> _load() async {
    if (_opening) return;
    _opening = true;
    setState(() => _loading = true);
    try {
      await _loadOnce();
    } finally {
      _opening = false;
    }
  }

  Future<void> _loadOnce() async {
    try {
      final IntensiveLesson? saved =
          widget.savedLesson ??
          await ref.read(lessonBookProvider.notifier).find(widget.source.id);
      if (!mounted) return;
      _lesson = saved;
      if (_lesson != null) {
        setState(() {
          _saved = true;
          _loading = false;
        });
        return;
      }
      if (!canGenerateLesson(ref.read(learningSettingsProvider))) {
        setState(() => _loading = false);
        return;
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '无法读取本地精讲，请关闭后重试。已有内容不会被覆盖。';
        });
      }
      return;
    }
    await _generate();
  }

  Future<void> _generate() async {
    if (!mounted) return;
    if (_cancel.isCancelled) _cancel = CancelToken();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final IntensiveLesson lesson = await ref
          .read(lessonServiceProvider)
          .generate(
            source: widget.source,
            settings: ref.read(learningSettingsProvider),
            cancelToken: _cancel,
          );
      if (!mounted || _cancel.isCancelled) return;
      setState(() => _lesson = lesson);
      await _save();
    } catch (error) {
      if (mounted) {
        setState(() {
          if (error is LessonGenerationException) {
            _requestUsage = error.usage;
            _requestModel = error.model;
          }
          _error = '解析未完成，请检查大模型配置后重试。不会自动重发请求。';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(lessonBookProvider.notifier).save(_lesson!);
      if (mounted) {
        setState(() {
          _saved = true;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '精讲已生成，但保存失败。请重试保存，无需再次生成。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _close(LessonDialogAction action) async {
    await _stopSpeech();
    if (mounted) Navigator.pop(context, action);
  }

  Future<void> _stopSpeech() async {
    _speechSession++;
    if (mounted) {
      setState(() {
        _speaking = false;
        _segment = -1;
      });
    }
    try {
      await _narrator.stop();
    } catch (_) {
      /* Stop must still invalidate the queue. */
    }
  }

  Future<void> _toggleSpeech() async {
    if (_speaking) return _stopSpeech();
    final int session = ++_speechSession;
    setState(() => _speaking = true);
    try {
      await _narrator.play(
        lesson: _lesson!,
        fromCard: _card,
        rate: () =>
            ref.read(lessonSpeechRateProvider) ??
            ref.read(learningSettingsProvider).ttsRate,
        onSegment: (int card, int segment) {
          if (!mounted || session != _speechSession) return;
          if (card != _card && _scroll.hasClients) _scroll.jumpTo(0);
          setState(() {
            _card = card;
            _segment = segment;
          });
        },
      );
    } catch (_) {
      if (mounted && session == _speechSession) _message('设备朗读不可用，请检查系统中英文语音。');
    } finally {
      if (mounted && session == _speechSession) {
        setState(() {
          _speaking = false;
          _segment = -1;
        });
      }
    }
  }

  void _selectCard(int card) {
    unawaited(_stopSpeech());
    setState(() => _card = card);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _setSpeechRate(double value) async {
    try {
      await ref
          .read(lessonSpeechRateProvider.notifier)
          .setRate(value == 0 ? null : value);
    } catch (_) {
      if (mounted) _message('语速保存失败，请重试。');
    }
  }

  Widget _speechRateControl() {
    final double? override = ref.watch(lessonSpeechRateProvider);
    final double systemRate = ref.watch(
      learningSettingsProvider.select(
        (LearningSettingsState settings) => settings.ttsRate,
      ),
    );
    return Semantics(
      container: true,
      child: Tooltip(
        message: '仅用于精讲朗读，播放中调整从下一句生效。',
        child: Container(
          width: 280,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFCFD8DC)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.speed_rounded,
                size: 18,
                color: Color(0xFF53625A),
              ),
              const SizedBox(width: 6),
              const Text('语速', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<double>(
                    key: const Key('lesson-speech-rate'),
                    value: override ?? 0,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(16),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppDesignTokens.textPrimary,
                    ),
                    items: <DropdownMenuItem<double>>[
                      DropdownMenuItem<double>(
                        value: 0,
                        child: Text(
                          '跟随系统（$systemRate×）',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      for (final double rate in ttsRateOptions)
                        DropdownMenuItem<double>(
                          value: rate,
                          child: Text('$rate×'),
                        ),
                    ],
                    onChanged: (double? value) {
                      if (value != null) unawaited(_setSpeechRate(value));
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final bool compact = size.width < 700;
    final IntensiveLesson? lesson = _lesson;
    return Dialog(
      key: const Key('lesson-dialog'),
      insetPadding: EdgeInsets.all(compact ? 12 : 28),
      constraints: const BoxConstraints(maxWidth: 1440),
      backgroundColor: AppDesignTokens.appWhite,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        key: const Key('lesson-dialog-surface'),
        width: min(1440, size.width * .93),
        height: min(900, size.height * .9),
        child: Column(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(compact ? 18 : 28, 14, 12, 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          '这句，讲明白',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.source.courseTitle} · ${widget.source.episodeTitle} · ${widget.source.timeLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: '关闭精讲',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 18 : 28,
                0,
                compact ? 18 : 28,
                10,
              ),
              child: LessonUsageHeader(
                usage: lesson?.usage ?? _requestUsage,
                model: lesson?.model ?? _requestModel,
                saved: _saved,
                hasLesson: lesson != null,
              ),
            ),
            if (lesson != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 28),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: List<Widget>.generate(
                      lesson.cards.length,
                      (int index) => ChoiceChip(
                        label: Text(lesson.cards[index].kind.label),
                        selected: _card == index,
                        onSelected: (_) => _selectCard(index),
                        selectedColor: AppDesignTokens.skyLight,
                        labelStyle: TextStyle(
                          color: _card == index
                              ? const Color(0xFF07658F)
                              : AppDesignTokens.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(
                  compact ? 18 : 28,
                  4,
                  compact ? 18 : 28,
                  24,
                ),
                child: lesson == null
                    ? _buildPending()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (_error != null)
                            _notice(
                              _error!,
                              action: !_saved && !_saving ? _save : null,
                              label: '重试保存',
                            ),
                          LessonCardView(
                            lesson: lesson,
                            card: lesson.cards[_card],
                            decorationAsset: _illustrations[_card],
                          ),
                          const SizedBox(height: 18),
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _showScript = !_showScript),
                            icon: Icon(
                              _showScript
                                  ? Icons.expand_less
                                  : Icons.subject_rounded,
                            ),
                            label: Text(_showScript ? '收起讲解稿' : '查看讲解稿'),
                          ),
                          if (_showScript)
                            ...List<Widget>.generate(
                              lesson.cards[_card].speech.length,
                              (int index) {
                                final LessonSpeech speech =
                                    lesson.cards[_card].speech[index];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.all(12),
                                  color: _speaking && _segment == index
                                      ? AppDesignTokens.skyLight
                                      : AppDesignTokens.softWhite,
                                  child: Text(
                                    speech.text,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      height: 1.6,
                                    ),
                                  ),
                                );
                              },
                            ),
                          const SizedBox(height: 8),
                          const Text(
                            '解析由 AI 根据字幕整理；情绪与场景推测请结合原片核对。',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppDesignTokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: EdgeInsets.all(compact ? 14 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (lesson != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _saved ? '已自动保存到「精讲」 · 设备朗读' : '尚未保存，请保留此窗口并重试保存',
                        style: TextStyle(
                          fontSize: 12,
                          color: _saved
                              ? const Color(0xFF367300)
                              : const Color(0xFF9A5200),
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: <Widget>[
                      if (lesson != null) _speechRateControl(),
                      if (lesson != null)
                        FilledButton.icon(
                          key: const Key('lesson-speak'),
                          onPressed: _toggleSpeech,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF367C05),
                          ),
                          icon: Icon(
                            _speaking
                                ? Icons.stop_rounded
                                : Icons.volume_up_rounded,
                          ),
                          label: Text(_speaking ? '停止讲解' : '播放讲解'),
                        ),
                      if (widget.canOpenSource)
                        OutlinedButton.icon(
                          onPressed: _saved || lesson == null
                              ? () => _close(LessonDialogAction.source)
                              : null,
                          icon: const Icon(Icons.movie_outlined),
                          label: const Text('回看原片'),
                        ),
                      if (widget.canResume)
                        TextButton(
                          onPressed: _saved || lesson == null
                              ? () => _close(LessonDialogAction.resume)
                              : null,
                          child: const Text('继续播放'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPending() {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 50),
        child: Column(
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            const Text(
              '正在整理这段对话的精讲…',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              widget.source.english,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, height: 1.6),
            ),
            const SizedBox(height: 16),
            const Text('完成后自动保存。关闭窗口会取消本次请求。', textAlign: TextAlign.center),
          ],
        ),
      );
    }
    final bool configured = canGenerateLesson(
      ref.watch(learningSettingsProvider),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.source.english,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _error ?? '配置 AI 后，就能把这段字幕变成精讲卡片。',
            style: const TextStyle(fontSize: 18, height: 1.6),
          ),
          const SizedBox(height: 12),
          const Text('精讲使用「设置 → 翻译」中的大模型配置。普通翻译接口不支持精讲；生成可能产生服务商费用。'),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: <Widget>[
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, LessonDialogAction.settings),
                child: const Text('配置 AI'),
              ),
              if (_error != null && configured)
                OutlinedButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _notice(
    String text, {
    Future<void> Function()? action,
    String? label,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          text,
          style: const TextStyle(color: Color(0xFF955200), height: 1.6),
        ),
        if (action != null) TextButton(onPressed: action, child: Text(label!)),
      ],
    ),
  );
}
