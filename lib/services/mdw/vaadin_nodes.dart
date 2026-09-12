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

  /// Feature holding the names of the methods the client may call on a node.
  static const int _clientDelegateHandlers = 19;

  /// Methods [nodeId] publishes to the client. Vaadin renames these between
  /// versions, so the names it declares are the only reliable list: a call to
  /// one it does not publish is dropped without an error.
  List<String> publishedMethods(int nodeId) {
    final names = <String>[];
    for (final VaadinNode node in changes) {
      if (node.node != nodeId) continue;
      if (node.feature != _clientDelegateHandlers) continue;
      names.addAll((node.add ?? const <dynamic>[]).whereType<String>());
    }
    return names;
  }

  /// Total rows the grid claims, read from the size it pushes, or null when
  /// the response did not carry one.
  int? get gridSize {
    int? size;
    for (final List<dynamic> call in execute) {
      if (!_expressionOf(call).contains(r'$connector.updateSize(')) continue;
      final Object? value = call.length > 1 ? call[1] : null;
      if (value is num) size = value.toInt();
    }
    return size;
  }

  /// Update ids the grid wants confirmed. Leaving one pending keeps the rows
  /// it covers active server-side, which stalls the next range request.
  List<int> get updateIds {
    final ids = <int>[];
    for (final List<dynamic> call in execute) {
      if (!_expressionOf(call).contains(r'$connector.confirm(')) continue;
      final Object? value = call.length > 1 ? call[1] : null;
      if (value is num) ids.add(value.toInt());
    }
    return ids;
  }

  /// Ranges the grid blanked out, which is how it reports rows that exist but
  /// were not sent.
  List<({int length, int start})> get clearedRanges {
    final ranges = <({int length, int start})>[];
    for (final List<dynamic> call in execute) {
      if (!_expressionOf(call).contains(r'$connector.clear(')) continue;
      if (call.length < 3) continue;
      final Object? start = call[1];
      final Object? length = call[2];
      if (start is num && length is num) {
        ranges.add((length: length.toInt(), start: start.toInt()));
      }
    }
    return ranges;
  }

  /// The JS Vaadin asked the client to run, which is the last argument.
  static String _expressionOf(List<dynamic> call) {
    final Object? last = call.isEmpty ? null : call.last;
    return last is String ? last : '';
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
