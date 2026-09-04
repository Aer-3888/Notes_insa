import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/providers/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a missing preference yields the system mode', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer.test();
    expect(container.read(themeModeProvider), ThemeMode.system);
    await container.read(themeModeProvider.notifier).loaded;
    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test('the persisted mode is restored on build', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'theme_mode': 'dark',
    });
    final container = ProviderContainer.test();
    container.read(themeModeProvider);
    await container.read(themeModeProvider.notifier).loaded;
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('set updates state immediately and persists', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer.test();
    await container.read(themeModeProvider.notifier).set(ThemeMode.light);
    expect(container.read(themeModeProvider), ThemeMode.light);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'light');
  });

  test('an unknown stored value falls back to system', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'theme_mode': 'sepia',
    });
    final container = ProviderContainer.test();
    container.read(themeModeProvider);
    await container.read(themeModeProvider.notifier).loaded;
    expect(container.read(themeModeProvider), ThemeMode.system);
  });
}
