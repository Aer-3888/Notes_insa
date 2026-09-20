import 'package:flutter_riverpod/flutter_riverpod.dart';

enum RoomFreeDuration {
  now('Maintenant', Duration.zero),
  minutes30('30 min', Duration(minutes: 30)),
  hour('1 h', Duration(hours: 1)),
  hours2('2 h', Duration(hours: 2));

  const RoomFreeDuration(this.label, this.minimum);

  final String label;
  final Duration minimum;
}

class RoomFreeDurationNotifier extends Notifier<RoomFreeDuration> {
  @override
  RoomFreeDuration build() => RoomFreeDuration.now;

  void select(RoomFreeDuration value) => state = value;
}

final roomFreeDurationProvider =
    NotifierProvider<RoomFreeDurationNotifier, RoomFreeDuration>(
      RoomFreeDurationNotifier.new,
    );
