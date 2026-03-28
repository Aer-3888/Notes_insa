import 'package:background_fetch/background_fetch.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

import 'services/grades_service.dart';
import 'services/notification_service.dart';
import 'data.dart';
import 'models.dart';

// Secure storage instance (uses custom ciphers for security and background task compatibility).
const _secureStorage = FlutterSecureStorage();

// Log error for debugging while failing silently in production.
void _logError(String context, dynamic error, [StackTrace? stackTrace]) {
  if (kDebugMode) {
    debugPrint('[BackgroundFetch] Error in $context: $error');
    if (stackTrace != null) {
      debugPrint('Stack trace: $stackTrace');
    }
  }
  // In production, errors are logged silently - could be extended to file logging or crash reporting.
}

// Headless background fetch entry point.
@pragma('vm:entry-point')
void backgroundFetchHeadlessTask(HeadlessTask task) async {
  final String taskId = task.taskId;
  final bool isTimeout = task.timeout;

  if (isTimeout) {
    _logError('backgroundFetchHeadlessTask', 'Task timed out: $taskId');
    BackgroundFetch.finish(taskId);
    return;
  }

  try {
    // performBackgroundFetch already initializes notifications internally
    await performBackgroundFetch();
  } catch (error, stackTrace) {
    _logError('backgroundFetchHeadlessTask', error, stackTrace);
  } finally {
    BackgroundFetch.finish(taskId);
  }
}

// Perform one background fetch: fetch grades, compare to stored snapshot,
// and notify only if there's a change.
Future<void> performBackgroundFetch() async {
  try {
    // Check settings before initializing anything — cheapest exit possible
    final prefs = await SharedPreferences.getInstance();
    final fetchEnabled = prefs.getBool('background_fetch_enabled') ?? true;
    if (!fetchEnabled) {
      if (kDebugMode)
        debugPrint('[BackgroundFetch] Background fetch is disabled');
      return;
    }

    // Notification init and credential reads are independent — run in parallel
    final initResults = await Future.wait([
      NotificationService.initialize(),
      _secureStorage.read(key: 'username'),
      _secureStorage.read(key: 'password'),
      _secureStorage.read(key: 'api_token'),
    ]);
    final username = initResults[1] as String?;
    final password = initResults[2] as String?;
    final secret = (initResults[3] as String?) ?? '';

    if (username == null || password == null) {
      _logError('performBackgroundFetch', 'Missing credentials');
      return;
    }

    if (kDebugMode) {
      debugPrint('[BackgroundFetch] Fetching grades for user: $username');
      debugPrint(
        '[BackgroundFetch] Secret/token ${secret.isEmpty ? "not found" : "loaded"}',
      );
    }

    // Read previous JSON before fetching — avoids writing to the same key concurrently
    final previousJson = await _secureStorage.read(key: 'stored_grades_json');
    final newJson = await GradesService.fetchGrades(username, password, secret);

    if (kDebugMode)
      debugPrint('[BackgroundFetch] Successfully fetched grades data');

    await prefs.setString('last_fetch_time', DateTime.now().toIso8601String());

    // Fast path: raw string equality — skip all parsing if nothing changed
    if (previousJson == newJson) {
      if (kDebugMode) debugPrint('[BackgroundFetch] No changes detected');
      return;
    }

    if (previousJson == null) {
      if (kDebugMode) debugPrint('[BackgroundFetch] First fetch - data stored');
      return;
    }

    // Data changed — pass raw strings directly, no intermediate decode/re-encode
    final changes = _getChangedSubjectNames(previousJson, newJson);

    if (changes['new']!.isEmpty && changes['updated']!.isEmpty) {
      if (kDebugMode)
        debugPrint(
          '[BackgroundFetch] Raw JSON changed but no grade changes — skipping notification',
        );
      return;
    }

    if (kDebugMode) {
      if (changes['new']!.isNotEmpty)
        debugPrint(
          '[BackgroundFetch] New grade(s): ${changes['new']!.join(", ")}',
        );
      if (changes['updated']!.isNotEmpty)
        debugPrint(
          '[BackgroundFetch] Updated grade(s): ${changes['updated']!.join(", ")}',
        );
    }

    if (changes['new']!.isNotEmpty) {
      await NotificationService.showNewGradesNotification(changes['new']!);
    }
    if (changes['updated']!.isNotEmpty) {
      await NotificationService.showUpdatedGradesNotification(
        changes['updated']!,
      );
    }
  } catch (error, stackTrace) {
    _logError('performBackgroundFetch', error, stackTrace);
  }
}

