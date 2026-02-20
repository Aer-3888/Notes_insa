import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../utils/google_auth_migration_decoder.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  // Prevent processing the same barcode multiple times while handling a detection
  bool _isScanned = false;

  void _onDetect(BarcodeCapture capture) {
    if (_isScanned) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        setState(() {
          _isScanned = true;
        });

        // Parse the scanned value and attempt to extract the OTP secret
        String secret = _extractSecretFromQR(barcode.rawValue!);

        // Only close and return a secret when one was extracted immediately.
        // If multiple accounts are found, the selection dialog will handle
        // returning the chosen secret asynchronously.
        if (secret.isNotEmpty && mounted) Navigator.pop(context, secret);
        break;
      }
    }
  }

  /// Parse a scanned QR value and extract the base32 secret used for OTP.
  /// Supports standard 'otpauth' URIs and Google Authenticator migration URIs.
  String _extractSecretFromQR(String rawValue) {
    try {
      final uri = Uri.parse(rawValue);

      // Handle Google Authenticator migration URI (contains multiple accounts)
      if (uri.scheme == 'otpauth-migration') {
        try {
          final accounts = GoogleAuthMigrationDecoder.decode(rawValue);

          if (accounts.isEmpty) {
            // No decoded accounts; return raw value as fallback
            return rawValue;
          }

          // Multiple accounts: show a selection dialog and do not return a
          // secret synchronously. The dialog will close the scanner and
          // return the selected secret when the user picks one.
          if (accounts.length > 1) {
            _showAccountSelectionDialog(accounts);
            return '';
          }

          // Single account: return its secret
          return accounts[0].secret;
        } catch (e) {
          // Decoding failed; allow scanning again (fail silently)
          if (mounted) {
            setState(() {
              _isScanned = false;
            });
          }
          return '';
        }
      }

      // Standard otpauth URI with a 'secret' query parameter
      if (uri.scheme == 'otpauth' &&
          uri.queryParameters.containsKey('secret')) {
        return uri.queryParameters['secret']!;
      }

      // Some OTP providers may use other URI schemes but still include
      // a 'secret' query parameter — handle that as a fallback.
      if (uri.queryParameters.containsKey('secret')) {
        return uri.queryParameters['secret']!;
      }

      // If nothing matched, return the raw scanned value (it might already be the secret)
      return rawValue;
    } catch (e) {
      // If the scanned value is not a valid URI, return the raw value
      return rawValue;
    }
  }

  /// Show a dialog to pick one account from a migration payload.
  /// When the user selects an account, the dialog will return its secret and
  /// close the scanner screen with that value.
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
                // Return the chosen secret to the dialog caller
                Navigator.pop(ctx, account.secret);
              },
            );
          }).toList(),
        ),
      ),
    ).then((selectedSecret) {
      if (!mounted) return;
      if (selectedSecret != null) {
        // Close the scanner screen and pass back the selected secret
        Navigator.pop(context, selectedSecret);
      } else {
        // If the dialog was dismissed without selection, allow scanning again
        setState(() {
          _isScanned = false;
        });
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
