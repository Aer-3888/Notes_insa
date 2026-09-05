import 'dart:async';
import 'package:flutter/material.dart';

import '../models.dart';
import '../theme/campus_context.dart';
import '../theme/tokens.dart';

String _formatLastUpdated(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'Mis à jour à l’instant';
  if (diff.inMinutes < 60) return 'Mis à jour il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'Mis à jour il y a ${diff.inHours} h';
  return 'Mis à jour il y a ${diff.inDays} j';
}

class DashboardHeader extends StatelessWidget {
  final double? average;

  /// The screen's name. The department belongs in [subtitle]: a module is not
  /// the app's home.
  final String title;
  final String subtitle;

  final DateTime? lastUpdated;
  final int selectedSemester;
  final List<int> availableSemesters;
  final ValueChanged<int> onSemesterChanged;

  /// When true, the displayed average is a local estimate.
  final bool provisional;

  const DashboardHeader({
    super.key,
    required this.average,
    required this.title,
    required this.subtitle,
    this.lastUpdated,
    required this.selectedSemester,
    required this.availableSemesters,
    required this.onSemesterChanged,
    this.provisional = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final text = context.text;
    final attention = GradeUtils.needsAttention(average, null);
    final averageText = average == null
        ? '–'
        : '${provisional ? '≈' : ''}${average!.toStringAsFixed(2)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CampusSpacing.gutter,
        CampusSpacing.x4,
        CampusSpacing.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.headlineMedium),
                    Text(
                      subtitle,
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (lastUpdated != null)
                      _LastUpdatedLabel(lastUpdated: lastUpdated!),
                  ],
                ),
              ),
              const SizedBox(width: CampusSpacing.x4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Moyenne',
                    style: text.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    averageText,
                    semanticsLabel: average == null
                        ? 'Moyenne du semestre indisponible'
                        : 'Moyenne du semestre $averageText sur 20',
                    style: context.campusType.displayNumeral.copyWith(
                      color: attention ? scheme.error : scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (provisional && average != null)
            Text(
              'Moyenne estimée à partir des notes publiées',
              style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          if (availableSemesters.isNotEmpty) ...[
            const SizedBox(height: CampusSpacing.x3),
            _SemesterSelector(
              availableSemesters: availableSemesters,
              selectedSemester: selectedSemester,
              onSemesterChanged: onSemesterChanged,
            ),
            const SizedBox(height: CampusSpacing.x3),
          ],
        ],
      ),
    );
  }
}

/// Displays "Mis à jour il y a X min" and refreshes itself every minute,
/// without forcing a rebuild of the rest of the dashboard.
class _LastUpdatedLabel extends StatefulWidget {
  final DateTime lastUpdated;

  const _LastUpdatedLabel({required this.lastUpdated});

  @override
  State<_LastUpdatedLabel> createState() => _LastUpdatedLabelState();
}

class _LastUpdatedLabelState extends State<_LastUpdatedLabel> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    _formatLastUpdated(widget.lastUpdated),
    style: context.text.labelMedium?.copyWith(
      color: context.campus.onSurfaceMuted,
    ),
  );
}

/// Selection reads the same here as everywhere else in the app, because it is
/// the themed Material control rather than a hand-built pill.
class _SemesterSelector extends StatelessWidget {
  const _SemesterSelector({
    required this.availableSemesters,
    required this.selectedSemester,
    required this.onSemesterChanged,
  });

  final List<int> availableSemesters;
  final int selectedSemester;
  final ValueChanged<int> onSemesterChanged;

  @override
  Widget build(BuildContext context) {
    final selected = availableSemesters.contains(selectedSemester)
        ? selectedSemester
        : availableSemesters.first;
    final button = SegmentedButton<int>(
      segments: [
        for (final s in availableSemesters)
          ButtonSegment<int>(value: s, label: Text('S$s')),
      ],
      selected: <int>{selected},
      showSelectedIcon: false,
      onSelectionChanged: (choice) => onSemesterChanged(choice.first),
    );

    // Beyond four semesters the segments stop fitting a phone's width.
    if (availableSemesters.length <= 4) return button;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: button,
    );
  }
}
