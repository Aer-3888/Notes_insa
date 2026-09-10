import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/module_cache.dart';
import '../../core/module_cache_provider.dart';
import 'crous_restaurant.dart';
import 'crous_service.dart';

const String kCrousModuleId = 'restos_crous';
const int kCrousSchemaVersion = 2;

final crousRestaurantsProvider =
    StreamProvider<CachedEntry<List<CrousRestaurant>>>((ref) async* {
      final cache = await ref.watch(moduleCacheProvider.future);
      final cached = await cache.read(
        kCrousModuleId,
        schemaVersion: kCrousSchemaVersion,
      );

      CachedEntry<List<CrousRestaurant>>? previous;
      final rawRestaurants = cached.data?['restaurants'];
      if (rawRestaurants is List) {
        try {
          previous = CachedEntry<List<CrousRestaurant>>(
            data: <CrousRestaurant>[
              for (final raw in rawRestaurants)
                CrousRestaurant.fromJson(Map<String, dynamic>.from(raw as Map)),
            ],
            cachedAt: cached.cachedAt,
            refreshState: RefreshState.refreshing,
          );
          yield previous;
        } catch (_) {
          previous = null;
        }
      }

      try {
        final fresh = await const CrousService().fetch();
        final syncedAt = fresh
            .map((restaurant) => restaurant.syncedAt)
            .whereType<DateTime>()
            .fold<DateTime?>(
              null,
              (latest, value) =>
                  latest == null || value.isAfter(latest) ? value : latest,
            );
        await cache.write(
          kCrousModuleId,
          schemaVersion: kCrousSchemaVersion,
          upstreamSyncedAt: syncedAt?.toUtc().toIso8601String(),
          data: <String, dynamic>{
            'restaurants': <Map<String, dynamic>>[
              for (final restaurant in fresh) restaurant.toJson(),
            ],
          },
        );
        yield CachedEntry<List<CrousRestaurant>>(
          data: fresh,
          cachedAt: DateTime.now(),
          upstreamSyncedAt: syncedAt?.toUtc().toIso8601String(),
        );
      } catch (error) {
        final state = error is SocketException || error is http.ClientException
            ? RefreshState.failedOffline
            : RefreshState.failedUpstream;
        if (previous != null) {
          yield previous.withState(state);
        } else {
          yield CachedEntry<List<CrousRestaurant>>(refreshState: state);
        }
      }
    });
