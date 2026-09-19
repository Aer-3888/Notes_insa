import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/campus_navigation.dart';
import '../../core/time.dart';
import '../../theme/campus_context.dart';
import '../../theme/state_view.dart';
import '../../theme/tokens.dart';
import 'association.dart';
import 'association_follow_action.dart';
import 'association_follows.dart';
import 'association_logo.dart';
import 'association_notification_permission.dart';
import 'association_organigram_screen.dart';
import 'association_reminder_provider.dart';
import 'association_reminders.dart';
import 'association_service.dart';

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
    final reminderLead = ref.watch(associationReminderLeadProvider);
    final permission = ref.watch(associationNotificationPermissionProvider);
    final now = campusNow();
    final upcoming = association.upcoming(now);
    final past = association.past(now);
    final recruitment = association.recruitment;

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
            onPressed: () => unawaited(
              toggleAssociationFollow(context, ref, association.id),
            ),
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
          if (isFollowed &&
              reminderLead != AssociationReminderLead.off &&
              permission.value?.isGranted == false)
            Padding(
              padding: const EdgeInsets.only(top: CampusSpacing.x2),
              child: _ReminderDisabled(
                onOpenSettings: () => unawaited(openAppSettings()),
              ),
            ),
          if (association.description case final description?) ...<Widget>[
            const SizedBox(height: CampusSpacing.x5),
            const _SectionHeader('À propos'),
            Text(description, style: context.text.bodyLarge),
          ],
          if (association.organigram case final organigram?) ...<Widget>[
            const SizedBox(height: CampusSpacing.x5),
            _OrganigramEntry(
              associationName: association.displayName,
              organigram: organigram,
            ),
          ],
          if (association.buildingCode case final code?) ...<Widget>[
            const SizedBox(height: CampusSpacing.x4),
            _LocalRow(buildingCode: code),
          ],
          if (!association.links.isEmpty) ...<Widget>[
            const SizedBox(height: CampusSpacing.x5),
            _Links(links: association.links),
          ],
          if (association.faqs.isNotEmpty) ...<Widget>[
            const _SectionHeader('Questions fréquentes'),
            _Faqs(faqs: association.faqs),
          ],
          if (recruitment?.isVisible == true ||
              upcoming.isNotEmpty) ...<Widget>[
            const _SectionHeader('Que puis-je faire ici ?'),
            if (recruitment case final openRecruitment?
                when openRecruitment.isVisible)
              _RecruitmentEntry(recruitment: openRecruitment),
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

class _RecruitmentEntry extends StatelessWidget {
  const _RecruitmentEntry({required this.recruitment});

  final AssociationRecruitment recruitment;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(CampusSpacing.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.person_add_alt_1_outlined),
          const SizedBox(width: CampusSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  recruitment.title ?? 'Recrutement ouvert',
                  style: context.text.titleSmall,
                ),
                if (recruitment.description
                    case final description?) ...<Widget>[
                  const SizedBox(height: CampusSpacing.x1),
                  Text(description),
                ],
                if (recruitment.url case final url?)
                  TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(url),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Candidater'),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _Faqs extends StatelessWidget {
  const _Faqs({required this.faqs});

  final List<AssociationFaq> faqs;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: <Widget>[
        for (var index = 0; index < faqs.length; index++) ...<Widget>[
          ExpansionTile(
            title: Text(faqs[index].question),
            childrenPadding: const EdgeInsets.fromLTRB(
              CampusSpacing.x4,
              0,
              CampusSpacing.x4,
              CampusSpacing.x3,
            ),
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(faqs[index].answer),
              ),
            ],
          ),
          if (index != faqs.length - 1) const Divider(height: 1),
        ],
      ],
    ),
  );
}

class _ReminderDisabled extends StatelessWidget {
  const _ReminderDisabled({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(CampusSpacing.x3),
      child: Row(
        children: <Widget>[
          const Icon(Icons.notifications_off_outlined),
          const SizedBox(width: CampusSpacing.x3),
          Expanded(
            child: Text('Rappels désactivés', style: context.text.bodyMedium),
          ),
          TextButton(onPressed: onOpenSettings, child: const Text('Activer')),
        ],
      ),
    ),
  );
}

class _OrganigramEntry extends StatelessWidget {
  const _OrganigramEntry({
    required this.associationName,
    required this.organigram,
  });

  final String associationName;
  final AssociationOrganigram organigram;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      key: const Key('association-organigram'),
      leading: const Icon(Icons.account_tree_outlined),
      title: const Text('L’équipe'),
      subtitle: Text('${organigram.title} · ${organigram.memberCount} membres'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AssociationOrganigramScreen(
            associationName: associationName,
            organigram: organigram,
          ),
        ),
      ),
    ),
  );
}

class _Identity extends StatelessWidget {
  const _Identity({required this.association});

  final Association association;

  @override
  Widget build(BuildContext context) {
    final summary = association.summary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        AssociationLogo(
          association: association,
          size: 56,
          initialsStyle: context.text.titleMedium,
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
      if (links.linkedin case final url?)
        (Icons.business_center_outlined, 'LinkedIn', Uri.parse(url)),
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
