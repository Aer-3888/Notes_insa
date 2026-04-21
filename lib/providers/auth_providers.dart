import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';

// Checks credentials only — pure read, no side effects.
// Invalidating this will force AuthGate to re-check the storage.
final hasCredentialsProvider = FutureProvider<bool>((ref) async {
  return AuthService().isLoggedIn();
});
