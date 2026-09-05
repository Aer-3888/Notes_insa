import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/freshness.dart';
import '../../theme/campus_context.dart';
import '../../theme/state_view.dart';
import '../../theme/tokens.dart';
import 'weather_provider.dart';

/// One-line summary for the home screen. Sizes to its content so it survives
/// a large text scale.
class WeatherStrip extends ConsumerWidget {
  const WeatherStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(weatherProvider).value?.data;
    if (snapshot == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CampusSpacing.gutter,
        vertical: CampusSpacing.x1,
      ),
      child: Row(
        children: [
          Icon(
            Icons.thermostat_outlined,
            size: 18,
            color: context.scheme.onSurfaceVariant,
          ),
          const SizedBox(width: CampusSpacing.x2),
          Text(
            '${snapshot.temperatureC.round()} °C',
            style: context.campusType.numeral,
          ),
          const SizedBox(width: CampusSpacing.x2),
          Text(
            '${snapshot.low.round()}° / ${snapshot.high.round()}°',
            style: context.text.bodyMedium?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
        ],
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
      appBar: AppBar(title: const Text('Météo')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => StateView(
          icon: Icons.cloud_off_outlined,
          title: 'Météo indisponible',
          body:
              'Impossible de joindre le service météo. Vérifiez la connexion, '
              'puis réessayez.',
          action: FilledButton.tonalIcon(
            onPressed: () => ref.invalidate(weatherProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
        ),
        data: (entry) {
          final snapshot = entry.data;
          if (snapshot == null) {
            return StateView(
              icon: Icons.cloud_off_outlined,
              title: 'Météo indisponible',
              body: freshnessLabel(entry.refreshState, entry.cachedAt),
              action: FilledButton.tonalIcon(
                onPressed: () => ref.invalidate(weatherProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(CampusSpacing.gutter),
            children: [
              Text(
                '${snapshot.temperatureC.round()} °C',
                style: context.campusType.displayNumeral,
              ),
              Text(
                'Min ${snapshot.low.round()}°, max ${snapshot.high.round()}°',
                style: context.text.bodyMedium?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: CampusSpacing.x6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final h in snapshot.hourly.take(12))
                      Padding(
                        padding: const EdgeInsets.only(right: CampusSpacing.x5),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${h.time.hour} h',
                              style: context.text.labelMedium?.copyWith(
                                color: context.scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: CampusSpacing.x2),
                            Text(
                              '${h.temperatureC.round()}°',
                              style: context.campusType.numeral,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: CampusSpacing.x6),
              Text(
                freshnessLabel(entry.refreshState, entry.cachedAt),
                style: context.text.labelMedium?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
