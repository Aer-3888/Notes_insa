import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/schedule/ics_parser.dart';

void main() {
  setUpAll(initCampusTime);

  late String fixture;

  setUp(() {
    fixture = File('test/fixtures/ade_week.ics').readAsStringSync();
  });

  test('parses every event in the recorded week', () {
    final events = parseAdeIcs(fixture);
    expect(events.length, 16);
  });

  test('events are returned in chronological order', () {
    final events = parseAdeIcs(fixture);
    for (var i = 1; i < events.length; i++) {
      expect(
        events[i].start.isBefore(events[i - 1].start),
        isFalse,
        reason: 'event $i is out of order',
      );
    }
  });

  test('converts UTC stamps to campus local time', () {
    final events = parseAdeIcs(fixture);
    // DTSTART:20260907T070000Z is 09:00 in Rennes (CEST, UTC+2).
    final monday = events.firstWhere(
      (e) => e.title.startsWith('Electronique 1'),
    );
    expect(monday.start.hour, 9);
    expect(monday.end.hour, 10);
  });

  test('splits groups, module and teachers out of the description', () {
    final events = parseAdeIcs(fixture);
    final algebre = events.firstWhere((e) => e.title.startsWith('Algèbre 3'));
    expect(algebre.groups, contains('S3-STPI-L'));
    expect(algebre.groups.length, 6);
    expect(algebre.module, 'Algebre 3 (Algebra)');
    expect(algebre.teachers, <String>['CAMAR-EDDINE MOHAMED']);
  });

  test('handles an event with teachers but no module', () {
    final events = parseAdeIcs(fixture);
    final distrib = events.firstWhere(
      (e) => e.title.startsWith('DISTRIBUTION'),
    );
    expect(distrib.module, isNull);
    expect(distrib.teachers, hasLength(2));
    expect(distrib.teachers, contains('MARCHAND LAURENCE'));
  });

  test('strips the \$\$ prefix from co-teacher names', () {
    final events = parseAdeIcs(fixture);
    final eps = events.firstWhere((e) => e.title.startsWith('EPS'));
    expect(eps.teachers, contains('ECKENSCHWILLER NICOLAS'));
    for (final t in eps.teachers) {
      expect(t.startsWith(r'$$'), isFalse);
    }
  });

  test('an event with no room yields a null room, never an empty string', () {
    final events = parseAdeIcs(fixture);
    final eps = events.firstWhere((e) => e.title.startsWith('EPS'));
    expect(eps.room, isNull);
  });

  test('keeps the raw room text when it cannot be tidied', () {
    final events = parseAdeIcs(fixture);
    final withRoom = events.firstWhere((e) => e.room != null);
    expect(withRoom.room, isNotEmpty);
  });

  test('never drops the export marker into a parsed field', () {
    final events = parseAdeIcs(fixture);
    for (final e in events) {
      expect(e.module ?? '', isNot(contains('Exported')));
      for (final t in e.teachers) {
        expect(t, isNot(contains('Exported')));
      }
      for (final g in e.groups) {
        expect(g, isNot(contains('Exported')));
      }
    }
  });

  test('unfolds wrapped lines before parsing', () {
    // ICS folds at 75 octets with a leading space; a naive line split would
    // truncate long descriptions.
    final events = parseAdeIcs(fixture);
    final longest = events
        .map((e) => e.groups.length)
        .reduce((a, b) => a > b ? a : b);
    expect(longest, greaterThan(3));
  });

  test('returns an empty list for a calendar with no events', () {
    const empty =
        'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//ADE\r\nEND:VCALENDAR';
    expect(parseAdeIcs(empty), isEmpty);
  });

  test('throws FormatException when the payload is not a calendar', () {
    expect(() => parseAdeIcs('<html>login</html>'), throwsFormatException);
  });

  test('interior whitespace in a room is collapsed', () {
    const ics =
        'BEGIN:VCALENDAR\r\n'
        'BEGIN:VEVENT\r\n'
        'DTSTART:20260908T081500Z\r\n'
        'DTEND:20260908T101500Z\r\n'
        'SUMMARY:Algebre 3\r\n'
        'LOCATION:Amphi C   (V)\r\n'
        'END:VEVENT\r\n'
        'END:VCALENDAR\r\n';
    expect(parseAdeIcs(ics).single.room, 'Amphi C (V)');
  });
}
