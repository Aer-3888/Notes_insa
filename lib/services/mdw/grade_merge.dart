/// Merge [incoming] nodes into [target], deduplicating by name. When a node
/// with the same name already exists and both carry child `details` lists
/// (e.g. two "ANNEE 3" wrappers from different cards holding different
/// semesters), their children are merged recursively instead of dropping the
/// second wrapper wholesale , otherwise distinct semesters would be lost.
void mergeGradeDetails(List<dynamic> target, List<dynamic> incoming) {
  for (final item in incoming) {
    if (item is! Map<String, dynamic>) {
      target.add(item);
      continue;
    }
    final name = item['name'] as String?;
    if (name == null) {
      target.add(item);
      continue;
    }

    final existing = target.firstWhere(
      (e) => e is Map<String, dynamic> && e['name'] == name,
      orElse: () => null,
    );

    if (existing == null) {
      target.add(item);
      continue;
    }

    // Same name: if both are containers, merge their children; otherwise the
    // node is a true duplicate (same leaf) and is skipped.
    if (existing is Map<String, dynamic> &&
        existing['details'] is List &&
        item['details'] is List) {
      mergeGradeDetails(
        existing['details'] as List<dynamic>,
        item['details'] as List<dynamic>,
      );
    }
  }
}
