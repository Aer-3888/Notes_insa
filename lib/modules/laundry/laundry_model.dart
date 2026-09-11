import 'package:flutter/foundation.dart';

/// Collapsed machine state as computed by the Worker (see laundry.ts).
enum LaundryMachineState { free, busy, reserved, finished, broken, unknown }

LaundryMachineState _stateFromJson(String? raw) {
  switch (raw) {
    case 'free':
      return LaundryMachineState.free;
    case 'busy':
      return LaundryMachineState.busy;
    case 'reserved':
      return LaundryMachineState.reserved;
    case 'finished':
      return LaundryMachineState.finished;
    case 'broken':
      return LaundryMachineState.broken;
    default:
      return LaundryMachineState.unknown;
  }
}

@immutable
class LaundryMachine {
  const LaundryMachine({
    required this.name,
    required this.size,
    required this.state,
    required this.secLeft,
  });

  final String name;
  final String size;
  final LaundryMachineState state;

  /// Seconds left on the current cycle, 0 unless running.
  final int secLeft;

  bool get isFree => state == LaundryMachineState.free;

  factory LaundryMachine.fromJson(Map<String, dynamic> json) => LaundryMachine(
    name: json['name'] as String? ?? '?',
    size: json['size'] as String? ?? '',
    state: _stateFromJson(json['state'] as String?),
    secLeft: (json['secLeft'] as num?)?.toInt() ?? 0,
  );
}

@immutable
class LaundryGroup {
  const LaundryGroup({
    required this.free,
    required this.total,
    required this.machines,
  });

  final int free;
  final int total;
  final List<LaundryMachine> machines;

  factory LaundryGroup.fromJson(Map<String, dynamic> json) => LaundryGroup(
    free: (json['free'] as num?)?.toInt() ?? 0,
    total: (json['total'] as num?)?.toInt() ?? 0,
    machines: <LaundryMachine>[
      for (final raw in (json['machines'] as List? ?? const <dynamic>[]))
        LaundryMachine.fromJson(Map<String, dynamic>.from(raw as Map)),
    ],
  );
}

@immutable
class LaundrySite {
  const LaundrySite({
    required this.id,
    required this.name,
    required this.washers,
    required this.dryers,
  });

  final int id;
  final String name;
  final LaundryGroup washers;
  final LaundryGroup dryers;

  factory LaundrySite.fromJson(Map<String, dynamic> json) => LaundrySite(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String? ?? '',
    washers: LaundryGroup.fromJson(
      Map<String, dynamic>.from(json['washers'] as Map),
    ),
    dryers: LaundryGroup.fromJson(
      Map<String, dynamic>.from(json['dryers'] as Map),
    ),
  );
}

@immutable
class LaundryStatus {
  const LaundryStatus({
    required this.sites,
    required this.cachedAt,
    required this.stale,
  });

  final List<LaundrySite> sites;
  final DateTime? cachedAt;

  /// True when the Worker served a last-known snapshot after an upstream error.
  final bool stale;

  factory LaundryStatus.fromJson(Map<String, dynamic> json) => LaundryStatus(
    sites: <LaundrySite>[
      for (final raw in (json['sites'] as List? ?? const <dynamic>[]))
        LaundrySite.fromJson(Map<String, dynamic>.from(raw as Map)),
    ],
    cachedAt: DateTime.tryParse(json['cachedAt'] as String? ?? ''),
    stale: json['stale'] as bool? ?? false,
  );
}
