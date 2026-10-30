import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../library/presentation/library_catalog_provider.dart';
import '../../../library/presentation/library_mock_data.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../shared/presentation/pad/pad_compact.dart';
import '../../domain/android_import_picker.dart';
import '../../domain/import_match.dart';
import '../../domain/online_video_import.dart';
import 'import_match_table.dart';
import 'import_step_header.dart';

enum ImportSourceMode { local, direct }

class ImportCourseFlow extends ConsumerStatefulWidget {
  const ImportCourseFlow({
    required this.onCancel,
    required this.onImportCompleted,
    this.showHeader = true,
    this.controller,
    this.pickVideoFolder,
    this.pickSubtitleFolder,
    this.pickAndroidVideoDirectory,
    this.pickAndroidSubtitleDirectory,
    super.key,
  });

  final VoidCallback onCancel;
  final VoidCallback onImportCompleted;
  final bool showHeader;
  final ImportCourseFlowController? controller;
  final Future<String?> Function()? pickVideoFolder;
  final Future<String?> Function()? pickSubtitleFolder;
  final Future<AndroidImportDirectorySelection?> Function()?
  pickAndroidVideoDirectory;
  final Future<AndroidImportDirectorySelection?> Function()?
  pickAndroidSubtitleDirectory;

  @override
  ConsumerState<ImportCourseFlow> createState() => _ImportCourseFlowState();
}

class ImportCourseFlowController extends ChangeNotifier {
  int _currentStep = 1;
  bool _busy = false;
  VoidCallback? _goBack;
  bool _notifyScheduled = false;
  bool _disposed = false;

  int get currentStep => _currentStep;
  bool get canGoBack => _currentStep > 1 && !_busy;

  void goBack() {
    _goBack?.call();
  }

  void bind({
    required int currentStep,
    required bool busy,
    required VoidCallback goBack,
  }) {
    final bool changed =
        _currentStep != currentStep || _busy != busy || _goBack != goBack;
    _currentStep = currentStep;
    _busy = busy;
    _goBack = goBack;
    if (changed) {
      _scheduleNotify();
    }
  }

  void unbind() {
    _goBack = null;
    if (_currentStep != 1 || _busy) {
      _currentStep = 1;
      _busy = false;
      _scheduleNotify();
    }
  }

  void _scheduleNotify() {
    if (_notifyScheduled || _disposed) {
      return;
    }
    _notifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) {
        return;
      }
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _goBack = null;
    super.dispose();
  }
}

class _ImportCourseFlowState extends ConsumerState<ImportCourseFlow> {
  ImportSourceMode sourceMode = ImportSourceMode.local;
  final TextEditingController onlineUrlController = TextEditingController();
  final TextEditingController courseTitleController = TextEditingController();
  String? targetCourseId;
  int currentStep = 1;
  String? selectedVideoFolder;
  String? selectedSubtitleFolder;
  String? selectedVideoSource;
  String? selectedSubtitleSource;
  Map<String, String> selectedVideoSourceUris = const <String, String>{};
  List<String> selectedVideoFiles = const <String>[];
  List<String> selectedSubtitleFiles = const <String>[];
  bool selectingVideo = false;
  bool selectingSubtitle = false;
  bool parsing = false;
  bool importing = false;
  bool downloadingOnlineVideo = false;
  double? onlineDownloadProgress;
  String? onlineDownloadProgressText;
  List<ImportMatchRow> parsedRows = const <ImportMatchRow>[];

