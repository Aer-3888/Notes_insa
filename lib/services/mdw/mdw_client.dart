import '../cas/http_session.dart';
import 'grade_parser.dart';
import 'vaadin_nodes.dart';
import 'vaadin_session.dart';
import 'vaadin_types.dart';

/// Drives "Mon Dossier Web" over Vaadin UIDL to reach the grade pages.
///
/// MDW is a server-side UI, so fetching grades means replaying the clicks a
/// browser would make: navigate, open a grade card, page in the rows.
class MdwClient {
  MdwClient(
    HttpSession http, {
    String baseUrl = VaadinSession.defaultBaseUrl,
    void Function(String label, Map<String, dynamic> body)? onResponse,
  }) : session = VaadinSession(http, baseUrl: baseUrl, onResponse: onResponse);

  final VaadinSession session;

  /// Node ids of the "Notes et résultats" buttons, one per card.
  List<int> groups = const <int>[];

  /// How many times to ask the grid again before giving up.
  static const int _maxRounds = 12;

  /// The grid's page size. Ranges have to be whole pages counted from zero,
  /// which is the only shape the real client ever sends.
  static const int _pageSize = 50;

  /// Children to ask for per parent, for a parent that sent none at all.
  static const int _childPageSize = 50;

  /// Names the grid may be asked for a root range under. Vaadin renamed this
  /// call, and a name the grid does not publish is dropped without an error.
  static const List<String> _rangeMethods = <String>[
    'setViewportRange',
    'setRequestedRange',
  ];

  /// Names the grid may be asked for one parent's children under.
  static const List<String> _childRangeMethods = <String>[
    'setParentViewportRanges',
    'setParentRequestedRanges',
    'setParentRequestedRange',
  ];

  /// The range calls this grid publishes, empty when it offers none.
  String rangeMethod = '';
  String childRangeMethod = '';

  int openedGroup = 0;
  int gridNode = 0;
  int dialogNode = 0;
  int closeButtonNode = 0;

  Future<void> init() async {
    await session.init();
    session.startBeating();
  }

  Future<void> dispose() async {
    session.stopBeating();
  }

  /// A mouse click, spelled the way the Vaadin client spells it.
  static Map<String, Object> _clickData() => <String, Object>{
    'event.altKey': false,
    'event.button': 0,
    'event.clientX': 0,
    'event.clientY': 0,
    'event.ctrlKey': false,
    'event.detail': 1,
    'event.metaKey': false,
    'event.screenX': 0,
    'event.screenY': 0,
    'event.shiftKey': false,
  };

  /// Loads the "inscriptions" view and records the grade cards it offers.
  Future<int> loadGroups() async {
    final data = await session.send(<VaadinRpc>[
      VaadinRpc(
        node: 1,
        type: 'event',
        event: 'ui-navigate',
        data: <String, Object>{
          'appShellTitle': '',
          'historyState': <String, Object>{'idx': 0},
          'query': '',
          'route': 'inscriptions',
          'trigger': '',
        },
      ),
    ], label: 'loadGroups');

    final layout = data.layoutNodes;
    final rpc = <VaadinRpc>[];

    const events = <String>[
      'primary-section-changed',
      'drawer-opened-changed',
      'overlay-changed',
      'drawer-opened-changed',
      'overlay-changed',
    ];
    for (final String event in events) {
      rpc.add(
        VaadinRpc(
          node: layout.layout,
          type: 'event',
          event: event,
          data: const <String, Object>{},
        ),
      );
    }

    rpc.add(
      VaadinRpc(
        node: layout.tabs,
        type: 'event',
        event: 'selected-changed',
        data: const <String, Object>{},
      ),
    );

    const syncs = <String>[
      'drawerOpened',
      'overlay',
      'drawerOpened',
      'overlay',
    ];
    for (var i = 0; i < syncs.length; i++) {
      rpc.add(
        VaadinRpc(
          node: layout.layout,
          type: 'mSync',
          feature: 1,
          property: syncs[i],
          value: i.isOdd,
        ),
      );
    }

    await session.send(rpc, label: 'loadGroups.ack');

    groups = data.gradeButtons;
    return groups.length;
  }

