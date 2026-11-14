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
    'Ark pronunciation credentials are independent and reopenable',
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
          .saveCredentials(apiKey: 'test-secret-key');

      expect(store.value.isComplete, isTrue);
      expect(
        first.read(pronunciationCredentialsProvider).value?.apiKey,
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

      expect(restored.apiKey, 'test-secret-key');
    },
  );

  test('empty values remove credentials from the secure store', () async {
    final _MemoryCredentialStore store = _MemoryCredentialStore()
      ..value = const PronunciationCredentials(apiKey: 'test-secret-key');
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        pronunciationCredentialStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    await container.read(pronunciationCredentialsProvider.future);
    await container
        .read(pronunciationCredentialsProvider.notifier)
        .saveCredentials(apiKey: '');
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
          .saveCredentials(apiKey: ' test-secret-key ');

      final PronunciationCredentials saved = container
          .read(pronunciationCredentialsProvider)
          .requireValue;

      expect(saved.apiKey, 'test-secret-key');
      expect(store.value.apiKey, saved.apiKey);
    },
  );
}
