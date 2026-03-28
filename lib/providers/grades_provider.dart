import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../services/grades_service.dart';
import '../services/auth_service.dart';

/// Grades state that holds the raw JSON data from the API.
class GradesState {
  final String jsonData;
  final DateTime? lastUpdated;
  final bool isLoading;
  final String? error;
  final DateTime? lastManualRefresh;

  const GradesState({
    this.jsonData = '{}',
    this.lastUpdated,
    this.isLoading = false,
    this.error,
    this.lastManualRefresh,
  });

  GradesState copyWith({
    String? jsonData,
    DateTime? lastUpdated,
    bool? isLoading,
    String? error,
    DateTime? lastManualRefresh,
  }) {
    return GradesState(
      jsonData: jsonData ?? this.jsonData,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      lastManualRefresh: lastManualRefresh ?? this.lastManualRefresh,
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
      final gradesService = GradesService();
      final jsonString = await gradesService.getLastSavedGrades();

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

  /// Fetch fresh grades from the API using stored credentials.
  Future<void> fetchGrades(
    String username,
    String password,
    String secret,
  ) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await GradesService.fetchGrades(
        username,
        password,
        secret,
      );

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

  /// Fetch grades using stored credentials from AuthService.
  Future<void> fetchGradesWithStoredCredentials() async {
    final authService = AuthService();
    final credentials = await authService.getCredentials();

    if (credentials == null) {
      state = state.copyWith(isLoading: false, error: 'No stored credentials');
      return;
    }

    await fetchGrades(
      credentials['username']!,
      credentials['password']!,
      credentials['token']!,
    );
  }

  /// Manual refresh — enforces a 30-second cooldown and ignores requests
  /// while a fetch is already in progress.
  /// Fires the fetch without awaiting so the RefreshIndicator spinner
  /// dismisses immediately on release; the pill handles loading feedback.
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
    state = const GradesState(jsonData: '{}');
  }
}

/// Provider for grades state.
final gradesProvider = StateNotifierProvider<GradesNotifier, GradesState>((
  ref,
) {
  return GradesNotifier();
});