  bool get _useAndroidDirectoryPicker =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _isBusy =>
      selectingVideo ||
      selectingSubtitle ||
      parsing ||
      importing ||
      downloadingOnlineVideo;

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncController();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant ImportCourseFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.unbind();
      _syncController();
    }
  }

  @override
  void dispose() {
    onlineUrlController.dispose();
    courseTitleController.dispose();
    widget.controller?.unbind();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool compact = context.isPadCompact;
    final double pagePadding = context.padPagePadding;

    return SafeArea(
      top: false,
      child: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                pagePadding,
                pagePadding,
                pagePadding,
                compact ? 28 : 36,
              ),
              children: <Widget>[
                if (kIsWeb) const _WebImportNotice(),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Stack(
                      children: <Widget>[
                        Positioned(
                          left: compact ? 10 : 24,
                          top: compact ? 48 : 42,
                          child: _DecorCircle(
                            size: compact ? 148 : 186,
                            color: AppDesignTokens.skyLight,
                          ),
                        ),
                        Positioned(
                          right: compact ? 6 : 18,
                          top: compact ? 92 : 80,
                          child: _DecorCircle(
                            size: compact ? 108 : 132,
                            color: AppDesignTokens.pinkLight.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),
                        Positioned(
                          right: compact ? 0 : 10,
                          bottom: 0,
                          child: _DecorCircle(
                            size: compact ? 136 : 168,
                            color: AppDesignTokens.purpleLight.withValues(
                              alpha: 0.46,
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            if (widget.showHeader) ..._titleArea,
                            SizedBox(height: compact ? 18 : 22),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 18 : 30,
                              ),
                              child: ImportStepHeader(currentStep: currentStep),
                            ),
                            SizedBox(height: compact ? 18 : 24),
                            _TaskCard(child: _buildStepBody()),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              pagePadding,
              0,
              pagePadding,
              compact ? 20 : 24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: _BottomActionBar(
                  child: _BottomActions(
                    compact: compact,
                    primaryAction: _buildPrimaryAction(),
                    onCancel: widget.onCancel,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> get _titleArea => <Widget>[
    Row(
      children: <Widget>[
        if (currentStep > 1) ...<Widget>[
          _HeaderIconButton(
            tooltip: '返回上一步',
            icon: Icons.arrow_back_rounded,
            onTap: _isBusy ? null : _handleGoBack,
          ),
          SizedBox(width: context.isPadCompact ? 12 : 14),
        ],
        Expanded(
          child: Text(
            '导入影视',
            style: TextStyle(
              fontSize: context.isPadCompact ? 30 : 36,
              fontWeight: FontWeight.w900,
              color: AppDesignTokens.textPrimary,
            ),
          ),
        ),
      ],
    ),
    SizedBox(height: context.isPadCompact ? 8 : 10),
    const Text(
      '把本地视频和字幕整理成新的学习片库。',
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppDesignTokens.textSecondary,
      ),
    ),
  ];

  Widget _buildStepBody() {
    switch (currentStep) {
      case 1:
        return _SourceSelectionStep(
          mode: sourceMode,
          controller: onlineUrlController,
          selectedPath: selectedVideoFolder,
          selecting: selectingVideo,
          downloading: downloadingOnlineVideo,
          downloadProgress: onlineDownloadProgress,
          downloadProgressText: onlineDownloadProgressText,
          onModeChanged: (ImportSourceMode value) => setState(() {
            sourceMode = value;
          }),
          onSelectLocalFolder: _selectVideoFolder,
        );
      case 2:
        return _ParsingStep(
          videoFolder: selectedVideoFolder ?? '',
          subtitleFolder: selectedSubtitleFolder,
          selectingSubtitle: selectingSubtitle,
          parsing: parsing,
          onSelectSubtitleFolder: _selectSubtitleFolder,
        );
      case 3:
        return _ImportDestinationStep(
          courses: ref.watch(libraryCatalogProvider),
          targetCourseId: targetCourseId,
          courseTitleController: courseTitleController,
          onTargetCourseChanged: (String? value) =>
              setState(() => targetCourseId = value),
          child: ImportMatchTable(
            rows: parsedRows,
            onRowChanged: _handleRowChanged,
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _selectVideoFolder() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('网页端请先在桌面端完成导入，网页当前只能使用已有课程库。')),
        );
      return;
    }

    setState(() {
      selectingVideo = true;
    });

    if ((_useAndroidDirectoryPicker ||
            widget.pickAndroidVideoDirectory != null) &&
        widget.pickVideoFolder == null) {
      final AndroidImportDirectorySelection? selection =
          await (widget.pickAndroidVideoDirectory?.call() ??
              pickAndroidImportDirectory(
                title: '选择视频文件夹',
                extensions: const <String>['mp4', 'mkv', 'mov', 'webm', 'rm'],
                copyFiles: false,
              ));
      if (!mounted) {
        return;
      }
      if (selection == null || selection.files.isEmpty) {
        setState(() {
          selectingVideo = false;
        });
        return;
      }

      setState(() {
        selectingVideo = false;
        selectedVideoFiles = selection.files;
        selectedVideoSourceUris = selection.sourceUris;
        selectedVideoFolder = selection.label;
        selectedVideoSource = selection.folderName;
        currentStep = 2;
        selectedSubtitleFolder = null;
        selectedSubtitleSource = null;
        selectedSubtitleFiles = const <String>[];
        parsedRows = const <ImportMatchRow>[];
      });
      return;
    }

    final String? selectedPath =
        await (widget.pickVideoFolder?.call() ??
            getDirectoryPath(confirmButtonText: '选择视频目录'));
    if (!mounted) {
      return;
    }
    if (selectedPath == null || selectedPath.isEmpty) {
      setState(() {
        selectingVideo = false;
      });
      return;
    }

    setState(() {
      selectingVideo = false;
      selectedVideoFolder = selectedPath;
      selectedVideoSource = selectedPath;
      selectedVideoSourceUris = const <String, String>{};
      selectedVideoFiles = const <String>[];
      currentStep = 2;
      selectedSubtitleFolder = null;
      selectedSubtitleSource = null;
      selectedSubtitleFiles = const <String>[];
      parsedRows = const <ImportMatchRow>[];
      targetCourseId = null;
      courseTitleController.text = selectedPath.split(RegExp(r'[\\/]')).last;
    });
  }

  Future<void> _selectSubtitleFolder() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('网页端请先在桌面端完成导入，网页当前只能使用已有课程库。')),
        );
      return;
    }

    setState(() {
      selectingSubtitle = true;
    });

    if ((_useAndroidDirectoryPicker ||
            widget.pickAndroidSubtitleDirectory != null) &&
        widget.pickSubtitleFolder == null) {
      final AndroidImportDirectorySelection? selection =
          await (widget.pickAndroidSubtitleDirectory?.call() ??
              pickAndroidImportDirectory(
                title: '选择字幕文件夹',
                extensions: const <String>['srt', 'vtt'],
              ));
      if (!mounted) {
        return;
      }
      if (selection == null || selection.files.isEmpty) {
        setState(() {
          selectingSubtitle = false;
        });
        return;
      }

      setState(() {
        selectingSubtitle = false;
        selectedSubtitleFiles = selection.files;
        selectedSubtitleFolder = selection.label;
        selectedSubtitleSource = selection.folderName;
      });
      return;
    }

    final String? selectedPath =
        await (widget.pickSubtitleFolder?.call() ??
            getDirectoryPath(confirmButtonText: '选择字幕目录'));
    if (!mounted) {
      return;
    }
    if (selectedPath == null || selectedPath.isEmpty) {
      setState(() {
        selectingSubtitle = false;
      });
      return;
    }
    setState(() {
      selectingSubtitle = false;
      selectedSubtitleFolder = selectedPath;
      selectedSubtitleSource = selectedPath;
      selectedSubtitleFiles = const <String>[];
    });
  }

  Future<void> _handleStartParsing() async {
    if (selectedVideoFolder == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('请先选择视频目录。')));
      return;
    }

    final String selectedVideoPath =
        selectedVideoSource ?? selectedVideoFolder!;
    final String selectedSubtitlePath =
        selectedSubtitleSource ?? selectedSubtitleFolder ?? '';

    setState(() {
      parsing = true;
    });
    try {
      final List<ImportMatchRow> rows = await ImportMatcher.parseInBackground(
        videoFolder: selectedVideoPath,
        subtitleFolder: selectedSubtitlePath,
        videoFiles: selectedVideoFiles.isEmpty ? null : selectedVideoFiles,
        subtitleFiles: selectedSubtitleFiles.isEmpty
            ? null
            : selectedSubtitleFiles,
      );
      if (!mounted) return;
      setState(() {
        parsedRows = rows;
        currentStep = 3;
        targetCourseId = null;
        courseTitleController.text = _courseTitleFor(
          selectedVideoSource ?? selectedVideoFolder ?? '',
        );
      });
    } catch (error) {
      if (mounted) _showMessage('解析失败：${_importErrorMessage(error)}');
    } finally {
      if (mounted) setState(() => parsing = false);
    }
  }

  Future<void> _handleConfirmImport() async {
    setState(() {
      importing = true;
    });
    try {
      final List<ImportMatchRow> resolvedRows =
          await _resolveVideoRowsForImport(parsedRows);
      if (!mounted) {
        return;
      }
      final bool imported = await ref
          .read(libraryCatalogProvider.notifier)
          .importCourseFromMatches(
            rows: resolvedRows,
            videoFolder: selectedVideoSource ?? '',
            subtitleFolder: selectedSubtitleSource ?? '',
            targetCourseId: targetCourseId,
            courseTitle: courseTitleController.text,
            sourceLabel: switch (sourceMode) {
              ImportSourceMode.local => '本地资源',
              ImportSourceMode.direct => '在线视频',
            },
          );
      if (!mounted) {
        return;
      }

      final int matchedCount = parsedRows
          .where((ImportMatchRow row) => row.matched)
          .length;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              imported
                  ? '智能导入课程成功！已解析 ${parsedRows.length} 个视频文件，其中 $matchedCount 个字幕匹配完整'
                  : '该课程已导入！',
            ),
          ),
        );
      widget.onImportCompleted();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('导入失败：${_importErrorMessage(error)}')),
        );
    } finally {
      if (mounted) {
        setState(() {
          importing = false;
        });
      }
    }
  }

  Future<void> _downloadOnlineVideo() async {
    final String url = onlineUrlController.text.trim();
    if (url.isEmpty) {
      _showMessage('请先输入视频链接。');
      return;
    }
    setState(() {
      downloadingOnlineVideo = true;
      onlineDownloadProgress = null;
      onlineDownloadProgressText = '正在准备下载...';
    });
    try {
      const OnlineVideoImporter importer = OnlineVideoImporter();
      final OnlineVideoImportResult result = await importer.downloadDirect(
        url,
        onProgress: _updateDownloadProgress,
      );
      if (!mounted) return;
      final Map<String, ImportSubtitleTrack> tracks =
          <String, ImportSubtitleTrack>{
            for (final ImportSubtitleTrack track in result.subtitleTracks)
              track.languageCode: track,
          };
      setState(() {
        selectedVideoSource = result.title;
        selectedVideoFolder = result.title;
        selectedVideoFiles = <String>[result.videoPath];
        selectedSubtitleFiles = result.subtitleTracks
            .map((ImportSubtitleTrack track) => track.path)
            .toList(growable: false);
        parsedRows = <ImportMatchRow>[
          ImportMatchRow(
            episodeName: result.title,
            videoFile: result.videoPath.split(RegExp(r'[\\/]')).last,
            videoPath: result.videoPath,
            subtitleTracks: tracks,
            candidateSubtitles: result.subtitleTracks
                .map(
                  (ImportSubtitleTrack track) => ImportSubtitleCandidate(
                    path: track.path,
                    languageCode: track.languageCode,
                    languageLabel: track.languageLabel,
                  ),
                )
                .toList(growable: false),
          ),
        ];
        currentStep = 3;
        targetCourseId = null;
        courseTitleController.text = result.title;
      });
    } catch (error) {
      if (mounted) _showMessage('下载失败：${_importErrorMessage(error)}');
    } finally {
      if (mounted) {
        setState(() {
          downloadingOnlineVideo = false;
          onlineDownloadProgress = null;
          onlineDownloadProgressText = null;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _updateDownloadProgress(OnlineVideoImportProgress progress) {
    if (!mounted) return;
    setState(() {
      onlineDownloadProgress = progress.value?.clamp(0.0, 1.0);
      onlineDownloadProgressText = progress.label;
    });
  }

  void _handleGoBack() {
    if (currentStep <= 1) {
      return;
    }
    setState(() {
      currentStep -= 1;
    });
  }

  void _handleRowChanged(int index, ImportMatchRow row) {
    setState(() {
      parsedRows = <ImportMatchRow>[
        for (int i = 0; i < parsedRows.length; i++)
          if (i == index) row else parsedRows[i],
      ];
    });
  }

  String _courseTitleFor(String value) {
    final List<String> segments = value
        .split(RegExp(r'[\\/]'))
        .where((String item) => item.trim().isNotEmpty)
        .toList(growable: false);
    return segments.isEmpty ? '已导入课程' : segments.last.trim();
  }

  void _syncController() {
    widget.controller?.bind(
      currentStep: currentStep,
      busy: _isBusy,
      goBack: _handleGoBack,
    );
  }

  _ImportPrimaryAction? _buildPrimaryAction() {
    if (currentStep == 1 && sourceMode != ImportSourceMode.local) {
      return _ImportPrimaryAction(
        enabled: !downloadingOnlineVideo,
        loading: downloadingOnlineVideo,
        icon: Icons.download_rounded,
        idleLabel: '下载并整理课程',
        loadingLabel: '正在下载...',
        onPressed: _downloadOnlineVideo,
      );
    }
    if (currentStep == 2) {
      return _ImportPrimaryAction(
        enabled: !parsing,
        loading: parsing,
        icon: Icons.search_rounded,
        idleLabel: '开始解析',
        loadingLabel: '正在解析...',
        onPressed: _handleStartParsing,
      );
    }
    if (currentStep == 3) {
      return _ImportPrimaryAction(
        enabled: parsedRows.isNotEmpty && !importing,
        loading: importing,
        icon: Icons.download_rounded,
        idleLabel: '确认导入并建立课程',
        loadingLabel: '正在导入...',
        onPressed: _handleConfirmImport,
      );
    }
    return null;
  }

  Future<List<ImportMatchRow>> _resolveVideoRowsForImport(
    List<ImportMatchRow> rows,
  ) async {
    if (selectedVideoSourceUris.isEmpty) {
      return rows;
    }

    final List<ImportMatchRow> resolved = <ImportMatchRow>[];
    for (final ImportMatchRow row in rows) {
      final String? sourceUri = selectedVideoSourceUris[row.videoPath];
      if (sourceUri == null || sourceUri.isEmpty) {
        resolved.add(row);
        continue;
      }
      final String? copiedPath = await copyPickedAndroidFile(
        sourceUri: sourceUri,
        destinationName: row.videoFile,
      );
      resolved.add(
        copiedPath == null || copiedPath.isEmpty
            ? row
            : row.copyWith(videoPath: copiedPath),
      );
    }
    return resolved;
  }

  String _importErrorMessage(Object error) {
    final String message = error.toString().trim();
    if (message.isEmpty) {
      return '请重试一次';
    }
    return message
        .replaceFirst('Exception: ', '')
        .replaceFirst('PlatformException(', '');
  }
}

class _ImportDestinationStep extends StatelessWidget {
  const _ImportDestinationStep({
    required this.courses,
    required this.targetCourseId,
    required this.courseTitleController,
    required this.onTargetCourseChanged,
    required this.child,
  });

  final List<LibraryCourseData> courses;
  final String? targetCourseId;
  final TextEditingController courseTitleController;
  final ValueChanged<String?> onTargetCourseChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool creatingCourse = targetCourseId == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '导入到哪里',
          style: TextStyle(
            fontSize: context.isPadCompact ? 22 : 24,
            fontWeight: FontWeight.w900,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '可新建一个季/系列，也可以继续追加到已有课程。',
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: AppDesignTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey<String>(targetCourseId ?? ''),
          initialValue: targetCourseId ?? '',
          decoration: const InputDecoration(labelText: '目标课程'),
          items: <DropdownMenuItem<String>>[
            const DropdownMenuItem<String>(value: '', child: Text('新建课程')),
            ...courses.map(
              (LibraryCourseData course) => DropdownMenuItem<String>(
                value: course.id,
                child: Text(course.title),
              ),
            ),
          ],
          onChanged: (String? value) => onTargetCourseChanged(
            value == null || value.isEmpty ? null : value,
          ),
        ),
        if (creatingCourse) ...<Widget>[
          const SizedBox(height: 12),
          TextField(
            controller: courseTitleController,
            decoration: const InputDecoration(
              labelText: '课程名称',
              hintText: '例如：小猪佩奇·第一季、哈利波特',
            ),
          ),
        ],
        const SizedBox(height: 28),
        child,
      ],
    );
  }
}

class _WebImportNotice extends StatelessWidget {
  const _WebImportNotice();

  @override
  Widget build(BuildContext context) {
    final bool compact = context.isPadCompact;

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 20 : 24),
      padding: EdgeInsets.all(compact ? 16 : 20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9ED),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF5DFA8)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.info_outlined, color: Color(0xFF8A5D14), size: 20),
              SizedBox(width: 8),
              Text(
                '网页版暂未支持目录扫描导入',
                style: TextStyle(
                  color: Color(0xFF8A5D14),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '如需导入新课程，请在桌面端先完成目录匹配后再回到课程库学习；'
            '当前网页可直接进入课程库进行学习与复习。',
            style: TextStyle(color: Color(0xFF6B5B36), height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool compact = context.isPadCompact;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFF0ECE6)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 18 : 24,
          vertical: compact ? 14 : 16,
        ),
        child: child,
      ),
    );
  }
}

