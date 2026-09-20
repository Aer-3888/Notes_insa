import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/freshness.dart' as freshness;
import '../../theme/campus_context.dart';
import '../../theme/state_view.dart';
import '../../theme/tokens.dart';
import '../schedule/ade_groups.dart';
import '../schedule/ade_groups_provider.dart';
import '../schedule/ade_tree.dart';
import '../schedule/resource_lookup_screen.dart';
import 'room_filter.dart';
import 'room_status.dart';
import 'rooms_provider.dart';

class RoomsScreen extends ConsumerStatefulWidget {
  const RoomsScreen({super.key, this.initialBuildingCode});

  final String? initialBuildingCode;

  @override
  ConsumerState<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends ConsumerState<RoomsScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _searching => _search.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final entry = ref.watch(roomsProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Salles libres'),
        bottom: entry == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(18),
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: CampusSpacing.gutter,
                    bottom: CampusSpacing.x2,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      freshness.freshnessLabel(
                        entry.refreshState,
                        entry.cachedAt,
                      ),
                      style: context.text.labelSmall?.copyWith(
                        color: context.scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: () => ref.invalidate(roomsProvider),
          ),
        ],
      ),
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
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Rechercher une salle',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Effacer la recherche',
                        onPressed: () => setState(_search.clear),
                      )
                    : null,
              ),
            ),
          ),
          const _DurationFilter(),
          Expanded(child: _searching ? _searchResults() : _freeList()),
        ],
      ),
    );
  }

  Widget _searchResults() {
    final all = ref.watch(adeGroupsProvider).value;
    if (all == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final rows = AdeTree.search(
      AdeGroups.ofCategory(all, AdeCategory.room),
      _search.text,
    );
    if (rows.isEmpty) {
      return const StateView(
        icon: Icons.search_off_outlined,
        title: 'Aucune salle',
        body: 'Essayez un autre nom, par exemple Amphi C.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        CampusSpacing.gutter,
        CampusSpacing.x2,
        CampusSpacing.gutter,
        CampusSpacing.x8,
      ),
      itemCount: rows.length,
      itemBuilder: (context, i) => ListTile(
        title: Text(rows[i].name),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(rows[i]),
      ),
    );
  }

  Widget _freeList() {
    final async = ref.watch(roomsProvider);
    final buildings = ref.watch(roomBuildingsProvider).value;
    final entry = async.value;

    if (entry?.data == null) {
      if (async.isLoading || entry == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return StateView(
        icon: Icons.cloud_off_outlined,
        title: 'Salles indisponibles',
        body:
            'Impossible de joindre ADE. Vérifiez la connexion, '
            'puis réessayez.',
        action: FilledButton.tonalIcon(
          onPressed: () => ref.invalidate(roomsProvider),
          icon: const Icon(Icons.refresh),
          label: const Text('Réessayer'),
        ),
      );
    }

    final freeRooms = ref.watch(freeRoomsProvider) ?? const <RoomStatus>[];
    final grouped = groupByBuilding(freeRooms, (room) => buildings?[room.id]);
    final requestedBuilding = widget.initialBuildingCode;
    final free = requestedBuilding == null
        ? grouped
        : <RoomBuilding>[
            ...grouped.where((group) => group.building == requestedBuilding),
            ...grouped.where((group) => group.building != requestedBuilding),
          ];
    final busy = (ref.watch(roomStatusesProvider) ?? const <RoomStatus>[])
        .where((status) => !status.isFree)
        .toList();
    final filter = ref.watch(roomFreeDurationProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(roomsProvider),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          CampusSpacing.gutter,
          CampusSpacing.x2,
          CampusSpacing.gutter,
          CampusSpacing.x8,
        ),
        children: [
          if (free.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: CampusSpacing.x4),
              child: Text(
                filter == RoomFreeDuration.now
                    ? 'Aucune salle libre pour le moment.'
                    : 'Aucune salle libre pendant ${filter.label}.',
              ),
            ),
          for (final group in free)
            _BuildingCard(
              key: ValueKey('building-${group.building}'),
              group: group,
              initiallyExpanded: group.building == requestedBuilding,
              onOpen: _open,
            ),
          if (busy.isNotEmpty)
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: CampusSpacing.x3,
                ),
                leading: const Icon(Icons.event_busy_outlined),
                title: const Text('Occupées'),
                subtitle: Text(
                  '${busy.length} salle${busy.length > 1 ? 's' : ''}',
                ),
                children: [
                  for (final status in busy)
                    _RoomTile(status: status, onTap: () => _open(status.room)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _open(AdeGroup room) => unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ResourceScheduleScreen(resource: room),
      ),
    ),
  );
}

