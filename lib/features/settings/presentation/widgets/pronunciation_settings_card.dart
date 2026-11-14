import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../player/domain/pronunciation_assessment.dart';
import '../../data/pronunciation_credentials.dart';
import 'pronunciation_help.dart';
import 'settings_group_card.dart';
import 'settings_rows.dart';

class PronunciationSettingsCard extends ConsumerStatefulWidget {
  const PronunciationSettingsCard({
    this.openLink = openPronunciationLink,
    super.key,
  });

  final Future<bool> Function(BuildContext, String) openLink;

  @override
  ConsumerState<PronunciationSettingsCard> createState() =>
      _PronunciationSettingsCardState();
}

class _PronunciationSettingsCardState
    extends ConsumerState<PronunciationSettingsCard> {
  final TextEditingController _apiKey = TextEditingController();
  bool _initialized = false;
  int _saveAttempt = 0;
  bool _saving = false;
  String? _saveError;

  @override
  void dispose() {
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PronunciationCredentials> credentials = ref.watch(
      pronunciationCredentialsProvider,
    );
    final PronunciationCredentials? current = credentials.value;
    if (current != null && !_initialized) {
      _initialized = true;
      _apiKey.text = current.apiKey;
    }

    return SettingsGroupCard(
      title: '跟读指导',
      icon: Icons.record_voice_over_rounded,
      children: <Widget>[
        const SettingsRowFrame(
          child: SettingsTitleBlock(
            title: '豆包发音指导',
            description: '使用自己的火山方舟账号，按音频和文字用量付费。',
          ),
        ),
        if (!kIsWeb) ...<Widget>[
          SettingsInputRow(
            title: 'API Key',
            description: '从火山方舟的 API Key 管理获取。',
            hintText: '火山方舟 API Key',
            controller: _apiKey,
            obscureText: true,
            enabled: !credentials.isLoading && !credentials.hasError,
            onChanged: _save,
            trailing: TextButton.icon(
              onPressed: () =>
                  widget.openLink(context, doubaoPronunciationKeysUrl),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('申请 API Key'),
            ),
          ),
          SettingsRowFrame(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _statusText(credentials),
                style: TextStyle(
                  color: _saveError == null
                      ? const Color(0xFF53625A)
                      : const Color(0xFFC62828),
                  fontSize: 12,
                ),
              ),
            ),
          ),
          SettingsActionRow(
            title: '开通模型',
            description: '在火山方舟开通 Doubao Seed 2.1 Lite。',
            icon: Icons.open_in_new_rounded,
            onTap: () =>
                widget.openLink(context, doubaoPronunciationConsoleUrl),
          ),
          SettingsActionRow(
            title: '帮助文档',
            description: '查看开通、密钥配置和录音指导步骤。',
            onTap: () =>
                showPronunciationHelp(context, openLink: widget.openLink),
          ),
          SettingsActionRow(
            title: '火山方舟计费',
            description: '查看模型单价和后付费规则。',
            icon: Icons.open_in_new_rounded,
            onTap: () =>
                widget.openLink(context, doubaoPronunciationBillingUrl),
          ),
        ] else
          const SettingsRowFrame(child: Text('请在客户端配置方舟 API Key。')),
      ],
    );
  }

  String get _storageLabel =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
      ? '本机配置'
      : '系统安全存储';

  String _statusText(AsyncValue<PronunciationCredentials> credentials) {
    if (credentials.isLoading) return '正在读取$_storageLabel…';
    if (credentials.hasError) return '读取$_storageLabel失败，请重试。';
    if (_saveError != null) return _saveError!;
    if (_saving) return '正在保存到$_storageLabel…';
    if (credentials.value?.isComplete ?? false) {
      return '密钥已保存在$_storageLabel中。';
    }
    return '输入会自动保存。';
  }

  Future<void> _save(String _) async {
    final int attempt = ++_saveAttempt;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await ref
          .read(pronunciationCredentialsProvider.notifier)
          .saveCredentials(apiKey: _apiKey.text);
      if (!mounted || attempt != _saveAttempt) return;
      setState(() => _saving = false);
    } catch (_) {
      if (!mounted || attempt != _saveAttempt) return;
      setState(() {
        _saving = false;
        _saveError = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
            ? '保存失败，请检查本机配置是否可写。'
            : '保存失败，请检查系统安全存储。';
      });
    }
  }
}
