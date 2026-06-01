import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';

// Checks credentials only — pure read, no side effects.
// Invalidating this will force AuthGate to re-check the storage.
final hasCredentialsProvider = FutureProvider<bool>((ref) async {
  return AuthService().isLoggedIn();
});

// Session lock: false = locked (must pass biometric/PIN), true = unlocked.
// Starts locked on cold start and is reset to locked when the app is backgrounded,
// so the biometric/PIN gate is re-armed on every resume. Kept separate from
// AuthStatus so transient auth states (error/authenticated) can never bypass it.
final appUnlockedProvider = StateProvider<bool>((ref) => false);
