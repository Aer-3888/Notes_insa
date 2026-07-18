import 'package:flutter/material.dart';

/// Shared credentials input used by the connect flow: the username + password
/// fields with the password's obscure toggle, kept in one place so every
/// connection entry point stays in sync.
///
/// Callers own the [TextEditingController]s (so they can compute submit state)
/// and provide the action button themselves; this widget only renders the two
/// fields.
class CredentialsFields extends StatefulWidget {
  final TextEditingController userController;
  final TextEditingController passController;

  /// Invoked when the user presses "done" on the password field (e.g. submit).
  final VoidCallback? onSubmit;

  final String usernameLabel;

  const CredentialsFields({
    super.key,
    required this.userController,
    required this.passController,
    this.onSubmit,
    this.usernameLabel = 'Identifiant INSA',
  });

  @override
  State<CredentialsFields> createState() => _CredentialsFieldsState();
}

class _CredentialsFieldsState extends State<CredentialsFields> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(widget.usernameLabel),
          const SizedBox(height: 8),
          TextField(
            controller: widget.userController,
            autofillHints: const [AutofillHints.username],
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(hintText: 'prenom.nom'),
          ),
          const SizedBox(height: 6),
          Text(
            'Le même identifiant que sur le portail INSA',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          const _FieldLabel('Mot de passe'),
          const SizedBox(height: 8),
          TextField(
            controller: widget.passController,
            autofillHints: const [AutofillHints.password],
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => widget.onSubmit?.call(),
            decoration: InputDecoration(
              hintText: 'Votre mot de passe INSA',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
                tooltip: _obscure
                    ? 'Afficher le mot de passe'
                    : 'Masquer le mot de passe',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
