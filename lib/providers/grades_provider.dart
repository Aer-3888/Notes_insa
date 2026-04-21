import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../services/grades_service.dart';
import '../services/coefficients_service.dart';
import '../services/auth_service.dart';
import '../constants.dart';

enum AuthStatus {
  unauthenticated,
  authenticating,
  twoFactorRequired,
  authenticated,
  error,
}

/// Grades state that holds the raw JSON data from the API.
class GradesState {
  final String jsonData;
  final DateTime? lastUpdated;
  final bool isLoading;
  final String? error;
  final bool needsReauth;
  final DateTime? lastManualRefresh;
  final AuthStatus authStatus;

  const GradesState({
    this.jsonData = '{}',
    this.lastUpdated,
    this.isLoading = false,
    this.error,
    this.needsReauth = false,
    this.lastManualRefresh,
    this.authStatus = AuthStatus.unauthenticated,
  });

  static const _keep = Object();

  GradesState copyWith({
    String? jsonData,
    Object? lastUpdated = _keep,
    bool? isLoading,
    String? error,
    bool? needsReauth,
    Object? lastManualRefresh = _keep,
    AuthStatus? authStatus,
  }) {
    return GradesState(
      jsonData: jsonData ?? this.jsonData,
      lastUpdated:
          lastUpdated == _keep ? this.lastUpdated : lastUpdated as DateTime?,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      needsReauth: needsReauth ?? this.needsReauth,
      lastManualRefresh:
          lastManualRefresh == _keep
              ? this.lastManualRefresh
              : lastManualRefresh as DateTime?,
      authStatus: authStatus ?? this.authStatus,
    );
  }

  bool get hasData => jsonData != '{}' && jsonData.isNotEmpty;

  /// Returns null if refresh is allowed, or the remaining cooldown duration.
  Duration? get manualRefreshCooldown {
    if (lastManualRefresh == null) return null;
    final elapsed = DateTime.now().difference(lastManualRefresh!);
    const cooldown = Duration(seconds: 30);
    if (elapsed >= cooldown) return null;
    return cooldown - elapsed;
  }
}

/// Notifier to manage grades state.
class GradesNotifier extends StateNotifier<GradesState> {
  GradesNotifier() : super(const GradesState());

  /// Load grades from local secure storage.
  Future<void> loadStoredGrades() async {
    try {
      final jsonString = await GradesService.getLastSavedGrades();
      if (jsonString != null) {
        state = state.copyWith(
          jsonData: jsonString,
          lastUpdated: DateTime.now(),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GradesProvider] Failed to load stored grades: $e');
      }
    }
  }

  /// Fetch grades after auth + optional 2FA are already complete.
  /// Called from the login screen once the full auth flow has succeeded.
  /// Also exports the CAS session so the next launch can skip re-auth.
  Future<void> fetchGradesAfterAuth() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      // Export session before fetching — captures the authenticated state
      try {
        final sessionToken = await GradesService.exportCAS();
        await AuthService().storeCasSession(sessionToken);
      } catch (_) {
        // Non-fatal — session just won't be restored next time
      }

      final result = await GradesService.fetchAndSaveGrades();
      await CoefficientsService.fetchAndCacheFromApi(result);
      state = state.copyWith(
        jsonData: result,
        lastUpdated: DateTime.now(),
        isLoading: false,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  /// Fetch grades using stored credentials, handling the full re-auth flow.
  /// Tries to restore the previous CAS session first — if still authenticated,
  /// skips re-auth entirely. Falls back to full auth if the session expired.
  /// If 2FA is required and no OTP secret is stored, sets an error state.
  Future<void> fetchGradesWithStoredCredentials() async {
    final authService = AuthService();
    final credentials = await authService.getCredentials();

    if (credentials == null) {
      state = state.copyWith(isLoading: false, error: 'No stored credentials');
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      // Try to restore the previous session — avoids re-auth when still valid
      final savedSession = await authService.getCasSession();
      if (savedSession != null) {
        try {
          await GradesService.importCAS(savedSession);
        } catch (_) {
          // Corrupt or incompatible token — fall back to fresh session
          await authService.deleteCasSession();
          await GradesService.newCAS();
        }
      } else {
        await GradesService.newCAS();
      }

      // Check if the restored session is still authenticated
      final authenticated = await GradesService.isAuthenticated();
      if (!authenticated) {
        // Session expired — need to re-auth (usually no 2FA after ImportCAS)
        await GradesService.auth(
          credentials[kStorageUser]!,
          credentials[kStoragePass]!,
        );

        final needs2fa = await GradesService.isTokenNeeded();
        if (needs2fa) {
          final secret = await authService.getOtpSecret();
          if (secret == null) {
            state = state.copyWith(
              isLoading: false,
              error: '2FA required',
              needsReauth: true,
            );
            return;
          }
          await GradesService.autoValidate(secret);
        }
      }

      // Export the (possibly refreshed) session for next time
      try {
        final sessionToken = await GradesService.exportCAS();
        await authService.storeCasSession(sessionToken);
      } catch (_) {
        // Non-fatal
      }

      final result = await GradesService.fetchAndSaveGrades();
      await CoefficientsService.fetchAndCacheFromApi(result);
      state = state.copyWith(
        jsonData: result,
        lastUpdated: DateTime.now(),
        isLoading: false,
        error: null,
        needsReauth: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  /// Manual refresh — enforces a 30-second cooldown and ignores requests
  /// while a fetch is already in progress.
  /// Returns true if the refresh was started, false otherwise.
  Future<bool> manualRefresh() async {
    if (state.isLoading) return false;
    if (state.manualRefreshCooldown != null) return false;
    state = state.copyWith(lastManualRefresh: DateTime.now());
    unawaited(fetchGradesWithStoredCredentials().catchError((_) {}));
    return true;
  }

  /// Clear all grades data (called on logout).
  void clearGrades() {
    state = const GradesState();
  }
}

/// Provider for grades state.
final gradesProvider = StateNotifierProvider<GradesNotifier, GradesState>((
  ref,
) {
  return GradesNotifier();
});
