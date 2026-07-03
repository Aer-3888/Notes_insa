import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../services/grades_service.dart';
import '../services/coefficients_service.dart';
import '../services/averages_service.dart';
import '../services/auth_service.dart';
import '../services/worker_sync_service.dart';
import '../constants.dart';
import 'coefficients_provider.dart';

enum AuthStatus {
  unauthenticated,
  authenticating,
  pinRequired,
  twoFactorRequired,
  authenticated,
  error,
}

/// Outcome of [GradesNotifier.prepareReauth], used by the 2FA screen to decide
/// whether to show the code form, leave (already authenticated), or surface an
/// error.
enum ReauthPrep {
  /// A fresh CAS challenge is pending; the server expects a 2FA token.
  tokenRequired,

  /// The stored credentials authenticated without needing a token.
  authenticated,

  /// No stored credentials to authenticate with.
  noCredentials,

  /// newCAS/auth failed (wrong password or network).
  failed,
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

  /// Academic year of the current snapshot (e.g. "2025-2026"), frozen at fetch
  /// time. Null until grades are loaded/fetched; consumers fall back to the
  /// current wall-clock academic year.
  final String? academicYearBaseline;

  const GradesState({
    this.jsonData = '{}',
    this.lastUpdated,
    this.isLoading = false,
    this.error,
    this.needsReauth = false,
    this.lastManualRefresh,
    this.authStatus = AuthStatus.unauthenticated,
    this.academicYearBaseline,
  });

  static const _keep = Object();

