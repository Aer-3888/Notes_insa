import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_colors.dart';
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.schedule, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.module ?? event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                  Text(
                    event.room == null ? hm : '$hm  •  ${event.room}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
