import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../modules/registry.dart';
import '../modules/schedule/schedule_focus.dart';
import '../modules/schedule/schedule_provider.dart';
import '../modules/schedule/upcoming_courses_card.dart';
import '../modules/weather/weather_screen.dart';
import '../theme/tokens.dart';
import 'module_card.dart';

/// B1 hub: the day's essentials above a module grid. B2 replaces the grid with
/// the Aujourd'hui timeline; the app bar stays. Settings is a bottom
/// destination, not an app-bar action.
class HomeHubScreen extends ConsumerWidget {
  const HomeHubScreen({super.key, this.onOpenModule});

  /// Called with a module id when a card is tapped. The shell selects that
  /// destination instead of pushing the module inside Aujourd'hui.
  final void Function(String moduleId)? onOpenModule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aujourd’hui')),
      body: Column(
        children: [
          const SizedBox(height: CampusSpacing.x2),
          UpcomingCoursesCard(
            onOpenEvent: onOpenModule == null
                ? null
                : (event) {
                    ref.read(scheduleFocusProvider.notifier).request(event);
                    onOpenModule!(kScheduleModuleId);
                  },
          ),
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
                    onTap: () => onOpenModule?.call(module.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
