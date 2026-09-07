import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/grades_view_mode_provider.dart';
import '../theme/campus_context.dart';

class GradesViewMenu extends ConsumerWidget {
  const GradesViewMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(gradesViewModeProvider);
    return PopupMenuButton<GradesViewMode>(
      tooltip: 'Changer d’affichage',
      initialValue: mode,
      onSelected: (mode) =>
          unawaited(ref.read(gradesViewModeProvider.notifier).set(mode)),
      itemBuilder: (_) => [
        for (final mode in GradesViewMode.values)
          PopupMenuItem(value: mode, child: Text(mode.label)),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(mode.label, style: context.text.headlineMedium),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}
