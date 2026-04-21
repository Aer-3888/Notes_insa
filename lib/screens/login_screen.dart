import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app_colors.dart';
import '../services/auth_service.dart';
import '../services/grades_service.dart';
import '../constants.dart';
import '../providers/grades_provider.dart';
import 'scan_screen.dart';
import 'dashboard_screen.dart';

enum _Step { credentials, twoFactor, setPin }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final AuthService _authService = AuthService();

  final _userController = TextEditingController();
  final _passController = TextEditingController();
  final _codeController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  _Step _step = _Step.credentials;
  bool _isLoading = false;
  bool _obscurePassword = true;

  // 2FA state
  bool _emailSent = false;
  bool _saveSecret = false;
  String? _scannedSecret;

  @override
  void initState() {
    super.initState();
    _autoFillUsername();
  }

  Future<void> _autoFillUsername() async {
    final credentials = await _authService.getCredentials();
    if (credentials != null && mounted) {
      setState(() => _userController.text = credentials[kStorageUser]!);
    }
  }

  // -------------------------------------------------------------------------
  // Step 1: authenticate with username + password
  // -------------------------------------------------------------------------

  Future<void> _handleConnect() async {
    setState(() => _isLoading = true);
    try {
      await GradesService.newCAS();
      await GradesService.auth(
        _userController.text.trim(),
        _passController.text,
      );
      final needs2fa = await GradesService.isTokenNeeded();

      if (!needs2fa) {
        // No 2FA — go straight to PIN check / completion
        await _checkPinAndComplete();
        return;
      }

      // Check if we already have a stored secret — auto-validate silently
      final storedSecret = await _authService.getOtpSecret();
      if (storedSecret != null) {
        try {
          await GradesService.autoValidate(storedSecret);
          await _checkPinAndComplete();
          return;
        } catch (_) {
          // Stored secret failed (e.g. expired) — fall through to manual 2FA
          await _authService.deleteOtpSecret();
        }
      }

      // Show 2FA step
      if (mounted) setState(() => _step = _Step.twoFactor);
    } on PlatformException catch (e) {
      await _showError(e.message ?? 'Erreur d\'authentification', e);
    } catch (e) {
      await _showError(
        kDebugMode ? e.toString() : 'Une erreur inattendue est survenue.',
        null,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // -------------------------------------------------------------------------
  // Step 2a: send email code
  // -------------------------------------------------------------------------

  Future<void> _handleTriggerEmail() async {
    setState(() => _isLoading = true);
    try {
      await GradesService.triggerEmail();
      if (mounted) setState(() => _emailSent = true);
    } on PlatformException catch (e) {
      await _showError(e.message ?? 'Erreur lors de l\'envoi de l\'email', e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // -------------------------------------------------------------------------
  // Step 2b: validate code (typed manually or from email)
  // -------------------------------------------------------------------------

  Future<void> _handleValidateCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      await GradesService.validate(code);
      // If user opted to save the scanned secret, store it now
      if (_saveSecret && _scannedSecret != null) {
        await _authService.storeOtpSecret(_scannedSecret!);
      }
      await _checkPinAndComplete();
    } on PlatformException catch (e) {
      await _showError(e.message ?? 'Code invalide', e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // -------------------------------------------------------------------------
  // Step 2c: auto-validate with scanned secret
  // -------------------------------------------------------------------------

  Future<void> _handleAutoValidateWithSecret(String secret) async {
    setState(() => _isLoading = true);
    try {
      await GradesService.autoValidate(secret);
      if (_saveSecret) await _authService.storeOtpSecret(secret);
      await _checkPinAndComplete();
    } on PlatformException catch (e) {
      await _showError(e.message ?? 'Secret invalide', e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // -------------------------------------------------------------------------
  // Step 3: check for PIN and complete
  // -------------------------------------------------------------------------

  Future<void> _checkPinAndComplete() async {
    final hasPinSet = await _authService.hasPin();
    final hasBiometrics = await _authService.hasBiometrics();
    if (hasPinSet || hasBiometrics) {
      await _completeLogin();
    } else {
      if (mounted) setState(() => _step = _Step.setPin);
    }
  }

  Future<void> _handleSetPin() async {
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();
    if (pin.length < 4 || pin != confirmPin) return;
    await _authService.setPin(pin);
    await _completeLogin();
  }

  // -------------------------------------------------------------------------
  // Scan QR code for OTP secret
  // -------------------------------------------------------------------------

  Future<void> _scanSecret() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (result != null && mounted) {
      setState(() => _scannedSecret = result);
    }
  }

  // -------------------------------------------------------------------------
  // Final step: fetch grades and navigate to dashboard
  // -------------------------------------------------------------------------

  Future<void> _completeLogin() async {
    // Save credentials (only after successful auth)
    await _authService.storeCredentials(
      _userController.text.trim(),
      _passController.text,
    );

    // Fetch grades — updates provider state; non-blocking so login completes
    // even when the grades endpoint fails (can be retried from dashboard).
    unawaited(
      ref
          .read(gradesProvider.notifier)
          .fetchGradesAfterAuth()
          .catchError((_) {}),
    );

    // Signal success to the autofill manager only after everything succeeded,
    // so the password manager doesn't offer to save credentials from a failed session.
    TextInput.finishAutofillContext();

    if (mounted) {
      unawaited(
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (ctx) => DashboardScreen(
              onReauthRequired: () => Navigator.of(
                ctx,
              ).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
            ),
          ),
          (_) => false,
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Error dialog
  // -------------------------------------------------------------------------

  Future<void> _showError(String message, PlatformException? e) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erreur'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              if (kDebugMode && e != null) ...[
                const SizedBox(height: 16),
                const Text(
                  'Détails techniques:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Code: ${e.code}\nMessage: ${e.message ?? "none"}',
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final canGoBack = Navigator.canPop(context);

    String title = 'Connexion';
    if (_step == _Step.twoFactor) title = 'Sécurité';
    if (_step == _Step.setPin) title = 'Sécurisez l\'accès';

    return Scaffold(
      body: Column(
        children: [
          // Gradient header
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: AppColors.headerGradient,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (canGoBack)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          tooltip: 'Retour',
                        ),
                      )
                    else
                      const SizedBox(height: 16),
                    const Icon(Icons.school, size: 64, color: Colors.white),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ),

          // Form section
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: _buildForm(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    switch (_step) {
      case _Step.credentials:
        return _CredentialsForm(
          userController: _userController,
          passController: _passController,
          obscurePassword: _obscurePassword,
          isLoading: _isLoading,
          onToggleObscure: () =>
              setState(() => _obscurePassword = !_obscurePassword),
          onChanged: () => setState(() {}),
          onConnect: _handleConnect,
        );
      case _Step.twoFactor:
        return _TwoFactorForm(
          codeController: _codeController,
          isLoading: _isLoading,
          emailSent: _emailSent,
          saveSecret: _saveSecret,
          scannedSecret: _scannedSecret,
          onTriggerEmail: _handleTriggerEmail,
          onValidateCode: _handleValidateCode,
          onScanSecret: _scanSecret,
          onAutoValidate: _handleAutoValidateWithSecret,
          onToggleSaveSecret: (v) => setState(() => _saveSecret = v),
          onCodeChanged: () => setState(() {}),
        );
      case _Step.setPin:
        return _SetPinForm(
          pinController: _pinController,
          confirmPinController: _confirmPinController,
          onSetPin: _handleSetPin,
          onPinChanged: () => setState(() {}),
        );
    }
  }

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    _codeController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }
}

// =============================================================================
// Step 3 widget — Set PIN
// =============================================================================

class _SetPinForm extends StatelessWidget {
  final TextEditingController pinController;
  final TextEditingController confirmPinController;
  final VoidCallback onSetPin;
  final VoidCallback onPinChanged;

  const _SetPinForm({
    required this.pinController,
    required this.confirmPinController,
    required this.onSetPin,
    required this.onPinChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pinReady =
        pinController.text.length >= 4 &&
        pinController.text == confirmPinController.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.pin_outlined, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Définir un code PIN',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    'Utilisé si la biométrie est indisponible',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        TextField(
          controller: pinController,
          onChanged: (_) => onPinChanged(),
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 8,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 8),
          decoration: const InputDecoration(
            labelText: 'Nouveau code PIN',
            border: OutlineInputBorder(),
            counterText: '',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: confirmPinController,
          onChanged: (_) => onPinChanged(),
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 8,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 8),
          decoration: InputDecoration(
            labelText: 'Confirmer le code PIN',
            border: const OutlineInputBorder(),
            counterText: '',
            errorText:
                (confirmPinController.text.isNotEmpty &&
                    confirmPinController.text != pinController.text)
                ? 'Les codes ne correspondent pas'
                : null,
          ),
        ),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: pinReady ? onSetPin : null,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(16),
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            'Confirmer le code PIN',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Step 1 widget — credentials
// =============================================================================

class _CredentialsForm extends StatelessWidget {
  final TextEditingController userController;
  final TextEditingController passController;
  final bool obscurePassword;
  final bool isLoading;
  final VoidCallback onToggleObscure;
  final VoidCallback onChanged;
  final VoidCallback onConnect;

  const _CredentialsForm({
    required this.userController,
    required this.passController,
    required this.obscurePassword,
    required this.isLoading,
    required this.onToggleObscure,
    required this.onChanged,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final isReady =
        userController.text.isNotEmpty && passController.text.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          'Identifiants ENT',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        AutofillGroup(
          child: Column(
            children: [
              TextField(
                controller: userController,
                onChanged: (_) => onChanged(),
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(
                  labelText: "Nom d'utilisateur",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passController,
                onChanged: (_) => onChanged(),
                obscureText: obscurePassword,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: onToggleObscure,
                    tooltip: obscurePassword
                        ? 'Afficher le mot de passe'
                        : 'Masquer le mot de passe',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: (isReady && !isLoading) ? onConnect : null,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(16),
            backgroundColor: AppColors.primary,
            disabledBackgroundColor: AppColors.primary.withOpacity(.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text(
                  'Se connecter',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
        ),
      ],
    );
  }
}

// =============================================================================
// Step 2 widget — 2FA
// =============================================================================

class _TwoFactorForm extends StatelessWidget {
  final TextEditingController codeController;
  final bool isLoading;
  final bool emailSent;
  final bool saveSecret;
  final String? scannedSecret;
  final VoidCallback onTriggerEmail;
  final VoidCallback onValidateCode;
  final VoidCallback onScanSecret;
  final ValueChanged<String> onAutoValidate;
  final ValueChanged<bool> onToggleSaveSecret;
  final VoidCallback onCodeChanged;

  const _TwoFactorForm({
    required this.codeController,
    required this.isLoading,
    required this.emailSent,
    required this.saveSecret,
    required this.scannedSecret,
    required this.onTriggerEmail,
    required this.onValidateCode,
    required this.onScanSecret,
    required this.onAutoValidate,
    required this.onToggleSaveSecret,
    required this.onCodeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final codeReady = codeController.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),

        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.security, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vérification en deux étapes',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    'Un code est requis pour continuer',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Option A: email
        OutlinedButton.icon(
          onPressed: (isLoading || emailSent) ? null : onTriggerEmail,
          icon: Icon(emailSent ? Icons.check_circle : Icons.email_outlined),
          label: Text(
            emailSent ? 'Email envoyé' : 'Recevoir un code par email',
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.all(14),
            foregroundColor: emailSent
                ? AppColors.statusPositive
                : AppColors.primary,
            side: BorderSide(
              color: emailSent ? AppColors.statusPositive : AppColors.primary,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Code input
        TextField(
          controller: codeController,
          onChanged: (_) => onCodeChanged(),
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: const InputDecoration(
            labelText: 'Code de vérification',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.pin_outlined),
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),

        // Validate code button
        ElevatedButton(
          onPressed: (codeReady && !isLoading) ? onValidateCode : null,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(16),
            backgroundColor: AppColors.primary,
            disabledBackgroundColor: AppColors.primary.withOpacity(.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text(
                  'Valider',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
        ),

        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('ou', style: TextStyle(color: Colors.grey)),
              ),
              Expanded(child: Divider()),
            ],
          ),
        ),

        // Option B: QR code scan for OTP secret
        Text(
          'Secret OTP (optionnel)',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Scannez le QR code 2FA pour valider automatiquement et éviter de ressaisir un code à chaque connexion.',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        ),
        const SizedBox(height: 10),

        GestureDetector(
          onTap: isLoading ? null : onScanSecret,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scannedSecret != null
                  ? AppColors.statusPositive.withOpacity(.1)
                  : Colors.grey.shade100,
              border: Border.all(
                color: scannedSecret != null
                    ? AppColors.statusPositive
                    : Colors.grey.shade300,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  scannedSecret != null
                      ? Icons.check_circle
                      : Icons.qr_code_scanner,
                  color: scannedSecret != null
                      ? AppColors.statusPositive
                      : AppColors.primary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    scannedSecret != null
                        ? 'Secret scanné'
                        : 'Scanner le QR code',
                    style: TextStyle(
                      color: scannedSecret != null
                          ? AppColors.statusPositive
                          : Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Save secret checkbox
        const SizedBox(height: 8),
        CheckboxListTile(
          value: saveSecret,
          onChanged: (v) => onToggleSaveSecret(v ?? false),
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Mémoriser le secret pour les prochaines connexions',
            style: TextStyle(fontSize: 13),
          ),
          subtitle: const Text(
            'Nécessaire pour la mise à jour automatique en arrière-plan.',
            style: TextStyle(fontSize: 11),
          ),
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: AppColors.primary,
        ),

        const SizedBox(height: 8),

        // Auto-validate button (only shown when secret is scanned)
        if (scannedSecret != null)
          ElevatedButton.icon(
            onPressed: isLoading ? null : () => onAutoValidate(scannedSecret!),
            icon: const Icon(Icons.auto_fix_high, color: Colors.white),
            label: const Text(
              'Valider automatiquement',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
              backgroundColor: AppColors.statusPositive,
              disabledBackgroundColor: AppColors.statusPositive.withOpacity(.3,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
      ],
    );
  }
}
