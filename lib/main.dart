import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_colors.dart';
import 'services/auth_service.dart';
import 'services/worker_sync_service.dart';
import 'providers/grades_provider.dart';
import 'providers/auth_providers.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/two_factor_screen.dart';
import 'background_tasks.dart';
import 'constants.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      debugShowCheckedModeBanner: false,
      title: 'Insa Notes',
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: AppColors.scaffoldBg,
        useMaterial3: true,
      ),
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
  }

  Future<void> _setupNotifications() async {
    await NotificationService.initialize();
    // Discard any cold-start payload — the normal startup flow already handles
    // everything: grades are re-fetched after biometric unlock, and a failed
    // 2FA auto-validate sets the reauth banner on the dashboard.
    NotificationService.consumePendingPayload();
    _notifSub = NotificationService.tapStream.listen(_onNotificationTap);
  }

  void _onNotificationTap(String payload) {
    if (!mounted) return;
    // Do nothing while the user hasn't passed the biometric/PIN gate yet.
    if (!ref.read(appUnlockedProvider)) return;
    switch (payload) {
      case 'reauth_required':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const TwoFactorScreen()));
      case 'new_grades':
      case 'updated_grades':
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-arm the biometric/PIN gate whenever the app leaves the foreground.
    if (state == AppLifecycleState.paused) {
      ref.read(appUnlockedProvider.notifier).state = false;
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

    return ref
        .watch(hasCredentialsProvider)
        .when(
          loading: () => const _SplashScreen(),
          error: (_, _) => const LoginScreen(),
          data: (hasCreds) {
            if (!hasCreds) return const LoginScreen();

            // Lock gate: until the user passes biometric/PIN this session, no
            // auth state may reveal the dashboard.
            final unlocked = ref.watch(appUnlockedProvider);
            if (!unlocked) {
              return gradesState.authStatus == AuthStatus.pinRequired
                  ? const _PinScreen()
                  : const _BiometricScreen();
            }

            // Unlocked — drive the dashboard/splash from auth status.
            switch (gradesState.authStatus) {
              case AuthStatus.authenticating:
                // Show data immediately if we have it; otherwise a splash with
                // an escape hatch in case the native call hangs.
                return gradesState.hasData
                    ? _dashboard(context)
                    : const _AuthenticatingSplash();
              case AuthStatus.unauthenticated:
              case AuthStatus.pinRequired:
              case AuthStatus.error:
              case AuthStatus.twoFactorRequired:
              case AuthStatus.authenticated:
                // The Dashboard handles cached data and any necessary banners.
                return _dashboard(context);
            }
          },
        );
  }
}

