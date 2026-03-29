import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../components/app_drawer.dart';
import '../providers/settings_provider.dart';

String _intervalLabel(int minutes) =>
    minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h';

/// Settings screen for background fetch configuration.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(settingsProvider);
    final availableIntervals = ref.watch(availableIntervalsProvider);

    return Scaffold(
      drawer: const AppDrawer(selected: DrawerItem.settings),
      appBar: AppBar(
        toolbarHeight: 84,
        elevation: 4,
        automaticallyImplyLeading: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF283593), Color(0xFF5C6BC0)],
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        leading: Builder(
          builder: (context) => Padding(
            padding: const EdgeInsets.only(left: 6.0),
            child: IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openDrawer(),
              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: const Text(
                'Paramètres',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
      body: settingsState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                // Notification permission card
                const _NotificationPermissionCard(),
                const SizedBox(height: 12),
                // Background fetch card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
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
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Fréquence de vérification des nouvelles notes',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Transform.scale(
                              scale: 0.85,
                              child: Switch(
                                value: settingsState.fetchEnabled,
                                onChanged: (enabled) {
                                  ref
                                      .read(settingsProvider.notifier)
                                      .setFetchEnabled(enabled);
                                },
                                activeThumbColor: Colors.green,
                                activeTrackColor: Colors.green.shade200,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Opacity(
                          opacity: settingsState.fetchEnabled ? 1.0 : 0.4,
                          child: IgnorePointer(
                            ignoring: !settingsState.fetchEnabled,
                            child: _IntervalSelector(
                              intervals: availableIntervals,
                              selected: settingsState.fetchInterval,
                              onChanged: (v) => ref
                                  .read(settingsProvider.notifier)
                                  .setFetchInterval(v),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _IntervalSelector extends StatelessWidget {
  final List<int> intervals;
  final int selected;
  final ValueChanged<int> onChanged;

  const _IntervalSelector({
    required this.intervals,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final n = intervals.length;
    final rawIdx = intervals.indexOf(selected);
    final selectedIndex = rawIdx < 0 ? 0 : rawIdx;

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth / n;

          return Stack(
            children: [
              // Pill animates independently — does not rebuild gesture detectors
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                left: selectedIndex * itemWidth,
                top: 0,
                bottom: 0,
                width: itemWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.indigo,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.indigo.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              // Stable gesture detectors — never rebuilt during animation
              Row(
                children: List.generate(
                  n,
                  (i) => Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(intervals[i]),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          style: TextStyle(
                            color: i == selectedIndex
                                ? Colors.white
                                : Colors.grey.shade600,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          child: Text(_intervalLabel(intervals[i])),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NotificationPermissionCard extends StatefulWidget {
  const _NotificationPermissionCard();

  @override
  State<_NotificationPermissionCard> createState() =>
      _NotificationPermissionCardState();
}

class _NotificationPermissionCardState
    extends State<_NotificationPermissionCard>
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

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              isUnknown
                  ? Icons.notifications_outlined
                  : isGranted
                  ? Icons.notifications_active
                  : Icons.notifications_off,
              color: isUnknown
                  ? Colors.grey.shade400
                  : isGranted
                  ? Colors.green.shade600
                  : Colors.orange.shade700,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notifications',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isUnknown
                        ? '...'
                        : isGranted
                        ? 'Activées'
                        : 'Désactivées',
                    style: TextStyle(
                      fontSize: 14,
                      color: isUnknown
                          ? Colors.grey.shade400
                          : isGranted
                          ? Colors.green.shade600
                          : Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
            ),
            if (!isUnknown && !isGranted)
              TextButton(
                onPressed: () async {
                  await openAppSettings();
                  _checkPermission();
                },
                child: const Text('Activer'),
              ),
          ],
        ),
      ),
    );
  }
}
