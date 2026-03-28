import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../components/app_drawer.dart';
import '../providers/settings_provider.dart';

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
                'Settings',
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
                            child: Column(
                              children: [
                                ...availableIntervals.map((interval) {
                                  final isSelected =
                                      settingsState.fetchInterval == interval;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: InkWell(
                                      onTap: () {
                                        ref
                                            .read(settingsProvider.notifier)
                                            .setFetchInterval(interval);
                                      },
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? Colors.indigo.shade50
                                              : Colors.grey.shade50,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: isSelected
                                                ? Colors.indigo.shade700
                                                : Colors.grey.shade300,
                                            width: isSelected ? 2 : 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                ref.watch(
                                                  intervalLabelProvider(
                                                    interval,
                                                  ),
                                                ),
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: isSelected
                                                      ? FontWeight.w600
                                                      : FontWeight.normal,
                                                  color: isSelected
                                                      ? Colors.indigo.shade900
                                                      : Colors.grey.shade700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ],
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
