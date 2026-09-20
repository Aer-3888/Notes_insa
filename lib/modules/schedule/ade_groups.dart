import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../../constants.dart';

/// What kind of ADE resource a row is. The web app offers the same tabs; its
/// teacher list is empty without a CAS session, so it is not carried here.
enum AdeCategory {
  student('s', 'Groupes'),
  room('r', 'Salles'),
  module('m', 'Matières');

  const AdeCategory(this.code, this.label);

  final String code;
  final String label;

  static AdeCategory fromCode(String? code) => values.firstWhere(
    (c) => c.code == code,
    orElse: () => AdeCategory.student,
  );
}

/// A selectable ADE resource.
class AdeGroup {
  const AdeGroup({
    required this.id,
    required this.name,
    this.category = AdeCategory.student,
    this.parentId,
  });

  final int id;
  final String name;
  final AdeCategory category;

  /// Null for a top-level entry such as INFO or STPI.
  final int? parentId;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'c': category.code,
    if (parentId != null) 'p': parentId,
  };

  factory AdeGroup.fromJson(Map<String, dynamic> json) => AdeGroup(
    id: json['id'] as int,
    name: json['name'] as String,
    category: AdeCategory.fromCode(json['c'] as String?),
    parentId: json['p'] as int?,
  );
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

  @visibleForTesting
  static List<AdeGroup> parseForTest(String source) => _parse(source);

  static List<AdeGroup> _parse(String source) {
    final raw = jsonDecode(source) as Map<String, dynamic>;
    // v1 shipped student groups under "groups"; v2 carries every category
    // under "resources". Both are accepted so a cached v1 payload still loads.
    final rows = (raw['resources'] ?? raw['groups']) as List<dynamic>?;
    if (rows == null) throw const FormatException('no resource list');
    final groups = <AdeGroup>[
      for (final g in rows) AdeGroup.fromJson(g as Map<String, dynamic>),
    ];
    if (groups.isEmpty) throw const FormatException('empty resource list');
    return groups;
  }

  /// Rows of one category, for the picker's tabs. Navigating what comes
  /// back is [AdeTree]'s job.
  static List<AdeGroup> ofCategory(List<AdeGroup> all, AdeCategory category) =>
      all.where((g) => g.category == category).toList();
}
