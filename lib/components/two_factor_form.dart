import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/campus_context.dart';
import '../theme/tokens.dart';

class TwoFactorForm extends StatefulWidget {
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
  State<TwoFactorForm> createState() => _TwoFactorFormState();
}

class _TwoFactorFormState extends State<TwoFactorForm> {
  @override
  void initState() {
    super.initState();
    // Rebuild on input so the 'Valider' button enable state stays in sync.
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    // Codes are numeric; require at least 4 digits before enabling validation.
    final codeReady = widget.controller.text.trim().length >= 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),

        // Header
        Row(
          children: [
            Icon(Icons.security, color: context.scheme.onSurfaceVariant),
            const SizedBox(width: CampusSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vérification en deux étapes',
                    style: context.text.titleMedium,
                  ),
                  Text(
                    'Un code est requis pour continuer',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Option: Email (if supported)
        if (widget.onTriggerEmail != null) ...[
          OutlinedButton.icon(
            onPressed: (widget.isLoading || widget.emailSent)
                ? null
                : widget.onTriggerEmail,
            icon: Icon(
              widget.emailSent ? Icons.check_circle : Icons.email_outlined,
            ),
            label: Text(
              widget.emailSent ? 'Email envoyé' : 'Recevoir un code par email',
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Code input
        TextField(
          controller: widget.controller,
          keyboardType: TextInputType.number,
          maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Code de vérification',
            prefixIcon: const Icon(Icons.pin_outlined),
            counterText: '',
            errorText: widget.errorText,
          ),
        ),
        const SizedBox(height: 16),

        // Validate code button
        FilledButton(
          onPressed: (codeReady && !widget.isLoading)
              ? widget.onValidate
              : null,
          child: widget.isLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: context.scheme.onPrimary,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Valider'),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(vertical: CampusSpacing.x5),
          child: Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CampusSpacing.x3,
                ),
                child: Text(
                  'ou',
                  style: context.text.labelMedium?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
        ),

        // QR code scan option
        Text('Secret OTP', style: context.text.titleMedium),
        if (widget.onToggleSaveSecret != null) ...[
          const SizedBox(height: 4),
          Text(
            'Scannez le QR code 2FA pour éviter de ressaisir un code à chaque '
            'connexion.',
            style: context.text.bodyMedium?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 10),

        InkWell(
          onTap: widget.isLoading ? null : widget.onScanQr,
          borderRadius: CampusRadii.cardRadius,
          child: Container(
            padding: const EdgeInsets.all(CampusSpacing.card),
            decoration: BoxDecoration(
              color: widget.scannedSecret != null
                  ? context.campus.positiveContainer
                  : context.scheme.surfaceContainer,
              border: Border.all(
                color: widget.scannedSecret != null
                    ? context.campus.positive
                    : context.scheme.outlineVariant,
              ),
              borderRadius: CampusRadii.cardRadius,
            ),
            child: Row(
              children: [
                Icon(
                  widget.scannedSecret != null
                      ? Icons.check_circle
                      : Icons.qr_code_scanner,
                  color: widget.scannedSecret != null
                      ? context.campus.positive
                      : context.scheme.onSurfaceVariant,
                ),
                const SizedBox(width: CampusSpacing.x4),
                Expanded(
                  child: Text(
                    widget.scannedSecret != null
                        ? 'Secret scanné'
                        : 'Scanner le QR code',
                    style: context.text.titleMedium?.copyWith(
                      color: widget.scannedSecret != null
                          ? context.campus.positive
                          : context.scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Optional save secret checkbox
        if (widget.onToggleSaveSecret != null) ...[
          const SizedBox(height: 8),
          CheckboxListTile(
            value: widget.saveSecret,
            onChanged: (v) => widget.onToggleSaveSecret!(v ?? false),
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Mémoriser le secret pour les prochaines connexions',
              style: context.text.bodyMedium,
            ),
            subtitle: Text(
              'Nécessaire pour la mise à jour automatique en arrière-plan.',
              style: context.text.labelMedium?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],

        // Optional auto-validate button
        if (widget.scannedSecret != null && widget.onAutoValidate != null) ...[
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: widget.isLoading
                ? null
                : () => widget.onAutoValidate!(widget.scannedSecret!),
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('Valider automatiquement'),
          ),
        ],
      ],
    );
  }
}
