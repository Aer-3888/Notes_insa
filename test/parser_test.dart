import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/data.dart';

void main() {
  const gradesJson = '''
  {
    "name": "DOE John (INFO)",
    "details": [
      {
        "name": "SEMESTRE 5",
        "details": [
          {
            "name": "UE1",
            "details": [
              {"name": "Math", "details": [{"name": "DS1", "score": "10/20"}]},
              {"name": "Phys", "details": [{"name": "DS1", "score": "16/20"}]}
            ]
          }
        ]
      }
    ]
  }
  ''';

  test('applies subject and UE coefficients from the coefficient map', () {
    final units = JsonCurriculumParser.parseSemester(
      gradesJson,
      5,
      coefficients: {'UE1|Math': 2.0, 'UE1|Phys': 1.0, 'UE1|': 3.0},
    );

    expect(units.length, 1);
    final ue = units.first;
    expect(ue.name, 'UE1');
    // UE-level coefficient picked up from the "UE1|" sentinel key.
    expect(ue.coeff, 3.0);
    // UE average is subject-coefficient-weighted: (10*2 + 16*1) / 3 = 12.
    expect(ue.average, closeTo(12, 1e-9));
  });

  test('falls back to coeff 1.0 when coefficients are absent', () {
    final units = JsonCurriculumParser.parseSemester(gradesJson, 5);
    expect(units.single.coeff, 1.0);
    // Unweighted UE average: (10 + 16) / 2 = 13.
    expect(units.single.average, closeTo(13, 1e-9));
  });

  test('round-trips through jsonEncode/Decode without error', () {
    // Sanity: the fixture is valid JSON.
    expect(() => jsonDecode(gradesJson), returnsNormally);
  });
}
