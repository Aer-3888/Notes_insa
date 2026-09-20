import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../modules/registry.dart';

/// Bumped with the default below: a stored v2 layout describes the old home.
const String kHomeLayoutKey = 'home_layout_v3';

const String kCoursesCardId = 'courses';

String moduleCardId(String moduleId) => 'module:$moduleId';

/// The day read top to bottom, shortcuts above it for the modules the bottom
/// bar has no room for, and the associations tile under the news it continues.
List<String> get _defaultOrder => <String>[
  moduleCardId('salles'),
  moduleCardId('laverie'),
  moduleCardId('meteo'),
  moduleCardId('notes'),
  kCoursesCardId,
  'weather',
  'associations',
  moduleCardId('assos'),
  moduleCardId('carte'),
  moduleCardId('edt'),
  'library',
  'crous',
];

/// Read before the square fallback. Never written to disk: a size enters
/// [HomeLayout.sizes] only once the user resizes that card.
final Map<String, HomeCardSize> kDefaultCardSizes = <String, HomeCardSize>{
  moduleCardId('salles'): HomeCardSize.dot,
  moduleCardId('laverie'): HomeCardSize.dot,
  moduleCardId('meteo'): HomeCardSize.dot,
  moduleCardId('notes'): HomeCardSize.dot,
  moduleCardId('assos'): HomeCardSize.full,
  moduleCardId('carte'): HomeCardSize.horizontal,
  moduleCardId('edt'): HomeCardSize.horizontal,
};

/// A module the default order does not place still lands on the home, at the
/// end, so registering one is never a silent way to hide it.
List<String> get kDefaultHomeCardOrder {
  final placed = _defaultOrder;
  return <String>[
    ...placed,
    for (final module in kCampusModules.whereType<ReadyModule>())
      if (!placed.contains(moduleCardId(module.id))) moduleCardId(module.id),
  ];
}

enum HomeCardSize { dot, horizontal, square, full }

class HomeLayout {
  const HomeLayout({
    required this.order,
    required this.hidden,
    required this.sizes,
  });

  factory HomeLayout.defaults() => const HomeLayout(
    order: <String>[],
    hidden: <String>{},
    sizes: <String, HomeCardSize>{},
  ).normalized();

  final List<String> order;
  final Set<String> hidden;
  final Map<String, HomeCardSize> sizes;

  bool isModule(String id) => id.startsWith('module:');

  HomeCardSize sizeOf(String id) => isModule(id)
      ? sizes[id] ?? kDefaultCardSizes[id] ?? HomeCardSize.square
      : HomeCardSize.full;

  HomeLayout normalized() {
    final known = kDefaultHomeCardOrder;
    final knownSet = known.toSet();
    final normalizedOrder = <String>[...order.where(knownSet.contains)];
    for (final id in known) {
      if (!normalizedOrder.contains(id)) normalizedOrder.add(id);
    }
    return HomeLayout(
      order: normalizedOrder,
      hidden: {...hidden.where(knownSet.contains)}..remove(kCoursesCardId),
      sizes: {
        for (final entry in sizes.entries)
          if (entry.key.startsWith('module:')) entry.key: entry.value,
      },
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'order': order,
    'hidden': hidden.toList(),
    'sizes': {for (final entry in sizes.entries) entry.key: entry.value.name},
  };

  factory HomeLayout.fromJson(Map<String, dynamic> json) => HomeLayout(
    order: [
      for (final id in json['order'] as List? ?? const <dynamic>[])
        id as String,
    ],
    hidden: {
      for (final id in json['hidden'] as List? ?? const <dynamic>[])
        id as String,
    },
    sizes: {
      for (final entry
          in (json['sizes'] as Map? ?? const <dynamic, dynamic>{}).entries)
        entry.key as String: ?HomeCardSize.values
            .where((size) => size.name == entry.value)
            .firstOrNull,
    },
  ).normalized();
}

class HomeLayoutNotifier extends Notifier<HomeLayout> {
  bool _changed = false;

  @override
  HomeLayout build() {
    unawaited(_restore());
    return HomeLayout.defaults();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!ref.mounted || _changed) return;
      final raw = prefs.getString(kHomeLayoutKey);
      if (raw == null) return;
      state = HomeLayout.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      // A dashboard preference must never prevent the default home from opening.
    }
  }

  void setVisibleOrder(List<String> visibleOrder) {
    final visible = visibleOrder.iterator;
    final order = <String>[];
    for (final id in state.order) {
      if (state.hidden.contains(id)) {
        order.add(id);
      } else {
        visible.moveNext();
        order.add(visible.current);
      }
    }
    _set(state.copyWith(order: order));
  }

  void toggleHidden(String id) => _set(
    state.copyWith(
      hidden: state.hidden.contains(id)
          ? ({...state.hidden}..remove(id))
          : {...state.hidden, id},
    ),
  );

  void setSize(String id, HomeCardSize size) =>
      _set(state.copyWith(sizes: {...state.sizes, id: size}));

  void reset() => _set(HomeLayout.defaults());

  void _set(HomeLayout next) {
    _changed = true;
    state = next.normalized();
    unawaited(_save());
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kHomeLayoutKey, jsonEncode(state.toJson()));
    } catch (_) {
      // Keep the user's current session layout even if storage is unavailable.
    }
  }
}

extension on HomeLayout {
  HomeLayout copyWith({
    List<String>? order,
    Set<String>? hidden,
    Map<String, HomeCardSize>? sizes,
  }) => HomeLayout(
    order: order ?? this.order,
    hidden: hidden ?? this.hidden,
    sizes: sizes ?? this.sizes,
  );
}

final homeLayoutProvider = NotifierProvider<HomeLayoutNotifier, HomeLayout>(
  HomeLayoutNotifier.new,
);
