import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/associations/association.dart';
import 'package:notes_insa/modules/associations/association_detail_screen.dart';
import 'package:notes_insa/modules/associations/association_notification_permission.dart';
import 'package:notes_insa/modules/associations/association_service.dart';
import 'package:notes_insa/services/notification_service.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePermissions implements NotificationPermissionGateway {
  _FakePermissions(this.value);

  NotificationPermissionState value;
  var requests = 0;
  var settingsOpened = 0;

  @override
  Future<void> openSettings() async {
    settingsOpened++;
  }

  @override
  Future<NotificationPermissionState> request() async {
    requests++;
    return value;
  }

  @override
  Future<NotificationPermissionState> status() async => value;
}

Future<void> _pump(
  WidgetTester tester,
  Association association, {
  NotificationPermissionGateway? permissions,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        associationsProvider.overrideWith(
          (ref) async => <Association>[association],
        ),
        if (permissions != null)
          notificationPermissionGatewayProvider.overrideWithValue(permissions),
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

  testWidgets('shows live opportunities and expands an FAQ', (tester) async {
    final association = Association(
      id: 'ouest-insa',
      name: 'Ouest INSA',
      category: AssociationCategory.entreprise,
      recruitment: const AssociationRecruitment(
        isOpen: true,
        title: 'Candidatures ouvertes',
        description: 'Candidate avant la date indiquée.',
        url: 'https://example.test/apply',
      ),
      events: <AssociationEvent>[
        AssociationEvent(
          id: 'open-day',
          associationId: 'ouest-insa',
          title: 'Réunion de découverte',
          startsAt: campusInstant(DateTime(2027, 1, 15, 18)),
        ),
      ],
      faqs: const <AssociationFaq>[
        AssociationFaq(
          question: 'Le recrutement est-il ouvert ?',
          answer: 'Non, il est fermé pendant la formation.',
        ),
      ],
    );

    await _pump(tester, association);
    expect(find.text('Que puis-je faire ici ?'), findsOneWidget);
    expect(find.text('Candidatures ouvertes'), findsOneWidget);
    expect(find.text('Réunion de découverte'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Questions fréquentes'), 300);
    expect(find.text('Non, il est fermé pendant la formation.'), findsNothing);

    await tester.tap(find.text('Le recrutement est-il ouvert ?'));
    await tester.pumpAndSettle();

    expect(
      find.text('Non, il est fermé pendant la formation.'),
      findsOneWidget,
    );
  });

  testWidgets('asks once for reminders after the first follow', (tester) async {
    final permissions = _FakePermissions(NotificationPermissionState.denied);
    final association = Association(
      id: 'a',
      name: 'Arts',
      category: AssociationCategory.culture,
    );

    await _pump(tester, association, permissions: permissions);
    await tester.tap(find.text('Suivre'));
    await tester.pumpAndSettle();

    expect(find.text('Activer les rappels ?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Activer'),
      ),
    );
    await tester.pumpAndSettle();

    expect(permissions.requests, 1);
    expect(find.text('Les rappels sont désactivés.'), findsOneWidget);
    expect(find.text('Suivie'), findsOneWidget);
  });
}
