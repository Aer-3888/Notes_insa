import 'package:flutter/material.dart';

import '../../../theme/campus_context.dart';
import '../../../theme/tokens.dart';

/// One wizard step: pinned progress, a title that says what is being asked,
/// and a list that owns the rest of the height.
///
/// Close to the grades onboarding's SlideLayout, but that one scrolls its
/// content, which cannot hold a list of a hundred groups. Here the list is the
/// content, so it gets [Expanded] and the header and button stay pinned.
class WizardScaffold extends StatelessWidget {
  const WizardScaffold({
    super.key,
    required this.stepCount,
    required this.currentIndex,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.primaryLabel,
    required this.onPrimary,
    this.onBack,
    this.breadcrumb,
  });

  final int stepCount;
  final int currentIndex;
  final String title;
  final String subtitle;
  final Widget child;
  final String primaryLabel;
  final VoidCallback? onPrimary;

  /// Null on the first step, where there is nowhere to go back to.
  final VoidCallback? onBack;

  /// Shown on the group step, which drills inside itself.
  final Widget? breadcrumb;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 52,
          child: Row(
            children: [
              if (onBack != null)
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Retour',
                  onPressed: onBack,
                )
              else
                const SizedBox(width: CampusSpacing.gutter),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: CampusSpacing.gutter),
                child: Text(
                  '${currentIndex + 1} / $stepCount',
                  semanticsLabel: 'Étape ${currentIndex + 1} sur $stepCount',
                  style: context.text.labelMedium?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        Semantics(
          label: 'Progression de la configuration',
          value: '${currentIndex + 1} sur $stepCount',
          child: LinearProgressIndicator(
            value: (currentIndex + 1) / stepCount,
            minHeight: 2,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CampusSpacing.gutter,
            CampusSpacing.x6,
            CampusSpacing.gutter,
            CampusSpacing.x2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.text.headlineSmall),
              const SizedBox(height: CampusSpacing.x2),
              Text(
                subtitle,
                style: context.text.bodyMedium?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        ?breadcrumb,
        Expanded(child: child),
        Padding(
          padding: const EdgeInsets.all(CampusSpacing.gutter),
          child: SizedBox(
            width: double.infinity,
            height: CampusSpacing.touchTarget,
            child: FilledButton(
              onPressed: onPrimary,
              child: Text(primaryLabel),
            ),
          ),
        ),
      ],
    ),
  );
}
