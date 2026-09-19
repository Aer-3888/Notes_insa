import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'hidden_courses_provider.dart';
import 'hide_rule.dart';
import 'schedule_event.dart';
import 'session_type.dart';

/// How long a hide or unhide message stays up.
///
/// Well under Material's four seconds: it confirms a switch the student just
/// flipped and can already see the result of, so it should not sit on the
/// timetable. It is the whole window for Annuler, which is the trade.
const Duration kHideMessageDuration = Duration(milliseconds: 1500);

/// Every one of these carries an Annuler, and a SnackBar with an action
/// defaults to persist: it then sits there until something else replaces it.
/// Saying so explicitly is what makes the duration above mean anything.
const bool kHideMessagePersists = false;

/// What a hide can target, widest last.
List<HideRule> hideOptionsFor(ScheduleEvent event) => <HideRule>[
  ?HideRule.occurrence(event),
  ?HideRule.series(event),
  HideRule.module(event),
];

/// How a rule reads as a choice in the chooser.
String hideOptionLabel(HideRule rule, ScheduleEvent event) =>
    switch (rule.field) {
      HideField.occurrence => 'Cette séance',
      HideField.series => switch (guessSessionType(event)) {
        final SessionType type => 'Les ${type.label} · ${event.title}',
        null => 'Cette série · ${event.title}',
      },
      _ => 'Tout ${event.module ?? event.title}',
    };

/// A rule aimed at this course alone, rather than a filter on a teacher or
/// a room.
bool _isNarrow(HideRule rule) => switch (rule.field) {
  HideField.occurrence || HideField.series || HideField.module => true,
  _ => false,
};

/// What removing [rule] should be reported as. A broad rule brings back more
/// than the course that was tapped, so it is named as a rule.
String unhideMessage(HideRule rule) => _isNarrow(rule)
    ? '${rule.label} affiché'
    : 'Filtre « ${rule.label} » retiré';

/// Opens the sheet for [event]: what to hide, or what to bring back when a
/// rule already hides it.
///
/// Reads the container rather than taking a WidgetRef: the event sheet pops
/// itself before calling this, so its own ref is already gone by then.
Future<void> showHideCourseSheet(
  BuildContext context,
  ScheduleEvent event,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final notifier = container.read(hiddenRulesProvider.notifier);
  final hiding = rulesHiding(event, container.read(hiddenRulesProvider));

  if (hiding.isEmpty) {
    await _hide(context, event, notifier);
    return;
  }
  await _unhide(context, event, hiding, notifier);
}

Future<void> _hide(
  BuildContext context,
  ScheduleEvent event,
  HiddenRulesNotifier notifier,
) async {
  final chosen = await showModalBottomSheet<HideRule>(
    context: context,
    showDragHandle: true,
    builder: (_) => _ChoiceSheet(
      title: 'Masquer',
      icon: Icons.visibility_off_outlined,
      options: <({HideRule rule, String label})>[
        for (final rule in hideOptionsFor(event))
          (rule: rule, label: hideOptionLabel(rule, event)),
      ],
    ),
  );
  if (chosen == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  await notifier.add(chosen);
  // Without this the undo for this action queues behind the previous one.
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text('${chosen.label} masqué'),
      duration: kHideMessageDuration,
      persist: kHideMessagePersists,
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () => unawaited(notifier.remove(chosen)),
      ),
    ),
  );
}

/// A single rule is lifted straight away, with an undo. Several means the
/// student has to be told which one they are lifting.
Future<void> _unhide(
  BuildContext context,
  ScheduleEvent event,
  List<HideRule> hiding,
  HiddenRulesNotifier notifier,
) async {
  var chosen = hiding.length == 1 ? hiding.first : null;
  if (chosen == null) {
    chosen = await showModalBottomSheet<HideRule>(
      context: context,
      showDragHandle: true,
      builder: (_) => _ChoiceSheet(
        title: 'Afficher',
        icon: Icons.visibility_outlined,
        subtitle: 'Plusieurs règles masquent ce cours.',
        options: <({HideRule rule, String label})>[
          for (final rule in hiding) (rule: rule, label: rule.label),
        ],
      ),
    );
    if (chosen == null || !context.mounted) return;
  }

  final lifted = chosen;
  final messenger = ScaffoldMessenger.of(context);
  await notifier.remove(lifted);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(unhideMessage(lifted)),
      duration: kHideMessageDuration,
      persist: kHideMessagePersists,
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () => unawaited(notifier.add(lifted)),
      ),
    ),
  );
}

class _ChoiceSheet extends StatelessWidget {
  const _ChoiceSheet({
    required this.title,
    required this.icon,
    required this.options,
    this.subtitle,
  });

  final String title;
  final IconData icon;
  final String? subtitle;
  final List<({HideRule rule, String label})> options;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CampusSpacing.gutter,
            0,
            CampusSpacing.gutter,
            CampusSpacing.x2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: context.text.titleLarge),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        for (final option in options)
          ListTile(
            leading: Icon(icon),
            title: Text(option.label),
            onTap: () => Navigator.of(context).pop(option.rule),
          ),
        const SizedBox(height: CampusSpacing.x4),
      ],
    ),
  );
}
