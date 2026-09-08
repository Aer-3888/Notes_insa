import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/campus_navigation.dart';
import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import '../campus_map/campus_places.dart';
import '../campus_map/map_screen.dart';
import 'room_lookup.dart';
import 'schedule_event.dart';

String _hm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// `2 h`, `1 h 30`, `45 min`.
String _duration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  if (hours == 0) return '$minutes min';
  if (minutes == 0) return '$hours h';
  return '$hours h $minutes';
}

Future<void> showEventSheet(BuildContext context, ScheduleEvent event) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _EventSheet(event: event),
    );

class _EventSheet extends ConsumerWidget {
  const _EventSheet({required this.event});

  final ScheduleEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places =
        ref.watch(campusPlacesProvider).value ?? const <CampusPlace>[];
    final room = resolveRoom(event.room, places);
    final hasRoom = event.room != null && event.room!.isNotEmpty;
    final title = event.module ?? event.title;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CampusSpacing.gutter,
          0,
          CampusSpacing.gutter,
          CampusSpacing.x6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: context.text.headlineMedium),
            // The summary sometimes carries a group suffix the module name
            // drops, so it is worth showing when the two differ.
            if (event.module != null && event.title != event.module)
              Text(
                event.title,
                style: context.text.bodyMedium?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: CampusSpacing.x4),
            Text(
              '${_hm(event.start)} à ${_hm(event.end)} · ${_duration(event.duration)}',
              style: context.text.bodyLarge,
            ),
            if (hasRoom) ...[
              const SizedBox(height: CampusSpacing.x2),
              Text(room.raw, style: context.text.bodyLarge),
              if (room.isResolved)
                Text(
                  'bâtiment ${room.buildingCode}',
                  style: context.text.bodyMedium?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
                ),
            ],
            if (event.teachers.isNotEmpty) ...[
              const SizedBox(height: CampusSpacing.x4),
              for (final teacher in event.teachers)
                Text(teacher, style: context.text.bodyMedium),
            ],
            if (event.groups.isNotEmpty) ...[
              const SizedBox(height: CampusSpacing.x2),
              Text(
                event.groups.join(', '),
                style: context.text.bodyMedium?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: CampusSpacing.x6),
            Wrap(
              spacing: CampusSpacing.x2,
              runSpacing: CampusSpacing.x2,
              children: [
                if (room.isResolved)
                  FilledButton.tonalIcon(
                    onPressed: () {
                      final navigation = CampusNavigationScope.maybeOf(context);
                      final navigator = Navigator.of(context);
                      navigator.pop();
                      final buildingCode = room.buildingCode!;
                      if (navigation != null) {
                        navigation.onOpenMap(buildingCode);
                        return;
                      }
                      navigator.push(
                        MaterialPageRoute<void>(
                          builder: (_) => MapScreen(
                            initialQuery: room.mapQuery,
                            initialBuildingCode: buildingCode,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.place_outlined),
                    label: const Text('Voir sur la carte'),
                  ),
                if (hasRoom)
                  TextButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: room.raw));
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Salle copiée')),
                      );
                    },
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copier la salle'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
