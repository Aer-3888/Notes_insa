import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/slide_layout.dart';

class PinSetupSlide extends StatefulWidget {
  final ValueChanged<String> onSetPin;
  final VoidCallback onSkip;
  final bool isLoading;
  final String? error;
  final int stepCount;
  final int currentIndex;
  final VoidCallback? onBack;

  const PinSetupSlide({
    super.key,
    required this.onSetPin,
    required this.onSkip,
    required this.isLoading,
    this.error,
    required this.stepCount,
    required this.currentIndex,
    this.onBack,
  });

  @override
  State<PinSetupSlide> createState() => _PinSetupSlideState();
}

class _PinSetupSlideState extends State<PinSetupSlide> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _pinMismatch = false;

  @override
  void initState() {
    super.initState();
    _pinController.addListener(_rebuild);
    _confirmController.addListener(_rebuild);
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _submit() {
    final pin = _pinController.text.trim();
    final confirm = _confirmController.text.trim();
    if (pin.length < 4 || pin != confirm) {
      setState(() => _pinMismatch = true);
      return;
    }
    widget.onSetPin(pin);
  }

  @override
  Widget build(BuildContext context) {
    final pinReady = _pinController.text.length >= 4;
    return SlideLayout(
      stepCount: widget.stepCount,
      currentIndex: widget.currentIndex,
      onBack: widget.onBack,
      title: 'Sécurisez\nl\'accès',
      subtitle: 'Créez un code PIN pour protéger vos notes',
      isLoading: widget.isLoading,
      error: widget.error,
      primaryLabel: 'Continuer',
      onPrimary: pinReady ? _submit : null,
      secondaryLabel: 'Passer',
      onSecondary: widget.onSkip,
      content: Column(
        children: [
          TextField(
            controller: _pinController,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() => _pinMismatch = false),
            decoration: const InputDecoration(
              labelText: 'Code PIN (4–8 chiffres)',
              border: OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirmController,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) {
              if (pinReady) _submit();
            },
            onChanged: (_) => setState(() => _pinMismatch = false),
            decoration: InputDecoration(
              labelText: 'Confirmer le code PIN',
              border: const OutlineInputBorder(),
              counterText: '',
              errorText: _pinMismatch
                  ? 'Les codes PIN ne correspondent pas ou sont trop courts'
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
