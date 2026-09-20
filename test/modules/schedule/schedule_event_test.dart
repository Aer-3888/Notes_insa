import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';

void main() {
  setUpAll(initCampusTime);

  ScheduleEvent anglais() => ScheduleEvent(
    title: 'ANGLAIS_L',
    start: campusFromEpochMs(
      DateTime.utc(2026, 9, 9, 6).millisecondsSinceEpoch,
    ),
    end: campusFromEpochMs(DateTime.utc(2026, 9, 9, 8).millisecondsSinceEpoch),
    groups: const <String>['S3-STPI-L'],
    teachers: const <String>['LEY OLIVIER'],
    module: 'Anglais 3',
    room: '*111 (VPI)',
    uid: 'ADE60-422-0',
    activityId: '422',
  );

  test('a cached event comes back whole', () {
    final original = anglais();
    final back = ScheduleEvent.fromJson(original.toJson(), campusFromEpochMs);
    expect(back.title, original.title);
    expect(back.start, original.start);
    expect(back.end, original.end);
    expect(back.groups, original.groups);
    expect(back.teachers, original.teachers);
    expect(back.module, original.module);
    expect(back.room, original.room);
    expect(back.uid, original.uid);
    expect(back.activityId, original.activityId);
  });

  test('an entry cached before the identifiers existed still reads', () {
    final legacy = anglais().toJson()
      ..remove('uid')
      ..remove('activityId');
    final back = ScheduleEvent.fromJson(legacy, campusFromEpochMs);
    expect(back.uid, isNull);
    expect(back.activityId, isNull);
    expect(back.title, 'ANGLAIS_L');
  });

  test('duration is the span between the stamps', () {
    expect(anglais().duration, const Duration(hours: 2));
  });
}
