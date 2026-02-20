import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';
import '../providers/grades_provider.dart';
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
    if (credentials != null && credentials['username'] != null && mounted) {
      setState(() {
        _userController.text = credentials['username']!;
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
      await _authService.saveCredentials(
        token: _scannedToken!,
        username: _userController.text,
        password: _passController.text,
      );

      // Also store credentials for background tasks
      await _authService.storeCredentials(
        _userController.text,
        _passController.text,
        token: _scannedToken!,
      );

      if (mounted) {
        // Go to Dashboard only on successful fetch
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
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

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              const Icon(Icons.school, size: 80, color: Colors.indigo),
              const SizedBox(height: 24),
              const Text(
                "Connexion",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),

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
                        ? Colors.green.shade50
                        : Colors.grey.shade100,
                    border: Border.all(
                      color: _scannedToken != null
                          ? Colors.green
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
                                ? Colors.green
                                : Colors.indigo,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              _scannedToken != null
                                  ? "Token Scanné"
                                  : "Scanner le QR Code",
                              style: TextStyle(
                                color: _scannedToken != null
                                    ? Colors.green.shade700
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
                          'Secret: ${_scannedToken!.substring(0, _scannedToken!.length > 16 ? 16 : _scannedToken!.length)}... (${_scannedToken!.length} chars)',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontFamily: 'monospace',
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
              TextField(
                controller: _userController,
                onChanged: (_) => setState(() {}),
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

              const SizedBox(height: 40),

              // Login Button
              ElevatedButton(
                onPressed: (isReady && !_isLoading) ? _handleLogin : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: Colors.indigo,
                  disabledBackgroundColor: Colors.indigo.withValues(alpha: .3),
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
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
              ),
            ],
          ),
        ),
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
