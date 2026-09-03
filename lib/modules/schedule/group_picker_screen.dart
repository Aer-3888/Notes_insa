import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_colors.dart';
import 'ade_groups.dart';
import 'ade_link.dart';
import 'schedule_provider.dart';

/// Search over the bundled group list. A tree of 1433 entries is not browsable
/// on a phone, so this is a search field, not a hierarchy.
class GroupPickerScreen extends ConsumerStatefulWidget {
  const GroupPickerScreen({super.key});

  /// Matches AdeLink.maxIds so a pasted selection and a hand-picked one have
  /// the same ceiling. Verified against ADE with a real 20-group request.
  static const int maxSelection = AdeLink.maxIds;

  @override
  ConsumerState<GroupPickerScreen> createState() => _GroupPickerScreenState();
}

class _GroupPickerScreenState extends ConsumerState<GroupPickerScreen> {
  final _controller = TextEditingController();
  List<AdeGroup> _all = const <AdeGroup>[];
  List<AdeGroup> _shown = const <AdeGroup>[];
  late Set<int> _selected;
  bool _loading = true;
  AdeCategory _category = AdeCategory.student;

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
      _applyFilters();
    });
  }

  void _applyFilters() {
    _shown = AdeGroups.search(
      AdeGroups.ofCategory(_all, _category),
      _controller.text,
    );
  }

  void _search(String query) => setState(_applyFilters);

  void _selectCategory(AdeCategory category) => setState(() {
    _category = category;
    _applyFilters();
  });

  void _toggle(AdeGroup g) {
    setState(() {
      if (_selected.contains(g.id)) {
        _selected.remove(g.id);
      } else if (_selected.length < GroupPickerScreen.maxSelection) {
        _selected.add(g.id);
      }
    });
  }

  /// Import a selection from a pasted ade-planning or ADE link. Students who
  /// already curated a group set have it in a URL; retyping it here is worse.
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
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Choisir un groupe'),
        foregroundColor: Colors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColors.headerGradient,
            ),
          ),
        ),
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
            child: Text(
              'OK (${_selected.length})',
              style: TextStyle(
                color: _selected.isEmpty ? Colors.white54 : Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              onChanged: _search,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Ex. S3-STPI-L',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 40,
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
                      onSelected: (_) => _selectCategory(c),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView.builder(
                itemCount: _shown.length,
                itemBuilder: (context, i) {
                  final g = _shown[i];
                  final selected = _selected.contains(g.id);
                  return CheckboxListTile(
                    value: selected,
                    onChanged: (_) => _toggle(g),
                    title: Text(g.name),
                    dense: true,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
