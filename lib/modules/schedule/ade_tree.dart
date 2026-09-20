import '../../core/search_text.dart';
import 'ade_groups.dart';

/// Navigation over the ADE resource tree.
///
/// ADE nests by department, then semester, then group, then subgroup (INFO >
/// S7-INFO > S7-INFO-G1 > S7-INFO-G1-1), and STPI goes two levels deeper still.
/// Two properties of that tree drive every screen that reads this file:
///
///  - a parent's timetable is the exact union of its subtree, so picking a
///    formation means every group of every year at once,
///  - a leaf already carries the promo-wide CMs, so one leaf is a complete
///    timetable for its semester.
///
/// Together they mean the useful pick is the deepest row, and the only thing a
/// student needs on top of it are the branches that sit *beside* their path:
/// options, ouvertures, langues. [electivesFor] is what finds those.
///
/// Every function here is pure, so the pickers can be tested without a network
/// or a widget tree.
class AdeTree {
  const AdeTree._();

  /// Direct children of [parentId], or the top level when it is null.
  static List<AdeGroup> childrenOf(List<AdeGroup> rows, int? parentId) {
    final out = rows.where((g) => g.parentId == parentId).toList();
    out.sort((a, b) => compareNatural(a.name, b.name));
    return out;
  }

  /// Orders names the way a human reads them, so S5 comes before S10.
  ///
  /// A plain string compare puts `S10-INFO` above `S5-INFO`, which is how the
  /// semester lists used to open, and it is wrong in eight of the eighteen
  /// formations. GPM only escaped it by writing `S05`. Comparing digit runs
  /// as numbers fixes both spellings with one rule, and keeps `Grp TP A3-2`
  /// ahead of `Grp TP A3-10` for free.
  ///
  /// Text runs are folded first, so case and accents do not reorder anything
  /// that [search] considers the same.
  static int compareNatural(String a, String b) {
    final ra = _runs(a);
    final rb = _runs(b);
    for (var i = 0; i < ra.length && i < rb.length; i++) {
      final x = ra[i];
      final y = rb[i];
      if (x.isDigits != y.isDigits) {
        // Text sorts before the digits at the same position, so `S7-INFO`
        // stays above `S7-INFO-G1` rather than interleaving with it.
        return x.isDigits ? 1 : -1;
      }
      final cmp = x.isDigits
          ? _compareNumeric(x.text, y.text)
          : foldForSearch(x.text).compareTo(foldForSearch(y.text));
      if (cmp != 0) return cmp;
    }
    if (ra.length != rb.length) return ra.length - rb.length;
    // Same under folding: fall back to the raw names so the order is total
    // and a rebuild never reshuffles two rows.
    return a.compareTo(b);
  }

  /// Compares two digit runs as numbers without parsing them, so a run longer
  /// than an int still orders correctly.
  static int _compareNumeric(String a, String b) {
    final x = a.replaceFirst(RegExp(r'^0+(?=.)'), '');
    final y = b.replaceFirst(RegExp(r'^0+(?=.)'), '');
    if (x.length != y.length) return x.length - y.length;
    return x.compareTo(y);
  }

  static List<({String text, bool isDigits})> _runs(String s) {
    final out = <({String text, bool isDigits})>[];
    var start = 0;
    while (start < s.length) {
      final digits = _isDigit(s.codeUnitAt(start));
      var end = start + 1;
      while (end < s.length && _isDigit(s.codeUnitAt(end)) == digits) {
        end++;
      }
      out.add((text: s.substring(start, end), isDigits: digits));
      start = end;
    }
    return out;
  }

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  static bool hasChildren(List<AdeGroup> rows, int id) =>
      rows.any((g) => g.parentId == id);

  /// [id] and its ancestors, outermost first. Empty when [id] is unknown.
  static List<AdeGroup> pathTo(List<AdeGroup> rows, int id) {
    final byId = _index(rows);
    final path = <AdeGroup>[];
    var current = byId[id];
    while (current != null) {
      path.insert(0, current);
      final parent = current.parentId;
      current = parent == null ? null : byId[parent];
      if (path.length > 12) break; // defensive: never loop on malformed data
    }
    return path;
  }