  GradesState copyWith({
    String? jsonData,
    Object? lastUpdated = _keep,
    bool? isLoading,
    Object? error = _keep,
    bool? needsReauth,
    Object? lastManualRefresh = _keep,
    AuthStatus? authStatus,
    String? academicYearBaseline,
  }) {
    return GradesState(
      jsonData: jsonData ?? this.jsonData,
      lastUpdated: lastUpdated == _keep
          ? this.lastUpdated
          : lastUpdated as DateTime?,
      isLoading: isLoading ?? this.isLoading,
      error: error == _keep ? this.error : error as String?,
      needsReauth: needsReauth ?? this.needsReauth,
      lastManualRefresh: lastManualRefresh == _keep
          ? this.lastManualRefresh
          : lastManualRefresh as DateTime?,
      authStatus: authStatus ?? this.authStatus,
      academicYearBaseline: academicYearBaseline ?? this.academicYearBaseline,
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
  GradesNotifier(this._ref) : super(const GradesState());

  final Ref _ref;

  /// Single-flight guard: while a fetch sequence is running, additional callers
  /// await the same future instead of starting a second sequence. This prevents
  /// concurrent native CAS-session calls (e.g. biometric + PIN + resume) from
  /// interleaving and corrupting the shared session.
  Future<void>? _inFlight;

  Future<void> _runExclusive(Future<void> Function() body) {
    final existing = _inFlight;
    if (existing != null) return existing;
    // body() runs synchronously up to its first await before returning the
    // future, so loading/auth state is set before _inFlight is observed.
    final future = body();
    _inFlight = future;
    future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    return future;
  }

  /// Load grades from local secure storage.
  Future<void> loadStoredGrades() async {
    try {
      // The background worker writes a newer snapshot only to its own store
      // (the Flutter→worker mirror is one-way), so adopt it here when it's
      // newer than our local copy before reading.
      await _adoptWorkerGradesIfNewer();

      final jsonString = await GradesService.getLastSavedGrades();
      if (jsonString != null) {
        final baseline = await AveragesService.loadAcademicYearBaseline();
        // Only re-stamp lastUpdated when the snapshot actually changed, so
        // foregrounding the app doesn't reset "updated just now" each time.
        if (jsonString != state.jsonData) {
          state = state.copyWith(
            jsonData: jsonString,
            lastUpdated: DateTime.now(),
            academicYearBaseline: baseline,
          );
        } else {
          state = state.copyWith(academicYearBaseline: baseline);
        }
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
  Future<void> fetchGradesAfterAuth() => _runExclusive(_fetchGradesAfterAuth);

  Future<void> _fetchGradesAfterAuth() async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      authStatus: AuthStatus.authenticated,
    );
    try {
      // Export session before fetching — captures the authenticated state
      try {
        final sessionToken = await GradesService.exportCAS();
        await AuthService().storeCasSession(sessionToken);
      } catch (_) {
        // Non-fatal — session just won't be restored next time
      }

      final fetched = await GradesService.fetchAndSaveGrades();
      // Freeze the academic-year baseline for this snapshot before caching
      // coefficients, which derives per-semester years from it.
      await AveragesService.persistAcademicYearBaseline();
      // Show grades immediately — the loading pill hides here. Weighted averages
      // fill in once coefficients arrive (semesterAverageProvisional bridges the
      // gap with an unweighted value in the meantime).
      state = state.copyWith(
        jsonData: fetched.json,
        lastUpdated: DateTime.now(),
        isLoading: false,
        error: null,
        authStatus: AuthStatus.authenticated,
        needsReauth: false,
        academicYearBaseline: AveragesService.currentAcademicYear(),
      );
      await _refreshCoefficients(fetched.json, fetched.groupCount);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        authStatus: AuthStatus.error,
      );
      rethrow;
    }
  }

  /// Fetch grades using stored credentials, handling the full re-auth flow.
  /// Tries to restore the previous CAS session first — if still authenticated,
  /// skips re-auth entirely. Falls back to full auth if the session expired.
  /// If 2FA is required and no OTP secret is stored, sets an error state.
  Future<void> fetchGradesWithStoredCredentials() =>
      _runExclusive(_fetchGradesWithStoredCredentials);

  /// Establishes a fresh CAS 2FA challenge for the reconnect screen so a code
  /// entered there validates even if the previous challenge lapsed or none was
  /// pending (e.g. the screen was reached via a notification deep-link after a
  /// cold start). Runs newCAS + auth(stored credentials) and reports whether the
  /// server now expects a token. Does not mutate grades state.
  ///
  /// Serialized against fetches through the same single-flight guard so the two
  /// don't interleave native CAS calls: waits for any in-flight sequence, then
  /// holds the guard for its own run.
  Future<ReauthPrep> prepareReauth() async {
    while (_inFlight != null) {
      try {
        await _inFlight;
      } catch (_) {}
    }
    final gate = Completer<void>();
    _inFlight = gate.future;
    try {
      return await _prepareReauth();
    } finally {
      if (identical(_inFlight, gate.future)) _inFlight = null;
      gate.complete();
    }
  }

  Future<ReauthPrep> _prepareReauth() async {
    final credentials = await AuthService().getCredentials();
    if (credentials == null) return ReauthPrep.noCredentials;
    try {
      await GradesService.newCAS();
      await GradesService.auth(
        credentials[kStorageUser]!,
        credentials[kStoragePass]!,
      );
      final needs2fa = await GradesService.isTokenNeeded();
      return needs2fa ? ReauthPrep.tokenRequired : ReauthPrep.authenticated;
    } catch (_) {
      return ReauthPrep.failed;
    }
  }

  Future<void> _fetchGradesWithStoredCredentials() async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      authStatus: AuthStatus.authenticating,
    );

    final authService = AuthService();
    final credentials = await authService.getCredentials();

    if (credentials == null) {
      state = state.copyWith(
        isLoading: false,
        error: 'No stored credentials',
        authStatus: AuthStatus.unauthenticated,
      );
      return;
    }

    try {
      // The background worker rotates the CAS session (and grades snapshot)
      // directly in its own store after a headless re-auth, but has no way to
      // mirror that back to flutter_secure_storage (see WorkerSyncService).
      // Adopt its copy first so we restore the session the server currently
      // recognizes — otherwise importCAS below fails on our stale copy, which
      // forces a redundant full re-auth + 2FA cycle (and risks the OTP server
      // rejecting a replayed TOTP code from the same time-step the worker just
      // used, surfacing as "2FA required" despite a valid stored secret).
      await _adoptWorkerCasSession(authService);

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
              authStatus: AuthStatus.twoFactorRequired,
            );
            return;
          }
          try {
            await GradesService.autoValidate(secret);
          } catch (_) {
            // Secret invalid or expired - trigger manual re-auth
            state = state.copyWith(
              isLoading: false,
              error: '2FA required (auto-validate failed)',
              needsReauth: true,
              authStatus: AuthStatus.twoFactorRequired,
            );
            return;
          }
        }
      }

      // Export the (possibly refreshed) session for next time
      try {
        final sessionToken = await GradesService.exportCAS();
        await authService.storeCasSession(sessionToken);
      } catch (_) {
        // Non-fatal
      }

      final fetched = await GradesService.fetchAndSaveGrades();
      // Freeze the academic-year baseline for this snapshot before caching
      // coefficients, which derives per-semester years from it.
      await AveragesService.persistAcademicYearBaseline();
      // Show grades immediately — the loading pill hides here. Weighted averages
      // fill in once coefficients arrive (semesterAverageProvisional bridges the
      // gap with an unweighted value in the meantime).
      state = state.copyWith(
        jsonData: fetched.json,
        lastUpdated: DateTime.now(),
        isLoading: false,
        error: null,
        needsReauth: false,
        authStatus: AuthStatus.authenticated,
        academicYearBaseline: AveragesService.currentAcademicYear(),
      );
      await _refreshCoefficients(fetched.json, fetched.groupCount);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        authStatus: AuthStatus.error,
      );
      rethrow;
    }
  }

  /// Pulls the CAS session from the native worker store and adopts it locally
  /// if it differs from ours. [storeCasSession] always mirrors forward to the
  /// worker store, so a mismatch can only mean the worker rotated its copy
  /// behind our back — its version is the one the server currently honors.
  /// Best-effort: any failure leaves the existing session untouched.
  Future<void> _adoptWorkerCasSession(AuthService authService) async {
    try {
      final values = await WorkerSyncService.read([
        WorkerSyncService.keyCasSession,
      ]);
      final workerSession = values?[WorkerSyncService.keyCasSession];
      if (workerSession == null) return;
      if (workerSession != await authService.getCasSession()) {
        await authService.storeCasSession(workerSession);
      }
    } catch (_) {
      // Fall back to whatever session we already have
    }
  }

  /// Fetches coefficients and drops the cached provider results so weighted
  /// averages replace the provisional unweighted ones shown right after grades
  /// load. Runs after the grades state is already set, but is awaited by the
  /// caller so it stays inside the single-flight section — native CAS calls
  /// (used by the coefficients fetch) must not interleave with a concurrent
  /// fetch. Non-fatal: on failure the averages simply stay provisional.
  Future<void> _refreshCoefficients(String gradesJson, int groupCount) async {
    try {
      await CoefficientsService.fetchAndCacheFromApi(gradesJson, groupCount);
      _ref.invalidate(coefficientsProvider);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GradesProvider] coefficient refresh failed: $e');
      }
    }
  }

  /// Pulls the grades snapshot from the worker store and adopts it locally when
  /// its timestamp is newer than ours — the background worker rotates the
  /// snapshot in its own store and has no way to mirror it back to
  /// flutter_secure_storage. Best-effort: any failure leaves the local copy.
  Future<void> _adoptWorkerGradesIfNewer() async {
    try {
      final localUpdatedAt = await GradesService.getLastSavedUpdatedAt();
      final values = await WorkerSyncService.read([
        WorkerSyncService.keyGradesJson,
        WorkerSyncService.keyGradesUpdatedAt,
      ]);
      if (values == null) return;

      final workerJson = values[WorkerSyncService.keyGradesJson];
      if (workerJson == null || workerJson.isEmpty) return;
      final workerUpdatedAt = int.tryParse(
        values[WorkerSyncService.keyGradesUpdatedAt] ?? '',
      );
      if (workerUpdatedAt == null) return;

      // Only adopt when strictly newer; equal timestamps mean the worker copy
      // is just our own mirror.
      if (localUpdatedAt != null && workerUpdatedAt <= localUpdatedAt) return;

      await GradesService.adoptGrades(workerJson, workerUpdatedAt);
    } catch (_) {
      // Keep whatever we already have.
    }
  }

  /// Manual refresh — enforces a 30-second cooldown and ignores requests
  /// while a fetch is already in progress.
  /// Returns true if the refresh was started, false otherwise.
  Future<bool> manualRefresh() async {
    if (state.isLoading) return false;
    if (state.manualRefreshCooldown != null) return false;
    state = state.copyWith(lastManualRefresh: DateTime.now(), error: null);
    unawaited(fetchGradesWithStoredCredentials().catchError((_) {}));
    return true;
  }

  /// Clear all grades data (called on logout).
  void clearGrades() {
    state = const GradesState();
  }

  /// Manually trigger a PIN requirement in the UI.
  void setPinRequired() {
    state = state.copyWith(authStatus: AuthStatus.pinRequired);
  }
}

/// Provider for grades state.
final gradesProvider = StateNotifierProvider<GradesNotifier, GradesState>((
  ref,
) {
  return GradesNotifier(ref);
});
