import 'package:common_learn_english/features/player/domain/pronunciation_assessment.dart';
import 'package:common_learn_english/features/settings/data/pronunciation_credentials.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/src/framework.dart' show Override;

class _MemoryCredentialStore implements PronunciationCredentialStore {
  PronunciationCredentials value = const PronunciationCredentials();

  @override
  Future<PronunciationCredentials> read() async => value;

  @override
  Future<void> write(PronunciationCredentials credentials) async {
    value = credentials;
  }
}

void main() {
  test(
    'Tencent pronunciation credentials are independent and reopenable',
    () async {
      final _MemoryCredentialStore store = _MemoryCredentialStore();
      final ProviderContainer first = ProviderContainer(
        overrides: <Override>[
          pronunciationCredentialStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(first.dispose);

      await first.read(pronunciationCredentialsProvider.future);
      await first
          .read(pronunciationCredentialsProvider.notifier)
          .saveCredentials(
            appId: '1250000000',
            secretId: 'test-secret-id',
            secretKey: 'test-secret-key',
          );

      expect(store.value.isComplete, isTrue);
      expect(
        first.read(pronunciationCredentialsProvider).value?.secretKey,
        'test-secret-key',
      );

      final ProviderContainer reopened = ProviderContainer(
        overrides: <Override>[
          pronunciationCredentialStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(reopened.dispose);
      final PronunciationCredentials restored = await reopened.read(
        pronunciationCredentialsProvider.future,
      );
      expect(restored.appId, '1250000000');
      expect(restored.secretId, 'test-secret-id');
      expect(restored.secretKey, 'test-secret-key');
    },
  );

  test('empty values remove credentials from the secure store', () async {
    final _MemoryCredentialStore store = _MemoryCredentialStore()
      ..value = const PronunciationCredentials(
        appId: '1250000000',
        secretId: 'test-secret-id',
        secretKey: 'test-secret-key',
      );
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        pronunciationCredentialStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    await container.read(pronunciationCredentialsProvider.future);
    await container
        .read(pronunciationCredentialsProvider.notifier)
        .saveCredentials(appId: '', secretId: '', secretKey: '');
    expect(store.value.isComplete, isFalse);
  });

  test(
    'credentials are trimmed before state and secure storage updates',
    () async {
      final _MemoryCredentialStore store = _MemoryCredentialStore();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          pronunciationCredentialStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      await container.read(pronunciationCredentialsProvider.future);
      await container
          .read(pronunciationCredentialsProvider.notifier)
          .saveCredentials(
            appId: ' 1250000000 ',
            secretId: ' test-secret-id ',
            secretKey: ' test-secret-key ',
          );

      final PronunciationCredentials saved = container
          .read(pronunciationCredentialsProvider)
          .requireValue;
      expect(saved.appId, '1250000000');
      expect(saved.secretId, 'test-secret-id');
      expect(saved.secretKey, 'test-secret-key');
      expect(store.value.secretKey, saved.secretKey);
    },
  );
}
