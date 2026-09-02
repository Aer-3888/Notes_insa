import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../services/auth_service.dart';

// Checks credentials only — pure read, no side effects.
// Invalidating this will force AuthGate to re-check the storage.
// Retry is disabled: an error here means "treat as logged out", and Riverpod 3
// would otherwise retry with backoff instead of surfacing it.
final hasCredentialsProvider = FutureProvider<bool>(
  (ref) async => AuthService().isLoggedIn(),
  retry: (_, _) => null,
);

// Session lock: false = locked (must pass biometric/PIN), true = unlocked.
// Starts locked on cold start and is reset to locked when the app is backgrounded,
// so the biometric/PIN gate is re-armed on every resume. Kept separate from
// AuthStatus so transient auth states (error/authenticated) can never bypass it.
final appUnlockedProvider = StateProvider<bool>((ref) => false);
