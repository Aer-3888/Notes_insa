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
    expect(ScheduleViewMode.troisJours.showsStrip, isFalse);
    expect(ScheduleViewMode.semaine.showsStrip, isFalse);
    expect(ScheduleViewMode.mois.showsStrip, isFalse);
  });

  test('defaults to Jour', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(scheduleViewModeProvider), ScheduleViewMode.jour);
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

  test(
    'the Day week strip is visible by default and can be remembered off',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(scheduleDayWeekStripProvider), isTrue);
      await container.read(scheduleDayWeekStripProvider.notifier).toggle();
      expect(container.read(scheduleDayWeekStripProvider), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kScheduleDayWeekStripKey), isFalse);
    },
  );

  test('an unknown stored value falls back to Jour', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kScheduleViewModeKey: 'trimestre',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(scheduleViewModeProvider);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(scheduleViewModeProvider), ScheduleViewMode.jour);
  });

  test('Liste starts without the strip and can be remembered on', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(scheduleListWeekStripProvider), isFalse);
    await container.read(scheduleListWeekStripProvider.notifier).toggle();
    expect(container.read(scheduleListWeekStripProvider), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kScheduleListWeekStripKey), isTrue);
  });

  test('Mois draws its classes until it is told not to', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(scheduleMonthPreviewProvider), isTrue);
    await container.read(scheduleMonthPreviewProvider.notifier).toggle();
    expect(container.read(scheduleMonthPreviewProvider), isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kScheduleMonthPreviewKey), isFalse);
  });

  test('a stored flag is restored', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kScheduleListWeekStripKey: true,
      kScheduleMonthPreviewKey: false,
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
      ..read(scheduleListWeekStripProvider)
      ..read(scheduleMonthPreviewProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(scheduleListWeekStripProvider), isTrue);
    expect(container.read(scheduleMonthPreviewProvider), isFalse);
  });

  test('the day widths run from a whole week to a long name', () {
    expect(
      ScheduleDayWidth.values.map((w) => w.minColumnWidth).toList(),
      <double>[48, 104, 160],
    );
    expect(ScheduleDayWidth.values.map((w) => w.label).toList(), <String>[
      'Compact',
      'Normal',
      'Large',
    ]);
  });

  test('the day width defaults to Normal and is written down', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(scheduleDayWidthProvider), 104);
    await container.read(scheduleDayWidthProvider.notifier).set(72);
    expect(container.read(scheduleDayWidthProvider), 72);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble(kScheduleDayWidthKey), 72);
  });

  test('a hand-set width is held to the bounds', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(scheduleDayWidthProvider.notifier);

    await notifier.set(10);
    expect(container.read(scheduleDayWidthProvider), kScheduleDayWidthMin);
    await notifier.set(900);
    expect(container.read(scheduleDayWidthProvider), kScheduleDayWidthMax);
  });

  test('a drag moves the width without writing it down', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(scheduleDayWidthProvider.notifier).drag(88);
    expect(container.read(scheduleDayWidthProvider), 88);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble(kScheduleDayWidthKey), isNull);
  });

  test('a width only carries a preset name when it lands on one', () {
    expect(scheduleDayWidthLabel(104), 'Normal');
    expect(scheduleDayWidthLabel(48), 'Compact');
    expect(scheduleDayWidthLabel(72), '72 dp');
    expect(scheduleDayWidthPreset(72), isNull);
  });

  test('a width stored as a preset name still opens', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kScheduleDayWidthKey: 'compact',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(scheduleDayWidthProvider);
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(scheduleDayWidthProvider),
      ScheduleDayWidth.compact.minColumnWidth,
    );
  });
}
