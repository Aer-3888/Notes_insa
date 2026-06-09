import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app_colors.dart';
import '../widgets/slide_layout.dart';

class ManualCodeSlide extends StatefulWidget {
  final TextEditingController codeController;
  final bool emailSent;
  final VoidCallback onTriggerEmail;
  final VoidCallback onValidate;
  final bool isLoading;
  final String? error;
  final int stepCount;
  final int currentIndex;
  final VoidCallback? onBack;

  const ManualCodeSlide({
    super.key,
    required this.codeController,
    required this.emailSent,
    required this.onTriggerEmail,
    required this.onValidate,
    required this.isLoading,
    this.error,
    required this.stepCount,
    required this.currentIndex,
    this.onBack,
  });

  @override
  State<ManualCodeSlide> createState() => _ManualCodeSlideState();
}

class _ManualCodeSlideState extends State<ManualCodeSlide> {
  @override
  void initState() {
    super.initState();
    widget.codeController.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.codeController.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final codeReady = widget.codeController.text.trim().length >= 4;
    return SlideLayout(
      stepCount: widget.stepCount,
      currentIndex: widget.currentIndex,
      onBack: widget.onBack,
      title: 'Code de\nvérification',
      subtitle: 'Entrez le code reçu par email ou généré par votre app',
      isLoading: widget.isLoading,
      error: widget.error,
      primaryLabel: 'Valider',
      onPrimary: codeReady ? widget.onValidate : null,
      content: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.isLoading ? null : widget.onTriggerEmail,
              icon: Icon(
                widget.emailSent
                    ? Icons.check_circle_outline
                    : Icons.email_outlined,
                color: widget.emailSent
                    ? AppColors.statusPositive
                    : AppColors.primary,
                size: 18,
              ),
              label: Text(
                widget.emailSent
                    ? 'Email envoyé'
                    : 'Recevoir un code par email',
                style: TextStyle(
                  color: widget.emailSent
                      ? AppColors.statusPositive
                      : AppColors.primary,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: widget.emailSent
                      ? AppColors.statusPositive
                      : AppColors.primary,
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: widget.codeController,
            keyboardType: TextInputType.number,
            maxLength: 8,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 24, letterSpacing: 6),
            onSubmitted: (_) {
              if (codeReady) widget.onValidate();
            },
            decoration: const InputDecoration(
              labelText: 'Code de vérification',
              border: OutlineInputBorder(),
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }
}
