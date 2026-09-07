import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/providers/schedule_tint_provider.dart';
import 'package:notes_insa/theme/module_tints.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ScheduleTintChoice> restored(Map<String, Object> stored) async {
  SharedPreferences.setMockInitialValues(stored);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await container.read(scheduleTintProvider.notifier).loaded;
  return container.read(scheduleTintProvider);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to what shipped, so nothing repaints on update', () async {
    final choice = await restored(<String, Object>{});
    expect(choice.scheme, ScheduleTintScheme.spectre);
    expect(choice.intensity, ScheduleTintIntensity.standard);
  });

  test('restores a stored choice', () async {
    final choice = await restored(<String, Object>{
      ScheduleTintNotifier.schemeKey: 'accessible',
      ScheduleTintNotifier.intensityKey: 'vif',
    });
    expect(choice.scheme, ScheduleTintScheme.accessible);
    expect(choice.intensity, ScheduleTintIntensity.vif);
  });

  test('an unknown stored value falls back instead of throwing', () async {
    final choice = await restored(<String, Object>{
      ScheduleTintNotifier.schemeKey: 'chaud',
      ScheduleTintNotifier.intensityKey: 'assourdissant',
    });
    expect(choice.scheme, ScheduleTintScheme.spectre);
    expect(choice.intensity, ScheduleTintIntensity.standard);
  });

  test('a scheme change keeps the intensity, and survives a reload', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(scheduleTintProvider.notifier).loaded;

    await container
        .read(scheduleTintProvider.notifier)
        .setIntensity(ScheduleTintIntensity.discret);
    await container
        .read(scheduleTintProvider.notifier)
        .setScheme(ScheduleTintScheme.froid);

    expect(
      container.read(scheduleTintProvider),
      const ScheduleTintChoice(
        scheme: ScheduleTintScheme.froid,
        intensity: ScheduleTintIntensity.discret,
      ),
    );

    final reloaded = ProviderContainer();
    addTearDown(reloaded.dispose);
    await reloaded.read(scheduleTintProvider.notifier).loaded;
    expect(
      reloaded.read(scheduleTintProvider).scheme,
      ScheduleTintScheme.froid,
    );
    expect(
      reloaded.read(scheduleTintProvider).intensity,
      ScheduleTintIntensity.discret,
    );
  });
}
