import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// A selectable ADE resource (a student group).
class AdeGroup {
  const AdeGroup({required this.id, required this.name});

  final int id;
  final String name;
}

/// The group list is bundled rather than fetched.
///
/// ADE exposes no anonymous resource listing, and the list changes about twice
/// a year, so shipping it as an asset keeps the picker instant and offline and
/// avoids polling anyone for data that does not move.
class AdeGroups {
  static const String assetPath = 'assets/data/ade_groups.json';

  static List<AdeGroup>? _cache;

  static Future<List<AdeGroup>> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final raw =
        jsonDecode(await rootBundle.loadString(assetPath))
            as Map<String, dynamic>;
    final groups = <AdeGroup>[
      for (final g in raw['groups'] as List<dynamic>)
        AdeGroup(
          id: (g as Map<String, dynamic>)['id'] as int,
          name: g['name'] as String,
        ),
    ];
    return _cache = groups;
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
