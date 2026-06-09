import 'package:flutter/material.dart';
import '../../../app_colors.dart';
import '../onboarding_enums.dart';
import '../widgets/slide_layout.dart';

class TwoFactorChoiceSlide extends StatelessWidget {
  final TfaMethod? selectedMethod;
  final ValueChanged<TfaMethod> onSelect;
  final VoidCallback? onContinue;
  final bool isLoading;
  final String? error;
  final int stepCount;
  final int currentIndex;
  final VoidCallback? onBack;

  const TwoFactorChoiceSlide({
    super.key,
    required this.selectedMethod,
    required this.onSelect,
    required this.onContinue,
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
      title: 'Double\nauthentification',
      subtitle: 'Choisissez comment valider votre identité',
      isLoading: isLoading,
      error: error,
      primaryLabel: 'Continuer',
      onPrimary: onContinue,
      content: Column(
        children: [
          _MethodCard(
            icon: Icons.dialpad_outlined,
            title: 'Entrer un code',
            description:
                'Recevez un code par email ou entrez celui de votre app TOTP à chaque connexion',
            warnings: const ['Action manuelle à chaque expiration de session'],
            selected: selectedMethod == TfaMethod.manual,
            onTap: () => onSelect(TfaMethod.manual),
          ),
          const SizedBox(height: 12),
          _MethodCard(
            icon: Icons.qr_code_scanner,
            title: 'Scanner le QR code',
            description:
                'Scannez le QR code INSA une seule fois pour vous authentifier',
            positives: const [
              'Option de mémorisation pour la reconnexion automatique',
            ],
            badge: 'Recommandé',
            selected: selectedMethod == TfaMethod.totp,
            onTap: () => onSelect(TfaMethod.totp),
          ),
        ],
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final List<String> positives;
  final List<String> warnings;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  const _MethodCard({
    required this.icon,
    required this.title,
    required this.description,
    this.positives = const [],
    this.warnings = const [],
    this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.05)
              : Colors.grey.shade50,
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey.shade200,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? AppColors.primary : Colors.grey.shade400,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: selected
                            ? AppColors.primary
                            : Colors.grey.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: selected
                                ? AppColors.primary
                                : AppColors.textDark,
                          ),
                        ),
                      ),
                      if (badge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  for (final p in positives) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          size: 14,
                          color: AppColors.statusPositive,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            p,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.statusPositive,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  for (final w in warnings) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_outlined,
                          size: 14,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            w,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
