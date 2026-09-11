import 'package:flutter/material.dart';

import '../modules/registry.dart';
import '../theme/campus_context.dart';
import '../theme/tokens.dart';
import 'home_layout_provider.dart';

class ModuleCard extends StatelessWidget {
  const ModuleCard({
    super.key,
    required this.module,
    required this.onTap,
    this.size = HomeCardSize.square,
  });

  final CampusModule module;
  final VoidCallback onTap;
  final HomeCardSize size;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: _content(context)),
    );
  }

  Widget _content(BuildContext context) => switch (size) {
    HomeCardSize.dot => Tooltip(
      message: module.label,
      child: Center(
        child: Icon(module.icon, color: context.scheme.onSurfaceVariant),
      ),
    ),
    HomeCardSize.horizontal => Padding(
      padding: const EdgeInsets.symmetric(horizontal: CampusSpacing.x3),
      child: Row(
        children: <Widget>[
          Icon(module.icon, color: context.scheme.onSurfaceVariant),
          const SizedBox(width: CampusSpacing.x2),
          Expanded(
            child: Text(
              module.label,
              style: context.text.labelLarge,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
    HomeCardSize.square || HomeCardSize.full => Padding(
      padding: const EdgeInsets.all(CampusSpacing.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Icon(module.icon, color: context.scheme.onSurfaceVariant),
          const SizedBox(height: CampusSpacing.x3),
          Text(module.label, style: context.text.titleMedium),
        ],
      ),
    ),
  };
}
