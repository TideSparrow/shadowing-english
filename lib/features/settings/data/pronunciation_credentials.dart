import 'dart:convert';

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

  static const String _credentialsKey = 'pronunciation.tencent.credentials.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<PronunciationCredentials> read() async {
    if (kIsWeb) return const PronunciationCredentials();
    final String? raw = await _storage.read(key: _credentialsKey);
    return _decodeCredentials(raw);
  }

  @override
  Future<void> write(PronunciationCredentials credentials) async {
    if (kIsWeb) throw StateError('系统安全存储在此平台不可用。');
    await _storage.write(
      key: _credentialsKey,
      value: _encodeCredentials(credentials),
    );
  }
}

/// macOS uses the same local preferences as translation / subtitle settings.
/// Never probe or migrate the old keychain item: even a read may show a system
/// password dialog. Other platforms keep their existing secure storage.
class LocalPronunciationCredentialStore
    implements PronunciationCredentialStore {
  static const String _credentialsKey = 'pronunciation.tencent.credentials.v1';

  @override
  Future<PronunciationCredentials> read() async {
    if (!Hive.isBoxOpen('prefs')) return const PronunciationCredentials();
    return _decodeCredentials(Hive.box<String>('prefs').get(_credentialsKey));
  }

  @override
  Future<void> write(PronunciationCredentials credentials) async {
    if (!Hive.isBoxOpen('prefs')) throw StateError('本地设置尚未初始化。');
    final Box<String> box = Hive.box<String>('prefs');
    final String? value = _encodeCredentials(credentials);
    if (value == null) {
      await box.delete(_credentialsKey);
    } else {
      await box.put(_credentialsKey, value);
    }
    await box.flush();
  }
}

PronunciationCredentials _decodeCredentials(String? raw) {
  if (raw == null || raw.isEmpty) return const PronunciationCredentials();
  final dynamic decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Saved credentials are invalid.');
  }
  return PronunciationCredentials(
    appId: decoded['appId'] is String ? decoded['appId'] as String : '',
    secretId: decoded['secretId'] is String
        ? decoded['secretId'] as String
        : '',
    secretKey: decoded['secretKey'] is String
        ? decoded['secretKey'] as String
        : '',
  );
}

String? _encodeCredentials(PronunciationCredentials credentials) {
  final Map<String, String> values = <String, String>{
    'appId': credentials.appId.trim(),
    'secretId': credentials.secretId.trim(),
    'secretKey': credentials.secretKey.trim(),
  };
  return values.values.every((String value) => value.isEmpty)
      ? null
      : jsonEncode(values);
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

  @override
  Future<PronunciationCredentials> build() {
    return ref.read(pronunciationCredentialStoreProvider).read();
  }

  Future<void> saveCredentials({
    String? appId,
    String? secretId,
    String? secretKey,
  }) async {
    final PronunciationCredentials previous =
        state.value ?? const PronunciationCredentials();
    final PronunciationCredentials next = PronunciationCredentials(
      appId: (appId ?? previous.appId).trim(),
      secretId: (secretId ?? previous.secretId).trim(),
      secretKey: (secretKey ?? previous.secretKey).trim(),
    );
    final Future<void> write = _writeQueue.then(
      (_) => ref.read(pronunciationCredentialStoreProvider).write(next),
    );
    _writeQueue = write.catchError((Object _) {});
    await write;
    state = AsyncData<PronunciationCredentials>(next);
  }
}
