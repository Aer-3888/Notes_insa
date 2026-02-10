import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/grades_service.dart';
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

  // Visibility toggles for credentials viewer
  bool _showStoredPassword = false;
  bool _showStoredSecret = false;

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

  // Copy to clipboard helper
  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copié'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Show currently entered credentials in a dialog
  void _showCurrentCredentialsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.visibility, color: Colors.indigo),
                SizedBox(width: 8),
                Text('Identifiants saisis'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Username
                  _buildDialogCredentialRow(
                    label: 'Nom d\'utilisateur',
                    value: _userController.text.isEmpty
                        ? 'Non saisi'
                        : _userController.text,
                    isVisible: true,
                    icon: Icons.person,
                    setDialogState: setDialogState,
                  ),
                  const Divider(height: 24),

                  // Password
                  _buildDialogCredentialRow(
                    label: 'Mot de passe',
                    value: _passController.text.isEmpty
                        ? 'Non saisi'
                        : _passController.text,
                    isVisible: _showStoredPassword,
                    icon: Icons.lock,
                    setDialogState: setDialogState,
                    onToggle: () {
                      setDialogState(() {
                        _showStoredPassword = !_showStoredPassword;
                      });
                    },
                  ),
                  const Divider(height: 24),

                  // OTP Secret
                  _buildDialogCredentialRow(
                    label: 'Secret OTP scanné (Base32)',
                    value: _scannedToken == null || _scannedToken!.isEmpty
                        ? 'Non scanné'
                        : _scannedToken!,
                    isVisible: _showStoredSecret,
                    icon: Icons.key,
                    setDialogState: setDialogState,
                    onToggle: () {
                      setDialogState(() {
                        _showStoredSecret = !_showStoredSecret;
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  // Reset visibility states
                  setState(() {
                    _showStoredPassword = false;
                    _showStoredSecret = false;
                  });
                },
                child: const Text('Fermer'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Build credential row for dialog
  Widget _buildDialogCredentialRow({
    required String label,
    required String value,
    required bool isVisible,
    required IconData icon,
    required StateSetter setDialogState,
    VoidCallback? onToggle,
  }) {
    final isEmpty = value.startsWith(
      'Non ',
    ); // 'Non saisi', 'Non scanné', 'Non défini'

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Colors.indigo),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (isEmpty)
          Text(
            value,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontStyle: FontStyle.italic,
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SelectableText(
                    isVisible
                        ? value
                        : '•' * (value.length > 20 ? 20 : value.length),
                    style: TextStyle(
                      fontFamily: isVisible ? 'monospace' : null,
                      fontSize: isVisible ? 12 : 14,
                    ),
                  ),
                ),
              ),
              if (onToggle != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onToggle,
                  icon: Icon(
                    isVisible ? Icons.visibility_off : Icons.visibility,
                    size: 20,
                  ),
                  tooltip: isVisible ? 'Masquer' : 'Afficher',
                ),
              ],
              IconButton(
                onPressed: () => _copyToClipboard(value, label),
                icon: const Icon(Icons.copy, size: 20),
                tooltip: 'Copier',
              ),
            ],
          ),
        if (!isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${value.length} caractères',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ),
      ],
    );
  }

  // Save credentials and go to Dashboard
  Future<void> _handleLogin() async {
    if (_scannedToken == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Attempt to fetch grades via native AAR (Android only)
      await GradesService.fetchGrades(
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

      if (mounted) {
        // Go to Dashboard only on successful fetch
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    } on PlatformException catch (e) {
      // Show error dialog and stay on login screen
      if (mounted) {
        // Build detailed error message for debugging
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

              // View Current Credentials Button
              TextButton.icon(
                onPressed: _showCurrentCredentialsDialog,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Voir les identifiants saisis'),
                style: TextButton.styleFrom(foregroundColor: Colors.indigo),
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
