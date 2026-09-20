import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/components/dashboard_header.dart';
import 'package:notes_insa/components/grades_view_menu.dart';
import 'package:notes_insa/components/grades_views.dart';
import 'package:notes_insa/components/unit_card_grid.dart';
import 'package:notes_insa/models.dart';
import 'package:notes_insa/providers/grades_view_mode_provider.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Deliberately synthetic units; no portal payload or personal grade data.
  List<TeachingUnit> curriculum() => [
    TeachingUnit('UE exemple', [
      Subject(
        'Matière exemple',
        2,
        {},
        grades: [
          GradeInstance('Épreuve A', 8, coeff: '1'),
          GradeInstance('Épreuve B', 16, coeff: '3'),
        ],
      ),
      Subject('Matière en attente', 1, {}),
    ], extractedAverage: 13),
    TeachingUnit('UE en attente', []),
  ];

  Future<void> pumpViews(
    WidgetTester tester, {
    ValueChanged<TeachingUnit>? onTap,
    List<TeachingUnit>? units,
    String? error,
    VoidCallback? onRetry,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: campusTheme(Brightness.light),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: Column(
                  children: [
                    const DashboardHeader(
                      average: 13,
                      title: 'Notes',
                      titleWidget: GradesViewMenu(),
                      subtitle: 'Département exemple',
                    ),
                    Expanded(
                      child: GradesViews(
                        mode: ref.watch(gradesViewModeProvider),
                        curriculum: units ?? curriculum(),
                        onUnitTap: onTap ?? (_) {},
                        errorMessage: error,
                        onRetry: onRetry,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(find.byType(PopupMenuButton<GradesViewMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('menu switches all views and keeps unit details accessible', (
    tester,
  ) async {
    TeachingUnit? opened;
    await pumpViews(tester, onTap: (unit) => opened = unit);
    // Synthèse is the default view.
    expect(find.byType(UnitCardGrid), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsWidgets);

    await choose(tester, 'Cartes');
    expect(find.byType(UnitCardGrid), findsOneWidget);

    await choose(tester, 'Liste');
    expect(find.text('Épreuve A : 8.00 (coeff. 1)'), findsOneWidget);
    expect(find.text('≈14.00'), findsOneWidget);
    expect(find.text('Aucune note publiée'), findsOneWidget);
    await tester.tap(find.text('Matière Exemple'));
    expect(opened?.name, 'UE exemple');

    opened = null;
    await choose(tester, 'Synthèse');
    expect(find.text('Matière Exemple'), findsNothing);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 13 / 20);
    expect(find.text('–'), findsOneWidget);
    await tester.tap(find.text('Ue Exemple'));
    expect(opened?.name, 'UE exemple');

    await choose(tester, 'Cartes');
    expect(find.byType(UnitCardGrid), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty and retry states remain available in each view', (
    tester,
  ) async {
    var retried = false;
    await pumpViews(
      tester,
      units: [],
      error: 'Connexion indisponible',
      onRetry: () => retried = true,
    );
    for (final mode in GradesViewMode.values) {
      await choose(tester, mode.label);
      expect(find.text('Notes indisponibles'), findsOneWidget);
      await tester.tap(find.text('Réessayer'));
      expect(retried, isTrue);
      retried = false;
    }
    await pumpViews(tester, units: []);
    expect(find.text('Aucune note pour ce semestre'), findsOneWidget);
  });

  for (final mode in GradesViewMode.values) {
    testWidgets('${mode.label} fits a narrow phone with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({kGradesViewModeKey: mode.name});
      await pumpViews(tester, textScale: 1.5);
      expect(find.text(mode.label), findsOneWidget);
      await tester.drag(
        find.byType(mode == GradesViewMode.cartes ? GridView : ListView),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
