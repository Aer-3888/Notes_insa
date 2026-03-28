import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import '../services/grades_service.dart';
import '../services/auth_service.dart';

/// Grades state that holds the raw JSON data from the API.
class GradesState {
  final String jsonData;
  final DateTime? lastUpdated;
  final bool isLoading;
  final String? error;

  const GradesState({
    this.jsonData = '{}',
    this.lastUpdated,
    this.isLoading = false,
    this.error,
  });

  GradesState copyWith({
    String? jsonData,
    DateTime? lastUpdated,
    bool? isLoading,
    String? error,
  }) {
    return GradesState(
      jsonData: jsonData ?? this.jsonData,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  bool get hasData => jsonData != '{}' && jsonData.isNotEmpty;
}

/// Notifier to manage grades state.
class GradesNotifier extends StateNotifier<GradesState> {
  GradesNotifier() : super(const GradesState());

  /// Load grades from local secure storage.
  Future<void> loadStoredGrades() async {
    try {
      final gradesService = GradesService();
      final storedData = await gradesService.getLastSavedGrades();

      if (storedData != null) {
        final jsonString = json.encode(storedData);
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

  /// Clear all grades data (called on logout).
  void clearGrades() {
    state = const GradesState(jsonData: '{}');
  }

  /// Update grades data directly (used by background tasks).
  void updateGradesData(String jsonData) {
    state = state.copyWith(jsonData: jsonData, lastUpdated: DateTime.now());
  }
}

/// Provider for grades state.
final gradesProvider = StateNotifierProvider<GradesNotifier, GradesState>((
  ref,
) {
  return GradesNotifier();
});
