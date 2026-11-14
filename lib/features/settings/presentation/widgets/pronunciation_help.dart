import 'package:flutter/material.dart';

import '../../../../utils/url_utils.dart';

const String doubaoPronunciationBillingUrl =
    'https://docs.volcengine.com/docs/ark/model-pricing?lang=zh';
const String doubaoPronunciationConsoleUrl =
    'https://ark.volcengine.com/region:cn-beijing/openManagement';
const String doubaoPronunciationKeysUrl =
    'https://ark.volcengine.com/region:cn-beijing/apiKey';

Future<bool> openPronunciationLink(BuildContext context, String url) async {
  try {
    if (await openUrl(Uri.parse(url))) return true;
  } catch (_) {
    // Show the address if an external browser could not be launched.
  }
  if (!context.mounted) return false;
  await showDialog<void>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text('无法打开链接'),
      content: SelectableText(url),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
  return false;
}

Future<void> showPronunciationHelp(
  BuildContext context, {
  Future<bool> Function(BuildContext, String) openLink = openPronunciationLink,
}) => showDialog<void>(
  context: context,
  builder: (BuildContext context) => AlertDialog(
    title: const Text('Shadowing English 跟读指导帮助'),
    scrollable: true,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text('1. 在火山方舟开通 Doubao Seed 2.1 Lite，并创建 API Key。'),
        TextButton(
          onPressed: () => openLink(context, doubaoPronunciationConsoleUrl),
          child: const Text('开通模型'),
        ),
        TextButton(
          onPressed: () => openLink(context, doubaoPronunciationKeysUrl),
          child: const Text('申请 API Key'),
        ),
        const Text('2. 把 API Key 填在「设置 · 跟读指导」，输入会自动保存。'),
        const SizedBox(height: 12),
        const Text(
          '3. 在「跟读对照」录完后，点「获取指导」。本句字幕、原声和你的录音会发给火山方舟。 '
          '豆包根据音频给出建议，设备会朗读建议。回听原声或打开指导记录无需再次调用。 '
          '豆包有时会听错，可对照原声和自己的录音判断。',
        ),
        const SizedBox(height: 12),
        const Text('每次提交按音频和文字用量后付费，有适用免费额度时优先抵扣。实际费用以方舟账单为准。'),
        TextButton(
          onPressed: () => openLink(context, doubaoPronunciationBillingUrl),
          child: const Text('火山方舟官方计费说明'),
        ),
      ],
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('关闭'),
      ),
    ],
  ),
);
