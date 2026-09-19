import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/associations/association.dart';
import 'package:notes_insa/modules/associations/association_detail_screen.dart';
import 'package:notes_insa/modules/associations/association_service.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester, Association association) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        associationsProvider.overrideWith(
          (ref) async => <Association>[association],
        ),
      ],
      child: MaterialApp(
        theme: campusTheme(Brightness.light),
        home: AssociationDetailScreen(associationId: association.id),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initCampusTime);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('opens a mandate team without using member photos', (
    tester,
  ) async {
    final association = Association(
      id: 'ouest-insa',
      name: 'Ouest INSA',
      category: AssociationCategory.entreprise,
      organigram: const AssociationOrganigram(
        title: 'Mandat 2026',
        sections: <AssociationOrganigramSection>[
          AssociationOrganigramSection(
            title: 'Bureau',
            members: <AssociationOrganigramMember>[
              AssociationOrganigramMember(role: 'Président·e', name: 'Maxime'),
            ],
          ),
          AssociationOrganigramSection(
            title: 'Conseil d’administration',
            members: <AssociationOrganigramMember>[
              AssociationOrganigramMember(
                role: 'Responsable DSI',
                name: 'Mathys',
              ),
            ],
          ),
        ],
      ),
    );

    await _pump(tester, association);

    expect(find.byKey(const Key('association-organigram')), findsOneWidget);
    expect(find.text('Mandat 2026 · 2 membres'), findsOneWidget);

    await tester.tap(find.byKey(const Key('association-organigram')));
    await tester.pumpAndSettle();

    expect(find.text('Bureau'), findsOneWidget);
    expect(find.text('Président·e'), findsOneWidget);
    expect(find.text('Maxime'), findsOneWidget);
    expect(find.text('Conseil d’administration'), findsOneWidget);
    expect(find.text('Mathys'), findsOneWidget);
  });
}
