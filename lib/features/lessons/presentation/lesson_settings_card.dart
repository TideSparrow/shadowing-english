import 'package:flutter/material.dart';

import '../../settings/presentation/widgets/settings_group_card.dart';

class LessonSettingsCard extends StatelessWidget {
  const LessonSettingsCard({super.key});

  @override
  Widget build(BuildContext context) => const SettingsGroupCard(
    title: '精讲',
    icon: Icons.auto_stories_outlined,
    children: <Widget>[
      Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          '精讲使用「翻译」中配置的大模型，未配置时不发起解析。卡片和中英文讲解稿自动保存在本机，'
          '使用设备语音朗读，下次可直接复习。',
          style: TextStyle(height: 1.7),
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Text(
          '内置小插画随机展示，无需配置或生成。卡片顶部显示接口实际返回的 Token 用量，复看不请求 AI。',
          style: TextStyle(height: 1.7),
        ),
      ),
    ],
  );
}
