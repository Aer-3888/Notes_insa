import '../cas/http_session.dart';
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

  int openedGroup = 0;
  int gridNode = 0;
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
  Future<VaadinData> openGrades(int groupIndex) async {
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
    closeButtonNode = data.closeButton;

    return data;
  }

  /// Acknowledges the rows Vaadin sent and opens the dialog.
  Future<void> confirmRows(int dialogNode, Iterable<String> parentKeys) async {
    final rpc = <VaadinRpc>[
      VaadinRpc(
        node: dialogNode,
        type: 'event',
        event: 'opened-changed',
        data: const <String, Object>{},
      ),
    ];

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

  /// Asks for the children of rows that arrived without any.
  Future<VaadinData> requestChildren(List<String> parentKeys) async {
    final ranges = parentKeys
        .map(
          (String key) => <String, Object>{
            'firstIndex': 0,
            'parentKey': key,
            'size': 50,
          },
        )
        .toList();

    return session.send(<VaadinRpc>[
      VaadinRpc(
        node: gridNode,
        type: 'publishedEventHandler',
        promise: 0,
        templateEventMethodName: 'setParentRequestedRanges',
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
    closeButtonNode = 0;
  }
}
