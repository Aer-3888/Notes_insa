import 'package:flutter/material.dart';

import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'ade_groups.dart';

/// Where the current list sits in the tree, and a way back to any level of it.
///
/// Shared by the wizard's group step and the advanced picker: both drill, and
/// both need climbing to be a visible control rather than a hidden meaning
/// attached to the system back button.
class AdeBreadcrumb extends StatelessWidget {
  const AdeBreadcrumb({
    super.key,
    required this.path,
    required this.onRoot,
    required this.onTap,
    this.rootLabel = 'Tout',
  });

  /// Outermost first, ending at the level being shown.
  final List<AdeGroup> path;
  final VoidCallback onRoot;
  final ValueChanged<AdeGroup> onTap;
  final String rootLabel;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 34,
    child: ListView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: CampusSpacing.x3),
      // Laid out from the right, so a path deeper than the screen keeps the
      // level you are actually in on screen instead of scrolling it off the
      // edge. Children therefore run innermost first and read
      // "Tout › INFO › S7-INFO".
      children: <Widget>[
        for (final g in path.reversed) ...<Widget>[
          TextButton(onPressed: () => onTap(g), child: Text(g.name)),
          Icon(
            Icons.chevron_right,
            size: 16,
            color: context.scheme.onSurfaceVariant,
          ),
        ],
        TextButton(onPressed: onRoot, child: Text(rootLabel)),
      ],
    ),
  );
}
