import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/time.dart';

void main() {
  setUpAll(initCampusTime);

  test('campusNow returns a time in the campus zone', () {
    final now = campusNow();
    // Rennes is UTC+1 in winter, UTC+2 in summer — never UTC.
    expect(now.timeZoneOffset.inHours, anyOf(1, 2));
  });

  test('campusInstant builds a wall-clock instant in the campus zone', () {
    // 2026-01-15 14:45 Rennes is UTC+1, so 13:45 UTC.
    final winter = campusInstant(DateTime(2026, 1, 15, 14, 45));
    expect(winter.toUtc().hour, 13);
  });

  test('campusInstant handles the 25 Oct 2026 DST boundary', () {
    // Before the change Rennes is UTC+2; after it is UTC+1.
    final before = campusInstant(DateTime(2026, 10, 25, 1, 30));
    final after = campusInstant(DateTime(2026, 10, 25, 4, 30));
    expect(before.toUtc().hour, 23); // 01:30 CEST == 23:30 UTC previous day
    expect(after.toUtc().hour, 3); //  04:30 CET  == 03:30 UTC
  });
}
