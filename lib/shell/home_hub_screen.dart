import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_colors.dart';
import '../modules/registry.dart';
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
      ),
      body: GridView.count(
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
    );
  }
}
