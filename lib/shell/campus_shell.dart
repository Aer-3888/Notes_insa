import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/cas_guard.dart';
import '../core/auth/lock_controller.dart';
import '../core/auth/pending_deep_link_controller.dart';
import '../core/auth/splash_screens.dart';
import '../main.dart' show rootNavigatorKey;
import '../modules/grades/grades_provider.dart';
import '../modules/grades/two_factor_screen.dart';
import '../app_colors.dart';
import '../modules/registry.dart';
import '../providers/auth_providers.dart';
import '../services/notification_service.dart';
import '../services/worker_sync_service.dart';
import 'app_settings_screen.dart';
import 'home_hub_screen.dart';

/// Root of the app. Opens on the campus hub with no account; only modules that
/// declare requiresCas are gated.
class CampusShell extends ConsumerStatefulWidget {
  const CampusShell({super.key});

  @override
  ConsumerState<CampusShell> createState() => _CampusShellState();
}

class _CampusShellState extends ConsumerState<CampusShell>
    with WidgetsBindingObserver {
  StreamSubscription<String>? _notifSub;
  PendingDeepLinkController? _deepLinks;
  LockController? _lock;

  /// Accueil sits in the middle of five destinations, so it is index 2.
  static const int _homeIndex = 2;
  static const int _notesIndex = 3;

  int _index = _homeIndex;

  /// Destinations that have been opened at least once. IndexedStack builds
  /// every child eagerly, which would construct the grades dashboard for a user
  /// who never logs in, so unvisited destinations render nothing until chosen.
  final Set<int> _visited = <int>{_homeIndex};

  // Same channel as the native method calls; used only to receive notification
  // deep-link routes posted by MainActivity (see EXTRA_NOTIF_ROUTE there).
  static const _routeChannel = MethodChannel('com.aer.notes_insa/grades');

  /// The five bottom destinations, in bar order. Labels and icons come from the
  /// registry where a module owns them, so the bar and the hub cannot disagree.
  ///
  /// Accueil and Paramètres are shell surfaces rather than modules, so they are
  /// named here.
  static final List<_Destination> _destinations = <_Destination>[
    _Destination.module('carte'),
    _Destination.module('edt'),
    const _Destination(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      label: 'Accueil',
    ),
    _Destination.module('notes'),
    const _Destination(
      icon: Icons.tune_outlined,
      selectedIcon: Icons.tune,
      label: 'Paramètres',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final container = ProviderScope.containerOf(context, listen: false);
    _lock = LockController(container, rootNavigatorKey);
    _deepLinks = PendingDeepLinkController(
      container,
      onDeliver: _handleDeepLink,
    );
    // Cached grades are read from local storage only, so this is cheap and
    // stays unconditional.
    ref.read(gradesProvider.notifier).loadStoredGrades();
    unawaited(_bootstrapForSignedInUsers());
  }

  /// Secret mirroring and notification setup only matter to a user who has an
  /// account. An anonymous hub visitor should pay for neither.
  Future<void> _bootstrapForSignedInUsers() async {
    final hasCreds = await ref.read(hasCredentialsProvider.future);
    if (!hasCreds || !mounted) return;
    unawaited(WorkerSyncService.backfill());
    await _setupNotifications();
  }

  Future<void> _setupNotifications() async {
    await NotificationService.initialize();
    _notifSub = NotificationService.tapStream.listen(_onNotificationTap);
    final pendingPayload = NotificationService.consumePendingPayload();
    if (pendingPayload != null) _onNotificationTap(pendingPayload);

    // Native background-worker notifications deep-link through MainActivity:
    // warm taps arrive as "onNotificationRoute" calls, cold-start taps are
    // pulled here.
    _routeChannel.setMethodCallHandler(_onNativeRoute);
    final route = await _routeChannel.invokeMethod<String>(
      'ConsumeNotificationRoute',
    );
    _handleNativeRoute(route);
  }

  Future<dynamic> _onNativeRoute(MethodCall call) async {
    if (call.method == 'onNotificationRoute') {
      _handleNativeRoute(call.arguments as String?);
    }
  }

  void _handleNativeRoute(String? route) {
    switch (route) {
      case 'reauth':
        _onNotificationTap('reauth_required');
      case 'refresh':
        _onNotificationTap('background_refresh_failed');
    }
  }

  /// Every payload goes through the buffer, which withholds it until the grades
  /// module is unlocked. None of them may act on a locked session.
  void _onNotificationTap(String payload) {
    if (!mounted) return;
    _deepLinks?.submit(payload);
  }

  void _handleDeepLink(String payload) {
    if (!mounted) return;
    switch (payload) {
      case 'reauth_required':
        _select(_notesIndex);
        rootNavigatorKey.currentState?.push(
          MaterialPageRoute<void>(builder: (_) => const TwoFactorScreen()),
        );
      case 'new_grades':
      case 'updated_grades':
      case 'background_refresh_failed':
        unawaited(
          ref
              .read(gradesProvider.notifier)
              .fetchGradesWithStoredCredentials()
              .catchError((_) {}),
        );
    }
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _deepLinks?.dispose();
    _routeChannel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _lock?.onPause();
    } else if (state == AppLifecycleState.resumed) {
      _ensureLockIfNeeded();
    }
  }

  /// Shows the lock only when a gated destination is actually on screen and the
  /// user has an account. Someone browsing the hub or the timetable is never
  /// asked to unlock anything.
  void _ensureLockIfNeeded() {
    if (_index != _notesIndex) return;
    final hasCreds = ref.read(hasCredentialsProvider).value ?? false;
    if (!hasCreds) return;
    unawaited(_lock?.onResume() ?? Future<void>.value());
  }

  void _select(int index) {
    setState(() {
      _index = index;
      _visited.add(index);
    });
    _ensureLockIfNeeded();
  }

  Widget _bodyFor(int index) {
    if (!_visited.contains(index)) return const SizedBox.shrink();
    if (index == _homeIndex) return const HomeHubScreen();
    if (index == _destinations.length - 1) return const AppSettingsScreen();

    final module = _destinations[index].module;
    return switch (module) {
      ReadyModule(:final builder, :final requiresCas) =>
        requiresCas
            ? CasGuard(child: Builder(builder: builder))
            : Builder(builder: builder),
      ComingSoonModule() => _ComingSoon(module: module),
      null => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final gradesState = ref.watch(gradesProvider);

    // Logout stays a root takeover: it is rare, destructive, and must not be
    // interruptible by tab switching.
    if (gradesState.authStatus == AuthStatus.loggingOut) {
      return const LogoutProgressScreen();
    }
    if (gradesState.authStatus == AuthStatus.logoutFailed) {
      return LogoutFailedScreen(
        onRetry: () => unawaited(ref.read(gradesProvider.notifier).logout()),
      );
    }

    return PopScope(
      canPop: _index == _homeIndex,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(_homeIndex);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: <Widget>[
            for (var i = 0; i < _destinations.length; i++) _bodyFor(i),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: <NavigationDestination>[
            for (final d in _destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon ?? d.icon),
                label: d.label,
              ),
          ],
        ),
      ),
    );
  }
}

/// One bottom-bar destination. A module-backed one takes its icon and label
/// from the registry; Accueil and Paramètres are shell surfaces and name
/// themselves.
class _Destination {
  const _Destination({
    required this.icon,
    required this.label,
    this.selectedIcon,
    this.module,
  });

  factory _Destination.module(String id) {
    final m = kCampusModules.firstWhere((m) => m.id == id);
    return _Destination(icon: m.icon, label: m.label, module: m);
  }

  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final CampusModule? module;
}

/// A module that is in the bar but not built yet. It is a destination rather
/// than a hidden entry so the app says plainly what is coming.
class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.module});

  final ComingSoonModule module;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(module.label),
      foregroundColor: Colors.white,
      flexibleSpace: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.headerGradient,
          ),
        ),
      ),
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(module.icon, size: 56, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              module.teaser,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Bientôt disponible',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    ),
  );
}
