<p align="center">
  <img src="assets/img/app_icon.png" alt="Shadowing English app icon" width="112" />
</p>

<h1 align="center">Shadowing English</h1>

> A local-first English shadowing app for listening and speaking practice with your own videos and subtitles.

> 使用自己的视频和字幕，通过逐句精听、重复播放和影子跟读练习英语听力与口语。

[English](README_EN.md) · 中文

[![License: MIT](https://img.shields.io/badge/License-MIT-0F766E.svg)](LICENSE)
[![CI](https://github.com/TideSparrow/shadowing-english/actions/workflows/lint.yaml/badge.svg)](https://github.com/TideSparrow/shadowing-english/actions/workflows/lint.yaml)
[![Flutter 3.44.4](https://img.shields.io/badge/Flutter-3.44.4-02569B?logo=flutter&logoColor=white)](.fvmrc)
[![Latest release](https://img.shields.io/github/v/release/TideSparrow/shadowing-english?display_name=tag&sort=semver)](https://github.com/TideSparrow/shadowing-english/releases/latest)
[![Release platforms](https://img.shields.io/badge/Release-Android%20%7C%20macOS%20%7C%20Linux%20%7C%20Windows-475569)](https://github.com/TideSparrow/shadowing-english/releases/latest)
[![GitHub stars](https://img.shields.io/github/stars/TideSparrow/shadowing-english?style=flat)](https://github.com/TideSparrow/shadowing-english/stargazers)
[![GitHub issues](https://img.shields.io/github/issues/TideSparrow/shadowing-english)](https://github.com/TideSparrow/shadowing-english/issues)
[![请我喝杯咖啡](https://img.shields.io/badge/请我喝杯咖啡-FFDD00?logo=buymeacoffee&logoColor=000000)](https://buymeacoffee.com/marklongpcm)

[下载最新版](https://github.com/TideSparrow/shadowing-english/releases/latest) · [字幕功能说明](#字幕功能从导入到逐词跟读) · [从源码运行](#从源码运行) · [导入学习素材](#导入学习素材)

## 功能截图

| 播放与逐句精听 | 导入本地视频与字幕 |
| :---: | :---: |
| <img src="assets/showcase/player.png" alt="逐句精听、播放控制和字幕面板" width="100%" /> | <img src="assets/showcase/import-course.jpg" alt="导入本地视频与字幕的流程" width="100%" /> |
| 点按字幕、循环难句，在视频与原句之间保持专注。 | 选择自己的媒体与字幕，确认匹配后开始学习。 |
| 点词查译与上下文 | 全文逐词阅读与播放联动 |
| <img src="assets/showcase/word-lookup-popup.png" alt="点按逐句字幕单词后显示的翻译和上下文弹窗" width="100%" /> | <img src="assets/showcase/full-transcript-reader.png" alt="逐词全文阅读器，当前播放句和单词会自动高亮" width="100%" /> |
| 点按字幕单词，立即查看释义、原句上下文，并可收藏或播放发音。 | 打开全文逐词阅读器，播放进度会同步定位当前句和单词。 |
| 视频字幕点词弹窗 | |
| <img src="assets/showcase/video-subtitle-lookup.png" alt="直接点按视频字幕中的单词后显示的翻译弹窗" width="100%" /> | |
| 视频正在播放时，也能直接点按画面字幕里的单词查看释义。 | |
| 三遍学习法 | 学习成长与等级 |
| <img src="assets/showcase/learning-guide.jpg" alt="Shadowing English 的三遍学习法页面" width="100%" /> | <img src="assets/showcase/growth.png" alt="学习成长、等级和学习路线" width="100%" /> |
| 先理解，再精听，最后跟读。 | 记录练习、积累经验，清楚看到下一步。 |
| 单词本 | 短语复习 |
| <img src="assets/showcase/words.jpg" alt="单词本与词义查看" width="100%" /> | <img src="assets/showcase/phrases.jpg" alt="短语收藏与复习空间" width="100%" /> |
| 将查过的重点单词留在语境中继续复习。 | 收藏值得反复开口练习的表达。 |
| 字幕、翻译与播放设置 | |
| <img src="assets/showcase/settings.jpg" alt="字幕、翻译和播放相关设置" width="100%" /> | |
| 按自己的学习方式配置字幕与辅助能力。 | |

Shadowing English 是一个 English shadowing app：你导入自己有权使用的本地视频和字幕，用真实场景完成听懂、重复、模仿和开口表达。项目不提供任何影视、课程或字幕资源；学习素材保留在你的设备上。

## 什么是 Shadowing English

影子跟读不是只跟着念一遍台词。它把英语听力练习和英语口语练习放在同一段真实视频里：先理解内容，再辨认声音，最后模仿说话者的节奏、连读、语调和发音。

你可以把自己想看的内容变成字幕英语学习材料。单词和短语不会脱离语境，下一次也能回到原来的句子继续练。

## 影子跟读怎么学

1. **理解 Understand**：打开双语字幕，先了解剧情、人物关系和说话语气。
2. **精听 Listen**：切换到英文字幕，逐句定位、重复播放，把难句听清楚。
3. **跟读 Shadow**：减少字幕辅助，模仿原声的节奏、连读、重音与语调。

短句循环让听觉识别和口语输出不断衔接。每次只练几句，也能逐步从“看懂字幕”走到“听懂并说出来”。

## 核心功能

- **本地视频导入**：从设备选择自己的视频文件夹，建立个人课程库。
- **课程资源目录**：在课程卡片或详情中查看视频、字幕目录；桌面端移动文件夹后可预览并重新关联，保留学习进度和生词，缺失剧集不删除，新视频按需导入。
- **字幕导入与匹配**：导入 `.srt` 或 `.vtt` 字幕，按文件名和集数标记匹配视频与字幕。
- **逐句字幕导航**：点按字幕定位播放位置，在完整视频中专注当前句子。
- **单句重复播放**：快速重播当前句子，并可开启单句循环。
- **字幕显示模式**：根据学习阶段切换英文、双语或隐藏字幕。
- **字幕查词**：点按字幕中的单词查看释义，并保留在原始语境里。
- **逐词全文阅读**：打开全文后，当前播放句和单词会自动高亮定位。
- **视频字幕点词**：播放画面中的字幕单词同样可以直接点按查词。
- **单词与短语收藏**：将值得复习的单词和表达保存到单词本、短语库。旧生词支持重新关联影片并跳到原时间点；影片语境随字幕大小写设置显示，保留原始台词。
- **Anki 导出**：收藏单词和短语可导出为自带卡片样式的 `.apkg` 牌组，也支持 TSV／CSV，保留音标、释义、多条原句、翻译及剧集时间点。
- **Shadowing 跟读模式**：记录每次跟读练习，让开口练习进入学习进度。
- **学习成长**：查看学习时长、句子、短语、课程进度、等级与成就。
- **可选 AI 字幕**：为没有现成字幕的视频生成或切换字幕，需要自行配置服务商。
- **本地优先**：视频、字幕和学习记录以设备本地内容为中心。

## 导出到 Anki

在“单词本”或“短语库”顶部点击“导出”，选择收藏单词、收藏短语和格式。Anki、CSV、TSV 中的英文语境与短语均按点击导出时的“英文字幕大小写”设置生成，收藏原文保持不变。默认 `.apkg` 自带卡片模板，保存后在 Anki 中导入即可；手机通过系统分享菜单选择保存或导入 Anki。

相同表达会合并多条语境。`.apkg` 使用稳定标识，重复导入可更新原卡片；在 Anki 中选择更新现有笔记即可，已有复习进度会保留。取消收藏不会自动删除此前导入 Anki 的卡片。导出只读取本地内容，不包含音视频片段，也不会改变应用内的复习计划。

CSV／TSV 均为普通纯文本表格，首行为相同的中文表头：英文、音标、释义、原句语境、原句翻译、来源、时间点、类型，不包含 Anki 配置行。两种格式保留原句换行，采用带 BOM 的 UTF-8 编码，方便表格软件识别中文；CSV 使用逗号分隔，TSV 使用制表符分隔。

## 字幕功能：从导入到逐词跟读

Shadowing English 不只是在视频上显示一句字幕，而是把字幕变成可以定位、循环、查词和跟读的学习时间轴。你可以按素材情况选择以下方式：

- **导入外部字幕**：支持 `.srt` 和 `.vtt`。已有质量较好的字幕时，这是最直接的方式；英文和中文字幕可以按文件名自动匹配。
- **切换视频内置字幕**：如果视频文件本身带有可切换字幕轨道，可以在播放器的字幕菜单中选择，不需要先把字幕从视频中导出。
- **AI生成可跟读的词级同步字幕**：没有现成字幕，或现有字幕只有整句时间轴时，可以让 AI 识别音频，为每个英文单词生成开始和结束时间。

### 如何使用 AI 字幕

1. 打开“设置”，在“AI生成可跟读的词级同步字幕”中选择 ASR 服务商并填写自己的 API Key。目前支持阿里云百炼（默认）和腾讯云；OpenAI 字幕生成入口已暂时移除，OpenAI 翻译仍可正常使用。
2. 如果需要中英双语，保持“生成双语字幕”开启，并配置翻译服务；只需要英文字幕时可以关闭它。
3. 导入并播放视频，在播放器中点击“AI生成可跟读的词级同步字幕”。生成过程中可以看到识别、翻译和保存进度。
4. 生成成功后，字幕会保存在本机并用于播放。进入“设置 → 管理 AI 字幕”，可以查看、按单词修改文本、导出、重新生成或删除字幕。

AI 中文翻译会按句子编号批量处理，每批最多 40 句，并根据文本长度进一步分批；已完成的翻译会保留，重试时只补未完成的部分。

生成字幕会调用你选择的第三方服务，可能产生少量费用。API Key 请只填写在应用设置中，不要提交到仓库、截图或公开日志里。

### 它是怎么工作的

```text
本地视频
  → 在设备上提取并分段音频
  → ASR 服务识别英文和词级时间戳
  → 本地合并、检查并修复时间轴
  → 可选批量生成中文翻译
  → 保存到本机并随播放逐词高亮
```

如果素材已有英文外部字幕或可读取的内置字幕，应用会把它作为参考：保留更完整、可靠的原字幕文本，再利用语音识别结果补充或校准单词时间。参考字幕不会被静默覆盖；当识别结果或时间轴需要修复时，应用会给出提示。没有参考字幕时，则直接根据视频音频生成英文文本和时间轴。

### 相比普通字幕的优势

- **逐词同步，而不只是整句同步**：正在说的单词会随播放高亮，更容易辨认连读、弱读和重音。
- **字幕直接参与学习**：点一句即可跳转，难句可以循环；点单词可查译，也可以在全文阅读中跟随播放定位。
- **充分利用已有字幕**：质量较好的原字幕负责正文，AI 更专注于补全词级时间，减少纯语音识别造成的漏词和错词。
- **生成结果可管理**：字幕保存在本机，可以编辑、导出、重新生成和删除，不必每次播放都重新调用服务。
- **失败时尽量保留可用结果**：应用会在本地修复常见的时间重叠、缺失时间戳等问题，并在中文翻译未完成时优先保留已经生成的英文字幕。

AI 识别仍可能受到背景音乐、多人重叠说话、口音和录音质量影响。重要内容建议使用已有字幕作为参考，并在“管理 AI 字幕”中检查后再长期使用。

## 为什么使用它

- **从你真正想看的视频开始**：看视频学英语不必依赖固定课程包。
- **让表达留在场景中**：单词、句子和短语来自真实对话，而不是孤立列表。
- **同一句可以反复练**：逐句定位与循环播放适合精听和 English shadowing practice。
- **听力和口语一起练**：先听懂，再跟读，减少“认识但说不出”的断层。
- **素材由你掌控**：本地视频和字幕不会被项目服务器收集或分发。

## 开始使用

### 下载应用

[最新正式版](https://github.com/TideSparrow/shadowing-english/releases/latest)提供以下安装包：

- Android：APK
- macOS：DMG
- Linux：x64 `.tar.gz`
- Windows：x64 `.zip`

前往 [Releases](https://github.com/TideSparrow/shadowing-english/releases/latest) 选择对应平台下载。

从 v0.1.2 起，每个版本附带 `SHA256SUMS.txt`，可用于校验下载文件是否完整。

桌面安装包内置了用于本地音频提取的精简版 FFmpeg，无需用户额外安装；许可证和构建信息会随应用一起发布。

### 从源码运行

需要 Flutter 3.44.4；仓库通过 FVM 固定版本。首次使用请先安装 [FVM](https://fvm.app/documentation/getting-started/installation)。

```bash
git clone https://github.com/TideSparrow/shadowing-english.git
cd shadowing-english
fvm use 3.44.4
fvm flutter pub get
fvm flutter run
```

在 VS Code 中安装 Flutter 与 Dart 扩展，打开项目根目录后，选择运行和调试配置 `Flutter - Prod (select device)`，再按 F5。项目会通过 `.fvm/flutter_sdk` 使用固定的 Flutter 版本；请不要提交本机 SDK 路径、设备 ID 或密钥。

如果使用自己的 Flutter 环境，也可以执行：

```bash
flutter pub get
flutter run
```

## 导入学习素材

推荐让视频与字幕使用相同的集数命名，例如：

```text
Friends-S01E01.mp4
Friends-S01E01.en.srt
Friends-S01E01.zh.srt
```

英文字幕可以是同名的 `Friends-S01E01.srt`，也可以通过 `.en`、`_en`、`english` 等文件名标记识别。导入前请确认你拥有相应媒体和字幕的使用权。

更多说明见 [RESOURCE_SETUP.md](RESOURCE_SETUP.md)。仓库不附带影视内容、商业字幕或未经授权的学习资源。

## 隐私

- 视频、字幕和学习记录以本地设备为中心保存和管理。
- 项目不会提供或托管你的课程资源。
- 如果你启用 AI 字幕或翻译，会使用你自行配置的第三方服务；相应请求由该服务商处理。

## 参与贡献

欢迎提交 [Issue](https://github.com/TideSparrow/shadowing-english/issues)，尤其是字幕匹配、播放器与跨平台问题。准备 Pull Request 前，建议先开 Issue 讨论；请不要提交未经授权的视频、字幕或课程资源。

## 支持项目

如果 Shadowing English 对你的英语学习有帮助，欢迎 [请我喝杯咖啡](https://buymeacoffee.com/marklongpcm)，支持项目维护、问题修复和功能改进。

赞助完全自愿，不影响应用的使用或 MIT 开源许可。也欢迎通过 Star、Issue 和 Pull Request 支持项目。

## License

Shadowing English 使用 [MIT License](LICENSE) 开源。

如果你正在寻找一个用本地视频练习英语听力、英语跟读和英语口语表达的工具，欢迎试试 Shadowing English。
