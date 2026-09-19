import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/time.dart';
import '../../services/notification_service.dart';
import 'association.dart';
import 'association_notification_permission.dart';
import 'association_reminders.dart';
import 'association_service.dart';

/// How long before an event to be reminded. Stored, so it survives a restart.
class AssociationReminderLeadNotifier
    extends Notifier<AssociationReminderLead> {
  static const String key = 'association_reminder_lead';

  Future<void>? _loaded;

  @visibleForTesting
  Future<void> get loaded => _loaded ?? Future<void>.value();

  @override
  AssociationReminderLead build() {
    _loaded = _load();
    return AssociationReminderLead.fallback;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = AssociationReminderLead.parse(prefs.getString(key));
    } catch (e) {
      if (kDebugMode) debugPrint('[AssociationReminders] load failed: $e');
    }
  }

  Future<void> set(AssociationReminderLead lead) async {
    if (state == lead) return;
    state = lead;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, lead.name);
    } catch (e) {
      if (kDebugMode) debugPrint('[AssociationReminders] save failed: $e');
    }
  }
}

final associationReminderLeadProvider =
    NotifierProvider<AssociationReminderLeadNotifier, AssociationReminderLead>(
      AssociationReminderLeadNotifier.new,
    );

/// What should currently be pending on the device.
///
/// Derived rather than stored: follows, the directory and the lead time each
/// invalidate it, so there is no way for the schedule to drift from what the
/// student actually asked for.
final associationReminderPlanProvider = Provider<List<AssociationReminder>>((
  ref,
) {
  final lead = ref.watch(associationReminderLeadProvider);
  if (lead == AssociationReminderLead.off) {
    return const <AssociationReminder>[];
  }
  final followed = ref.watch(followedAssociationEventsProvider);
  if (followed.isEmpty) return const <AssociationReminder>[];

  final all = ref.watch(associationsProvider).value ?? const <Association>[];
  return planAssociationReminders(
    events: followed,
    directory: <String, Association>{for (final a in all) a.id: a},
    lead: lead,
    now: campusNow(),
  );
});

/// Keeps the device's pending notifications matching the plan.
///
/// Started by the shell. Riverpod hands it every change, so following an
/// association reschedules immediately rather than at the next launch.
abstract interface class AssociationReminderPlatform {
  Future<void> schedule(List<AssociationReminder> reminders);
  Future<void> cancel();
}

class _DeviceAssociationReminderPlatform
    implements AssociationReminderPlatform {
  @override
  Future<void> schedule(List<AssociationReminder> reminders) =>
      NotificationService.scheduleAssociationReminders(<
        ({int id, DateTime fireAt, String title, String body, String payload})
      >[
        for (final reminder in reminders)
          (
            id: reminder.id,
            fireAt: reminder.fireAt,
            title: reminder.title,
            body: reminder.body,
            payload: reminder.payload,
          ),
      ]);

  @override
  Future<void> cancel() => NotificationService.cancelAssociationReminders();
}

class AssociationReminderScheduler {
  AssociationReminderScheduler(
    this._container, {
    AssociationReminderPlatform? platform,
  }) : _platform = platform ?? _DeviceAssociationReminderPlatform() {
    _planSubscription = _container.listen<List<AssociationReminder>>(
      associationReminderPlanProvider,
      (_, _) => unawaited(_applyCurrentPlan()),
      fireImmediately: true,
    );
    _permissionSubscription = _container
        .listen<AsyncValue<NotificationPermissionState>>(
          associationNotificationPermissionProvider,
          (_, _) => unawaited(_applyCurrentPlan()),
          fireImmediately: true,
        );
  }

  final ProviderContainer _container;
  final AssociationReminderPlatform _platform;
  late final ProviderSubscription<List<AssociationReminder>> _planSubscription;
  late final ProviderSubscription<AsyncValue<NotificationPermissionState>>
  _permissionSubscription;

  Future<void> _inFlight = Future<void>.value();

  Future<void> _apply(List<AssociationReminder> plan) {
    _inFlight = _inFlight
        .then((_) => _schedule(plan))
        .catchError((Object _) {});
    return _inFlight;
  }

  Future<void> _applyCurrentPlan() =>
      _apply(_container.read(associationReminderPlanProvider));

  Future<void> _schedule(List<AssociationReminder> plan) async {
    final permission = _container
        .read(associationNotificationPermissionProvider)
        .value;
    if (permission?.isGranted != true || plan.isEmpty) {
      await _platform.cancel();
      return;
    }
    await _platform.schedule(plan);
  }

  Future<void> refreshPermission() async {
    _container.invalidate(associationNotificationPermissionProvider);
    await _container.read(associationNotificationPermissionProvider.future);
    await _applyCurrentPlan();
  }

  Future<void> get idle => _inFlight;

  void dispose() {
    _planSubscription.close();
    _permissionSubscription.close();
  }
}
