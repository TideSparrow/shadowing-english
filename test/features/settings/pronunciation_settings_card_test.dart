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
  testWidgets('shows a single Ark API key and official links', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final List<String> openedLinks = <String>[];
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
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PronunciationSettingsCard(
                openLink: (BuildContext context, String url) async {
                  openedLinks.add(url);
                  return true;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('跟读指导'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('API Key'), findsOneWidget);
    await tester.tap(find.text('申请 API Key'));
    expect(
      openedLinks.single,
      'https://ark.volcengine.com/region:cn-beijing/apiKey',
    );
    expect(find.text('火山方舟计费'), findsOneWidget);
    final Finder activate = find.text('开通模型');
    await tester.ensureVisible(activate);
    await tester.tap(activate);
    expect(
      openedLinks.last,
      'https://ark.volcengine.com/region:cn-beijing/openManagement',
    );
    final Finder help = find.text('帮助文档');
    await tester.ensureVisible(help);
    await tester.pumpAndSettle();
    await tester.tap(help);
    await tester.pumpAndSettle();
    expect(find.text('Shadowing English 跟读指导帮助'), findsOneWidget);
    expect(find.widgetWithText(AlertDialog, '开通模型'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
      expect(fields, findsOneWidget);
      expect(tester.widget<TextField>(fields).enabled, isFalse);

      loading.complete(const PronunciationCredentials(apiKey: 'stored-key'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(fields).enabled, isTrue);
      expect(tester.widget<TextField>(fields).obscureText, isTrue);
      expect(tester.widget<TextField>(fields).controller!.text, 'stored-key');
    },
  );
}
