import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/module_cache.dart';
import 'weather_model.dart';
import 'weather_service.dart';

const String kWeatherModuleId = 'meteo';
const int kWeatherSchemaVersion = 1;

final moduleCacheProvider = FutureProvider<ModuleCache>(
  (ref) => ModuleCache.open(),
);

/// Cache-first weather. Emits the cached snapshot immediately so the screen
/// paints without waiting on the network, then the refreshed one.
///
/// A failed refresh keeps the cached value and reports why it failed, because
/// "you are offline" and "the service is broken" need different copy.
final weatherProvider = StreamProvider<CachedEntry<WeatherSnapshot>>((
  ref,
) async* {
  final cache = await ref.watch(moduleCacheProvider.future);
  final cached = await cache.read(
    kWeatherModuleId,
    schemaVersion: kWeatherSchemaVersion,
  );

  CachedEntry<WeatherSnapshot>? previous;
  if (cached.data != null) {
    previous = CachedEntry<WeatherSnapshot>(
      data: WeatherSnapshot.fromJson(cached.data!),
      cachedAt: cached.cachedAt,
      refreshState: RefreshState.refreshing,
    );
    yield previous;
  }

  try {
    final fresh = await const WeatherService().fetch();
    await cache.write(
      kWeatherModuleId,
      schemaVersion: kWeatherSchemaVersion,
      data: fresh.toJson(),
    );
    yield CachedEntry<WeatherSnapshot>(data: fresh, cachedAt: DateTime.now());
  } catch (e) {
    final state = e is SocketException || e is http.ClientException
        ? RefreshState.failedOffline
        : RefreshState.failedUpstream;
    if (previous != null) {
      yield previous.withState(state);
    } else {
      yield CachedEntry<WeatherSnapshot>(refreshState: state);
    }
  }
});
