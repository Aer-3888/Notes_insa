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

const _grades = '''
{
  "name": "DOE John",
  "details": [
    {
      "name": "1STPI-SEMESTRE1",
      "score": "10/20",
      "details": [
        {
          "name": "UE S1",
          "details": [
            {
              "name": "Matière S1",
              "details": [{"name": "DS", "score": "10/20"}]
            }
          ]
        }
      ]
    },
    {
      "name": "1STPI-SEMESTRE2",
      "score": "12/20",
      "details": [
        {
          "name": "UE S2",
          "details": [
            {
              "name": "Matière S2",
              "details": [{"name": "DS", "score": "12/20"}]
            }
          ]
        }
      ]
    }
  ]
}
''';

class _TestGradesNotifier extends GradesNotifier {
  _TestGradesNotifier(super.ref) {
    state = const GradesState(
      jsonData: _grades,
      academicYearBaseline: '2025-2026',
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'sharing_consent_asked': true});
  });

  testWidgets('swiping keeps each semester page and selection in sync', (
    tester,
  ) async {
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

    expect(find.text('Ue S2'), findsOneWidget);
    expect(container.read(effectiveSemesterProvider), 2);

    await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('Ue S1'), findsOneWidget);
    expect(container.read(effectiveSemesterProvider), 1);
  });
}
