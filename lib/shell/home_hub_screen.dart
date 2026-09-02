import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_colors.dart';
import '../modules/registry.dart';
import '../modules/weather/weather_screen.dart';
import 'app_settings_screen.dart';
import 'module_card.dart';

class HomeHubScreen extends ConsumerWidget {
  const HomeHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Campus'),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
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
          const SizedBox(height: 8),
          const WeatherStrip(),
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.all(16),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.95,
              children: [
                for (final module in kCampusModules)
                  ModuleCard(
                    module: module,
                    onTap: switch (module) {
                      ReadyModule() => () => Navigator.of(
                        context,
                      ).push(MaterialPageRoute<void>(builder: module.builder)),
                      ComingSoonModule() => null,
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
