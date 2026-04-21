import 'package:flutter/material.dart';
import '../app_colors.dart';

class TwoFactorForm extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onValidate;
  final VoidCallback onScanQr;
  final String? errorText;

  const TwoFactorForm({
    super.key,
    required this.controller,
    required this.isLoading,
    required this.onValidate,
    required this.onScanQr,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final codeReady = controller.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),

        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.security, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vérification en deux étapes',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    'Un code est requis pour continuer',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Code input
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: InputDecoration(
            labelText: 'Code de vérification',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.pin_outlined),
            counterText: '',
            errorText: errorText,
          ),
        ),
        const SizedBox(height: 16),

        // Validate code button
        ElevatedButton(
          onPressed: (codeReady && !isLoading) ? onValidate : null,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(16),
            backgroundColor: AppColors.primary,
            disabledBackgroundColor: AppColors.primary.withValues(alpha: .3),
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
              : const Text(
                  'Valider',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
        ),

        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('ou', style: TextStyle(color: Colors.grey)),
              ),
              Expanded(child: Divider()),
            ],
          ),
        ),

        // QR code scan option
        Text(
          'Secret OTP',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),

        InkWell(
          onTap: isLoading ? null : onScanQr,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.qr_code_scanner, color: AppColors.primary),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Scanner le QR code',
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
