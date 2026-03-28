import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../utils/google_auth_migration_decoder.dart';
import '../utils/base32_codec.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _isScanned = false;

  void _onDetect(BarcodeCapture capture) {
    if (_isScanned) return;

    for (final barcode in capture.barcodes) {
      if (barcode.rawValue == null) continue;

      setState(() => _isScanned = true);

      final result = _extractSecretFromQR(barcode.rawValue!);

      if (result == null) {
        _showError('QR non reconnu. Scannez un code OTP valide.');
        setState(() => _isScanned = false);
      } else if (result.isNotEmpty && mounted) {
        Navigator.pop(context, result);
      }
      break;
    }
  }

  /// Returns the base32 secret, empty string when async (account picker),
  /// or null when the QR is invalid/unrecognized.
  String? _extractSecretFromQR(String rawValue) {
    try {
      final uri = Uri.parse(rawValue);

      // Google Authenticator migration export
      if (uri.scheme == 'otpauth-migration') {
        try {
          final accounts = GoogleAuthMigrationDecoder.decode(rawValue);
          if (accounts.isEmpty) return null;
          if (accounts.length > 1) {
            _showAccountSelectionDialog(accounts);
            return '';
          }
          return accounts[0].secret;
        } catch (_) {
          return null;
        }
      }

      // Standard otpauth URI (totp/hotp) from any authenticator app
      if (uri.scheme == 'otpauth' &&
          uri.queryParameters.containsKey('secret')) {
        final secret = uri.queryParameters['secret']!;
        return Base32Codec.isValid(secret) ? secret : null;
      }

      // Any URI that carries a secret param
      if (uri.queryParameters.containsKey('secret')) {
        final secret = uri.queryParameters['secret']!;
        return Base32Codec.isValid(secret) ? secret : null;
      }

      // Raw base32 secret (some services show these directly)
      if (Base32Codec.isValid(rawValue)) return rawValue;

      return null;
    } catch (_) {
      // Not a URI — check if it's a raw base32 secret
      if (Base32Codec.isValid(rawValue)) return rawValue;
      return null;
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  void _showAccountSelectionDialog(List<OtpAccount> accounts) {
    if (!mounted) return;

    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sélectionner un compte'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: accounts
              .map(
                (account) => ListTile(
                  leading: const Icon(Icons.key),
                  title: Text(account.name),
                  subtitle: Text(account.issuer),
                  onTap: () => Navigator.pop(ctx, account.secret),
                ),
              )
              .toList(),
        ),
      ),
    ).then((selectedSecret) {
      if (!mounted) return;
      if (selectedSecret != null) {
        Navigator.pop(context, selectedSecret);
      } else {
        setState(() => _isScanned = false);
      }
    });
  }

  void _showManualEntryDialog() {
    final controller = TextEditingController();

    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Saisir le secret manuellement'),
        content: TextField(
          controller: controller,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: 'Secret base32 (ex: JBSWY3DPEHPK3PXP)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              final value = controller.text.trim().toUpperCase();
              if (Base32Codec.isValid(value)) {
                Navigator.pop(ctx, value);
              } else {
                _showError('Secret invalide. Vérifiez le format base32.');
              }
            },
            child: const Text('Confirmer'),
          ),
        ],
      ),
    ).then((secret) {
      if (!mounted || secret == null) return;
      Navigator.pop(context, secret);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner le Token'),
        actions: [
          TextButton(
            onPressed: _showManualEntryDialog,
            child: const Text('Saisir manuellement'),
          ),
        ],
      ),
      body: MobileScanner(onDetect: _onDetect),
    );
  }
}
