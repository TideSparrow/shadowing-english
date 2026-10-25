import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../import_course/domain/import_match.dart';
import '../course_directory_relink.dart';
import '../library_catalog_provider.dart';
import '../library_mock_data.dart';

class CourseResourceDirectoryDialog extends ConsumerStatefulWidget {
  const CourseResourceDirectoryDialog({
    required this.courseId,
    this.pickDirectory,
    this.scanDirectory = scanCourseDirectory,
    super.key,
  });
  final String courseId;
  final Future<String?> Function()? pickDirectory;
  final Future<CourseDirectoryRelinkPlan> Function({
    required LibraryCourseData course,
    required String oldRoot,
    required String newRoot,
    required bool subtitlesOnly,
  })
  scanDirectory;

  @override
  ConsumerState<CourseResourceDirectoryDialog> createState() =>
      _CourseResourceDirectoryDialogState();
}

class _CourseResourceDirectoryDialogState
    extends ConsumerState<CourseResourceDirectoryDialog> {
  CourseDirectoryRelinkPlan? _plan;
  Map<String, String> _selections = <String, String>{};
  final Set<String> _additions = <String>{};
  bool _busy = false;
  String? _error;

  Future<void> _scan(
    LibraryCourseData course,
    String oldRoot,
    bool subtitlesOnly,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final String? path =
          await (widget.pickDirectory?.call() ??
              getDirectoryPath(confirmButtonText: '选择新目录'));
      if (path == null || !mounted) return;
      final CourseDirectoryRelinkPlan plan = await widget.scanDirectory(
        course: course,
        oldRoot: oldRoot,
        newRoot: path,
        subtitlesOnly: subtitlesOnly,
      );
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _selections = plan.initialSelections;
        _additions.clear();
      });
    } catch (_) {
      if (mounted) setState(() => _error = '无法扫描目录，请检查目录是否存在及访问权限。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(libraryCatalogProvider.notifier)
          .relinkDirectory(
            plan: _plan!,
            selections: _selections,
            addedVideoPaths: _additions,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError ? error.message : '保存失败，请重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDirectory(String path) async {
    try {
      if (await launchUrl(Uri.directory(path))) return;
    } catch (_) {
      /* Report unsupported or unavailable local directories below. */
    }
    if (mounted) setState(() => _error = '无法打开此目录，可复制路径在文件管理器中查看。');
  }

  @override
  Widget build(BuildContext context) {
    final LibraryCourseData? course = ref
        .watch(libraryCatalogProvider)
        .where((LibraryCourseData c) => c.id == widget.courseId)
        .firstOrNull;
    final CourseDirectoryRelinkPlan? plan = _plan;
    final bool conflict =
        _selections.values.toSet().length != _selections.length;
    return AlertDialog(
      title: Text(plan == null ? '资源目录' : '确认重新关联'),
      content: SizedBox(
        width: 640,
        height: (MediaQuery.sizeOf(context).height * .6).clamp(160.0, 540.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (conflict) const Text('同一个文件被重复选择，请调整关联。'),
            Expanded(
              child: course == null
                  ? const Text('课程已被删除。')
                  : plan == null
                  ? _directories(course)
                  : _preview(plan),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(plan == null ? '关闭' : '取消'),
        ),
        if (plan != null) ...<Widget>[
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _plan = null;
                    _error = null;
                  }),
            child: const Text('重新选择'),
          ),
          FilledButton(
            onPressed:
                _busy ||
                    conflict ||
                    course == null ||
                    (_selections.isEmpty && _additions.isEmpty)
                ? null
                : _save,
            child: const Text('确认更新'),
          ),
        ],
      ],
    );
  }

  Widget _directories(LibraryCourseData course) {
    final List<String> videos = courseResourceDirectories(
      course,
      subtitles: false,
    );
    final List<String> subtitles = courseResourceDirectories(
      course,
      subtitles: true,
    );
    final bool desktop =
        !kIsWeb &&
        <TargetPlatform>[
          TargetPlatform.macOS,
          TargetPlatform.windows,
          TargetPlatform.linux,
        ].contains(defaultTargetPlatform);
    return ListView(
      children: <Widget>[
        Text(course.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('移动文件夹后，可选择新目录重新关联。原有学习进度和生词会保留。'),
        if (course.episodes.any((LibraryEpisodeItem e) => e.videoMissing))
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('部分视频文件缺失，可重新关联原目录或新目录。'),
          ),
        for (final bool isSubtitle in <bool>[false, true]) ...<Widget>[
          const SizedBox(height: 20),
          Text(
            isSubtitle ? '字幕目录' : '视频目录',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if ((isSubtitle ? subtitles : videos).isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('暂无本地目录'),
            ),
          for (final String path in isSubtitle ? subtitles : videos)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SelectableText(path),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      if (desktop)
                        TextButton.icon(
                          onPressed: _busy ? null : () => _openDirectory(path),
                          icon: const Icon(Icons.folder_open_outlined),
                          label: Text(
                            defaultTargetPlatform == TargetPlatform.macOS
                                ? '在 Finder 中打开'
                                : '打开目录',
                          ),
                        ),
                      TextButton.icon(
                        onPressed: _busy || !desktop
                            ? null
                            : () => _scan(course, path, isSubtitle),
                        icon: const Icon(Icons.folder_copy_outlined),
                        label: const Text('重新关联目录'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
        if (!desktop) const Text('请在桌面端重新关联本地目录。'),
      ],
    );
  }

  Widget _preview(CourseDirectoryRelinkPlan plan) {
    final int videoCount = plan.files
        .where((ResourceRelinkFile f) => f.isVideo)
        .length;
    final int matchedVideos = plan.files
        .where(
          (ResourceRelinkFile f) =>
              f.isVideo && _selections.containsKey(f.oldPath),
        )
        .length;
    final int subtitleCount = plan.files
        .where((ResourceRelinkFile f) => !f.isVideo)
        .length;
    final int matchedSubtitles = plan.files
        .where(
          (ResourceRelinkFile f) =>
              !f.isVideo && _selections.containsKey(f.oldPath),
        )
        .length;
    return ListView(
      children: <Widget>[
        SelectableText('新目录：${plan.newRoot}'),
        const SizedBox(height: 12),
        Text(
          '视频：已匹配 $matchedVideos / $videoCount；字幕：已匹配 $matchedSubtitles / $subtitleCount',
        ),
        Text(
          '未关联 ${plan.files.length - _selections.length} 个文件；新增 ${plan.newVideos.length} 个视频',
        ),
        const SizedBox(height: 8),
        const Text('未找到的视频保留原记录并标记“文件缺失”。字幕未匹配时保留原路径。'),
        for (final ResourceRelinkFile file in plan.files)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${file.isVideo ? '视频' : '字幕'} · ${resourceFileName(file.oldPath)}',
                ),
                if (file.candidates.isEmpty)
                  const Text(
                    '未找到文件',
                    style: TextStyle(color: Colors.deepOrange),
                  )
                else
                  DropdownButton<String>(
                    isExpanded: true,
                    value: _selections[file.oldPath] ?? '',
                    hint: const Text('请选择匹配文件'),
                    items: <DropdownMenuItem<String>>[
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('暂不关联'),
                      ),
                      ...file.candidates.map(
                        (String path) => DropdownMenuItem<String>(
                          value: path,
                          child: Text(
                            resourceRelativePath(path, plan.newRoot),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (String? path) => setState(() {
                            if (path == null || path.isEmpty) {
                              _selections.remove(file.oldPath);
                            } else {
                              _selections[file.oldPath] = path;
                            }
                          }),
                  ),
              ],
            ),
          ),
        if (plan.newVideos.isNotEmpty) ...<Widget>[
          const Divider(),
          const Text('选择要导入的新视频（默认不导入）'),
          for (final ImportMatchRow row in plan.newVideos)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(row.videoFile),
              subtitle: Text(resourceRelativePath(row.videoPath, plan.newRoot)),
              value: _additions.contains(row.videoPath),
              onChanged: _busy
                  ? null
                  : (bool? value) => setState(() {
                      if (value ?? false) {
                        _additions.add(row.videoPath);
                      } else {
                        _additions.remove(row.videoPath);
                      }
                    }),
            ),
        ],
      ],
    );
  }
}
