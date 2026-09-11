import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/services/mdw/grade.dart';
import 'package:notes_insa/services/mdw/grade_parser.dart';
import 'package:notes_insa/services/mdw/vaadin_types.dart';

/// Builds a response in the shape captured from MDW: rows arrive as the third
/// argument of a JS call, naming their columns by node id, and the text for
/// those nodes lives in `changes` behind an addNodes hop.
class _ResponseBuilder {
  final List<Map<String, dynamic>> _changes = <Map<String, dynamic>>[];
  final List<List<dynamic>> _execute = <List<dynamic>>[];
  int _nextNode = 100;

  /// Adds a node whose text is [values], and returns the id to reference.
  int textNode(List<String> values) {
    final holder = _nextNode++;
    final children = <int>[];

    for (final String value in values) {
      final leaf = _nextNode++;
      children.add(leaf);
      _changes.add(<String, dynamic>{
        'node': leaf,
        'type': 'put',
        'key': 'text',
        'value': value,
      });
    }

    _changes.add(<String, dynamic>{'node': holder, 'addNodes': children});
    return holder;
  }

  void row({
    required int index,
    required String key,
    required int level,
    required int nameNode,
    int? valueNode,
    bool children = false,
  }) {
    final item = <String, dynamic>{
      'key': key,
      'level': level,
      if (children) ...<String, dynamic>{'children': true, 'expanded': true},
      'lr_89c27c9fba1d48d5_nodeid': nameNode,
      if (valueNode != null) 'lr_8c127e4141854e82_nodeid': valueNode,
    };
    _execute.add(<dynamic>[
      <String, dynamic>{'@v-node': 222},
      index,
      <dynamic>[item],
      'return \$0.\$connector.confirm(\$1)',
    ]);
  }

  /// A call carrying no rows, as the response also contains.
  void bareCall() => _execute.add(<dynamic>[
    <String, dynamic>{'@v-node': 222},
    '\$0.setAttribute("focus")',
  ]);

  VaadinData build() => VaadinData.fromJson(<String, dynamic>{
    'changes': _changes,
    'execute': _execute,
  });
}

