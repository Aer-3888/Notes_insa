import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time.dart';
import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'association.dart';
import 'association_detail_screen.dart';
import 'association_service.dart';

/// What the associations a student follows have coming up.
///
/// Absent entirely when nothing is coming: a student who follows nothing, or
/// whose assos have no dates yet, should not get an empty card every morning.
class AssociationsTodayCard extends ConsumerStatefulWidget {
  const AssociationsTodayCard({super.key});

  @override
  ConsumerState<AssociationsTodayCard> createState() =>
      _AssociationsTodayCardState();
}

class _AssociationsTodayCardState extends ConsumerState<AssociationsTodayCard>
    with WidgetsBindingObserver {
  /// Events are day-scale, so returning to the app is a fine moment to recheck
  /// what has passed. A minute timer would cost battery for nothing.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _open(String associationId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssociationDetailScreen(associationId: associationId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Nothing followed is the common case, and it is answered without the
    // clock: campusNow() needs a timezone database this card should not
    // require just to decide it has nothing to show.
    final followed = ref.watch(followedAssociationEventsProvider);
    if (followed.isEmpty) return const SizedBox.shrink();

    final now = campusNow();
    final upcoming = followed
        .where((event) => !event.isPast(now))
        .take(3)
        .toList();
    if (upcoming.isEmpty) return const SizedBox.shrink();

    final all = ref.watch(associationsProvider).value ?? const <Association>[];
    final byId = <String, Association>{for (final a in all) a.id: a};

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CampusSpacing.gutter,
        CampusSpacing.x2,
        CampusSpacing.gutter,
        CampusSpacing.x2,
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CampusSpacing.x4,
                CampusSpacing.x4,
                CampusSpacing.x4,
                CampusSpacing.x2,
              ),
              child: Text(
                'Chez tes assos',
                style: context.text.titleSmall?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final event in upcoming)
              ListTile(
                onTap: () => _open(event.associationId),
                title: Text(event.title),
                subtitle: Text(
                  <String>[
                    associationEventWhen(event),
                    ?byId[event.associationId]?.displayName,
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
            const SizedBox(height: CampusSpacing.x2),
          ],
        ),
      ),
    );
  }
}
