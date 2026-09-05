import 'package:flutter/material.dart';
import '../../../../theme/campus_context.dart';
import '../../../../theme/tokens.dart';
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
              duration: CampusMotion.of(context, CampusMotion.fast),
              width: double.infinity,
              decoration: BoxDecoration(
                color: scannedSecret != null
                    ? context.campus.positiveContainer
                    : context.scheme.surfaceContainer,
                border: Border.all(
                  color: scannedSecret != null
                      ? context.campus.positive
                      : context.scheme.outlineVariant,
                ),
                borderRadius: CampusRadii.cardRadius,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isLoading ? null : onScan,
                  borderRadius: CampusRadii.cardRadius,
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
                              ? context.campus.positive
                              : context.scheme.onSurfaceVariant,
                          size: 28,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            scannedSecret != null
                                ? 'QR code reconnu'
                                : 'Ouvrir le scanner',
                            style: context.text.titleMedium?.copyWith(
                              color: scannedSecret != null
                                  ? context.campus.positive
                                  : context.scheme.onSurface,
                            ),
                          ),
                        ),
                        Icon(
                          scannedSecret != null
                              ? Icons.check_rounded
                              : Icons.arrow_forward_rounded,
                          color: scannedSecret != null
                              ? context.campus.positive
                              : context.scheme.onSurfaceVariant,
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
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mémoriser le secret',
                          style: context.text.titleMedium,
                        ),
                        Text(
                          'Permet la reconnexion automatique en arrière-plan',
                          style: context.text.bodyMedium?.copyWith(
                            color: context.scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: CampusSpacing.x3),
                  Switch(value: saveOtpSecret, onChanged: onToggleSave),
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
          child: Text('$number.', style: context.text.titleMedium),
        ),
        Expanded(
          child: Text(
            text,
            style: context.text.bodyMedium?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
