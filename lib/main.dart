import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/auth_service.dart';
import 'providers/grades_provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'background_tasks.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF0F2F5),
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
    return ref
        .watch(_hasCredentialsProvider)
        .when(
          loading: () => const _SplashScreen(),
          error: (_, _) => const LoginScreen(),
          data: (hasCreds) =>
              hasCreds ? const _BiometricScreen() : const LoginScreen(),
        );
  }
}

// Shown while credentials are being loaded from secure storage
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF0F2F5),
      body: Align(
        alignment: Alignment(0, -0.65),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school, size: 72, color: Color(0xFF3949AB)),
            SizedBox(height: 16),
            Text(
              'Notes INSA',
              style: TextStyle(
                color: Color(0xFF3949AB),
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() {
      _failed = false;
      _authenticating = true;
    });

    final success = await AuthService().authenticate();
    if (!mounted) return;

    if (success) {
      setState(() => _authenticating = false);
      unawaited(
        ref
            .read(gradesProvider.notifier)
            .fetchGradesWithStoredCredentials()
            .catchError((_) {}),
      );
      _replaceWith(const DashboardScreen());
    } else {
      setState(() {
        _failed = true;
        _authenticating = false;
      });
      _shakeController.forward(from: 0.0);
    }
  }

  void _replaceWith(Widget screen) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => screen),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
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
                  color: _failed
                      ? Colors.grey.shade400
                      : const Color(0xFF3949AB),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _failed ? 'Authentification échouée' : 'Notes INSA',
                style: TextStyle(
                  fontSize: _failed ? 20 : 24,
                  fontWeight: FontWeight.bold,
                  color: _failed
                      ? Colors.grey.shade700
                      : const Color(0xFF3949AB),
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
                      backgroundColor: const Color(0xFF3949AB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _authenticate,
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
