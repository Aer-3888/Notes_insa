import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/module_cache.dart';

void main() {
  late Directory root;
  late ModuleCache cache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('module_cache_test');
    cache = ModuleCache(root);
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('read returns an empty entry when nothing is cached', () async {
    final entry = await cache.read('weather', schemaVersion: 1);
    expect(entry.data, isNull);
    expect(entry.cachedAt, isNull);
  });

  test('write then read round-trips the payload', () async {
    await cache.write(
      'weather',
      schemaVersion: 1,
      data: <String, dynamic>{'temp': 12},
      upstreamSyncedAt: '02/09/2026 15:45',
    );
    final entry = await cache.read('weather', schemaVersion: 1);
    expect(entry.data, <String, dynamic>{'temp': 12});
    expect(entry.upstreamSyncedAt, '02/09/2026 15:45');
    expect(entry.cachedAt, isNotNull);
  });

  test('read discards an entry written with an older schemaVersion', () async {
    await cache.write(
      'weather',
      schemaVersion: 1,
      data: <String, dynamic>{'temp': 12},
    );
    final entry = await cache.read('weather', schemaVersion: 2);
    expect(entry.data, isNull);
  });

  test('read discards corrupt JSON instead of throwing', () async {
    final file = File('${root.path}/weather.json');
    await file.writeAsString('{ this is not json');
    final entry = await cache.read('weather', schemaVersion: 1);
    expect(entry.data, isNull);
  });

  test('write is atomic and leaves no temp file behind', () async {
    await cache.write(
      'weather',
      schemaVersion: 1,
      data: <String, dynamic>{'a': 1},
    );
    final leftovers = root.listSync().where((e) => e.path.endsWith('.tmp'));
    expect(leftovers, isEmpty);
  });

  test('clear removes the entry', () async {
    await cache.write(
      'weather',
      schemaVersion: 1,
      data: <String, dynamic>{'a': 1},
    );
    await cache.clear('weather');
    final entry = await cache.read('weather', schemaVersion: 1);
    expect(entry.data, isNull);
  });

  test('stored envelope carries the schema version', () async {
    await cache.write(
      'weather',
      schemaVersion: 3,
      data: <String, dynamic>{'a': 1},
    );
    final raw =
        jsonDecode(await File('${root.path}/weather.json').readAsString())
            as Map<String, dynamic>;
    expect(raw['schemaVersion'], 3);
  });
}