  /// Case- and accent-insensitive contains search over group names.
  static List<AdeGroup> search(List<AdeGroup> rows, String query) {
    final q = foldForSearch(query);
    if (q.isEmpty) return rows;
    final out = rows.where((g) => foldForSearch(g.name).contains(q)).toList();
    out.sort((a, b) => compareNatural(a.name, b.name));
    return out;
  }

  /// How far [id] sits from the top level: 0 for a department, 3 for
  /// S7-INFO-G1-1, 5 for the deepest STPI TP group. -1 when [id] is unknown.
  static int depthOf(List<AdeGroup> rows, int id) =>
      pathTo(rows, id).length - 1;

  /// Every row under [id], at any depth.
  ///
  /// This is the number that tells a student a row is too broad to pick, and
  /// it costs nothing: the alternative, a real event count, would mean one ADE
  /// request per resource.
  static int descendantCount(List<AdeGroup> rows, int id) {
    final byParent = <int?, List<AdeGroup>>{};
    for (final g in rows) {
      byParent.putIfAbsent(g.parentId, () => <AdeGroup>[]).add(g);
    }
    var total = 0;
    final queue = <int>[id];
    while (queue.isNotEmpty) {
      final children = byParent[queue.removeLast()] ?? const <AdeGroup>[];
      total += children.length;
      for (final c in children) {
        queue.add(c.id);
      }
      if (total > rows.length) break; // defensive: never loop on a cycle
    }
    return total;
  }

  /// The promo [id] belongs to: its depth-1 ancestor, or itself when it is
  /// already one. Null for a department, which has no promo above it.
  static AdeGroup? semesterNodeFor(List<AdeGroup> rows, int id) {
    final path = pathTo(rows, id);
    return path.length < 2 ? null : path[1];
  }

  /// The heading a selected row belongs under: its semester when it has one,
  /// otherwise the formation or pool it hangs from.
  ///
  /// S7-INFO-G1-1 and S7-INFO-langues both land under S7-INFO. LV2- LV3 sits
  /// one level below HUMA and has no semester, so it lands under HUMA.
  static AdeGroup? groupingNodeFor(List<AdeGroup> rows, int id) {
    final path = pathTo(rows, id);
    if (path.isEmpty) return null;
    return path.length >= 3 ? path[1] : path.first;
  }

  /// The branches a student picks *in addition* to their base group.
  ///
  /// Options, ouvertures and langues hang off the promo beside the group
  /// branch, so they never come with the base pick however deep it goes. This
  /// returns the promo's children minus the one the base sits under.
  ///
  /// The parallel group branch (S7-INFO-G2 next to G1) is left in: it is a
  /// legitimate, if uncommon, pick, and filtering it would need a name
  /// heuristic that the data does not support.
  static List<AdeGroup> electivesFor(List<AdeGroup> rows, int baseId) {
    final semester = semesterNodeFor(rows, baseId);
    if (semester == null) return const <AdeGroup>[];
    final onPath = pathTo(rows, baseId).map((g) => g.id).toSet();
    return childrenOf(
      rows,
      semester.id,
    ).where((g) => !onPath.contains(g.id)).toList();
  }

  /// The same, for several bases at once, de-duplicated.
  ///
  /// A student following two semesters of the year has electives in both, and
  /// two bases inside one semester (S9-INFO's separate TD and TP branches)
  /// must not make that semester offer its branches twice.
  static List<AdeGroup> electivesForAll(
    List<AdeGroup> rows,
    Iterable<int> baseIds,
  ) {
    final onPath = <int>{
      for (final id in baseIds) ...pathTo(rows, id).map((g) => g.id),
    };
    final out = <int, AdeGroup>{};
    for (final id in baseIds) {
      final semester = semesterNodeFor(rows, id);
      if (semester == null) continue;
      for (final g in childrenOf(rows, semester.id)) {
        if (!onPath.contains(g.id)) out[g.id] = g;
      }
    }
    return out.values.toList();
  }

