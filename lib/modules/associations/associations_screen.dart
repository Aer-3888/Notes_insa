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

    final matches = all.where((a) => a.matches(_query.text)).toList();
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
            _header(category.label),
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

  Widget _header(String label) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        CampusSpacing.gutter,
        CampusSpacing.x4,
        CampusSpacing.gutter,
        CampusSpacing.x1,
      ),
      child: Text(
        label,
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
    return ListTile(
      onTap: onTap,
      leading: _AssociationAvatar(association: association),
      title: Text(association.name),
      subtitle: summary == null
          ? null
          : Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        icon: Icon(isFollowed ? Icons.notifications : Icons.notifications_none),
        tooltip: isFollowed ? 'Ne plus suivre' : 'Suivre',
        color: isFollowed ? context.scheme.primary : null,
        onPressed: () => ref
            .read(associationFollowsProvider.notifier)
            .toggle(association.id),
      ),
    );
  }
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
    if (asset != null || logoUrl != null) {
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
