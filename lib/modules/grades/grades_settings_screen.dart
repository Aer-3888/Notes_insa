import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../providers/settings_provider.dart';
import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'grades_provider.dart';
import '../../services/averages_service.dart';

String _intervalLabel(int minutes) =>
    minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h';

/// Grades module settings: background fetch, cohort sharing and the
/// notification permission. App-level settings live in shell/app_settings_screen.dart.
class GradesSettingsScreen extends ConsumerWidget {
  const GradesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(settingsProvider);
    final availableIntervals = ref.watch(availableIntervalsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Synchronisation et partage')),
      body: settingsState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: CampusSpacing.x2),
              children: [
                const _NotificationPermissionTile(),
                const Divider(),

                // Sharing consent
                Padding(
                  padding: const EdgeInsets.all(CampusSpacing.gutter),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.people_outline,
                            color: context.scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: CampusSpacing.x3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Partage anonyme',
                                  style: context.text.titleMedium,
                                ),
                                Text(
                                  'Contribuer aux moyennes de promo',
                                  style: context.text.bodyMedium?.copyWith(
                                    color: context.scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: settingsState.sharingConsent,
                            onChanged: (value) {
                              ref
                                  .read(settingsProvider.notifier)
                                  .setSharingConsent(value);
                            },
                          ),
                        ],
                      ),
                      if (!settingsState.sharingConsent) ...[
                        const SizedBox(height: CampusSpacing.x2),
                        Text(
                          'Vos notes ne sont pas partagées.',
                          style: context.text.labelMedium?.copyWith(
                            color: context.scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Force send data
                if (settingsState.sharingConsent)
                  ListTile(
                    leading: const Icon(Icons.cloud_upload_outlined),
                    title: const Text('Forcer l’envoi des données'),
                    subtitle: const Text(
                      'Mettre à jour manuellement vos moyennes',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => unawaited(_forceSend(context, ref)),
                  ),
                const Divider(),

                // Background fetch
                Padding(
                  padding: const EdgeInsets.all(CampusSpacing.gutter),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Intervalle de mise à jour',
                                  style: context.text.titleMedium,
                                ),
                                Text(
                                  'Fréquence de vérification des nouvelles notes',
                                  style: context.text.bodyMedium?.copyWith(
                                    color: context.scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: settingsState.fetchEnabled,
                            onChanged: (enabled) async {
                              try {
                                await ref
                                    .read(settingsProvider.notifier)
                                    .setFetchEnabled(enabled);
                              } catch (_) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Impossible de modifier la mise à jour en arrière-plan.',
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: CampusSpacing.x5),
                      IgnorePointer(
                        ignoring: !settingsState.fetchEnabled,
                        child: _IntervalSelector(
                          intervals: availableIntervals,
                          selected: settingsState.fetchInterval,
                          enabled: settingsState.fetchEnabled,
                          onChanged: (v) async {
                            try {
                              await ref
                                  .read(settingsProvider.notifier)
                                  .setFetchInterval(v);
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Impossible de modifier la fréquence de mise à jour.',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _forceSend(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final gradesJson = ref.read(gradesProvider).jsonData;
    if (gradesJson == '{}' || gradesJson.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Aucune donnée à envoyer')),
      );
      return;
    }

    messenger.showSnackBar(
      const SnackBar(
        content: Text('Envoi des données…'),
        duration: Duration(seconds: 1),
      ),
    );

    try {
      await AveragesService.submitAllSemesters(gradesJson);
      messenger.showSnackBar(const SnackBar(content: Text('Données envoyées')));
    } catch (_) {
      // The exception text is for the log, not the user: it names internals
      // they cannot act on.
      messenger.showSnackBar(
        const SnackBar(content: Text('Envoi impossible. Réessayez plus tard.')),
      );
    }
  }
}

class _IntervalSelector extends StatelessWidget {
  final List<int> intervals;
  final int selected;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const _IntervalSelector({
    required this.intervals,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final value = intervals.contains(selected) ? selected : intervals.first;
    return SegmentedButton<int>(
      segments: [
        for (final i in intervals)
          ButtonSegment<int>(
            value: i,
            label: Text(_intervalLabel(i)),
            enabled: enabled,
          ),
      ],
      selected: <int>{value},
      showSelectedIcon: false,
      onSelectionChanged: (choice) => onChanged(choice.first),
    );
  }
}

class _NotificationPermissionTile extends StatefulWidget {
  const _NotificationPermissionTile();

  @override
  State<_NotificationPermissionTile> createState() =>
      _NotificationPermissionTileState();
}

class _NotificationPermissionTileState
    extends State<_NotificationPermissionTile>
    with WidgetsBindingObserver {
  PermissionStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermission();
  }

  Future<void> _checkPermission() async {
    final status = await Permission.notification.status;
    if (mounted) setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    final isUnknown = _status == null;
    final isGranted = _status?.isGranted ?? false;

    return ListTile(
      leading: Icon(
        isUnknown
            ? Icons.notifications_outlined
            : isGranted
            ? Icons.notifications_active
            : Icons.notifications_off,
        color: isUnknown
            ? context.scheme.onSurfaceVariant
            : isGranted
            ? context.campus.positive
            : context.scheme.error,
      ),
      title: const Text('Notifications'),
      // While the status is unknown the row simply has no subtitle, rather
      // than showing a placeholder that reads as broken.
      subtitle: isUnknown ? null : Text(isGranted ? 'Activées' : 'Désactivées'),
      trailing: (!isUnknown && !isGranted)
          ? TextButton(
              onPressed: () async {
                await openAppSettings();
                unawaited(_checkPermission());
              },
              child: const Text('Activer'),
            )
          : null,
    );
  }
}
