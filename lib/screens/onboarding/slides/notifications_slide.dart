import 'package:flutter/material.dart';
import '../../../app_colors.dart';
import '../widgets/slide_layout.dart';

class NotificationsSlide extends StatelessWidget {
  final VoidCallback onEnable;
  final VoidCallback onSkip;
  final int stepCount;
  final int currentIndex;
  final VoidCallback? onBack;

  const NotificationsSlide({
    super.key,
    required this.onEnable,
    required this.onSkip,
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
      title: 'Soyez notifié\ndès qu\'une note\nest publiée',
      subtitle: 'Même quand l\'application est fermée',
      primaryLabel: 'Activer les notifications',
      onPrimary: onEnable,
      secondaryLabel: 'Peut-être plus tard',
      onSecondary: onSkip,
      content: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.notifications_outlined,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Notes INSA',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Divider(height: 20, color: Colors.grey.shade200),
            const Text(
              'Nouvelle note : Mathématiques',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              '14 / 20',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
