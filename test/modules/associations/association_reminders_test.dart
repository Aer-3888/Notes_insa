import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/associations/association.dart';
import 'package:notes_insa/modules/associations/association_reminders.dart';

AssociationEvent _event(
  String id,
  DateTime startsAt, {
  String association = 'a',
  String title = 'Gala',
  String? location,
}) => AssociationEvent(
  id: id,
  associationId: association,
  title: title,
  startsAt: startsAt,
  location: location,
);

Association _asso(String id, String name) =>
    Association(id: id, name: name, category: AssociationCategory.culture);

void main() {
  setUpAll(initCampusTime);

  DateTime at(int day, int hour) => campusInstant(DateTime(2026, 3, day, hour));

  final directory = <String, Association>{
    'a': _asso('a', 'Arts plastiques'),
    'b': _asso('b', 'Basket'),
  };

  List<AssociationReminder> plan(
    List<AssociationEvent> events, {
    AssociationReminderLead lead = AssociationReminderLead.oneDay,
    DateTime? now,
    int cap = 32,
  }) => planAssociationReminders(
    events: events,
    directory: directory,
    lead: lead,
    now: now ?? at(10, 12),
    cap: cap,
  );

  test('off schedules nothing at all', () {
    final reminders = plan(<AssociationEvent>[
      _event('e1', at(14, 20)),
    ], lead: AssociationReminderLead.off);
    expect(reminders, isEmpty);
  });

  test('a reminder fires one lead time before the event', () {
    final reminders = plan(<AssociationEvent>[_event('e1', at(14, 20))]);
    expect(reminders.single.fireAt, at(13, 20));
  });

  test('the lead time is the one the student chose', () {
    final reminders = plan(<AssociationEvent>[
      _event('e1', at(14, 20)),
    ], lead: AssociationReminderLead.oneHour);
    expect(reminders.single.fireAt, at(14, 19));
  });

  test('an event whose lead time has already passed is not scheduled', () {
    // The event is still ahead, but a day's warning is no longer possible.
    final reminders = plan(<AssociationEvent>[
      _event('e1', at(10, 20)),
    ], now: at(10, 12));
    expect(reminders, isEmpty);
  });

  test('an event already over is not scheduled', () {
    final reminders = plan(<AssociationEvent>[
      _event('e1', at(2, 20)),
    ], now: at(10, 12));
    expect(reminders, isEmpty);
  });

  test('the notification names the association and the event', () {
    final reminders = plan(<AssociationEvent>[
      _event('e1', at(14, 20), title: 'Vernissage'),
    ]);
    expect(reminders.single.title, 'Arts plastiques');
    expect(reminders.single.body, contains('Vernissage'));
  });

  test('the body carries the time, and the place when there is one', () {
    final withPlace = plan(<AssociationEvent>[
      _event('e1', at(14, 20), location: 'Halle Francis Querné'),
    ]).single;
    expect(withPlace.body, contains('20:00'));
    expect(withPlace.body, contains('Halle Francis Querné'));

    final without = plan(<AssociationEvent>[_event('e2', at(14, 20))]).single;
    expect(without.body, contains('20:00'));
  });

  test('tapping a reminder opens its association', () {
    final reminders = plan(<AssociationEvent>[
      _event('e1', at(14, 20), association: 'b'),
    ]);
    expect(reminders.single.payload, 'asso:b');
  });

  test('an event from an association not in the directory is skipped', () {
    // A follow left over after the asso was removed from the seed.
    final reminders = plan(<AssociationEvent>[
      _event('e1', at(14, 20), association: 'gone'),
    ]);
    expect(reminders, isEmpty);
  });

  group('ids', () {
    test('are stable, so rescheduling replaces instead of duplicating', () {
      final first = plan(<AssociationEvent>[_event('e1', at(14, 20))]).single;
      final again = plan(<AssociationEvent>[_event('e1', at(14, 20))]).single;
      expect(first.id, again.id);
    });

    test('differ between events', () {
      final reminders = plan(<AssociationEvent>[
        _event('e1', at(14, 20)),
        _event('e2', at(15, 20)),
      ]);
      expect(reminders[0].id, isNot(reminders[1].id));
    });

    test('stay clear of the ids the grades notifications use', () {
      final reminders = plan(<AssociationEvent>[_event('e1', at(14, 20))]);
      expect(reminders.single.id, greaterThan(100));
    });
  });

  group('the cap', () {
    test('keeps the soonest events, because iOS only holds 64 pending', () {
      final events = <AssociationEvent>[
        for (var day = 20; day >= 12; day--) _event('e$day', at(day, 20)),
      ];
      final reminders = plan(events, cap: 3);
      expect(reminders.length, 3);
      expect(reminders.map((r) => r.fireAt), <DateTime>[
        at(11, 20),
        at(12, 20),
        at(13, 20),
      ]);
    });

    test('is not reached by a normal number of follows', () {
      final events = <AssociationEvent>[
        for (var day = 12; day < 20; day++) _event('e$day', at(day, 20)),
      ];
      expect(plan(events).length, 8);
    });
  });

  test('reminders come back in the order they will fire', () {
    final reminders = plan(<AssociationEvent>[
      _event('late', at(18, 20)),
      _event('soon', at(12, 20)),
      _event('mid', at(15, 20)),
    ]);
    expect(reminders.map((r) => r.eventId), <String>['soon', 'mid', 'late']);
  });

  group('an event with a date but no time', () {
    AssociationEvent allDay() => AssociationEvent.fromJson(<String, Object?>{
      'id': 'gala',
      'title': 'Gala',
      'startsAt': '2026-03-14',
    }, 'a')!;

    test('reads as all-day rather than as midnight', () {
      expect(allDay().isAllDay, isTrue);
      expect(
        AssociationEvent.fromJson(<String, Object?>{
          'id': 'e',
          'title': 'Gala',
          'startsAt': '2026-03-14T20:00:00',
        }, 'a')!.isAllDay,
        isFalse,
      );
    });

    test('is reminded about in the morning, not at midnight', () {
      // Counting a day back from midnight would fire at midnight too.
      final reminders = plan(<AssociationEvent>[allDay()]);
      expect(reminders.single.fireAt, at(13, 9));
    });

    test('keeps the campus timezone its start had', () {
      expect(allDay().reminderAnchor.timeZoneOffset, at(14, 9).timeZoneOffset);
    });

    test('is announced without an invented hour', () {
      final reminders = plan(<AssociationEvent>[allDay()]);
      expect(reminders.single.body, isNot(contains('00:00')));
      expect(reminders.single.body, contains('Gala'));
    });
  });

  group('the lead setting', () {
    test('every option names itself in French', () {
      for (final lead in AssociationReminderLead.values) {
        expect(lead.label, isNotEmpty);
      }
    });

    test('a stored value that no longer exists falls back to the default', () {
      expect(
        AssociationReminderLead.parse('deux_semaines'),
        AssociationReminderLead.oneDay,
      );
      expect(
        AssociationReminderLead.parse(null),
        AssociationReminderLead.oneDay,
      );
      expect(AssociationReminderLead.parse('off'), AssociationReminderLead.off);
    });
  });
}
