import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../modules/registry.dart';
import '../modules/schedule/next_course_card.dart';
import '../modules/weather/weather_screen.dart';
import '../theme/tokens.dart';
import 'app_settings_screen.dart';
import 'module_card.dart';

/// B1 hub: the day's essentials above a module grid. B2 replaces the grid with
/// the Aujourd'hui timeline; the app bar and settings action stay.
class HomeHubScreen extends ConsumerWidget {
  const HomeHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aujourd’hui'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Paramètres',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AppSettingsScreen(),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: CampusSpacing.x2),
          const NextCourseCard(),
          const WeatherStrip(),
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.all(CampusSpacing.gutter),
              crossAxisCount: 2,
              mainAxisSpacing: CampusSpacing.x3,
              crossAxisSpacing: CampusSpacing.x3,
              childAspectRatio: 1.4,
              children: [
                for (final module in kCampusModules.whereType<ReadyModule>())
                  ModuleCard(
                    module: module,
                    onTap: () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute<void>(builder: module.builder)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
