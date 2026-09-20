import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/schedule/ics_parser.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/session_type.dart';

void main() {
  setUpAll(initCampusTime);

  late List<ScheduleEvent> events;

  setUp(() {
    events = parseAdeIcs(File('test/fixtures/ade_week.ics').readAsStringSync());
  });

  SessionType? typeOf(String title) =>
      guessSessionType(events.firstWhere((e) => e.title.startsWith(title)));

  test('an amphi is read as a lecture', () {
    expect(typeOf('Algèbre 3'), SessionType.cm);
    expect(typeOf('Mécanique 3'), SessionType.cm);
  });

  test('an explicit type in the summary wins over the room', () {
    expect(typeOf('TEDS_L'), SessionType.tp);
  });

  test('a lab room is read as a lab', () {
    expect(typeOf('PHYSIQUE_L'), SessionType.tp);
  });

  test('a numbered room is read as a tutorial', () {
    expect(typeOf('ANGLAIS_L'), SessionType.td);
    expect(typeOf('SA_L'), SessionType.td);
  });

  test('an event with no module is never labelled', () {
    expect(typeOf('DISTRIBUTION'), isNull);
    expect(typeOf('Reunion'), isNull);
  });

  test('a course with no room is never labelled', () {
    expect(typeOf('EPS'), isNull);
  });

  test('most of the recorded week gets a label', () {
    final labelled = events.where((e) => guessSessionType(e) != null).length;
    expect(labelled, 13);
  });
}
