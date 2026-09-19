import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../modules/associations/association_notification_help_screen.dart';
import '../modules/associations/association_reminder_provider.dart';
import '../modules/associations/association_reminders.dart';
import '../modules/grades/grades_provider.dart';
import '../modules/grades/grades_settings_screen.dart';
import '../modules/grades/raw_json_viewer_screen.dart';
import '../modules/schedule/group_picker_screen.dart';
import '../modules/schedule/schedule_colors_screen.dart';
import '../modules/schedule/schedule_view_mode.dart';
import '../modules/schedule/schedule_width_screen.dart';
import '../providers/auth_providers.dart';
import '../providers/package_info_provider.dart';
import '../providers/theme_mode_provider.dart';
import '../theme/campus_context.dart';
import '../theme/tokens.dart';

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
    final mode = ref.watch(themeModeProvider);
    final reminderLead = ref.watch(associationReminderLeadProvider);
    final dayWidth = ref.watch(scheduleDayWidthProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: CampusSpacing.x8),
        children: [
          const _SectionHeader('Emploi du temps'),
          ListTile(
            leading: const Icon(Icons.group_outlined),
            title: const Text('Mes groupes'),
            subtitle: const Text('Choisir les groupes affichés'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const GroupPickerScreen(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Couleurs des cours'),
            subtitle: const Text('Choisir les teintes de l’emploi du temps'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ScheduleColorsScreen(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.view_column_outlined),
            title: const Text('Largeur des jours'),
            subtitle: Text('Vue Semaine : ${scheduleDayWidthLabel(dayWidth)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ScheduleWidthScreen(),
              ),
            ),
          ),

          const _SectionHeader('Apparence'),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CampusSpacing.gutter,
              vertical: CampusSpacing.x2,
            ),
            child: SegmentedButton<ThemeMode>(
              segments: const <ButtonSegment<ThemeMode>>[
                ButtonSegment(value: ThemeMode.system, label: Text('Système')),
                ButtonSegment(value: ThemeMode.light, label: Text('Clair')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Sombre')),
              ],
              selected: <ThemeMode>{mode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => unawaited(
                ref.read(themeModeProvider.notifier).set(selection.first),
              ),
            ),
          ),

          const _SectionHeader('Associations'),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CampusSpacing.gutter,
              CampusSpacing.x1,
              CampusSpacing.gutter,
              CampusSpacing.x1,
            ),
            child: Text(
              'Rappel avant un évènement d’une asso suivie',
              style: context.text.bodyMedium?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CampusSpacing.gutter,
              vertical: CampusSpacing.x2,
            ),
            child: SegmentedButton<AssociationReminderLead>(
              segments: <ButtonSegment<AssociationReminderLead>>[
                for (final lead in AssociationReminderLead.values)
                  ButtonSegment(value: lead, label: Text(lead.label)),
              ],
              selected: <AssociationReminderLead>{reminderLead},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => unawaited(
                ref
                    .read(associationReminderLeadProvider.notifier)
                    .set(selection.first),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Rappels non reçus ou en retard ?'),
            subtitle: const Text('Aide pour les notifications et la batterie'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AssociationNotificationHelpScreen(),
              ),
            ),
          ),

          if (hasCreds) ...[
            const _SectionHeader('Notes'),
            ListTile(
              leading: const Icon(Icons.sync_outlined),
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
            const _SectionHeader('Compte'),
            ListTile(
              leading: Icon(Icons.logout, color: context.scheme.error),
              title: Text(
                'Se déconnecter',
                style: context.text.bodyLarge?.copyWith(
                  color: context.scheme.error,
                ),
              ),
              onTap: () => _confirmLogout(context, ref),
            ),
          ],

          const _SectionHeader('À propos'),
          const _VersionTile(),
          const ListTile(
            leading: Icon(Icons.schedule),
            title: Text('Source des horaires'),
            subtitle: Text(
              'Les horaires proviennent du service ADE de l’INSA Rennes.',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.mail_outline),
            title: Text('Contact'),
            subtitle: Text('theo.phan.quoc.huy@gmail.com'),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      CampusSpacing.gutter,
      CampusSpacing.x6,
      CampusSpacing.gutter,
      CampusSpacing.x1,
    ),
    child: Text(
      label,
      style: context.text.labelMedium?.copyWith(
        color: context.scheme.onSurfaceVariant,
      ),
    ),
  );
}

/// Seven taps on the version reveal the raw JSON viewer, the way Android
/// reveals developer options. Nothing else in the list mentions it.
class _VersionTile extends ConsumerStatefulWidget {
  const _VersionTile();

  @override
  ConsumerState<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends ConsumerState<_VersionTile> {
  static const int _tapsToReveal = 7;
  int _taps = 0;
  bool _revealed = false;

  void _onTap() {
    if (_revealed) return;
    _taps++;
    if (_taps < _tapsToReveal) return;
    setState(() => _revealed = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Outils développeur activés')));
  }

  @override
  Widget build(BuildContext context) {
    final version = ref.watch(packageInfoProvider);
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Version'),
          subtitle: version.when(
            data: (info) => Text('${info.version}+${info.buildNumber}'),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const Text('inconnue'),
          ),
          onTap: _onTap,
        ),
        if (_revealed)
          ListTile(
            leading: const Icon(Icons.data_object_outlined),
            title: const Text('JSON brut'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const RawJsonViewerScreen(),
              ),
            ),
          ),
      ],
    );
  }
}
