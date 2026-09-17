import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/campus_navigation.dart';
import '../../core/time.dart';
import '../../theme/campus_context.dart';
import '../../theme/state_view.dart';
import '../../theme/tokens.dart';
import 'association.dart';
import 'association_follows.dart';
import 'association_service.dart';
import 'associations_screen.dart' show associationInitials;

/// One association's page.
///
/// Looked up by id rather than passed whole, so it survives the directory
/// reloading underneath it when phase 2 puts it behind the API.
class AssociationDetailScreen extends ConsumerWidget {
  const AssociationDetailScreen({super.key, required this.associationId});

  final String associationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(associationsProvider).value;
    final association = all
        ?.where((a) => a.id == associationId)
        .cast<Association?>()
        .firstWhere((a) => true, orElse: () => null);

    if (association == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const StateView(
          icon: Icons.groups_outlined,
          title: 'Association introuvable',
        ),
      );
    }

    final follows = ref.watch(associationFollowsProvider);
    final isFollowed = follows.contains(association.id);
    final now = campusNow();
    final upcoming = association.upcoming(now);
    final past = association.past(now);

    return Scaffold(
      appBar: AppBar(title: Text(association.displayName)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          CampusSpacing.gutter,
          CampusSpacing.x4,
          CampusSpacing.gutter,
          CampusSpacing.x8,
        ),
        children: <Widget>[
          _Identity(association: association),
          const SizedBox(height: CampusSpacing.x5),
          FilledButton.tonalIcon(
            onPressed: () => ref
                .read(associationFollowsProvider.notifier)
                .toggle(association.id),
            icon: Icon(
              isFollowed
                  ? Icons.notifications_active
                  : Icons.notifications_none,
            ),
            label: Text(isFollowed ? 'Suivie' : 'Suivre'),
          ),
          if (isFollowed)
            Padding(
              padding: const EdgeInsets.only(top: CampusSpacing.x2),
              child: Text(
                'Ses évènements apparaissent dans Aujourd’hui.',
                style: context.text.bodySmall?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
            ),
          if (association.description case final description?) ...<Widget>[
            const SizedBox(height: CampusSpacing.x5),
            Text(description, style: context.text.bodyLarge),
          ],
          if (association.buildingCode case final code?) ...<Widget>[
            const SizedBox(height: CampusSpacing.x4),
            _LocalRow(buildingCode: code),
          ],
          if (!association.links.isEmpty) ...<Widget>[
            const SizedBox(height: CampusSpacing.x5),
            _Links(links: association.links),
          ],
          if (upcoming.isNotEmpty) ...<Widget>[
            const _SectionHeader('À venir'),
            for (final event in upcoming)
              _EventTile(event: event, isPast: false),
          ],
          if (past.isNotEmpty) ...<Widget>[
            const _SectionHeader('Déjà passé'),
            for (final event in past.take(5))
              _EventTile(event: event, isPast: true),
          ],
          if (upcoming.isEmpty && past.isEmpty) ...<Widget>[
            const SizedBox(height: CampusSpacing.x6),
            Text(
              'Aucun évènement pour le moment.',
              style: context.text.bodyMedium?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.association});

  final Association association;

  @override
  Widget build(BuildContext context) {
    final asset = association.logoAsset;
    final logoUrl = association.logoUrl;
    final summary = association.summary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 56,
          height: 56,
          child: asset == null && logoUrl == null
              ? _Initials(name: association.displayName)
              : ClipRRect(
                  borderRadius: CampusRadii.controlRadius,
                  child: asset != null
                      ? Image.asset(
                          asset,
                          fit: BoxFit.cover,
                          errorBuilder: (context, _, _) =>
                              _Initials(name: association.displayName),
                        )
                      : Image.network(
                          logoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, _, _) =>
                              _Initials(name: association.displayName),
                        ),
                ),
        ),
        const SizedBox(width: CampusSpacing.x4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(association.name, style: context.text.titleMedium),
              const SizedBox(height: CampusSpacing.x1),
              Text(
                association.category.label,
                style: context.text.bodySmall?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
              if (summary != null) ...<Widget>[
                const SizedBox(height: CampusSpacing.x2),
                Text(summary, style: context.text.bodyMedium),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.scheme.secondaryContainer,
      borderRadius: CampusRadii.controlRadius,
    ),
    child: Text(
      associationInitials(name),
      style: context.text.titleMedium?.copyWith(
        color: context.scheme.onSecondaryContainer,
      ),
    ),
  );
}

/// The association's room, handed to the map tab the same way a course room is.
class _LocalRow extends StatelessWidget {
  const _LocalRow({required this.buildingCode});

  final String buildingCode;

  @override
  Widget build(BuildContext context) {
    final openMap = CampusNavigationScope.maybeOf(context)?.onOpenMap;
    return Row(
      children: <Widget>[
        Icon(
          Icons.place_outlined,
          size: 20,
          color: context.scheme.onSurfaceVariant,
        ),
        const SizedBox(width: CampusSpacing.x3),
        Expanded(child: Text('Bâtiment $buildingCode')),
        if (openMap != null)
          TextButton(
            onPressed: () => openMap(buildingCode, startGuidance: false),
            child: const Text('Voir sur la carte'),
          ),
      ],
    );
  }
}

class _Links extends StatelessWidget {
  const _Links({required this.links});

  final AssociationLinks links;

  Future<void> _open(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir ce lien.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = <(IconData, String, Uri)>[
      if (links.instagramUri case final uri?)
        (Icons.camera_alt_outlined, 'Instagram', uri),
      if (links.website case final url?)
        (Icons.language, 'Site web', Uri.parse(url)),
      if (links.discord case final url?)
        (Icons.forum_outlined, 'Discord', Uri.parse(url)),
      if (links.facebook case final url?)
        (Icons.groups_outlined, 'Facebook', Uri.parse(url)),
      if (links.email case final address?)
        (Icons.mail_outline, 'Écrire', Uri(scheme: 'mailto', path: address)),
    ];

    return Wrap(
      spacing: CampusSpacing.x2,
      runSpacing: CampusSpacing.x2,
      children: <Widget>[
        for (final (icon, label, uri) in entries)
          ActionChip(
            avatar: Icon(icon, size: 18),
            label: Text(label),
            onPressed: () => _open(context, uri),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: CampusSpacing.x6,
      bottom: CampusSpacing.x1,
    ),
    child: Text(
      label,
      style: context.text.labelLarge?.copyWith(
        color: context.scheme.onSurfaceVariant,
      ),
    ),
  );
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.isPast});

  final AssociationEvent event;
  final bool isPast;

  @override
  Widget build(BuildContext context) {
    final openMap = CampusNavigationScope.maybeOf(context)?.onOpenMap;
    final where = event.location;
    final url = event.url;
    return Opacity(
      // Past events are context, not something to act on.
      opacity: isPast ? 0.6 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CampusSpacing.x2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(associationEventWhen(event), style: context.text.labelMedium),
            const SizedBox(height: CampusSpacing.x1),
            Text(event.title, style: context.text.titleSmall),
            if (event.description case final description?) ...<Widget>[
              const SizedBox(height: CampusSpacing.x1),
              Text(description, style: context.text.bodyMedium),
            ],
            if (where != null) ...<Widget>[
              const SizedBox(height: CampusSpacing.x1),
              Text(
                where,
                style: context.text.bodySmall?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (!isPast)
              Wrap(
                spacing: CampusSpacing.x2,
                children: <Widget>[
                  if (event.buildingCode case final code? when openMap != null)
                    TextButton.icon(
                      onPressed: () => openMap(code, startGuidance: false),
                      icon: const Icon(Icons.place_outlined, size: 18),
                      label: const Text('Sur la carte'),
                    ),
                  if (url != null)
                    TextButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('En savoir plus'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

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

/// "14 mars · 20:00", the way a poster would write it. An event the seed gave
/// no time for shows the day alone rather than an invented midnight.
String associationEventWhen(AssociationEvent event) {
  final start = event.startsAt;
  final day = '${start.day} ${_months[start.month - 1]}';
  if (event.isAllDay) return day;
  final hour = start.hour.toString().padLeft(2, '0');
  final minute = start.minute.toString().padLeft(2, '0');
  return '$day · $hour:$minute';
}
