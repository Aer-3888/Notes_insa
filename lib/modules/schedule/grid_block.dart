import 'package:flutter/material.dart';

import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'module_palette.dart';
import 'schedule_event.dart';

enum BlockLabelDensity { none, moduleOnly, moduleAndRoom }

/// Measured in the shipped font at labelMedium: the shortest real module name
/// (`Algèbre 3`) needs 55.7 dp and `Amphi C` needs 47.4 dp. Below that a label
/// is an ellipsis, which tells the reader less than a bare bar does.
const double _minModuleWidth = 56;
const double _minModuleAndRoomWidth = 100;

/// Under this a block cannot hold one line of text whatever its width.
const double _minLabelHeight = 24;

BlockLabelDensity blockLabelDensity({
  required double width,
  required double height,
}) {
  if (height < _minLabelHeight) return BlockLabelDensity.none;
  if (width >= _minModuleAndRoomWidth) return BlockLabelDensity.moduleAndRoom;
  if (width >= _minModuleWidth) return BlockLabelDensity.moduleOnly;
  return BlockLabelDensity.none;
}

/// One event in the grid. Sizes itself to whatever the grid gives it and shows
/// as much as that size can honestly carry.
class GridBlock extends StatelessWidget {
  const GridBlock({required this.event, required this.onTap, super.key});

  final ScheduleEvent event;

  /// Null in the settings preview, where a block is a sample, not a control.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final campus = context.campus;
    final tint = ModulePalette.blocksOf(context).colorFor(
      ModulePalette.normalize(event.module ?? event.title),
      fallback: campus.surfaceContainerHighest,
    );
    return Material(
      color: tint,
      borderRadius: BorderRadius.circular(CampusRadii.bar),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CampusRadii.bar),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final density = blockLabelDensity(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
            );
            if (density == BlockLabelDensity.none) {
              return const SizedBox.expand();
            }
            return Padding(
              padding: const EdgeInsets.all(CampusSpacing.x1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      event.module ?? event.title,
                      style: context.text.labelMedium?.copyWith(
                        color: campus.onModuleBlockTint,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (density == BlockLabelDensity.moduleAndRoom &&
                      event.room != null)
                    Text(
                      event.room!,
                      style: context.text.labelMedium?.copyWith(
                        color: context.scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
