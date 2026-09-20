import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/schedule_period.dart';
import 'package:notes_insa/modules/schedule/schedule_view_mode.dart';

void main() {
  group('academicYearRange', () {
    test('starts in September and ends in August', () {
      expect(academicYearRange(DateTime(2026, 9, 20)), (
        from: DateTime(2026, 9, 1),
        to: DateTime(2027, 8, 31),
      ));
    });

    test('keeps summer in the preceding academic year', () {
      expect(academicYearRange(DateTime(2027, 8, 2)), (
        from: DateTime(2026, 9, 1),
        to: DateTime(2027, 8, 31),
      ));
    });
  });

  // Tuesday 8 September 2026; its Monday is the 7th.
  final tuesday = DateTime(2026, 9, 8);

  group('periodRange', () {
    test('a day is its own period', () {
      final range = periodRange(ScheduleViewMode.jour, tuesday);
      expect(range.from, tuesday);
      expect(range.to, tuesday);
    });

    test('three days start on the day itself', () {
      final range = periodRange(ScheduleViewMode.troisJours, tuesday);
      expect(range.from, tuesday);
      expect(range.to, DateTime(2026, 9, 10));
    });

    test('a week starts on Monday whichever day is showing', () {
      final range = periodRange(ScheduleViewMode.semaine, tuesday);
      expect(range.from, DateTime(2026, 9, 7));
      expect(range.to, DateTime(2026, 9, 13));
    });

    test('the list carries the week of the day on screen', () {
      expect(
        periodRange(ScheduleViewMode.liste, tuesday),
        periodRange(ScheduleViewMode.semaine, tuesday),
      );
    });

    test('a month runs first to last, leap years included', () {
      final range = periodRange(ScheduleViewMode.mois, DateTime(2028, 2, 14));
      expect(range.from, DateTime(2028, 2));
      expect(range.to, DateTime(2028, 2, 29));
    });
  });

  group('periodLabel', () {
    test('names a single day in full', () {
      expect(periodLabel(ScheduleViewMode.jour, tuesday), 'mardi 8 septembre');
    });

    test('joins a span inside one month', () {
      expect(
        periodLabel(ScheduleViewMode.semaine, tuesday),
        'du 7 au 13 septembre',
      );
      expect(
        periodLabel(ScheduleViewMode.troisJours, tuesday),
        'du 8 au 10 septembre',
      );
    });

    test('names both months when a span crosses one', () {
      expect(
        periodLabel(ScheduleViewMode.troisJours, DateTime(2026, 9, 30)),
        'du 30 septembre au 2 octobre',
      );
    });

    test('names a month with its year', () {
      expect(periodLabel(ScheduleViewMode.mois, tuesday), 'septembre 2026');
    });
  });

  group('shiftPeriod', () {
    test('steps by the span the mode shows', () {
      expect(
        shiftPeriod(ScheduleViewMode.jour, tuesday, 1),
        DateTime(2026, 9, 9),
      );
      expect(
        shiftPeriod(ScheduleViewMode.troisJours, tuesday, 1),
        DateTime(2026, 9, 11),
      );
      expect(
        shiftPeriod(ScheduleViewMode.semaine, tuesday, 1),
        DateTime(2026, 9, 15),
      );
      expect(
        shiftPeriod(ScheduleViewMode.semaine, tuesday, -1),
        DateTime(2026, 9, 1),
      );
    });

    test('a month steps to the first of the next month', () {
      expect(
        shiftPeriod(ScheduleViewMode.mois, DateTime(2026, 12, 20), 1),
        DateTime(2027),
      );
    });
  });

  group('containsDay', () {
    test('knows whether today is on screen', () {
      final week = periodRange(ScheduleViewMode.semaine, tuesday);
      expect(containsDay(week, DateTime(2026, 9, 13, 23, 30)), isTrue);
      expect(containsDay(week, DateTime(2026, 9, 14)), isFalse);
      expect(containsDay(week, DateTime(2026, 9, 6, 23, 59)), isFalse);
    });
  });
}
