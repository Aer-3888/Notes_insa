import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/services/cas/http_session.dart';
import 'package:notes_insa/services/mdw/grade.dart';
import 'package:notes_insa/services/mdw/grade_parser.dart';
import 'package:notes_insa/services/mdw/mdw_client.dart';

/// A tree grid that behaves like MDW: the open click answers with the first
/// [pageSize] rows of the flattened tree and nothing else, so the cut lands
/// inside a parent, and the rest only arrives per parent through
/// `setParentRequestedRanges`.
class _FakeMdw {
  _FakeMdw(
    this._server, {
    required this.modules,
    required this.pageSize,
    this.lazy = const <String>{},
    this.publishes = defaultMethods,
  }) {
    _server.listen(_handle);
  }

  static const List<String> defaultMethods = <String>[
    'setViewportRange',
    'setParentRequestedRanges',
    'confirmUpdate',
    'confirmParentUpdate',
  ];

  static const int gridNode = 222;
  static const int groupNode = 7;

  final HttpServer _server;

  /// Modules under each of the two semesters.
  final int modules;
  final int pageSize;

  /// Parents whose children the flat list withholds entirely, so they only
  /// arrive through a request for that parent.
  final Set<String> lazy;

  /// Method names the grid declares to the client.
  final List<String> publishes;

  /// Every child range asked for, as (parentKey, firstIndex).
  final List<({int firstIndex, String parentKey})> asked =
      <({int firstIndex, String parentKey})>[];

  /// Every viewport range asked for, as (start, length).
  final List<({int length, int start})> ranges = <({int length, int start})>[];

  int _sync = 1;
  int _node = 1000;

  /// Flat indices already delivered; the grid does not resend a row.
  final Set<int> _sent = <int>{};

  String get baseUrl => 'http://${_server.address.address}:${_server.port}';

  Future<void> close() => _server.close(force: true);

  /// Each key mapped to its ordered child keys.
  Map<String, List<String>> get _tree => <String, List<String>>{
    'r': <String>['s0', 's1'],
    's0': <String>[for (var i = 0; i < modules; i++) 's0m$i'],
    's1': <String>[for (var i = 0; i < modules; i++) 's1m$i'],
  };

  int _levelOf(String key) => key == 'r' ? 0 : (key.contains('m') ? 2 : 1);

