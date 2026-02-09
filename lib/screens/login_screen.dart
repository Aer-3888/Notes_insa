import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'scan_screen.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();

  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();

  String? _scannedToken;
  bool _isLoading = false;

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

    // Simulate a small delay (or real network check here)
    await Future.delayed(const Duration(milliseconds: 500));

    // Save everything securely
    await _authService.saveCredentials(
      token: _scannedToken!,
      username: _userController.text,
      password: _passController.text,
    );

    if (mounted) {
      // Go to Dashboard
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
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
              const SizedBox(height: 40),

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
                  child: Row(
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
                      Text(
                        _scannedToken != null
                            ? "Token Valide"
                            : "Scanner le QR Code",
                        style: TextStyle(
                          color: _scannedToken != null
                              ? Colors.green.shade700
                              : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Mot de passe",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
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
}
