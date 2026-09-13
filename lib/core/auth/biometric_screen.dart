import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../modules/grades/grades_provider.dart';
import '../../modules/grades/onboarding/onboarding_screen.dart';
import '../../providers/auth_providers.dart';
import '../../services/auth_service.dart';

class BiometricScreen extends ConsumerStatefulWidget {
  const BiometricScreen({super.key});

  @override
  ConsumerState<BiometricScreen> createState() => _BiometricScreenState();
}

class _BiometricScreenState extends ConsumerState<BiometricScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _failed = false;
  bool _authenticating = false;
  bool _hasPin = false;
  // True when _init() ran while backgrounded and auth must fire on next resume.
  bool _pendingAuth = false;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    _shakeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // If _init() ran while backgrounded, fire the deferred biometric prompt
    // now that the activity is back in the foreground and onResume() has run.
    if (state == AppLifecycleState.resumed && _pendingAuth && mounted) {
      _pendingAuth = false;
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) unawaited(_authenticate());
      });
    }
  }

  Future<void> _init() async {
    final authService = AuthService();
    final hasPin = await authService.hasPin();
    if (mounted) setState(() => _hasPin = hasPin);

    // If the app is backgrounded (paused/hidden), BiometricPrompt cannot be
    // shown, the FragmentManager has already saved state and any attempt
    // throws "Called after onSaveInstanceState". Defer to the next resume.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      _pendingAuth = true;
      return;
    }

    // Requesting the prompt on the very first frame can race with the Android
    // activity's resume transition, a brief delay lets onResume() settle.
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
      if (!MediaQuery.disableAnimationsOf(context)) {
        unawaited(_shakeController.forward(from: 0.0));
      }
    }
  }

  void _onSuccess() {
    ref.read(gradesUnlockedProvider.notifier).state = true;
    // The lock is a pushed route, so it dismisses itself rather than waiting
    // for a parent to swap its body.
    if (mounted && Navigator.canPop(context)) Navigator.of(context).pop();
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
                child: _failed
                    ? Icon(
                        Icons.fingerprint,
                        size: 48,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 16),
              Text(
                _failed ? 'Authentification échouée' : 'Campus INSA',
                style: _failed
                    ? Theme.of(context).textTheme.titleLarge
                    : Theme.of(context).textTheme.headlineMedium,
              ),
              if (_failed) ...[
                const SizedBox(height: 8),
                Text(
                  'La vérification biométrique a été annulée ou a échoué.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Réessayer'),
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
