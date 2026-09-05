import 'package:flutter/material.dart';
import '../../../../theme/campus_context.dart';
import '../../../../theme/tokens.dart';
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
      title: 'Une alerte quand une note arrive',
      subtitle:
          'Facultatif. Campus INSA peut vous prévenir même lorsque l’application est fermée.',
      primaryLabel: 'Activer les notifications',
      onPrimary: onEnable,
      secondaryLabel: 'Peut-être plus tard',
      onSecondary: onSkip,
      content: Card(
        child: Padding(
          padding: const EdgeInsets.all(CampusSpacing.card),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.notifications_outlined,
                    size: 20,
                    color: context.scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: CampusSpacing.x3),
                  Text('Campus INSA', style: context.text.titleMedium),
                ],
              ),
              const Divider(height: CampusSpacing.x5),
              Text(
                'Nouvelle note : Mathématiques',
                style: context.text.bodyLarge,
              ),
              const SizedBox(height: CampusSpacing.x1),
              Text(
                '14 / 20',
                style: context.text.bodyMedium?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
