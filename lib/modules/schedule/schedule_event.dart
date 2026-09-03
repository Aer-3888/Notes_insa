/// One timetable entry, normalized from the ADE iCal export.
class ScheduleEvent {
  const ScheduleEvent({
    required this.title,
    required this.start,
    required this.end,
    required this.groups,
    required this.teachers,
    this.module,
    this.room,
  });

  final String title;

  /// Campus-local start and end. ADE stamps these in UTC.
  final DateTime start;
  final DateTime end;

  /// Student groups the session is scheduled for.
  final List<String> groups;

  /// Teacher names, with ADE's `$$ -` co-teacher prefix removed.
  final List<String> teachers;

  /// Full module name when ADE supplies one; the summary is often abbreviated.
  final String? module;

  /// Raw room text. Null rather than empty when ADE gives no location.
  final String? room;

  Duration get duration => end.difference(start);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title,
    'start': start.millisecondsSinceEpoch,
    'end': end.millisecondsSinceEpoch,
    'groups': groups,
    'teachers': teachers,
    'module': module,
    'room': room,
  };

  /// Rebuilds from cache. Timestamps come back through the campus zone so a
  /// cached entry reads as the campus hour, not the viewer's.
  factory ScheduleEvent.fromJson(
    Map<String, dynamic> json,
    DateTime Function(int) toCampusTime,
  ) => ScheduleEvent(
    title: json['title'] as String,
    start: toCampusTime(json['start'] as int),
    end: toCampusTime(json['end'] as int),
    groups: <String>[...(json['groups'] as List<dynamic>).cast<String>()],
    teachers: <String>[...(json['teachers'] as List<dynamic>).cast<String>()],
    module: json['module'] as String?,
    room: json['room'] as String?,
  );
}
