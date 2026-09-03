import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notes_insa/modules/schedule/ade_groups.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the bundled group asset loads and contains real groups', () async {
    final raw = await rootBundle.loadString(AdeGroups.assetPath);
    expect(raw.length, greaterThan(1000));
    final groups = await AdeGroups.loadBundled();
    expect(groups.length, 1433);
    final hit = AdeGroups.search(groups, 'S3-STPI-L');
    expect(hit.first.id, 2152);
  });

  test('fetchRemote parses the worker payload', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'version': 1,
          'groups': [
            {'id': 7, 'name': 'S1-STPI-A'},
          ],
        }),
        200,
      ),
    );
    final groups = await AdeGroups.fetchRemote(client: client);
    expect(groups.single.id, 7);
  });

  test(
    'fetchRemote rejects a non-200 rather than returning an empty list',
    () async {
      final client = MockClient((_) async => http.Response('nope', 503));
      expect(
        () => AdeGroups.fetchRemote(client: client),
        throwsA(isA<http.ClientException>()),
      );
    },
  );

  test('fetchRemote rejects an empty group list', () async {
    final client = MockClient(
      (_) async => http.Response(jsonEncode({'groups': <dynamic>[]}), 200),
    );
    expect(
      () => AdeGroups.fetchRemote(client: client),
      throwsA(isA<FormatException>()),
    );
  });
}