  /// Clicks a grade card open and returns the response holding its rows.
  Future<VaadinData> _openGrades(int groupIndex) async {
    if (groups.isEmpty) {
      throw VaadinException('groups not loaded');
    }
    if (groupIndex < 0 || groupIndex >= groups.length) {
      throw VaadinException('invalid group index $groupIndex');
    }

    final nodeId = groups[groupIndex];
    final data = await session.send(<VaadinRpc>[
      VaadinRpc(
        node: nodeId,
        type: 'event',
        event: 'click',
        data: _clickData(),
      ),
    ], label: 'openGrades');

    final nodes = data.gridNodes;
    openedGroup = nodeId;
    gridNode = nodes.grid;
    dialogNode = nodes.dialog;
    closeButtonNode = data.closeButton;

    final published = data.publishedMethods(gridNode);
    String offered(List<String> names) =>
        names.firstWhere(published.contains, orElse: () => '');
    rangeMethod = offered(_rangeMethods);
    childRangeMethod = offered(_childRangeMethods);

    return data;
  }

  /// Opens card [groupIndex] and widens the viewport until it holds every row.
  Future<VaadinData> openAllRows(int groupIndex) async {
    final responses = <VaadinData>[await _openGrades(groupIndex)];
    var merged = responses.first;
    var rows = GradeParser.rowsOf(merged);

    await _confirmRows(_parentsOf(rows), updateIds: merged.updateIds);

    var window = _pageSize;

    for (var round = 0; round < _maxRounds; round++) {
      if (rangeMethod.isEmpty) break;

      var knownEnd = merged.gridSize ?? 0;
      for (final gap in merged.clearedRanges) {
        final end = gap.start + gap.length;
        if (end > knownEnd) knownEnd = end;
      }

      final flatIndices = <int>{
        for (final row in rows)
          if (row.parentKey == null) row.index,
      };
      final hasKnownGap = merged.clearedRanges.any(
        (gap) => Iterable<int>.generate(
          gap.length,
          (i) => gap.start + i,
        ).any((index) => !flatIndices.contains(index)),
      );
      final firstPageIsFull = rows.length >= window;
      if (!hasKnownGap && rows.length >= knownEnd && !firstPageIsFull) break;

      final wanted = ((knownEnd + _pageSize - 1) ~/ _pageSize) * _pageSize;
      window = wanted > window ? wanted : window + _pageSize;

      final before = rows.length;
      responses.add(await _requestRange(0, window));
      merged = VaadinData.merge(responses);
      rows = GradeParser.rowsOf(merged);
      await _confirmRows(_parentsOf(rows), updateIds: responses.last.updateIds);
      if (rows.length == before) break;
    }

    // A parent that sent no children at all is the one case the flat list does
    // not cover.
    for (var round = 0; round < _maxRounds; round++) {
      final missing = GradeParser.missingChildKeys(rows);
      if (missing.isEmpty || childRangeMethod.isEmpty) break;

      final before = rows.length;
      responses.add(
        await _requestChildren(<Map<String, Object>>[
          for (final String key in missing)
            <String, Object>{
              'firstIndex': 0,
              'parentKey': key,
              'size': _childPageSize,
            },
        ]),
      );
      merged = VaadinData.merge(responses);
      rows = GradeParser.rowsOf(merged);
      await _confirmRows(_parentsOf(rows), updateIds: responses.last.updateIds);
      if (rows.length == before) break;
    }

    return merged;
  }

  /// Asks for a window of the flat list, as whole pages counted from zero.
  Future<VaadinData> _requestRange(int start, int length) =>
      session.send(<VaadinRpc>[
        VaadinRpc(
          node: gridNode,
          type: 'publishedEventHandler',
          promise: 0,
          templateEventMethodName: rangeMethod,
          templateEventMethodArgs: <Object>[start, length],
        ),
      ], label: 'requestRange');

