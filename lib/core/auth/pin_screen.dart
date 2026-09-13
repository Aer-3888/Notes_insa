import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../modules/grades/grades_provider.dart';
import '../../modules/grades/onboarding/onboarding_screen.dart';
import '../../providers/auth_providers.dart';
import '../../services/auth_service.dart';

class PinScreen extends ConsumerStatefulWidget {
  const PinScreen({super.key});

  @override
  ConsumerState<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<PinScreen> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  final _authService = AuthService();
  bool _error = false;
  int? _remainingAttempts;
  Duration? _lockout;
  Timer? _lockoutTimer;

  // After a legacy (<6-digit) PIN is verified, switch to upgrade mode and
  // require the user to set a new, stronger PIN before unlocking.
  bool _upgradeMode = false;
  bool _upgradeError = false;

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
      // Legacy short PIN, require an upgrade before unlocking.
      if (await _authService.pinNeedsUpgrade()) {
        if (!mounted) return;
        setState(() {
          _upgradeMode = true;
          _error = false;
          _pinController.clear();
        });
        return;
      }
      _unlockAndFetch();
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

  void _unlockAndFetch() {
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

  Future<void> _submitUpgrade() async {
    final pin = _pinController.text.trim();
    final confirm = _confirmController.text.trim();
    if (pin.length < AuthService.minPinLength || pin != confirm) {
      setState(() => _upgradeError = true);
      return;
    }
    await _authService.setPin(pin);
    if (!mounted) return;
    _unlockAndFetch();
  }

  String? get _errorText {
    if (_lockout != null) {
      return 'Trop de tentatives. Réessayez dans ${_lockout!.inSeconds + 1} s.';
    }
    if (!_error) return null;
    if (_remainingAttempts != null && _remainingAttempts! > 0) {
      final n = _remainingAttempts!;
      final word = n == 1 ? 'tentative restante' : 'tentatives restantes';
      return 'Code PIN incorrect, $n $word';
    }
    return 'Code PIN incorrect';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _upgradeMode ? 'Renforcez votre code' : 'Code PIN requis',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _upgradeMode
                    ? 'Choisissez un nouveau code PIN de 6 chiffres minimum.'
                    : 'Entrez votre code PIN pour accéder à vos notes',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              if (_upgradeMode) ...[
                TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(letterSpacing: 8),
                  onChanged: (_) {
                    if (_upgradeError) setState(() => _upgradeError = false);
                  },
                  decoration: const InputDecoration(
                    labelText: 'Nouveau code PIN',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(letterSpacing: 8),
                  onChanged: (_) {
                    if (_upgradeError) setState(() => _upgradeError = false);
                  },
                  onSubmitted: (_) => _submitUpgrade(),
                  decoration: InputDecoration(
                    labelText: 'Confirmer le code PIN',
                    counterText: '',
                    errorText: _upgradeError
                        ? 'Les codes ne correspondent pas ou sont trop courts'
                        : null,
                  ),
                ),
              ] else
                TextField(
                  controller: _pinController,
                  enabled: _lockout == null,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(letterSpacing: 8),
                  onChanged: (_) {
                    if (_error) setState(() => _error = false);
                  },
                  onSubmitted: (_) => _verify(),
                  decoration: InputDecoration(
                    counterText: '',
                    errorText: _errorText,
                  ),
                ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _upgradeMode
                      ? _submitUpgrade
                      : (_lockout == null ? _verify : null),
                  child: const Text('Valider'),
                ),
              ),
              if (!_upgradeMode) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                  ),
                  child: const Text('Se connecter autrement'),
                ),
              ],
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
    _confirmController.dispose();
    super.dispose();
  }
}
