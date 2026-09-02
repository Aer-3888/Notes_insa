import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_colors.dart';
import '../../modules/grades/grades_provider.dart';
import '../../modules/grades/onboarding/onboarding_screen.dart';

class LogoutProgressScreen extends StatelessWidget {
  const LogoutProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Déconnexion sécurisée en cours…'),
          ],
        ),
      ),
    );
  }
}

class LogoutFailedScreen extends StatelessWidget {
  const LogoutFailedScreen({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_outline,
                size: 56,
                color: AppColors.primary,
              ),
              const SizedBox(height: 20),
              const Text(
                'La déconnexion n’a pas pu être terminée.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Réessayez pour supprimer toutes les données locales avant de vous reconnecter.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
            ],
          ),
        ),
      ),
    );
  }
}

// Shown while credentials are being loaded from secure storage

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

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
              'Relevé',
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
class AuthenticatingSplash extends ConsumerStatefulWidget {
  const AuthenticatingSplash({super.key});

  @override
  ConsumerState<AuthenticatingSplash> createState() =>
      _AuthenticatingSplashState();
}

class _AuthenticatingSplashState extends ConsumerState<AuthenticatingSplash> {
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
                'Relevé',
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
                      MaterialPageRoute(
                        builder: (_) => const OnboardingScreen(),
                      ),
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
