import 'package:flutter/material.dart';
import '../../../../theme/campus_context.dart';
import '../../../../theme/tokens.dart';
import '../../../../components/credentials_fields.dart';
import '../widgets/slide_layout.dart';

class CredentialsSlide extends StatefulWidget {
  final TextEditingController userController;
  final TextEditingController passController;
  final VoidCallback onConnect;
  final bool isLoading;
  final String? error;
  final int stepCount;
  final int currentIndex;

  const CredentialsSlide({
    super.key,
    required this.userController,
    required this.passController,
    required this.onConnect,
    required this.isLoading,
    this.error,
    required this.stepCount,
    required this.currentIndex,
  });

  @override
  State<CredentialsSlide> createState() => _CredentialsSlideState();
}

class _CredentialsSlideState extends State<CredentialsSlide> {
  @override
  void initState() {
    super.initState();
    widget.userController.addListener(_rebuild);
    widget.passController.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.userController.removeListener(_rebuild);
    widget.passController.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        widget.userController.text.trim().isNotEmpty &&
        widget.passController.text.isNotEmpty;
    return SlideLayout(
      stepCount: widget.stepCount,
      currentIndex: widget.currentIndex,
      title: 'Connexion',
      subtitle: 'Utilisez vos identifiants du portail INSA.',
      isLoading: widget.isLoading,
      error: widget.error,
      primaryLabel: 'Se connecter',
      onPrimary: canSubmit ? widget.onConnect : null,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CredentialsFields(
            userController: widget.userController,
            passController: widget.passController,
            onSubmit: canSubmit ? widget.onConnect : null,
          ),
          const SizedBox(height: 28),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: context.scheme.onSurfaceVariant,
              ),
              const SizedBox(width: CampusSpacing.x3),
              Expanded(
                child: Text(
                  'Vos identifiants sont enregistrés dans le stockage '
                  'sécurisé de l’appareil.',
                  style: context.text.bodyMedium?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
