import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notes_insa/modules/schedule/ade_groups.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the bundled asset carries every picker category', () async {
    final all = await AdeGroups.loadBundled();
    expect(AdeGroups.ofCategory(all, AdeCategory.student).length, 1433);
    expect(AdeGroups.ofCategory(all, AdeCategory.room).length, 231);
    expect(AdeGroups.ofCategory(all, AdeCategory.module).length, 1978);
  });

  test('a known group resolves to the id ADE accepts', () async {
    final all = await AdeGroups.loadBundled();
    final students = AdeGroups.ofCategory(all, AdeCategory.student);
    expect(AdeGroups.search(students, 'S3-STPI-L').first.id, 2152);
  });

  test('the full S7-INFO selection is present and resolvable', () async {
    final all = await AdeGroups.loadBundled();
    final byId = {for (final g in all) g.id: g.name};
    const ids = <int>[
      1214,
      133,
      136,
      138,
      139,
      144,
      145,
      1672,
      196,
      1678,
      199,
      1676,
      1679,
      601,
      448,
      899,
      1681,
      2614,
      942,
      187,
    ];
    for (final id in ids) {
      expect(byId[id], isNotNull, reason: 'id \$id missing from the bundle');
      expect(byId[id], startsWith('S7-INFO'));
    }
  });

  test('the top level is departments, not 1433 groups', () async {
    final all = await AdeGroups.loadBundled();
    final students = AdeGroups.ofCategory(all, AdeCategory.student);
    final roots = AdeGroups.childrenOf(students, null);
    expect(roots.length, 18);
    expect(roots.map((g) => g.name), contains('INFO'));
    expect(roots.map((g) => g.name), contains('STPI'));
  });

  test('drilling INFO reaches S7-INFO, then its groups', () async {
    final all = await AdeGroups.loadBundled();
    final students = AdeGroups.ofCategory(all, AdeCategory.student);
    final info = AdeGroups.childrenOf(
      students,
      null,
    ).firstWhere((g) => g.name == 'INFO');

    final semesters = AdeGroups.childrenOf(students, info.id);
    expect(semesters.map((g) => g.name), contains('S7-INFO'));

    final s7 = semesters.firstWhere((g) => g.name == 'S7-INFO');
    expect(s7.id, 1214);
    final groups = AdeGroups.childrenOf(students, s7.id);
    expect(groups.map((g) => g.name), contains('S7-INFO-G1'));
    expect(groups.map((g) => g.name), contains('S7-INFO-OPTION'));
  });

  test(
    'a leaf reports no children so the picker offers no drill-down',
    () async {
      final all = await AdeGroups.loadBundled();
      final students = AdeGroups.ofCategory(all, AdeCategory.student);
      expect(AdeGroups.hasChildren(students, 899), isFalse); // S7-INFO-ROBO
      expect(AdeGroups.hasChildren(students, 1214), isTrue); // S7-INFO
    },
  );

  test('pathTo builds the breadcrumb outermost first', () async {
    final all = await AdeGroups.loadBundled();
    final students = AdeGroups.ofCategory(all, AdeCategory.student);
    final path = AdeGroups.pathTo(students, 136); // S7-INFO-G1-1
    expect(path.map((g) => g.name).toList(), <String>[
      'INFO',
      'S7-INFO',
      'S7-INFO-G1',
      'S7-INFO-G1-1',
    ]);
  });

  test('a v1 payload still parses, so a cached older list keeps working', () {
    final groups = AdeGroups.parseForTest(
      jsonEncode({
        'version': 1,
        'groups': [
          {'id': 7, 'name': 'S1-STPI-A'},
        ],
      }),
    );
    expect(groups.single.category, AdeCategory.student);
  });

  test('fetchRemote parses the worker payload', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'version': 2,
          'resources': [
            {'id': 7, 'name': 'S1-STPI-A', 'c': 's'},
          ],
        }),
        200,
      ),
    );
    final groups = await AdeGroups.fetchRemote(client: client);
    expect(groups.single.id, 7);
  });

  test(
    'fetchRemote rejects a non-200 rather than returning an empty list',
    () async {
      final client = MockClient((_) async => http.Response('nope', 503));
      expect(
        () => AdeGroups.fetchRemote(client: client),
        throwsA(isA<http.ClientException>()),
      );
    },
  );

  test('fetchRemote rejects an empty group list', () async {
    final client = MockClient(
      (_) async => http.Response(jsonEncode({'resources': <dynamic>[]}), 200),
    );
    expect(
      () => AdeGroups.fetchRemote(client: client),
      throwsA(isA<FormatException>()),
    );
  });
}
