import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/ade_link.dart';
import 'package:notes_insa/modules/schedule/selection_share.dart';

void main() {
  test('builds the link shape the ade-planning web app uses', () {
    expect(
      SelectionShare.buildUrl(<int>[1214, 133, 136]),
      'https://ade-planning.insa-rennes.fr/view/1214,133,136/',
    );
  });

  test('round-trips through the importer, which is the whole point', () {
    const ids = <int>[4, 8, 199];
    expect(AdeLink.parseIds(SelectionShare.buildUrl(ids)), ids);
  });

  test('an empty selection has nothing to share', () {
    expect(SelectionShare.buildUrl(const <int>[]), '');
  });

  test('never builds a link longer than ADE accepts', () {
    final ids = List<int>.generate(200, (i) => i + 1);
    expect(
      AdeLink.parseIds(SelectionShare.buildUrl(ids)).length,
      AdeLink.maxIds,
    );
  });
}
