import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/ade_groups.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('the bundled group asset loads and contains real groups', () async {
    // rootBundle in tests reads from the declared assets.
    final raw = await rootBundle.loadString(AdeGroups.assetPath);
    expect(raw.length, greaterThan(1000));
    final groups = await AdeGroups.load();
    expect(groups.length, 1433);
    expect(groups.any((g) => g.name == 'S3-STPI-L'), isTrue);
    final hit = AdeGroups.search(groups, 'S3-STPI-L');
    expect(hit.first.id, 2152);
  });
}
