import 'package:flutter_riverpod/flutter_riverpod.dart';
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
}
