import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/campus_navigation.dart';
import '../../core/freshness.dart';
import '../../core/time.dart';
import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'crous_provider.dart';
import 'crous_restaurant.dart';

class CrousTodayCard extends ConsumerStatefulWidget {
  const CrousTodayCard({super.key});

  @override
  ConsumerState<CrousTodayCard> createState() => _CrousTodayCardState();
}

class _CrousTodayCardState extends ConsumerState<CrousTodayCard>
    with WidgetsBindingObserver {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startClock();
  }

  void _startClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startClock();
      setState(() {});
    } else {
      _clock?.cancel();
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(crousRestaurantsProvider);
    final entry = async.value;
    final restaurants = entry?.data;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CampusSpacing.gutter,
        CampusSpacing.x2,
        CampusSpacing.gutter,
        CampusSpacing.x2,
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CampusSpacing.x2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CampusSpacing.x4,
                  CampusSpacing.x1,
                  CampusSpacing.x2,
                  CampusSpacing.x1,
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.restaurant_outlined, size: 20),
                    const SizedBox(width: CampusSpacing.x3),
                    Expanded(
                      child: Text(
                        'Restos U’ proches',
                        style: context.text.titleSmall,
                      ),
                    ),
                    IconButton(
                      onPressed: () => ref.invalidate(crousRestaurantsProvider),
                      tooltip: 'Actualiser les Restos U’',
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              if (restaurants != null && restaurants.isNotEmpty)
                for (final restaurant in restaurants)
                  _RestaurantRow(
                    restaurant: restaurant,
                    now: campusNow(),
                    onTap: () => CampusNavigationScope.maybeOf(
                      context,
                    )?.onOpenMap(restaurant.mapCode),
                  )
              else if (async.isLoading)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CampusSpacing.x4,
                    CampusSpacing.x2,
                    CampusSpacing.x4,
                    CampusSpacing.x3,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Chargement des horaires…',
                      style: context.text.bodyMedium?.copyWith(
                        color: context.scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CampusSpacing.x4,
                    CampusSpacing.x2,
                    CampusSpacing.x2,
                    CampusSpacing.x2,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Statut CROUS indisponible',
                          style: context.text.bodyMedium?.copyWith(
                            color: context.scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(crousRestaurantsProvider),
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
              if (entry != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CampusSpacing.x4,
                    CampusSpacing.x1,
                    CampusSpacing.x4,
                    CampusSpacing.x2,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Source Crous · '
                      '${freshnessLabel(entry.refreshState, entry.cachedAt)}',
                      style: context.text.labelSmall?.copyWith(
                        color: context.scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RestaurantRow extends StatelessWidget {
  const _RestaurantRow({
    required this.restaurant,
    required this.now,
    required this.onTap,
  });

  final CrousRestaurant restaurant;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = restaurant.statusAt(now);
    final statusColor = status.isOpen
        ? context.campus.positive
        : status.availability == CrousAvailability.opensLater
        ? context.campus.attention
        : context.scheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CampusSpacing.x4,
          vertical: CampusSpacing.x2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: CampusSpacing.x2),
              child: Container(
                width: CampusSpacing.x2,
                height: CampusSpacing.x2,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: CampusSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          restaurant.shortName,
                          style: context.text.labelLarge,
                        ),
                      ),
                      Text(
                        status.label,
                        style: context.text.labelMedium?.copyWith(
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: CampusSpacing.x1),
                  Text(
                    status.detail,
                    style: context.text.bodySmall?.copyWith(
                      color: context.scheme.onSurfaceVariant,
                    ),
                  ),
                  if (status.notice != null)
                    Text(
                      status.notice!,
                      style: context.text.bodySmall?.copyWith(
                        color: context.campus.attention,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: CampusSpacing.x2),
            const Padding(
              padding: EdgeInsets.only(top: CampusSpacing.x1),
              child: Icon(Icons.map_outlined, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
