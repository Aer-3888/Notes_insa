import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_colors.dart';
import '../../core/module_cache.dart';
import '../../shell/app_settings_screen.dart';
import 'weather_model.dart';
import 'weather_provider.dart';

String freshnessLabel(CachedEntry<WeatherSnapshot> entry) {
  final at = entry.cachedAt;
  final stamp = at == null
      ? ''
      : ' (${at.day}/${at.month} ${at.hour.toString().padLeft(2, '0')}:'
            '${at.minute.toString().padLeft(2, '0')})';
  return switch (entry.refreshState) {
    RefreshState.fresh => 'À jour',
    RefreshState.refreshing => 'Actualisation...',
    RefreshState.failedOffline => 'Hors ligne$stamp',
    RefreshState.failedUpstream => 'Service indisponible$stamp',
  };
}

/// One-line summary for the hub. Renders a fixed-height box while the cache
/// resolves so the grid below it does not jump.
class WeatherStrip extends ConsumerWidget {
  const WeatherStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(weatherProvider).value?.data;
    return SizedBox(
      height: 34,
      child: snapshot == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(
                    Icons.wb_sunny_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${snapshot.temperatureC.round()}°C  •  '
                    '${snapshot.low.round()}° / ${snapshot.high.round()}°',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
    );
  }
}

class WeatherScreen extends ConsumerWidget {
  const WeatherScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(weatherProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Météo'),
        foregroundColor: Colors.white,
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
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Météo indisponible pour le moment.')),
        data: (entry) {
          final snapshot = entry.data;
          if (snapshot == null) {
            return Center(child: Text(freshnessLabel(entry)));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${snapshot.temperatureC.round()}°C',
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
              Text(
                'Min ${snapshot.low.round()}°  •  Max ${snapshot.high.round()}°',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 90,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final h in snapshot.hourly.take(12))
                      Padding(
                        padding: const EdgeInsets.only(right: 18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${h.time.hour}h'),
                            const SizedBox(height: 8),
                            Text('${h.temperatureC.round()}°'),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                freshnessLabel(entry),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
