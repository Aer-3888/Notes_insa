import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/schedule/hide_rule.dart';
import 'package:notes_insa/modules/schedule/ics_parser.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';

void main() {
  setUpAll(initCampusTime);

  late List<ScheduleEvent> events;

  setUp(() {
    events = parseAdeIcs(File('test/fixtures/ade_week.ics').readAsStringSync());
  });

  ScheduleEvent event(String title) =>
      events.firstWhere((e) => e.title.startsWith(title));

  group('series rules', () {
    test('hide one series and every session of it goes', () {
      final rule = HideRule.series(event('SA_L'))!;
      final visible = visibleEvents(events, <HideRule>[rule]);
      expect(visible.where((e) => e.title == 'SA_L'), isEmpty);
      expect(visible, hasLength(events.length - 2));
    });

    test('a series rule leaves every other course alone', () {
      final rule = HideRule.series(event('Algèbre 3'))!;
      final visible = visibleEvents(events, <HideRule>[rule]);
      expect(visible.any((e) => e.title.startsWith('Analyse 3')), isTrue);
    });

    test('a series rule is offered only when ADE gave an activity id', () {
      final orphan = ScheduleEvent(
        title: 'Sans uid',
        start: DateTime(2026, 9, 7, 12),
        end: DateTime(2026, 9, 7, 14),
        groups: const <String>[],
        teachers: const <String>[],
      );
      expect(HideRule.series(orphan), isNull);
    });
  });

  group('module rules', () {
    test('hide a module and its sessions go whatever the summary says', () {
      final rule = HideRule.module(event('SA_L'));
      final visible = visibleEvents(events, <HideRule>[rule]);
      expect(visible.where((e) => e.module == 'Systemes automatises'), isEmpty);
    });

    test('a module rule keys on the same name the colours use', () {
      // `Thermoénergétique _GHIJKL` and its module name must land together.
      final rule = HideRule.module(event('Thermoénergétique'));
      expect(rule.value, 'thermo-energetique');
    });
  });

  group('occurrence rules', () {
    test('the label names the day, so it is not read as the module', () {
      final rule = HideRule.occurrence(
        ScheduleEvent(
          title: 'Analyse 3_GHIJKL',
          start: DateTime(2026, 10, 12, 8),
          end: DateTime(2026, 10, 12, 10),
          groups: const <String>[],
          teachers: const <String>[],
          module: 'Analyse 3',
          uid: 'ADE60-4276-12',
        ),
      )!;
      expect(rule.label, 'Analyse 3 · 12 octobre');
    });

    test('hide one session and its siblings stay', () {
      final sa = events.where((e) => e.title == 'SA_L').toList();
      final rule = HideRule.occurrence(sa.first)!;
      final visible = visibleEvents(events, <HideRule>[rule]);
      expect(visible.where((e) => e.title == 'SA_L'), hasLength(1));
    });
  });

  group('custom rules', () {
    test('teacher matches whatever the case', () {
      final rule = HideRule.teacher('ley olivier');
      expect(rule.matches(event('Analyse 3')), isTrue);
    });

    test('title contains matches the module name too', () {
      final rule = HideRule.titleContains('bases de donnees');
      expect(rule.matches(event('INFORMATIQUE_L')), isTrue);
    });

    test('room matches a fragment', () {
      final rule = HideRule.room('amphi c');
      final visible = visibleEvents(events, <HideRule>[rule]);
      expect(
        visible.any((e) => e.room?.startsWith('Amphi C') ?? false),
        isFalse,
      );
    });

    test('the hors cours preset catches what has no module', () {
      const rule = HideRule.nonCourse();
      final hidden = hiddenEvents(events, <HideRule>[rule]);
      expect(hidden, hasLength(2));
      expect(hidden.every((e) => e.module == null), isTrue);
    });
  });

  group('the rule set as a whole', () {
    test('no rules hides nothing', () {
      expect(visibleEvents(events, const <HideRule>[]), hasLength(16));
    });

    test('rules combine as or', () {
      final rules = <HideRule>[
        HideRule.module(event('SA_L')),
        const HideRule.nonCourse(),
      ];
      expect(hiddenEvents(events, rules), hasLength(4));
    });

    test('visible and hidden always partition the input', () {
      final rules = <HideRule>[
        HideRule.room('amphi'),
        HideRule.teacher('LEY OLIVIER'),
      ];
      expect(
        visibleEvents(events, rules).length +
            hiddenEvents(events, rules).length,
        events.length,
      );
    });
  });

  group('storage', () {
    test('a rule survives a round trip', () {
      final rule = HideRule.series(event('SA_L'))!;
      expect(HideRule.fromJson(rule.toJson()), rule);
    });

    test('an unknown field is dropped rather than thrown on', () {
      expect(
        HideRule.fromJson(<String, dynamic>{
          'field': 'colour_of_the_sky',
          'value': 'blue',
          'label': 'Bleu',
        }),
        isNull,
      );
    });

    test('a malformed entry is dropped', () {
      expect(HideRule.fromJson(<String, dynamic>{'value': 1}), isNull);
    });
  });
}