  /// Depth-first order, which is how the grid flattens an expanded tree.
  List<String> get _flat {
    final out = <String>[];
    void walk(String key) {
      out.add(key);
      if (lazy.contains(key)) return;
      for (final String child in _tree[key] ?? const <String>[]) {
        walk(child);
      }
    }

    walk('r');
    return out;
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.uri.queryParameters['v-r'] == 'init') {
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, dynamic>{
            'appConfig': <String, dynamic>{
              'v-uiId': 1,
              'heartbeatInterval': 0,
              'uidl': <String, dynamic>{
                'syncId': 1,
                'clientId': 1,
                'Vaadin-Security-Key': 'key',
              },
            },
          }),
        );
      await request.response.close();
      return;
    }

    final body = await utf8.decoder.bind(request).join();
    final rpc =
        (jsonDecode(body) as Map<String, dynamic>)['rpc'] as List<dynamic>;

    request.response
      ..headers.contentType = ContentType.json
      ..write('for(;;);${jsonEncode(<Object?>[_respond(rpc)])}');
    await request.response.close();
  }

  Map<String, dynamic> _respond(List<dynamic> rpc) {
    for (final Object? call in rpc) {
      if (call is! Map<String, dynamic>) continue;

      if (call['templateEventMethodName'] == 'setViewportRange') {
        final args = call['templateEventMethodArgs'] as List<dynamic>;
        ranges.add((length: args[1] as int, start: args[0] as int));
        return _openPage(args[0] as int, args[1] as int);
      }

      if (call['templateEventMethodName'] == 'setParentRequestedRanges') {
        final args = call['templateEventMethodArgs'] as List<dynamic>;
        return _children(
          (args.first as List<dynamic>).cast<Map<String, dynamic>>(),
        );
      }

      if (call['node'] == groupNode && call['event'] == 'click') {
        return _openPage();
      }
    }

    return _empty();
  }

  Map<String, dynamic> _empty() => <String, dynamic>{
    'syncId': ++_sync,
    'clientId': _sync,
  };

  /// A window of the flattened tree, never more than the grid serves at once,
  /// plus the size and the blanked range standing for what was withheld.
  Map<String, dynamic> _openPage([int start = 0, int length = -1]) {
    final opening = length < 0;
    final changes = <Map<String, dynamic>>[
      if (opening) ...<Map<String, dynamic>>[
        _tag(gridNode, 'vaadin-grid'),
        _methods(gridNode, publishes),
        _tag(223, 'vaadin-dialog'),
        _tag(224, 'vaadin-button'),
        ..._text(224, 'Fermer'),
      ],
    ];
    final execute = <List<dynamic>>[];

    final flat = _flat;
    execute.add(<dynamic>[
      <String, dynamic>{'@v-node': gridNode},
      flat.length,
      r'return $0.$connector.updateSize($1)',
    ]);

    final end = opening
        ? pageSize
        : (start + length < flat.length ? start + length : flat.length);
    for (var i = opening ? 0 : start; i < flat.length && i < end; i++) {
      if (!_sent.add(i)) continue;
      execute.add(_rowCall(i, flat[i], changes));
    }

    if (end < flat.length) {
      execute.add(<dynamic>[
        <String, dynamic>{'@v-node': gridNode},
        end,
        flat.length - end,
        r'return $0.$connector.clear($1,$2)',
      ]);
    }

    execute.add(<dynamic>[
      <String, dynamic>{'@v-node': gridNode},
      0,
      r'return $0.$connector.confirm($1)',
    ]);

    return <String, dynamic>{
      'syncId': ++_sync,
      'clientId': _sync,
      'changes': changes,
      'execute': execute,
    };
  }

  /// One page of children per requested range, indexed within the parent.
  Map<String, dynamic> _children(List<Map<String, dynamic>> ranges) {
    final changes = <Map<String, dynamic>>[];
    final execute = <List<dynamic>>[];

    for (final Map<String, dynamic> range in ranges) {
      final parent = range['parentKey'] as String;
      final first = range['firstIndex'] as int;
      final wanted = range['size'] as int;
      asked.add((firstIndex: first, parentKey: parent));

      final children = _tree[parent] ?? const <String>[];
      for (var i = first; i < children.length && i < first + wanted; i++) {
        execute.add(_rowCall(i, children[i], changes, parentKey: parent));
      }
    }

    if (execute.isEmpty) return _empty();
    return <String, dynamic>{
      'syncId': ++_sync,
      'clientId': _sync,
      'changes': changes,
      'execute': execute,
    };
  }

  List<dynamic> _rowCall(
    int index,
    String key,
    List<Map<String, dynamic>> changes, {
    String? parentKey,
  }) {
    final holder = _node;
    _node += 2;
    changes.addAll(_text(holder, key.toUpperCase()));

    final item = <String, dynamic>{
      'key': key,
      'level': _levelOf(key),
      if ((_tree[key] ?? const <String>[]).isNotEmpty) ...<String, dynamic>{
        'children': true,
        'expanded': true,
      },
      'lr_a_nodeid': holder,
    };

    return <dynamic>[
      <String, dynamic>{'@v-node': gridNode},
      index,
      <dynamic>[item],
      ?parentKey,
      parentKey == null
          ? r'return $0.$connector.set($1,$2)'
          : r'return $0.$connector.set($1,$2,$3)',
    ];
  }

  /// The feature that declares which methods the client may call.
  static Map<String, dynamic> _methods(int node, List<String> names) =>
      <String, dynamic>{
        'node': node,
        'type': 'splice',
        'feat': 19,
        'index': 0,
        'add': names,
      };

  static Map<String, dynamic> _tag(int node, String tag) => <String, dynamic>{
    'node': node,
    'type': 'put',
    'key': 'tag',
    'value': tag,
  };

  static List<Map<String, dynamic>> _text(int holder, String value) =>
      <Map<String, dynamic>>[
        <String, dynamic>{
          'node': holder + 1,
          'type': 'put',
          'key': 'text',
          'value': value,
        },
        <String, dynamic>{
          'node': holder,
          'addNodes': <int>[holder + 1],
        },
      ];
}

