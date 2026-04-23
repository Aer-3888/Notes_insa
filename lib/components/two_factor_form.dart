import 'package:flutter/material.dart';
import '../app_colors.dart';

class TwoFactorForm extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onValidate;
  final VoidCallback onScanQr;
  final String? errorText;

  // Optional email support
  final VoidCallback? onTriggerEmail;
  final bool emailSent;

  // Optional secret management (auto-validate)
  final String? scannedSecret;
  final ValueChanged<String>? onAutoValidate;
  final bool saveSecret;
  final ValueChanged<bool>? onToggleSaveSecret;

  const TwoFactorForm({
    super.key,
    required this.controller,
    required this.isLoading,
    required this.onValidate,
    required this.onScanQr,
    this.errorText,
    this.onTriggerEmail,
    this.emailSent = false,
    this.scannedSecret,
    this.onAutoValidate,
    this.saveSecret = false,
    this.onToggleSaveSecret,
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

        // Option: Email (if supported)
        if (onTriggerEmail != null) ...[
          OutlinedButton.icon(
            onPressed: (isLoading || emailSent) ? null : onTriggerEmail,
            icon: Icon(emailSent ? Icons.check_circle : Icons.email_outlined),
            label: Text(
              emailSent ? 'Email envoyé' : 'Recevoir un code par email',
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(14),
              foregroundColor: emailSent
                  ? AppColors.statusPositive
                  : AppColors.primary,
              side: BorderSide(
                color: emailSent ? AppColors.statusPositive : AppColors.primary,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Code input
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 8,
          onChanged: (_) {
            // Force rebuild to update 'Validate' button state if needed
            (context as Element).markNeedsBuild();
          },
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
        if (onToggleSaveSecret != null) ...[
          const SizedBox(height: 4),
          Text(
            'Scannez le QR code 2FA pour éviter de ressaisir un code à chaque connexion.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
        const SizedBox(height: 10),

        InkWell(
          onTap: isLoading ? null : onScanQr,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scannedSecret != null
                  ? AppColors.statusPositive.withValues(alpha: .1)
                  : Colors.grey.shade100,
              border: Border.all(
                color: scannedSecret != null
                    ? AppColors.statusPositive
                    : Colors.grey.shade300,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  scannedSecret != null
                      ? Icons.check_circle
                      : Icons.qr_code_scanner,
                  color: scannedSecret != null
                      ? AppColors.statusPositive
                      : AppColors.primary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    scannedSecret != null
                        ? 'Secret scanné'
                        : 'Scanner le QR code',
                    style: TextStyle(
                      color: scannedSecret != null
                          ? AppColors.statusPositive
                          : Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Optional save secret checkbox
        if (onToggleSaveSecret != null) ...[
          const SizedBox(height: 8),
          CheckboxListTile(
            value: saveSecret,
            onChanged: (v) => onToggleSaveSecret!(v ?? false),
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Mémoriser le secret pour les prochaines connexions',
              style: TextStyle(fontSize: 13),
            ),
            subtitle: const Text(
              'Nécessaire pour la mise à jour automatique en arrière-plan.',
              style: TextStyle(fontSize: 11),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppColors.primary,
          ),
        ],

        // Optional auto-validate button
        if (scannedSecret != null && onAutoValidate != null) ...[
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: isLoading ? null : () => onAutoValidate!(scannedSecret!),
            icon: const Icon(Icons.auto_fix_high, color: Colors.white),
            label: const Text(
              'Valider automatiquement',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
              backgroundColor: AppColors.statusPositive,
              disabledBackgroundColor: AppColors.statusPositive.withValues(
                alpha: .3,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
