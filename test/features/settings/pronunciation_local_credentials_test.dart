import 'dart:io';

import 'package:common_learn_english/features/player/domain/pronunciation_assessment.dart';
import 'package:common_learn_english/features/settings/data/pronunciation_credentials.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel keychain = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  late Directory directory;
  late List<ProviderContainer> containers;
  int keychainCalls = 0;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    containers = <ProviderContainer>[];
    keychainCalls = 0;
    // Trap any attempt to read, migrate, write, or delete an old keychain item.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(keychain, (MethodCall call) async {
          keychainCalls++;
          throw StateError('The macOS settings flow must not use Keychain.');
        });
    directory = Directory.systemTemp.createTempSync('pronunciation-local-');
    Hive.init(directory.path);
    await Hive.openBox<String>('prefs');
  });

  tearDown(() async {
    for (final ProviderContainer container in containers) {
      container.dispose();
    }
    if (Hive.isBoxOpen('prefs')) await Hive.box<String>('prefs').close();
    await directory.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(keychain, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('macOS save, disk reopen and clear never access Keychain', () async {
    const String unrelatedSettings = '{"translationApiKey":"test-bailian-key"}';
    await Hive.box<String>(
      'prefs',
    ).put('learning_settings_v1', unrelatedSettings);
    final ProviderContainer first = ProviderContainer();
    containers.add(first);
    expect(
      first.read(pronunciationCredentialStoreProvider),
      isA<LocalPronunciationCredentialStore>(),
    );
    expect(
      (await first.read(pronunciationCredentialsProvider.future)).isComplete,
      isFalse,
    );
    await first
        .read(pronunciationCredentialsProvider.notifier)
        .saveCredentials(
          appId: ' 1250000000 ',
          secretId: ' test-id ',
          secretKey: ' test-key ',
        );
    first.dispose();
    containers.remove(first);
    await Hive.box<String>('prefs').close();
    await Hive.openBox<String>('prefs');

    final ProviderContainer reopened = ProviderContainer();
    containers.add(reopened);
    final PronunciationCredentials restored = await reopened.read(
      pronunciationCredentialsProvider.future,
    );
    expect(restored.appId, '1250000000');
    expect(restored.secretId, 'test-id');
    expect(restored.secretKey, 'test-key');
    for (int i = 0; i < 3; i++) {
      expect(
        (await reopened.read(
          pronunciationCredentialsProvider.future,
        )).secretKey,
        'test-key',
      );
    }
    await reopened
        .read(pronunciationCredentialsProvider.notifier)
        .saveCredentials(appId: '', secretId: '', secretKey: '');
    expect(
      Hive.box<String>(
        'prefs',
      ).containsKey('pronunciation.tencent.credentials.v1'),
      isFalse,
    );
    expect(
      Hive.box<String>('prefs').get('learning_settings_v1'),
      unrelatedSettings,
    );
    expect(keychainCalls, 0);
  });

  test('failed local save is not cached and a later retry succeeds', () async {
    await Hive.box<String>('prefs').close();
    final ProviderContainer container = ProviderContainer();
    containers.add(container);
    await container.read(pronunciationCredentialsProvider.future);
    final PronunciationCredentialsNotifier notifier = container.read(
      pronunciationCredentialsProvider.notifier,
    );
    await expectLater(
      notifier.saveCredentials(
        appId: '1250000000',
        secretId: 'test-id',
        secretKey: 'test-key',
      ),
      throwsStateError,
    );
    expect(
      container.read(pronunciationCredentialsProvider).requireValue.isComplete,
      isFalse,
    );
    await Hive.openBox<String>('prefs');
    await notifier.saveCredentials(
      appId: '1250000000',
      secretId: 'test-id',
      secretKey: 'test-key',
    );
    expect(
      container.read(pronunciationCredentialsProvider).requireValue.isComplete,
      isTrue,
    );
    expect(keychainCalls, 0);
  });

  test('other native platforms keep their existing secure store', () {
    for (final TargetPlatform platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      final ProviderContainer container = ProviderContainer();
      containers.add(container);
      expect(
        container.read(pronunciationCredentialStoreProvider),
        isA<SecurePronunciationCredentialStore>(),
      );
    }
    expect(keychainCalls, 0);
  });
}
