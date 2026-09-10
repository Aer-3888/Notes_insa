import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time.dart';
import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'crous_provider.dart';
import 'crous_restaurant.dart';
import 'crous_service.dart';

class CrousMapDetails extends ConsumerWidget {
  const CrousMapDetails({required this.mapCode, super.key});

  final String mapCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(crousRestaurantsProvider).value;
    final live = _restaurantFor(entry?.data, mapCode);
    final restaurant =
        live ?? _restaurantFor(CrousService.fallbackNearby, mapCode);
    if (restaurant == null) return const SizedBox.shrink();

    final status = live?.statusAt(campusNow());
    final statusColor = switch (status?.availability) {
      CrousAvailability.open => context.campus.positive,
      CrousAvailability.opensLater => context.campus.attention,
      _ => context.scheme.onSurfaceVariant,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Horaires et statut', style: context.text.titleMedium),
        const SizedBox(height: CampusSpacing.x2),
        if (status != null) ...<Widget>[
          Row(
            children: <Widget>[
              Container(
                width: CampusSpacing.x2,
                height: CampusSpacing.x2,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: CampusSpacing.x2),
              Text(
                status.label,
                style: context.text.labelLarge?.copyWith(color: statusColor),
              ),
            ],
          ),
          const SizedBox(height: CampusSpacing.x1),
          Text(status.detail, style: context.text.bodyMedium),
          if (status.notice != null)
            Text(
              status.notice!,
              style: context.text.bodySmall?.copyWith(
                color: context.campus.attention,
              ),
            ),
        ] else
          Text(
            'Statut en direct indisponible',
            style: context.text.bodyMedium?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: CampusSpacing.x3),
        Text('Horaires habituels', style: context.text.labelLarge),
        const SizedBox(height: CampusSpacing.x1),
        for (final period in restaurant.openingPeriods)
          Padding(
            padding: const EdgeInsets.only(bottom: CampusSpacing.x1),
            child: Text(
              '${period.opensAtMinute >= 17 * 60 ? 'Soir' : 'Midi'} · '
              '${period.usualHoursLabel}',
              style: context.text.bodyMedium,
            ),
          ),
        Text(
          'Les fermetures Crous et jours fériés restent prioritaires.',
          style: context.text.bodySmall?.copyWith(
            color: context.scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

CrousRestaurant? _restaurantFor(
  List<CrousRestaurant>? restaurants,
  String mapCode,
) {
  if (restaurants == null) return null;
  for (final restaurant in restaurants) {
    if (restaurant.mapCode == mapCode) return restaurant;
  }
  return null;
}
