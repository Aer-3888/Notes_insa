import 'package:flutter/material.dart';
import '../../../../theme/campus_context.dart';
import '../../../../theme/tokens.dart';

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
                      Text(title, style: context.text.headlineMedium),
                      if (subtitle != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          subtitle!,
                          style: context.text.bodyLarge?.copyWith(
                            color: context.scheme.onSurfaceVariant,
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
                    child: Text(secondaryLabel!),
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
                  tooltip: 'Retour',
                ),
              ],
              const Spacer(),
              if (stepCount > 1)
                Text(
                  '${currentIndex + 1} / $stepCount',
                  semanticsLabel: 'Étape ${currentIndex + 1} sur $stepCount',
                  style: context.text.labelMedium?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        if (stepCount > 1)
          Semantics(
            label: 'Progression de la configuration',
            value: '${currentIndex + 1} sur $stepCount',
            child: LinearProgressIndicator(
              value: (currentIndex + 1) / stepCount,
              minHeight: 2,
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
        padding: const EdgeInsets.symmetric(
          horizontal: CampusSpacing.x4,
          vertical: CampusSpacing.x3,
        ),
        decoration: BoxDecoration(
          color: context.scheme.errorContainer,
          borderRadius: CampusRadii.controlRadius,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 20,
              color: context.scheme.onErrorContainer,
            ),
            const SizedBox(width: CampusSpacing.x3),
            Expanded(
              child: Text(
                message,
                style: context.text.bodyMedium?.copyWith(
                  color: context.scheme.onErrorContainer,
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
      height: CampusSpacing.touchTarget,
      child: FilledButton(
        onPressed: isLoading ? null : onTap,
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: context.scheme.onPrimary,
                  strokeWidth: 2,
                ),
              )
            : Text(label),
      ),
    );
  }
}
