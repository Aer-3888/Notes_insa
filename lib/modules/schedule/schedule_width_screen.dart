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

/// Names of deliberately different lengths, so the widths are compared on what
/// actually separates them: whether a module name survives.
final List<ScheduleEvent> _sample = <ScheduleEvent>[
  _at(0, 'Analyse 3', 8, 10, 'Amphi C'),
  _at(1, 'Thermoénergétique', 8, 10, 'B12'),
  _at(2, 'INFORMATIQUE', 8, 10, 'I3'),
  _at(3, 'Anglais', 8, 10, 'L204'),
  _at(4, 'Algèbre 3', 8, 10, 'Amphi B'),
];

ScheduleEvent _at(int dayOffset, String title, int from, int to, String room) {
  final day = DateTime(_monday.year, _monday.month, _monday.day + dayOffset);
  return ScheduleEvent(
    title: title,
    start: DateTime(day.year, day.month, day.day, from),
    end: DateTime(day.year, day.month, day.day, to),
    groups: const <String>[],
    teachers: const <String>[],
    room: room,
  );
}

/// Tall enough for the headings and the two sample hours under them.
const double _previewHeight = 180;

class ScheduleWidthScreen extends ConsumerWidget {
  const ScheduleWidthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chosen = ref.watch(scheduleDayWidthProvider);
    final notifier = ref.read(scheduleDayWidthProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Largeur des jours')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: CampusSpacing.x8),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CampusSpacing.gutter,
              CampusSpacing.x3,
              CampusSpacing.gutter,
              0,
            ),
            child: Text(
              'En Semaine, une colonne plus large se lit mieux mais oblige à '
              'faire défiler les jours.',
              style: context.text.bodyMedium?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final width in ScheduleDayWidth.values)
            _WidthRow(
              width: width,
              selected: width == chosen,
              onTap: () => unawaited(notifier.set(width)),
            ),
        ],
      ),
    );
  }
}

class _WidthRow extends StatelessWidget {
  const _WidthRow({
    required this.width,
    required this.selected,
    required this.onTap,
  });

  final ScheduleDayWidth width;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
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
                      Text(width.label, style: context.text.titleMedium),
                      Text(
                        width.description,
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
            _Preview(width: width),
          ],
        ),
      ),
    ),
  );
}

/// The real grid at the candidate width, so the preview cannot promise
/// something the week does not deliver.
class _Preview extends StatelessWidget {
  const _Preview({required this.width});

  final ScheduleDayWidth width;

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
            minColumnWidth: width.minColumnWidth,
            onTapEvent: (_) {},
          ),
        ),
      ),
    );
  }
}
