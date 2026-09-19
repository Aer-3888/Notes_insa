import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/module_cache.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/schedule/hidden_courses_provider.dart';
import 'package:notes_insa/modules/schedule/hide_rule.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ScheduleEvent _at(Duration fromNow, {required String title, String? module}) {
  final start = campusNow().add(fromNow);
  return ScheduleEvent(
    title: title,
    start: start,
    end: start.add(const Duration(hours: 2)),
    groups: const <String>[],
    teachers: const <String>[],
    module: module ?? title,
    room: 'Amphi C',
  );
}

/// Keeps the preview subscribed and lets the stream emit, which a bare read
/// cannot do.
Future<List<ScheduleEvent>> _upcoming(ProviderContainer container) async {
  final subscription = container.listen(
    upcomingCoursesProvider,
    (_, _) {},
    fireImmediately: true,
  );
  await Future<void>.delayed(Duration.zero);
  return subscription.read();
}

ProviderContainer _container(List<ScheduleEvent> events) {
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
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initCampusTime);

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('the stored rules', () {
    test('start empty', () async {
      final container = _container(const <ScheduleEvent>[]);
      await container.read(hiddenRulesProvider.notifier).loaded;
      expect(container.read(hiddenRulesProvider), isEmpty);
    });

    test('an added rule survives a reload', () async {
      final container = _container(const <ScheduleEvent>[]);
      final rule = HideRule.titleContains('anglais');
      await container.read(hiddenRulesProvider.notifier).add(rule);

      final reloaded = _container(const <ScheduleEvent>[]);
      await reloaded.read(hiddenRulesProvider.notifier).loaded;
      expect(reloaded.read(hiddenRulesProvider), <HideRule>[rule]);
    });

    test('adding the same rule twice keeps one', () async {
      final container = _container(const <ScheduleEvent>[]);
      final notifier = container.read(hiddenRulesProvider.notifier);
      await notifier.add(HideRule.titleContains('anglais'));
      await notifier.add(HideRule.titleContains('anglais'));
      expect(container.read(hiddenRulesProvider), hasLength(1));
    });

    test('a removed rule is gone', () async {
      final container = _container(const <ScheduleEvent>[]);
      final notifier = container.read(hiddenRulesProvider.notifier);
      final rule = HideRule.titleContains('anglais');
      await notifier.add(rule);
      await notifier.remove(rule);
      expect(container.read(hiddenRulesProvider), isEmpty);
    });

    test('an unreadable stored entry is skipped, not thrown on', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kHiddenRulesKey: <String>['not json at all', '{"field":"module"}'],
      });
      final container = _container(const <ScheduleEvent>[]);
      await container.read(hiddenRulesProvider.notifier).loaded;
      expect(container.read(hiddenRulesProvider), isEmpty);
    });
  });

  group('the hub preview', () {
    test('drops what a rule matches', () async {
      final container = _container(<ScheduleEvent>[
        _at(const Duration(hours: 1), title: 'Anglais 3'),
        _at(const Duration(hours: 4), title: 'Analyse 3'),
      ]);
      await container.read(hiddenRulesProvider.notifier).loaded;
      await container
          .read(hiddenRulesProvider.notifier)
          .add(HideRule.titleContains('anglais'));

      final upcoming = await _upcoming(container);
      expect(upcoming.map((e) => e.title), <String>['Analyse 3']);
    });

    test('keeps every session when no rule is set', () async {
      final container = _container(<ScheduleEvent>[
        _at(const Duration(hours: 1), title: 'Analyse 3'),
      ]);
      expect(await _upcoming(container), hasLength(1));
    });

    test('reads the timetable directly, with no provider in between', () {
      // A derived provider between the stream and the card invalidates itself
      // while the card is building. See the widget test in schedule_hidden.
      final source = File(
        'lib/modules/schedule/schedule_provider.dart',
      ).readAsStringSync();
      expect(source.contains('visibleScheduleProvider'), isFalse);
    });
  });

  group('the reveal toggle', () {
    test('starts off', () async {
      final container = _container(const <ScheduleEvent>[]);
      expect(container.read(scheduleRevealHiddenProvider), isFalse);
    });

    test('survives a reload', () async {
      final container = _container(const <ScheduleEvent>[]);
      await container.read(scheduleRevealHiddenProvider.notifier).toggle();

      final reloaded = _container(const <ScheduleEvent>[]);
      // The first read is what builds the notifier and starts its restore.
      reloaded.read(scheduleRevealHiddenProvider);
      await Future<void>.delayed(Duration.zero);
      expect(reloaded.read(scheduleRevealHiddenProvider), isTrue);
    });
  });
}
