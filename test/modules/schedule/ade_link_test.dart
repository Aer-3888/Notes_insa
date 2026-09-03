import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/ade_link.dart';

void main() {
  test('parses a real ade-planning view link', () {
    const url =
        'https://ade-planning.insa-rennes.fr/view/1214,133,136,138,139,144,'
        '145,1672,196,1678,199,1676,1679,601,448,899,1681,2614,942,187/';
    final ids = AdeLink.parseIds(url);
    expect(ids.length, 20);
    expect(ids.first, 1214);
    expect(ids.last, 187);
    expect(ids, contains(899));
  });

  test('parses an anonymous_cal.jsp link via the resources parameter', () {
    const url =
        'https://ade.insa-rennes.fr/jsp/custom/modules/plannings/'
        'anonymous_cal.jsp?resources=2152,248&projectId=2&calType=ical';
    expect(AdeLink.parseIds(url), <int>[2152, 248]);
  });

  test('parses a bare comma-separated list', () {
    expect(AdeLink.parseIds(' 2152, 248 '), <int>[2152, 248]);
  });

  test('parses a single id', () {
    expect(AdeLink.parseIds('2152'), <int>[2152]);
  });

  test('de-duplicates repeated ids, keeping first occurrence order', () {
    expect(AdeLink.parseIds('5,3,5,7'), <int>[5, 3, 7]);
  });

  test('caps an over-long list rather than sending it all upstream', () {
    final many = List<int>.generate(150, (i) => i + 1).join(',');
    expect(AdeLink.parseIds(many).length, AdeLink.maxIds);
  });

  test('accepts a selection as large as the website allows', () {
    final hundred = List<int>.generate(100, (i) => i + 1).join(',');
    expect(AdeLink.parseIds(hundred).length, 100);
  });

  test('rejects zero and negative ids', () {
    expect(AdeLink.parseIds('0,-4,12'), <int>[12]);
  });

  test('returns empty for text with no ids', () {
    expect(AdeLink.parseIds('https://example.com/hello'), isEmpty);
    expect(AdeLink.parseIds(''), isEmpty);
    expect(AdeLink.parseIds('   '), isEmpty);
  });

  test('ignores a trailing slash and surrounding whitespace', () {
    expect(
      AdeLink.parseIds('  https://ade-planning.insa-rennes.fr/view/7,8/  '),
      <int>[7, 8],
    );
  });
}
