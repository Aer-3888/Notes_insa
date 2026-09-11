import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

    expect(
      container.read(homeLayoutProvider).sizeOf(module),
      HomeCardSize.square,
    );

    for (final size in HomeCardSize.values) {
      notifier.setSize(module, size);
      expect(container.read(homeLayoutProvider).sizeOf(module), size);
    }
  });
}
