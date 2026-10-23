import 'package:flutter/material.dart';

import '../../../library/presentation/library_mock_data.dart';
import '../../../library/presentation/widgets/library_course_poster.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../shared/presentation/pad/pad_compact.dart';

class PadHomeHero extends StatelessWidget {
  const PadHomeHero({
    required this.onTap,
    required this.course,
    required this.episode,
    super.key,
  });

  final VoidCallback onTap;
  final LibraryCourseData? course;
  final LibraryEpisodeItem? episode;

  @override
  Widget build(BuildContext context) {
    final bool compact = context.isPadCompact;
    final bool narrow = MediaQuery.sizeOf(context).width < 720;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppDesignTokens.appWhite,
          borderRadius: BorderRadius.circular(compact ? 30 : 36),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x1F24385B),
              blurRadius: 36,
              offset: Offset(0, 18),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _VideoPreview(course: course, episode: episode),
                  _HeroDetails(onTap: onTap, course: course, episode: episode),
                ],
              )
            : SizedBox(
                height: compact ? 330 : 350,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      flex: 9,
                      child: _VideoPreview(course: course, episode: episode),
                    ),
                    Expanded(
                      flex: 11,
                      child: _HeroDetails(
                        onTap: onTap,
                        course: course,
                        episode: episode,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _VideoPreview extends StatelessWidget {
  const _VideoPreview({required this.course, required this.episode});

  final LibraryCourseData? course;
  final LibraryEpisodeItem? episode;

  @override
  Widget build(BuildContext context) {
    const BorderRadius radius = BorderRadius.zero;
    return AspectRatio(
      aspectRatio: 1.15,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          LibraryCoursePoster(
            title: course?.title ?? '导入你的第一套课程',
            path: course?.coverImage ?? '',
            borderRadius: radius,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0x240A1425), Color(0xB6000000)],
              ),
            ),
          ),
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppDesignTokens.appWhite.withValues(alpha: 0.22),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppDesignTokens.appWhite.withValues(alpha: 0.55),
                ),
                boxShadow: const <BoxShadow>[
                  BoxShadow(color: Color(0x66000000), blurRadius: 16),
                ],
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                size: 40,
                color: AppDesignTokens.appWhite,
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 18,
            child: Text(
              episode?.title ?? '本地视频 · 英文字幕',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppDesignTokens.appWhite,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroDetails extends StatelessWidget {
  const _HeroDetails({
    required this.onTap,
    required this.course,
    required this.episode,
  });

  final VoidCallback onTap;
  final LibraryCourseData? course;
  final LibraryEpisodeItem? episode;

  @override
  Widget build(BuildContext context) {
    final bool compact = context.isPadCompact;
    final bool hasCourse = course != null;
    final String progressTime = episode?.progressTimeStr ?? '从第 1 句开始';

    return Padding(
      padding: EdgeInsets.all(compact ? 18 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _Pill(
            label: hasCourse ? 'WELCOME BACK · 继续学习' : '开始你的学习旅程',
            color: const Color(0xFFE8F1FF),
            textColor: const Color(0xFF315D9D),
          ),
          const SizedBox(height: 10),
          Text(
            hasCourse ? course!.title : '导入你的第一套英语视频课程',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 28 : 32,
              fontWeight: FontWeight.w900,
              height: 1.1,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          if (hasCourse && episode != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              episode!.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppDesignTokens.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (hasCourse) ...<Widget>[
            const SizedBox(height: 8),
            const Row(
              children: <Widget>[
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: AppDesignTokens.primaryBlueDark,
                ),
                SizedBox(width: 6),
                Text(
                  '字幕精听 · 从上次停留的句子继续',
                  style: TextStyle(
                    color: AppDesignTokens.primaryBlueDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            hasCourse ? '上次学习：$progressTime' : '导入本地视频和英文字幕，即刻开始精听。',
            style: const TextStyle(
              color: AppDesignTokens.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: compact ? 50 : 52,
            child: FilledButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.play_arrow_rounded, size: 25),
              label: Text(
                hasCourse ? '继续播放' : '去导入课程',
                style: TextStyle(
                  fontSize: compact ? 17 : 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppDesignTokens.brandGreen,
                foregroundColor: AppDesignTokens.appWhite,
                elevation: 0,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          if (hasCourse) ...<Widget>[
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                const Text(
                  '课程进度',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${course!.progressPercent}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppDesignTokens.brandGreenDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Stack(
                children: <Widget>[
                  Container(height: 12, color: const Color(0xFFE7ECF0)),
                  FractionallySizedBox(
                    widthFactor: course!.progressPercent / 100,
                    child: Container(
                      height: 12,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[
                            AppDesignTokens.brandGreen,
                            Color(0xFF8BE03E),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
      ),
    );
  }
}
