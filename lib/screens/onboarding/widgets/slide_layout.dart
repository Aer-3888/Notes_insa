import 'package:flutter/material.dart';
import '../../../app_colors.dart';

class SlideLayout extends StatelessWidget {
  final int stepCount;
  final int currentIndex;
  final VoidCallback? onBack;
  final String title;
  final String? subtitle;
  final Widget content;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool isLoading;
  final String? error;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const SlideLayout({
    super.key,
    required this.stepCount,
    required this.currentIndex,
    this.onBack,
    required this.title,
    this.subtitle,
    required this.content,
    required this.primaryLabel,
    required this.onPrimary,
    this.isLoading = false,
    this.error,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              _Header(
                stepCount: stepCount,
                currentIndex: currentIndex,
                onBack: onBack,
              ),
              // Title + subtitle + content share one scroll region so they
              // never overflow when vertical space is tight (keyboard up,
              // landscape, or large accessibility text-scale). The header and
              // primary CTA stay pinned, keeping the CTA reachable above the
              // keyboard.
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 32),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.7,
                          height: 1.12,
                          color: AppColors.textDark,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.45,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      content,
                      if (error != null) ...[
                        const SizedBox(height: 20),
                        _ErrorMessage(error!),
                      ],
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _PrimaryButton(
                label: primaryLabel,
                onTap: onPrimary,
                isLoading: isLoading,
              ),
              if (secondaryLabel != null)
                Center(
                  child: TextButton(
                    onPressed: onSecondary,
                    child: Text(
                      secondaryLabel!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(height: 8),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int stepCount;
  final int currentIndex;
  final VoidCallback? onBack;

  const _Header({
    required this.stepCount,
    required this.currentIndex,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    if (stepCount <= 1 && onBack == null) {
      return const SizedBox(height: 20);
    }

    return Column(
      children: [
        SizedBox(
          height: 52,
          child: Row(
            children: [
              if (onBack != null) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: onBack,
                  color: AppColors.textDark,
                  tooltip: 'Retour',
                ),
              ],
              const Spacer(),
              if (stepCount > 1)
                Text(
                  '${currentIndex + 1} / $stepCount',
                  semanticsLabel: 'Étape ${currentIndex + 1} sur $stepCount',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        if (stepCount > 1)
          Semantics(
            label: 'Progression de la configuration',
            value: '${currentIndex + 1} sur $stepCount',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(1),
              child: LinearProgressIndicator(
                value: (currentIndex + 1) / stepCount,
                minHeight: 2,
                backgroundColor: AppColors.border,
                color: AppColors.primary,
              ),
            ),
          ),
      ],
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.errorSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 19,
              color: AppColors.error,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isLoading;

  const _PrimaryButton({
    required this.label,
    required this.onTap,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton(
        onPressed: isLoading ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
