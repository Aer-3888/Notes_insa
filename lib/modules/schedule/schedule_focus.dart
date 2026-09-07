import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'schedule_event.dart';

/// A session another surface has asked the timetable to show.
class ScheduleFocus {
  const ScheduleFocus(this.event);

  final ScheduleEvent event;

  DateTime get day =>
      DateTime(event.start.year, event.start.month, event.start.day);
}

/// One-shot: the timetable consumes the request, so returning to the tab later
/// does not reopen the sheet.
class ScheduleFocusRequest extends Notifier<ScheduleFocus?> {
  @override
  ScheduleFocus? build() => null;

  void request(ScheduleEvent event) => state = ScheduleFocus(event);

  ScheduleFocus? consume() {
    final pending = state;
    state = null;
    return pending;
  }
}

final scheduleFocusProvider =
    NotifierProvider<ScheduleFocusRequest, ScheduleFocus?>(
      ScheduleFocusRequest.new,
    );
