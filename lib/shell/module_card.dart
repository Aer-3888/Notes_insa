import 'package:flutter/material.dart';

import '../modules/registry.dart';
import '../theme/campus_context.dart';
import '../theme/tokens.dart';

class ModuleCard extends StatelessWidget {
  const ModuleCard({super.key, required this.module, required this.onTap});

  final CampusModule module;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(CampusSpacing.card),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(module.icon, color: context.scheme.onSurfaceVariant),
              const SizedBox(height: CampusSpacing.x3),
              Text(module.label, style: context.text.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