// Shown while credentials are being loaded from secure storage
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Align(
        alignment: Alignment(0, -0.65),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school, size: 72, color: AppColors.primary),
            SizedBox(height: 16),
            Text(
              'Notes INSA',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Shown while the first post-unlock fetch is running and there's no cached data
// yet. If the native call hangs, an escape hatch appears so the user is never
// stranded on a control-less splash.
class _AuthenticatingSplash extends ConsumerStatefulWidget {
  const _AuthenticatingSplash();

  @override
  ConsumerState<_AuthenticatingSplash> createState() =>
      _AuthenticatingSplashState();
}

class _AuthenticatingSplashState extends ConsumerState<_AuthenticatingSplash> {
  bool _showEscape = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _showEscape = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.school, size: 72, color: AppColors.primary),
              const SizedBox(height: 16),
              const Text(
                'Notes INSA',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(color: AppColors.primary),
              if (_showEscape) ...[
                const SizedBox(height: 32),
                Text(
                  'La connexion prend plus de temps que prévu.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Réessayer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      setState(() => _showEscape = false);
                      _timer?.cancel();
                      _timer = Timer(const Duration(seconds: 8), () {
                        if (mounted) setState(() => _showEscape = true);
                      });
                      unawaited(
                        ref
                            .read(gradesProvider.notifier)
                            .fetchGradesWithStoredCredentials()
                            .catchError((_) {}),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    ),
                    child: const Text('Se connecter autrement'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Handles the full biometric flow on a single screen — no navigation transitions
// between waiting / failed states. Uses pushAndRemoveUntil on success or
// "connect another way" so the back button can never loop back here.
class _BiometricScreen extends ConsumerStatefulWidget {
  const _BiometricScreen();

  @override
  ConsumerState<_BiometricScreen> createState() => _BiometricScreenState();
}

class _BiometricScreenState extends ConsumerState<_BiometricScreen>
    with TickerProviderStateMixin {
  bool _failed = false;
  bool _authenticating = false;
  bool _hasPin = false;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
          TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 8.0, end: -8.0), weight: 2),
          TweenSequenceItem(tween: Tween(begin: -8.0, end: 0.0), weight: 1),
        ]).animate(
          CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final authService = AuthService();
    final hasPin = await authService.hasPin();
    if (mounted) setState(() => _hasPin = hasPin);
    // Requesting the prompt on the very first frame can race with the Android
    // activity's resume transition — the FragmentManager may still report a
    // saved state from before the app was backgrounded, so BiometricPrompt
    // throws "Called after onSaveInstanceState" and the user is stuck on this
    // screen. A brief delay lets onResume() settle before the first attempt.
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    await _authenticate();
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() {
      _failed = false;
      _authenticating = true;
    });

    final result = await AuthService().authenticate();
    if (!mounted) return;

    if (result == AuthResult.success) {
      setState(() => _authenticating = false);
      _onSuccess();
    } else if (result == AuthResult.pinRequired) {
      setState(() => _authenticating = false);
      ref.read(gradesProvider.notifier).setPinRequired();
    } else {
      setState(() {
        _failed = true;
        _authenticating = false;
      });
      unawaited(_shakeController.forward(from: 0.0));
    }
  }

  void _onSuccess() {
    ref.read(appUnlockedProvider.notifier).state = true;
    unawaited(
      ref
          .read(gradesProvider.notifier)
          .fetchGradesWithStoredCredentials()
          .catchError((_) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Align(
        alignment: _failed ? Alignment.center : const Alignment(0, -0.65),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _shakeAnimation,
                builder: (_, child) => Transform.translate(
                  offset: Offset(_failed ? _shakeAnimation.value : 0.0, 0),
                  child: child,
                ),
                child: Icon(
                  _failed ? Icons.fingerprint : Icons.school,
                  size: 72,
                  color: _failed ? Colors.grey.shade400 : AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _failed ? 'Authentification échouée' : 'Notes INSA',
                style: TextStyle(
                  fontSize: _failed ? 20 : 24,
                  fontWeight: FontWeight.bold,
                  color: _failed ? Colors.grey.shade700 : AppColors.primary,
                  letterSpacing: 1.2,
                ),
              ),
              if (_failed) ...[
                const SizedBox(height: 8),
                Text(
                  'La vérification biométrique a été annulée ou a échoué.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Réessayer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _authenticate,
                  ),
                ),
                if (_hasPin) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.pin_outlined),
                      label: const Text('Utiliser le code PIN'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () =>
                          ref.read(gradesProvider.notifier).setPinRequired(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    ),
                    child: const Text('Se connecter autrement'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PinScreen extends ConsumerStatefulWidget {
  const _PinScreen();

  @override
  ConsumerState<_PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<_PinScreen> {
  final _pinController = TextEditingController();
  final _authService = AuthService();
  bool _error = false;
  int? _remainingAttempts;
  Duration? _lockout;
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshLockout());
  }

  Future<void> _refreshLockout() async {
    final remaining = await _authService.pinLockoutRemaining();
    if (!mounted) return;
    setState(() => _lockout = remaining);
    _lockoutTimer?.cancel();
    if (remaining != null) {
      // Tick down once a second until the lockout expires.
      _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        unawaited(_refreshLockout());
      });
    }
  }

  Future<void> _verify() async {
    if (_lockout != null) return;
    final success = await _authService.verifyPin(_pinController.text);
    if (success) {
      await _authService.resetPinAttempts();
      if (!mounted) return;
      ref.read(appUnlockedProvider.notifier).state = true;
      unawaited(
        ref
            .read(gradesProvider.notifier)
            .fetchGradesWithStoredCredentials()
            .catchError((_) {}),
      );
    } else {
      final remaining = await _authService.recordPinFailure();
      if (!mounted) return;
      setState(() {
        _error = true;
        _remainingAttempts = remaining;
        _pinController.clear();
      });
      if (remaining == 0) await _refreshLockout();
    }
  }

  String? get _errorText {
    if (_lockout != null) {
      return 'Trop de tentatives. Réessayez dans ${_lockout!.inSeconds + 1} s.';
    }
    if (!_error) return null;
    if (_remainingAttempts != null && _remainingAttempts! > 0) {
      return 'Code PIN incorrect ($_remainingAttempts tentative(s) restante(s))';
    }
    return 'Code PIN incorrect';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.pin_outlined,
                size: 72,
                color: AppColors.primary,
              ),
              const SizedBox(height: 16),
              const Text(
                'Code PIN requis',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Entrez votre code PIN pour accéder à vos notes',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _pinController,
                enabled: _lockout == null,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                onChanged: (_) {
                  if (_error) setState(() => _error = false);
                },
                onSubmitted: (_) => _verify(),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  counterText: '',
                  errorText: _errorText,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _lockout == null ? _verify : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Valider', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
                child: const Text('Se connecter autrement'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _pinController.dispose();
    super.dispose();
  }
}
