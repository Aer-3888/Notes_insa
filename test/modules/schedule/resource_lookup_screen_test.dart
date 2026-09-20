import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notes_insa/core/module_cache.dart';
import 'package:notes_insa/core/module_cache_provider.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/schedule/ade_groups.dart';
import 'package:notes_insa/modules/schedule/ade_groups_provider.dart';
import 'package:notes_insa/modules/schedule/ade_service.dart';
import 'package:notes_insa/modules/schedule/resource_lookup_screen.dart';
import 'package:notes_insa/modules/schedule/schedule_provider.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _rows = <AdeGroup>[
  AdeGroup(id: 1, name: 'S7-INFO'),
  AdeGroup(id: 8, name: 'Amphi C', category: AdeCategory.room),
  AdeGroup(id: 9, name: 'salle 101', category: AdeCategory.room),
  AdeGroup(id: 10, name: 'Modèles Stochastiques', category: AdeCategory.module),
];

/// Placed just inside the fetch window, so the row lands near the top of the
/// timeline whatever day the suite runs on.
String get _ics {
  final day = campusNow().subtract(kScheduleLookback - const Duration(days: 1));
  final d =
      '${day.year.toString().padLeft(4, '0')}'
      '${day.month.toString().padLeft(2, '0')}'
      '${day.day.toString().padLeft(2, '0')}';
  return 'BEGIN:VCALENDAR\r\n'
      'BEGIN:VEVENT\r\n'
      'DTSTART:${d}T081500Z\r\n'
      'DTEND:${d}T101500Z\r\n'
      'SUMMARY:Algebre 3\r\n'
      'LOCATION:Amphi C (V)\r\n'
      'END:VEVENT\r\n'
      'END:VCALENDAR\r\n';
}

Future<List<Uri>> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final root = Directory.systemTemp.createTempSync('notes-insa-resource-test-');
  addTearDown(() => root.delete(recursive: true));
  final asked = <Uri>[];
  final service = AdeService(
    client: MockClient((request) async {
      asked.add(request.url);
      return http.Response(_ics, 200);
    }),
  );
  final container = ProviderContainer(
    overrides: [
      adeGroupsProvider.overrideWith((ref) async => _rows),
      adeServiceProvider.overrideWithValue(service),
      moduleCacheProvider.overrideWith((ref) async => ModuleCache(root)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: campusTheme(Brightness.light),
        home: const ResourceLookupScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return asked;
}

void main() {
  setUpAll(initCampusTime);

  testWidgets('opens on rooms, with modules a chip away', (tester) async {
    await _pump(tester);
    expect(find.text('Amphi C'), findsOneWidget);
    expect(find.text('Modèles Stochastiques'), findsNothing);
    // Student groups are a subscription, not a lookup, so they are not here.
    expect(find.text('S7-INFO'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Matières'));
    await tester.pumpAndSettle();
    expect(find.text('Modèles Stochastiques'), findsOneWidget);
    expect(find.text('Amphi C'), findsNothing);
  });

  testWidgets('search narrows the list', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), '101');
    await tester.pumpAndSettle();
    expect(find.text('salle 101'), findsOneWidget);
    expect(find.text('Amphi C'), findsNothing);
  });

  testWidgets('picking a room shows its timetable, read-only', (tester) async {
    final asked = await _pump(tester);
    await tester.tap(find.text('Amphi C'));
    await tester.pumpAndSettle();

    expect(asked.single.queryParameters['resources'], '8');
    expect(find.text('Algebre 3'), findsOneWidget);
    // Looking a room up must never change what the user is subscribed to.
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('Valider (1)'), findsNothing);
  });

  testWidgets('the lookup leaves the subscription alone', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final root = Directory.systemTemp.createTempSync(
      'notes-insa-resource-test-',
    );
    addTearDown(() => root.delete(recursive: true));
    final container = ProviderContainer(
      overrides: [
        adeGroupsProvider.overrideWith((ref) async => _rows),
        adeServiceProvider.overrideWithValue(
          AdeService(client: MockClient((_) async => http.Response(_ics, 200))),
        ),
        moduleCacheProvider.overrideWith((ref) async => ModuleCache(root)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: campusTheme(Brightness.light),
          home: const ResourceLookupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amphi C'));
    await tester.pumpAndSettle();
    expect(container.read(selectedGroupsProvider), isEmpty);
  });
}
