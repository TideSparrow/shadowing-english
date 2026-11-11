import 'dart:convert';

import 'package:common_learn_english/features/settings/data/app_update_service.dart';
import 'package:common_learn_english/features/settings/presentation/app_update_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const AppUpdate _release = AppUpdate(
  version: '0.3.1',
  assetName: 'shadowing-english-v0.3.1-android.apk',
  downloadUrl: 'https://example.com/shadowing-english-v0.3.1-android.apk',
  checksumUrl: 'https://example.com/SHA256SUMS.txt',
);

class _UpdateService extends AppUpdateService {
  int checks = 0;
  AppUpdate? release = _release;
  bool fail = false;

  @override
  Future<AppUpdate?> checkForUpdate() async {
    checks++;
    if (fail) throw StateError('Offline');
    return release;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('automatic checks share a daily result across restarts', () async {
    final _UpdateService service = _UpdateService();
    final ProviderContainer first = _container(service);
    final AppUpdateNotifier notifier = first.read(appUpdateProvider.notifier);

    await Future.wait(<Future<Duration>>[
      notifier.checkAutomatically(),
      notifier.checkAutomatically(),
    ]);
    expect(service.checks, 1);
    expect(first.read(appUpdateProvider).update?.version, '0.3.1');
    expect(first.read(appUpdateProvider).message, isNull);

    final ProviderContainer reopened = _container(service);
    final Duration delay = await reopened
        .read(appUpdateProvider.notifier)
        .checkAutomatically();
    expect(delay, greaterThan(const Duration(hours: 23)));
    expect(service.checks, 1);
    expect(reopened.read(appUpdateProvider).update?.version, '0.3.1');

    service.release = null;
    final ProviderContainer upgraded = _container(service, version: '0.3.1');
    await upgraded.read(appUpdateProvider.notifier).checkAutomatically();
    expect(service.checks, 2);
    expect(upgraded.read(appUpdateProvider).update, isNull);
  });

  test('a failed daily check retains the last known update', () async {
    final _UpdateService service = _UpdateService();
    final ProviderContainer first = _container(service);
    await first.read(appUpdateProvider.notifier).checkAutomatically();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = prefs.getKeys().single;
    final Map<String, dynamic> cached =
        jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
    cached['checkedAt'] = DateTime.now()
        .subtract(const Duration(days: 1, minutes: 1))
        .millisecondsSinceEpoch;
    await prefs.setString(key, jsonEncode(cached));

    service.fail = true;
    final ProviderContainer reopened = _container(service);
    final AppUpdateNotifier notifier = reopened.read(
      appUpdateProvider.notifier,
    );
    await notifier.checkAutomatically();
    await notifier.checkAutomatically();
    expect(service.checks, 2);
    expect(reopened.read(appUpdateProvider).update?.version, '0.3.1');
    expect(reopened.read(appUpdateProvider).message, isNull);

    await notifier.check();
    expect(service.checks, 3);
    expect(reopened.read(appUpdateProvider).message, startsWith('更新检测失败'));
  });
}

ProviderContainer _container(
  _UpdateService service, {
  String version = '0.3.0',
}) {
  return ProviderContainer.test(
    overrides: <Override>[
      appVersionProvider.overrideWith((_) async => version),
      appUpdateServiceProvider.overrideWithValue(service),
    ],
  );
}