void main() {
  late _FakeMdw fake;
  late HttpSession http;
  late MdwClient mdw;

  Future<void> start({
    required int modules,
    int pageSize = 50,
    Set<String> lazy = const <String>{},
    List<String>? publishes,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    fake = _FakeMdw(
      server,
      modules: modules,
      pageSize: pageSize,
      lazy: lazy,
      publishes: publishes ?? _FakeMdw.defaultMethods,
    );
    http = HttpSession();
    mdw = MdwClient(http, baseUrl: fake.baseUrl);
    await mdw.init();
    mdw.groups = <int>[_FakeMdw.groupNode];
  }

  tearDown(() async {
    await mdw.dispose();
    http.close();
    await fake.close();
  });

  List<int> moduleCounts(Grade root) =>
      root.details.map((Grade s) => s.details.length).toList();

  test(
    'uses the range call the grid publishes, not a hardcoded name',
    () async {
      await start(modules: 30);

      await mdw.openAllRows(0);

      expect(mdw.rangeMethod, 'setViewportRange');
      expect(mdw.childRangeMethod, 'setParentRequestedRanges');
    },
  );

  test('asks for nothing when the grid publishes no range call', () async {
    await start(modules: 30, publishes: <String>['confirmUpdate']);

    await mdw.openAllRows(0);

    expect(mdw.rangeMethod, isEmpty);
    expect(fake.ranges, isEmpty);
    expect(fake.asked, isEmpty);
  });

  test('widens the viewport until it holds the whole flat list', () async {
    // 1 root + 2 semesters + 60 modules = 63 rows, so the first page of 50
    // stops partway through the second semester.
    await start(modules: 30);

    final root = GradeParser.parse(await mdw.openAllRows(0))!;

    expect(root.name, 'R');
    expect(moduleCounts(root), <int>[30, 30]);
  });

  test('asks for whole pages counted from zero', () async {
    await start(modules: 30);

    await mdw.openAllRows(0);

    expect(fake.ranges, isNotEmpty);
    for (final ({int length, int start}) r in fake.ranges) {
      expect(r.start, 0, reason: 'ranges run from zero');
      expect(r.length % 50, 0, reason: 'whole pages only');
    }
  });

  test('sends no range request when the first page held everything', () async {
    await start(modules: 4);

    final root = GradeParser.parse(await mdw.openAllRows(0))!;

    expect(moduleCounts(root), <int>[4, 4]);
    expect(fake.ranges, isEmpty);
  });

  test('asks for a parent that the flat list gave no children for', () async {
    await start(modules: 4, lazy: <String>{'s1'});

    final root = GradeParser.parse(await mdw.openAllRows(0))!;

    expect(
      fake.asked.map((({int firstIndex, String parentKey}) r) => r.parentKey),
      <String>['s1'],
    );
    expect(moduleCounts(root), <int>[4, 4]);
  });

  test(
    'a child page does not collide with the row at the same index',
    () async {
      // s1's modules only arrive as a child page, indexed from zero inside s1,
      // which collides with the flat indices of the rows already held.
      await start(modules: 4, lazy: <String>{'s1'});

      final root = GradeParser.parse(await mdw.openAllRows(0))!;

      expect(moduleCounts(root), <int>[4, 4]);
      expect(root.details.last.details.map((Grade g) => g.name), <String>[
        'S1M0',
        'S1M1',
        'S1M2',
        'S1M3',
      ]);
    },
  );
}
