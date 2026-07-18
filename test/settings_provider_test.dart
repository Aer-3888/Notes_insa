import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notes_insa/providers/settings_provider.dart';

/// Waits for the async `_loadSettings()` kicked off in the notifier constructor.
Future<SettingsState> _loaded(ProviderContainer container) async {
  for (var i = 0; i < 100; i++) {
    final s = container.read(settingsProvider);
    if (!s.isLoading) return s;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return container.read(settingsProvider);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const nativeChannel = MethodChannel('com.aer.notes_insa/grades');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(nativeChannel, null);
  });

  test('sharing consent defaults to false when never set (opt-in)', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final s = await _loaded(container);
    expect(s.isLoading, isFalse);
    expect(s.sharingConsent, isFalse);
    expect(s.sharingConsentAsked, isFalse);
  });

  test('explicit stored consent is respected', () async {
    SharedPreferences.setMockInitialValues({
      'sharing_consent': true,
      'sharing_consent_asked': true,
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final s = await _loaded(container);
    expect(s.sharingConsent, isTrue);
    expect(s.sharingConsentAsked, isTrue);
  });

  test('an explicit false is preserved', () async {
    SharedPreferences.setMockInitialValues({'sharing_consent': false});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final s = await _loaded(container);
    expect(s.sharingConsent, isFalse);
  });

  test('failed background cancellation restores enabled preference', () async {
    SharedPreferences.setMockInitialValues({'background_fetch_enabled': true});
    messenger.setMockMethodCallHandler(nativeChannel, (call) async {
      if (call.method == 'StopBackgroundTask') {
        throw PlatformException(code: 'schedule_failed');
      }
      return null;
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _loaded(container);

    await expectLater(
      container.read(settingsProvider.notifier).setFetchEnabled(false),
      throwsA(isA<PlatformException>()),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('background_fetch_enabled'), isTrue);
    expect(container.read(settingsProvider).fetchEnabled, isTrue);
  });

  test('disabling fetch clears account-scoped failure state', () async {
    SharedPreferences.setMockInitialValues({
      'background_fetch_enabled': true,
      'background_failure_started_at_ms': 1000,
      'last_background_failure_alert_ms': 2000,
      'consecutive_auth_failures': 2,
    });
    messenger.setMockMethodCallHandler(nativeChannel, (_) async => null);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _loaded(container);

    await container.read(settingsProvider.notifier).setFetchEnabled(false);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('background_fetch_enabled'), isFalse);
    expect(prefs.get('background_failure_started_at_ms'), isNull);
    expect(prefs.get('last_background_failure_alert_ms'), isNull);
    expect(prefs.get('consecutive_auth_failures'), isNull);
  });
}
