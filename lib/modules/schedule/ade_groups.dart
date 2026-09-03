import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../../constants.dart';

/// A selectable ADE resource (a student group).
class AdeGroup {
  const AdeGroup({required this.id, required this.name});

  final int id;
  final String name;

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'name': name};

  factory AdeGroup.fromJson(Map<String, dynamic> json) =>
      AdeGroup(id: json['id'] as int, name: json['name'] as String);
}

/// Loads the ADE group list.
///
/// ADE exposes no anonymous resource listing, so the list is refreshed daily by
/// the Worker and served from `/ade/groups`. A copy ships in the app as an
/// asset, which seeds first launch and covers the Worker being unreachable, so
/// the picker always has something to show.
class AdeGroups {
  static const String assetPath = 'assets/data/ade_groups.json';

  static List<AdeGroup>? _memo;

  /// Bundled list only. Always available, may be a release or two behind.
  static Future<List<AdeGroup>> loadBundled() async =>
      _parse(await rootBundle.loadString(assetPath));

  /// Fresh list from the Worker. Throws if unreachable or malformed.
  static Future<List<AdeGroup>> fetchRemote({http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final uri = Uri.parse('$kWorkerBaseUrl/ade/groups');
      final response = await c.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw http.ClientException('HTTP ${response.statusCode}', uri);
      }
      return _parse(response.body);
    } finally {
      if (client == null) c.close();
    }
  }

  /// The list the picker uses: freshest available, never empty.
  ///
  /// Memoized for the session, since it is read on every picker open and the
  /// underlying list changes about twice a year.
  static Future<List<AdeGroup>> load({http.Client? client}) async {
    final memo = _memo;
    if (memo != null) return memo;
    try {
      return _memo = await fetchRemote(client: client);
    } catch (_) {
      // Offline, Worker down, or route not deployed yet. The bundled copy is
      // the whole point of shipping one.
      return _memo = await loadBundled();
    }
  }

  static List<AdeGroup> _parse(String source) {
    final raw = jsonDecode(source) as Map<String, dynamic>;
    final groups = <AdeGroup>[
      for (final g in raw['groups'] as List<dynamic>)
        AdeGroup.fromJson(g as Map<String, dynamic>),
    ];
    if (groups.isEmpty) throw const FormatException('empty group list');
    return groups;
  }

  /// Case- and accent-insensitive contains search over group names.
  static List<AdeGroup> search(List<AdeGroup> groups, String query) {
    final q = _normalize(query);
    if (q.isEmpty) return groups;
    return groups.where((g) => _normalize(g.name).contains(q)).toList();
  }

  static String _normalize(String v) {
    var s = v.toLowerCase().trim();
    const accents = {
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'ô': 'o',
      'ö': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
    };
    accents.forEach((a, b) => s = s.replaceAll(a, b));
    return s;
  }
}
