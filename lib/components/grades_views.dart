import 'package:flutter/material.dart';

import '../models.dart';
import '../providers/grades_view_mode_provider.dart';
import '../theme/campus_context.dart';
import '../theme/tokens.dart';
import 'unit_card_grid.dart';

class GradesViews extends StatelessWidget {
  const GradesViews({
    super.key,
    required this.mode,
    required this.curriculum,
    required this.onUnitTap,
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
  });

  final GradesViewMode mode;
  final List<TeachingUnit> curriculum;
  final ValueChanged<TeachingUnit> onUnitTap;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // All modes share the existing loading, empty and retry states.
    if (mode == GradesViewMode.cartes || curriculum.isEmpty) {
      return UnitCardGrid(
        curriculum: curriculum,
        onUnitTap: onUnitTap,
        isLoading: isLoading,
        errorMessage: errorMessage,
        onRetry: onRetry,
      );
    }

    return ListView.separated(
      key: PageStorageKey(mode),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        CampusSpacing.gutter,
        0,
        CampusSpacing.gutter,
        CampusSpacing.gutter,
      ),
      itemCount: curriculum.length,
      separatorBuilder: (_, _) => const SizedBox(height: CampusSpacing.x3),
      itemBuilder: (context, index) {
        final unit = curriculum[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                onTap: () => onUnitTap(unit),
                title: Text(titleCase(unit.name)),
                subtitle: Text('${unit.statusLabel} · Coeff. ${unit.coeff}'),
                trailing: _Average(
                  value: unit.average,
                  estimated: unit.isAverageEstimated,
                  status: unit.extractedStatus,
                ),
              ),
              if (mode == GradesViewMode.synthese)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CampusSpacing.card,
                    0,
                    CampusSpacing.card,
                    CampusSpacing.card,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (unit.average != null) ...[
                        LinearProgressIndicator(
                          value: (unit.average! / 20).clamp(0.0, 1.0),
                          color:
                              GradeUtils.needsAttention(
                                unit.average,
                                unit.extractedStatus,
                              )
                              ? context.scheme.error
                              : context.scheme.primary,
                          semanticsLabel:
                              'Moyenne ${unit.isAverageEstimated ? 'estimée ' : ''}de '
                              '${titleCase(unit.name)} : '
                              '${unit.average!.toStringAsFixed(2)} sur 20',
                        ),
                        const SizedBox(height: CampusSpacing.x2),
                      ],
                      Text(
                        '${unit.subjects.length} matière${unit.subjects.length == 1 ? '' : 's'} · Moyenne sur 20',
                        style: context.text.labelMedium,
                      ),
                    ],
                  ),
                )
              else ...[
                const Divider(height: 1),
                if (unit.subjects.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(CampusSpacing.card),
                    child: Text('Aucune matière'),
                  ),
                for (final subject in unit.subjects)
                  ListTile(
                    onTap: () => onUnitTap(unit),
                    title: Text(titleCase(subject.name)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: CampusSpacing.x1),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Coeff. ${subject.coeff}'),
                          if (subject.grades.isEmpty)
                            const Text('Aucune note publiée')
                          else
                            Wrap(
                              spacing: CampusSpacing.x2,
                              runSpacing: CampusSpacing.x1,
                              children: [
                                for (final grade in subject.grades)
                                  Text(
                                    '${grade.label} : ${grade.value.toStringAsFixed(2)}'
                                    '${grade.coeff.isEmpty ? '' : ' (coeff. ${grade.coeff})'}',
                                    style: context.text.bodySmall?.copyWith(
                                      color:
                                          GradeUtils.needsAttention(
                                            grade.value,
                                            null,
                                          )
                                          ? context.scheme.error
                                          : context.scheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    trailing: _Average(
                      value: subject.average,
                      estimated: subject.isAverageEstimated,
                      status: subject.extractedStatus,
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Average extends StatelessWidget {
  const _Average({required this.value, required this.estimated, this.status});

  final double? value;
  final bool estimated;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final label = value == null
        ? '–'
        : '${estimated ? '≈' : ''}${value!.toStringAsFixed(2)}';
    return Text(
      label,
      semanticsLabel: value == null
          ? 'Moyenne indisponible'
          : 'Moyenne ${estimated ? 'estimée ' : ''}$label sur 20',
      style: context.text.titleLarge?.copyWith(
        color: GradeUtils.needsAttention(value, status)
            ? context.scheme.error
            : context.scheme.onSurface,
      ),
    );
  }
}
