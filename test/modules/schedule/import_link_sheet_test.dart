import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/import_link_sheet.dart';

const _link = 'https://ade-planning.insa-rennes.fr/view/1214,133,136/';

/// Opens the sheet from a real route. The returned future completes when the
/// dialog is dismissed, so a test can interact first and await after.
Future<Completer<List<int>?>> _open(
  WidgetTester tester, {
  String? clipboard,
}) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => call.method == 'Clipboard.getData' && clipboard != null
        ? <String, dynamic>{'text': clipboard}
        : null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );

  final done = Completer<List<int>?>();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                done.complete(await showImportLinkSheet(context)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return done;
}

void main() {
  testWidgets('a link already on the clipboard is filled in', (tester) async {
    await _open(tester, clipboard: _link);
    expect(find.widgetWithText(TextField, _link), findsOneWidget);
  });

  testWidgets('an unrelated clipboard is left out of the field', (
    tester,
  ) async {
    await _open(tester, clipboard: 'bonjour');
    expect(find.widgetWithText(TextField, 'bonjour'), findsNothing);
  });

  testWidgets('an empty clipboard is no obstacle', (tester) async {
    await _open(tester);
    expect(find.text('Coller un lien ADE'), findsOneWidget);
  });

  testWidgets('importing returns the ids in the link', (tester) async {
    final done = await _open(tester, clipboard: _link);
    await tester.tap(find.widgetWithText(FilledButton, 'Importer'));
    await tester.pumpAndSettle();
    expect(await done.future, <int>[1214, 133, 136]);
  });

  testWidgets('cancelling returns nothing', (tester) async {
    final done = await _open(tester, clipboard: _link);
    await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
    await tester.pumpAndSettle();
    expect(await done.future, isNull);
  });

  testWidgets('a link with no ids says so instead of failing silently', (
    tester,
  ) async {
    final done = await _open(tester);
    await tester.enterText(find.byType(TextField), 'https://example.com/');
    await tester.tap(find.widgetWithText(FilledButton, 'Importer'));
    await tester.pumpAndSettle();
    expect(await done.future, isNull);
    expect(find.text('Aucun groupe trouvé dans ce lien.'), findsOneWidget);
  });
}
