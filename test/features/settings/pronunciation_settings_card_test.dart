import 'dart:async';

import 'package:common_learn_english/features/player/domain/pronunciation_assessment.dart';
import 'package:common_learn_english/features/settings/data/pronunciation_credentials.dart';
import 'package:common_learn_english/features/settings/presentation/widgets/pronunciation_settings_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/src/framework.dart' show Override;

class _Store implements PronunciationCredentialStore {
  _Store(this.readFuture);

  final Future<PronunciationCredentials> readFuture;

  @override
  Future<PronunciationCredentials> read() => readFuture;

  @override
  Future<void> write(PronunciationCredentials credentials) async {}
}

void main() {
  testWidgets('shows independent Tencent credentials and official links', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          pronunciationCredentialStoreProvider.overrideWithValue(
            _Store(
              Future<PronunciationCredentials>.value(
                const PronunciationCredentials(),
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: PronunciationSettingsCard()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('跟读评测'), findsOneWidget);
    expect(find.text('AppID'), findsOneWidget);
    expect(find.text('SecretId'), findsOneWidget);
    expect(find.text('SecretKey'), findsOneWidget);
    expect(find.text('申请 API 密钥'), findsOneWidget);
    expect(find.text('开通口语评测'), findsOneWidget);
    expect(find.textContaining('不会读取翻译或 ASR 配置'), findsOneWidget);
  });

  testWidgets(
    'credential fields stay disabled until secure store load completes',
    (WidgetTester tester) async {
      final Completer<PronunciationCredentials> loading =
          Completer<PronunciationCredentials>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            pronunciationCredentialStoreProvider.overrideWithValue(
              _Store(loading.future),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: PronunciationSettingsCard()),
            ),
          ),
        ),
      );
      await tester.pump();
      final Finder fields = find.byType(TextField);
      expect(fields, findsNWidgets(3));
      for (int index = 0; index < 3; index++) {
        expect(tester.widget<TextField>(fields.at(index)).enabled, isFalse);
      }

      loading.complete(
        const PronunciationCredentials(
          appId: '1250000000',
          secretId: 'stored-id',
          secretKey: 'stored-key',
        ),
      );
      await tester.pumpAndSettle();
      for (int index = 0; index < 3; index++) {
        expect(tester.widget<TextField>(fields.at(index)).enabled, isTrue);
      }
      expect(
        tester.widget<TextField>(fields.at(0)).controller!.text,
        '1250000000',
      );
      expect(
        tester.widget<TextField>(fields.at(1)).controller!.text,
        'stored-id',
      );
      expect(
        tester.widget<TextField>(fields.at(2)).controller!.text,
        'stored-key',
      );
    },
  );
}
