import 'package:flutter/material.dart';

import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'hidden_courses_scope.dart';
import 'module_palette.dart';
import 'schedule_event.dart';

enum BlockLabelDensity { none, moduleTruncated, moduleOnly, moduleAndRoom }

/// Measured in the shipped font at labelMedium: the shortest real module name
/// (`Algèbre 3`) needs 55.7 dp and `Amphi C` needs 47.4 dp.
const double _minModuleWidth = 56;
const double _minModuleAndRoomWidth = 100;

/// Narrowest block that still says something. It cannot hold a whole name, but
/// the first few letters separate two classes where a bare bar cannot.
const double kMinTruncatedLabelWidth = 40;

/// Under this a block cannot hold one line of text whatever its width.
const double _minLabelHeight = 24;

BlockLabelDensity blockLabelDensity({
  required double width,
  required double height,
}) {
  if (height < _minLabelHeight) return BlockLabelDensity.none;
  if (width >= _minModuleAndRoomWidth) return BlockLabelDensity.moduleAndRoom;
  if (width >= _minModuleWidth) return BlockLabelDensity.moduleOnly;
  if (width >= kMinTruncatedLabelWidth) {
    return BlockLabelDensity.moduleTruncated;
  }
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
    final scope = HiddenCoursesScope.maybeOf(context);
    final hidden = scope?.hides(event) ?? false;
    final block = Material(
      color: tint,
      borderRadius: BorderRadius.circular(CampusRadii.bar),
      child: InkWell(
        onTap: onTap,
        onLongPress: scope == null || onTap == null
            ? null
            : () => scope.onHide(context, event),
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
            final truncated = density == BlockLabelDensity.moduleTruncated;
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
                        decoration: hidden ? TextDecoration.lineThrough : null,
                      ),
                      maxLines: truncated ? 1 : 2,
                      // A fade keeps the letters an ellipsis would spend on
                      // itself, which is most of what a narrow block has.
                      softWrap: !truncated,
                      overflow: truncated
                          ? TextOverflow.fade
                          : TextOverflow.ellipsis,
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
    if (!hidden) return block;
    return Opacity(opacity: CampusOpacity.hidden, child: block);
  }
}
