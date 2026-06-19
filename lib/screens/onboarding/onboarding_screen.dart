import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../constants.dart';
import '../../providers/auth_providers.dart';
import '../../providers/grades_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/auth_service.dart';
import '../../services/grades_service.dart';
import '../../services/notification_service.dart';
import '../scan_screen.dart';
import 'onboarding_enums.dart';
import 'slides/credentials_slide.dart';
import 'slides/manual_code_slide.dart';
import 'slides/notifications_slide.dart';
import 'slides/participation_slide.dart';
import 'slides/pin_setup_slide.dart';
import 'slides/totp_scan_slide.dart';
import 'slides/two_factor_choice_slide.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  final _authService = AuthService();

  List<OnboardingStep> _steps = [OnboardingStep.credentials];
  int _currentIndex = 0;
  bool _isLoading = false;
  String? _error;

  final _userController = TextEditingController();
  final _passController = TextEditingController();

  TfaMethod? _selectedMethod;
  TfaMethod? _chosenMethod;
  bool _emailSent = false;
  final _codeController = TextEditingController();
  String? _scannedSecret;
  bool _saveOtpSecret = true;
  // Server-side 2FA validation can't be replayed: once the session is
  // validated, re-submitting a code/secret is rejected. This tracks that we've
  // already succeeded so revisiting the step just advances instead of failing.
  bool _twoFactorValidated = false;

  @override
  void initState() {
    super.initState();
    _prefillUsername();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _userController.dispose();
    _passController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _prefillUsername() async {
    final creds = await _authService.getCredentials();
    if (creds != null && mounted) {
      setState(() => _userController.text = creds[kStorageUser]!);
    }
  }

  void _advance() {
    if (_currentIndex >= _steps.length - 1) return;
    setState(() {
      _currentIndex++;
      _error = null;
    });
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _goBack() {
    if (_currentIndex <= 0) return;
    setState(() {
      _currentIndex--;
      _error = null;
    });
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // ─── Credentials ────────────────────────────────────────────────────────────

  Future<void> _handleConnect() async {
    final username = _userController.text.trim();
    final password = _passController.text;
    if (username.isEmpty || password.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
      // A new authentication starts a new session that needs fresh 2FA.
      _twoFactorValidated = false;
    });
    try {
      await GradesService.newCAS();
      await GradesService.auth(username, password);

      bool needs2fa = await GradesService.isTokenNeeded();
      if (needs2fa) {
        final storedSecret = await _authService.getOtpSecret();
        if (storedSecret != null) {
          try {
            await GradesService.autoValidate(storedSecret);
            needs2fa = false;
          } catch (_) {
            await _authService.deleteOtpSecret();
          }
        }
      }

      await _buildStepsAndAdvance(needs2fa: needs2fa);
    } on PlatformException catch (_) {
      setState(() => _error = 'Erreur d\'authentification');
    } catch (e) {
      setState(
        () => _error = kDebugMode
            ? e.toString()
            : 'Une erreur inattendue est survenue.',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _buildStepsAndAdvance({required bool needs2fa}) async {
    final hasBiometrics = await _authService.hasBiometrics();
    final hasPin = await _authService.hasPin();
    final settings = ref.read(settingsProvider);
    final notifGranted = await Permission.notification.isGranted;

    final remaining = <OnboardingStep>[
      if (needs2fa) ...[
        OnboardingStep.twoFactorChoice,
        OnboardingStep.twoFactorExecution,
      ],
      if (!hasBiometrics && !hasPin) OnboardingStep.pinSetup,
      if (!settings.sharingConsentAsked) OnboardingStep.participation,
      if (!notifGranted) OnboardingStep.notifications,
    ];

    if (remaining.isEmpty) {
      await _completeOnboarding();
      return;
    }

    setState(() {
      _steps = [OnboardingStep.credentials, ...remaining];
      _error = null;
    });
    _advance();
  }

  // ─── 2FA choice ─────────────────────────────────────────────────────────────

  void _handleMethodChoice() {
    if (_selectedMethod == null) return;
    setState(() {
      _chosenMethod = _selectedMethod;
      _error = null;
    });
    _advance();
  }

  // ─── Manual code ─────────────────────────────────────────────────────────────

  Future<void> _handleTriggerEmail() async {
    setState(() => _isLoading = true);
    try {
      await GradesService.triggerEmail();
      if (mounted) setState(() => _emailSent = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleEmailValidate() async {
    // Already validated on a previous visit: don't replay the server call.
    if (_twoFactorValidated) {
      _advance();
      return;
    }
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await GradesService.validate(code);
      _twoFactorValidated = true;
      _advance();
    } on PlatformException catch (_) {
      setState(() => _error = 'Code invalide ou expiré');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── TOTP ────────────────────────────────────────────────────────────────────

  Future<void> _scanQr() async {
    final secret = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (secret != null && mounted) setState(() => _scannedSecret = secret);
  }

  Future<void> _handleTotpValidate() async {
    if (_scannedSecret == null) return;
    // Already validated on a previous visit: don't replay the server call.
    if (_twoFactorValidated) {
      _advance();
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await GradesService.autoValidate(_scannedSecret!);
      if (_saveOtpSecret) await _authService.storeOtpSecret(_scannedSecret!);
      _twoFactorValidated = true;
      _advance();
    } on PlatformException catch (_) {
      setState(() => _error = 'Secret OTP invalide');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── PIN ─────────────────────────────────────────────────────────────────────

  Future<void> _handleSetPin(String pin) async {
    await _authService.setPin(pin);
    _advance();
  }

  // ─── Participation ───────────────────────────────────────────────────────────

  void _handleParticipation(bool consent) {
    ref.read(settingsProvider.notifier).setSharingConsent(consent);
    ref.read(settingsProvider.notifier).markConsentAsked();
    _advance();
  }

  // ─── Notifications ───────────────────────────────────────────────────────────

  Future<void> _handleEnableNotifications() async {
    await NotificationService.requestPermission();
    await _completeOnboarding();
  }

  // ─── Completion ──────────────────────────────────────────────────────────────

  Future<void> _completeOnboarding() async {
    await _authService.storeCredentials(
      _userController.text.trim(),
      _passController.text,
    );
    ref.read(appUnlockedProvider.notifier).state = true;
    ref.invalidate(hasCredentialsProvider);
    unawaited(
      ref
          .read(gradesProvider.notifier)
          .fetchGradesAfterAuth()
          .catchError((_) {}),
    );
    TextInput.finishAutofillContext();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: PageView.builder(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _steps.length,
            itemBuilder: (_, i) => _buildSlide(_steps[i]),
          ),
        ),
      ),
    );
  }

  Widget _buildSlide(OnboardingStep step) {
    final onBack = _currentIndex > 0 ? _goBack : null;
    final count = _steps.length;
    final idx = _currentIndex;

    return switch (step) {
      OnboardingStep.credentials => CredentialsSlide(
        userController: _userController,
        passController: _passController,
        onConnect: _handleConnect,
        isLoading: _isLoading,
        error: _error,
        stepCount: count,
        currentIndex: idx,
      ),
      OnboardingStep.twoFactorChoice => TwoFactorChoiceSlide(
        selectedMethod: _selectedMethod,
        onSelect: (m) => setState(() => _selectedMethod = m),
        onContinue: _selectedMethod != null ? _handleMethodChoice : null,
        isLoading: _isLoading,
        error: _error,
        stepCount: count,
        currentIndex: idx,
        onBack: onBack,
      ),
      OnboardingStep.twoFactorExecution =>
        _chosenMethod == TfaMethod.manual
            ? ManualCodeSlide(
                codeController: _codeController,
                emailSent: _emailSent,
                onTriggerEmail: _handleTriggerEmail,
                onValidate: _handleEmailValidate,
                isLoading: _isLoading,
                error: _error,
                stepCount: count,
                currentIndex: idx,
                onBack: onBack,
              )
            : TotpScanSlide(
                scannedSecret: _scannedSecret,
                saveOtpSecret: _saveOtpSecret,
                onScan: _scanQr,
                onToggleSave: (v) => setState(() => _saveOtpSecret = v),
                onValidate: _handleTotpValidate,
                isLoading: _isLoading,
                error: _error,
                stepCount: count,
                currentIndex: idx,
                onBack: onBack,
              ),
      OnboardingStep.pinSetup => PinSetupSlide(
        onSetPin: _handleSetPin,
        onSkip: _advance,
        isLoading: _isLoading,
        error: _error,
        stepCount: count,
        currentIndex: idx,
        onBack: onBack,
      ),
      OnboardingStep.participation => ParticipationSlide(
        onAccept: () => _handleParticipation(true),
        onDecline: () => _handleParticipation(false),
        stepCount: count,
        currentIndex: idx,
        onBack: onBack,
      ),
      OnboardingStep.notifications => NotificationsSlide(
        onEnable: _handleEnableNotifications,
        onSkip: _completeOnboarding,
        stepCount: count,
        currentIndex: idx,
        onBack: onBack,
      ),
    };
  }
}
