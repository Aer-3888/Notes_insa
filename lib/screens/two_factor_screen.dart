import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../components/two_factor_form.dart';
import '../providers/grades_provider.dart';
import '../providers/auth_providers.dart';
import '../services/auth_service.dart';
import '../services/grades_service.dart';
import 'scan_screen.dart';
import 'login_screen.dart';

class TwoFactorScreen extends ConsumerStatefulWidget {
  const TwoFactorScreen({super.key});

  @override
  ConsumerState<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends ConsumerState<TwoFactorScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;
  String? _errorText;
  String? _scannedSecret;

  Future<void> _validate() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });
    try {
      await GradesService.validate(_codeController.text.trim());
      await ref.read(gradesProvider.notifier).fetchGradesAfterAuth();
    } catch (e) {
      setState(() => _errorText = 'Code invalide ou expiré');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _triggerEmail() async {
    setState(() => _isLoading = true);
    try {
      await GradesService.triggerEmail();
      setState(() => _emailSent = true);
    } catch (e) {
      setState(() => _errorText = 'Erreur lors de l\'envoi de l\'email');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _scanQr() async {
    final secret = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (secret != null && mounted) {
      setState(() => _scannedSecret = secret);
    }
  }

  Future<void> _autoValidate(String secret) async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });
    try {
      await AuthService().storeOtpSecret(secret);
      await GradesService.autoValidate(secret);
      await ref.read(gradesProvider.notifier).fetchGradesAfterAuth();
    } catch (e) {
      setState(() => _errorText = 'Secret OTP invalide');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _logout() async {
    await AuthService().logout();
    ref.read(gradesProvider.notifier).clearGrades();
    ref.invalidate(hasCredentialsProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Double Authentification'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Déconnexion',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TwoFactorForm(
              controller: _codeController,
              isLoading: _isLoading,
              onValidate: _validate,
              onScanQr: _scanQr,
              errorText: _errorText,
              onTriggerEmail: _triggerEmail,
              emailSent: _emailSent,
              scannedSecret: _scannedSecret,
              onAutoValidate: _autoValidate,
              onToggleSaveSecret: (_) {}, // Always saved if using auto-validate here
              saveSecret: true,
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              ),
              child: const Text('Se connecter autrement'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }
}
