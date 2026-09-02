import 'package:flutter/material.dart';

import '../../app_colors.dart';

// Full-screen cover shown whenever the app is not in the foreground, so the OS
// task-switcher snapshot never reveals user data. Purely visual — the
// biometric/PIN lock route (LockController + gradesUnlockedProvider) is what
// actually re-gates access on resume.
class PrivacyCover extends StatefulWidget {
  final Widget child;
  const PrivacyCover({super.key, required this.child});

  @override
  State<PrivacyCover> createState() => _PrivacyCoverState();
}

class _PrivacyCoverState extends State<PrivacyCover>
    with WidgetsBindingObserver {
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Cover on anything that isn't a clean foreground (inactive/paused/hidden/
    // detached) — inactive fires before the snapshot is taken, so the snapshot
    // captures the curtain rather than the underlying screen.
    final obscured = state != AppLifecycleState.resumed;
    if (obscured != _obscured) setState(() => _obscured = obscured);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_obscured) const Positioned.fill(child: _PrivacyCurtain()),
      ],
    );
  }
}

// The opaque branded curtain itself — mirrors the splash screen.
class _PrivacyCurtain extends StatelessWidget {
  const _PrivacyCurtain();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.scaffoldBg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school, size: 72, color: AppColors.primary),
            SizedBox(height: 16),
            Text(
              'Campus INSA',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
