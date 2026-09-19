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
  final Widget? titleWidget;
  final String subtitle;

  final DateTime? lastUpdated;

  /// Injected rather than built here so the rail can share the tab controller
  /// that drives the pages.
  final Widget? semesterSelector;

  /// When true, the displayed average is a local estimate.
  final bool provisional;

  const DashboardHeader({
    super.key,
    required this.average,
    required this.title,
    this.titleWidget,
    required this.subtitle,
    this.lastUpdated,
    this.semesterSelector,
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
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titleWidget ?? Text(title, style: text.headlineMedium),
        Text(
          subtitle,
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (lastUpdated != null) _LastUpdatedLabel(lastUpdated: lastUpdated!),
      ],
    );
    final averageLabel = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'Moyenne',
          style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        AnimatedSwitcher(
          duration: CampusMotion.of(context, CampusMotion.exit),
          switchInCurve: CampusMotion.standard,
          switchOutCurve: CampusMotion.standard,
          // Overlap the two numerals so a digit-count change does not shift
          // the layout mid-fade.
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerRight,
            children: <Widget>[...previous, ?current],
          ),
          child: Text(
            averageText,
            key: ValueKey<String>('$averageText/$attention'),
            semanticsLabel: average == null
                ? 'Moyenne du semestre indisponible'
                : 'Moyenne du semestre $averageText sur 20',
            style: context.campusType.displayNumeral.copyWith(
              color: attention ? scheme.error : scheme.onSurface,
            ),
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(top: CampusSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CampusSpacing.gutter,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
                if (constraints.maxWidth < 320 * scale) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      heading,
                      const SizedBox(height: CampusSpacing.x2),
                      Align(
                        alignment: Alignment.centerRight,
                        child: averageLabel,
                      ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: CampusSpacing.x4),
                    averageLabel,
                  ],
                );
              },
            ),
          ),
          AnimatedSize(
            duration: CampusMotion.of(context, CampusMotion.enter),
            curve: CampusMotion.standard,
            child: (provisional && average != null)
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CampusSpacing.gutter,
                      CampusSpacing.x1,
                      CampusSpacing.gutter,
                      0,
                    ),
                    child: Text(
                      'Moyenne estimée à partir des notes publiées',
                      style: text.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          if (semesterSelector != null) ...[
            const SizedBox(height: CampusSpacing.x3),
            semesterSelector!,
            const SizedBox(height: CampusSpacing.x2),
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
