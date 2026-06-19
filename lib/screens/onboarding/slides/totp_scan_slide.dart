import 'package:flutter/material.dart';
import '../../../app_colors.dart';
import '../widgets/slide_layout.dart';

class TotpScanSlide extends StatelessWidget {
  final String? scannedSecret;
  final bool saveOtpSecret;
  final VoidCallback onScan;
  final ValueChanged<bool> onToggleSave;
  final VoidCallback onValidate;
  final bool isLoading;
  final String? error;
  final int stepCount;
  final int currentIndex;
  final VoidCallback? onBack;

  const TotpScanSlide({
    super.key,
    required this.scannedSecret,
    required this.saveOtpSecret,
    required this.onScan,
    required this.onToggleSave,
    required this.onValidate,
    required this.isLoading,
    this.error,
    required this.stepCount,
    required this.currentIndex,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SlideLayout(
      stepCount: stepCount,
      currentIndex: currentIndex,
      onBack: onBack,
      title: 'Scanner le QR code',
      subtitle:
          'Si vous n\'avez pas encore configuré votre OTP, rendez-vous sur l\'intranet INSA dans l\'OTP Manager',
      isLoading: isLoading,
      error: error,
      primaryLabel: 'Valider',
      onPrimary: scannedSecret != null ? onValidate : null,
      content: Column(
        children: [
          Semantics(
            button: true,
            selected: scannedSecret != null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              decoration: BoxDecoration(
                color: scannedSecret != null
                    ? AppColors.statusPositive.withValues(alpha: 0.05)
                    : Colors.grey.shade50,
                border: Border.all(
                  color: scannedSecret != null
                      ? AppColors.statusPositive
                      : Colors.grey.shade300,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isLoading ? null : onScan,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 40,
                      horizontal: 20,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          scannedSecret != null
                              ? Icons.check_circle_outline
                              : Icons.qr_code_scanner,
                          color: scannedSecret != null
                              ? AppColors.statusPositive
                              : AppColors.primary,
                          size: 56,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          scannedSecret != null
                              ? 'QR code scanné ✓'
                              : 'Scanner le QR code',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: scannedSecret != null
                                ? AppColors.statusPositive
                                : AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (scannedSecret != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Mémoriser le secret',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Permet la reconnexion automatique en arrière-plan',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Switch(
                    value: saveOtpSecret,
                    onChanged: onToggleSave,
                    activeThumbColor: AppColors.primary,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
