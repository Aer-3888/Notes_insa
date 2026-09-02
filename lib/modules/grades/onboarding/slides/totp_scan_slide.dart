import 'package:flutter/material.dart';
import '../../../../app_colors.dart';
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
      title: 'Scannez votre QR code',
      subtitle: 'Le QR code est disponible dans l’OTP Manager du portail INSA.',
      isLoading: isLoading,
      error: error,
      primaryLabel: 'Valider',
      onPrimary: scannedSecret != null ? onValidate : null,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Instruction(
            number: '1',
            text: 'Ouvrez l’OTP Manager sur le portail INSA.',
          ),
          const SizedBox(height: 12),
          const _Instruction(
            number: '2',
            text: 'Affichez votre QR code, puis scannez-le ici.',
          ),
          const SizedBox(height: 24),
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
                      vertical: 18,
                      horizontal: 18,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          scannedSecret != null
                              ? Icons.check_circle_outline
                              : Icons.qr_code_scanner,
                          color: scannedSecret != null
                              ? AppColors.statusPositive
                              : AppColors.primary,
                          size: 28,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            scannedSecret != null
                                ? 'QR code reconnu'
                                : 'Ouvrir le scanner',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: scannedSecret != null
                                  ? AppColors.statusPositive
                                  : AppColors.textDark,
                            ),
                          ),
                        ),
                        Icon(
                          scannedSecret != null
                              ? Icons.check_rounded
                              : Icons.arrow_forward_rounded,
                          color: scannedSecret != null
                              ? AppColors.statusPositive
                              : AppColors.textSecondary,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (scannedSecret != null) ...[
            const SizedBox(height: 16),
            const Divider(color: AppColors.border),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mémoriser le secret',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Permet la reconnexion automatique en arrière-plan',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: AppColors.textSecondary,
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

class _Instruction extends StatelessWidget {
  const _Instruction({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          child: Text(
            '$number.',
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