  /// The ancestors of [id] as one line, for a subtitle under its name.
  ///
  /// Required rather than decorative: the tree has real duplicates. `2 GROUPES
  /// TP` appears dozens of times, `DROM` twice, and `S3-STPI-C` exists as both
  /// a parent and its own child, so a search result without its path cannot be
  /// told from another.
  ///
  /// [from] drops everything up to and including that ancestor, for a list
  /// that already says where it is. Under a heading of S7-INFO, the useful
  /// part of S7-INFO-G1-1's path is S7-INFO-G1 alone.
  static String pathLabel(List<AdeGroup> rows, int id, {int? from}) {
    final path = pathTo(rows, id);
    if (path.length < 2) return '';
    var ancestors = path.take(path.length - 1);
    if (from != null) {
      ancestors = ancestors.any((g) => g.id == from)
          ? ancestors.skipWhile((g) => g.id != from).skip(1)
          : ancestors;
    }
    return ancestors.map((g) => g.name).join(' › ');
  }

  /// Whether a top-level node nests by semester, which is what separates a
  /// formation from a master's programme or a parcours.
  ///
  /// Two is the threshold rather than one: a single stray `S9-…` child would
  /// otherwise promote a programme that merely names its year.
  static bool hasSemesters(List<AdeGroup> rows, int id) =>
      childrenOf(rows, id).where((g) => _semester.hasMatch(g.name)).length >= 2;

  /// `S5-INFO`, `S05-GPM`, `DC-AI -S1`. Not `SPIR-1-`, `MASTER MMGC -SR3` or
  /// `M&N09-CIV`, whose digits belong to something else.
  static final RegExp _semester = RegExp(
    r'(?:^|[^A-Za-z0-9])S\s*\d{1,2}(?![0-9])',
    caseSensitive: false,
  );

  /// The formations a student starts from: the ten that nest by semester.
  static List<AdeGroup> formations(List<AdeGroup> rows) => visibleRoots(rows)
      .where((g) => !crossCuttingRoots.contains(g.name))
      .where((g) => hasSemesters(rows, g.id))
      .toList();

  /// Masters and parcours: their own cohorts, but with no semester level, so
  /// the wizard goes straight from here to picking a group.
  static List<AdeGroup> otherTracks(List<AdeGroup> rows) => visibleRoots(rows)
      .where((g) => !crossCuttingRoots.contains(g.name))
      .where((g) => !hasSemesters(rows, g.id))
      .toList();

  /// Branches any student can add whatever their formation: LV2, anglais
  /// transversal, arts-études.
  static List<AdeGroup> crossCutting(List<AdeGroup> rows) => <AdeGroup>[
    for (final root in visibleRoots(rows))
      if (crossCuttingRoots.contains(root.name)) ...childrenOf(rows, root.id),
  ];

  /// Top-level nodes that are a pool every formation draws on rather than a
  /// cohort of their own.
  ///
  /// Not derivable from the tree. HUMA looks exactly like MASTER-EO from here,
  /// a root with no semester children, and only INSA's own organisation says
  /// one is a cross-cutting teaching department and the other a programme.
  /// Named rather than guessed, so the reason is visible.
  static const Set<String> crossCuttingRoots = <String>{'HUMA'};

  /// Every top-level node worth offering anywhere.
  ///
  /// ADE carries a few individual students at the top level alongside the real
  /// formations. The filter is deliberately narrow, only the `Étudiant 1234`
  /// shape, because a broader rule would start eating small but real entries
  /// such as RIT or MIE.
  static List<AdeGroup> visibleRoots(List<AdeGroup> rows) =>
      childrenOf(rows, null).where((g) => !_isIndividual(g.name)).toList();

  static final RegExp _individual = RegExp(
    r'^étudiant\s*\d+$',
    caseSensitive: false,
  );

  static bool _isIndividual(String name) => _individual.hasMatch(name.trim());

  static Map<int, AdeGroup> _index(List<AdeGroup> rows) => <int, AdeGroup>{
    for (final g in rows) g.id: g,
  };
}
