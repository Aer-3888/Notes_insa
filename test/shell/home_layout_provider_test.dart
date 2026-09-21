import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notes_insa/modules/registry.dart';
import 'package:notes_insa/shell/home_layout_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
    'allows the first position to be replaced but keeps courses visible',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(homeLayoutProvider.notifier);

      final reordered = [...container.read(homeLayoutProvider).order];
      final second = reordered.removeAt(1);
      reordered.insert(0, second);
      notifier.setVisibleOrder(reordered);
      notifier.toggleHidden(kCoursesCardId);

      final layout = container.read(homeLayoutProvider);
      expect(layout.order.first, second);
      expect(layout.hidden, isNot(contains(kCoursesCardId)));
    },
  );

  test('accepts every modular size selected by the resize gesture', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(homeLayoutProvider.notifier);
    final module = moduleCardId('laverie');

    expect(container.read(homeLayoutProvider).sizeOf(module), HomeCardSize.dot);

    for (final size in HomeCardSize.values) {
      notifier.setSize(module, size);
      expect(container.read(homeLayoutProvider).sizeOf(module), size);
    }
  });

  group('the default home', () {
    final layout = HomeLayout.defaults();

    test('opens on the day, not on a wall of shortcuts', () {
      expect(layout.hidden, isEmpty);
      expect(
        layout.order.indexOf(kCoursesCardId),
        lessThan(layout.order.indexOf('weather')),
      );
      expect(
        layout.order.indexOf('associations'),
        lessThan(layout.order.indexOf('library')),
      );
      expect(
        layout.order.indexOf('library'),
        lessThan(layout.order.indexOf('crous')),
      );
    });

    test(
      'puts the shortcuts the bottom bar has no room for above the feed',
      () {
        final courses = layout.order.indexOf(kCoursesCardId);
        for (final id in <String>['salles', 'laverie', 'meteo', 'notes']) {
          expect(
            layout.order.indexOf(moduleCardId(id)),
            lessThan(courses),
            reason: '$id should sit in the head strip',
          );
          expect(layout.sizeOf(moduleCardId(id)), HomeCardSize.dot);
        }
      },
    );

    test('lands the associations tile right under its own news', () {
      final news = layout.order.indexOf('associations');
      expect(layout.order[news + 1], moduleCardId('assos'));
      expect(layout.sizeOf(moduleCardId('assos')), HomeCardSize.full);
    });

    test('follows the tile with two labelled halves, before the libraries', () {
      final tile = layout.order.indexOf(moduleCardId('assos'));
      expect(layout.order[tile + 1], moduleCardId('carte'));
      expect(layout.order[tile + 2], moduleCardId('edt'));
      expect(layout.sizeOf(moduleCardId('carte')), HomeCardSize.horizontal);
      expect(layout.sizeOf(moduleCardId('edt')), HomeCardSize.horizontal);
      expect(layout.order[tile + 3], 'library');
    });

    test('still carries every registered module', () {
      for (final module in kCampusModules.whereType<ReadyModule>()) {
        expect(
          layout.order,
          contains(moduleCardId(module.id)),
          reason: '${module.id} is missing from the default home',
        );
      }
    });

    test('keeps a stored layout free of the default sizes', () {
      // The default table can change later without fighting the stored map.
      expect(layout.sizes, isEmpty);
      expect(layout.toJson()['sizes'], isEmpty);
    });
  });
}
