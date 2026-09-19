import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/grades/dashboard_screen.dart';
import 'package:notes_insa/modules/grades/grades_provider.dart';
import 'package:notes_insa/providers/averages_provider.dart';
import 'package:notes_insa/providers/coefficients_provider.dart';
import 'package:notes_insa/providers/dashboard_providers.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Semesters 1..[count], two per academic year as the portal numbers them.
String _gradesFor(int count) {
  final semesters = <String>[
    for (var n = 1; n <= count; n++)
      '''
    {
      "name": "${(n + 1) ~/ 2}STPI-SEMESTRE$n",
      "score": "${10 + (n - 1) * 2 > 19 ? 19 : 10 + (n - 1) * 2}/20",
      "details": [
        {
          "name": "UE S$n",
          "details": [
            {
              "name": "Matière S$n",
              "details": [{"name": "DS", "score": "13/20"}]
            }
          ]
        }
      ]
    }''',
  ];
  return '{"name": "DOE John", "details": [${semesters.join(',')}]}';
}

/// Set by [_pumpDashboard] before the notifier is constructed.
String _activeGrades = _gradesFor(3);

class _TestGradesNotifier extends GradesNotifier {
  _TestGradesNotifier(super.ref) {
    state = GradesState(
      jsonData: _activeGrades,
      academicYearBaseline: '2025-2026',
    );
  }
}