class _DecorCircle extends StatelessWidget {
  const _DecorCircle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool compact = context.isPadCompact;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 28 : 34),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFFF0ECE6)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.compact,
    required this.primaryAction,
    required this.onCancel,
  });

  final bool compact;
  final _ImportPrimaryAction? primaryAction;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        TextButton(
          onPressed: onCancel,
          child: const Text(
            '取消导入',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.primaryBlueDark,
            ),
          ),
        ),
        if (primaryAction != null) ...<Widget>[
          SizedBox(width: compact ? 12 : 16),
          FilledButton.icon(
            onPressed: primaryAction!.enabled ? primaryAction!.onPressed : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppDesignTokens.brandGreenDark,
              disabledBackgroundColor: const Color(0xFFE2E0DF),
              foregroundColor: AppDesignTokens.appWhite,
              disabledForegroundColor: const Color(0xFF9F9A96),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              elevation: 0,
            ),
            icon: primaryAction!.loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppDesignTokens.appWhite,
                    ),
                  )
                : Icon(primaryAction!.icon, size: 18),
            label: Text(
              primaryAction!.loading
                  ? primaryAction!.loadingLabel
                  : primaryAction!.idleLabel,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ],
    );
  }
}

class _ImportPrimaryAction {
  const _ImportPrimaryAction({
    required this.enabled,
    required this.loading,
    required this.icon,
    required this.idleLabel,
    required this.loadingLabel,
    required this.onPressed,
  });