void main() {
  group('row extraction', () {
    test('reads rows and ignores calls that carry none', () {
      final b = _ResponseBuilder()..bareCall();
      b.row(index: 0, key: '0', level: 0, nameNode: b.textNode(['ANNEE 3']));
      b.bareCall();

      final rows = GradeParser.rowsOf(b.build());

      expect(rows, hasLength(1));
      expect(rows.single.key, '0');
    });

    test('orders rows by tree position, not by call order', () {
      final b = _ResponseBuilder();
      b.row(index: 2, key: 'c', level: 1, nameNode: b.textNode(['third']));
      b.row(index: 0, key: 'a', level: 0, nameNode: b.textNode(['first']));
      b.row(index: 1, key: 'b', level: 1, nameNode: b.textNode(['second']));

      expect(GradeParser.rowsOf(b.build()).map((GradeRow r) => r.key), <String>[
        'a',
        'b',
        'c',
      ]);
    });
  });

  group('tree building', () {
    VaadinData sample() {
      final b = _ResponseBuilder();
      b.row(
        index: 0,
        key: '0',
        level: 0,
        nameNode: b.textNode(['ANNEE 3']),
        valueNode: b.textNode(['12,50/20']),
        children: true,
      );
      b.row(
        index: 1,
        key: '1',
        level: 1,
        nameNode: b.textNode(['SEMESTRE 5']),
        valueNode: b.textNode(['13,00/20']),
        children: true,
      );
      b.row(
        index: 2,
        key: '2',
        level: 2,
        nameNode: b.textNode(['MATHEMATIQUES']),
        valueNode: b.textNode(['14,00/20']),
      );
      b.row(
        index: 3,
        key: '3',
        level: 2,
        nameNode: b.textNode(['PHYSIQUE']),
        valueNode: b.textNode(['VAL']),
      );
      b.row(
        index: 4,
        key: '4',
        level: 1,
        nameNode: b.textNode(['SEMESTRE 6']),
        valueNode: b.textNode(['Aucun résultats']),
      );
      return b.build();
    }

    test('nests rows by level', () {
      final root = GradeParser.parse(sample())!;

      expect(root.name, 'ANNEE 3');
      expect(root.details.map((Grade g) => g.name), <String>[
        'SEMESTRE 5',
        'SEMESTRE 6',
      ]);
      expect(root.details.first.details.map((Grade g) => g.name), <String>[
        'MATHEMATIQUES',
        'PHYSIQUE',
      ]);
    });

    test('resolves the label column and the value column', () {
      final root = GradeParser.parse(sample())!;
      final maths = root.details.first.details.first;

      expect(maths.name, 'MATHEMATIQUES');
      expect(maths.score, <String>['14,00/20']);
    });

    test('keeps non-numeric results verbatim', () {
      final root = GradeParser.parse(sample())!;

      expect(root.details.first.details.last.score, <String>['VAL']);
      expect(root.details.last.score, <String>['Aucun résultats']);
    });

    test('closes deeper levels when the tree steps back out', () {
      final root = GradeParser.parse(sample())!;

      expect(root.details.last.details, isEmpty);
    });

    test('carries several values on one row', () {
      final b = _ResponseBuilder();
      b.row(
        index: 0,
        key: '0',
        level: 0,
        nameNode: b.textNode(['UE']),
        valueNode: b.textNode(['12,00/20', 'VAL']),
      );

      expect(GradeParser.parse(b.build())!.score, <String>['12,00/20', 'VAL']);
    });

    test('skips a row whose label does not resolve to one value', () {
      final b = _ResponseBuilder();
      b.row(index: 0, key: '0', level: 0, nameNode: b.textNode(['ANNEE 3']));
      b.row(index: 1, key: '1', level: 1, nameNode: b.textNode(<String>[]));
      b.row(index: 2, key: '2', level: 1, nameNode: b.textNode(['KEPT']));

      final root = GradeParser.parse(b.build())!;

      expect(root.details.map((Grade g) => g.name), <String>['KEPT']);
    });

    test('returns null when the response carried no rows', () {
      expect(
        GradeParser.parse((_ResponseBuilder()..bareCall()).build()),
        isNull,
      );
    });

    test('wraps several roots rather than losing them', () {
      final b = _ResponseBuilder();
      b.row(index: 0, key: '0', level: 0, nameNode: b.textNode(['A']));
      b.row(index: 1, key: '1', level: 0, nameNode: b.textNode(['B']));

      final root = GradeParser.parse(b.build())!;

      expect(root.details.map((Grade g) => g.name), <String>['A', 'B']);
    });
  });

  group('lazy children', () {
    test('reports a parent whose children never arrived', () {
      final b = _ResponseBuilder();
      b.row(
        index: 0,
        key: '0',
        level: 0,
        nameNode: b.textNode(['ANNEE 3']),
        children: true,
      );
      b.row(
        index: 1,
        key: '1',
        level: 1,
        nameNode: b.textNode(['SEMESTRE 5']),
        children: true,
      );

      expect(
        GradeParser.missingChildKeys(GradeParser.rowsOf(b.build())),
        <String>['1'],
      );
    });

    test('reports nothing when every parent was filled', () {
      final b = _ResponseBuilder();
      b.row(
        index: 0,
        key: '0',
        level: 0,
        nameNode: b.textNode(['ANNEE 3']),
        children: true,
      );
      b.row(index: 1, key: '1', level: 1, nameNode: b.textNode(['SEMESTRE 5']));

      expect(
        GradeParser.missingChildKeys(GradeParser.rowsOf(b.build())),
        isEmpty,
      );
    });
  });

  group('serialization', () {
    test('matches the shape the app already parses', () {
      final grade = Grade(
        name: 'ANNEE 3',
        score: const <String>['12,50/20'],
        details: <Grade>[
          Grade(name: 'MATHS', score: const <String>['14,00/20'], details: []),
        ],
      );

      expect(grade.toJson(), <String, dynamic>{
        'name': 'ANNEE 3',
        'score': <String>['12,50/20'],
        'details': <dynamic>[
          <String, dynamic>{
            'name': 'MATHS',
            'score': <String>['14,00/20'],
            'details': <dynamic>[],
          },
        ],
      });
    });

    test('omits the coefficient until it is filled', () {
      final grade = Grade(name: 'X', score: const <String>[], details: []);
      expect(grade.toJson().containsKey('coeff'), isFalse);

      grade.coeff = '2.5';
      expect(grade.toJson()['coeff'], '2.5');
    });
  });
}
