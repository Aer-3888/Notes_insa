import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'schedule_provider.dart';

/// The next session, read from the timetable cache. Costs no extra request and
/// renders offline; shows nothing at all until a group has been chosen.
class NextCourseCard extends ConsumerWidget {
  const NextCourseCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(nextCourseProvider);
    if (event == null) return const SizedBox.shrink();
    final start = event.start;
    final hm =
        '${start.hour.toString().padLeft(2, '0')}:'
        '${start.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CampusSpacing.gutter,
        CampusSpacing.x1,
        CampusSpacing.gutter,
        CampusSpacing.x2,
      ),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(CampusSpacing.card),
          child: Row(
            children: [
              Text(hm, style: context.campusType.numeral),
              const SizedBox(width: CampusSpacing.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.module ?? event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleMedium,
                    ),
                    if (event.room != null)
                      Text(
                        event.room!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodyMedium?.copyWith(
                          color: context.scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
