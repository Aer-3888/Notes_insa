import 'package:flutter/material.dart';

import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'association.dart';

class AssociationOrganigramScreen extends StatelessWidget {
  const AssociationOrganigramScreen({
    super.key,
    required this.associationName,
    required this.organigram,
  });

  final String associationName;
  final AssociationOrganigram organigram;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('L’équipe')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        CampusSpacing.gutter,
        CampusSpacing.x4,
        CampusSpacing.gutter,
        CampusSpacing.x8,
      ),
      children: <Widget>[
        Text(associationName, style: context.text.titleLarge),
        const SizedBox(height: CampusSpacing.x1),
        Text(
          organigram.title,
          style: context.text.bodyMedium?.copyWith(
            color: context.scheme.onSurfaceVariant,
          ),
        ),
        for (final section in organigram.sections) ...<Widget>[
          const SizedBox(height: CampusSpacing.x5),
          _TeamSection(section: section),
        ],
      ],
    ),
  );
}

class _TeamSection extends StatelessWidget {
  const _TeamSection({required this.section});

  final AssociationOrganigramSection section;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CampusSpacing.x4,
            CampusSpacing.x3,
            CampusSpacing.x4,
            CampusSpacing.x1,
          ),
          child: Text(section.title, style: context.text.titleSmall),
        ),
        for (final member in section.members)
          ListTile(
            minVerticalPadding: CampusSpacing.x2,
            leading: CircleAvatar(
              backgroundColor: context.campus.nowContainer,
              foregroundColor: context.campus.onNow,
              child: Text(_initials(member.name)),
            ),
            title: Text(member.role),
            subtitle: Text(member.name),
          ),
      ],
    ),
  );
}

String _initials(String name) {
  final words = name.split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
  return words.take(2).map((word) => word[0].toUpperCase()).join();
}
