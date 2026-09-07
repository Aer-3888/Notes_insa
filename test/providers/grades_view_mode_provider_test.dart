import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/providers/grades_view_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to cards and tolerates an unknown saved mode', () async {
    SharedPreferences.setMockInitialValues({kGradesViewModeKey: 'unknown'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(gradesViewModeProvider), GradesViewMode.cartes);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(gradesViewModeProvider), GradesViewMode.cartes);
  });

  test('selection survives a new provider container', () async {
    final first = ProviderContainer();
    await first
        .read(gradesViewModeProvider.notifier)
        .set(GradesViewMode.synthese);
    first.dispose();

    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    restored.read(gradesViewModeProvider);
    await Future<void>.delayed(Duration.zero);
    expect(restored.read(gradesViewModeProvider), GradesViewMode.synthese);
  });

  test(
    'an immediate selection wins over restoring an older preference',
    () async {
      SharedPreferences.setMockInitialValues({kGradesViewModeKey: 'synthese'});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(gradesViewModeProvider.notifier)
          .set(GradesViewMode.liste);
      expect(container.read(gradesViewModeProvider), GradesViewMode.liste);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kGradesViewModeKey), 'liste');
    },
  );

  test('disposing during restore is safe', () async {
    SharedPreferences.setMockInitialValues({kGradesViewModeKey: 'liste'});
    final container = ProviderContainer();
    container.read(gradesViewModeProvider);
    container.dispose();
    await Future<void>.delayed(Duration.zero);
  });
}
