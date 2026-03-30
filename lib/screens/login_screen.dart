import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app_colors.dart';
import '../services/auth_service.dart';
import '../constants.dart';
import '../providers/grades_provider.dart';
import '../providers/settings_provider.dart';
import 'scan_screen.dart';
import 'dashboard_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final AuthService _authService = AuthService();

  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();

  String? _scannedToken;
  bool _isLoading = false;

  // Toggle for password visibility in the password text field
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _autoFillUsername();
  }

  // Auto-fill username from stored credentials if available
  Future<void> _autoFillUsername() async {
    final credentials = await _authService.getCredentials();
    if (credentials != null && credentials[kStorageUser] != null && mounted) {
      setState(() {
        _userController.text = credentials[kStorageUser]!;
      });
    }
  }

  // Scan QR Code to get Token
  Future<void> _scanToken() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );

    if (result != null) {
      setState(() {
        _scannedToken = result.toString();
      });
    }
  }

  // Save credentials and go to Dashboard
  Future<void> _handleLogin() async {
    if (_scannedToken == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Fetch grades via Riverpod provider (updates state automatically)
      await ref
          .read(gradesProvider.notifier)
          .fetchGrades(
            _userController.text,
            _passController.text,
            _scannedToken!,
          );

      // Only save credentials AFTER successful fetch
      await _authService.storeCredentials(
        _userController.text,
        _passController.text,
        token: _scannedToken!,
      );
      TextInput.finishAutofillContext();

      if (mounted) {
        final needsConsent = !ref.read(settingsProvider).sharingConsentAsked;
        // Go to Dashboard only on successful fetch
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => DashboardScreen(showConsentOnMount: needsConsent),
          ),
          (_) => false,
        );
      }
    } on PlatformException catch (e) {
      // Show error dialog and remain on the login screen
      if (mounted) {
        // Prepare error details for the dialog
        final errorDetails = StringBuffer();
        errorDetails.writeln('Code: ${e.code}');
        errorDetails.writeln('Message: ${e.message ?? "none"}');
        if (e.details != null) {
          errorDetails.writeln('Details: ${e.details}');
        }

        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Erreur de synchronisation'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.message ??
                        'Erreur inconnue lors de la récupération des notes.',
                  ),
                  const SizedBox(height: 16),
                  // Show technical details only in debug builds
                  if (kDebugMode) ...[
                    const Text(
                      'Détails techniques:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      errorDetails.toString(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
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
    } catch (e) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Erreur de synchronisation'),
            content: Text(
              kDebugMode ? e.toString() : 'Une erreur inattendue est survenue.',
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
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isReady =
        _scannedToken != null &&
        _userController.text.isNotEmpty &&
        _passController.text.isNotEmpty;

    final canGoBack = Navigator.canPop(context);

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
                    const Text(
                      'Connexion',
                      style: TextStyle(
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
          // White form section
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),

                    // Qr Code Scan Section
                    Text(
                      "Étape 1 : Token d'accès",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _scanToken,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _scannedToken != null
                              ? AppColors.statusPositive.withValues(alpha: 0.1)
                              : Colors.grey.shade100,
                          border: Border.all(
                            color: _scannedToken != null
                                ? AppColors.statusPositive
                                : Colors.grey.shade300,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _scannedToken != null
                                      ? Icons.check_circle
                                      : Icons.qr_code_scanner,
                                  color: _scannedToken != null
                                      ? AppColors.statusPositive
                                      : AppColors.primary,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    _scannedToken != null
                                        ? "Token Scanné"
                                        : "Scanner le QR Code",
                                    style: TextStyle(
                                      color: _scannedToken != null
                                          ? AppColors.statusPositive
                                          : Colors.black87,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_scannedToken != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Token enregistré',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),

                    // Form Section
                    Text(
                      "Étape 2 : Identifiants ENT",
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
                            controller: _userController,
                            onChanged: (_) => setState(() {}),
                            autofillHints: const [AutofillHints.username],
                            decoration: const InputDecoration(
                              labelText: "Nom d'utilisateur",
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _passController,
                            onChanged: (_) => setState(() {}),
                            obscureText: _obscurePassword,
                            autofillHints: const [AutofillHints.password],
                            decoration: InputDecoration(
                              labelText: "Mot de passe",
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                                tooltip: _obscurePassword
                                    ? 'Afficher le mot de passe'
                                    : 'Masquer le mot de passe',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Login Button
                    ElevatedButton(
                      onPressed: (isReady && !_isLoading) ? _handleLogin : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor: AppColors.primary.withValues(
                          alpha: .3,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              "Se connecter",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }
}
