import 'package:flutter/material.dart';
import '../app_colors.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../utils/google_auth_migration_decoder.dart';
import '../utils/base32_codec.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  bool _isScanned = false;
  late final AnimationController _successController;
  late final Animation<double> _successFade;

  @override
  void initState() {
    super.initState();
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _successFade = CurvedAnimation(
      parent: _successController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _successController.dispose();
    super.dispose();
  }

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
        _successController.forward().then((_) {
          if (mounted) Navigator.pop(context, result);
        });
      }
      break;
    }
  }

  String? _extractSecretFromQR(String rawValue) {
    if (rawValue.length > 10240) {
      return null; // Reject unreasonably large payloads
    }
    try {
      final uri = Uri.parse(rawValue);

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

      if (uri.scheme == 'otpauth' &&
          uri.queryParameters.containsKey('secret')) {
        final secret = uri.queryParameters['secret']!;
        return Base32Codec.isValid(secret) ? secret : null;
      }

      if (uri.queryParameters.containsKey('secret')) {
        final secret = uri.queryParameters['secret']!;
        return Base32Codec.isValid(secret) ? secret : null;
      }

      if (Base32Codec.isValid(rawValue)) return rawValue;

      return null;
    } catch (_) {
      if (Base32Codec.isValid(rawValue)) return rawValue;
      return null;
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ),
    );
  }

  void _showAccountSelectionDialog(List<OtpAccount> accounts) {
    if (!mounted) return;

    showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Sélectionner un compte',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            ...accounts.map(
              (account) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.key,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                title: Text(
                  account.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  account.issuer,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, account.secret),
              ),
            ),
          ],
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

    showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Saisir le secret manuellement',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Entrez le secret base32 fourni par votre service.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: controller,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  letterSpacing: 1.2,
                ),
                decoration: InputDecoration(
                  hintText: 'JBSWY3DPEHPK3PXP',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    letterSpacing: 1.2,
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final value = controller.text.trim().toUpperCase();
                    if (Base32Codec.isValid(value)) {
                      Navigator.pop(ctx, value);
                    } else {
                      _showError('Secret invalide. Vérifiez le format base32.');
                    }
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Confirmer',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((secret) {
      if (!mounted || secret == null) return;
      Navigator.pop(context, secret);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera feed
          MobileScanner(onDetect: _onDetect),

          // Overlay
          _ScanOverlay(isScanned: _isScanned),

          // Success flash
          FadeTransition(
            opacity: _successFade,
            child: Container(color: Colors.white.withOpacity(0.25)),
          ),

          // Top bar: back button + title
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    _OverlayButton(
                      icon: Icons.arrow_back,
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Scanner le Token',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom bar: instruction + manual entry
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isScanned
                          ? 'Code reconnu...'
                          : 'Pointez vers un QR code OTP',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _showManualEntryDialog,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withOpacity(0.5),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Saisir manuellement',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
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
}

// ---------------------------------------------------------------------------
// Scan overlay with viewfinder cutout and corner brackets
// ---------------------------------------------------------------------------

class _ScanOverlay extends StatelessWidget {
  final bool isScanned;

  const _ScanOverlay({required this.isScanned});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cutoutSize = size.width * 0.68;

    return CustomPaint(
      painter: _OverlayPainter(cutoutSize: cutoutSize, isScanned: isScanned),
      child: const SizedBox.expand(),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final double cutoutSize;
  final bool isScanned;

  _OverlayPainter({required this.cutoutSize, required this.isScanned});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.42;
    final half = cutoutSize / 2;
    const radius = 12.0;

    final cutout = RRect.fromLTRBR(
      cx - half,
      cy - half,
      cx + half,
      cy + half,
      const Radius.circular(radius),
    );

    // Dark overlay with hole
    final overlayPaint = Paint()..color = Colors.black.withOpacity(0.55);
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final path = Path()
      ..addRect(fullRect)
      ..addRRect(cutout)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, overlayPaint);

    // Corner brackets
    final bracketColor = isScanned ? AppColors.statusPositive : Colors.white;
    final bracketPaint = Paint()
      ..color = bracketColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const arm = 24.0;
    final l = cx - half;
    final t = cy - half;
    final r = cx + half;
    final b = cy + half;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(l + arm, t)
        ..lineTo(l + radius, t)
        ..arcToPoint(
          Offset(l, t + radius),
          radius: const Radius.circular(radius),
          clockwise: false,
        )
        ..lineTo(l, t + arm),
      bracketPaint,
    );
    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(r - arm, t)
        ..lineTo(r - radius, t)
        ..arcToPoint(
          Offset(r, t + radius),
          radius: const Radius.circular(radius),
        )
        ..lineTo(r, t + arm),
      bracketPaint,
    );
    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(l, b - arm)
        ..lineTo(l, b - radius)
        ..arcToPoint(
          Offset(l + radius, b),
          radius: const Radius.circular(radius),
          clockwise: false,
        )
        ..lineTo(l + arm, b),
      bracketPaint,
    );
    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(r, b - arm)
        ..lineTo(r, b - radius)
        ..arcToPoint(
          Offset(r - radius, b),
          radius: const Radius.circular(radius),
        )
        ..lineTo(r - arm, b),
      bracketPaint,
    );
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.isScanned != isScanned || old.cutoutSize != cutoutSize;
}

// ---------------------------------------------------------------------------
// Overlay icon button
// ---------------------------------------------------------------------------

class _OverlayButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _OverlayButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