/// Pumps the dashboard with [semesters] semesters loaded.
Future<ProviderContainer> _pumpDashboard(
  WidgetTester tester, {
  int semesters = 3,
}) async {
  _activeGrades = _gradesFor(semesters);
  final container = ProviderContainer(
    overrides: [
      gradesProvider.overrideWith(_TestGradesNotifier.new),
      coefficientsProvider.overrideWith((ref, params) async => {}),
      averagesProvider.overrideWith((ref, params) async => []),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: campusTheme(Brightness.light),
        home: const DashboardScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

TabController _tabController(WidgetTester tester) =>
    DefaultTabController.of(tester.element(find.byType(TabBarView)));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'sharing_consent_asked': true});
  });

  testWidgets('swiping keeps each semester page and selection in sync', (
    tester,
  ) async {
    final container = await _pumpDashboard(tester);

    expect(find.text('Ue S3'), findsOneWidget);
    expect(container.read(effectiveSemesterProvider), 3);

    final recordedSemesters = <int>[];
    container.listen(effectiveSemesterProvider, (_, next) {
      if (next != null) recordedSemesters.add(next);
    });

    await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();

    debugPrint('Recorded swipe semesters: $recordedSemesters');
    expect(find.text('Ue S2'), findsOneWidget);
    expect(container.read(effectiveSemesterProvider), 2);
  });

  testWidgets('tapping semester pill animates pager and stays in sync', (
    tester,
  ) async {
    final container = await _pumpDashboard(tester);

    expect(find.text('Ue S3'), findsOneWidget);
    expect(container.read(effectiveSemesterProvider), 3);

    final recordedSemesters = <int>[];
    container.listen(effectiveSemesterProvider, (_, next) {
      if (next != null) recordedSemesters.add(next);
    });

    await tester.tap(find.text('S1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    debugPrint('Recorded semesters: $recordedSemesters');
    expect(find.text('Ue S1'), findsOneWidget);
    expect(container.read(effectiveSemesterProvider), 1);
  });

  testWidgets('the rail indicator tracks the drag instead of snapping', (
    tester,
  ) async {
    await _pumpDashboard(tester);
    final controller = _tabController(tester);
    expect(controller.index, 2);

    // Drag back towards S2 without releasing.
    final pager = find.byType(TabBarView);
    final gesture = await tester.startGesture(tester.getCenter(pager));
    // Several small moves rather than one big one: the first is swallowed by
    // the drag recogniser's touch slop.
    final step = tester.getSize(pager).width / 12;
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(Offset(step, 0));
      await tester.pump();
    }

    // Mid-travel between S3 and S2 rather than still pinned to S3.
    expect(controller.animation!.value, lessThan(2.0));
    expect(controller.animation!.value, greaterThan(1.0));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a selection made outside the screen moves the pager', (
    tester,
  ) async {
    final container = await _pumpDashboard(tester);
    expect(find.text('Ue S3'), findsOneWidget);

    container.read(selectedSemesterProvider.notifier).state = 1;
    await tester.pumpAndSettle();

    expect(find.text('Ue S1'), findsOneWidget);
    expect(_tabController(tester).index, 0);
  });

  testWidgets('two academic years keep every semester on one flat row', (
    tester,
  ) async {
    await _pumpDashboard(tester, semesters: 4);

    // Two rows of two equal columns would read as a grid, not a hierarchy.
    expect(find.text('1A'), findsNothing);
    expect(find.text('2A'), findsNothing);
    for (final label in const ['S1', 'S2', 'S3', 'S4']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('four academic years add a year row above the semesters', (
    tester,
  ) async {
    final container = await _pumpDashboard(tester, semesters: 8);

    for (final label in const ['1A', '2A', '3A', '4A']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('S7'), findsOneWidget);
    expect(find.text('S8'), findsOneWidget);
    expect(find.text('S1'), findsNothing);
    expect(container.read(effectiveSemesterProvider), 8);
  });

  testWidgets('tapping a year lands on its most recent semester', (
    tester,
  ) async {
    final container = await _pumpDashboard(tester, semesters: 8);

    await tester.tap(find.text('2A'));
    await tester.pumpAndSettle();

    expect(container.read(effectiveSemesterProvider), 4);
    expect(find.text('Ue S4'), findsOneWidget);
    expect(find.text('S3'), findsOneWidget);
    expect(find.text('S4'), findsOneWidget);
    expect(find.text('S7'), findsNothing);
  });

  testWidgets('a lone semester shows no selector at all', (tester) async {
    await _pumpDashboard(tester, semesters: 1);

    expect(find.text('S1'), findsNothing);
    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Ue S1'), findsOneWidget);
  });

  testWidgets('jumping across years never shows the years in between', (
    tester,
  ) async {
    final container = await _pumpDashboard(tester, semesters: 8);

    await tester.tap(find.text('1A'));
    // Step through the animation: the controller animates its value across
    // every tab between S8 and S1 on the way.
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
      for (final label in const ['S3', 'S4', 'S5', 'S6', 'S7', 'S8']) {
        expect(find.text(label), findsNothing, reason: 'saw $label mid-jump');
      }
    }

    await tester.pumpAndSettle();
    expect(find.text('S1'), findsOneWidget);
    expect(find.text('S2'), findsOneWidget);
    expect(container.read(effectiveSemesterProvider), 2);
  });

  testWidgets('changing year puts the pill straight on its target, both ways', (
    tester,
  ) async {
    final container = await _pumpDashboard(tester, semesters: 8);

    FontWeight? weightOf(String label) =>
        tester.widget<Text>(find.text(label)).style?.fontWeight;

    Future<void> expectPinned(String on, String off) async {
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 40));
        expect(weightOf(on), FontWeight.w700, reason: 'pill left $on mid-jump');
        expect(
          weightOf(off),
          FontWeight.w600,
          reason: 'pill hit $off mid-jump',
        );
      }
      await tester.pumpAndSettle();
    }

    // Backwards, 4A -> 2A.
    await tester.tap(find.text('2A'));
    await expectPinned('S4', 'S3');
    expect(container.read(effectiveSemesterProvider), 4);

    // Forwards, 2A -> 4A: clamping alone left this direction sliding, because
    // the value arrives at the year from below its first segment.
    await tester.tap(find.text('4A'));
    await expectPinned('S8', 'S7');
    expect(container.read(effectiveSemesterProvider), 8);
  });
}
