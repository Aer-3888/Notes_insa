import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/schedule_tint_provider.dart';
import '../../theme/campus_context.dart';
import '../../theme/campus_theme.dart';
import '../../theme/module_tints.dart';
import '../../theme/tokens.dart';
import 'grid_block.dart';
import 'schedule_event.dart';
import 'schedule_timeline.dart';

/// Two fixed sessions, so every scheme is compared on the same names and the
/// hash spreads them across the ramp.
final List<ScheduleEvent> _sample = <ScheduleEvent>[
  ScheduleEvent(
    title: 'Analyse 3',
    start: DateTime(2026, 9, 7, 8),
    end: DateTime(2026, 9, 7, 10),
    groups: const <String>[],
    teachers: const <String>[],
    room: 'Amphi C',
  ),
  ScheduleEvent(
    title: 'Thermoénergétique',
    start: DateTime(2026, 9, 7, 10, 15),
    end: DateTime(2026, 9, 7, 12, 15),
    groups: const <String>[],
    teachers: const <String>[],
    room: 'B12',
  ),
];

class ScheduleColorsScreen extends ConsumerWidget {
  const ScheduleColorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(scheduleTintProvider);
    final notifier = ref.read(scheduleTintProvider.notifier);
    final hasColour = choice.scheme != ScheduleTintScheme.aucune;

    return Scaffold(
      appBar: AppBar(title: const Text('Couleurs des cours')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: CampusSpacing.x8),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CampusSpacing.gutter,
              vertical: CampusSpacing.x3,
            ),
            child: SegmentedButton<ScheduleTintIntensity>(
              segments: <ButtonSegment<ScheduleTintIntensity>>[
                for (final intensity in ScheduleTintIntensity.values)
                  ButtonSegment<ScheduleTintIntensity>(
                    value: intensity,
                    label: Text(intensity.label),
                  ),
              ],
              selected: <ScheduleTintIntensity>{choice.intensity},
              showSelectedIcon: false,
              onSelectionChanged: hasColour
                  ? (selection) =>
                        unawaited(notifier.setIntensity(selection.first))
                  : null,
            ),
          ),
          for (final scheme in ScheduleTintScheme.values)
            _SchemeRow(
              scheme: scheme,
              intensity: choice.intensity,
              selected: scheme == choice.scheme,
              onTap: () => unawaited(notifier.setScheme(scheme)),
            ),
        ],
      ),
    );
  }
}

class _SchemeRow extends StatelessWidget {
  const _SchemeRow({
    required this.scheme,
    required this.intensity,
    required this.selected,
    required this.onTap,
  });

  final ScheduleTintScheme scheme;
  final ScheduleTintIntensity intensity;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Semantics(
        selected: selected,
        button: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CampusSpacing.gutter,
            vertical: CampusSpacing.x3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(scheme.label, style: context.text.titleMedium),
                        Text(
                          scheme.description,
                          style: context.text.bodyMedium?.copyWith(
                            color: context.scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected) const Icon(Icons.check),
                ],
              ),
              const SizedBox(height: CampusSpacing.x2),
              _Preview(scheme: scheme, intensity: intensity),
            ],
          ),
        ),
      ),
    );
  }
}

/// The real widgets under the candidate palette, so a preview cannot drift
/// from the timetable it promises.
class _Preview extends StatelessWidget {
  const _Preview({required this.scheme, required this.intensity});

  final ScheduleTintScheme scheme;
  final ScheduleTintIntensity intensity;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: campusTheme(
        Theme.of(context).brightness,
        scheme: scheme,
        intensity: intensity,
      ),
      child: Builder(
        builder: (context) => ClipRRect(
          borderRadius: CampusRadii.cardRadius,
          child: ColoredBox(
            color: context.campus.surface,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  height: 64,
                  child: Row(
                    children: <Widget>[
                      for (final event in _sample)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(CampusSpacing.x1),
                            child: GridBlock(event: event, onTap: null),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: scheduleEventRowHeight(context),
                  child: ScheduleEventRow(event: _sample.first),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
