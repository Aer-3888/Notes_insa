import 'package:flutter/material.dart';
import '../../../../theme/campus_context.dart';
import '../../../../theme/tokens.dart';
import '../widgets/slide_layout.dart';

class ParticipationSlide extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final int stepCount;
  final int currentIndex;
  final VoidCallback? onBack;

  const ParticipationSlide({
    super.key,
    required this.onAccept,
    required this.onDecline,
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
      title: 'Situez-vous dans votre promo',
      subtitle:
          'Facultatif. Vous partagez vos moyennes de façon anonyme et '
          'voyez en retour celles de votre promo.',
      primaryLabel: 'Participer',
      onPrimary: onAccept,
      secondaryLabel: 'Non merci',
      onSecondary: onDecline,
      content: const Column(
        children: [
          _DataSection(
            label: 'Partagé',
            positive: true,
            items: [
              'Moyenne par matière',
              'Département',
              'Semestre et année académique',
            ],
          ),
          Divider(height: CampusSpacing.x8),
          _DataSection(
            label: 'Jamais partagé',
            positive: false,
            items: [
              'Votre nom',
              'Notes individuelles (CC, exam…)',
              'Toute information personnelle',
            ],
          ),
        ],
      ),
    );
  }
}

class _DataSection extends StatelessWidget {
  final String label;
  final bool positive;
  final List<String> items;

  const _DataSection({
    required this.label,
    required this.positive,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.text.labelMedium?.copyWith(
              color: positive
                  ? context.campus.positive
                  : context.scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          for (final item in items) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  positive ? Icons.check_circle_outline : Icons.cancel_outlined,
                  size: 18,
                  color: positive
                      ? context.campus.positive
                      : context.scheme.onSurfaceVariant,
                ),
                const SizedBox(width: CampusSpacing.x2),
                Expanded(child: Text(item, style: context.text.bodyMedium)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
