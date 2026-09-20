import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/campus_context.dart';
import '../../theme/state_view.dart';
import '../../theme/tokens.dart';
import 'ade_groups.dart';
import 'ade_groups_provider.dart';
import 'ade_tree.dart';
import 'group_picker_screen.dart';
import 'group_wizard/group_wizard_screen.dart';
import 'import_link_sheet.dart';
import 'schedule_provider.dart';
import 'selection_share.dart';

/// What the timetable is following, and every way to change it.
///
/// The feature needed one stable place to come back to. Before this, changing
/// a group meant re-entering the tree and rebuilding the whole selection from
/// memory, with no screen anywhere that simply said what was currently
/// subscribed.
///
/// The stored selection is a flat list of ADE ids and stays that way. The
/// grouping below is computed, not stored, so a selection built by pasting a
/// link reads the same as one built by the wizard.
class MySelectionScreen extends ConsumerWidget {
  const MySelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(selectedGroupsProvider);
    final rows = ref.watch(adeGroupsProvider).value ?? const <AdeGroup>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ma sélection'),
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Importer un lien ADE',
            onPressed: () => unawaited(_import(context, ref)),
          ),
        ],
      ),
      body: ids.isEmpty
          ? _empty(context)
          : _list(context, ref, ids: ids, rows: rows),
    );
  }

  Widget _empty(BuildContext context) => StateView(
    icon: Icons.group_outlined,
    title: 'Aucun groupe choisi',
    body:
        'Quelques questions et votre emploi du temps s’affiche, '
        'même hors ligne.',
    action: FilledButton(
      onPressed: () => unawaited(_openWizard(context)),
      child: const Text('Choisir mon groupe'),
    ),
  );

  Widget _list(
    BuildContext context,
    WidgetRef ref, {
    required List<int> ids,
    required List<AdeGroup> rows,
  }) {
    final sections = _sections(ids, rows);
    return ListView(
      padding: const EdgeInsets.only(bottom: CampusSpacing.x8),
      children: [
        for (final section in sections) ...[
          _SectionHeader(section.heading),
          for (final id in section.ids)
            _ResourceTile(
              id: id,
              rows: rows,
              below: section.headingId,
              onRemove: () => unawaited(
                ref
                    .read(selectedGroupsProvider.notifier)
                    .set(ids.where((i) => i != id).toList()),
              ),
            ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CampusSpacing.gutter,
            CampusSpacing.x4,
            CampusSpacing.gutter,
            0,
          ),
          child: OutlinedButton.icon(
            onPressed: () => unawaited(_openWizard(context)),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Refaire le choix'),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Ajouter un groupe ou une option'),
          onTap: () => unawaited(_openPicker(context)),
        ),
        const Divider(height: CampusSpacing.x6),
        ListTile(
          leading: const Icon(Icons.ios_share),
          title: const Text('Partager ma sélection'),
          subtitle: const Text(
            'Un lien que votre promo peut ouvrir ou importer',
          ),
          onTap: () => unawaited(_share(context, ids)),
        ),
        ListTile(
          leading: const Icon(Icons.account_tree_outlined),
          title: const Text('Parcourir tout ADE'),
          subtitle: const Text('Avancé : l’arborescence complète'),
          onTap: () => unawaited(_openPicker(context)),
        ),
        _EventCount(),
      ],
    );
  }

  /// The selection split under one heading per semester, in the order the
  /// wizard committed them.
  List<({String heading, int? headingId, List<int> ids})> _sections(
    List<int> ids,
    List<AdeGroup> rows,
  ) {
    final headings = <String, ({int? id, List<int> ids})>{};
    for (final id in ids) {
      final node = AdeTree.groupingNodeFor(rows, id);
      headings
          .putIfAbsent(
            node?.name ?? 'Autres',
            () => (id: node?.id, ids: <int>[]),
          )
          .ids
          .add(id);
    }
    return <({String heading, int? headingId, List<int> ids})>[
      for (final e in headings.entries)
        (heading: e.key, headingId: e.value.id, ids: e.value.ids),
    ];
  }

  Future<void> _openWizard(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const GroupWizardScreen()));

  Future<void> _openPicker(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const GroupPickerScreen()));

  Future<void> _share(BuildContext context, List<int> ids) async {
    final url = SelectionShare.buildUrl(ids);
    if (url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Lien copié.')));
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final ids = await showImportLinkSheet(context);
    if (ids == null) return;
    await ref.read(selectedGroupsProvider.notifier).set(ids);
  }
}

/// One selected resource: its name, where it sits under its heading, and a
/// way to drop it.
class _ResourceTile extends StatelessWidget {
  const _ResourceTile({
    required this.id,
    required this.rows,
    this.below,
    this.onRemove,
  });

  final int id;
  final List<AdeGroup> rows;

  /// The heading this row sits under, trimmed off its path.
  final int? below;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final match = rows.where((g) => g.id == id).firstOrNull;
    // An id can outlive the list that named it: ADE renumbers between years,
    // and a pasted link can carry anything. Showing the number beats dropping
    // the row, since the timetable is still following it.
    final name = match?.name ?? 'Ressource $id';
    final path = match == null ? '' : AdeTree.pathLabel(rows, id, from: below);

    return ListTile(
      title: Text(name),
      subtitle: path.isEmpty
          ? null
          : Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelMedium?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
      trailing: onRemove == null
          ? null
          : IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Retirer $name',
              onPressed: onRemove,
            ),
    );
  }
}

/// How much the current selection actually produces, read off the timetable
/// already in the cache so it costs no extra request.
class _EventCount extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(scheduleProvider).value?.data;
    if (events == null || events.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(CampusSpacing.gutter),
      child: Text(
        '${events.length} cours sur les huit prochaines semaines',
        style: context.text.labelMedium?.copyWith(
          color: context.scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      CampusSpacing.gutter,
      CampusSpacing.x5,
      CampusSpacing.gutter,
      CampusSpacing.x1,
    ),
    child: Text(
      label,
      style: context.text.labelLarge?.copyWith(color: context.scheme.primary),
    ),
  );
}
