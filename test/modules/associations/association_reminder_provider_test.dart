import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/associations/association.dart';
import 'package:notes_insa/modules/associations/association_follows.dart';
import 'package:notes_insa/modules/associations/association_notification_permission.dart';
import 'package:notes_insa/modules/associations/association_reminder_provider.dart';
import 'package:notes_insa/modules/associations/association_reminders.dart';
import 'package:notes_insa/modules/associations/association_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notes_insa/services/notification_service.dart';

class _FakePermissions implements NotificationPermissionGateway {
  _FakePermissions(this.value);

  NotificationPermissionState value;

  @override
  Future<void> openSettings() async {}

  @override
  Future<NotificationPermissionState> request() async => value;

  @override
  Future<NotificationPermissionState> status() async => value;
}

class _FakeReminderPlatform implements AssociationReminderPlatform {
  var cancels = 0;
  final schedules = <List<AssociationReminder>>[];

  @override
  Future<void> cancel() async {
    cancels++;
  }

  @override
  Future<void> schedule(List<AssociationReminder> reminders) async {
    schedules.add(reminders);
  }
}

Association _asso(String id, {List<AssociationEvent> events = const []}) =>
    Association(
      id: id,
      name: 'Asso $id',
      category: AssociationCategory.culture,
      events: events,
    );

AssociationEvent _event(String id, String association, DateTime startsAt) =>
    AssociationEvent(
      id: id,
      associationId: association,
      title: 'Évènement $id',
      startsAt: startsAt,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initCampusTime);

  late ProviderContainer container;

  Future<ProviderContainer> open({
    List<String> follows = const <String>[],
    AssociationReminderLead? lead,
    NotificationPermissionGateway? permissions,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AssociationFollowsNotifier.key: follows,
      if (lead != null) AssociationReminderLeadNotifier.key: lead.name,
    });
    final soon = campusNow().add(const Duration(days: 5));
    container = ProviderContainer(
      overrides: [
        associationsProvider.overrideWith(
          (ref) async => <Association>[
            _asso('a', events: <AssociationEvent>[_event('e1', 'a', soon)]),
            _asso('b', events: <AssociationEvent>[_event('e2', 'b', soon)]),
          ],
        ),
        if (permissions != null)
          notificationPermissionGatewayProvider.overrideWithValue(permissions),
      ],
    );
    addTearDown(container.dispose);
    await container.read(associationsProvider.future);
    await container.read(associationFollowsProvider.notifier).loaded;
    await container.read(associationReminderLeadProvider.notifier).loaded;
    return container;
  }

  test('nothing followed means nothing to schedule', () async {
    await open();
    expect(container.read(associationReminderPlanProvider), isEmpty);
  });

  test('the plan covers only the followed associations', () async {
    await open(follows: <String>['a']);
    final plan = container.read(associationReminderPlanProvider);
    expect(plan.map((r) => r.eventId), <String>['e1']);
  });

  test('following a second association extends the plan', () async {
    await open(follows: <String>['a']);
    await container.read(associationFollowsProvider.notifier).follow('b');
    final plan = container.read(associationReminderPlanProvider);
    expect(plan.map((r) => r.eventId).toSet(), <String>{'e1', 'e2'});
  });

  test('unfollowing takes its reminders back out', () async {
    await open(follows: <String>['a', 'b']);
    await container.read(associationFollowsProvider.notifier).unfollow('a');
    expect(
      container.read(associationReminderPlanProvider).map((r) => r.eventId),
      <String>['e2'],
    );
  });

  test(
    'turning reminders off empties the plan without losing follows',
    () async {
      await open(follows: <String>['a']);
      expect(container.read(associationReminderPlanProvider), isNotEmpty);

      await container
          .read(associationReminderLeadProvider.notifier)
          .set(AssociationReminderLead.off);

      expect(container.read(associationReminderPlanProvider), isEmpty);
      expect(container.read(associationFollowsProvider), <String>{'a'});
    },
  );

  test('the stored lead time is the one used', () async {
    await open(follows: <String>['a'], lead: AssociationReminderLead.oneHour);
    expect(
      container.read(associationReminderLeadProvider),
      AssociationReminderLead.oneHour,
    );
    final reminder = container.read(associationReminderPlanProvider).single;
    // One hour before, not the default day.
    expect(
      reminder.fireAt.difference(campusNow()).inHours,
      closeTo(5 * 24 - 1, 1),
    );
  });

  test('a lead time that is no longer offered falls back', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AssociationReminderLeadNotifier.key: 'une_semaine',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(associationReminderLeadProvider.notifier).loaded;
    expect(
      c.read(associationReminderLeadProvider),
      AssociationReminderLead.fallback,
    );
  });

  test('schedules only after notification permission is granted', () async {
    final permissions = _FakePermissions(NotificationPermissionState.denied);
    await open(follows: <String>['a'], permissions: permissions);
    final platform = _FakeReminderPlatform();
    final scheduler = AssociationReminderScheduler(
      container,
      platform: platform,
    );
    addTearDown(scheduler.dispose);

    await container.read(associationNotificationPermissionProvider.future);
    await scheduler.idle;
    expect(platform.schedules, isEmpty);
    expect(platform.cancels, greaterThanOrEqualTo(1));

    permissions.value = NotificationPermissionState.granted;
    await scheduler.refreshPermission();
    await scheduler.idle;
    expect(platform.schedules, isNotEmpty);
    expect(platform.schedules.last.map((r) => r.eventId), <String>['e1']);
  });
}
