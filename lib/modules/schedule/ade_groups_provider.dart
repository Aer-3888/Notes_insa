import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ade_groups.dart';

/// The ADE resource list, loaded once and shared by every picker.
///
/// [AdeGroups.load] already memoizes for the session. Going through a provider
/// on top of it is what lets the screens be driven against a fixture instead
/// of the network, the same way [adeServiceProvider] does for timetables.
final adeGroupsProvider = FutureProvider<List<AdeGroup>>(
  (ref) => AdeGroups.load(),
);

/// Just the student groups, which is all the subscription screens offer.
final adeStudentGroupsProvider = FutureProvider<List<AdeGroup>>(
  (ref) async => AdeGroups.ofCategory(
    await ref.watch(adeGroupsProvider.future),
    AdeCategory.student,
  ),
);
