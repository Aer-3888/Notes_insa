import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/cas_guard.dart';
import '../core/campus_navigation.dart';
import '../core/auth/lock_controller.dart';
import '../core/auth/pending_deep_link_controller.dart';
import '../core/auth/splash_screens.dart';
import '../main.dart' show rootNavigatorKey;
import '../modules/associations/association_detail_screen.dart';
import '../modules/associations/association_reminder_provider.dart';
import '../modules/associations/association_reminders.dart';
import '../modules/crous/crous_map_details.dart';
import '../modules/grades/grades_provider.dart';
import '../modules/grades/two_factor_screen.dart';
import '../modules/registry.dart';
import '../modules/schedule/schedule_focus.dart';
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
  AssociationReminderScheduler? _assoReminders;

  /// Aujourd'hui sits at the centre of the bar; it is where the app opens and
  /// where system back always lands.
  static const int _homeIndex = 2;
  static const int _notesIndex = 1;
  static const int _settingsIndex = 4;

  int _index = _homeIndex;
  final CampusMapFocus _mapFocus = CampusMapFocus();

  /// Destinations that have been opened at least once. IndexedStack builds
  /// every child eagerly, which would construct the grades dashboard for a user
  /// who never logs in, so unvisited destinations render nothing until chosen.
  final Set<int> _visited = <int>{_homeIndex};

  /// One per destination, so a page opened from a tab stays under the bar.
  /// Takeovers opt out with `rootNavigator: true`.
  final List<GlobalKey<NavigatorState>> _tabNavigators =
      <GlobalKey<NavigatorState>>[
        for (var i = 0; i < 5; i++) GlobalKey<NavigatorState>(),
      ];

  // Same channel as the native method calls; used only to receive notification
  // deep-link routes posted by MainActivity (see EXTRA_NOTIF_ROUTE there).
  static const _routeChannel = MethodChannel('com.aer.notes_insa/grades');

  /// The five bottom destinations, in bar order. Labels and icons come from the
  /// registry where a module owns them, so the bar and the hub cannot disagree.
  /// Aujourd'hui and Réglages are shell surfaces and name themselves.
  static final List<_Destination> _destinations = <_Destination>[
    _Destination.module('edt'),
    _Destination.module('notes'),
    const _Destination(
      icon: Icons.today_outlined,
      selectedIcon: Icons.today,
      label: 'Aujourd’hui',
    ),
    _Destination.module('carte'),
    const _Destination(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Réglages',
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
    // Association reminders belong to every student, not only the ones with
    // an INSA account, so this is set up outside the signed-in bootstrap.
    _assoReminders = AssociationReminderScheduler(container);
    unawaited(_setupNotifications());
    unawaited(_bootstrapForSignedInUsers());
  }

  /// Secret mirroring and notification setup only matter to a user who has an
  /// account. An anonymous hub visitor should pay for neither.
  Future<void> _bootstrapForSignedInUsers() async {
    final hasCreds = await ref.read(hasCredentialsProvider.future);
    if (!hasCreds || !mounted) return;
    unawaited(WorkerSyncService.backfill());
  }

  Future<void> _setupNotifications() async {
    if (_notifSub != null) return;
    await NotificationService.initialize();
    if (!mounted) return;
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
    // An association reminder has nothing to do with grades, so it must not
    // sit in the buffer waiting for a lock the student may never open.
    final associationId = associationIdFromPayload(payload);
    if (associationId != null) {
      _openAssociation(associationId);
      return;
    }
    _deepLinks?.submit(payload);
  }

  void _openAssociation(String associationId) {
    _select(_homeIndex);
    _tabNavigators[_homeIndex].currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => AssociationDetailScreen(associationId: associationId),
      ),
    );
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
    _assoReminders?.dispose();
    _deepLinks?.dispose();
    _routeChannel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    _mapFocus.dispose();
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

  void _select(int index, {bool resetSchedule = true}) {
    final isReturningToSchedule =
        index == 0 && _index != index && resetSchedule;
    if (isReturningToSchedule) {
      ref.read(scheduleTodayRequestProvider.notifier).request();
    }
    setState(() {
      _index = index;
      _visited.add(index);
    });
    _ensureLockIfNeeded();
  }

  /// The hub's cards select a destination rather than pushing the module.
  /// Modules the bar has no room for have no destination to select, so they
  /// open as a page in the current tab and keep the bar.
  void _openModule(String id) {
    final index = _destinations.indexWhere((d) => d.module?.id == id);
    if (index >= 0) {
      final opensFocusedEvent =
          id == 'edt' && ref.read(scheduleFocusProvider) != null;
      _select(index, resetSchedule: !opensFocusedEvent);
      return;
    }
    for (final module in kCampusModules) {
      if (module.id != id) continue;
      if (module is! ReadyModule) return;
      _tabNavigators[_index].currentState?.push(
        MaterialPageRoute<void>(builder: (_) => _screenFor(module)),
      );
      return;
    }
  }

  void _openMap(String buildingCode, {bool startGuidance = false}) {
    _mapFocus.request(buildingCode, startGuidance: startGuidance);
    _tabNavigators[3].currentState?.popUntil((route) => route.isFirst);
    _select(3);
  }

  /// A module's screen, behind the lock when it needs an account.
  Widget _screenFor(ReadyModule module) => module.requiresCas
      ? CasGuard(child: Builder(builder: module.builder))
      : Builder(builder: module.builder);

  /// Built on first visit, so an unvisited tab still costs nothing.
  Widget _destinationFor(int index) {
    if (!_visited.contains(index)) return const SizedBox.shrink();
    return Navigator(
      key: _tabNavigators[index],
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => _bodyFor(index),
      ),
    );
  }

  Widget _bodyFor(int index) {
    if (index == _homeIndex) return HomeHubScreen(onOpenModule: _openModule);
    if (index == _settingsIndex) return const AppSettingsScreen();

    final module = _destinations[index].module;
    return switch (module) {
      ReadyModule() => _screenFor(module),
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

    // Not `canPop`: it is read at build time and goes stale on a tab push.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final tab = _tabNavigators[_index].currentState;
        if (tab != null && tab.canPop()) {
          tab.pop();
          return;
        }
        if (_index != _homeIndex) {
          _select(_homeIndex);
          return;
        }
        SystemNavigator.pop();
      },
      child: CampusPlaceDetailsScope(
        builder: (code) => CrousMapDetails(mapCode: code),
        child: CampusNavigationScope(
          mapFocus: _mapFocus,
          onOpenMap: _openMap,
          child: Scaffold(
            body: IndexedStack(
              index: _index,
              children: <Widget>[
                // IndexedStack keeps every visited tab alive, so a hidden one
                // would keep animating and keep its sensors running.
                for (var i = 0; i < _destinations.length; i++)
                  TickerMode(enabled: i == _index, child: _destinationFor(i)),
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
        ),
      ),
    );
  }
}

/// One bottom-bar destination. A module-backed one takes its icon and label
/// from the registry; Aujourd'hui is a shell surface and names itself.
class _Destination {
  const _Destination({
    required this.icon,
    required this.label,
    this.selectedIcon,
    this.module,
  });

  factory _Destination.module(String id) {
    final m = kCampusModules.firstWhere((m) => m.id == id);
    return _Destination(icon: m.icon, label: m.barLabel, module: m);
  }

  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final CampusModule? module;
}
