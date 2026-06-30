import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/data.dart';

void main() {
  Map<String, dynamic> decode(String s) =>
      JsonCurriculumParser.tryDecode(s) ?? (throw 'invalid fixture JSON');

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
      decode(gradesJson),
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
    final units = JsonCurriculumParser.parseSemester(decode(gradesJson), 5);
    expect(units.single.coeff, 1.0);
    // Unweighted UE average: (10 + 16) / 2 = 13.
    expect(units.single.average, closeTo(13, 1e-9));
  });

  test('prefers extracted subject and UE averages over local estimates', () {
    const json = '''
    {
      "name": "DOE John (INFO)",
      "details": [
        {
          "name": "SEMESTRE 5",
          "details": [
            {
              "name": "UE1",
              "score": "14/20",
              "details": [
                {
                  "name": "Math",
                  "score": "13/20",
                  "details": [{"name": "DS1", "score": "10/20"}]
                }
              ]
            }
          ]
        }
      ]
    }
    ''';

    final unit = JsonCurriculumParser.parseSemester(decode(json), 5).single;
    final subject = unit.subjects.single;

    expect(subject.average, 13);
    expect(subject.isAverageEstimated, isFalse);
    expect(unit.average, 14);
    expect(unit.isAverageEstimated, isFalse);
  });

  test('uses grade coefficients for subject fallback estimates', () {
    const json = '''
    {
      "name": "DOE John (INFO)",
      "details": [
        {
          "name": "SEMESTRE 5",
          "details": [
            {
              "name": "UE1",
              "details": [
                {
                  "name": "Math",
                  "details": [
                    {"name": "DS1", "score": "10/20", "coeff": "2"},
                    {"name": "DS2", "score": "16/20", "coeff": "1"}
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
    ''';

    final subject = JsonCurriculumParser.parseSemester(
      decode(json),
      5,
    ).single.subjects.single;

    expect(subject.average, closeTo(12, 1e-9));
    expect(subject.isAverageEstimated, isTrue);
  });

  test(
    'getSemesterAverage reads the pre-computed score from the semester node',
    () {
      const json = '''
    {
      "name": "DOE John (INFO)",
      "details": [
        {"name": "SEMESTRE 5", "score": "13.25/20", "details": []}
      ]
    }
    ''';
      expect(
        JsonCurriculumParser.getSemesterAverage(decode(json), 5),
        closeTo(13.25, 1e-9),
      );
    },
  );

  test(
    'getSemesterAverage returns null when the semester node has no score',
    () {
      expect(
        JsonCurriculumParser.getSemesterAverage(decode(gradesJson), 5),
        isNull,
      );
    },
  );

  test('round-trips through jsonEncode/Decode without error', () {
    // Sanity: the fixture is valid JSON.
    expect(() => jsonDecode(gradesJson), returnsNormally);
  });

  test('extracts the UE validation status, falling back to "En cours"', () {
    const json = '''
    {
      "name": "DOE John (INFO)",
      "details": [
        {
          "name": "SEMESTRE 5",
          "details": [
            {
              "name": "UE_VAL",
              "score": ["14/20", "VAL"],
              "details": [
                {"name": "Math", "details": [{"name": "DS1", "score": ["14/20"]}]}
              ]
            },
            {
              "name": "UE_COMP",
              "score": ["8.35/20", "VALCOMP"],
              "details": [
                {"name": "Phys", "details": [{"name": "DS1", "score": ["8.35/20"]}]}
              ]
            },
            {
              "name": "UE_STATUS_ONLY",
              "score": ["VAL"],
              "details": [
                {"name": "Stage", "score": ["VAL"], "details": null}
              ]
            },
            {
              "name": "UE_PENDING",
              "score": ["11/20"],
              "details": [
                {"name": "Chimie", "details": [{"name": "DS1", "score": ["11/20"]}]}
              ]
            }
          ]
        }
      ]
    }
    ''';

    final units = JsonCurriculumParser.parseSemester(decode(json), 5);
    final byName = {for (final u in units) u.name: u};

    expect(byName['UE_VAL']!.statusLabel, 'VAL');
    expect(byName['UE_COMP']!.statusLabel, 'VALCOMP');
    // Status can be the lone element of the score list (no numeric grade).
    expect(byName['UE_STATUS_ONLY']!.statusLabel, 'VAL');
    // No status published yet, so the unit is in progress.
    expect(byName['UE_PENDING']!.extractedStatus, isNull);
    expect(byName['UE_PENDING']!.statusLabel, 'En cours');

    // EC (subject) level: status is extracted per subject, null when absent.
    expect(byName['UE_STATUS_ONLY']!.subjects.single.extractedStatus, 'VAL');
    expect(byName['UE_VAL']!.subjects.single.extractedStatus, isNull);
  });

  // STPI first-cycle semesters wrap UEs in an extra "FILIERE" level (and S3/S4
  // add a further scientific sub-grouping). The parser must flatten those so the
  // real UEs disperse instead of collapsing into a single unit.
  test('flattens the STPI FILIERE wrapper into individual UEs', () {
    const json = '''
    {
      "name": "INGENIEUR STPI1",
      "details": [
        {
          "name": "1STPI-SEMESTRE1",
          "score": ["13.818/20", "VAL"],
          "details": [
            {
              "name": "1STPI-SEMESTRE1- FILIERE CLASSIQUE ",
              "score": ["13.818/20", "VAL"],
              "details": [
                {
                  "name": "SCIENCES FONDAMENTALES S1",
                  "score": ["12.5/20", "VAL"],
                  "details": [
                    {
                      "name": "Algebre 1",
                      "score": ["12.5/20", "VAL"],
                      "details": [
                        {"name": "N1 ALGEBRE 1", "score": ["14/20"], "details": null},
                        {"name": "N2 ALGEBRE 1", "score": ["11/20"], "details": null}
                      ]
                    }
                  ]
                },
                {
                  "name": "ORIENTATION ET TRANSITION",
                  "score": ["13.825/20", "VAL"],
                  "details": [
                    {"name": "PIX", "score": ["Aucun resultat"], "details": null},
                    {
                      "name": "TSE 1",
                      "score": ["13.825/20", "VAL"],
                      "details": [
                        {"name": "TSE 1", "score": ["12/20"], "details": null}
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
    ''';

    final units = JsonCurriculumParser.parseSemester(decode(json), 1);

    // The lone FILIERE node must NOT become the only UE; its children disperse.
    expect(units.map((u) => u.name), [
      'SCIENCES FONDAMENTALES S1',
      'ORIENTATION ET TRANSITION',
    ]);

    final sciences = units.first;
    expect(sciences.average, closeTo(12.5, 1e-9)); // official UE average
    final algebre = sciences.subjects.single;
    expect(algebre.name, 'Algebre 1');
    expect(algebre.grades.length, 2);
    expect(algebre.average, closeTo(12.5, 1e-9)); // official subject average

    // A gradeless subject (status only) is kept, with no average.
    final orientation = units[1];
    final pix = orientation.subjects.firstWhere((s) => s.name == 'PIX');
    expect(pix.grades, isEmpty);
    expect(pix.average, isNull);
    final tse = orientation.subjects.firstWhere((s) => s.name == 'TSE 1');
    expect(tse.grades.single.value, 12);
  });

  test('flattens the deeper STPI scientific sub-grouping (S3/S4 shape)', () {
    const json = '''
    {
      "name": "INGENIEUR STPI2",
      "details": [
        {
          "name": "2STPI-SEMESTRE3",
          "details": [
            {
              "name": "2STPI-SEMESTRE3- FILIERE CLASSIQUE",
              "details": [
                {
                  "name": "ENSEIGNEMENTS SCIENTIFIQUES S3",
                  "details": [
                    {
                      "name": "SCIENCES EXPERIMENTALES S3",
                      "details": [
                        {
                          "name": "Chimie 3",
                          "details": [
                            {"name": "DS1", "score": ["12/20"], "details": null}
                          ]
                        }
                      ]
                    },
                    {
                      "name": "SCIENCES FONDAMENTALES S3",
                      "details": [
                        {
                          "name": "Algebre 3",
                          "details": [
                            {"name": "DS1", "score": ["14/20"], "details": null}
                          ]
                        }
                      ]
                    }
                  ]
                },
                {
                  "name": "ENSEIGNEMENTS NON SCIENTIFIQUES S3",
                  "details": [
                    {
                      "name": "Anglais 3",
                      "details": [
                        {"name": "DS", "score": ["18/20"], "details": null}
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
    ''';

    final units = JsonCurriculumParser.parseSemester(decode(json), 3);

    // Both the FILIERE wrapper and the inner ENSEIGNEMENTS SCIENTIFIQUES grouping
    // are flattened; the three real UEs land side by side.
    expect(units.map((u) => u.name), [
      'SCIENCES EXPERIMENTALES S3',
      'SCIENCES FONDAMENTALES S3',
      'ENSEIGNEMENTS NON SCIENTIFIQUES S3',
    ]);
    expect(units.every((u) => u.subjects.isNotEmpty), isTrue);
    expect(units.first.subjects.single.grades.single.value, 12);
  });
}
