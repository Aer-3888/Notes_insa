import 'package:flutter/material.dart';

import '../../theme/campus_context.dart';
import '../../theme/state_view.dart';
import '../../theme/tokens.dart';
import 'ade_groups.dart';
import 'ade_tree.dart';

/// What the selectable rows offer: one pick, or several.
enum AdeTreeSelection { radio, check }

/// One row per ADE resource, with the tree's two kinds of row kept visually
/// apart.
///
/// A branch navigates and a leaf selects, and they must not look alike: the
/// old picker put a checkbox on every row, so subscribing to a department
/// looked exactly like subscribing to a group while producing every year's
/// timetable at once. Here a branch shows a chevron and how much sits under
/// it, and carries no control at all.
///
/// Shared by the wizard's group step and the advanced picker so the two
/// cannot drift apart. The caller owns the position in the tree and the
/// selection, and this only draws them.
class AdeTreeList extends StatelessWidget {
  const AdeTreeList({
    super.key,
    required this.rows,
    required this.visible,
    required this.selected,
    required this.onToggle,
    required this.onDrill,
    this.mode = AdeTreeSelection.check,
    this.drillable = true,
    this.showPath = false,
    this.headerBefore,
    this.emptyTitle,
    this.emptyBody,
  });

  /// Every row of the category, for the counts and paths. Not what is drawn.
  final List<AdeGroup> rows;

  /// The rows to draw: one level of the tree, or a search result.
  final List<AdeGroup> visible;

  final Set<int> selected;
  final ValueChanged<AdeGroup> onToggle;
  final ValueChanged<AdeGroup> onDrill;
  final AdeTreeSelection mode;

  /// Whether a row with children is somewhere to go rather than something to
  /// pick. False where the level itself is the question, "which formation?",
  /// since every answer there has children and none is a dead end.
  final bool drillable;

  /// Names each row's ancestors underneath it. On by default nowhere, and
  /// required in search: the tree has real duplicates, so `2 GROUPES TP` on
  /// its own does not say which one it is.
  final bool showPath;

  /// A section label to draw above a row, or null for no break. Lets one flat
  /// list say that its halves are different kinds of thing: formations against
  /// masters, your promo's options against the langues everyone can take.
  final String? Function(AdeGroup)? headerBefore;

  final String? emptyTitle;
  final String? emptyBody;

  @override
  Widget build(BuildContext context) {
    if (visible.isEmpty) {
      return StateView(
        icon: Icons.search_off_outlined,
        title: emptyTitle ?? 'Aucun résultat',
        body:
            emptyBody ?? 'Essayez un autre nom de groupe, par exemple S7-INFO.',
      );
    }
    final list = ListView.builder(
      itemCount: visible.length,
      itemBuilder: (context, i) {
        final row = _Row(
          rows: rows,
          group: visible[i],
          selected: selected.contains(visible[i].id),
          mode: mode,
          drillable: drillable,
          showPath: showPath,
          onToggle: onToggle,
          onDrill: onDrill,
        );
        final header = headerBefore?.call(visible[i]);
        if (header == null) return row;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[_SectionHeader(header), row],
        );
      },
    );
    // Selecting is still routed through onToggle rather than handled here,
    // because the caller may need to do more than store an id.
    return mode == AdeTreeSelection.radio
        ? RadioGroup<int>(
            groupValue: selected.isEmpty ? null : selected.first,
            onChanged: (id) {
              if (id == null) return;
              onToggle(visible.firstWhere((g) => g.id == id));
            },
            child: list,
          )
        : list;
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.rows,
    required this.group,
    required this.selected,
    required this.mode,
    required this.drillable,
    required this.showPath,
    required this.onToggle,
    required this.onDrill,
  });

  final List<AdeGroup> rows;
  final AdeGroup group;
  final bool selected;
  final AdeTreeSelection mode;
  final bool drillable;
  final bool showPath;
  final ValueChanged<AdeGroup> onToggle;
  final ValueChanged<AdeGroup> onDrill;

  @override
  Widget build(BuildContext context) {
    // In search the tree is flattened, so a branch is drawn as what it is
    // rather than as somewhere to go: drilling into a row the caller did not
    // navigate to would lose the query.
    final isBranch =
        drillable && !showPath && AdeTree.hasChildren(rows, group.id);
    final subtitle = showPath
        ? AdeTree.pathLabel(rows, group.id)
        : isBranch
        ? _countLabel(AdeTree.descendantCount(rows, group.id))
        : '';

    return ListTile(
      leading: isBranch ? null : _control(),
      title: Text(group.name),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelMedium?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
      trailing: isBranch
          ? Icon(Icons.chevron_right, color: context.scheme.onSurfaceVariant)
          : null,
      onTap: isBranch ? () => onDrill(group) : () => onToggle(group),
    );
  }

  Widget _control() => switch (mode) {
    AdeTreeSelection.radio => Radio<int>(value: group.id),
    AdeTreeSelection.check => Checkbox(
      value: selected,
      onChanged: (_) => onToggle(group),
    ),
  };

  static String _countLabel(int n) => n == 1 ? '1 groupe' : '$n groupes';
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      CampusSpacing.gutter,
      CampusSpacing.x4,
      CampusSpacing.gutter,
      CampusSpacing.x1,
    ),
    child: Text(
      label,
      style: context.text.labelLarge?.copyWith(color: context.scheme.primary),
    ),
  );
}
