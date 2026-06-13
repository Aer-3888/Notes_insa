import 'package:flutter/material.dart';
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
  bool _obscurePass = true;

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
      title: 'Relevé',
      subtitle: 'Connectez-vous à votre compte',
      isLoading: widget.isLoading,
      error: widget.error,
      primaryLabel: 'Se connecter',
      onPrimary: canSubmit ? widget.onConnect : null,
      content: AutofillGroup(
        child: Column(
          children: [
            TextField(
              controller: widget.userController,
              autofillHints: const [AutofillHints.username],
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Identifiant INSA',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: widget.passController,
              autofillHints: const [AutofillHints.password],
              obscureText: _obscurePass,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (canSubmit) widget.onConnect();
              },
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePass
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
