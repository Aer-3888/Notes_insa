import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The official INSA Rennes site plan (July 2025 edition).
const String kCampusPlanUrl =
    'https://www.insa-rennes.fr/fileadmin/ressources/Rubriques/02-INSA/PlanCampusINSA-Rennes_juil2025.pdf';

enum PlaceKind {
  amphi,
  batiment,
  bu,
  ru,
  residence,
  service;

  static PlaceKind? parse(String raw) {
    for (final kind in PlaceKind.values) {
      if (kind.name == raw) return kind;
    }
    return null;
  }

  String get label => switch (this) {
    PlaceKind.amphi => 'Amphis',
    PlaceKind.batiment => 'Bâtiments et départements',
    PlaceKind.bu => 'Bibliothèque',
    PlaceKind.ru => 'Restauration',
    PlaceKind.residence => 'Résidences',
    PlaceKind.service => 'Services',
  };
}

@immutable
class CampusPlace {
  const CampusPlace({
    required this.code,
    required this.name,
    required this.kind,
  });

  /// Building number on the INSA plan. Several places share one building.
  final String code;
  final String name;
  final PlaceKind kind;

  static CampusPlace? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final code = raw['code'];
    final name = raw['name'];
    final kind = PlaceKind.parse(raw['kind'] as String? ?? '');
    if (code is! String || name is! String || kind == null) return null;
    if (code.isEmpty || name.isEmpty) return null;
    return CampusPlace(code: code, name: name, kind: kind);
  }

  bool matches(String query) {
    final q = _fold(query);
    if (q.isEmpty) return true;
    return _fold(name).contains(q) || _fold(code).contains(q);
  }
}

/// Lower-cases and strips the accents students will not bother typing.
String _fold(String s) {
  const from = 'àâäéèêëîïôöùûüç';
  const to = 'aaaeeeeiioouuuc';
  final out = StringBuffer();
  for (final rune in s.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    final i = from.indexOf(ch);
    out.write(i >= 0 ? to[i] : ch);
  }
  return out.toString().trim();
}

abstract final class CampusPlaces {
  static const String assetPath = 'assets/data/campus_places.json';

  static List<CampusPlace> parse(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const <CampusPlace>[];
      return decoded
          .map(CampusPlace.fromJson)
          .whereType<CampusPlace>()
          .toList(growable: false);
    } catch (e) {
      if (kDebugMode) debugPrint('[CampusPlaces] unreadable dataset: $e');
      return const <CampusPlace>[];
    }
  }

  static Future<List<CampusPlace>> load() async {
    try {
      return parse(await rootBundle.loadString(assetPath));
    } catch (e) {
      if (kDebugMode) debugPrint('[CampusPlaces] missing dataset: $e');
      return const <CampusPlace>[];
    }
  }
}

final campusPlacesProvider = FutureProvider<List<CampusPlace>>(
  (ref) => CampusPlaces.load(),
);
