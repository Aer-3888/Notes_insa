import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/notification_service.dart';
import 'association_follows.dart';
import 'association_notification_permission.dart';
import 'association_reminder_provider.dart';
import 'association_reminders.dart';

const _permissionPromptShownKey =
    'association_reminder_permission_prompt_shown';

Future<void> toggleAssociationFollow(
  BuildContext context,
  WidgetRef ref,
  String associationId,
) async {
  final follows = ref.read(associationFollowsProvider);
  final followNotifier = ref.read(associationFollowsProvider.notifier);
  if (follows.contains(associationId)) {
    await followNotifier.unfollow(associationId);
    return;
  }

  await followNotifier.follow(associationId);
  if (!context.mounted ||
      ref.read(associationReminderLeadProvider) ==
          AssociationReminderLead.off) {
    return;
  }

  final permission = await refreshAssociationNotificationPermission(ref);
  if (!context.mounted ||
      permission.isGranted ||
      permission == NotificationPermissionState.unavailable ||
      await _permissionPromptWasShown()) {
    return;
  }

  await _markPermissionPromptShown();
  if (!context.mounted) return;
  final shouldRequest = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Activer les rappels ?'),
      content: const Text(
        'Tu suivras toujours cette association. Active les notifications pour '
        'recevoir un rappel avant ses prochains événements.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Pas maintenant'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Activer'),
        ),
      ],
    ),
  );
  if (shouldRequest != true || !context.mounted) return;

  final result = await ref
      .read(notificationPermissionGatewayProvider)
      .request();
  await refreshAssociationNotificationPermission(ref);
  if (!context.mounted || result.isGranted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('Les rappels sont désactivés.'),
      action: SnackBarAction(
        label: 'Réglages',
        onPressed: () =>
            ref.read(notificationPermissionGatewayProvider).openSettings(),
      ),
    ),
  );
}

Future<bool> _permissionPromptWasShown() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_permissionPromptShownKey) ?? false;
  } catch (_) {
    return false;
  }
}

Future<void> _markPermissionPromptShown() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_permissionPromptShownKey, true);
  } catch (_) {}
}
