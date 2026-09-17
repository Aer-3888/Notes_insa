import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../constants.dart';
import 'association.dart';
import 'association_follows.dart';

/// The association directory.
///
/// Phase 1 reads the bundled seed, the same shape the Worker will serve later,
/// so moving to the API is a change to [load] and nothing above it. A row the
/// seed gets wrong is dropped rather than crashing the list: the asset test is
/// what catches it, not a student's phone.
abstract final class Associations {
  static const String assetPath = 'assets/data/associations.json';
  static const Duration _timeout = Duration(seconds: 10);

  /// Bumped when the shape changes in a way an older app cannot read.
  static const int supportedVersion = 1;

  static List<Association> parse(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return const <Association>[];
      final version = decoded['version'];
      if (version is! num || version.toInt() != supportedVersion) {
        if (kDebugMode) debugPrint('[Associations] version $version ignored');
        return const <Association>[];
      }
      final rows = decoded['associations'];
      if (rows is! List) return const <Association>[];
      final out = rows
          .map(Association.fromJson)
          .whereType<Association>()
          .toList(growable: false);
      return out..sort((a, b) => a.name.compareTo(b.name));
    } catch (e) {
      if (kDebugMode) debugPrint('[Associations] unreadable dataset: $e');
      return const <Association>[];
    }
  }

  static Future<List<Association>> load({http.Client? client}) async {
    try {
      final remote = await _fetchRemote(client: client);
      if (remote.isNotEmpty) return remote;
    } catch (_) {
      // The bundled directory deliberately covers offline use and a Worker
      // outage. The remote feed will be tried again on the next app launch.
    }
    try {
      return parse(await rootBundle.loadString(assetPath));
    } catch (e) {
      if (kDebugMode) debugPrint('[Associations] missing dataset: $e');
      return const <Association>[];
    }
  }

  static Future<List<Association>> _fetchRemote({http.Client? client}) async {
    final c = client ?? http.Client();
    final uri = Uri.parse('$kWorkerBaseUrl/associations');
    try {
      final response = await c.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        throw http.ClientException('HTTP ${response.statusCode}', uri);
      }
      final parsed = parse(response.body);
      if (parsed.isEmpty) {
        throw const FormatException('empty associations feed');
      }
      return parsed;
    } finally {
      if (client == null) c.close();
    }
  }
}

final associationsProvider = FutureProvider<List<Association>>(
  (ref) => Associations.load(),
);

/// Every event from every association, soonest first. The today card reads
/// this and filters it down to what the student follows.
final associationEventsProvider = Provider<List<AssociationEvent>>((ref) {
  final associations = ref.watch(associationsProvider).value;
  if (associations == null) return const <AssociationEvent>[];
  return <AssociationEvent>[
    for (final association in associations) ...association.events,
  ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
});

/// Events from the associations the student follows, soonest first.
///
/// Not filtered on the clock: the caller passes the moment it cares about, so
/// a card with its own minute timer stays correct without invalidating this.
final followedAssociationEventsProvider = Provider<List<AssociationEvent>>((
  ref,
) {
  final follows = ref.watch(associationFollowsProvider);
  if (follows.isEmpty) return const <AssociationEvent>[];
  return ref
      .watch(associationEventsProvider)
      .where((event) => follows.contains(event.associationId))
      .toList(growable: false);
});
