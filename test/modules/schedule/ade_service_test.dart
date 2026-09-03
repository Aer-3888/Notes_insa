import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/ade_groups.dart';
import 'package:notes_insa/modules/schedule/ade_service.dart';

void main() {
  group('buildUri', () {
    final uri = AdeService.buildUri(
      resourceIds: <int>[2152, 248],
      from: DateTime(2026, 9, 7),
      to: DateTime(2026, 11, 2),
    );

    test('targets the official INSA ADE anonymous export', () {
      expect(uri.origin, 'https://ade.insa-rennes.fr');
      expect(uri.path, '/jsp/custom/modules/plannings/anonymous_cal.jsp');
    });

    test('joins resources with commas and pins the project', () {
      expect(uri.queryParameters['resources'], '2152,248');
      expect(uri.queryParameters['projectId'], '2');
      expect(uri.queryParameters['calType'], 'ical');
    });

    test('windows the request server-side with zero-padded dates', () {
      expect(uri.queryParameters['firstDate'], '2026-09-07');
      expect(uri.queryParameters['lastDate'], '2026-11-02');
    });

    test('carries no credential or token of any kind', () {
      expect(uri.query.toLowerCase(), isNot(contains('token')));
      expect(uri.userInfo, isEmpty);
    });
  });

  group('group search', () {
    const groups = <AdeGroup>[
      AdeGroup(id: 1, name: 'S3-STPI-L'),
      AdeGroup(id: 2, name: 'S3-STPI-FILIERE INTER'),
      AdeGroup(id: 3, name: 'ESP-Niveau A1- STPI 1A'),
      AdeGroup(id: 4, name: 'S7-INFO-ROBO'),
    ];

    test('matches case-insensitively', () {
      final hits = AdeGroups.search(groups, 's3-stpi-l');
      expect(hits.map((g) => g.id), <int>[1]);
    });

    test('matches on a partial fragment', () {
      final hits = AdeGroups.search(groups, 'STPI');
      expect(hits.length, 3);
    });

    test('ignores accents so "Niveau" is findable either way', () {
      expect(AdeGroups.search(groups, 'niveau').length, 1);
    });

    test('an empty query returns everything', () {
      expect(AdeGroups.search(groups, '   ').length, groups.length);
    });

    test('an unmatched query returns nothing rather than throwing', () {
      expect(AdeGroups.search(groups, 'zzzz'), isEmpty);
    });
  });
}
