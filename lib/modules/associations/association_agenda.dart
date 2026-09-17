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
            : 'Aucun évènement annoncé pour le moment. Explore les assos du campus pour en découvrir.',
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
      rows.add(_AgendaEventCard(event: event, association: association));
    }
    rows.add(const SizedBox(height: CampusSpacing.x8));
    return ListView(children: rows);
  }
}

class _AgendaEventCard extends StatelessWidget {
  const _AgendaEventCard({required this.event, required this.association});

  final AssociationEvent event;
  final Association? association;

  @override
  Widget build(BuildContext context) {
    final coverUrl = event.coverUrl;
    final day = event.startsAt.day.toString().padLeft(2, '0');
    final coverWidth = (72 * MediaQuery.devicePixelRatioOf(context)).round();
    final coverHeight = (88 * MediaQuery.devicePixelRatioOf(context)).round();
    final month = _months[event.startsAt.month - 1]
        .substring(0, 3)
        .toUpperCase();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CampusSpacing.gutter,
        0,
        CampusSpacing.gutter,
        CampusSpacing.x2,
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  AssociationDetailScreen(associationId: event.associationId),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: <Widget>[
                Container(
                  width: 72,
                  padding: const EdgeInsets.symmetric(
                    horizontal: CampusSpacing.x2,
                    vertical: CampusSpacing.x3,
                  ),
                  color: context.scheme.primaryContainer,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        day,
                        style: context.text.headlineSmall?.copyWith(
                          color: context.scheme.onPrimaryContainer,
                        ),
                      ),
                      Text(
                        month,
                        style: context.text.labelMedium?.copyWith(
                          color: context.scheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CampusSpacing.x3,
                      CampusSpacing.x3,
                      CampusSpacing.x2,
                      CampusSpacing.x3,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(event.title, style: context.text.titleSmall),
                        const SizedBox(height: CampusSpacing.x1),
                        Text(
                          <String>[
                            if (!event.isAllDay) _clock(event.startsAt),
                            ?association?.displayName,
                            ?event.location,
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(
                            color: context.scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (coverUrl != null)
                  SizedBox(
                    width: 72,
                    height: 88,
                    child: Image.network(
                      coverUrl,
                      fit: BoxFit.cover,
                      cacheWidth: coverWidth,
                      cacheHeight: coverHeight,
                      filterQuality: FilterQuality.low,
                      errorBuilder: (context, _, _) => const SizedBox.shrink(),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(CampusSpacing.x3),
                    child: Icon(
                      Icons.auto_awesome,
                      color: context.scheme.secondary,
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
