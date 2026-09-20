import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/registry.dart';

void main() {
  test('module ids are unique', () {
    final ids = kCampusModules.map((m) => m.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('every module has non-empty French copy', () {
    for (final m in kCampusModules) {
      expect(m.label, isNotEmpty, reason: 'module ${m.id} has no label');
    }
  });

  test('every registered module is built', () {
    expect(
      kCampusModules.whereType<ReadyModule>().length,
      kCampusModules.length,
    );
  });

  test('the grades module is the only CAS-gated one in this phase', () {
    final gated = kCampusModules
        .whereType<ReadyModule>()
        .where((m) => m.requiresCas)
        .map((m) => m.id);
    expect(gated, <String>['notes']);
  });

  test('the bar modules exist in the registry', () {
    final ids = kCampusModules.map((m) => m.id).toSet();
    expect(ids.containsAll(<String>['edt', 'notes', 'carte']), isTrue);
  });

  test('free rooms are available from the hub', () {
    final rooms = kCampusModules.whereType<ReadyModule>().singleWhere(
      (module) => module.id == 'salles',
    );
    expect(rooms.label, 'Salles libres');
  });
}
