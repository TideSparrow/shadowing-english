import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

enum AppNavDestination {
  home(
    route: '/home',
    label: '首页',
    title: '学习主页',
    subtitle: '继续你的逐句精听练习，回到最近的课程和学习节奏。',
    icon: Icons.home_outlined,
    activeIcon: Icons.home_rounded,
  ),
  library(
    route: '/library',
    label: '学习',
    title: '学习',
    subtitle: '浏览课程、查看集数进度，并回到上次学习的位置。',
    icon: LucideIcons.clapperboard,
    activeIcon: LucideIcons.clapperboard,
  ),
  growth(
    route: '/growth',
    label: '成长',
    title: '英语成长之旅',
    subtitle: '记录你的每一次进步，完成属于自己的英语冒险。',
    icon: LucideIcons.sprout,
    activeIcon: LucideIcons.trophy,
  ),
  review(
    route: '/review',
    label: '复习',
    title: '每日复习',
    subtitle: '统一安排收藏的单词和短语，继续未完成的记忆练习。',
    icon: Icons.event_repeat_outlined,
    activeIcon: Icons.event_repeat_rounded,
  ),
  phrases(
    route: '/phrases',
    label: '短语',
    title: '短语库',
    subtitle: '回顾收藏过的句子和表达，集中复习高价值内容。',
    icon: Icons.auto_stories_outlined,
    activeIcon: Icons.auto_stories_rounded,
  ),
  words(
    route: '/words',
    label: '单词',
    title: '单词本',
    subtitle: '查看在视频字幕中见过并收藏的单词。',
    icon: Icons.menu_book_outlined,
    activeIcon: Icons.menu_book_rounded,
  ),
  guide(
    route: '/guide',
    label: '怎么学',
    title: '怎么学',
    subtitle: '跟着视频，用轻松的三遍法练听力。',
    icon: Icons.tips_and_updates_outlined,
    activeIcon: Icons.tips_and_updates_rounded,
    showInBottomNav: false,
  ),
  settings(
    route: '/settings',
    label: '设置',
    title: '我的',
    subtitle: '管理播放偏好、界面设置和本地学习体验。',
    icon: Icons.tune_outlined,
    activeIcon: Icons.tune_rounded,
  ),
  importCourse(
    route: '/importCourse',
    label: '导入课程',
    title: '导入课程',
    subtitle: '选择本地视频和字幕文件，预览匹配结果后再导入。',
    icon: Icons.file_upload_outlined,
    activeIcon: Icons.file_upload_rounded,
    showInNav: false,
  );

  const AppNavDestination({
    required this.route,
    required this.label,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.activeIcon,
    this.showInNav = true,
    this.showInBottomNav = true,
  });

  final String route;
  final String label;
  final String title;
  final String subtitle;
  final IconData icon;
  final IconData activeIcon;
  final bool showInNav;
  final bool showInBottomNav;
}