  /// Keys of the rows that carry children, which is what MDW expects back.
  static List<String> _parentsOf(List<GradeRow> rows) => rows
      .where((GradeRow r) => r.hasChildren)
      .map((GradeRow r) => r.key)
      .toList();

  /// Acknowledges the rows Vaadin sent and opens the dialog.
  ///
  /// MDW keeps the grid's server-side state pending until each update is
  /// confirmed, and leaving it pending makes the next card open empty.
  Future<void> _confirmRows(
    Iterable<String> parentKeys, {
    Iterable<int> updateIds = const <int>[],
  }) async {
    final rpc = <VaadinRpc>[
      VaadinRpc(
        node: dialogNode,
        type: 'event',
        event: 'opened-changed',
        data: const <String, Object>{},
      ),
    ];

    for (final int id in updateIds) {
      rpc.add(
        VaadinRpc(
          node: gridNode,
          type: 'publishedEventHandler',
          promise: 0,
          templateEventMethodName: 'confirmUpdate',
          templateEventMethodArgs: <Object>[id],
        ),
      );
    }

    for (final String key in parentKeys) {
      rpc.add(
        VaadinRpc(
          node: gridNode,
          type: 'publishedEventHandler',
          promise: 0,
          templateEventMethodName: 'confirmParentUpdate',
          templateEventMethodArgs: <Object>[0, key],
        ),
      );
    }

    await session.send(rpc, label: 'confirmRows');
  }

  /// Asks for a window of several parents' children at once.
  Future<VaadinData> _requestChildren(List<Map<String, Object>> ranges) async {
    return session.send(<VaadinRpc>[
      VaadinRpc(
        node: gridNode,
        type: 'publishedEventHandler',
        promise: 0,
        templateEventMethodName: childRangeMethod,
        templateEventMethodArgs: <Object>[ranges],
      ),
    ], label: 'requestChildren');
  }

  /// Opens a row's details dialog and reads its coefficient.
  ///
  /// Selecting the row, showing its details and clicking it are all needed
  /// before MDW renders the dialog.
  Future<({String? coefficient, int node})> openCoefficient(String key) async {
    final rpc = <VaadinRpc>[
      for (final String method in <String>['select', 'setDetailsVisible'])
        VaadinRpc(
          node: gridNode,
          type: 'publishedEventHandler',
          promise: 0,
          templateEventMethodName: method,
          templateEventMethodArgs: <String>[key],
        ),
      VaadinRpc(
        node: gridNode,
        type: 'event',
        event: 'item-click',
        data: <String, Object>{
          ..._clickData(),
          'event.detail.internalColumnId': 'col0',
          'event.detail.itemKey': key,
        },
      ),
    ];

    final data = await session.send(rpc, label: 'openCoefficient');
    final node = data.coefficientNode;

    if (node != 0) {
      await session.send(<VaadinRpc>[
        VaadinRpc(node: node, type: 'event', event: 'opened-changed'),
      ], label: 'openCoefficient.ack');
    }

    return (coefficient: data.coefficient, node: node);
  }

  Future<void> closeCoefficient(int node) async {
    if (node == 0) return;
    await session.send(<VaadinRpc>[
      VaadinRpc(
        node: node,
        type: 'publishedEventHandler',
        promise: 0,
        templateEventMethodName: 'handleClientClose',
        templateEventMethodArgs: const <Object>[],
      ),
    ], label: 'closeCoefficient');
  }

  Future<void> closeGrades() async {
    if (closeButtonNode == 0) return;
    await session.send(<VaadinRpc>[
      VaadinRpc(
        node: closeButtonNode,
        type: 'event',
        event: 'click',
        data: _clickData(),
      ),
    ], label: 'closeGrades');

    openedGroup = 0;
    gridNode = 0;
    dialogNode = 0;
    closeButtonNode = 0;
  }
}
