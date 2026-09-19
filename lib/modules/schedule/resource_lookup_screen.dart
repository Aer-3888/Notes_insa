import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time.dart';
import '../../theme/state_view.dart';
import '../../theme/tokens.dart';
import 'ade_groups.dart';
import 'ade_groups_provider.dart';
import 'ade_tree.dart';
import 'schedule_day_index.dart';
import 'schedule_event.dart';
import 'schedule_provider.dart';
import 'schedule_timeline.dart';

/// Looks a room or a subject up without subscribing to it.
///
/// Split out of the group picker, which used to offer Groupes, Salles and
/// Matières behind one Valider button. Those are two different verbs: a group
/// is what your timetable follows, a room is something you check once because
/// you want to know whether it is free. Mixing them meant "where is Amphi C?"
/// could quietly rewrite your timetable.
class ResourceLookupScreen extends ConsumerStatefulWidget {
  const ResourceLookupScreen({super.key});

  @override
  ConsumerState<ResourceLookupScreen> createState() =>
      _ResourceLookupScreenState();
}

class _ResourceLookupScreenState extends ConsumerState<ResourceLookupScreen> {
  final _controller = TextEditingController();

  /// Rooms first, because it is the question people arrive with.
  AdeCategory _category = AdeCategory.room;

  static const List<AdeCategory> _categories = <AdeCategory>[
    AdeCategory.room,
    AdeCategory.module,
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(adeGroupsProvider).value;
    final rows = all == null
        ? const <AdeGroup>[]
        : AdeTree.search(
            AdeGroups.ofCategory(all, _category),
            _controller.text,
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Salles et matières')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CampusSpacing.x3,
              CampusSpacing.x3,
              CampusSpacing.x3,
              CampusSpacing.x2,
            ),
            child: TextField(
              controller: _controller,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Rechercher (ex. Amphi C)',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: CampusSpacing.x3),
              children: [
                for (final c in _categories)
                  Padding(
                    padding: const EdgeInsets.only(right: CampusSpacing.x2),
                    child: ChoiceChip(
                      label: Text(c.label),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: CampusSpacing.x1),
          if (all == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (rows.isEmpty)
            const Expanded(
              child: StateView(
                icon: Icons.search_off_outlined,
                title: 'Aucun résultat',
                body: 'Essayez un autre nom, par exemple Amphi C.',
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, i) => ListTile(
                  title: Text(rows[i].name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ResourceScheduleScreen(resource: rows[i]),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One resource's timetable, fetched on its own and shown read-only.
class ResourceScheduleScreen extends ConsumerStatefulWidget {
  const ResourceScheduleScreen({super.key, required this.resource});

  final AdeGroup resource;

  @override
  ConsumerState<ResourceScheduleScreen> createState() =>
      _ResourceScheduleScreenState();
}

class _ResourceScheduleScreenState
    extends ConsumerState<ResourceScheduleScreen> {
  final ScrollController _scroll = ScrollController();

  late Future<List<ScheduleEvent>> _events;
  late DateTime _from;
  late DateTime _to;

  @override
  void initState() {
    super.initState();
    // Not cached: a lookup is a one-off, and caching it would compete with the
    // user's own timetable for the one schedule cache slot.
    final now = campusNow();
    _from = now.subtract(kScheduleLookback);
    _to = now.add(kScheduleLookahead);
    _events = ref
        .read(adeServiceProvider)
        .fetch(resourceIds: <int>[widget.resource.id], from: _from, to: _to);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.resource.name)),
    body: FutureBuilder<List<ScheduleEvent>>(
      future: _events,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return StateView(
            icon: Icons.cloud_off_outlined,
            title: 'Emploi du temps indisponible',
            body:
                'Impossible de joindre ADE. Vérifiez la connexion, '
                'puis réessayez.',
            action: FilledButton.tonalIcon(
              onPressed: () => setState(() {
                _events = ref
                    .read(adeServiceProvider)
                    .fetch(
                      resourceIds: <int>[widget.resource.id],
                      from: _from,
                      to: _to,
                    );
              }),
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          );
        }
        final events = snapshot.data ?? const <ScheduleEvent>[];
        if (events.isEmpty) {
          return const StateView(
            icon: Icons.event_busy_outlined,
            title: 'Rien de prévu',
            body: 'ADE ne publie aucune séance pour cette ressource.',
          );
        }
        return ScheduleTimeline(
          index: ScheduleDayIndex.build(events: events, from: _from, to: _to),
          controller: _scroll,
          now: campusNow(),
        );
      },
    ),
  );
}
