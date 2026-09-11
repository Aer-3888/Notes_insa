/// A node in the grade tree, serialized exactly as the native bridge did so
/// the rest of the app keeps parsing it unchanged.
class Grade {
  Grade({
    required this.name,
    required this.score,
    required this.details,
    this.coeff,
    this.key = '',
  });

  final String name;

  /// The values the row carries: a mark, or "VAL" / "NON-VAL" / "Aucun
  /// résultats". A row can carry more than one.
  final List<String> score;

  /// Filled in separately by the coefficient lookup.
  String? coeff;

  final List<Grade> details;

  /// The Vaadin item key, needed to ask for children or a coefficient.
  final String key;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'score': score,
    if (coeff != null && coeff!.isNotEmpty) 'coeff': coeff,
    'details': details.map((Grade g) => g.toJson()).toList(),
  };

  /// Walks the tree depth-first, passing each node and its depth.
  void forEach(void Function(int depth, Grade grade) visit, [int depth = 0]) {
    visit(depth, this);
    for (final Grade child in details) {
      child.forEach(visit, depth + 1);
    }
  }
}