  final bool enabled;
  final bool loading;
  final IconData icon;
  final String idleLabel;
  final String loadingLabel;
  final VoidCallback onPressed;
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: AppDesignTokens.appWhite,
          foregroundColor: AppDesignTokens.brandGreenDark,
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          side: const BorderSide(color: AppDesignTokens.borderGray),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }
}

class _SourceSelectionStep extends StatelessWidget {
  const _SourceSelectionStep({
    required this.mode,
    required this.controller,
    required this.selectedPath,
    required this.selecting,
    required this.downloading,
    required this.downloadProgress,
    required this.downloadProgressText,
    required this.onModeChanged,
    required this.onSelectLocalFolder,
  });

  final ImportSourceMode mode;
  final TextEditingController controller;
  final String? selectedPath;
  final bool selecting;
  final bool downloading;
  final double? downloadProgress;
  final String? downloadProgressText;
  final ValueChanged<ImportSourceMode> onModeChanged;
  final Future<void> Function() onSelectLocalFolder;

  @override
  Widget build(BuildContext context) {
    final bool compact = context.isPadCompact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '选择导入方式',
          style: TextStyle(
            fontSize: compact ? 24 : 28,
            fontWeight: FontWeight.w900,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '原始字幕会作为课程字幕保存；之后仍可在播放器中生成并切换 AI 字幕。请仅导入你有权保存和学习的媒体。',
          style: TextStyle(
            fontSize: 15,
            height: 1.5,
            color: AppDesignTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            _SourceModeCard(
              mode: ImportSourceMode.local,
              current: mode,
              icon: Icons.video_library_outlined,
              title: '导入本地影视',
              body: '选择本地视频与字幕文件夹',
              onTap: onModeChanged,
            ),
            _SourceModeCard(
              mode: ImportSourceMode.direct,
              current: mode,
              icon: Icons.link_rounded,
              title: '下载 m3u8 / mp4',
              body: '保存直链视频或未加密 HLS',
              onTap: onModeChanged,
            ),
          ],
        ),
        const SizedBox(height: 28),
        if (mode == ImportSourceMode.local)
          _FolderTray(
            icon: Icons.video_library_outlined,
            value: selectedPath ?? '尚未选择文件夹',
            action: FilledButton.icon(
              onPressed: selecting ? null : onSelectLocalFolder,
              style: FilledButton.styleFrom(
                backgroundColor: AppDesignTokens.brandGreenDark,
                foregroundColor: AppDesignTokens.appWhite,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 18,
                ),
                shape: const StadiumBorder(),
              ),
              icon: selecting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppDesignTokens.appWhite,
                      ),
                    )
                  : const Icon(Icons.folder_open_rounded, size: 18),
              label: Text(
                selecting ? '正在整理文件...' : '选择视频文件夹',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          )
        else ...<Widget>[
          TextField(
            controller: controller,
            enabled: !downloading,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'm3u8 或 mp4 直链',
              hintText: 'https://example.com/video.m3u8',
              prefixIcon: const Icon(Icons.link_rounded),
              suffixIcon: IconButton(
                tooltip: '清空链接',
                onPressed: downloading ? null : controller.clear,
                icon: const Icon(Icons.close_rounded),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'm3u8 当前支持未加密分片流；有字幕文件时可在下一步或播放器中补充。',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          if (downloading) ...<Widget>[
            const SizedBox(height: 18),
            LinearProgressIndicator(value: downloadProgress),
            const SizedBox(height: 8),
            Text(
              downloadProgressText ?? '正在下载...',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppDesignTokens.textSecondary,
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _SourceModeCard extends StatelessWidget {
  const _SourceModeCard({
    required this.mode,
    required this.current,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });
  final ImportSourceMode mode;
  final ImportSourceMode current;
  final IconData icon;
  final String title;
  final String body;
  final ValueChanged<ImportSourceMode> onTap;

  @override
  Widget build(BuildContext context) {
    final bool selected = mode == current;
    return InkWell(
      onTap: () => onTap(mode),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: selected
              ? AppDesignTokens.skyLight
              : AppDesignTokens.softWhite,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppDesignTokens.primaryBlueDark
                : AppDesignTokens.borderGray,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: AppDesignTokens.brandGreenDark),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: AppDesignTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              body,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppDesignTokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParsingStep extends StatelessWidget {
  const _ParsingStep({
    required this.videoFolder,
    required this.subtitleFolder,
    required this.selectingSubtitle,
    required this.parsing,
    required this.onSelectSubtitleFolder,
  });

  final String videoFolder;
  final String? subtitleFolder;
  final bool selectingSubtitle;
  final bool parsing;
  final Future<void> Function() onSelectSubtitleFolder;

  @override
  Widget build(BuildContext context) {
    final bool compact = context.isPadCompact;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '选择字幕文件夹并开始解析',
          style: TextStyle(
            fontSize: compact ? 24 : 28,
            fontWeight: FontWeight.w900,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '字幕可选。选择字幕文件夹时会按同名规则匹配中英字幕；没有字幕也可以先导入视频，之后在播放器里生成 AI 字幕。',
          style: TextStyle(
            fontSize: 15,
            height: 1.5,
            color: AppDesignTokens.textSecondary,
          ),
        ),
        SizedBox(height: compact ? 24 : 28),
        _ImportPathRow(
          label: '视频目录',
          value: videoFolder,
          icon: Icons.video_library_outlined,
        ),
        const SizedBox(height: 14),
        _ImportPathRow(
          label: '字幕目录',
          value: subtitleFolder ?? '尚未选择字幕文件夹',
          icon: Icons.subtitles_outlined,
          action: FilledButton.icon(
            onPressed: selectingSubtitle ? null : onSelectSubtitleFolder,
            style: FilledButton.styleFrom(
              backgroundColor: AppDesignTokens.brandGreenDark,
              foregroundColor: AppDesignTokens.appWhite,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              elevation: 0,
            ),
            icon: selectingSubtitle
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppDesignTokens.appWhite,
                    ),
                  )
                : const Icon(Icons.folder_open_rounded, size: 18),
            label: Text(
              selectingSubtitle ? '正在整理字幕...' : '选择字幕文件夹',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        SizedBox(height: compact ? 20 : 24),
        Container(
          padding: EdgeInsets.all(compact ? 20 : 24),
          decoration: BoxDecoration(
            color: parsing
                ? AppDesignTokens.skyLight.withValues(alpha: 0.72)
                : AppDesignTokens.softWhite,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE7E1DA)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: compact ? 52 : 60,
                height: compact ? 52 : 60,
                decoration: BoxDecoration(
                  color: AppDesignTokens.appWhite,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: parsing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : const Icon(
                          Icons.auto_awesome_rounded,
                          size: 24,
                          color: AppDesignTokens.primaryBlueDark,
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      parsing ? '正在分析视频和字幕...' : '已准备好开始智能解析',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitleFolder == null
                          ? '先补充字幕文件夹，再开始扫描匹配。'
                          : '系统会按文件名自动对齐视频、中英字幕和剧集结果。',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ],
    );
  }
}

class _FolderTray extends StatelessWidget {
  const _FolderTray({
    required this.icon,
    required this.value,
    required this.action,
  });

  final IconData icon;
  final String value;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final bool empty = value == '尚未选择文件夹';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFCFB),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE5E1DC)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF8F1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: AppDesignTokens.brandGreenDark, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: empty ? FontWeight.w600 : FontWeight.w700,
                color: empty
                    ? const Color(0xFF9A9A9A)
                    : AppDesignTokens.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 16),
          action,
        ],
      ),
    );
  }
}

class _ImportPathRow extends StatelessWidget {
  const _ImportPathRow({
    required this.label,
    required this.value,
    required this.icon,
    this.action,
  });

  final String label;
  final String value;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFCFB),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5E1DC)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF8F1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: AppDesignTokens.brandGreenDark),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
