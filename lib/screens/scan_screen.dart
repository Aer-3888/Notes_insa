// Camera chrome is dark in both themes by function, not by style: the preview
// must not be framed by a light surface. Everything outside the viewfinder
// (sheets, snackbars, buttons) follows the app theme.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/campus_context.dart';
import '../theme/tokens.dart';
import '../utils/google_auth_migration_decoder.dart';
import '../utils/base32_codec.dart';

// Viewfinder brackets turn this green on a successful scan. It is a fixed
// value rather than a theme token because it is painted over a live camera
// feed, not over any app surface.
const Color _kScanSuccess = Color(0xFF2A7354);

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  bool _isScanned = false;
  DateTime? _lastErrorAt;
  BarcodeCapture? _trackedCapture;
  late final AnimationController _successController;
  late final Animation<double> _successFade;
  final MobileScannerController _scannerController = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

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
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture, {bool trackBarcode = true}) {
    if (_isScanned) return;

    for (final barcode in capture.barcodes) {
      if (barcode.rawValue == null) continue;

      setState(() {
        _isScanned = true;
        if (trackBarcode) _trackedCapture = capture;
      });

      final result = _extractSecretFromQR(barcode.rawValue!);

      if (result == null) {
        // mobile_scanner fires every frame; debounce so an unrecognised QR in
        // view doesn't spam a SnackBar on each frame.
        final now = DateTime.now();
        if (_lastErrorAt == null ||
            now.difference(_lastErrorAt!) > const Duration(seconds: 2)) {
          _lastErrorAt = now;
          _showError('QR non reconnu. Scannez un code OTP valide.');
        }
        setState(() => _isScanned = false);
      } else if (result.isNotEmpty && mounted) {
        HapticFeedback.lightImpact();
        _successController.forward().then((_) {
          if (mounted) Navigator.pop(context, result);
        });
      }
      break;
    }
  }

  /// Lets the user pick a screenshot/photo of a QR code from the gallery and
  /// decodes it through the same pipeline as a live scan.
  Future<void> _pickFromGallery() async {
    if (_isScanned) return;
    try {
      final XFile? file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
      );
      if (file == null || !mounted) return;

      final BarcodeCapture? capture = await _scannerController.analyzeImage(
        file.path,
      );
      if (!mounted) return;

      if (capture == null || capture.barcodes.isEmpty) {
        _showError('Aucun QR code trouvé dans l\'image.');
        return;
      }
      // Reuse the live-scan handling (extraction, multi-account, navigation).
      _onDetect(capture, trackBarcode: false);
    } catch (_) {
      if (mounted) _showError('Impossible de lire l\'image.');
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
          // Keep only accounts the app can generate valid codes for. Anything
          // else (HOTP, non-SHA1, 8 digits) would import as a broken seed.
          final supported = accounts.where((a) => a.isSupportedTotp).toList();
          if (supported.isEmpty) {
            _showError('Ce compte 2FA utilise un format non pris en charge.');
            return null;
          }
          if (supported.length > 1) {
            _showAccountSelectionDialog(supported);
            return '';
          }
          return supported[0].secret;
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showAccountSelectionDialog(List<OtpAccount> accounts) {
    if (!mounted) return;

    showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(
          CampusSpacing.gutter,
          0,
          CampusSpacing.gutter,
          CampusSpacing.x8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Sélectionner un compte', style: ctx.text.titleLarge),
            ),
            const SizedBox(height: CampusSpacing.x4),
            ...accounts.map(
              (account) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.key, color: ctx.scheme.onSurfaceVariant),
                title: Text(account.name, style: ctx.text.titleMedium),
                subtitle: Text(
                  account.issuer,
                  style: ctx.text.bodyMedium?.copyWith(
                    color: ctx.scheme.onSurfaceVariant,
                  ),
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
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            CampusSpacing.gutter,
            0,
            CampusSpacing.gutter,
            CampusSpacing.x8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Saisir le secret manuellement', style: ctx.text.titleLarge),
              const SizedBox(height: CampusSpacing.x2),
              Text(
                'Entrez le secret base32 fourni par votre service.',
                style: ctx.text.bodyMedium?.copyWith(
                  color: ctx.scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: CampusSpacing.x5),
              TextField(
                controller: controller,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                // Monospace is meaningful here: this is a machine code the
                // user is transcribing character by character.
                style: ctx.text.bodyLarge?.copyWith(
                  fontFamily: 'monospace',
                  letterSpacing: 1.2,
                ),
                decoration: const InputDecoration(hintText: 'JBSWY3DPEHPK3PXP'),
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
                  child: const Text('Confirmer'),
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
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final scanWindow = _scanWindowFor(constraints.biggest);

          return Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _scannerController,
                onDetect: _onDetect,
                errorBuilder: (_, _) => const _CameraError(),
              ),
              _ScanOverlay(
                guideWindow: scanWindow,
                capture: _trackedCapture,
                deviceOrientation: _scannerController.value.deviceOrientation,
                isScanned: _isScanned,
              ),
              IgnorePointer(
                child: FadeTransition(
                  opacity: _successFade,
                  child: const ColoredBox(
                    color: Color.fromRGBO(5, 150, 105, 0.1),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Row(
                      children: [
                        _OverlayButton(
                          icon: Icons.arrow_back_rounded,
                          tooltip: 'Retour',
                          onTap: () => Navigator.pop(context),
                        ),
                        const Expanded(
                          child: Text(
                            'Scanner le QR code',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        ValueListenableBuilder<MobileScannerState>(
                          valueListenable: _scannerController,
                          builder: (_, state, _) {
                            final torchAvailable =
                                state.torchState != TorchState.unavailable;
                            final torchEnabled =
                                state.torchState == TorchState.on;
                            return _OverlayButton(
                              icon: torchEnabled
                                  ? Icons.flashlight_on_rounded
                                  : Icons.flashlight_off_rounded,
                              tooltip: torchEnabled
                                  ? 'Éteindre la lampe'
                                  : 'Allumer la lampe',
                              isActive: torchEnabled,
                              onTap: torchAvailable && !_isScanned
                                  ? _scannerController.toggleTorch
                                  : null,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: SafeArea(
                  top: false,
                  child: _ScannerActions(
                    isScanned: _isScanned,
                    onGallery: _pickFromGallery,
                    onManualEntry: _showManualEntryDialog,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Rect _scanWindowFor(Size size) {
    final availableWidth = math.max(160.0, size.width - 64);
    final availableHeight = math.max(160.0, size.height - 300);
    final side = math.min(300.0, math.min(availableWidth, availableHeight));
    final minimumY = (side / 2) + 88;
    final maximumY = math.max(minimumY, size.height - (side / 2) - 190);
    final centerY = (size.height * 0.4).clamp(minimumY, maximumY);

    return Rect.fromCenter(
      center: Offset(size.width / 2, centerY),
      width: side,
      height: side,
    );
  }
}

// ---------------------------------------------------------------------------
// Scan overlay with viewfinder cutout and corner brackets
// ---------------------------------------------------------------------------

class _ScanOverlay extends StatelessWidget {
  final Rect guideWindow;
  final BarcodeCapture? capture;
  final DeviceOrientation deviceOrientation;
  final bool isScanned;

  const _ScanOverlay({
    required this.guideWindow,
    required this.capture,
    required this.deviceOrientation,
    required this.isScanned,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackedWindow = _trackedWindowFor(
          capture,
          constraints.biggest,
          deviceOrientation,
        );

        return TweenAnimationBuilder<Rect>(
          tween: _ScannerRectTween(
            begin: guideWindow,
            end: trackedWindow ?? guideWindow,
          ),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          builder: (context, animatedWindow, _) {
            return CustomPaint(
              painter: _OverlayPainter(
                scanWindow: animatedWindow,
                isScanned: isScanned,
                isTracking: trackedWindow != null,
              ),
              child: const SizedBox.expand(),
            );
          },
        );
      },
    );
  }

  Rect? _trackedWindowFor(
    BarcodeCapture? capture,
    Size layoutSize,
    DeviceOrientation orientation,
  ) {
    if (capture == null || capture.size.isEmpty || layoutSize.isEmpty) {
      return null;
    }

    Barcode? detectedQr;
    for (final barcode in capture.barcodes) {
      if (barcode.corners.length >= 4) {
        detectedQr = barcode;
        break;
      }
    }
    if (detectedQr == null) return null;

    final isLandscape =
        orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight;
    final previewSize = isLandscape ? capture.size.flipped : capture.size;
    final ratios = calculateBoxFitRatio(BoxFit.cover, previewSize, layoutSize);
    final horizontalCrop =
        (previewSize.width * ratios.widthRatio - layoutSize.width) / 2;
    final verticalCrop =
        (previewSize.height * ratios.heightRatio - layoutSize.height) / 2;

    final points = detectedQr.corners.map(
      (corner) => Offset(
        corner.dx * ratios.widthRatio - horizontalCrop,
        corner.dy * ratios.heightRatio - verticalCrop,
      ),
    );
    final left = points.map((point) => point.dx).reduce(math.min);
    final top = points.map((point) => point.dy).reduce(math.min);
    final right = points.map((point) => point.dx).reduce(math.max);
    final bottom = points.map((point) => point.dy).reduce(math.max);
    final trackedWindow = Rect.fromLTRB(left, top, right, bottom).inflate(10);
    final visibleArea = Rect.fromLTWH(
      8,
      8,
      math.max(0, layoutSize.width - 16),
      math.max(0, layoutSize.height - 16),
    );
    final visibleWindow = trackedWindow.intersect(visibleArea);

    if (visibleWindow.width < 40 || visibleWindow.height < 40) return null;
    return visibleWindow;
  }
}

class _ScannerRectTween extends Tween<Rect> {
  _ScannerRectTween({required Rect begin, required Rect end})
    : super(begin: begin, end: end);

  @override
  Rect lerp(double t) => Rect.lerp(begin, end, t)!;
}

class _OverlayPainter extends CustomPainter {
  final Rect scanWindow;
  final bool isScanned;
  final bool isTracking;

  _OverlayPainter({
    required this.scanWindow,
    required this.isScanned,
    required this.isTracking,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(22.0, scanWindow.shortestSide / 4);
    final cutout = RRect.fromRectAndRadius(scanWindow, Radius.circular(radius));

    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.46);
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final path = Path()
      ..addRect(fullRect)
      ..addRRect(cutout)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, overlayPaint);

    final bracketColor = isScanned ? _kScanSuccess : Colors.white;
    final outlinePaint = Paint()
      ..color = bracketColor.withValues(alpha: isTracking ? 0.7 : 0.45)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(cutout, outlinePaint);

    final bracketPaint = Paint()
      ..color = bracketColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final arm = math.min(28.0, scanWindow.shortestSide / 3);
    final l = scanWindow.left;
    final t = scanWindow.top;
    final r = scanWindow.right;
    final b = scanWindow.bottom;

    canvas.drawPath(
      Path()
        ..moveTo(l + arm, t)
        ..lineTo(l + radius, t)
        ..arcToPoint(
          Offset(l, t + radius),
          radius: Radius.circular(radius),
          clockwise: false,
        )
        ..lineTo(l, t + arm),
      bracketPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(r - arm, t)
        ..lineTo(r - radius, t)
        ..arcToPoint(Offset(r, t + radius), radius: Radius.circular(radius))
        ..lineTo(r, t + arm),
      bracketPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(l, b - arm)
        ..lineTo(l, b - radius)
        ..arcToPoint(
          Offset(l + radius, b),
          radius: Radius.circular(radius),
          clockwise: false,
        )
        ..lineTo(l + arm, b),
      bracketPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(r, b - arm)
        ..lineTo(r, b - radius)
        ..arcToPoint(Offset(r - radius, b), radius: Radius.circular(radius))
        ..lineTo(r - arm, b),
      bracketPaint,
    );
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.isScanned != isScanned ||
      old.isTracking != isTracking ||
      old.scanWindow != scanWindow;
}

// ---------------------------------------------------------------------------
// Overlay icon button
// ---------------------------------------------------------------------------

class _OverlayButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isActive;

  const _OverlayButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 22),
      style: IconButton.styleFrom(
        fixedSize: const Size(48, 48),
        foregroundColor: isActive ? Colors.black : Colors.white,
        disabledForegroundColor: Colors.white.withValues(alpha: 0.35),
        backgroundColor: isActive
            ? Colors.white
            : Colors.black.withValues(alpha: 0.24),
        disabledBackgroundColor: Colors.black.withValues(alpha: 0.14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
        shape: const CircleBorder(),
      ),
    );
  }
}

class _ScannerActions extends StatelessWidget {
  const _ScannerActions({
    required this.isScanned,
    required this.onGallery,
    required this.onManualEntry,
  });

  final bool isScanned;
  final VoidCallback onGallery;
  final VoidCallback onManualEntry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Column(
              key: ValueKey(isScanned),
              children: [
                Text(
                  isScanned
                      ? 'QR code reconnu'
                      : 'Placez le QR code dans le cadre',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isScanned
                      ? 'Validation en cours'
                      : 'La lecture démarre automatiquement',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.64),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.12)),
          Row(
            children: [
              Expanded(
                child: _ScannerAction(
                  icon: Icons.photo_library_outlined,
                  label: 'Galerie',
                  onTap: isScanned ? null : onGallery,
                ),
              ),
              SizedBox(
                height: 36,
                child: VerticalDivider(
                  width: 1,
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              Expanded(
                child: _ScannerAction(
                  icon: Icons.keyboard_outlined,
                  label: 'Saisie manuelle',
                  onTap: isScanned ? null : onManualEntry,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScannerAction extends StatelessWidget {
  const _ScannerAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = Colors.white.withValues(alpha: onTap == null ? 0.34 : 0.78);

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 54,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF151719),
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.no_photography_outlined,
                size: 34,
                color: Colors.white70,
              ),
              SizedBox(height: 16),
              Text(
                'Caméra indisponible',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Vérifiez l’autorisation caméra dans les réglages de l’appareil.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
