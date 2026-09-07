import 'package:flutter/material.dart';

import '../models.dart';
import '../theme/campus_context.dart';
import '../theme/state_view.dart';
import '../theme/tokens.dart';

class UnitCardGrid extends StatelessWidget {
  final List<TeachingUnit> curriculum;
  final Function(TeachingUnit) onUnitTap;
  final bool isLoading;

  /// Message to show when there is nothing to display because of a problem
  /// (fetch failure or unreadable data). When null, an empty curriculum shows
  /// the neutral placeholder instead.
  final String? errorMessage;
  final VoidCallback? onRetry;

  const UnitCardGrid({
    super.key,
    required this.curriculum,
    required this.onUnitTap,
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && curriculum.isEmpty) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(
          CampusSpacing.gutter,
          0,
          CampusSpacing.gutter,
          CampusSpacing.gutter,
        ),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.85,
          crossAxisSpacing: CampusSpacing.x4,
          mainAxisSpacing: CampusSpacing.x4,
        ),
        itemCount: 6,
        itemBuilder: (_, _) => const _SkeletonCard(),
      );
    }

    if (curriculum.isEmpty && errorMessage != null) {
      return StateView(
        icon: Icons.cloud_off_outlined,
        title: 'Notes indisponibles',
        body: errorMessage,
        action: onRetry == null
            ? null
            : FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
      );
    }

    if (curriculum.isEmpty) {
      return const StateView(
        icon: Icons.inbox_outlined,
        title: 'Aucune note pour ce semestre',
        body: 'Les notes apparaîtront ici dès que le portail les publiera.',
      );
    }

    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final columns = textScale > 1.3 ? 1 : 2;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        CampusSpacing.gutter,
        0,
        CampusSpacing.gutter,
        CampusSpacing.gutter,
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: (columns == 1 ? 1.6 : 0.85) / textScale,
        crossAxisSpacing: CampusSpacing.x4,
        mainAxisSpacing: CampusSpacing.x4,
      ),
      itemCount: curriculum.length,
      itemBuilder: (context, index) {
        final unit = curriculum[index];
        return _UnitCard(unit: unit, onTap: () => onUnitTap(unit));
      },
    );
  }
}

class _UnitCard extends StatelessWidget {
  const _UnitCard({required this.unit, required this.onTap});

  final TeachingUnit unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final attention = GradeUtils.needsAttention(
      unit.average,
      unit.extractedStatus,
    );
    final averagePrefix = unit.isAverageEstimated ? '≈' : '';
    final averageText = unit.average == null
        ? '–'
        : '$averagePrefix${unit.average!.toStringAsFixed(2)}';
    final semanticLabel = unit.average == null
        ? '${titleCase(unit.name)}, pas encore de moyenne'
        : '${titleCase(unit.name)}, moyenne $averageText sur 20';

    return Semantics(
      button: true,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(CampusSpacing.card),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  averageText,
                  style: context.campusType.displayNumeral.copyWith(
                    fontSize: 28,
                    height: 32 / 28,
                    color: attention ? scheme.error : scheme.onSurface,
                  ),
                ),
                Text(
                  titleCase(unit.name),
                  style: context.text.titleMedium,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  unit.statusLabel,
                  style: context.text.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Static placeholder boxes. A shimmer on a cache-first screen flashes more
/// often than it reassures.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    final fill = context.scheme.surfaceContainerHighest;
    Widget box(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: CampusRadii.controlRadius,
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(CampusSpacing.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [box(72, 28), box(double.infinity, 16), box(56, 12)],
        ),
      ),
    );
  }
}
