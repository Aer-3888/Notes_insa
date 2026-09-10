import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notes_insa/modules/crous/crous_service.dart';

void main() {
  MockClient clientFor(List<Map<String, Object?>> restaurants) => MockClient(
    (_) async => http.Response.bytes(
      utf8.encode(jsonEncode(restaurants)),
      200,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    ),
  );

  final payload = <Map<String, Object?>>[
    <String, Object?>{
      'id': 915,
      'title': "Resto U' Etoile",
      'opening': '011,011,011,011,010,000,000',
      'closing': '0',
      'infos': '<p>MIDI : 11h15 -13h45<br>SOIR : 18h15 à 20h</p>',
      'lastSyncAt': '2026-09-10T20:35:57Z',
    },
    <String, Object?>{
      'id': 916,
      'title': "Resto U' Astrolabe",
      'opening': '110,110,110,110,110,000,000',
      'closing': '0',
      'infos': '<p>MIDI : 11h15–13h45, du lundi au vendredi</p>',
      'lastSyncAt': '2026-09-10T20:35:58Z',
    },
  ];

  test('reads the two nearby restaurants from the official feed', () async {
    final restaurants = await CrousService(client: clientFor(payload)).fetch();

    expect(restaurants.map((restaurant) => restaurant.shortName), <String>[
      'Étoile',
      'Astrolabe',
    ]);
    expect(restaurants.first.name, 'Resto U’ Étoile');
    expect(restaurants.first.openingPeriods, hasLength(2));
    expect(restaurants.first.openingPeriods.last.closesAtMinute, 20 * 60);
    expect(restaurants.first.openingPeriods.last.days, <int>{1, 2, 3, 4});
    expect(restaurants.last.openingPeriods, hasLength(1));
    expect(restaurants.last.syncedAt, DateTime.parse('2026-09-10T20:35:58Z'));
  });

  test('fails clearly if a configured restaurant disappears', () async {
    final service = CrousService(client: clientFor(<Map<String, Object?>>[]));
    expect(service.fetch(), throwsA(isA<FormatException>()));
  });
}
