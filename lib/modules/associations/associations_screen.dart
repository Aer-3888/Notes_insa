import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/search_text.dart';
import '../../theme/campus_context.dart';
import '../../theme/state_view.dart';
import '../../theme/tokens.dart';
import 'association.dart';
import 'association_agenda.dart';
import 'association_detail_screen.dart';
import 'association_follows.dart';
import 'association_logo.dart';
import 'association_service.dart';

/// Associations open on what is happening next. Discovery stays one tap away
/// in Explorer, where followed associations are lifted to the top.
class AssociationsScreen extends ConsumerWidget {
  const AssociationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(associationsProvider);
    final follows = ref.watch(associationFollowsProvider);

    final directory = async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const StateView(
        icon: Icons.groups_outlined,
        title: 'Annuaire indisponible',
        body: 'La liste des associations n’a pas pu être lue.',
      ),
      data: (all) => all.isEmpty
          ? const StateView(
              icon: Icons.groups_outlined,
              title: 'Bientôt',
              body:
                  'L’annuaire des associations du campus arrive. '
                  'Il est en cours de préparation.',
            )
          : _Directory(
              all: all,
              follows: follows,
              onToggle: (id) =>
                  ref.read(associationFollowsProvider.notifier).toggle(id),
            ),
    );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Associations'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'Agenda'),
              Tab(text: 'Explorer'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[const AssociationAgenda(), directory],
        ),
      ),
    );
  }
}

/// The searchable list. It owns the query and the category filter so typing
/// rebuilds the list and nothing above it.
class _Directory extends StatefulWidget {
  const _Directory({
    required this.all,
    required this.follows,
    required this.onToggle,
  });

  final List<Association> all;
  final Set<String> follows;
  final ValueChanged<String> onToggle;

  @override
  State<_Directory> createState() => _DirectoryState();
}

class _DirectoryState extends State<_Directory> {
  final TextEditingController _query = TextEditingController();
  AssociationCategory? _selectedCategory;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _open(Association association) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssociationDetailScreen(associationId: association.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.all;
    final follows = widget.follows;

    final folded = foldForSearch(_query.text);
    final offered = <AssociationCategory>{};
    final followed = <Association>[];
    final byCategory = <AssociationCategory, List<Association>>{};
    var matches = 0;

    for (final association in all) {
      if (!association.matchesFolded(folded)) continue;
      offered.add(association.category);
      if (_selectedCategory != null &&
          association.category != _selectedCategory) {
        continue;
      }
      matches++;
      if (follows.contains(association.id)) {
        followed.add(association);
      } else {
        (byCategory[association.category] ??= <Association>[]).add(association);
      }
    }

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            CampusSpacing.gutter,
            CampusSpacing.x3,
            CampusSpacing.gutter,
            CampusSpacing.x2,
          ),
          sliver: SliverToBoxAdapter(
            child: TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: all.length > 1
                    ? 'Rechercher parmi ${all.length} associations'
                    : 'Rechercher une association',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Effacer',
                        onPressed: () {
                          _query.clear();
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 42,
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: CampusSpacing.gutter,
              ),
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(right: CampusSpacing.x2),
                  child: ChoiceChip(
                    label: const Text('Tout'),
                    selected: _selectedCategory == null,
                    onSelected: (_) => setState(() => _selectedCategory = null),
                  ),
                ),
                for (final category in AssociationCategory.values)
                  if (offered.contains(category))
                    Padding(
                      padding: const EdgeInsets.only(right: CampusSpacing.x2),
                      child: ChoiceChip(
                        label: Text(category.label),
                        selected: _selectedCategory == category,
                        onSelected: (selected) => setState(
                          () => _selectedCategory = selected ? category : null,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
        if (matches == 0)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: StateView(
              icon: Icons.search_off,
              title: 'Aucun résultat',
              body: 'Essayez un autre nom.',
            ),
          ),
        if (followed.isNotEmpty) ...<Widget>[
          _header('Suivies'),
          _list(followed),
        ],
        for (final category in AssociationCategory.values)
          if (byCategory[category] case final group?) ...<Widget>[
            _header(
              category.label,
              key: Key('association-category-${category.name}'),
            ),
            _list(group),
          ],
        const SliverToBoxAdapter(child: SizedBox(height: CampusSpacing.x8)),
      ],
    );
  }

  Widget _header(String label, {Key? key}) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        CampusSpacing.gutter,
        CampusSpacing.x4,
        CampusSpacing.gutter,
        CampusSpacing.x1,
      ),
      child: Text(
        label,
        key: key,
        style: context.text.labelLarge?.copyWith(
          color: context.scheme.onSurfaceVariant,
        ),
      ),
    ),
  );

  Widget _list(List<Association> group) => SliverList.builder(
    itemCount: group.length,
    itemBuilder: (context, i) => _AssociationRow(
      association: group[i],
      isFollowed: widget.follows.contains(group[i].id),
      onTap: () => _open(group[i]),
      onToggle: () => widget.onToggle(group[i].id),
    ),
  );
}

class _AssociationRow extends StatelessWidget {
  const _AssociationRow({
    required this.association,
    required this.isFollowed,
    required this.onTap,
    required this.onToggle,
  });

  final Association association;
  final bool isFollowed;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final summary = association.summary;
    final scheme = context.scheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CampusSpacing.gutter,
        vertical: CampusSpacing.x1,
      ),
      child: Card(
        // The card already draws the rounded corners. Giving the tile the same
        // shape keeps the ink splash inside them without a clip layer.
        clipBehavior: Clip.none,
        child: ListTile(
          onTap: onTap,
          shape: const RoundedRectangleBorder(
            borderRadius: CampusRadii.cardRadius,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: CampusSpacing.x3,
            vertical: CampusSpacing.x1,
          ),
          leading: AssociationLogo(association: association, size: 40),
          title: Text(association.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: CampusSpacing.x1),
              Text(
                association.category.label,
                style: context.text.labelSmall?.copyWith(color: scheme.primary),
              ),
              if (summary != null)
                Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
          trailing: IconButton(
            icon: Icon(
              isFollowed
                  ? Icons.notifications_active
                  : Icons.notifications_none,
            ),
            tooltip: isFollowed ? 'Ne plus suivre' : 'Suivre',
            color: isFollowed ? scheme.primary : null,
            onPressed: onToggle,
          ),
        ),
      ),
    );
  }
}
