import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../utils/url_utils.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/data/word_pronunciation_service.dart';
import '../../shared/presentation/pad/pad_compact.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import 'ai_subtitle_management_screen.dart';
import 'app_update_provider.dart';
import 'settings_provider.dart';
import 'widgets/settings_group_card.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool compact = context.isPadCompact;
    final LearningSettingsState settings = ref.watch(learningSettingsProvider);
    final bool isAiProvider = _isAiProvider(settings.translationProvider);
    final bool isGoogleTranslate = settings.translationProvider == 'Google 翻译';
    final bool isBaiduTranslate = settings.translationProvider == '百度翻译';
    final bool isAliyunTranslate = settings.translationProvider == '阿里云翻译';
    final AsyncValue<TtsEngineSnapshot> ttsEngines = ref.watch(
      ttsEngineSnapshotProvider,
    );
    final AsyncValue<TtsVoiceSnapshot> ttsVoices = ref.watch(
      ttsVoiceSnapshotProvider(settings.ttsEngine),
    );
    final AppUpdateState updateState = ref.watch(appUpdateProvider);
    final AsyncValue<String> appVersion = ref.watch(appVersionProvider);
    ref.listen<AppUpdateState>(appUpdateProvider, (
      AppUpdateState? previous,
      AppUpdateState next,
    ) {
      if (((previous?.isChecking ?? false) ||
              (previous?.isDownloading ?? false) ||
              (previous?.isInstalling ?? false)) &&
          !next.isChecking &&
          !next.isDownloading &&
          !next.isInstalling &&
          next.message != null) {
        _showMessage(context, next.message!);
      }
    });

    return PadScaffold(
      currentDestination: AppNavDestination.settings,
      topBar: const PadTopBar(title: '英语学习休息室', subtitle: '设置'),
      body: ListView(
        padding: EdgeInsets.all(context.padPagePadding),
        children: <Widget>[
          Text(
            '设置',
            style: TextStyle(
              fontSize: compact ? 30 : 34,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF191C1E),
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          Text(
            '管理您的学习体验',
            style: TextStyle(
              fontSize: compact ? 14 : 15,
              color: const Color(0xFF53625A),
            ),
          ),
          SizedBox(height: context.padSectionGap),
          SettingsGroupCard(
            title: '播放',
            icon: Icons.play_circle_rounded,
            children: <Widget>[
              _SelectRow(
                title: '默认字幕模式',
                description: '选择默认情况下字幕的显示方式。',
                value: settings.subtitleMode,
                options: subtitleModeOptions,
                onChanged: (String? value) {
                  if (value == null) {
                    return;
                  }
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setSubtitleMode(value);
                },
              ),
              _SelectRow(
                title: '英文字幕大小写',
                description: '切换已有和新字幕的显示格式；首字母大写按句首处理。',
                value: settings.subtitleLetterCase,
                options: subtitleLetterCaseOptions,
                onChanged: (String? value) {
                  if (value == null) return;
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setSubtitleLetterCase(value);
                },
              ),
              _SelectRow(
                title: '默认速度',
                description: '设置新视频的默认播放速度。',
                value: settings.playbackSpeed,
                options: playbackSpeedOptions,
                onChanged: (String? value) {
                  if (value == null) {
                    return;
                  }
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setPlaybackSpeed(value);
                },
              ),
              _SelectRow(
                title: '字幕字体大小',
                description: '调整屏幕文本的大小。',
                value: settings.fontSize,
                options: playerFontOptions,
                onChanged: (String? value) {
                  if (value == null) {
                    return;
                  }
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setFontSize(value);
                },
              ),
              _InputRow(
                title: '字幕延迟 ms',
                description: '字幕比视频快时填正数，例如 500；比视频慢时填负数。',
                value: settings.subtitleDelayMs.toString(),
                hintText: '0',
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                onChanged: (String value) {
                  final int? delayMs = int.tryParse(value.trim());
                  if (delayMs == null) {
                    return;
                  }
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setSubtitleDelayMs(delayMs);
                },
              ),
            ],
          ),
          SizedBox(height: compact ? 20 : 24),
          SettingsGroupCard(
            title: '学习',
            icon: Icons.school_outlined,
            children: <Widget>[
              _SwitchRow(
                title: '开启单词高亮',
                description: '自动高亮复杂词汇。',
                value: settings.highlightWords,
                onChanged: (bool value) {
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setHighlightWords(value: value);
                },
              ),
              _SelectRow(
                title: '单词高亮样式',
                description: '设置播放中当前字幕单词的选中效果。',
                value: settings.subtitleWordHighlightStyle,
                options: subtitleWordHighlightStyleOptions,
                onChanged: (String? value) {
                  if (value == null) {
                    return;
                  }
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setSubtitleWordHighlightStyle(value);
                },
              ),
              _SubtitleWordHighlightBorderWidthRow(
                value: settings.subtitleWordHighlightBorderWidth,
                onChanged: (double value) => ref
                    .read(learningSettingsProvider.notifier)
                    .setSubtitleWordHighlightBorderWidth(value),
              ),
              _SwitchRow(
                title: '每日打卡提醒',
                description: '接收温和的提示以保持您的学习连续记录。',
                value: settings.reminder,
                onChanged: (bool value) {
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setReminder(value: value);
                },
              ),
              _TtsEngineRow(
                selectedEngine: settings.ttsEngine,
                snapshot: ttsEngines.value,
                isLoading: ttsEngines.isLoading,
                onChanged: (String? value) {
                  if (value == null) {
                    return;
                  }
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setTtsEngine(value);
                },
              ),
              _TtsVoiceRow(
                selectedVoice: settings.ttsVoice,
                snapshot: ttsVoices.value,
                isLoading: ttsVoices.isLoading,
                onChanged: (String? value) {
                  if (value == null) {
                    return;
                  }
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setTtsVoice(value);
                },
              ),
              _TtsRateRow(
                value: settings.ttsRate,
                onChanged: (double value) => ref
                    .read(learningSettingsProvider.notifier)
                    .setTtsRate(value),
              ),
            ],
          ),
          SizedBox(height: compact ? 20 : 24),
          SettingsGroupCard(
            title: '翻译',
            icon: Icons.translate_rounded,
            children: <Widget>[
              _SelectRow(
                title: '翻译来源',
                description: '先选择翻译 API，再填写对应配置。',
                value: settings.translationProvider,
                options: translationProviderOptions,
                onChanged: (String? value) {
                  if (value == null) {
                    return;
                  }
                  ref
                      .read(learningSettingsProvider.notifier)
                      .setTranslationProvider(value);
                },
              ),
              if (isAiProvider) ...<Widget>[
                _InputRow(
                  title: 'API Key',
                  description: '用于调用 AI 翻译接口。',
                  value: settings.translationApiKey,
                  hintText: 'YOUR_API_KEY_HERE',
                  obscureText: true,
                  onChanged: (String value) {
                    ref
                        .read(learningSettingsProvider.notifier)
                        .setTranslationApiKey(value);
                  },
                ),
                _SwitchRow(
                  title: '自定义接口地址',
                  description: '关闭时使用内置厂商默认 baseUrl 和 model。',
                  value: settings.useCustomTranslationEndpoint,
                  onChanged: (bool value) {
                    ref
                        .read(learningSettingsProvider.notifier)
                        .setUseCustomTranslationEndpoint(value: value);
                  },
                ),
                _InputRow(
                  title: 'Base URL',
                  description: '默认已内置，可按需覆盖。',
                  value: settings.translationBaseUrl,
                  hintText: 'https://api.example.com/v1',
                  enabled: settings.useCustomTranslationEndpoint,
                  onChanged: (String value) {
                    ref
                        .read(learningSettingsProvider.notifier)
                        .setTranslationBaseUrl(value);
                  },
                ),
                _ModelFetchRow(
                  isLoading: settings.isFetchingTranslationModels,
                  hasModels: settings.availableTranslationModels.isNotEmpty,
                  onTap: () async {
                    if (settings.translationApiKey.trim().isEmpty) {
                      _showMessage(context, '请先填写 API Key。');
                      return;
                    }
                    try {
                      final List<String> models = await ref
                          .read(learningSettingsProvider.notifier)
                          .fetchTranslationModels();
                      if (!context.mounted) {
                        return;
                      }
                      _showMessage(
                        context,
                        models.isEmpty
                            ? '未获取到可用模型。'
                            : '已获取 ${models.length} 个模型。',
                      );
                    } catch (_) {
                      if (!context.mounted) {
                        return;
                      }
                      _showMessage(context, '获取模型失败，请检查当前配置。');
                    }
                  },
                ),
                if (settings.availableTranslationModels.isNotEmpty)
                  _SelectRow(
                    title: '模型选择',
                    description: '从当前 provider 返回的模型列表中直接选择。',
                    value:
                        settings.availableTranslationModels.contains(
                          settings.translationModel,
                        )
                        ? settings.translationModel
                        : settings.availableTranslationModels.first,
                    options: settings.availableTranslationModels,
                    onChanged: (String? value) {
                      if (value == null) {
                        return;
                      }
                      ref
                          .read(learningSettingsProvider.notifier)
                          .setTranslationModel(value);
                    },
                  ),
                _InputRow(
                  title: 'Model',
                  description: '可手动输入模型名；已获取模型后也可以直接覆盖。',
                  value: settings.translationModel,
                  hintText: 'gpt-4o-mini',
                  onChanged: (String value) {
                    ref
                        .read(learningSettingsProvider.notifier)
                        .setTranslationModel(value);
                  },
                ),
              ],
              if (isGoogleTranslate)
                _InputRow(
                  title: 'API Key',
                  description: 'Google Cloud Translation API Key。',
                  value: settings.translationApiKey,
                  hintText: 'YOUR_GOOGLE_API_KEY',
                  obscureText: true,
                  onChanged: (String value) {
                    ref
                        .read(learningSettingsProvider.notifier)
                        .setTranslationApiKey(value);
                  },
                ),
              if (isBaiduTranslate) ...<Widget>[
                _InputRow(
                  title: 'App ID',
                  description: '百度翻译开放平台 App ID。',
                  value: settings.translationApiKey,
                  hintText: 'YOUR_BAIDU_APP_ID',
                  obscureText: true,
                  onChanged: (String value) {
                    ref
                        .read(learningSettingsProvider.notifier)
                        .setTranslationApiKey(value);
                  },
                ),
                _InputRow(
                  title: 'Secret',
                  description: '百度翻译开放平台密钥。',
                  value: settings.translationApiSecret,
                  hintText: 'YOUR_BAIDU_SECRET',
                  obscureText: true,
                  onChanged: (String value) {
                    ref
                        .read(learningSettingsProvider.notifier)
                        .setTranslationApiSecret(value);
                  },
                ),
              ],
              if (isAliyunTranslate) ...<Widget>[
                _InputRow(
                  title: 'AccessKey ID',
                  description: '阿里云 AccessKey ID。',
                  value: settings.translationApiKey,
                  hintText: 'YOUR_ACCESS_KEY_ID',
                  obscureText: true,
                  onChanged: (String value) {
                    ref
                        .read(learningSettingsProvider.notifier)
                        .setTranslationApiKey(value);
                  },
                ),
                _InputRow(
                  title: 'AccessKey Secret',
                  description: '阿里云 AccessKey Secret。',
                  value: settings.translationApiSecret,
                  hintText: 'YOUR_ACCESS_KEY_SECRET',
                  obscureText: true,
                  onChanged: (String value) {
                    ref
                        .read(learningSettingsProvider.notifier)
                        .setTranslationApiSecret(value);
                  },
                ),
              ],
            ],
          ),
          SizedBox(height: compact ? 20 : 24),
          SettingsGroupCard(
            title: 'AI生成可跟读的词级同步字幕',
            icon: Icons.auto_awesome_rounded,
            children: <Widget>[
              Builder(
                builder: (BuildContext context) {
                  final bool isTencentAsr = settings.asrProvider == '腾讯云';
                  final bool isAlibabaAsr = settings.asrProvider == '阿里云百炼';
                  final ({String secretId, String secretKey})
                  tencentCredential = _splitTencentCredential(
                    settings.asrApiKey,
                  );
                  return Column(
                    children: <Widget>[
                      _SwitchRow(
                        title: '生成双语字幕',
                        description: '开启后会使用“翻译”设置补齐每句中文。',
                        value: settings.generateBilingualAsrSubtitles,
                        onChanged: (bool value) {
                          ref
                              .read(learningSettingsProvider.notifier)
                              .setGenerateBilingualAsrSubtitles(value: value);
                        },
                      ),
                      _SelectRow(
                        title: 'ASR 来源',
                        description: '独立于翻译 API，用于生成视频字幕。',
                        value: settings.asrProvider,
                        options: asrProviderOptions,
                        onChanged: (String? value) {
                          if (value == null) {
                            return;
                          }
                          ref
                              .read(learningSettingsProvider.notifier)
                              .setAsrProvider(value);
                        },
                      ),
                      if (isTencentAsr) ...<Widget>[
                        _InputRow(
                          title: '腾讯云 SecretId',
                          description: '在腾讯云访问密钥页面创建。',
                          value: tencentCredential.secretId,
                          hintText: 'AKIDxxxxxxxx',
                          obscureText: true,
                          onChanged: (String value) {
                            ref
                                .read(learningSettingsProvider.notifier)
                                .setAsrApiKey(
                                  _joinTencentCredential(
                                    secretId: value,
                                    secretKey: tencentCredential.secretKey,
                                  ),
                                );
                          },
                        ),
                        _InputRow(
                          title: '腾讯云 SecretKey',
                          description: '与 SecretId 配套的密钥。',
                          value: tencentCredential.secretKey,
                          hintText: 'SECRET_KEY',
                          obscureText: true,
                          onChanged: (String value) {
                            ref
                                .read(learningSettingsProvider.notifier)
                                .setAsrApiKey(
                                  _joinTencentCredential(
                                    secretId: tencentCredential.secretId,
                                    secretKey: value,
                                  ),
                                );
                          },
                        ),
                      ] else
                        _InputRow(
                          title: isAlibabaAsr ? '百炼 API Key' : 'ASR API Key',
                          description: isAlibabaAsr
                              ? '在阿里云百炼创建 API Key；音频仅临时上传用于转写。'
                              : '用于调用当前 ASR 接口。',
                          value: settings.asrApiKey,
                          hintText: 'YOUR_ASR_API_KEY_HERE',
                          obscureText: true,
                          onChanged: (String value) {
                            ref
                                .read(learningSettingsProvider.notifier)
                                .setAsrApiKey(value);
                          },
                        ),
                      if (isAlibabaAsr)
                        _ActionRow(
                          title: '申请百炼 API Key',
                          description:
                              '1. 登录阿里云并开通百炼；2. 在 API Key 管理页创建；3. 复制到上方。',
                          icon: Icons.open_in_new_rounded,
                          onTap: () {
                            openUrl(
                              Uri.parse(
                                'https://help.aliyun.com/zh/model-studio/get-api-key',
                              ),
                            );
                          },
                        ),
                      _SwitchRow(
                        title: '自定义 ASR 接口地址',
                        description: '关闭时使用内置厂商默认 baseUrl 和 model。',
                        value: settings.useCustomAsrEndpoint,
                        onChanged: (bool value) {
                          ref
                              .read(learningSettingsProvider.notifier)
                              .setUseCustomAsrEndpoint(value: value);
                        },
                      ),
                      _InputRow(
                        title: 'ASR Base URL',
                        description: '默认已内置，可按需覆盖。',
                        value: settings.asrBaseUrl,
                        hintText: 'https://api.example.com/v1',
                        enabled: settings.useCustomAsrEndpoint,
                        onChanged: (String value) {
                          ref
                              .read(learningSettingsProvider.notifier)
                              .setAsrBaseUrl(value);
                        },
                      ),
                      if (!isTencentAsr && !isAlibabaAsr)
                        _ModelFetchRow(
                          title: '获取 ASR 模型',
                          emptyDescription: '获取接口的模型列表，当前模型不会自动更改。',
                          loadedDescription: '列表可能包含聊天模型，请选择支持词级时间戳的语音识别模型。',
                          isLoading: settings.isFetchingAsrModels,
                          hasModels: settings.availableAsrModels.isNotEmpty,
                          onTap: () async {
                            if (settings.asrApiKey.trim().isEmpty) {
                              _showMessage(context, '请先填写 ASR API Key。');
                              return;
                            }
                            try {
                              final List<String> models = await ref
                                  .read(learningSettingsProvider.notifier)
                                  .fetchAsrModels();
                              if (!context.mounted) {
                                return;
                              }
                              _showMessage(
                                context,
                                models.isEmpty
                                    ? '未获取到可用 ASR 模型。'
                                    : '已获取 ${models.length} 个模型，请选择语音识别模型。',
                              );
                            } catch (_) {
                              if (!context.mounted) {
                                return;
                              }
                              _showMessage(context, '获取 ASR 模型失败，请检查当前配置。');
                            }
                          },
                        ),
                      if (settings.availableAsrModels.isNotEmpty)
                        _SelectRow(
                          title: 'ASR 模型选择',
                          description: '请选择支持词级时间戳的语音识别模型，不能使用聊天模型。',
                          value: settings.asrModel,
                          options: <String>{
                            settings.asrModel,
                            ...settings.availableAsrModels,
                          }.toList(growable: false),
                          onChanged: (String? value) {
                            if (value == null) {
                              return;
                            }
                            ref
                                .read(learningSettingsProvider.notifier)
                                .setAsrModel(value);
                          },
                        ),
                      _InputRow(
                        title: 'ASR Model',
                        description: isTencentAsr
                            ? '腾讯英文识别使用 16k_en。'
                            : isAlibabaAsr
                            ? '默认使用 qwen3-asr-flash-filetrans，提供词级时间戳。'
                            : '默认 whisper-1；中转需支持语音转写和词级时间戳。',
                        value: settings.asrModel,
                        hintText: isTencentAsr
                            ? '16k_en'
                            : isAlibabaAsr
                            ? 'qwen3-asr-flash-filetrans'
                            : 'whisper-1',
                        onChanged: (String value) {
                          ref
                              .read(learningSettingsProvider.notifier)
                              .setAsrModel(value);
                        },
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          SizedBox(height: compact ? 20 : 24),
          SettingsGroupCard(
            title: '系统',
            icon: Icons.settings_system_daydream_rounded,
            children: <Widget>[
              _ActionRow(
                title: updateState.downloadedPath != null
                    ? (updateState.isInstalling
                          ? '正在打开安装包…'
                          : '安装 v${updateState.update!.version}')
                    : updateState.update == null
                    ? (updateState.isChecking ? '正在检查更新…' : '检查更新')
                    : (updateState.isDownloading
                          ? _downloadTitle(updateState)
                          : '更新到 v${updateState.update!.version}'),
                description: updateState.isDownloading
                    ? _downloadDescription(updateState)
                    : updateState.downloadedPath != null
                    ? '安装包已校验完成，点击开始安装。'
                    : updateState.update == null
                    ? '从 GitHub Release 检查当前平台的最新安装包。'
                    : '已找到适用于当前平台的安装包。',
                icon: Icons.system_update_rounded,
                onTap: () => _handleUpdateAction(ref, updateState),
              ),
              _ActionRow(
                title: '管理 AI 字幕',
                description: '查看、编辑、导出、重新生成或删除已生成的字幕。',
                icon: Icons.subtitles_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AiSubtitleManagementScreen(),
                  ),
                ),
              ),
              _ActionRow(
                title: '备份同步云端数据',
                description: '将您本地记录的 142 个词汇与学习周期备份，支持多设备同步。',
                onTap: () => _showMessage(context, '精听学习进度和短语本备份同步成功！'),
              ),
              _ActionRow(
                title: '清除应用缓存与生词记录',
                description: '清除所有收藏例句和缓存图片，重置应用到初始状态。',
                danger: true,
                onTap: () => _confirmReset(context, ref),
              ),
            ],
          ),
          SizedBox(height: compact ? 20 : 24),
          Center(
            child: Text(
              appVersion.when(
                data: (String version) => '当前版本 v$version',
                loading: () => '当前版本',
                error: (_, _) => '当前版本未知',
              ),
              style: const TextStyle(fontSize: 12, color: Color(0xFF8C9890)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('确认清除缓存'),
          content: const Text('确定要清除缓存和重置所有学习数据吗？这会清空您的生词本。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认清除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    ref.read(learningSettingsProvider.notifier).resetToDefaults();
    _showMessage(context, '缓存清除成功，数据已重置！');
  }

  void _handleUpdateAction(WidgetRef ref, AppUpdateState state) {
    if (state.isChecking || state.isDownloading || state.isInstalling) {
      return;
    }
    if (state.downloadedPath != null) {
      ref.read(appUpdateProvider.notifier).install();
      return;
    }
    if (state.update == null) {
      ref.read(appUpdateProvider.notifier).check();
      return;
    }
    ref.read(appUpdateProvider.notifier).download();
  }

  String _downloadTitle(AppUpdateState state) {
    final double? progress = state.downloadProgress;
    return progress == null
        ? '正在下载更新…'
        : '正在下载更新 ${(progress * 100).toStringAsFixed(0)}%';
  }

  String _downloadDescription(AppUpdateState state) {
    final double downloaded = state.downloadedBytes / (1024 * 1024);
    final int? totalBytes = state.totalBytes;
    if (totalBytes == null) {
      return '已下载 ${downloaded.toStringAsFixed(1)} MB。';
    }
    final double total = totalBytes / (1024 * 1024);
    return '已下载 ${downloaded.toStringAsFixed(1)} / ${total.toStringAsFixed(1)} MB。';
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  bool _isAiProvider(String provider) {
    return provider == 'OpenAI' ||
        provider == 'OpenRouter' ||
        provider == 'SiliconFlow' ||
        provider == 'DeepSeek';
  }
}

({String secretId, String secretKey}) _splitTencentCredential(String value) {
  final String trimmed = value.trim();
  int separator = trimmed.indexOf(':');
  if (separator < 0) {
    separator = trimmed.indexOf('：');
  }
  if (separator < 0) {
    return (secretId: trimmed, secretKey: '');
  }
  return (
    secretId: trimmed.substring(0, separator).trim(),
    secretKey: trimmed.substring(separator + 1).trim(),
  );
}

String _joinTencentCredential({
  required String secretId,
  required String secretKey,
}) {
  final String id = secretId.trim();
  final String key = secretKey.trim();
  if (id.isEmpty && key.isEmpty) {
    return '';
  }
  return '$id:$key';
}

class _ModelFetchRow extends StatelessWidget {
  const _ModelFetchRow({
    this.title = '获取模型',
    this.emptyDescription = '从当前 provider 拉取可用模型列表。',
    this.loadedDescription = '已拿到模型列表，可直接在下方选择。',
    required this.isLoading,
    required this.hasModels,
    required this.onTap,
  });

  final String title;
  final String emptyDescription;
  final String loadedDescription;
  final bool isLoading;
  final bool hasModels;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return _SettingsRowFrame(
      child: Row(
        children: <Widget>[
          Expanded(
            child: _TitleBlock(
              title: title,
              description: hasModels ? loadedDescription : emptyDescription,
            ),
          ),
          const SizedBox(width: 16),
          FilledButton(
            onPressed: isLoading ? null : onTap,
            child: Text(isLoading ? '获取中...' : '获取模型'),
          ),
        ],
      ),
    );
  }
}

class _TtsEngineRow extends StatelessWidget {
  const _TtsEngineRow({
    required this.selectedEngine,
    required this.snapshot,
    required this.isLoading,
    required this.onChanged,
  });

  final String selectedEngine;
  final TtsEngineSnapshot? snapshot;
  final bool isLoading;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final List<TtsEngineOption> engines =
        snapshot?.engines ?? const <TtsEngineOption>[];
    final bool hasSelected = engines.any(
      (TtsEngineOption engine) => engine.id == selectedEngine,
    );
    final String value = hasSelected ? selectedEngine : '';

    return _SettingsRowFrame(
      child: Row(
        children: <Widget>[
          Expanded(
            child: _TitleBlock(
              title: 'TTS 语音引擎',
              description: isLoading
                  ? '正在读取设备语音引擎。'
                  : '默认跟随系统；系统未设置时自动使用设备可用引擎。',
            ),
          ),
          const SizedBox(width: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFB9CDBE)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: value,
                  borderRadius: BorderRadius.circular(16),
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Color(0xFF53625A),
                  ),
                  items: <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(
                      value: '',
                      child: Text(_systemDefaultLabel(engines)),
                    ),
                    for (final TtsEngineOption engine in engines)
                      DropdownMenuItem<String>(
                        value: engine.id,
                        child: Text(
                          engine.isDefault
                              ? '${engine.label}（当前系统）'
                              : engine.label,
                        ),
                      ),
                  ],
                  onChanged: isLoading ? null : onChanged,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _systemDefaultLabel(List<TtsEngineOption> engines) {
    final TtsEngineOption? systemDefault = _firstOrNull(
      engines.where((TtsEngineOption engine) => engine.isDefault),
    );
    if (systemDefault != null) {
      return '系统默认（${systemDefault.label}）';
    }
    final TtsEngineOption? fallback = engines.isEmpty ? null : engines.first;
    if (fallback == null) {
      return '系统默认';
    }
    return '系统默认（未设置，自动使用 ${fallback.label}）';
  }

  TtsEngineOption? _firstOrNull(Iterable<TtsEngineOption> engines) {
    for (final TtsEngineOption engine in engines) {
      return engine;
    }
    return null;
  }
}

class _TtsVoiceRow extends StatelessWidget {
  const _TtsVoiceRow({
    required this.selectedVoice,
    required this.snapshot,
    required this.isLoading,
    required this.onChanged,
  });

  final String selectedVoice;
  final TtsVoiceSnapshot? snapshot;
  final bool isLoading;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final List<TtsVoiceOption> voices =
        snapshot?.voices ?? const <TtsVoiceOption>[];
    final bool hasSelected = voices.any(
      (TtsVoiceOption voice) => voice.id == selectedVoice,
    );
    final String value = hasSelected ? selectedVoice : '';

    return _SettingsRowFrame(
      child: Row(
        children: <Widget>[
          Expanded(
            child: _TitleBlock(
              title: '英语朗读音色',
              description: isLoading
                  ? '正在读取当前引擎的英语音色。'
                  : '可选已安装的英语音色；自动选择会优先使用高质量音色。',
            ),
          ),
          const SizedBox(width: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFB9CDBE)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: value,
                  borderRadius: BorderRadius.circular(16),
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Color(0xFF53625A),
                  ),
                  items: <DropdownMenuItem<String>>[
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('自动选择（优先高质量）'),
                    ),
                    for (final TtsVoiceOption voice in voices)
                      DropdownMenuItem<String>(
                        value: voice.id,
                        child: Text(voice.label),
                      ),
                  ],
                  onChanged: isLoading ? null : onChanged,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubtitleWordHighlightBorderWidthRow extends StatelessWidget {
  const _SubtitleWordHighlightBorderWidthRow({
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;

  static final Map<double, String> _options = <double, String>{
    1.5: '细',
    2.5: '标准',
    3.5: '粗',
  };

  @override
  Widget build(BuildContext context) {
    return _SettingsRowFrame(
      child: Row(
        children: <Widget>[
          const Expanded(
            child: _TitleBlock(
              title: '单词高亮边框粗细',
              description: '调整播放中当前朗读单词的边框粗细。',
            ),
          ),
          const SizedBox(width: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFB9CDBE)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<double>(
                  value: value,
                  borderRadius: BorderRadius.circular(16),
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Color(0xFF53625A),
                  ),
                  items: _options.entries
                      .map(
                        (MapEntry<double, String> entry) =>
                            DropdownMenuItem<double>(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                      )
                      .toList(growable: false),
                  onChanged: (double? nextValue) {
                    if (nextValue != null) onChanged(nextValue);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TtsRateRow extends StatelessWidget {
  const _TtsRateRow({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  static const List<double> _rates = <double>[0.5, 0.75, 1, 1.25];

  @override
  Widget build(BuildContext context) {
    return _SettingsRowFrame(
      child: Row(
        children: <Widget>[
          const Expanded(
            child: _TitleBlock(
              title: '英语朗读速度',
              description: '只影响单词和句子朗读，不影响视频播放速度。',
            ),
          ),
          const SizedBox(width: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFB9CDBE)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<double>(
                  value: value,
                  borderRadius: BorderRadius.circular(16),
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Color(0xFF53625A),
                  ),
                  items: _rates
                      .map(
                        (double rate) => DropdownMenuItem<double>(
                          value: rate,
                          child: Text('$rate×'),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (double? nextValue) {
                    if (nextValue != null) onChanged(nextValue);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.title,
    required this.description,
    required this.value,
    required this.hintText,
    required this.onChanged,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
  });

  final String title;
  final String description;
  final String value;
  final String hintText;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return _SettingsRowFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _TitleBlock(title: title, description: description),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey<int>(Object.hash(title, enabled, value.hashCode)),
            initialValue: value,
            enabled: enabled,
            obscureText: obscureText,
            keyboardType: keyboardType,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hintText,
              filled: true,
              fillColor: enabled ? Colors.white : const Color(0xFFF3F6F4),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFB9CDBE)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFB9CDBE)),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFD4DDD7)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectRow extends StatelessWidget {
  const _SelectRow({
    required this.title,
    required this.description,
    required this.value,
    required this.options,
    required this.onChanged,
    this.optionLabel,
  });

  final String title;
  final String description;
  final String value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final String Function(String value)? optionLabel;

  @override
  Widget build(BuildContext context) {
    return _SettingsRowFrame(
      child: Row(
        children: <Widget>[
          Expanded(
            child: _TitleBlock(title: title, description: description),
          ),
          const SizedBox(width: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFB9CDBE)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: value,
                  borderRadius: BorderRadius.circular(16),
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Color(0xFF53625A),
                  ),
                  items: options
                      .map((String item) {
                        return DropdownMenuItem<String>(
                          value: item,
                          child: Text(optionLabel?.call(item) ?? item),
                        );
                      })
                      .toList(growable: false),
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingsRowFrame(
      child: Row(
        children: <Widget>[
          Expanded(
            child: _TitleBlock(title: title, description: description),
          ),
          const SizedBox(width: 16),
          SwitchTheme(
            data: SwitchThemeData(
              trackOutlineColor: WidgetStateProperty.resolveWith<Color?>((
                Set<WidgetState> states,
              ) {
                if (states.contains(WidgetState.selected)) {
                  return const Color(0xFF0F7A43);
                }
                return Colors.transparent;
              }),
              trackColor: WidgetStateProperty.resolveWith<Color>((
                Set<WidgetState> states,
              ) {
                if (states.contains(WidgetState.selected)) {
                  return const Color(0xFF0F7A43);
                }
                return const Color(0xFFE4E8E4);
              }),
              thumbColor: WidgetStateProperty.all<Color>(Colors.white),
            ),
            child: Switch(value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.title,
    required this.description,
    required this.onTap,
    this.danger = false,
    this.icon,
  });

  final String title;
  final String description;
  final VoidCallback onTap;
  final bool danger;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final Color titleColor = danger
        ? const Color(0xFFC62828)
        : const Color(0xFF191C1E);
    final Color descColor = danger
        ? const Color(0xFFD86A6A)
        : const Color(0xFF53625A);
    final Color iconColor = danger
        ? const Color(0xFFC62828)
        : const Color(0xFF8C9890);

    return InkWell(
      onTap: onTap,
      child: _SettingsRowFrame(
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: descColor),
                  ),
                ],
              ),
            ),
            Icon(
              icon ??
                  (danger
                      ? Icons.restore_from_trash_rounded
                      : Icons.chevron_right_rounded),
              color: iconColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRowFrame extends StatelessWidget {
  const _SettingsRowFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: child,
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF191C1E),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          description,
          style: const TextStyle(fontSize: 12, color: Color(0xFF53625A)),
        ),
      ],
    );
  }
}
