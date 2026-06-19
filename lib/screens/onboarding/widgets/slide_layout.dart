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
              const SizedBox(height: 8),
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
                      const SizedBox(height: 24),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                          color: AppColors.textDark,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      content,
                    ],
                  ),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
              const SizedBox(height: 12),
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
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
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
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack,
              color: AppColors.textDark,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          Expanded(
            child: _Dots(stepCount: stepCount, currentIndex: currentIndex),
          ),
          if (onBack != null) const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int stepCount;
  final int currentIndex;

  const _Dots({required this.stepCount, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    // The full step list isn't known until after login (it depends on 2FA,
    // biometrics/PIN, consent and notification state), so the credentials
    // slide reports a count of 1. A lone dot is meaningless — hide it.
    if (stepCount <= 1) return const SizedBox.shrink();
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < stepCount; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == currentIndex ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == currentIndex
                    ? AppColors.primary
                    : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
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
      child: ElevatedButton(
        onPressed: isLoading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
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
            : Text(label, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}
