import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'ade_breadcrumb.dart';
import 'ade_groups.dart';
import 'ade_groups_provider.dart';
import 'ade_link.dart';
import 'ade_tree.dart';
import 'ade_tree_list.dart';
import 'import_link_sheet.dart';
import 'schedule_provider.dart';

/// The whole ADE group tree, for the cases the wizard's four questions cannot
/// express: a second promo, a branch that does not nest the way the others do,
/// or adding one elective to an existing selection.
///
/// Reached from "Ma sélection", never as the first thing a new user sees. It
/// browses rather than teaches, so it assumes you know what you are looking
/// for.
class GroupPickerScreen extends ConsumerStatefulWidget {
  const GroupPickerScreen({super.key});

  /// Same ceiling as the ade-planning web app, so a selection that works there
  /// works here. A cap below this silently truncated real students' groups.
  static const int maxSelection = AdeLink.maxIds;

  @override
  ConsumerState<GroupPickerScreen> createState() => _GroupPickerScreenState();
}

class _GroupPickerScreenState extends ConsumerState<GroupPickerScreen> {
  final _controller = TextEditingController();

  late Set<int> _selected;
  late Set<int> _initial;

  /// Null at the top level, otherwise the node we have drilled into.
  int? _parentId;

  /// Set on the first toggle. Until then the draft follows the stored
  /// selection, which arrives a frame or two late because it is restored from
  /// shared_preferences asynchronously.
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _initial = ref.read(selectedGroupsProvider).toSet();
    _selected = _initial.toSet();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _searching => _controller.text.trim().isNotEmpty;

  bool get _dirty =>
      _selected.length != _initial.length || !_selected.containsAll(_initial);

  void _toggle(AdeGroup g) {
    _touched = true;
    if (_selected.contains(g.id)) {
      setState(() => _selected.remove(g.id));
      return;
    }
    if (_selected.length >= GroupPickerScreen.maxSelection) {
      // Silently refusing the tap was the old behaviour, and it read as the
      // screen being broken.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ADE n’accepte pas plus de '
            '${GroupPickerScreen.maxSelection} groupes à la fois.',
          ),
        ),
      );
      return;
    }
    setState(() => _selected.add(g.id));
  }

  Future<void> _save() async {
    await ref.read(selectedGroupsProvider.notifier).set(_selected.toList());
    _initial = _selected.toSet();
  }

  /// Back leaves the screen. Climbing is the breadcrumb's job. The old picker
  /// bound it to the system back button, which meant five presses to escape a
  /// five-level branch and no way out at all from the deepest ones.
  Future<void> _confirmLeave() async {
    final keep = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Garder les modifications ?'),
        content: const Text(
          'Votre sélection de groupes a changé mais n’a pas été enregistrée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abandonner'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (keep == null || !mounted) return;
    if (keep) await _save();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _import() async {
    final ids = await showImportLinkSheet(context);
    if (ids == null || !mounted) return;
    setState(() {
      _touched = true;
      _selected
        ..clear()
        ..addAll(ids);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(selectedGroupsProvider, (_, next) {
      if (_touched) return;
      setState(() {
        _initial = next.toSet();
        _selected = next.toSet();
      });
    });
    final all = ref.watch(adeGroupsProvider).value;
    final students = all == null
        ? const <AdeGroup>[]
        : AdeGroups.ofCategory(all, AdeCategory.student);
    // Search ignores the current position in the tree: someone typing
    // "S7-INFO-ROBO" should find it without knowing it lives under INFO.
    final visible = all == null
        ? const <AdeGroup>[]
        : _searching
        ? AdeTree.search(students, _controller.text)
        : AdeTree.childrenOf(students, _parentId);
    final breadcrumb = _parentId == null
        ? const <AdeGroup>[]
        : AdeTree.pathTo(students, _parentId!);

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_confirmLeave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Parcourir les groupes'),
          actions: [
            IconButton(
              icon: const Icon(Icons.link),
              tooltip: 'Coller un lien ADE',
              onPressed: () => unawaited(_import()),
            ),
            TextButton(
              onPressed: !_dirty
                  ? null
                  : () async {
                      await _save();
                      if (context.mounted) Navigator.of(context).pop();
                    },
              child: Text('Valider (${_selected.length})'),
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
                controller: _controller,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Rechercher (ex. S7-INFO-ROBO)',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searching
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'Effacer la recherche',
                          onPressed: () => setState(_controller.clear),
                        )
                      : null,
                ),
              ),
            ),
            if (!_searching && breadcrumb.isNotEmpty)
              AdeBreadcrumb(
                path: breadcrumb,
                onRoot: () => setState(() => _parentId = null),
                onTap: (g) => setState(() => _parentId = g.id),
              ),
            if (all == null)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: AdeTreeList(
                  rows: students,
                  visible: visible,
                  selected: _selected,
                  showPath: _searching,
                  onToggle: _toggle,
                  onDrill: (g) => setState(() => _parentId = g.id),
                ),
              ),
            _SelectionTray(
              rows: students,
              selected: _selected,
              onRemove: (id) => setState(() {
                _touched = true;
                _selected.remove(id);
              }),
            ),
          ],
        ),
      ),
    );
  }
}

/// The current selection, pinned under the list.
///
/// Without it the selection is invisible the moment you drill into another
/// branch, and the only feedback is a count in the app bar, which is how the
/// old screen let people lose track of what they had already picked.
class _SelectionTray extends StatelessWidget {
  const _SelectionTray({
    required this.rows,
    required this.selected,
    required this.onRemove,
  });

  final List<AdeGroup> rows;
  final Set<int> selected;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    if (selected.isEmpty) return const SizedBox.shrink();
    final byId = <int, AdeGroup>{for (final g in rows) g.id: g};
    return Material(
      color: context.scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: CampusSpacing.x3,
              vertical: CampusSpacing.x2,
            ),
            children: [
              for (final id in selected)
                Padding(
                  padding: const EdgeInsets.only(right: CampusSpacing.x2),
                  child: InputChip(
                    label: Text(byId[id]?.name ?? 'Ressource $id'),
                    onDeleted: () => onRemove(id),
                    deleteButtonTooltipMessage:
                        'Retirer ${byId[id]?.name ?? id}',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