class _BuildingCard extends StatefulWidget {
  const _BuildingCard({
    super.key,
    required this.group,
    required this.initiallyExpanded,
    required this.onOpen,
  });

  final RoomBuilding group;
  final bool initiallyExpanded;
  final ValueChanged<AdeGroup> onOpen;

  @override
  State<_BuildingCard> createState() => _BuildingCardState();
}

class _BuildingCardState extends State<_BuildingCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final motion = CampusMotion.of(context, CampusMotion.exit);
    return Padding(
      padding: const EdgeInsets.only(bottom: CampusSpacing.x2),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: true,
              expanded: _expanded,
              child: InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: CampusSpacing.x3,
                  ),
                  leading: const Icon(Icons.apartment_outlined),
                  title: Text('Bâtiment ${widget.group.building}'),
                  subtitle: Text(
                    '${widget.group.rooms.length} salle${widget.group.rooms.length > 1 ? 's' : ''} libre${widget.group.rooms.length > 1 ? 's' : ''}',
                  ),
                  trailing: AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: motion,
                    curve: CampusMotion.standard,
                    child: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ),
              ),
            ),
            ClipRect(
              child: AnimatedSize(
                duration: motion,
                curve: CampusMotion.enterCurve,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Divider(height: 1),
                          for (final status in widget.group.rooms)
                            _RoomTile(
                              status: status,
                              onTap: () => widget.onOpen(status.room),
                            ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DurationFilter extends ConsumerWidget {
  const _DurationFilter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(roomFreeDurationProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CampusSpacing.gutter,
        0,
        CampusSpacing.gutter,
        CampusSpacing.x2,
      ),
      child: SegmentedButton<RoomFreeDuration>(
        expandedInsets: EdgeInsets.zero,
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(0, CampusSpacing.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: CampusSpacing.x1),
          textStyle: context.text.labelMedium,
          animationDuration: CampusMotion.of(context, CampusMotion.fast),
        ),
        segments: [
          for (final value in RoomFreeDuration.values)
            ButtonSegment<RoomFreeDuration>(
              value: value,
              label: Text(value.label),
            ),
        ],
        selected: {selected},
        onSelectionChanged: (selection) => ref
            .read(roomFreeDurationProvider.notifier)
            .select(selection.single),
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.status, required this.onTap});

  final RoomStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(
      status.isFree
          ? Icons.event_available_outlined
          : Icons.event_busy_outlined,
      color: status.isFree ? context.scheme.primary : context.scheme.outline,
    ),
    title: Text(status.room.name),
    subtitle: Text(
      _subtitle(status),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.text.labelMedium?.copyWith(
        color: context.scheme.onSurfaceVariant,
      ),
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );

  static String _subtitle(RoomStatus s) {
    final until = s.until;
    if (s.isFree) {
      if (until == null) return 'Libre le reste de la journée';
      return 'Libre pendant ${_short(s.freeFor!)}, jusqu’à ${_hm(until)}';
    }
    final title = s.current?.title ?? 'Occupée';
    return until == null ? title : '$title, jusqu’à ${_hm(until)}';
  }

  static String _hm(DateTime d) =>
      '${d.hour}h${d.minute.toString().padLeft(2, '0')}';

  static String _short(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours == 0) return '$minutes min';
    if (minutes == 0) return '$hours h';
    return '$hours h $minutes';
  }
}
