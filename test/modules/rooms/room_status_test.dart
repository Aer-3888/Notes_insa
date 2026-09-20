import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/rooms/room_status.dart';
import 'package:notes_insa/modules/schedule/ade_groups.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';

const _a = AdeGroup(id: 1, name: '*102* (VPI)', category: AdeCategory.room);
const _b = AdeGroup(id: 2, name: '*201*(V)', category: AdeCategory.room);
const _c = AdeGroup(id: 3, name: 'Amphi C (V)', category: AdeCategory.room);

DateTime _t(int hour, [int minute = 0]) => DateTime(2026, 9, 21, hour, minute);

ScheduleEvent _event({
  required String room,
  required DateTime start,
  required DateTime end,
  String title = 'CPOO2_G1',
}) => ScheduleEvent(
  title: title,
  start: start,
  end: end,
  room: room,
  groups: const <String>[],
  teachers: const <String>[],
  uid: '$room-${start.hour}',
);

void main() {
  test('a room with nothing today is free for the rest of it', () {
    final s = roomStatuses(
      rooms: const <AdeGroup>[_a],
      events: const <ScheduleEvent>[],
      now: _t(14),
    ).single;
    expect(s.isFree, isTrue);
    expect(s.until, isNull);
    expect(s.current, isNull);
  });

  test('a room in use reports what is in it and when it ends', () {
    final s = roomStatuses(
      rooms: const <AdeGroup>[_a],
      events: <ScheduleEvent>[
        _event(room: '*102* (VPI)', start: _t(13, 30), end: _t(15, 45)),
      ],
      now: _t(14),
    ).single;
    expect(s.isFree, isFalse);
    expect(s.until, _t(15, 45));
    expect(s.current?.title, 'CPOO2_G1');
  });

  test('a free room reports when its next session starts', () {
    final s = roomStatuses(
      rooms: const <AdeGroup>[_a],
      events: <ScheduleEvent>[
        _event(room: '*102* (VPI)', start: _t(16), end: _t(18)),
      ],
      now: _t(14, 3),
    ).single;
    expect(s.isFree, isTrue);
    expect(s.until, _t(16));
    expect(s.freeFor, const Duration(hours: 1, minutes: 57));
  });

  test('a session already over does not make the room busy', () {
    final s = roomStatuses(
      rooms: const <AdeGroup>[_a],
      events: <ScheduleEvent>[
        _event(room: '*102* (VPI)', start: _t(8), end: _t(10)),
      ],
      now: _t(14),
    ).single;
    expect(s.isFree, isTrue);
    expect(s.until, isNull);
  });

  test('a zero-length session does not shorten a free room', () {
    final s = roomStatuses(
      rooms: const <AdeGroup>[_a],
      events: <ScheduleEvent>[
        _event(room: '*102* (VPI)', start: _t(15), end: _t(15)),
      ],
      now: _t(14),
    ).single;
    expect(s.isFree, isTrue);
    expect(s.until, isNull);
  });

  test('back-to-back sessions run the busy stretch to the end of both', () {
    final s = roomStatuses(
      rooms: const <AdeGroup>[_a],
      events: <ScheduleEvent>[
        _event(room: '*102* (VPI)', start: _t(13), end: _t(14)),
        _event(room: '*102* (VPI)', start: _t(14), end: _t(15), title: 'TD'),
      ],
      now: _t(13, 30),
    ).single;
    expect(s.isFree, isFalse);
    expect(s.until, _t(15));
  });

  test('an overlapping later session names the booking that frees last', () {
    final s = roomStatuses(
      rooms: const <AdeGroup>[_a],
      events: <ScheduleEvent>[
        _event(
          room: '*102* (VPI)',
          start: _t(13),
          end: _t(14, 30),
          title: 'CM',
        ),
        _event(room: '*102* (VPI)', start: _t(14), end: _t(16), title: 'TD'),
      ],
      now: _t(14, 15),
    ).single;
    expect(s.isFree, isFalse);
    expect(s.until, _t(16));
    expect(s.current?.title, 'TD');
  });

  test('a gap between sessions counts as free', () {
    final s = roomStatuses(
      rooms: const <AdeGroup>[_a],
      events: <ScheduleEvent>[
        _event(room: '*102* (VPI)', start: _t(13), end: _t(14)),
        _event(room: '*102* (VPI)', start: _t(16), end: _t(17)),
      ],
      now: _t(14, 30),
    ).single;
    expect(s.isFree, isTrue);
    expect(s.until, _t(16));
  });

  test('a session booked in two rooms occupies both', () {
    final statuses = roomStatuses(
      rooms: const <AdeGroup>[_a, _b],
      events: <ScheduleEvent>[
        _event(room: '*102* (VPI),*201*(V)', start: _t(13), end: _t(15)),
      ],
      now: _t(14),
    );
    expect(statuses.every((s) => !s.isFree), isTrue);
  });

  test('interior spacing does not stop a room matching its events', () {
    const room = AdeGroup(
      id: 9,
      name: '*106  (V)co-modal',
      category: AdeCategory.room,
    );
    final s = roomStatuses(
      rooms: const <AdeGroup>[room],
      events: <ScheduleEvent>[
        _event(room: '*106 (V)co-modal', start: _t(13), end: _t(15)),
      ],
      now: _t(14),
    ).single;
    expect(s.isFree, isFalse);
  });

  test('an event in an unknown room is ignored rather than mismatched', () {
    final statuses = roomStatuses(
      rooms: const <AdeGroup>[_a],
      events: <ScheduleEvent>[
        _event(room: 'Salle inconnue', start: _t(13), end: _t(15)),
      ],
      now: _t(14),
    );
    expect(statuses.single.isFree, isTrue);
  });

  group('groupByBuilding', () {
    String? building(AdeGroup g) => switch (g.id) {
      1 => '2',
      2 => '10',
      3 => '2',
      _ => null,
    };

    test('gathers rooms under the building they are in', () {
      final groups = groupByBuilding(
        roomStatuses(
          rooms: const <AdeGroup>[_a, _b, _c],
          events: const <ScheduleEvent>[],
          now: _t(14),
        ),
        building,
      );
      expect(groups.map((g) => g.building), <String>['2', '10']);
      expect(groups.first.rooms.map((s) => s.room.id), <int>[1, 3]);
    });

    test('orders buildings by number, so 10 follows 2', () {
      final groups = groupByBuilding(
        roomStatuses(
          rooms: const <AdeGroup>[_b, _a],
          events: const <ScheduleEvent>[],
          now: _t(14),
        ),
        building,
      );
      expect(groups.map((g) => g.building), <String>['2', '10']);
    });

    test('a room with no building is left out rather than bucketed', () {
      const orphan = AdeGroup(
        id: 99,
        name: 'SALLE DE MUSIQUE',
        category: AdeCategory.room,
      );
      final groups = groupByBuilding(
        roomStatuses(
          rooms: const <AdeGroup>[_a, orphan],
          events: const <ScheduleEvent>[],
          now: _t(14),
        ),
        building,
      );
      expect(groups, hasLength(1));
      expect(groups.single.rooms.map((s) => s.room.id), <int>[1]);
    });

    test('keeps the order the statuses arrived in', () {
      final groups = groupByBuilding(
        roomStatuses(
          rooms: const <AdeGroup>[_a, _c],
          events: <ScheduleEvent>[
            _event(room: '*102* (VPI)', start: _t(15), end: _t(16)),
          ],
          now: _t(14),
        ),
        building,
      );
      expect(groups.single.rooms.map((s) => s.room.id), <int>[3, 1]);
    });
  });

  test('free rooms come first, longest free stretch leading', () {
    final statuses = roomStatuses(
      rooms: const <AdeGroup>[_a, _b, _c],
      events: <ScheduleEvent>[
        _event(room: '*102* (VPI)', start: _t(13), end: _t(15)),
        _event(room: '*201*(V)', start: _t(15), end: _t(16)),
      ],
      now: _t(14),
    );
    expect(statuses.map((s) => s.room.name), <String>[
      'Amphi C (V)',
      '*201*(V)',
      '*102* (VPI)',
    ]);
  });
}
