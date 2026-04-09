import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'services/grades_service.dart';
import 'services/notification_service.dart';
import 'constants.dart';
import 'data.dart';
import 'models.dart';

const _taskUniqueName = 'grades_fetch';
const _taskName = 'grades_fetch_task';

// Secure storage instance (uses custom ciphers for security and background task compatibility).
const _secureStorage = FlutterSecureStorage();

// Log error for debugging while failing silently in production.
void _logError(String context, dynamic error, [StackTrace? stackTrace]) {
  if (kDebugMode) {
    debugPrint('[BackgroundTask] Error in $context: $error');
    if (stackTrace != null) debugPrint('Stack trace: $stackTrace');
  }
}

// WorkManager callback dispatcher — must be a top-level function.
// The OS spawns a fresh Dart isolate and calls this directly.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == _taskName) {
      try {
        await performBackgroundFetch();
      } catch (_) {
        return false; // Trigger WorkManager retry with backoff
      }
    }
    return true;
  });
}

// Perform one background fetch: fetch grades, compare to stored snapshot,
// and notify only if there's a change.
Future<void> performBackgroundFetch() async {
  try {
    // Check settings before initializing anything — cheapest exit possible
    final prefs = await SharedPreferences.getInstance();
    final fetchEnabled = prefs.getBool('background_fetch_enabled') ?? true;
    if (!fetchEnabled) {
      if (kDebugMode) {
        debugPrint('[BackgroundTask] Background fetch is disabled');
      }
      return;
    }

    // Notification init and credential reads are independent — run in parallel
    final initResults = await Future.wait([
      NotificationService.initialize(),
      _secureStorage.read(key: kStorageUser),
      _secureStorage.read(key: kStoragePass),
      _secureStorage.read(key: kStorageToken),
    ]);
    final username = initResults[1] as String?;
    final password = initResults[2] as String?;
    final secret = (initResults[3] as String?) ?? '';

    if (username == null || password == null) {
      _logError('performBackgroundFetch', 'Missing credentials');
      return;
    }

    if (kDebugMode) {
      debugPrint('[BackgroundTask] Fetching grades for user: $username');
      debugPrint(
        '[BackgroundTask] Secret/token ${secret.isEmpty ? "not found" : "loaded"}',
      );
    }

    // Read previous JSON before fetching — avoids writing to the same key concurrently
    final previousJson = await _secureStorage.read(key: 'stored_grades_json');
    final newJson = await GradesService.fetchGrades(username, password, secret);

    if (kDebugMode) {
      debugPrint('[BackgroundTask] Successfully fetched grades data');
    }

    await prefs.setString('last_fetch_time', DateTime.now().toIso8601String());

    // Fast path: raw string equality — skip all parsing if nothing changed
    if (previousJson == newJson) {
      if (kDebugMode) debugPrint('[BackgroundTask] No changes detected');
      return;
    }

    if (previousJson == null) {
      if (kDebugMode) debugPrint('[BackgroundTask] First fetch - data stored');
      return;
    }

    // Data changed — pass raw strings directly, no intermediate decode/re-encode
    final changes = _getChangedSubjectNames(previousJson, newJson);

    if (changes['new']!.isEmpty && changes['updated']!.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[BackgroundTask] Raw JSON changed but no grade changes — skipping notification',
        );
      }
      return;
    }

    if (kDebugMode) {
      if (changes['new']!.isNotEmpty) {
        debugPrint(
          '[BackgroundTask] New grade(s): ${changes['new']!.join(", ")}',
        );
      }
      if (changes['updated']!.isNotEmpty) {
        debugPrint(
          '[BackgroundTask] Updated grade(s): ${changes['updated']!.join(", ")}',
        );
      }
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
    final oldSubjects = _getAllSubjects(oldJsonString);
    final newSubjects = _getAllSubjects(newJsonString);

    final oldSubjectMap = <String, Subject>{
      for (final s in oldSubjects) s.name: s,
    };

    const equality = DeepCollectionEquality();

    for (final newSubject in newSubjects) {
      if (newSubject.grades.isEmpty) continue;

      final oldSubject = oldSubjectMap[newSubject.name];

      if (oldSubject == null || oldSubject.grades.isEmpty) {
        if (kDebugMode) {
          debugPrint('[BackgroundTask] New grade detected: ${newSubject.name}');
        }
        newGrades.add(newSubject.name);
      } else {
        if (!equality.equals(
          oldSubject.grades
              .map((g) => {'label': g.label, 'value': g.value})
              .toList(),
          newSubject.grades
              .map((g) => {'label': g.label, 'value': g.value})
              .toList(),
        )) {
          if (kDebugMode) {
            debugPrint('[BackgroundTask] Grade updated in: ${newSubject.name}');
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

// Initialize WorkManager and register the periodic grades fetch task.
Future<void> initBackgroundTasks() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final fetchInterval = prefs.getInt('background_fetch_interval') ?? 15;

    if (kDebugMode) {
      debugPrint(
        '[BackgroundTask] Initializing with interval: $fetchInterval minutes',
      );
    }

    await Workmanager().initialize(callbackDispatcher);

    await Workmanager().registerPeriodicTask(
      _taskUniqueName,
      _taskName,
      frequency: Duration(minutes: fetchInterval),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
    );

    if (kDebugMode) debugPrint('[BackgroundTask] Successfully registered');
  } catch (error, stackTrace) {
    _logError('initBackgroundTasks', error, stackTrace);
  }
}

// Cancel the periodic grades fetch task.
Future<void> stopBackgroundTasks() async {
  try {
    await Workmanager().cancelByUniqueName(_taskUniqueName);
    if (kDebugMode) debugPrint('[BackgroundTask] Successfully stopped');
  } catch (error, stackTrace) {
    _logError('stopBackgroundTasks', error, stackTrace);
  }
}
