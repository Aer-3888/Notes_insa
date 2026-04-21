import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_colors.dart';
import 'services/auth_service.dart';
import 'providers/grades_provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/two_factor_screen.dart';
import 'background_tasks.dart';
import 'constants.dart';

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

// Checks credentials only — pure read, no side effects
final _hasCredentialsProvider = FutureProvider<bool>((ref) async {
  return AuthService().isLoggedIn();
});

// Decides between splash → biometric screen → dashboard, or login.
// Loads stored grades as a side effect on first build, separately from the
// credential check so the provider stays pure.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  @override
  void initState() {
    super.initState();
    // Load cached grades into state once on app start — independent of auth
    ref.read(gradesProvider.notifier).loadStoredGrades();
  }

  @override
  Widget build(BuildContext context) {
    final gradesState = ref.watch(gradesProvider);

    return ref.watch(_hasCredentialsProvider).when(
      loading: () => const _SplashScreen(),
      error: (_, _) => const LoginScreen(),
      data: (hasCreds) {
        if (!hasCreds) return const LoginScreen();

        // Interceptor Logic
        switch (gradesState.authStatus) {
          case AuthStatus.unauthenticated:
          case AuthStatus.authenticating:
          case AuthStatus.error:
            return const _BiometricScreen();
          case AuthStatus.pinRequired:
            return const _PinScreen();
          case AuthStatus.twoFactorRequired:
            return const TwoFactorScreen();
          case AuthStatus.authenticated:
            return DashboardScreen(
              onReauthRequired: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              ),
            );
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
                      onPressed:
                          () =>
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

  Future<void> _verify() async {
    final success = await _authService.verifyPin(_pinController.text);
    if (success) {
      if (!mounted) return;
      unawaited(
        ref
            .read(gradesProvider.notifier)
            .fetchGradesWithStoredCredentials()
            .catchError((_) {}),
      );
    } else {
      setState(() {
        _error = true;
        _pinController.clear();
      });
    }
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
                  errorText: _error ? 'Code PIN incorrect' : null,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _verify,
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
    _pinController.dispose();
    super.dispose();
  }
}
