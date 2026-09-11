import 'package:flutter/foundation.dart';

import 'association.dart';

/// How long before an event the student wants to be told.
enum AssociationReminderLead {
  off,
  oneHour,
  oneDay;

  static const AssociationReminderLead fallback =
      AssociationReminderLead.oneDay;

  static AssociationReminderLead parse(String? raw) {
    for (final value in AssociationReminderLead.values) {
      if (value.name == raw) return value;
    }
    return fallback;
  }

  Duration get lead => switch (this) {
    AssociationReminderLead.off => Duration.zero,
    AssociationReminderLead.oneHour => const Duration(hours: 1),
    AssociationReminderLead.oneDay => const Duration(days: 1),
  };

  String get label => switch (this) {
    AssociationReminderLead.off => 'Jamais',
    AssociationReminderLead.oneHour => '1 heure avant',
    AssociationReminderLead.oneDay => 'La veille',
  };
}

/// One local notification waiting to be scheduled.
@immutable
class AssociationReminder {
  const AssociationReminder({
    required this.id,
    required this.eventId,
    required this.fireAt,
    required this.title,
    required this.body,
    required this.payload,
  });

  /// Stable across reschedules, so the platform replaces the pending
  /// notification for an event instead of stacking a second one.
  final int id;

  final String eventId;
  final DateTime fireAt;
  final String title;
  final String body;

  /// `asso:<id>`, which the shell turns into the association's page.
  final String payload;
}

/// iOS keeps at most 64 pending local notifications and silently drops the
/// rest. Staying well under leaves room for the grades notifications, which
/// are scheduled by a different part of the app.
const int kAssociationReminderCap = 32;

/// Notification ids live above this, clear of the fixed ids the grades
/// notifications use.
const int _idBase = 900000;

/// What to schedule for the events a student follows.
///
/// Pure, so the rules stay testable without the platform: nothing in the past,
/// nothing whose warning has already lapsed, soonest first, and never more
/// than [cap].
List<AssociationReminder> planAssociationReminders({
  required List<AssociationEvent> events,
  required Map<String, Association> directory,
  required AssociationReminderLead lead,
  required DateTime now,
  int cap = kAssociationReminderCap,
}) {
  if (lead == AssociationReminderLead.off) return const <AssociationReminder>[];

  final out = <AssociationReminder>[];
  for (final event in events) {
    final association = directory[event.associationId];
    // A follow can outlive the association that was removed from the seed.
    if (association == null) continue;

    final fireAt = event.startsAt.subtract(lead.lead);
    // Too late to warn about: either the event has passed, or the warning
    // window closed while the app was shut.
    if (!fireAt.isAfter(now)) continue;

    out.add(
      AssociationReminder(
        id: _idBase + (event.id.hashCode.abs() % 90000),
        eventId: event.id,
        fireAt: fireAt,
        title: association.displayName,
        body: _body(event),
        payload: associationPayload(event.associationId),
      ),
    );
  }

  out.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return out.length > cap ? out.sublist(0, cap) : out;
}

String _body(AssociationEvent event) {
  final hour = event.startsAt.hour.toString().padLeft(2, '0');
  final minute = event.startsAt.minute.toString().padLeft(2, '0');
  final where = event.location;
  final when = where == null ? '$hour:$minute' : '$hour:$minute · $where';
  return '${event.title} · $when';
}

/// The notification payload for an association, and the way back out of it.
String associationPayload(String associationId) => 'asso:$associationId';

String? associationIdFromPayload(String payload) =>
    payload.startsWith('asso:') ? payload.substring(5) : null;
