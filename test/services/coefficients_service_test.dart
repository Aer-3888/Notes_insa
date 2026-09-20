import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/constants.dart';
import 'package:notes_insa/services/averages_service.dart';
import 'package:notes_insa/services/coefficients_service.dart';
import 'package:notes_insa/services/grades_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  late Map<String, String> store;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    store = <String, String>{};
    messenger.setMockMethodCallHandler(storageChannel, (call) async {
      final args =
          (call.arguments as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final key = args['key'] as String?;
      switch (call.method) {
        case 'read':
          return store[key];
        case 'write':
          store[key!] = args['value'] as String;
          return null;
        case 'delete':
          store.remove(key);
          return null;
        case 'deleteAll':
          store.clear();
          return null;
        case 'readAll':
          return Map<String, String>.from(store);
        case 'containsKey':
          return store.containsKey(key);
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(storageChannel, null);
    GradesService.coefficientsOverride = null;
  });

  const dummyGradesJson = '''
  {
    "details": [
      {
        "name": "3INFO-SEMESTRE5",
        "details": [
          {
            "name": "UE 51",
            "details": [
              {
                "name": "Algorithmique",
                "score": ["14"]
              }
            ]
          }
        ]
      }
    ]
  }
  ''';

  test(
    'fetchAndCacheFromApi skips MDW when Tier 1 cache already has coefficients',
    () async {
      // Populate local cache for Semestre 5
      final cacheKey = semesterCacheKey(
        kStorageCoefficientsPrefix,
        '3INFO',
        5,
        AveragesService.currentAcademicYear(),
      );
      store[cacheKey] = jsonEncode({
        'ts': DateTime.now().millisecondsSinceEpoch,
        'coeffs': {'UE 51|Algorithmique': 2.0},
      });

      var mdwScrapeCalled = false;
      GradesService.coefficientsOverride = (_) async {
        mdwScrapeCalled = true;
        return '{"details": []}';
      };

      await CoefficientsService.fetchAndCacheFromApi(dummyGradesJson, 1);

      expect(mdwScrapeCalled, isFalse);
    },
  );

  test('fetchAndCacheFromApi calls MDW when cache misses', () async {
    var mdwScrapeCalled = false;
    GradesService.coefficientsOverride = (_) async {
      mdwScrapeCalled = true;
      return '{"details": []}';
    };

    await CoefficientsService.fetchAndCacheFromApi(dummyGradesJson, 1);

    expect(mdwScrapeCalled, isTrue);
  });

  test(
    'fetchAndCacheFromApi respects isCancelled before calling MDW',
    () async {
      var mdwScrapeCalled = false;
      GradesService.coefficientsOverride = (_) async {
        mdwScrapeCalled = true;
        return '{"details": []}';
      };

      await CoefficientsService.fetchAndCacheFromApi(
        dummyGradesJson,
        1,
        isCancelled: () => true,
      );

      expect(mdwScrapeCalled, isFalse);
    },
  );
}