// Get all subjects with grades from parsed data across all semesters.
List<Subject> _getAllSubjects(String jsonData) {
  final allSubjects = <Subject>[];

  try {
    final availableSemesters = JsonCurriculumParser.getAvailableSemesters(
      jsonData,
    );

    for (final semesterNum in availableSemesters) {
      final units = JsonCurriculumParser.parseSemester(jsonData, semesterNum);

      for (final unit in units) {
        allSubjects.addAll(unit.subjects);
      }
    }
  } catch (error, stackTrace) {
    _logError('_getAllSubjects', error, stackTrace);
  }

  return allSubjects;
}

// Compare old and new subjects to find which ones are new vs updated.
Map<String, List<String>> _getChangedSubjectNames(
  String oldJsonString,
  String newJsonString,
) {
  final newGrades = <String>[];
  final updatedGrades = <String>[];

  try {
    // Parse into Subject objects using UI logic.
    final oldSubjects = _getAllSubjects(oldJsonString);
    final newSubjects = _getAllSubjects(newJsonString);

    // Create maps for easier comparison (key = subject name).
    final oldSubjectMap = <String, Subject>{};
    for (final subject in oldSubjects) {
      oldSubjectMap[subject.name] = subject;
    }

    const equality = DeepCollectionEquality();

    for (final newSubject in newSubjects) {
      if (newSubject.grades.isEmpty) {
        continue;
      }

      final oldSubject = oldSubjectMap[newSubject.name];

      if (oldSubject == null || oldSubject.grades.isEmpty) {
        // New subject or subject that previously had no grades.
        if (kDebugMode) {
          debugPrint(
            '[BackgroundFetch] New grade detected: ${newSubject.name}',
          );
        }
        newGrades.add(newSubject.name);
      } else {
        // Compare grades lists for existing subjects with grades.
        if (!equality.equals(
          oldSubject.grades
              .map((g) => {'label': g.label, 'value': g.value})
              .toList(),
          newSubject.grades
              .map((g) => {'label': g.label, 'value': g.value})
              .toList(),
        )) {
          if (kDebugMode) {
            debugPrint(
              '[BackgroundFetch] Grade updated in: ${newSubject.name}',
            );
          }
          updatedGrades.add(newSubject.name);
        }
      }
    }
  } catch (error, stackTrace) {
    _logError('_getChangedSubjectNames', error, stackTrace);
  }

  return {'new': newGrades, 'updated': updatedGrades};
}

// Configure and start background fetch with user-defined interval.
Future<void> initBackgroundTasks() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final fetchInterval = prefs.getInt('background_fetch_interval') ?? 15;

    if (kDebugMode) {
      debugPrint(
        '[BackgroundFetch] Initializing with interval: $fetchInterval minutes',
      );
    }

    await BackgroundFetch.configure(
      BackgroundFetchConfig(
        minimumFetchInterval: fetchInterval,
        stopOnTerminate: false,
        enableHeadless: true,
        startOnBoot: true,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresBatteryNotLow: false,
        requiresStorageNotLow: false,
        forceAlarmManager: false,
        requiredNetworkType: NetworkType.ANY,
      ),
      (String taskId) async {
        if (kDebugMode) debugPrint('[BackgroundFetch] Task triggered: $taskId');
        await performBackgroundFetch();
        BackgroundFetch.finish(taskId);
      },
      (String taskId) async {
        _logError(
          'initBackgroundTasks timeout handler',
          'Task timed out: $taskId',
        );
        BackgroundFetch.finish(taskId);
      },
    );

    BackgroundFetch.registerHeadlessTask(backgroundFetchHeadlessTask);
    await BackgroundFetch.start();

    if (kDebugMode) debugPrint('[BackgroundFetch] Successfully started');
  } catch (error, stackTrace) {
    _logError('initBackgroundTasks', error, stackTrace);
  }
}

// Stop background fetch tasks.
Future<void> stopBackgroundTasks() async {
  try {
    await BackgroundFetch.stop();
    if (kDebugMode) debugPrint('[BackgroundFetch] Successfully stopped');
  } catch (error, stackTrace) {
    _logError('stopBackgroundTasks', error, stackTrace);
  }
}
