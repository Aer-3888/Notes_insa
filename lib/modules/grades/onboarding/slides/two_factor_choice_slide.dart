import 'package:flutter/material.dart';
import '../../../../app_colors.dart';
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
      title: 'Double authentification',
      subtitle: 'Choisissez comment valider votre identité',
      isLoading: isLoading,
      error: error,
      primaryLabel: 'Continuer',
      onPrimary: onContinue,
      content: Column(
        children: [
          _MethodOption(
            icon: Icons.dialpad_outlined,
            title: 'Entrer un code',
            description:
                'Un code par email ou depuis votre app TOTP, à chaque connexion.',
            selected: selectedMethod == TfaMethod.manual,
            onTap: () => onSelect(TfaMethod.manual),
          ),
          const SizedBox(height: 8),
          _MethodOption(
            icon: Icons.qr_code_scanner,
            title: 'Scanner le QR code',
            description:
                'À scanner une seule fois. Reconnexion automatique possible.',
            recommendation: 'Recommandé',
            selected: selectedMethod == TfaMethod.totp,
            onTap: () => onSelect(TfaMethod.totp),
          ),
        ],
      ),
    );
  }
}

class _MethodOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? recommendation;
  final bool selected;
  final VoidCallback onTap;

  const _MethodOption({
    required this.icon,
    required this.title,
    required this.description,
    this.recommendation,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    size: 21,
                  ),
                  const SizedBox(width: 14),
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
                                  : AppColors.textSecondary,
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
                            if (recommendation != null)
                              Text(
                                recommendation!,
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          description,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
