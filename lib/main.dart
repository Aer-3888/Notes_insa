import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_colors.dart';
import 'core/time.dart';
import 'services/worker_sync_service.dart';
import 'modules/grades/grades_provider.dart';
import 'providers/auth_providers.dart';
import 'modules/grades/onboarding/onboarding_screen.dart';
import 'modules/grades/dashboard_screen.dart';
import 'modules/grades/two_factor_screen.dart';
import 'background_tasks.dart';
import 'constants.dart';
import 'services/notification_service.dart';
import 'core/auth/biometric_screen.dart';
import 'core/auth/pin_screen.dart';
import 'core/auth/privacy_cover.dart';
import 'core/auth/splash_screens.dart';

// Root navigator key so lifecycle handling can dismiss open modal routes
// (bottom sheets, dialogs, pushed screens) when the app is backgrounded.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initCampusTime();
  if (kAppSecret.isEmpty) {
    throw StateError('APP_SECRET not provided via --dart-define');
  }
  unawaited(initBackgroundTasks());
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Relevé',
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: AppColors.scaffoldBg,
        useMaterial3: true,
      ),
      // Wrap every route in a privacy curtain so the OS task-switcher snapshot
      // never reveals user data. Sits above the Navigator, so it also covers
      // open bottom sheets and dialogs.
      builder: (context, child) =>
          PrivacyCover(child: child ?? const SizedBox.shrink()),
      home: const AuthGate(),
    );
  }
}

// Decides between splash → biometric screen → dashboard, or login.
// Loads stored grades as a side effect on first build, separately from the
// credential check so the provider stays pure.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate>
    with WidgetsBindingObserver {
  StreamSubscription<String>? _notifSub;
  ProviderSubscription<bool>? _unlockSub;
  String? _pendingNotificationPayload;

  // Same channel as the native method calls; used only to receive notification
  // deep-link routes posted by MainActivity (see EXTRA_NOTIF_ROUTE there).
  static const _routeChannel = MethodChannel('com.aer.notes_insa/grades');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Load cached grades into state once on app start — independent of auth
    ref.read(gradesProvider.notifier).loadStoredGrades();
    // One-time mirror of existing secrets into the native worker store so
    // already-logged-in users enable background fetch without re-authenticating.
    unawaited(WorkerSyncService.backfill());
    unawaited(_setupNotifications());
    _unlockSub = ref.listenManual<bool>(appUnlockedProvider, (_, unlocked) {
      if (unlocked) _consumePendingNotification();
    });
  }

  Future<void> _setupNotifications() async {
    await NotificationService.initialize();
    _notifSub = NotificationService.tapStream.listen(_onNotificationTap);
    final pendingPayload = NotificationService.consumePendingPayload();
    if (pendingPayload != null) _onNotificationTap(pendingPayload);

    // Native background-worker notifications deep-link through MainActivity:
    // warm taps arrive as "onNotificationRoute" calls, cold-start taps are
    // pulled here. Both reuse the existing reauth tap handling (unlock-gated;
    // the dashboard banner remains the fallback when locked).
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

  void _onNotificationTap(String payload) {
    if (!mounted) return;
    // Preserve the tap until the user passes the biometric/PIN gate.
    if (!ref.read(appUnlockedProvider)) {
      _pendingNotificationPayload = payload;
      return;
    }
    switch (payload) {
      case 'reauth_required':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const TwoFactorScreen()));
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

  void _consumePendingNotification() {
    final payload = _pendingNotificationPayload;
    if (payload == null) return;
    _pendingNotificationPayload = null;
    _onNotificationTap(payload);
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _unlockSub?.close();
    _routeChannel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-arm the biometric/PIN gate whenever the app leaves the foreground.
    if (state == AppLifecycleState.paused) {
      final wasUnlocked = ref.read(appUnlockedProvider);
      ref.read(appUnlockedProvider.notifier).state = false;
      // The lock gate is a body swap inside AuthGate, so any open bottom sheet,
      // dialog, or pushed screen lives *above* it on the Navigator stack and
      // would otherwise linger over the lock screen on resume (and leak into the
      // task-switcher snapshot). Pop everything back down to the AuthGate root
      // so the biometric/PIN screen is the only thing on screen.
      if (wasUnlocked) {
        rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
      }
    }
  }

  DashboardScreen _dashboard(BuildContext context) => DashboardScreen(
    onReauthRequired: () => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TwoFactorScreen())),
  );

  @override
  Widget build(BuildContext context) {
    final gradesState = ref.watch(gradesProvider);

    if (gradesState.authStatus == AuthStatus.loggingOut) {
      return const LogoutProgressScreen();
    }
    if (gradesState.authStatus == AuthStatus.logoutFailed) {
      return LogoutFailedScreen(
        onRetry: () => unawaited(ref.read(gradesProvider.notifier).logout()),
      );
    }

    return ref
        .watch(hasCredentialsProvider)
        .when(
          loading: () => const SplashScreen(),
          error: (_, _) => const OnboardingScreen(),
          data: (hasCreds) {
            if (!hasCreds) return const OnboardingScreen();

            // Lock gate: until the user passes biometric/PIN this session, no
            // auth state may reveal the dashboard.
            final unlocked = ref.watch(appUnlockedProvider);
            if (!unlocked) {
              return gradesState.authStatus == AuthStatus.pinRequired
                  ? const PinScreen()
                  : const BiometricScreen();
            }

            // Unlocked — drive the dashboard/splash from auth status.
            switch (gradesState.authStatus) {
              case AuthStatus.authenticating:
                // Show data immediately if we have it; otherwise a splash with
                // an escape hatch in case the native call hangs.
                return gradesState.hasData
                    ? _dashboard(context)
                    : const AuthenticatingSplash();
              case AuthStatus.unauthenticated:
              case AuthStatus.pinRequired:
              case AuthStatus.error:
              case AuthStatus.twoFactorRequired:
              case AuthStatus.authenticated:
              case AuthStatus.loggingOut:
              case AuthStatus.logoutFailed:
                // The Dashboard handles cached data and any necessary banners.
                return _dashboard(context);
            }
          },
        );
  }
}
