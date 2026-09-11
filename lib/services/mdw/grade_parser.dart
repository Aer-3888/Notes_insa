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
  });

  /// Position in the flattened tree, which is the order rows must be read in.
  final int index;
  final String key;
  final int level;
  final bool hasChildren;

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
  static List<GradeRow> rowsOf(VaadinData data) {
    final rows = <GradeRow>[];

    for (final List<dynamic> call in data.execute) {
      if (call.length < 3) continue;

      final Object? index = call[1];
      final Object? payload = call[2];
      if (index is! num || payload is! List) continue;

      for (final Object? entry in payload) {
        if (entry is! Map<String, dynamic>) continue;
        final Object? key = entry['key'];
        if (key is! String) continue;

        final columnNodes = <int>[];
        for (final MapEntry<String, dynamic> field in entry.entries) {
          if (!field.key.startsWith('lr_')) continue;
          final Object? value = field.value;
          if (value is num) columnNodes.add(value.toInt());
        }
        if (columnNodes.isEmpty) continue;

        rows.add(
          GradeRow(
            index: index.toInt(),
            key: key,
            level: (entry['level'] as num?)?.toInt() ?? 0,
            hasChildren: entry['children'] == true,
            columnNodes: columnNodes,
          ),
        );
      }
    }

    rows.sort((GradeRow a, GradeRow b) => a.index.compareTo(b.index));
    return rows;
  }

  /// Builds the tree from [data], or null when it carried no rows.
  ///
  /// Rows are nested by their `level`, so a row belongs to the last row one
  /// level above it. The first column is the label and the rest are values.
  static Grade? parse(VaadinData data) {
    final rows = rowsOf(data);
    if (rows.isEmpty) return null;

    final roots = <Grade>[];
    // Index n holds the grade currently open at level n.
    final stack = <Grade>[];

    for (final GradeRow row in rows) {
      final names = data.nodeValues(row.columnNodes.first);
      if (names.length != 1) continue;

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

    if (roots.isEmpty) return null;
    if (roots.length == 1) return roots.first;

    return Grade(name: '', score: const <String>[], details: roots);
  }

  /// Keys of rows that claim children but arrived without any, which is what
  /// the grid's lazy paging has to be asked for.
  static List<String> missingChildKeys(List<GradeRow> rows) {
    final levels = <int, List<GradeRow>>{};
    for (final GradeRow row in rows) {
      levels.putIfAbsent(row.level, () => <GradeRow>[]).add(row);
    }

    final missing = <String>[];
    for (final GradeRow row in rows) {
      if (!row.hasChildren) continue;
      final deeper = levels[row.level + 1] ?? const <GradeRow>[];
      final hasAny = deeper.any((GradeRow c) => c.index > row.index);
      if (!hasAny) missing.add(row.key);
    }
    return missing;
  }
}
