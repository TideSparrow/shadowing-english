import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../utils/url_utils.dart';
import '../../../player/domain/pronunciation_assessment.dart';
import '../../data/pronunciation_credentials.dart';
import 'settings_group_card.dart';

class PronunciationSettingsCard extends ConsumerStatefulWidget {
  const PronunciationSettingsCard({super.key});

  @override
  ConsumerState<PronunciationSettingsCard> createState() =>
      _PronunciationSettingsCardState();
}

class _PronunciationSettingsCardState
    extends ConsumerState<PronunciationSettingsCard> {
  final TextEditingController _appId = TextEditingController();
  final TextEditingController _secretId = TextEditingController();
  final TextEditingController _secretKey = TextEditingController();
  bool _initialized = false;
  bool _dirty = false;
  bool _saving = false;
  String? _saveError;

  @override
  void dispose() {
    _appId.dispose();
    _secretId.dispose();
    _secretKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PronunciationCredentials> credentials = ref.watch(
      pronunciationCredentialsProvider,
    );
    ref.listen<AsyncValue<PronunciationCredentials>>(
      pronunciationCredentialsProvider,
      (
        AsyncValue<PronunciationCredentials>? previous,
        AsyncValue<PronunciationCredentials> next,
      ) {
        final PronunciationCredentials? value = next.value;
        if (value != null && !_dirty) _setControllers(value);
      },
    );
    final PronunciationCredentials? current = credentials.value;
    if (current != null && !_initialized && !_dirty) _setControllers(current);

    return SettingsGroupCard(
      title: '跟读评测',
      icon: Icons.record_voice_over_rounded,
      children: <Widget>[
        const _SettingsIntro(text: '独立使用腾讯云智聆口语评测新版密钥，不会读取翻译或 ASR 配置。'),
        if (!kIsWeb) ...<Widget>[
          _CredentialField(
            title: 'AppID',
            hint: '腾讯云 AppID',
            controller: _appId,
            keyboardType: TextInputType.number,
            enabled: !credentials.isLoading && !_saving,
            onChanged: _markDirty,
          ),
          _CredentialField(
            title: 'SecretId',
            hint: '腾讯云 SecretId',
            controller: _secretId,
            obscureText: true,
            enabled: !credentials.isLoading && !_saving,
            onChanged: _markDirty,
          ),
          _CredentialField(
            title: 'SecretKey',
            hint: '腾讯云 SecretKey',
            controller: _secretKey,
            obscureText: true,
            enabled: !credentials.isLoading && !_saving,
            onChanged: _markDirty,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: Row(
              children: <Widget>[
                Expanded(
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
                FilledButton(
                  onPressed: _saving || credentials.isLoading ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F7A43),
                    foregroundColor: Colors.white,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('保存密钥'),
                ),
              ],
            ),
          ),
          const _SettingsLink(
            title: '申请 API 密钥',
            description: '查看账号 AppID，并在控制台申请 SecretId 和 SecretKey。',
            url: 'https://console.cloud.tencent.com/cam/capi',
          ),
          const _SettingsLink(
            title: '开通口语评测',
            description: '在腾讯云控制台开通智聆口语评测新版。',
            url: 'https://console.cloud.tencent.com/soenew',
          ),
        ] else
          const _SettingsIntro(text: '网页版本没有系统密钥链，不能安全保存腾讯云密钥。', isLast: true),
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
    if (_dirty) return '有未保存的更改。';
    if (credentials.value?.isComplete ?? false) {
      return '密钥已保存在$_storageLabel中。';
    }
    return '尚未配置；保存后即可启用评分。';
  }

  void _setControllers(PronunciationCredentials value) {
    _initialized = true;
    _appId.text = value.appId;
    _secretId.text = value.secretId;
    _secretKey.text = value.secretKey;
  }

  void _markDirty(String _) {
    setState(() {
      _dirty = true;
      _saveError = null;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await ref
          .read(pronunciationCredentialsProvider.notifier)
          .saveCredentials(
            appId: _appId.text,
            secretId: _secretId.text,
            secretKey: _secretKey.text,
          );
      if (!mounted) return;
      final PronunciationCredentials saved = ref
          .read(pronunciationCredentialsProvider)
          .requireValue;
      setState(() {
        _setControllers(saved);
        _dirty = false;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
            ? '保存失败，请检查本机配置是否可写。'
            : '保存失败，请检查系统安全存储。';
      });
    }
  }
}

class _SettingsIntro extends StatelessWidget {
  const _SettingsIntro({required this.text, this.isLast = false});

  final String text;
  final bool isLast;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(18, 14, 18, isLast ? 16 : 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: Color(0xFF53625A)),
    ),
  );
}

class _CredentialField extends StatelessWidget {
  const _CredentialField({
    required this.title,
    required this.hint,
    required this.controller,
    required this.onChanged,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
  });

  final String title;
  final String hint;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
    child: TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: title,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFB9CDBE)),
        ),
      ),
    ),
  );
}

class _SettingsLink extends StatelessWidget {
  const _SettingsLink({
    required this.title,
    required this.description,
    required this.url,
  });

  final String title;
  final String description;
  final String url;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
    child: OutlinedButton.icon(
      onPressed: () async {
        try {
          final bool opened = await openUrl(Uri.parse(url));
          if (!opened && context.mounted) {
            ScaffoldMessenger.maybeOf(
              context,
            )?.showSnackBar(const SnackBar(content: Text('无法打开腾讯云控制台链接。')));
          }
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.maybeOf(
              context,
            )?.showSnackBar(const SnackBar(content: Text('无法打开腾讯云控制台链接。')));
          }
        }
      },
      icon: const Icon(Icons.open_in_new_rounded),
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(description, style: const TextStyle(fontSize: 11)),
        ],
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF17456B),
        alignment: Alignment.centerLeft,
        minimumSize: const Size.fromHeight(48),
      ),
    ),
  );
}
