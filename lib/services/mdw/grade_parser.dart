import 'grade.dart';
import 'vaadin_nodes.dart';
import 'vaadin_types.dart';

/// One grid row as Vaadin delivers it.
class GradeRow {
  GradeRow({
    required this.index,
    required this.key,
    required this.level,
    required this.hasChildren,
    required this.columnNodes,
    this.parentKey,
  });

  /// Position among its siblings for a row fetched through [parentKey], and
  /// position in the flattened tree for one that arrived with the page itself.
  final int index;
  final String key;
  final int level;
  final bool hasChildren;

  /// Set when the row came from a request for one parent's children. The grid
  /// then indexes it within that parent rather than within the whole tree.
  final String? parentKey;

  /// Node ids holding each column's text, in column order.
  final List<int> columnNodes;
}

/// Turns a UIDL response into the grade tree.
///
/// Rows arrive as arguments to the JS calls in `execute`, shaped
/// `[{@v-node}, index, [row], expression]`, and each row names its columns by
/// node id rather than carrying text. The text lives in `changes`, so every
/// column is resolved through the node lookup.
class GradeParser {
  /// Reads the rows out of [data], ordered by their position in the tree.
  ///
  /// The grid sends a row set either for the tree as a whole or for one
  /// parent's children, and the two differ only in the arity of the call, so
  /// the expression is what tells them apart.
  static List<GradeRow> rowsOf(VaadinData data) {
    final rows = <GradeRow>[];

    for (final List<dynamic> call in data.execute) {
      if (call.length < 3) continue;

      final Object? index = call[1];
      final Object? payload = call[2];
      if (index is! num || payload is! List) continue;

      final Object? expression = call.last;
      final String? parentKey =
          expression is String &&
              expression.contains(r'$3') &&
              call.length > 4 &&
              call[3] is String
          ? call[3] as String
          : null;

      for (final Object? entry in payload) {
        if (entry is! Map<String, dynamic>) continue;
        final Object? key = entry['key'];
        if (key is! String) continue;

        final columnNodes = <int>[];
        var columnChildren = false;
        for (final MapEntry<String, dynamic> field in entry.entries) {
          if (!field.key.startsWith('lr_')) continue;
          final Object? value = field.value;
          if (value is num) columnNodes.add(value.toInt());
          // Older MDW hung the flag off the label column instead of the row.
          if (field.key.endsWith('_children') && value == true) {
            columnChildren = true;
          }
        }
        if (columnNodes.isEmpty) continue;

        // A row names its parent outright when MDW sends it that way. The
        // call argument covers the shape that does not.
        final Object? named = entry['parentUniqueKey'];
        final String? parent = named is String && named.isNotEmpty
            ? named
            : parentKey;

        rows.add(
          GradeRow(
            index: index.toInt(),
            key: key,
            level: (entry['level'] as num?)?.toInt() ?? 0,
            hasChildren: entry['children'] == true || columnChildren,
            columnNodes: columnNodes,
            parentKey: parent,
          ),
        );
      }
    }

    // Only the tree-wide rows share one index space. A parent's children are
    // numbered within that parent and are placed by key later.
    final flat = rows.where((GradeRow r) => r.parentKey == null).toList()
      ..sort((GradeRow a, GradeRow b) => a.index.compareTo(b.index));
    final lazy = rows.where((GradeRow r) => r.parentKey != null).toList()
      ..sort((GradeRow a, GradeRow b) => a.index.compareTo(b.index));

    // A widened window or a re-asked parent repeats rows already in hand, and
    // counting those again would read as progress.
    final seen = <String>{};
    return <GradeRow>[
      for (final GradeRow row in <GradeRow>[...flat, ...lazy])
        if (seen.add(row.key)) row,
    ];
  }

  /// Builds the tree from [data], or null when it carried no rows.
  ///
  /// Rows that came with the tree are nested by their `level`, so a row belongs
  /// to the last row one level above it. Rows fetched for a single parent name
  /// it, and are hung off that parent once it exists.
  static Grade? parse(VaadinData data) {
    final rows = rowsOf(data);
    if (rows.isEmpty) return null;

    final byKey = <String, Grade>{};
    final roots = <Grade>[];
    // Index n holds the grade currently open at level n.
    final stack = <Grade>[];

    Grade? build(GradeRow row) {
      final names = data.nodeValues(row.columnNodes.first);
      if (names.length != 1) return null;

      final values = <String>[];
      for (final int node in row.columnNodes.skip(1)) {
        values.addAll(data.nodeValues(node));
      }

      final grade = Grade(
        name: names.first,
        score: values,
        details: <Grade>[],
        key: row.key,
      );
      if (row.key.isNotEmpty) byKey[row.key] = grade;
      return grade;
    }

    for (final GradeRow row in rows.where(
      (GradeRow r) => r.parentKey == null,
    )) {
      final Grade? grade = build(row);
      if (grade == null) continue;

      if (row.level <= 0 || stack.isEmpty) {
        roots.add(grade);
        stack
          ..clear()
          ..add(grade);
        continue;
      }

      // A level deeper than the open row means a row was skipped; attach to
      // the deepest row we do have rather than dropping the subtree.
      final parentLevel = row.level - 1 < stack.length
          ? row.level - 1
          : stack.length - 1;
      stack[parentLevel].details.add(grade);

      stack.length = parentLevel + 1;
      stack.add(grade);
    }

    // A page of children can name a parent that another page delivered, so keep
    // going while parents keep turning up.
    final pending = rows.where((GradeRow r) => r.parentKey != null).toList();
    while (pending.isNotEmpty) {
      final placed = <GradeRow>[];
      for (final GradeRow row in pending) {
        final Grade? parent = byKey[row.parentKey];
        if (parent == null) continue;
        placed.add(row);
        // A page can repeat a row the tree already carried, and taking it
        // again would duplicate the grade under its parent.
        if (byKey.containsKey(row.key)) continue;
        final Grade? grade = build(row);
        if (grade != null) parent.details.add(grade);
      }
      if (placed.isEmpty) break;
      pending.removeWhere(placed.contains);
    }

    if (roots.isEmpty) return null;
    if (roots.length == 1) return roots.first;

    return Grade(name: '', score: const <String>[], details: roots);
  }

  /// Keys of rows that claim children but arrived without any, which is what
  /// the grid's lazy paging has to be asked for.
  ///
  /// In the flat list a row's first child sits immediately after it, so the row
  /// at the next index settles it. Looking further ahead would count a later
  /// sibling's children as this row's.
  static List<String> missingChildKeys(List<GradeRow> rows) {
    final flatByIndex = <int, GradeRow>{
      for (final GradeRow row in rows)
        if (row.parentKey == null) row.index: row,
    };
    final named = <String>{
      for (final GradeRow row in rows)
        if (row.parentKey != null) row.parentKey!,
    };

    final missing = <String>[];
    for (final GradeRow row in rows) {
      if (!row.hasChildren || named.contains(row.key)) continue;
      if (row.parentKey == null) {
        final GradeRow? next = flatByIndex[row.index + 1];
        if (next != null && next.level > row.level) continue;
      }
      missing.add(row.key);
    }
    return missing;
  }
}
