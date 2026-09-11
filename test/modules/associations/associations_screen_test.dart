import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/associations/association.dart';
import 'package:notes_insa/modules/associations/association_follows.dart';
import 'package:notes_insa/modules/associations/association_service.dart';
import 'package:notes_insa/modules/associations/associations_screen.dart';
import 'package:notes_insa/modules/associations/associations_today_card.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Association _asso({
  required String id,
  required String name,
  AssociationCategory category = AssociationCategory.culture,
  String? summary,
  String? buildingCode,
  List<AssociationEvent> events = const <AssociationEvent>[],
}) => Association(
  id: id,
  name: name,
  category: category,
  summary: summary,
  buildingCode: buildingCode,
  events: events,
);

AssociationEvent _event({
  required String id,
  required String associationId,
  required String title,
  required DateTime startsAt,
}) => AssociationEvent(
  id: id,
  associationId: associationId,
  title: title,
  startsAt: startsAt,
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  List<Association> directory = const <Association>[],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [associationsProvider.overrideWith((ref) async => directory)],
      child: MaterialApp(theme: campusTheme(Brightness.light), home: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initCampusTime);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('the directory', () {
    testWidgets('groups associations under their category', (tester) async {
      await _pump(
        tester,
        const AssociationsScreen(),
        directory: <Association>[
          _asso(id: 'a', name: 'Arts', category: AssociationCategory.culture),
          _asso(id: 'b', name: 'Basket', category: AssociationCategory.sport),
        ],
      );
      expect(find.text('Culture'), findsOneWidget);
      expect(find.text('Sport'), findsOneWidget);
      expect(find.text('Arts'), findsOneWidget);
      expect(find.text('Basket'), findsOneWidget);
    });

    testWidgets('an empty directory says it is coming, not that it broke', (
      tester,
    ) async {
      await _pump(tester, const AssociationsScreen());
      expect(find.text('Bientôt'), findsOneWidget);
    });

    testWidgets('search filters on name and reports finding nothing', (
      tester,
    ) async {
      await _pump(
        tester,
        const AssociationsScreen(),
        directory: <Association>[
          _asso(id: 'a', name: 'Arts plastiques'),
          _asso(id: 'b', name: 'Robotique'),
        ],
      );
      await tester.enterText(find.byType(TextField), 'robot');
      await tester.pumpAndSettle();
      expect(find.text('Robotique'), findsOneWidget);
      expect(find.text('Arts plastiques'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Aucun résultat'), findsOneWidget);
    });

    testWidgets('search ignores the accents nobody types', (tester) async {
      await _pump(
        tester,
        const AssociationsScreen(),
        directory: <Association>[_asso(id: 'a', name: 'Théâtre')],
      );
      await tester.enterText(find.byType(TextField), 'theatre');
      await tester.pumpAndSettle();
      expect(find.text('Théâtre'), findsOneWidget);
    });

    testWidgets('following lifts an association into its own section', (
      tester,
    ) async {
      await _pump(
        tester,
        const AssociationsScreen(),
        directory: <Association>[
          _asso(id: 'a', name: 'Arts', category: AssociationCategory.culture),
        ],
      );
      expect(find.text('Suivies'), findsNothing);

      await tester.tap(find.byIcon(Icons.notifications_none));
      await tester.pumpAndSettle();

      expect(find.text('Suivies'), findsOneWidget);
      expect(find.text('Culture'), findsNothing);
    });
  });

  group('the today card', () {
    testWidgets('stays away when nothing is followed', (tester) async {
      await _pump(
        tester,
        const Scaffold(body: AssociationsTodayCard()),
        directory: <Association>[
          _asso(
            id: 'a',
            name: 'Arts',
            events: <AssociationEvent>[
              _event(
                id: 'e1',
                associationId: 'a',
                title: 'Vernissage',
                startsAt: campusNow().add(const Duration(days: 3)),
              ),
            ],
          ),
        ],
      );
      expect(find.byType(Card), findsNothing);
      expect(find.text('Vernissage'), findsNothing);
    });

    testWidgets('shows what a followed association has coming', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AssociationFollowsNotifier.key: <String>['a'],
      });
      await _pump(
        tester,
        const Scaffold(body: AssociationsTodayCard()),
        directory: <Association>[
          _asso(
            id: 'a',
            name: 'Arts',
            events: <AssociationEvent>[
              _event(
                id: 'e1',
                associationId: 'a',
                title: 'Vernissage',
                startsAt: campusNow().add(const Duration(days: 3)),
              ),
            ],
          ),
        ],
      );
      await tester.pumpAndSettle();
      expect(find.text('Chez tes assos'), findsOneWidget);
      expect(find.text('Vernissage'), findsOneWidget);
    });

    testWidgets('an event already over is not still coming up', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AssociationFollowsNotifier.key: <String>['a'],
      });
      await _pump(
        tester,
        const Scaffold(body: AssociationsTodayCard()),
        directory: <Association>[
          _asso(
            id: 'a',
            name: 'Arts',
            events: <AssociationEvent>[
              _event(
                id: 'e1',
                associationId: 'a',
                title: 'Vernissage',
                startsAt: campusNow().subtract(const Duration(days: 3)),
              ),
            ],
          ),
        ],
      );
      await tester.pumpAndSettle();
      expect(find.text('Vernissage'), findsNothing);
    });
  });

  testWidgets('meets the tap target and contrast guidelines', (tester) async {
    await _pump(
      tester,
      const AssociationsScreen(),
      directory: <Association>[
        _asso(
          id: 'a',
          name: 'Arts plastiques',
          summary: 'Le club d’arts du campus',
        ),
        _asso(id: 'b', name: 'Basket', category: AssociationCategory.sport),
      ],
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });

  testWidgets('the directory renders in dark mode', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          associationsProvider.overrideWith(
            (ref) async => <Association>[_asso(id: 'a', name: 'Arts')],
          ),
        ],
        child: MaterialApp(
          theme: campusTheme(Brightness.dark),
          home: const AssociationsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });

  group('the agenda', () {
    List<Association> withEvents() => <Association>[
      _asso(
        id: 'a',
        name: 'Arts',
        events: <AssociationEvent>[
          _event(
            id: 'e1',
            associationId: 'a',
            title: 'Vernissage',
            startsAt: campusNow().add(const Duration(days: 2)),
          ),
        ],
      ),
      _asso(
        id: 'b',
        name: 'Basket',
        category: AssociationCategory.sport,
        events: <AssociationEvent>[
          _event(
            id: 'e2',
            associationId: 'b',
            title: 'Tournoi',
            startsAt: campusNow().add(const Duration(days: 4)),
          ),
        ],
      ),
    ];

    testWidgets('is absent while nothing is dated', (tester) async {
      await _pump(
        tester,
        const AssociationsScreen(),
        directory: <Association>[_asso(id: 'a', name: 'Arts')],
      );
      expect(find.text('Agenda'), findsNothing);
      expect(find.byType(TabBar), findsNothing);
    });

    testWidgets('appears as a tab once there is something on', (tester) async {
      await _pump(tester, const AssociationsScreen(), directory: withEvents());
      expect(find.text('Agenda'), findsOneWidget);

      await tester.tap(find.text('Agenda'));
      await tester.pumpAndSettle();
      expect(find.text('Vernissage'), findsOneWidget);
      expect(find.text('Tournoi'), findsOneWidget);
    });

    testWidgets('lists every asso, not only the followed ones', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AssociationFollowsNotifier.key: <String>['a'],
      });
      await _pump(tester, const AssociationsScreen(), directory: withEvents());
      await tester.tap(find.text('Agenda'));
      await tester.pumpAndSettle();
      expect(find.text('Tournoi'), findsOneWidget);
    });

    testWidgets('the filter narrows it to what is followed', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AssociationFollowsNotifier.key: <String>['a'],
      });
      await _pump(tester, const AssociationsScreen(), directory: withEvents());
      await tester.tap(find.text('Agenda'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilterChip, 'Mes assos'));
      await tester.pumpAndSettle();

      expect(find.text('Vernissage'), findsOneWidget);
      expect(find.text('Tournoi'), findsNothing);
    });

    testWidgets('the filter is hidden when nothing is followed', (
      tester,
    ) async {
      await _pump(tester, const AssociationsScreen(), directory: withEvents());
      await tester.tap(find.text('Agenda'));
      await tester.pumpAndSettle();
      expect(find.byType(FilterChip), findsNothing);
    });
  });

  group('initials stand in for a missing logo', () {
    test('two words give two letters', () {
      expect(associationInitials('Arts Plastiques'), 'AP');
      expect(associationInitials('Club de Robotique'), 'CD');
    });

    test('a hyphen separates words', () {
      expect(associationInitials('Franco-Allemand'), 'FA');
    });

    test('one word gives one letter', () {
      expect(associationInitials('Ktulu'), 'K');
    });

    test('a name with no letters still renders something', () {
      expect(associationInitials('42'), '?');
      expect(associationInitials(''), '?');
    });
  });
}
