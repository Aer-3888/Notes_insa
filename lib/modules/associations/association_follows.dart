import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The associations a student follows.
///
/// Local only for now. Phase 4 registers a device with the Worker and sends
/// this set up so notifications can be targeted, which is why it is keyed on
/// association id rather than name: the id is what survives a rename.
///
/// A storage failure keeps whatever is in memory rather than dropping the set,
/// the same policy as ScheduleTintNotifier.
class AssociationFollowsNotifier extends Notifier<Set<String>> {
  static const String key = 'association_follows';

  Future<void>? _loaded;

  @visibleForTesting
  Future<void> get loaded => _loaded ?? Future<void>.value();

  @override
  Set<String> build() {
    _loaded = _load();
    return const <String>{};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(key);
      if (stored != null) state = stored.toSet();
    } catch (e) {
      if (kDebugMode) debugPrint('[AssociationFollows] load failed: $e');
    }
  }

  bool isFollowing(String id) => state.contains(id);

  Future<void> toggle(String id) =>
      state.contains(id) ? unfollow(id) : follow(id);

  Future<void> follow(String id) async {
    if (state.contains(id)) return;
    state = <String>{...state, id};
    await _save();
  }

  Future<void> unfollow(String id) async {
    if (!state.contains(id)) return;
    state = <String>{...state}..remove(id);
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, state.toList()..sort());
    } catch (e) {
      if (kDebugMode) debugPrint('[AssociationFollows] save failed: $e');
    }
  }
}

final associationFollowsProvider =
    NotifierProvider<AssociationFollowsNotifier, Set<String>>(
      AssociationFollowsNotifier.new,
    );
