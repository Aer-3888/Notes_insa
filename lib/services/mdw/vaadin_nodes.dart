import 'vaadin_types.dart';

/// Node lookups over a UIDL response.
///
/// Vaadin identifies widgets by a `tag` put on a node, so finding the grid or a
/// button means scanning the changes for the tag and then reading the node's
/// text back out of its children.
extension VaadinNodeLookup on VaadinData {
  /// Text carried by [nodeId], gathered recursively from its children.
  List<String> nodeValues(int nodeId, {int depth = 0}) {
    if (depth > 20) return const <String>[];

    for (final VaadinNode node in changes) {
      if (node.node != nodeId) continue;

      final children = node.addNodes;
      if (children != null) {
        final values = <String>[];
        for (final int child in children) {
          values.addAll(nodeValues(child, depth: depth + 1));
        }
        return values;
      }

      if (node.key == 'text') {
        final value = node.value;
        if (value is String) return <String>[value];
      }
    }

    return const <String>[];
  }

  /// The node a `tag` put names, or 0.
  int nodeTagged(String tag) {
    for (final VaadinNode node in changes) {
      if (node.key == 'tag' && node.type == 'put' && node.value == tag) {
        return node.node;
      }
    }
    return 0;
  }

  List<int> nodesTagged(String tag) {
    final found = <int>[];
    for (final VaadinNode node in changes) {
      if (node.key == 'tag' && node.type == 'put' && node.value == tag) {
        found.add(node.node);
      }
    }
    return found;
  }

  ({int layout, int tabs}) get layoutNodes => (
    layout: nodeTagged('vaadin-app-layout'),
    tabs: nodeTagged('vaadin-tabs'),
  );

  ({int grid, int dialog}) get gridNodes =>
      (grid: nodeTagged('vaadin-grid'), dialog: nodeTagged('vaadin-dialog'));

  int get coefficientNode => nodeTagged('vaadin-dialog');

  List<int> get buttons => nodesTagged('vaadin-button');

  /// Buttons labelled "Notes et résultats", one per grade card.
  List<int> get gradeButtons => buttons
      .where((int id) => nodeValues(id).contains('Notes et résultats'))
      .toList();

  int get closeButton {
    for (final int id in buttons) {
      if (nodeValues(id).contains('Fermer')) return id;
    }
    return 0;
  }

  /// The coefficient shown in the details dialog.
  ///
  /// The dialog carries it as the text node immediately before the one reading
  /// "coefficient", so the label is what locates the value.
  String? get coefficient {
    final texts = <String>[];
    for (final VaadinNode node in changes) {
      if (node.key != 'text') continue;
      final value = node.value;
      if (value is String) texts.add(value);
    }

    final label = texts.indexWhere(
      (String t) => t.trim().toLowerCase() == 'coefficient',
    );
    return label > 0 ? texts[label - 1] : null;
  }

  /// A short type-and-shape summary used in error messages when the server
  /// changes format. Reports names and sizes, never transported values.
  String describe() {
    final buffer = StringBuffer('changes=${changes.length}')
      ..write(' execute=${execute.length}');
    for (var i = 0; i < execute.length; i++) {
      buffer.write(' | [$i] len=${execute[i].length}');
      for (var j = 0; j < execute[i].length; j++) {
        buffer.write(' $j:${_describeValue(execute[i][j], 0)}');
      }
    }
    return buffer.toString();
  }

  static String _describeValue(Object? value, int depth) {
    if (value is List) {
      if (depth >= 3) return 'array(${value.length})';
      if (value.isEmpty) return 'array(0)';
      return 'array(${value.length})'
          '[${_describeValue(value.last, depth + 1)}]';
    }
    if (value is Map) {
      final keys = value.keys.map((Object? k) => '$k').toList()..sort();
      return 'object{${keys.join(',')}}';
    }
    if (value is String) return 'string';
    if (value is num) return 'number';
    if (value is bool) return 'bool';
    return 'null';
  }
}
