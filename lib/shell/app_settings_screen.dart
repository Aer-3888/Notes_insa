import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_colors.dart';
import '../modules/grades/grades_provider.dart';
import '../modules/grades/grades_settings_screen.dart';
import '../modules/grades/raw_json_viewer_screen.dart';
import '../modules/schedule/group_picker_screen.dart';
import '../providers/auth_providers.dart';
import '../providers/package_info_provider.dart';

/// The app's single settings screen.
///
/// Every module's preferences live here rather than behind a per-module drawer,
/// so grades reads as one part of the campus app instead of a separate app.
/// Module-specific sections appear only when they apply: the grades section is
/// hidden entirely for someone who has never signed in.
class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasCreds = ref.watch(hasCredentialsProvider).value ?? false;

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
          const _SectionTitle('Emploi du temps'),
          _Card(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.group_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Mes groupes'),
                subtitle: const Text('Choisir les groupes affichés'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const GroupPickerScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (hasCreds) ...[
            const _SectionTitle('Notes'),
            _Card(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.sync_outlined,
                    color: AppColors.primary,
                  ),
                  title: const Text('Synchronisation et partage'),
                  subtitle: const Text(
                    'Rafraîchissement en arrière-plan, notifications, partage',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const GradesSettingsScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.data_object_outlined,
                    color: AppColors.primary,
                  ),
                  title: const Text('JSON brut'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RawJsonViewerScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.logout, color: Colors.red.shade400),
                  title: Text(
                    'Déconnexion',
                    style: TextStyle(color: Colors.red.shade400),
                  ),
                  onTap: () => _confirmLogout(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],

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
                title: Text('Source des horaires'),
                subtitle: Text(
                  'Les horaires proviennent du service ADE de l’INSA Rennes.',
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

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text(
          'Vos identifiants et vos notes enregistrées seront effacés de cet '
          'appareil. Le reste de l’application continue de fonctionner.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    // Leave settings first: the shell takes over with its logout screen.
    Navigator.of(context).popUntil((route) => route.isFirst);
    unawaited(ref.read(gradesProvider.notifier).logout());
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
