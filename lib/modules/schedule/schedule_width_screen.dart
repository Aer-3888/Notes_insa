import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'schedule_day_index.dart';
import 'schedule_event.dart';
import 'schedule_grid.dart';
import 'schedule_view_mode.dart';

/// 7 September 2026 is a Monday, so the sample week reads Lundi to Dimanche.
final DateTime _monday = DateTime(2026, 9, 7);

/// Names of deliberately different lengths, so the width is judged on what
/// actually separates one setting from another: how much of a name survives.
final List<ScheduleEvent> _sample = <ScheduleEvent>[
  _at(0, 'Analyse 3', 'Amphi C'),
  _at(1, 'Thermoénergétique', 'B12'),
  _at(2, 'INFORMATIQUE', 'I3'),
  _at(3, 'Anglais', 'L204'),
  _at(4, 'Algèbre 3', 'Amphi B'),
];

ScheduleEvent _at(int dayOffset, String title, String room) {
  final day = DateTime(_monday.year, _monday.month, _monday.day + dayOffset);
  return ScheduleEvent(
    title: title,
    start: DateTime(day.year, day.month, day.day, 8),
    end: DateTime(day.year, day.month, day.day, 10),
    groups: const <String>[],
    teachers: const <String>[],
    room: room,
  );
}

/// Tall enough for the headings and the two sample hours under them.
const double _previewHeight = 180;

/// The slider moves in 4 dp steps, so a hand-set width still lands on the
/// spacing scale.
const double _step = CampusSpacing.x1;

class ScheduleWidthScreen extends ConsumerWidget {
  const ScheduleWidthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = ref.watch(scheduleDayWidthProvider);
    final notifier = ref.read(scheduleDayWidthProvider.notifier);
    final hourHeight = ref.watch(scheduleHourHeightProvider);
    final hourHeightNotifier = ref.read(scheduleHourHeightProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Grille de l’emploi du temps')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: CampusSpacing.x8),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CampusSpacing.gutter,
              CampusSpacing.x3,
              CampusSpacing.gutter,
              CampusSpacing.x3,
            ),
            child: Text(
              'En Semaine, une colonne plus large se lit mieux mais oblige à '
              'faire défiler les jours.',
              style: context.text.bodyMedium?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CampusSpacing.gutter,
            ),
            child: _Preview(width: width, hourHeight: hourHeight),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CampusSpacing.gutter,
              CampusSpacing.x3,
              CampusSpacing.gutter,
              0,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text('Par jour', style: context.text.titleMedium),
                ),
                Text('${width.round()} dp', style: context.campusType.numeral),
              ],
            ),
          ),
          Slider(
            value: width,
            min: kScheduleDayWidthMin,
            max: kScheduleDayWidthMax,
            divisions: ((kScheduleDayWidthMax - kScheduleDayWidthMin) / _step)
                .round(),
            label: '${width.round()} dp',
            semanticFormatterCallback: (value) => '${value.round()} dp',
            onChanged: notifier.drag,
            onChangeEnd: (value) => unawaited(notifier.set(value)),
          ),
          const _SectionHeader('Hauteur des heures'),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CampusSpacing.gutter,
              0,
              CampusSpacing.gutter,
              CampusSpacing.x2,
            ),
            child: Text(
              'Dans Jour, 3 jours et Semaine, pincez verticalement dans la '
              'grille pour voir plus ou moins de la journée.',
              style: context.text.bodyMedium?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CampusSpacing.gutter,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text('Par heure', style: context.text.titleMedium),
                ),
                Text(
                  '${hourHeight.round()} dp',
                  style: context.campusType.numeral,
                ),
              ],
            ),
          ),
          Slider(
            value: hourHeight,
            min: kScheduleHourHeightMin,
            max: kScheduleHourHeightMax,
            divisions:
                ((kScheduleHourHeightMax - kScheduleHourHeightMin) / _step)
                    .round(),
            label: '${hourHeight.round()} dp',
            semanticFormatterCallback: (value) => '${value.round()} dp',
            onChanged: hourHeightNotifier.drag,
            onChangeEnd: (value) => unawaited(hourHeightNotifier.set(value)),
          ),
          const _SectionHeader('Réglages courants'),
          for (final preset in ScheduleDayWidth.values)
            _PresetRow(
              preset: preset,
              selected: preset.minColumnWidth == width,
              onTap: () => unawaited(notifier.set(preset.minColumnWidth)),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      CampusSpacing.gutter,
      CampusSpacing.x4,
      CampusSpacing.gutter,
      CampusSpacing.x2,
    ),
    child: Text(label, style: context.text.titleMedium),
  );
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final ScheduleDayWidth preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    selected: selected,
    title: Text(preset.label),
    subtitle: Text(preset.description),
    trailing: Text(
      '${preset.minColumnWidth.round()} dp',
      style: context.text.bodyMedium?.copyWith(
        color: context.scheme.onSurfaceVariant,
      ),
    ),
  );
}

/// The real grid at the chosen width, so the preview cannot promise something
/// the week does not deliver.
class _Preview extends StatelessWidget {
  const _Preview({required this.width, required this.hourHeight});

  final double width;
  final double hourHeight;

  @override
  Widget build(BuildContext context) {
    final index = ScheduleDayIndex.build(
      events: _sample,
      from: _monday,
      to: DateTime(_monday.year, _monday.month, _monday.day + 6),
    );

    return ClipRRect(
      borderRadius: CampusRadii.cardRadius,
      child: ColoredBox(
        color: context.campus.surface,
        child: SizedBox(
          height: _previewHeight,
          child: ScheduleGrid(
            index: index,
            days: <DateTime>[
              for (var i = 0; i < 7; i++)
                DateTime(_monday.year, _monday.month, _monday.day + i),
            ],
            minColumnWidth: width,
            hourHeight: hourHeight,
            onTapEvent: (_) {},
          ),
        ),
      ),
    );
  }
}
