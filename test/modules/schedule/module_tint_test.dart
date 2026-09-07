import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/grid_block.dart';
import 'package:notes_insa/modules/schedule/module_palette.dart';
import 'package:notes_insa/modules/schedule/schedule_day_index.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_timeline.dart';
import 'package:notes_insa/modules/schedule/week_strip.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:notes_insa/theme/module_tints.dart';
import 'package:notes_insa/theme/tokens.dart';

ScheduleEvent event(String title, {String? module, String? room}) =>
    ScheduleEvent(
      title: title,
      start: DateTime(2026, 9, 7, 8),
      end: DateTime(2026, 9, 7, 10),
      groups: const <String>[],
      teachers: const <String>[],
      module: module,
      room: room,
    );

Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: campusTheme(Brightness.light),
      home: Scaffold(body: SizedBox(width: 200, height: 120, child: child)),
    ),
  );
}

/// The fill of the block's own Material, not the Scaffold's.
Color blockFill(WidgetTester tester) => tester
    .widget<Material>(
      find.descendant(
        of: find.byType(GridBlock),
        matching: find.byType(Material),
      ),
    )
    .color!;

void main() {
  group('grid block', () {
    testWidgets('takes the tint of its module', (tester) async {
      await pump(
        tester,
        GridBlock(event: event('Analyse 3_GHIJKL'), onTap: () {}),
      );
      expect(CampusColors.light.moduleBlockTints, contains(blockFill(tester)));
    });

    testWidgets('is no longer the one flat container fill', (tester) async {
      await pump(
        tester,
        GridBlock(event: event('Analyse 3_GHIJKL'), onTap: () {}),
      );
      expect(
        blockFill(tester),
        isNot(CampusColors.light.surfaceContainerHighest),
      );
    });

    testWidgets('two sessions of one module share a fill', (tester) async {
      await pump(
        tester,
        GridBlock(event: event('Analyse 3_GHIJKL'), onTap: () {}),
      );
      final first = blockFill(tester);
      await pump(
        tester,
        GridBlock(event: event('Analyse 3_ABCDEF'), onTap: () {}),
      );
      expect(blockFill(tester), first);
    });

    testWidgets('the module field wins over the dirty summary', (tester) async {
      await pump(
        tester,
        GridBlock(
          event: event('ANA3_GHIJKL', module: 'Analyse 3'),
          onTap: () {},
        ),
      );
      final viaModule = blockFill(tester);
      await pump(tester, GridBlock(event: event('Analyse 3'), onTap: () {}));
      expect(blockFill(tester), viaModule);
    });
  });

  group('timeline row', () {
    Color spineColor(WidgetTester tester) => tester
        .widget<ColoredBox>(
          find.descendant(
            of: find.byType(ScheduleEventRow),
            matching: find.byType(ColoredBox),
          ),
        )
        .color;

    testWidgets('carries a spine in the module tint', (tester) async {
      await pump(
        tester,
        ScheduleEventRow(event: event('Analyse 3_GHIJKL', room: 'Amphi C')),
      );
      expect(CampusColors.light.moduleSpineTints, contains(spineColor(tester)));
    });

    testWidgets('agrees with the grid block for the same module', (
      tester,
    ) async {
      await pump(
        tester,
        ScheduleEventRow(event: event('Analyse 3_GHIJKL', room: 'Amphi C')),
      );
      final spine = spineColor(tester);
      await pump(
        tester,
        GridBlock(event: event('Analyse 3_GHIJKL'), onTap: () {}),
      );
      expect(blockFill(tester), spine);
    });
  });

  group('week strip', () {
    testWidgets('bars are tinted, not one flat neutral', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final monday = DateTime(2026, 9, 7);
      final index = ScheduleDayIndex.build(
        events: <ScheduleEvent>[
          ScheduleEvent(
            title: 'Analyse 3_GHIJKL',
            start: DateTime(2026, 9, 7, 8),
            end: DateTime(2026, 9, 7, 10),
            groups: const <String>[],
            teachers: const <String>[],
          ),
        ],
        from: monday,
        to: DateTime(2026, 9, 13),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: campusTheme(Brightness.light),
          home: Scaffold(
            body: WeekStrip(
              index: index,
              weekOf: monday,
              currentDay: monday,
              onDayTap: (_) {},
            ),
          ),
        ),
      );

      final bar = tester.widget<WeekStripBar>(find.byType(WeekStripBar));
      expect(CampusColors.light.moduleBarTints, contains(bar.color));
      expect(bar.color, isNot(CampusColors.light.onSurfaceVariant));

      // The bar is the information in the strip, so it takes the bold ramp,
      // not the pale fill a grid block gets.
      expect(CampusColors.light.moduleBlockTints, isNot(contains(bar.color)));
    });
  });

  testWidgets('a module keeps its hue between the strip and the grid', (
    tester,
  ) async {
    await pump(
      tester,
      GridBlock(event: event('Analyse 3_GHIJKL'), onTap: () {}),
    );
    final fillIndex = CampusColors.light.moduleBlockTints.indexOf(
      blockFill(tester),
    );
    expect(fillIndex, isNonNegative);

    final key = ModulePalette.normalize('Analyse 3_GHIJKL');
    final bold = ModulePalette(
      tints: CampusColors.light.moduleBarTints,
    ).colorFor(key, fallback: const Color(0xFF000000));
    expect(CampusColors.light.moduleBarTints.indexOf(bold), fillIndex);
  });

  group('sans couleur', () {
    Future<void> pumpPlain(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: campusTheme(
            Brightness.light,
            scheme: ScheduleTintScheme.aucune,
          ),
          home: Scaffold(body: SizedBox(width: 200, height: 120, child: child)),
        ),
      );
    }

    testWidgets('a block falls back to the flat container fill', (
      tester,
    ) async {
      await pumpPlain(
        tester,
        GridBlock(event: event('Analyse 3_GHIJKL'), onTap: () {}),
      );
      expect(blockFill(tester), CampusColors.light.surfaceContainerHighest);
    });

    testWidgets('a spine falls back to the hairline', (tester) async {
      await pumpPlain(
        tester,
        ScheduleEventRow(event: event('Analyse 3_GHIJKL', room: 'Amphi C')),
      );
      final spine = tester
          .widget<ColoredBox>(
            find.descendant(
              of: find.byType(ScheduleEventRow),
              matching: find.byType(ColoredBox),
            ),
          )
          .color;
      expect(spine, CampusColors.light.outlineVariant);
    });
  });

  testWidgets('discret leaves the block neutral but tints the spine', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(
          Brightness.light,
          intensity: ScheduleTintIntensity.discret,
        ),
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 120,
            child: GridBlock(event: event('Analyse 3_GHIJKL'), onTap: () {}),
          ),
        ),
      ),
    );
    expect(blockFill(tester), CampusColors.light.surfaceContainerHighest);
  });

  test('the palette reads its tints from the theme extension', () {
    final palette = ModulePalette(tints: CampusColors.dark.moduleBlockTints);
    expect(
      CampusColors.dark.moduleBlockTints,
      contains(
        palette.colorFor('analyse 3', fallback: const Color(0xFF000000)),
      ),
    );
  });
}
