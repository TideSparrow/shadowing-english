import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

const String _releasesUrl =
    'https://api.github.com/repos/TideSparrow/shadowing-english/releases?per_page=100';

class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.assetName,
    required this.downloadUrl,
    required this.checksumUrl,
  });

  final String version;
  final String assetName;
  final String downloadUrl;
  final String checksumUrl;
}

class AppUpdateService {
  AppUpdateService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<AppUpdate?> checkForUpdate() async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    final Response<List<dynamic>> response = await _dio.get<List<dynamic>>(
      _releasesUrl,
      options: Options(
        headers: <String, String>{
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ),
    );
    final Map<String, dynamic> release = _highestStableRelease(
      response.data ?? <dynamic>[],
    );
    final String latestVersion = _versionFromTag(release['tag_name']);
    if (_compareVersions(latestVersion, packageInfo.version) <= 0) {
      return null;
    }

    final List<dynamic> assets =
        release['assets'] as List<dynamic>? ?? <dynamic>[];
    final String suffix = _assetSuffixForCurrentPlatform();
    final Map<String, dynamic>? package = _assetEndingWith(assets, suffix);
    final Map<String, dynamic>? checksum = _assetEndingWith(
      assets,
      'SHA256SUMS.txt',
    );
    if (package == null || checksum == null) {
      throw StateError('该 Release 未提供当前平台（$suffix）的更新包。');
    }

    return AppUpdate(
      version: latestVersion,
      assetName: package['name'] as String,
      downloadUrl: package['browser_download_url'] as String,
      checksumUrl: checksum['browser_download_url'] as String,
    );
  }

  Future<String> download(
    AppUpdate update, {
    void Function(int received, int total)? onProgress,
  }) async {
    final Directory root =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final Directory destination = Directory(
      '${root.path}${Platform.pathSeparator}Shadowing English',
    );
    await destination.create(recursive: true);
    final File file = File(
      '${destination.path}${Platform.pathSeparator}${update.assetName}',
    );

    await _dio.download(
      update.downloadUrl,
      file.path,
      onReceiveProgress: onProgress,
    );
    final String expectedChecksum = await _checksumFor(
      update.assetName,
      update.checksumUrl,
    );
    final String actualChecksum = (await sha256.bind(file.openRead()).first)
        .toString();
    if (actualChecksum.toLowerCase() != expectedChecksum.toLowerCase()) {
      await file.delete();
      throw StateError('安装包校验失败，已删除下载文件。');
    }
    return file.path;
  }

  Future<void> install(String path) async {
    final OpenResult result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      throw StateError(result.message);
    }
  }

  Future<String> _checksumFor(String assetName, String checksumUrl) async {
    final Response<String> response = await _dio.get<String>(checksumUrl);
    for (final String rawLine in response.data?.split('\n') ?? <String>[]) {
      final String line = rawLine.trim();
      if (line.endsWith('  $assetName')) {
        return line.split(RegExp(r'\s+')).first;
      }
    }
    throw StateError('SHA256SUMS.txt 中未找到 $assetName。');
  }

  Map<String, dynamic>? _assetEndingWith(List<dynamic> assets, String suffix) {
    for (final dynamic asset in assets) {
      if (asset is Map<String, dynamic>) {
        final Object? name = asset['name'];
        if (name is String && name.endsWith(suffix)) {
          return asset;
        }
      }
    }
    return null;
  }
}

Map<String, dynamic> _highestStableRelease(List<dynamic> releases) {
  Map<String, dynamic>? newestRelease;
  String? newestVersion;
  for (final dynamic release in releases) {
    if (release is! Map<String, dynamic> ||
        release['draft'] == true ||
        release['prerelease'] == true) {
      continue;
    }
    final String? version = _tryVersionFromTag(release['tag_name']);
    if (version == null) {
      continue;
    }
    if (newestVersion == null || _compareVersions(version, newestVersion) > 0) {
      newestRelease = release;
      newestVersion = version;
    }
  }
  if (newestRelease == null) {
    throw const FormatException('GitHub 未返回可用的正式 Release。');
  }
  return newestRelease;
}

String _assetSuffixForCurrentPlatform() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return '-android.apk';
    case TargetPlatform.linux:
      return '-linux-x64.tar.gz';
    case TargetPlatform.macOS:
      return '-macos.dmg';
    case TargetPlatform.windows:
      return '-windows-x64.zip';
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      throw UnsupportedError('当前平台不支持从 GitHub Release 更新。');
  }
}

String _versionFromTag(Object? tag) {
  final String? version = _tryVersionFromTag(tag);
  if (version == null) {
    throw const FormatException('GitHub Release 缺少版本标签。');
  }
  return version;
}

String? _tryVersionFromTag(Object? tag) {
  if (tag is! String) {
    return null;
  }
  final String version = tag.replaceFirst(RegExp('^v'), '');
  return RegExp(r'^\d+(?:\.\d+){2}$').hasMatch(version) ? version : null;
}

int _compareVersions(String left, String right) {
  final List<int> leftParts = left
      .split('+')
      .first
      .split('.')
      .map(int.parse)
      .toList();
  final List<int> rightParts = right
      .split('+')
      .first
      .split('.')
      .map(int.parse)
      .toList();
  final int length = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (int index = 0; index < length; index++) {
    final int difference =
        (index < leftParts.length ? leftParts[index] : 0) -
        (index < rightParts.length ? rightParts[index] : 0);
    if (difference != 0) {
      return difference;
    }
  }
  return 0;
}
