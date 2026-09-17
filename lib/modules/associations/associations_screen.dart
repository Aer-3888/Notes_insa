import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/campus_context.dart';
import '../../theme/state_view.dart';
import '../../theme/tokens.dart';
import 'association.dart';
import 'association_agenda.dart';
import 'association_detail_screen.dart';
import 'association_follows.dart';
import 'association_service.dart';

/// Associations open on what is happening next. Discovery stays one tap away
/// in Explorer, where followed associations are lifted to the top.
class AssociationsScreen extends ConsumerStatefulWidget {
  const AssociationsScreen({super.key});

  @override
  ConsumerState<AssociationsScreen> createState() => _AssociationsScreenState();
}

class _AssociationsScreenState extends ConsumerState<AssociationsScreen> {
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
    final async = ref.watch(associationsProvider);
    final follows = ref.watch(associationFollowsProvider);

    final directory = async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const StateView(
        icon: Icons.groups_outlined,
        title: 'Annuaire indisponible',
        body: 'La liste des associations n’a pas pu être lue.',
      ),
      data: (all) => _body(all, follows),
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

  Widget _body(List<Association> all, Set<String> follows) {
    if (all.isEmpty) {
      return const StateView(
        icon: Icons.groups_outlined,
        title: 'Bientôt',
        body:
            'L’annuaire des associations du campus arrive. '
            'Il est en cours de préparation.',
      );
    }

    final searchMatches = all.where((a) => a.matches(_query.text)).toList();
    final matches = _selectedCategory == null
        ? searchMatches
        : searchMatches
              .where((association) => association.category == _selectedCategory)
              .toList();
    final followed = matches.where((a) => follows.contains(a.id)).toList();
    final rest = matches.where((a) => !follows.contains(a.id)).toList();

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            CampusSpacing.gutter,
            CampusSpacing.x3,
            CampusSpacing.gutter,
            CampusSpacing.x2,
          ),
          sliver: SliverToBoxAdapter(child: _DirectoryHero(count: all.length)),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            CampusSpacing.gutter,
            0,
            CampusSpacing.gutter,
            CampusSpacing.x2,
          ),
          sliver: SliverToBoxAdapter(
            child: TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Rechercher une association',
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
                  if (searchMatches.any((a) => a.category == category))
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
        if (matches.isEmpty)
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
          _list(followed, follows),
        ],
        for (final category in AssociationCategory.values)
          if (_inCategory(rest, category) case final group
              when group.isNotEmpty) ...<Widget>[
            _header(
              category.label,
              key: Key('association-category-${category.name}'),
            ),
            _list(group, follows),
          ],
        const SliverToBoxAdapter(child: SizedBox(height: CampusSpacing.x8)),
      ],
    );
  }

  List<Association> _inCategory(
    List<Association> from,
    AssociationCategory category,
  ) => from.where((a) => a.category == category).toList();

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

  Widget _list(List<Association> group, Set<String> follows) =>
      SliverList.builder(
        itemCount: group.length,
        itemBuilder: (context, i) => _AssociationRow(
          association: group[i],
          isFollowed: follows.contains(group[i].id),
          onTap: () => _open(group[i]),
        ),
      );
}

class _AssociationRow extends ConsumerWidget {
  const _AssociationRow({
    required this.association,
    required this.isFollowed,
    required this.onTap,
  });

  final Association association;
  final bool isFollowed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = association.summary;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CampusSpacing.gutter,
        vertical: CampusSpacing.x1,
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: CampusSpacing.x3,
            vertical: CampusSpacing.x1,
          ),
          leading: _AssociationAvatar(association: association),
          title: Text(association.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: CampusSpacing.x1),
              Text(
                association.category.label,
                style: context.text.labelSmall?.copyWith(
                  color: context.scheme.primary,
                ),
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
            color: isFollowed ? context.scheme.primary : null,
            onPressed: () => ref
                .read(associationFollowsProvider.notifier)
                .toggle(association.id),
          ),
        ),
      ),
    );
  }
}

class _DirectoryHero extends StatelessWidget {
  const _DirectoryHero({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(CampusSpacing.x4),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: <Color>[
          context.scheme.primaryContainer,
          context.scheme.tertiaryContainer,
        ],
      ),
      borderRadius: CampusRadii.cardRadius,
    ),
    child: Row(
      children: <Widget>[
        Icon(
          Icons.local_activity_outlined,
          color: context.scheme.onPrimaryContainer,
          size: 34,
        ),
        const SizedBox(width: CampusSpacing.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Trouve ton collectif', style: context.text.titleMedium),
              const SizedBox(height: CampusSpacing.x1),
              Text(
                '$count associations, clubs et projets à découvrir.',
                style: context.text.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// The logo when there is one, its initials until then. Most associations will
/// not have supplied a logo during the first pass.
class _AssociationAvatar extends StatelessWidget {
  const _AssociationAvatar({required this.association});

  final Association association;

  static const double size = 40;

  @override
  Widget build(BuildContext context) {
    final asset = association.logoAsset;
    final logoUrl = association.logoUrl;
    // A long directory can create many list children just beyond the viewport.
    // Keep scrolling on the raster thread: the initials remain useful until
    // Flutter says this subtree is no longer part of a fast scroll.
    if (asset == null &&
        logoUrl != null &&
        Scrollable.recommendDeferredLoadingForContext(context)) {
      return _initials(context);
    }
    if (asset != null || logoUrl != null) {
      final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).round();
      return ClipRRect(
        borderRadius: CampusRadii.controlRadius,
        child: asset != null
            ? Image.asset(
                asset,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, _, _) => _initials(context),
              )
            : Image.network(
                logoUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                // The originals are supplied by associations and can be much
                // larger than a 40 dp avatar. Avoid retaining their full-size
                // decoded bitmaps while the directory is open.
                cacheWidth: cacheSize,
                cacheHeight: cacheSize,
                filterQuality: FilterQuality.low,
                errorBuilder: (context, _, _) => _initials(context),
              ),
      );
    }
    return _initials(context);
  }

  Widget _initials(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.scheme.secondaryContainer,
      borderRadius: CampusRadii.controlRadius,
    ),
    child: Text(
      associationInitials(association.displayName),
      style: context.text.labelLarge?.copyWith(
        color: context.scheme.onSecondaryContainer,
      ),
    ),
  );
}

/// Up to two initials, from the first two words that start with a letter.
String associationInitials(String name) {
  final words = name
      .split(RegExp(r'[\s-]+'))
      .where(
        (w) => w.isNotEmpty && RegExp(r'^\p{L}', unicode: true).hasMatch(w),
      )
      .take(2);
  if (words.isEmpty) return '?';
  return words.map((w) => w.characters.first.toUpperCase()).join();
}
