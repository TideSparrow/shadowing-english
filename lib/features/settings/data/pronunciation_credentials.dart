import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce/hive.dart';

import '../../player/domain/pronunciation_assessment.dart';

abstract interface class PronunciationCredentialStore {
  Future<PronunciationCredentials> read();
  Future<void> write(PronunciationCredentials credentials);
}

class SecurePronunciationCredentialStore
    implements PronunciationCredentialStore {
  SecurePronunciationCredentialStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  static const String _credentialsKey = 'pronunciation.doubao.apiKey.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<PronunciationCredentials> read() async {
    if (kIsWeb) return const PronunciationCredentials();
    final String? raw = await _storage.read(key: _credentialsKey);
    return PronunciationCredentials(apiKey: raw ?? '');
  }

  @override
  Future<void> write(PronunciationCredentials credentials) async {
    if (kIsWeb) throw StateError('系统安全存储在此平台不可用。');
    if (credentials.isComplete) {
      await _storage.write(
        key: _credentialsKey,
        value: credentials.apiKey.trim(),
      );
    } else {
      await _storage.delete(key: _credentialsKey);
    }
  }
}

/// macOS uses the same local preferences as translation / subtitle settings.
/// Never probe or migrate the old keychain item: even a read may show a system
/// password dialog. Other platforms keep their existing secure storage.
class LocalPronunciationCredentialStore
    implements PronunciationCredentialStore {
  static const String _credentialsKey = 'pronunciation.doubao.apiKey.v1';

  @override
  Future<PronunciationCredentials> read() async {
    if (!Hive.isBoxOpen('prefs')) return const PronunciationCredentials();
    return PronunciationCredentials(
      apiKey: Hive.box<String>('prefs').get(_credentialsKey) ?? '',
    );
  }

  @override
  Future<void> write(PronunciationCredentials credentials) async {
    if (!Hive.isBoxOpen('prefs')) throw StateError('本地设置尚未初始化。');
    final Box<String> box = Hive.box<String>('prefs');
    final String value = credentials.apiKey.trim();
    if (value.isEmpty) {
      await box.delete(_credentialsKey);
    } else {
      await box.put(_credentialsKey, value);
    }
    await box.flush();
  }
}

final Provider<PronunciationCredentialStore>
pronunciationCredentialStoreProvider = Provider<PronunciationCredentialStore>(
  (Ref ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
      ? LocalPronunciationCredentialStore()
      : SecurePronunciationCredentialStore(),
);

final AsyncNotifierProvider<
  PronunciationCredentialsNotifier,
  PronunciationCredentials
>
pronunciationCredentialsProvider =
    AsyncNotifierProvider<
      PronunciationCredentialsNotifier,
      PronunciationCredentials
    >(PronunciationCredentialsNotifier.new);

class PronunciationCredentialsNotifier
    extends AsyncNotifier<PronunciationCredentials> {
  Future<void> _writeQueue = Future<void>.value();
  Future<void>? _latestWrite;

  Future<void>? get pendingSave => _latestWrite;

  @override
  Future<PronunciationCredentials> build() {
    return ref.read(pronunciationCredentialStoreProvider).read();
  }

  Future<void> saveCredentials({required String apiKey}) async {
    final PronunciationCredentials next = PronunciationCredentials(
      apiKey: apiKey.trim(),
    );
    final PronunciationCredentialStore store = ref.read(
      pronunciationCredentialStoreProvider,
    );
    final Future<void> write = _writeQueue.then((_) async {
      await store.write(next);
      state = AsyncData<PronunciationCredentials>(next);
    });
    _latestWrite = write;
    _writeQueue = write.catchError((Object _) {});
    await write;
  }
}
