import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/schedule_view_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('every mode has French copy', () {
    expect(ScheduleViewMode.values.map((m) => m.label).toList(), <String>[
      'Liste',
      'Jour',
      '3 jours',
      'Semaine',
      'Mois',
    ]);
  });

  test('column counts drive the grid', () {
    expect(ScheduleViewMode.jour.dayColumns, 1);
    expect(ScheduleViewMode.troisJours.dayColumns, 3);
    expect(ScheduleViewMode.semaine.dayColumns, 7);
    expect(ScheduleViewMode.liste.dayColumns, 0);
    expect(ScheduleViewMode.mois.dayColumns, 0);
  });

  test('the strip shows only where the body is not already the overview', () {
    expect(ScheduleViewMode.liste.showsStrip, isTrue);
    expect(ScheduleViewMode.jour.showsStrip, isTrue);
    expect(ScheduleViewMode.troisJours.showsStrip, isTrue);
    expect(ScheduleViewMode.semaine.showsStrip, isFalse);
    expect(ScheduleViewMode.mois.showsStrip, isFalse);
  });

  test('defaults to Liste, which is what shipped before modes existed', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(scheduleViewModeProvider), ScheduleViewMode.liste);
  });

  test('a chosen mode is written to preferences', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(scheduleViewModeProvider.notifier)
        .set(ScheduleViewMode.semaine);
    expect(container.read(scheduleViewModeProvider), ScheduleViewMode.semaine);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kScheduleViewModeKey), 'semaine');
  });

  test('a stored mode is restored', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kScheduleViewModeKey: 'troisJours',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(scheduleViewModeProvider);
    // The restore is async, so let the microtask queue drain before reading.
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(scheduleViewModeProvider),
      ScheduleViewMode.troisJours,
    );
  });

  test('an unknown stored value falls back to Liste', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kScheduleViewModeKey: 'trimestre',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(scheduleViewModeProvider);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(scheduleViewModeProvider), ScheduleViewMode.liste);
  });
}
