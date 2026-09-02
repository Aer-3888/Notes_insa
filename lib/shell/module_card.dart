import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../modules/registry.dart';

class ModuleCard extends StatelessWidget {
  const ModuleCard({super.key, required this.module, this.onTap});

  final CampusModule module;

  /// Null for a module that is not yet built.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final teaser = switch (module) {
      ComingSoonModule(:final teaser) => teaser,
      ReadyModule() => null,
    };
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(module.icon, color: AppColors.primary, size: 26),
                const SizedBox(height: 12),
                Text(
                  module.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                if (teaser != null) ...[
                  const SizedBox(height: 6),
                  Expanded(
                    child: Text(
                      teaser,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const Text(
                    'Bientôt disponible',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
