import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time.dart';
import '../../theme/campus_context.dart';
import '../../theme/state_view.dart';
import '../../theme/tokens.dart';
import 'association.dart';
import 'association_detail_screen.dart';
import 'association_follows.dart';
import 'association_service.dart';

/// Everything coming up on campus, or only what the student follows.
///
/// The today card shows the next three; this is the rest of them.
class AssociationAgenda extends ConsumerStatefulWidget {
  const AssociationAgenda({super.key});

  @override
  ConsumerState<AssociationAgenda> createState() => _AssociationAgendaState();
}

class _AssociationAgendaState extends ConsumerState<AssociationAgenda> {
  bool _followedOnly = false;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(associationsProvider).value ?? const <Association>[];
    final follows = ref.watch(associationFollowsProvider);
    final byId = <String, Association>{for (final a in all) a.id: a};

    final now = campusNow();
    final events = ref
        .watch(associationEventsProvider)
        .where((event) => !event.isPast(now))
        .where(
          (event) => !_followedOnly || follows.contains(event.associationId),
        )
        .toList();

    return Column(
      children: <Widget>[
        if (follows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CampusSpacing.gutter,
              CampusSpacing.x3,
              CampusSpacing.gutter,
              0,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: const Text('Mes assos'),
                selected: _followedOnly,
                onSelected: (value) => setState(() => _followedOnly = value),
              ),
            ),
          ),
        Expanded(child: _list(events, byId)),
      ],
    );
  }

  Widget _list(List<AssociationEvent> events, Map<String, Association> byId) {
    if (events.isEmpty) {
      return StateView(
        icon: Icons.event_outlined,
        title: _followedOnly ? 'Rien chez tes assos' : 'Rien de prévu',
        body: _followedOnly
            ? 'Aucun évènement à venir dans les associations que tu suis.'
            : 'Aucun évènement annoncé pour le moment.',
      );
    }

    // A heading per day, so a busy week reads as a week and not as a list.
    String? lastDay;
    final rows = <Widget>[];
    for (final event in events) {
      final day = _dayLabel(event.startsAt);
      if (day != lastDay) {
        lastDay = day;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CampusSpacing.gutter,
              CampusSpacing.x4,
              CampusSpacing.gutter,
              CampusSpacing.x1,
            ),
            child: Text(
              day,
              style: context.text.labelLarge?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }
      final association = byId[event.associationId];
      rows.add(
        ListTile(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  AssociationDetailScreen(associationId: event.associationId),
            ),
          ),
          title: Text(event.title),
          subtitle: Text(
            <String>[
              if (!event.isAllDay) _clock(event.startsAt),
              ?association?.displayName,
              ?event.location,
            ].join(' · '),
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      );
    }
    rows.add(const SizedBox(height: CampusSpacing.x8));
    return ListView(children: rows);
  }
}

const List<String> _weekdays = <String>[
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

const List<String> _months = <String>[
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

String _dayLabel(DateTime day) =>
    '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}';

String _clock(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
