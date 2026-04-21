import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../components/two_factor_form.dart';
import '../providers/grades_provider.dart';
import '../services/auth_service.dart';
import '../services/grades_service.dart';
import 'scan_screen.dart';

class TwoFactorScreen extends ConsumerStatefulWidget {
  const TwoFactorScreen({super.key});

  @override
  ConsumerState<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends ConsumerState<TwoFactorScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorText;

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

  Future<void> _scanQr() async {
    final secret = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (secret != null) {
      await AuthService().storeOtpSecret(secret);
      await _validate();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Double Authentification')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: TwoFactorForm(
          controller: _codeController,
          isLoading: _isLoading,
          onValidate: _validate,
          onScanQr: _scanQr,
          errorText: _errorText,
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
