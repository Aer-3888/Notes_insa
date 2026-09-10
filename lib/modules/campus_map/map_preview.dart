import 'package:flutter/material.dart';

import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'campus_geo.dart';
import 'map_painter.dart';

/// A compact, non-interactive campus map focused on one highlighted building.
class CampusMapPreview extends StatelessWidget {
  const CampusMapPreview({
    required this.geo,
    required this.buildingCode,
    this.onTap,
    super.key,
  });

  final CampusGeo geo;
  final String buildingCode;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final building = geo.byCode(buildingCode);
    if (building == null) return const SizedBox.shrink();

    final campus = context.campus;
    final palette = CampusMapPalette(
      ground: campus.surfaceLowest,
      path: campus.outlineVariant,
      context: campus.surfaceContainer,
      contextEdge: campus.outlineVariant,
      building: campus.surfaceContainerHighest,
      buildingEdge: campus.outline,
      selected: campus.now,
      selectedEdge: campus.now,
    );

    return Semantics(
      button: onTap != null,
      label: 'Bâtiment $buildingCode sélectionné sur le plan du campus',
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: CampusRadii.cardRadius,
        ),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 156,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return CustomPaint(
                  size: size,
                  painter: CampusMapPainter(
                    geometry: CampusMapGeometry(geo),
                    camera: MapCamera.fit(
                      building.bounds.inflate(55),
                      size,
                      padding: CampusSpacing.x3,
                    ),
                    palette: palette,
                    labels: LabelCache(),
                    labelStyle: context.campusType.numeral.copyWith(
                      color: campus.onSurfaceVariant,
                    ),
                    selectedLabelStyle: context.campusType.numeral.copyWith(
                      color: campus.onNow,
                    ),
                    selected: buildingCode,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
