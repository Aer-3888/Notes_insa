import 'package:flutter/material.dart';

import 'tokens.dart';

/// Short names for what every widget reads. Nothing outside lib/theme builds
/// a Color or a TextStyle; it asks here.
extension CampusContext on BuildContext {
  CampusColors get campus => Theme.of(this).extension<CampusColors>()!;
  CampusTypography get campusType =>
      Theme.of(this).extension<CampusTypography>()!;
  ColorScheme get scheme => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}
