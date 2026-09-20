import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/ade_groups.dart';
import 'package:notes_insa/modules/schedule/ade_tree.dart';

/// Asserted against the bundled asset rather than a hand-built fixture: the
/// shapes these helpers have to survive (five levels deep, duplicate names,
/// electives in sibling branches) are properties of the real ADE tree, and a
/// fixture that smooths them over would prove nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<AdeGroup> students;

  setUpAll(() async {
    students = AdeGroups.ofCategory(
      await AdeGroups.loadBundled(),
      AdeCategory.student,
    );
  });

  group('depthOf', () {
    test('a department is depth 0, a leaf four levels down is depth 3', () {
      expect(AdeTree.depthOf(students, 1108), 0); // INFO
      expect(AdeTree.depthOf(students, 1214), 1); // S7-INFO
      expect(AdeTree.depthOf(students, 133), 2); // S7-INFO-G1
      expect(AdeTree.depthOf(students, 136), 3); // S7-INFO-G1-1
    });

    test('STPI reaches depth 5, the deepest the tree goes', () {
      expect(AdeTree.depthOf(students, 207), 5); // S1 - Grp TP A2-1
    });

    test('an unknown id is -1 rather than throwing', () {
      expect(AdeTree.depthOf(students, 999999), -1);
    });
  });

  group('descendantCount', () {
    test('a leaf has none', () {
      expect(AdeTree.descendantCount(students, 899), 0); // S7-INFO-ROBO
    });

    test('a promo counts every group under it, not just its children', () {
      // S7-INFO: G1 + G1-1 + G1-2 + G2 + G2-1 + G2-2 + OPTION + 4 options
      // + OUVERTURE + 5 ouvertures + créativité + projet-langues.
      expect(AdeTree.descendantCount(students, 1214), 19);
    });

    test('a department counts its whole subtree across every year', () {
      expect(AdeTree.descendantCount(students, 1108), greaterThan(60)); // INFO
    });
  });

  group('semesterNodeFor', () {
    test('resolves the depth-1 ancestor from a deep leaf', () {
      expect(AdeTree.semesterNodeFor(students, 136)?.id, 1214); // S7-INFO
      expect(AdeTree.semesterNodeFor(students, 207)?.id, 4); // S1-STPI
    });

    test('a semester resolves to itself', () {
      expect(AdeTree.semesterNodeFor(students, 1214)?.id, 1214);
    });

    test('a department has no semester above it', () {
      expect(AdeTree.semesterNodeFor(students, 1108), isNull);
    });
  });

  group('electivesFor', () {
    test('offers the S7-INFO branches that are not on the base path', () {
      final names = AdeTree.electivesFor(
        students,
        136,
      ).map((g) => g.name).toList();
      expect(names, contains('S7-INFO-OPTION'));
      expect(names, contains('S7-INFO-OUVERTURE'));
      expect(names, contains('S7-INFO-projet-langues'));
      expect(names, contains('S7-INFO-G2'));
      // The base's own branch is already covered by the base pick.
      expect(names, isNot(contains('S7-INFO-G1')));
    });

    test('S9-INFO offers TP alongside TD, which is why step 4 exists', () {
      final names = AdeTree.electivesFor(
        students,
        29, // S9-INFO-TD-1
      ).map((g) => g.name).toList();
      expect(names, contains('S9-INFO-TP'));
      expect(names, isNot(contains('S9-INFO-TD')));
    });

    test('a department base yields nothing rather than throwing', () {
      expect(AdeTree.electivesFor(students, 1108), isEmpty);
    });
  });

  group('groupingNodeFor', () {
    test('a deep group lands under its semester', () {
      expect(AdeTree.groupingNodeFor(students, 136)?.name, 'S7-INFO');
      expect(AdeTree.groupingNodeFor(students, 199)?.name, 'S7-INFO');
      expect(AdeTree.groupingNodeFor(students, 207)?.name, 'S1-STPI');
    });

    test('a cross-cutting branch lands under its pool, not itself', () {
      final lv2 = students.firstWhere((g) => g.name == 'LV2- LV3');
      expect(AdeTree.groupingNodeFor(students, lv2.id)?.name, 'HUMA');
    });

    test('an unknown id has no heading', () {
      expect(AdeTree.groupingNodeFor(students, 999999), isNull);
    });
  });

  group('pathLabel', () {
    test('names every ancestor so duplicate rows can be told apart', () {
      expect(
        AdeTree.pathLabel(students, 207),
        'STPI › S1-STPI › S1-STPI-FILIERE CLASSIQUE › S1-STPI-A › 2 GROUPES TP',
      );
    });

    test('a department has no path above it', () {
      expect(AdeTree.pathLabel(students, 1108), '');
    });

    test('the label excludes the row itself, which the tile already shows', () {
      expect(AdeTree.pathLabel(students, 136), 'INFO › S7-INFO › S7-INFO-G1');
    });
  });

  group('visibleRoots', () {
    test('drops the individual-student junk node', () {
      final names = AdeTree.visibleRoots(students).map((g) => g.name).toList();
      expect(names, isNot(contains('Étudiant 2271')));
      expect(names.length, 17);
    });

    test('keeps every real department', () {
      final names = AdeTree.visibleRoots(students).map((g) => g.name).toList();
      expect(names, contains('INFO'));
      expect(names, contains('STPI'));
      expect(names, contains('HUMA'));
      expect(names, contains('PTP-M&N-S9'));
    });

    test('is sorted, so the first screen reads alphabetically', () {
      final names = AdeTree.visibleRoots(students).map((g) => g.name).toList();
      expect(names.first, 'DMA');
      expect(names.last, 'STPI');
    });
  });

  group('top-level classification', () {
    test('a formation is a root whose children are semesters', () {
      final names = AdeTree.formations(students).map((g) => g.name).toList();
      expect(names, <String>[
        'DMA',
        'E&T',
        'EII',
        'ELE-APPRENTISSAGE',
        'GCU',
        'GMA',
        'GMA-FISA',
        'GPM',
        'INFO',
        'STPI',
      ]);
    });

    test('masters and parcours are offered apart, not as departments', () {
      final names = AdeTree.otherTracks(students).map((g) => g.name).toList();
      expect(names, <String>[
        'MASTER-EO',
        'MASTER-MMGC',
        'MIE',
        'PTP-M&N-S9',
        'RIT',
        'SPIR',
      ]);
    });

    test('HUMA is in neither: it is a pool, not somewhere to start', () {
      expect(
        AdeTree.formations(students).map((g) => g.name),
        isNot(contains('HUMA')),
      );
      expect(
        AdeTree.otherTracks(students).map((g) => g.name),
        isNot(contains('HUMA')),
      );
    });

    test('the two lists plus HUMA account for every real root', () {
      final roots = AdeTree.visibleRoots(students).map((g) => g.name).toSet();
      final split = <String>{
        ...AdeTree.formations(students).map((g) => g.name),
        ...AdeTree.otherTracks(students).map((g) => g.name),
        ...AdeTree.crossCuttingRoots,
      };
      expect(split, roots);
    });

    test('hasSemesters drives the split, and skips step 2 when false', () {
      expect(AdeTree.hasSemesters(students, 1108), isTrue); // INFO
      expect(AdeTree.hasSemesters(students, 1106), isTrue); // GCU, DC-AI -S1…
      expect(AdeTree.hasSemesters(students, 2282), isFalse); // MASTER-EO
      expect(AdeTree.hasSemesters(students, 55), isFalse); // PTP-M&N-S9
      expect(AdeTree.hasSemesters(students, 1625), isFalse); // HUMA
    });
  });

  group('crossCutting', () {
    test('offers the langues and humanités branches everyone can take', () {
      final names = AdeTree.crossCutting(students).map((g) => g.name).toList();
      expect(names, contains('LV2- LV3'));
      expect(names, contains('ANGLAIS-TRANSVERSAL'));
      expect(names, contains('ARTS-ETUDES'));
    });
  });

  group('electivesForAll', () {
    test('unions the electives of every chosen semester', () {
      final names = AdeTree.electivesForAll(students, <int>[
        136, // S7-INFO-G1-1
        3439, // S8-INFO-G1-1
      ]).map((g) => g.name).toList();
      expect(names, contains('S7-INFO-OPTION'));
      expect(names, contains('S8-INFO-OPTION'));
      expect(names, isNot(contains('S7-INFO-G1')));
      expect(names, isNot(contains('S8-INFO-G1')));
    });

    test('never repeats a branch when two bases share a semester', () {
      final names = AdeTree.electivesForAll(students, <int>[
        29, // S9-INFO-TD-1
        376, // S9-INFO-TP1, same semester
      ]).map((g) => g.name).toList();
      expect(names.toSet().length, names.length);
      // Both of their own branches are covered, so neither is offered again.
      expect(names, isNot(contains('S9-INFO-TD')));
      expect(names, isNot(contains('S9-INFO-TP')));
    });
  });

  group('childrenOf ordering', () {
    test('semesters run S5 → S10, not S10 → S5', () {
      final names = AdeTree.childrenOf(
        students,
        1108, // INFO
      ).map((g) => g.name).toList();
      expect(names, <String>[
        'Clément',
        'Océane',
        'S5-INFO',
        'S6-INFO',
        'S7-INFO',
        'S8-INFO',
        'S9-INFO',
        'S10-INFO',
      ]);
    });

    test('zero padding does not change the order', () {
      final names = AdeTree.childrenOf(
        students,
        1105, // GPM, whose semesters are written S05..S10
      ).map((g) => g.name).toList();
      expect(names.first, 'S05-GPM');
      expect(names.last, 'S10-GPM');
    });

    test('numbered groups inside a TP branch stay in order', () {
      final names = AdeTree.childrenOf(
        students,
        202, // S1-STPI-A > 3 GROUPES TP
      ).map((g) => g.name).toList();
      expect(names, <String>[
        'S1 - Grp TP A3-1',
        'S1 - Grp TP A3-2',
        'S1 - Grp TP A3-3',
      ]);
    });
  });

  group('compareNatural', () {
    test('compares digit runs as numbers', () {
      expect(AdeTree.compareNatural('S5-INFO', 'S10-INFO'), lessThan(0));
      expect(AdeTree.compareNatural('S10-INFO', 'S9-INFO'), greaterThan(0));
    });

    test('reads S05 as the number 5, whatever the padding', () {
      expect(AdeTree.compareNatural('S05-GPM', 'S10-GPM'), lessThan(0));
      expect(AdeTree.compareNatural('S5-GPM', 'S10-GPM'), lessThan(0));
      expect(AdeTree.compareNatural('S05-GPM', 'S6-GPM'), lessThan(0));
    });

    test('folds case and accents, like the search does', () {
      // É is U+00C9, which a raw compare puts after Z.
      expect(AdeTree.compareNatural('Étudiant', 'Zebre'), lessThan(0));
      expect(AdeTree.compareNatural('groupe A', 'GROUPE B'), lessThan(0));
    });

    test('never returns 0 for two different names, so sorts stay stable', () {
      expect(AdeTree.compareNatural('S05-GPM', 'S5-GPM'), isNot(0));
      expect(AdeTree.compareNatural('Étudiant', 'etudiant'), isNot(0));
    });

    test('orders text before the digits that follow it', () {
      expect(AdeTree.compareNatural('S7-INFO', 'S7-INFO-G1'), lessThan(0));
      expect(AdeTree.compareNatural('G1-2', 'G1-10'), lessThan(0));
    });

    test('is a total order: equal names compare equal', () {
      expect(AdeTree.compareNatural('2 GROUPES TP', '2 GROUPES TP'), 0);
    });

    test('survives a digit run too long to be an int', () {
      final huge = '9' * 40;
      expect(AdeTree.compareNatural('S$huge', 'S1'), greaterThan(0));
    });
  });
}
