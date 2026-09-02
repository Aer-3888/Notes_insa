import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../modules/grades/onboarding/onboarding_screen.dart';
import '../../providers/auth_providers.dart';
import 'splash_screens.dart';

/// Wraps a module that needs INSA credentials. Modules without `requiresCas`
/// never see this.
///
/// The biometric/PIN lock is not here: it is a route pushed on the root
/// navigator by LockController, so it can sit above sheets and dialogs this
/// module opens.
class CasGuard extends ConsumerWidget {
  const CasGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(hasCredentialsProvider)
        .when(
          loading: () => const SplashScreen(),
          error: (_, _) => const OnboardingScreen(),
          data: (hasCreds) => hasCreds ? child : const OnboardingScreen(),
        );
  }
}
