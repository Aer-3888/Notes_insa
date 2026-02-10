import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../utils/google_auth_migration_decoder.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _isScanned = false; // Prevent scanning the same code twice rapidly

  void _onDetect(BarcodeCapture capture) {
    if (_isScanned) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        setState(() {
          _isScanned = true;
        });

        // Extract the secret from OTP URI (e.g., otpauth://totp/...?secret=BASE32SECRET)
        String secret = _extractSecretFromQR(barcode.rawValue!);

        // Close the screen and return the extracted secret
        Navigator.pop(context, secret);
        break;
      }
    }
  }

  /// Extracts the base32 secret from an OTP QR code URI.
  /// Handles both standard OTP URIs and Google Authenticator migration URIs.
  String _extractSecretFromQR(String rawValue) {
    try {
      // Try to parse as URI
      final uri = Uri.parse(rawValue);

      // Check if it's a Google Authenticator migration URI
      if (uri.scheme == 'otpauth-migration') {
        try {
          final accounts = GoogleAuthMigrationDecoder.decode(rawValue);

          if (accounts.isEmpty) {
            return rawValue; // Fallback to raw value
          }

          // If multiple accounts, show a dialog to select
          if (accounts.length > 1) {
            _showAccountSelectionDialog(accounts);
            return accounts[0].secret;
          }

          // Single account - return the secret
          final secret = accounts[0].secret;
          return secret;
        } catch (e) {
          // Show error to user
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Erreur de décodage: $e')));
          }
          return ''; // Return empty to prevent proceeding
        }
      }

      // Check if it's a standard OTP auth URI
      if (uri.scheme == 'otpauth' &&
          uri.queryParameters.containsKey('secret')) {
        final secret = uri.queryParameters['secret']!;
        return secret;
      }

      // If not an OTP URI, check if query params exist anyway
      if (uri.queryParameters.containsKey('secret')) {
        final secret = uri.queryParameters['secret']!;
        return secret;
      }

      // Otherwise return raw value (might already be the secret)
      return rawValue;
    } catch (e) {
      // If parsing fails, return raw value
      return rawValue;
    }
  }

  /// Show dialog to select from multiple OTP accounts
  void _showAccountSelectionDialog(List<OtpAccount> accounts) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sélectionner un compte'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: accounts.map((account) {
            return ListTile(
              leading: const Icon(Icons.key),
              title: Text(account.name),
              subtitle: Text(account.issuer),
              onTap: () {
                Navigator.pop(ctx, account.secret);
              },
            );
          }).toList(),
        ),
      ),
    ).then((selectedSecret) {
      if (selectedSecret != null) {
        Navigator.pop(context, selectedSecret);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scanner le Token")),
      body: MobileScanner(onDetect: _onDetect),
    );
  }
}
