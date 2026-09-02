import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_colors.dart';
import '../providers/package_info_provider.dart';

/// Settings that belong to the app rather than to any one module, so they stay
/// reachable from the hub by a user who has never signed in.
///
/// Module-specific settings live with their module. The grades module keeps its
/// own screen for background fetch, cohort sharing and notifications.
class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Paramètres'),
        foregroundColor: Colors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColors.headerGradient,
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('À propos'),
          _Card(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.info_outline,
                  color: AppColors.primary,
                ),
                title: const Text('Version'),
                subtitle: ref
                    .watch(packageInfoProvider)
                    .when(
                      data: (info) =>
                          Text('${info.version}+${info.buildNumber}'),
                      loading: () => const Text('...'),
                      error: (_, _) => const Text('inconnue'),
                    ),
              ),
              const Divider(height: 1),
              const ListTile(
                leading: Icon(Icons.schedule, color: AppColors.primary),
                title: Text('Emploi du temps'),
                subtitle: Text(
                  'Les horaires proviennent du service ADE de l’INSA '
                  'Rennes. Pour toute question sur cette source, contactez '
                  'l’adresse ci-dessous.',
                ),
              ),
              const Divider(height: 1),
              const ListTile(
                leading: Icon(Icons.mail_outline, color: AppColors.primary),
                title: Text('Contact'),
                subtitle: Text('theo.phan.quoc.huy@gmail.com'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(children: children),
  );
}
