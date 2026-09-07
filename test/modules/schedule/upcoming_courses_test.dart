import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/module_cache.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_provider.dart';

/// One session offset from now, so the fixtures stay inside the fetch window
/// whatever day the suite runs on.
ScheduleEvent _at(Duration fromNow, {String title = 'Algèbre 3'}) {
  final start = campusNow().add(fromNow);
  return ScheduleEvent(
    title: title,
    start: start,
    end: start.add(const Duration(hours: 2)),
    groups: const <String>[],
    teachers: const <String>[],
    room: 'Amphi C',
  );
}

/// [events] null stands for the state before a group has been chosen, where
/// the cache has nothing to read.
Future<List<ScheduleEvent>> _upcoming(List<ScheduleEvent>? events) async {
  final container = ProviderContainer(
    overrides: [
      scheduleProvider.overrideWith(
        (ref) => Stream<CachedEntry<List<ScheduleEvent>>>.value(
          CachedEntry<List<ScheduleEvent>>(data: events),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  final subscription = container.listen(
    upcomingCoursesProvider,
    (_, _) {},
    fireImmediately: true,
  );
  await Future<void>.delayed(Duration.zero);
  return subscription.read();
}

void main() {
  setUpAll(initCampusTime);

  test('drops the sessions that have already ended', () async {
    final over = _at(const Duration(hours: -4), title: 'Terminé');
    final next = _at(const Duration(hours: 2), title: 'À venir');

    final upcoming = await _upcoming(<ScheduleEvent>[over, next]);

    expect(upcoming.map((e) => e.title), <String>['À venir']);
  });

  test('keeps a session that is running right now', () async {
    final running = _at(const Duration(minutes: -30), title: 'En cours');

    final upcoming = await _upcoming(<ScheduleEvent>[running]);

    expect(upcoming.map((e) => e.title), <String>['En cours']);
  });

  test('caps the preview so the hub never holds the whole timetable', () async {
    final events = <ScheduleEvent>[
      for (var i = 1; i <= kUpcomingPreviewCount + 4; i++)
        _at(Duration(hours: i * 3), title: 'Cours $i'),
    ];

    final upcoming = await _upcoming(events);

    expect(upcoming, hasLength(kUpcomingPreviewCount));
    expect(upcoming.first.title, 'Cours 1');
  });

  test('is empty until the cache has a timetable to read', () async {
    expect(await _upcoming(null), isEmpty);
  });
}
