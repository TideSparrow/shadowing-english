# Contributing / 参与开发

欢迎提交问题、产品建议、文档改进和范围明确的 Pull Request。
Bug reports, product ideas, documentation improvements, and focused pull requests are welcome.

## 从终端运行 / Run from a terminal

项目使用 Flutter **3.44.4**，Dart 随 Flutter 一起安装。FVM 只是 Flutter 版本管理工具，不是应用框架；VS Code 也不是必需的。可以使用 Android Studio、IntelliJ、其他编辑器或终端。

The project uses Flutter **3.44.4**, which includes Dart. FVM only manages SDK versions; neither FVM nor VS Code is required. Android Studio, IntelliJ, other editors, and terminal workflows are supported.

已安装对应版本的 Flutter 时，在仓库根目录执行：
With the matching Flutter SDK installed, run from the repository root:

```bash
flutter doctor
flutter pub get
flutter devices
flutter run -d <device-id>
```

`<device-id>` 来自 `flutter devices`，例如 `windows`、`macos` 或已连接的 Android 设备。桌面构建须在对应系统进行；Android 需要 Android SDK。用 `flutter doctor` 检查本机缺少的工具。

Use an ID from `flutter devices`, such as `windows`, `macos`, or a connected Android device. Desktop builds require the corresponding OS; Android requires the Android SDK. `flutter doctor` identifies missing local tools.

如果偏好 FVM，执行 `fvm install` 后，把上面的 `flutter` 换成 `fvm flutter` 即可；版本记录在 `.fvmrc`。
If you prefer FVM, run `fvm install`, then replace `flutter` with `fvm flutter` above. The pinned version is stored in `.fvmrc`.

## 代码入口 / Code map

| 路径 / Path | 用途 / Purpose |
| --- | --- |
| `lib/main.dart`、`lib/my_app.dart` | 应用启动、主题 / Startup and theme |
| `lib/router/` | 页面路由 / Navigation |
| `lib/features/library/` | 课程库、剧集、资源关联 / Library and episodes |
| `lib/features/import_course/` | 文件选择、后台扫描和字幕匹配 / Import and subtitle matching |
| `lib/features/player/` | 播放、字幕轨道、AI 字幕 / Playback and subtitles |
| `lib/features/settings/` | 设置及持久化 / Settings and persistence |
| `lib/features/words/`、`lib/features/phrases/` | 生词和短语 / Saved words and phrases |
| `test/features/` | 按功能组织的测试 / Tests by feature |
| `android/`、`windows/`、`macos/`、`linux/`、`ios/` | 平台工程 / Platform projects |
| `assets/` | 字典、字体、翻译等 / Dictionaries, fonts, translations |

功能目录通常按 `presentation`（界面与状态）、`domain`（业务逻辑）、`data`（存储与服务）划分；部分小功能只有其中一层。名字中的 `pad` 是历史命名，也用于手机和桌面。排查“全部剧集”从 `library_screen.dart` 和 `widgets/episode_list_item.dart` 开始；字幕轨道从 `player_native_subtitles.dart` 及两个 `pad_*_player_screen.dart` 开始。

Features generally use `presentation` for UI and state, `domain` for business logic, and `data` for storage and services. Small features may omit layers. The historical `pad` prefix also covers phone and desktop layouts. Start episode-list fixes in `library_screen.dart` and `widgets/episode_list_item.dart`; subtitle tracks are handled in `player_native_subtitles.dart` and the two `pad_*_player_screen.dart` files.

## 检查改动 / Validate changes

```bash
flutter analyze
flutter test
```

修改模型或 Riverpod 注解后重新生成代码；不要手改 `*.g.dart`、`*.freezed.dart`：
Regenerate code after changing models or Riverpod annotations; do not hand-edit generated files:

```bash
dart run build_runner build --delete-conflicting-outputs
```

AI 服务配置是可选的，普通本地导入和播放不需要 API Key。不要提交版权视频、字幕包、个人素材、密钥、本机 SDK 路径或设备 ID。
AI service configuration is optional; ordinary local import and playback require no API key. Do not commit copyrighted videos, subtitle packs, personal study material, secrets, local SDK paths, or device IDs.
