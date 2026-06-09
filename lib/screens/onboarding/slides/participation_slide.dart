import 'package:flutter/material.dart';
import '../../../app_colors.dart';
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
      title: 'Comparez\nvos notes\navec la promo',
      subtitle: 'Contribuez anonymement pour voir les moyennes de votre classe',
      primaryLabel: 'Participer',
      onPrimary: onAccept,
      secondaryLabel: 'Non merci',
      onSecondary: onDecline,
      content: const Column(
        children: [
          _DataCard(
            label: 'CE QUI EST PARTAGÉ',
            positive: true,
            items: [
              'Moyenne par matière',
              'Département',
              'Semestre et année académique',
            ],
          ),
          SizedBox(height: 12),
          _DataCard(
            label: 'NON PARTAGÉ',
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

class _DataCard extends StatelessWidget {
  final String label;
  final bool positive;
  final List<String> items;

  const _DataCard({
    required this.label,
    required this.positive,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade500,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in items) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  positive ? Icons.check_circle_outline : Icons.cancel_outlined,
                  size: 16,
                  color: positive
                      ? AppColors.statusPositive
                      : Colors.grey.shade400,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(item, style: const TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
