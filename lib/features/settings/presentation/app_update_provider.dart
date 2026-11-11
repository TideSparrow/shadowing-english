import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_update_service.dart';

const String _updateCacheKey = 'app_update_check';
const Duration _checkInterval = Duration(days: 1);

bool get supportsAppUpdates =>
    !kIsWeb &&
    switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      TargetPlatform.iOS || TargetPlatform.fuchsia => false,
    };

final FutureProvider<String> appVersionProvider = FutureProvider<String>((
  Ref ref,
) async {
  final PackageInfo packageInfo = await PackageInfo.fromPlatform();
  return packageInfo.version;
});

final Provider<AppUpdateService> appUpdateServiceProvider =
    Provider<AppUpdateService>((Ref ref) => AppUpdateService());

final NotifierProvider<AppUpdateNotifier, AppUpdateState> appUpdateProvider =
    NotifierProvider<AppUpdateNotifier, AppUpdateState>(AppUpdateNotifier.new);

class AppUpdateState {
  const AppUpdateState({
    this.update,
    this.isChecking = false,
    this.isDownloading = false,
    this.isInstalling = false,
    this.downloadedPath,
    this.downloadedBytes = 0,
    this.totalBytes,
    this.message,
  });

  final AppUpdate? update;
  final bool isChecking;
  final bool isDownloading;
  final bool isInstalling;
  final String? downloadedPath;
  final int downloadedBytes;
  final int? totalBytes;
  final String? message;

  double? get downloadProgress => totalBytes == null || totalBytes! <= 0
      ? null
      : downloadedBytes / totalBytes!;
}

class AppUpdateNotifier extends Notifier<AppUpdateState> {
  DateTime? _lastCheckedAt;
  SharedPreferences? _preferences;
  String? _installedVersion;
  bool _cacheLoaded = false;
  bool _checking = false;

  @override
  AppUpdateState build() => const AppUpdateState();

  bool get _isBusy => _checking || state.isDownloading || state.isInstalling;

  Future<Duration> checkAutomatically() async {
    if (!supportsAppUpdates) return _checkInterval;
    if (_isBusy) return const Duration(minutes: 1);
    await _check(automatic: true);
    return _timeUntilNextCheck;
  }

  Future<void> check() => _check(automatic: false);

  Duration get _timeUntilNextCheck {
    final DateTime? checkedAt = _lastCheckedAt;
    if (checkedAt == null) return Duration.zero;
    final Duration elapsed = DateTime.now().difference(checkedAt);
    if (elapsed.isNegative || elapsed >= _checkInterval) return Duration.zero;
    return _checkInterval - elapsed;
  }

  Future<void> _check({required bool automatic}) async {
    if (!supportsAppUpdates || _isBusy) return;
    _checking = true;
    try {
      await _restoreCache();
      if (!ref.mounted || (automatic && _timeUntilNextCheck > Duration.zero)) {
        return;
      }
      final AppUpdateState previous = state;
      state = AppUpdateState(
        update: previous.update,
        downloadedPath: previous.downloadedPath,
        isChecking: true,
      );
      final DateTime checkedAt = DateTime.now();
      _lastCheckedAt = checkedAt;
      await _fetchUpdate(previous, automatic: automatic);
      if (ref.mounted) await _saveCache(checkedAt);
    } finally {
      _checking = false;
    }
  }

  Future<void> _fetchUpdate(
    AppUpdateState previous, {
    required bool automatic,
  }) async {
    try {
      final AppUpdate? update = await ref
          .read(appUpdateServiceProvider)
          .checkForUpdate();
      if (!ref.mounted) return;
      state = AppUpdateState(
        update: update,
        downloadedPath: update?.version == previous.update?.version
            ? previous.downloadedPath
            : null,
        message: automatic
            ? null
            : update == null
            ? '当前已是最新版本。'
            : '发现 v${update.version}，可以下载更新。',
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = AppUpdateState(
        update: previous.update,
        downloadedPath: previous.downloadedPath,
        message: automatic ? null : '更新检测失败：$error',
      );
    }
  }

  Future<void> _restoreCache() async {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    try {
      _installedVersion = await ref.read(appVersionProvider.future);
      _preferences = await SharedPreferences.getInstance();
      final String? raw = _preferences?.getString(_updateCacheKey);
      if (!ref.mounted || raw == null) return;
      final Map<String, dynamic> cached =
          jsonDecode(raw) as Map<String, dynamic>;
      if (cached['installedVersion'] != _installedVersion) return;
      final Map<String, dynamic>? release =
          cached['update'] as Map<String, dynamic>?;
      final AppUpdate? update = release == null
          ? null
          : AppUpdate(
              version: release['version'] as String,
              assetName: release['assetName'] as String,
              downloadUrl: release['downloadUrl'] as String,
              checksumUrl: release['checksumUrl'] as String,
            );
      _lastCheckedAt = DateTime.fromMillisecondsSinceEpoch(
        cached['checkedAt'] as int,
      );
      state = AppUpdateState(update: update);
    } catch (_) {
      // A missing or unreadable cache should never prevent a fresh check.
    }
  }

  Future<void> _saveCache(DateTime checkedAt) async {
    final SharedPreferences? preferences = _preferences;
    if (preferences == null) return;
    final AppUpdate? update = state.update;
    try {
      await preferences.setString(
        _updateCacheKey,
        jsonEncode(<String, Object?>{
          'installedVersion': _installedVersion,
          'checkedAt': checkedAt.millisecondsSinceEpoch,
          'update': update == null
              ? null
              : <String, String>{
                  'version': update.version,
                  'assetName': update.assetName,
                  'downloadUrl': update.downloadUrl,
                  'checksumUrl': update.checksumUrl,
                },
        }),
      );
    } catch (_) {
      // The in-memory result still applies if preferences are unavailable.
    }
  }

  Future<void> download() async {
    final AppUpdate? update = state.update;
    if (update == null || _isBusy) return;
    state = AppUpdateState(update: update, isDownloading: true);
    try {
      final String path = await ref
          .read(appUpdateServiceProvider)
          .download(
            update,
            onProgress: (int received, int total) {
              state = AppUpdateState(
                update: update,
                isDownloading: true,
                downloadedBytes: received,
                totalBytes: total > 0 ? total : null,
              );
            },
          );
      state = AppUpdateState(
        update: update,
        downloadedPath: path,
        message: '下载并校验完成，可以开始安装。',
      );
    } catch (error) {
      state = AppUpdateState(update: update, message: '更新下载失败：$error');
    }
  }

  Future<void> install() async {
    final String? path = state.downloadedPath;
    final AppUpdate? update = state.update;
    if (path == null || update == null || _isBusy) return;
    state = AppUpdateState(
      update: update,
      downloadedPath: path,
      isInstalling: true,
    );
    try {
      await ref.read(appUpdateServiceProvider).install(path);
      state = AppUpdateState(
        update: update,
        downloadedPath: path,
        message: '已打开安装包，请按系统提示完成安装。',
      );
    } catch (error) {
      state = AppUpdateState(
        update: update,
        downloadedPath: path,
        message: '无法打开安装包：$error',
      );
    }
  }
}
