import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/campus_context.dart';
import '../../theme/state_view.dart';
import 'ade_groups.dart';
import 'ade_link.dart';
import 'schedule_provider.dart';

/// Browse ADE resources the way the web app does: drill down by department,
/// then semester, then group. Typing switches to a flat search across the whole
/// category, because 1433 rows are unusable as a single list.
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

  List<AdeGroup> _all = const <AdeGroup>[];
  late Set<int> _selected;
  bool _loading = true;
  AdeCategory _category = AdeCategory.student;

  /// Null at the top level; otherwise the node we have drilled into.
  int? _parentId;

  @override
  void initState() {
    super.initState();
    _selected = ref.read(selectedGroupsProvider).toSet();
    _load();
  }

  Future<void> _load() async {
    final groups = await AdeGroups.load();
    if (!mounted) return;
    setState(() {
      _all = groups;
      _loading = false;
    });
  }

  List<AdeGroup> get _categoryRows => AdeGroups.ofCategory(_all, _category);

  bool get _searching => _controller.text.trim().isNotEmpty;

  /// Search ignores the current position in the tree: someone typing
  /// "S7-INFO-ROBO" should find it without knowing it lives under INFO.
  List<AdeGroup> get _rows => _searching
      ? AdeGroups.search(_categoryRows, _controller.text)
      : AdeGroups.childrenOf(_categoryRows, _parentId);

  void _toggle(AdeGroup g) {
    setState(() {
      if (_selected.contains(g.id)) {
        _selected.remove(g.id);
      } else if (_selected.length < GroupPickerScreen.maxSelection) {
        _selected.add(g.id);
      }
    });
  }

  void _openCategory(AdeCategory c) => setState(() {
    _category = c;
    _parentId = null;
    _controller.clear();
  });

  Future<void> _importFromLink() async {
    final field = TextEditingController();
    final link = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Coller un lien ADE'),
        content: TextField(
          controller: field,
          autofocus: true,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'https://ade-planning.insa-rennes.fr/view/...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(field.text),
            child: const Text('Importer'),
          ),
        ],
      ),
    );
    field.dispose();
    if (link == null || !mounted) return;

    final ids = AdeLink.parseIds(link);
    if (ids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun groupe trouvé dans ce lien.')),
      );
      return;
    }
    await ref.read(selectedGroupsProvider.notifier).set(ids);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final breadcrumb = _parentId == null
        ? const <AdeGroup>[]
        : AdeGroups.pathTo(_categoryRows, _parentId!);

    return PopScope(
      // Back steps up the tree before it leaves the screen.
      canPop: _parentId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(
          () => _parentId = breadcrumb.length >= 2
              ? breadcrumb[breadcrumb.length - 2].id
              : null,
        );
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Choisir un groupe'),
          actions: [
            IconButton(
              icon: const Icon(Icons.link),
              tooltip: 'Coller un lien ADE',
              onPressed: _importFromLink,
            ),
            TextButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () async {
                      await ref
                          .read(selectedGroupsProvider.notifier)
                          .set(_selected.toList());
                      if (context.mounted) Navigator.of(context).pop();
                    },
              child: Text('Valider (${_selected.length})'),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
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
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final c in AdeCategory.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(c.label),
                        selected: _category == c,
                        onSelected: (_) => _openCategory(c),
                      ),
                    ),
                ],
              ),
            ),
            if (!_searching && breadcrumb.isNotEmpty)
              _Breadcrumb(
                path: breadcrumb,
                onRoot: () => setState(() => _parentId = null),
                onTap: (g) => setState(() => _parentId = g.id),
              ),
            const SizedBox(height: 4),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    final rows = _rows;
    if (rows.isEmpty) {
      return const StateView(
        icon: Icons.search_off_outlined,
        title: 'Aucun r\u00e9sultat',
        body: 'Essayez un autre nom de groupe, par exemple S7-INFO.',
      );
    }
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final g = rows[i];
        final selected = _selected.contains(g.id);
        final expandable =
            !_searching && AdeGroups.hasChildren(_categoryRows, g.id);
        return ListTile(
          leading: Checkbox(value: selected, onChanged: (_) => _toggle(g)),
          title: Text(g.name),
          // A parent is selectable in its own right: picking S7-INFO gives the
          // whole promotion's timetable, which is what many students want.
          subtitle: expandable
              ? Text(
                  'Contient des sous-groupes',
                  style: context.text.labelMedium?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
                )
              : null,
          trailing: expandable
              ? Icon(
                  Icons.chevron_right,
                  color: context.scheme.onSurfaceVariant,
                )
              : null,
          onTap: expandable
              ? () => setState(() => _parentId = g.id)
              : () => _toggle(g),
        );
      },
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({
    required this.path,
    required this.onRoot,
    required this.onTap,
  });

  final List<AdeGroup> path;
  final VoidCallback onRoot;
  final ValueChanged<AdeGroup> onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 34,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        TextButton(onPressed: onRoot, child: const Text('Tout')),
        for (final g in path) ...[
          Icon(
            Icons.chevron_right,
            size: 16,
            color: context.scheme.onSurfaceVariant,
          ),
          TextButton(onPressed: () => onTap(g), child: Text(g.name)),
        ],
      ],
    ),
  );
}
