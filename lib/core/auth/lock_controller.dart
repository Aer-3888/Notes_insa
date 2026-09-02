import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import 'lock_screen.dart';

/// Owns re-arming the grades lock across the app lifecycle.
///
/// The lock is a pushed route, not a body swap. A route on the root navigator
/// sits above every bottom sheet and dialog by construction, so nothing a
/// module opened can survive on top of it.
class LockController {
  LockController(this._container, this._navigatorKey);

  final ProviderContainer _container;
  final GlobalKey<NavigatorState> _navigatorKey;

  static const String lockRouteName = 'grades-lock';

  bool _lockRouteIsShowing = false;

  /// Re-arms the lock. Called on AppLifecycleState.paused.
  void onPause() {
    _container.read(gradesUnlockedProvider.notifier).state = false;
  }

  /// Shows the lock if the grades module is locked and no lock is already up.
  Future<void> onResume() async {
    if (_lockRouteIsShowing) return;
    if (_container.read(gradesUnlockedProvider)) return;

    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    _lockRouteIsShowing = true;
    try {
      await navigator.push(
        PageRouteBuilder<void>(
          settings: const RouteSettings(name: lockRouteName),
          opaque: true,
          transitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => const LockScreen(),
        ),
      );
    } finally {
      _lockRouteIsShowing = false;
    }
  }
}
