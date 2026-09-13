import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../services/auth_service.dart';

// Checks credentials only, pure read, no side effects.
// Invalidating this will force CasGuard to re-check the storage.
// Retry is disabled: an error here means "treat as logged out", and Riverpod 3
// would otherwise retry with backoff instead of surfacing it.
final hasCredentialsProvider = FutureProvider<bool>(
  (ref) async => AuthService().isLoggedIn(),
  retry: (_, _) => null,
);

// Grades module lock: false = locked (must pass biometric/PIN), true = unlocked.
// Starts locked on cold start and is reset to locked when the app is
// backgrounded. It gates the grades module only, since the hub, timetable and
// weather are open. Kept separate from AuthStatus so transient auth states
// (error/authenticated) can never bypass it.
final gradesUnlockedProvider = StateProvider<bool>((ref) => false);
