import 'package:common_learn_english/features/settings/data/app_update_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('checks the current repository and selects each platform update', () async {
    PackageInfo.setMockInitialValues(
      appName: 'Shadowing English',
      packageName: 'com.shadowing.english',
      version: '0.2.4',
      buildNumber: '14',
      buildSignature: '',
    );
    const String downloadRoot =
        'https://github.com/TideSparrow/shadowing-english/releases/download/v0.2.5';
    const Map<TargetPlatform, String> suffixes = <TargetPlatform, String>{
      TargetPlatform.android: 'android.apk',
      TargetPlatform.linux: 'linux-x64.tar.gz',
      TargetPlatform.macOS: 'macos.dmg',
      TargetPlatform.windows: 'windows-x64.zip',
    };
    final Dio dio = Dio();
    addTearDown(dio.close);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          expect(options.uri.host, 'api.github.com');
          expect(
            options.uri.path,
            '/repos/TideSparrow/shadowing-english/releases',
          );
          handler.resolve(
            Response<List<dynamic>>(
              requestOptions: options,
              data: <dynamic>[
                <String, dynamic>{
                  'tag_name': 'v0.2.5',
                  'draft': false,
                  'prerelease': false,
                  'assets': <Map<String, String>>[
                    for (final String suffix in suffixes.values)
                      <String, String>{
                        'name': 'shadowing-english-v0.2.5-$suffix',
                        'browser_download_url':
                            '$downloadRoot/shadowing-english-v0.2.5-$suffix',
                      },
                    <String, String>{
                      'name': 'SHA256SUMS.txt',
                      'browser_download_url': '$downloadRoot/SHA256SUMS.txt',
                    },
                  ],
                },
              ],
            ),
          );
        },
      ),
    );

    for (final MapEntry<TargetPlatform, String> platform in suffixes.entries) {
      debugDefaultTargetPlatformOverride = platform.key;
      final AppUpdate? update = await AppUpdateService(
        dio: dio,
      ).checkForUpdate();
      expect(update, isNotNull);
      expect(update!.version, '0.2.5');
      expect(update.assetName, 'shadowing-english-v0.2.5-${platform.value}');
      expect(update.downloadUrl, '$downloadRoot/${update.assetName}');
      expect(update.checksumUrl, '$downloadRoot/SHA256SUMS.txt');
    }
  });
}
