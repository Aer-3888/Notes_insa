import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_colors.dart';
import 'ade_groups.dart';
import 'schedule_provider.dart';

/// Search over the bundled group list. A tree of 1433 entries is not browsable
/// on a phone, so this is a search field, not a hierarchy.
class GroupPickerScreen extends ConsumerStatefulWidget {
  const GroupPickerScreen({super.key});

  /// ADE accepts comma-joined resources; keep the request small and the UI sane.
  static const int maxSelection = 10;

  @override
  ConsumerState<GroupPickerScreen> createState() => _GroupPickerScreenState();
}

class _GroupPickerScreenState extends ConsumerState<GroupPickerScreen> {
  final _controller = TextEditingController();
  List<AdeGroup> _all = const <AdeGroup>[];
  List<AdeGroup> _shown = const <AdeGroup>[];
  late Set<int> _selected;
  bool _loading = true;

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
      _shown = groups;
      _loading = false;
    });
  }

  void _search(String query) =>
      setState(() => _shown = AdeGroups.search(_all, query));

  void _toggle(AdeGroup g) {
    setState(() {
      if (_selected.contains(g.id)) {
        _selected.remove(g.id);
      } else if (_selected.length < GroupPickerScreen.maxSelection) {
        _selected.add(g.id);
      }
    });
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
