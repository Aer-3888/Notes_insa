import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_colors.dart';
import '../../modules/grades/grades_provider.dart';
import 'biometric_screen.dart';
import 'pin_screen.dart';

/// Marker for the opaque full-screen barrier the lock renders behind. Tests
/// assert against this to prove nothing sensitive sits above the lock.
class LockBarrier extends StatelessWidget {
  const LockBarrier({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: ColoredBox(color: AppColors.scaffoldBg, child: child),
  );
}

/// The biometric/PIN gate, pushed as a route on the root navigator so it sits
/// above every sheet and dialog a module may have opened.
class LockScreen extends ConsumerWidget {
  const LockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needsPin =
        ref.watch(gradesProvider).authStatus == AuthStatus.pinRequired;
    return PopScope(
      canPop: false,
      child: LockBarrier(
        child: needsPin ? const PinScreen() : const BiometricScreen(),
      ),
    );
  }
}
