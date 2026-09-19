import 'schedule_event.dart';

/// What kind of session a block is, as far as the feed lets us tell.
///
/// ADE has no type field, so this is a guess from the room and the wording.
/// It labels a row and nothing else. A hide rule keys on the activity id.
enum SessionType {
  cm('CM'),
  td('TD'),
  tp('TP');

  const SessionType(this.label);

  final String label;
}

final RegExp _explicit = RegExp(r'\b(CM|TD|TP)\b');
final RegExp _amphi = RegExp('amphi', caseSensitive: false);

/// The kind of [event], or null when the feed gives nothing to go on.
SessionType? guessSessionType(ScheduleEvent event) {
  // Events with no module are announcements and handouts, not classes.
  if (event.module == null) return null;

  final said = _explicit.firstMatch('${event.title} ${event.module}');
  if (said != null) {
    return SessionType.values.firstWhere((t) => t.label == said.group(1));
  }

  final room = event.room;
  if (room == null) return null;
  if (_amphi.hasMatch(room)) return SessionType.cm;
  if (_explicit.firstMatch(room)?.group(1) == 'TP') return SessionType.tp;
  return SessionType.td;
}
