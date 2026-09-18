import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../modules/associations/associations_today_card.dart';
import '../modules/crous/crous_today_card.dart';
import '../modules/library/library_today_card.dart';
import '../modules/registry.dart';
import '../modules/schedule/event_sheet.dart';
import '../modules/schedule/upcoming_courses_card.dart';
import '../modules/weather/weather_screen.dart';
import '../theme/campus_context.dart';
import '../theme/tokens.dart';
import 'home_layout_provider.dart';
import 'module_card.dart';

/// A personalizable dashboard whose cards keep a local user-defined layout.
class HomeHubScreen extends ConsumerStatefulWidget {
  const HomeHubScreen({super.key, this.onOpenModule});

  final void Function(String moduleId)? onOpenModule;

  @override
  ConsumerState<HomeHubScreen> createState() => _HomeHubScreenState();
}

class _HomeHubScreenState extends ConsumerState<HomeHubScreen> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(homeLayoutProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Modifier l’accueil' : 'Aujourd’hui'),
        actions: <Widget>[
          if (_editing) ...<Widget>[
            TextButton(
              onPressed: ref.read(homeLayoutProvider.notifier).reset,
              child: const Text('Réinitialiser'),
            ),
            TextButton(
              onPressed: () => setState(() => _editing = false),
              child: const Text('Terminé'),
            ),
          ] else
            IconButton(
              tooltip: 'Modifier l’accueil',
              onPressed: () => setState(() => _editing = true),
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: _editing
          ? _HomeLayoutEditor(layout: layout)
          : _HomeDashboard(layout: layout, onOpenModule: widget.onOpenModule),
    );
  }
}

class _HomeDashboard extends ConsumerWidget {
  const _HomeDashboard({required this.layout, required this.onOpenModule});

  final HomeLayout layout;
  final void Function(String moduleId)? onOpenModule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = layout.order
        .where((id) => !layout.hidden.contains(id))
        .toList();
    final slivers = <Widget>[
      const SliverToBoxAdapter(child: SizedBox(height: CampusSpacing.x2)),
    ];
    var modules = <String>[];

    void addModules() {
      if (modules.isEmpty) return;
      slivers.add(
        SliverToBoxAdapter(
          child: _ModuleShortcuts(
            ids: modules,
            layout: layout,
            onOpenModule: onOpenModule,
          ),
        ),
      );
      modules = <String>[];
    }

    for (final id in visible) {
      if (layout.isModule(id)) {
        modules.add(id);
        continue;
      }
      addModules();
      slivers.add(SliverToBoxAdapter(child: _todayCard(context, id, ref)));
    }
    addModules();
    return CustomScrollView(slivers: slivers);
  }

  Widget _todayCard(BuildContext context, String id, WidgetRef ref) =>
      switch (id) {
        kCoursesCardId => UpcomingCoursesCard(
          onOpenEvent: (event) => unawaited(showEventSheet(context, event)),
        ),
        'weather' => const WeatherStrip(),
        'crous' => const CrousTodayCard(),
        'library' => const LibraryTodayCard(),
        'associations' => const AssociationsTodayCard(),
        _ => const SizedBox.shrink(),
      };
}

class _ModuleShortcuts extends StatelessWidget {
  const _ModuleShortcuts({
    required this.ids,
    required this.layout,
    required this.onOpenModule,
  });

  final List<String> ids;
  final HomeLayout layout;
  final void Function(String moduleId)? onOpenModule;

  @override
  Widget build(BuildContext context) {
    final modules = <String, ReadyModule>{
      for (final module in kCampusModules.whereType<ReadyModule>())
        moduleCardId(module.id): module,
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - CampusSpacing.gutter * 2;
        final unit = (width - CampusSpacing.x3 * 3) / 4;
        final placements = _packCards(ids, layout.sizeOf, unit, width);
        final height = placements.isEmpty
            ? 0.0
            : placements
                  .map((placement) => placement.rect.bottom)
                  .reduce((a, b) => a > b ? a : b);
        return Padding(
          padding: const EdgeInsets.all(CampusSpacing.gutter),
          child: SizedBox(
            height: height,
            child: Stack(
              children: <Widget>[
                for (final placement in placements)
                  if (modules[placement.id] case final module?)
                    Positioned.fromRect(
                      rect: placement.rect,
                      child: ModuleCard(
                        module: module,
                        size: layout.sizeOf(placement.id),
                        onTap: () => onOpenModule?.call(module.id),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HomeLayoutEditor extends ConsumerStatefulWidget {
  const _HomeLayoutEditor({required this.layout});

  final HomeLayout layout;

  @override
  ConsumerState<_HomeLayoutEditor> createState() => _HomeLayoutEditorState();
}

class _HomeLayoutEditorState extends ConsumerState<_HomeLayoutEditor> {
  final _gridKey = GlobalKey();
  final _scrollController = ScrollController();
  final Map<String, HomeCardSize> _previewSizes = <String, HomeCardSize>{};
  late List<String> _order;
  String? _draggingId;
  String? _resizingId;
  HomeCardSize? _resizeStartSize;
  Size? _resizeExtent;
  Offset _resizeDelta = Offset.zero;

  HomeLayout get layout => widget.layout;

  @override
  void initState() {
    super.initState();
    _order = _visibleOrder(layout);
  }

  @override
  void didUpdateWidget(covariant _HomeLayoutEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_draggingId == null && _resizingId == null) {
      _order = _visibleOrder(layout);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  HomeCardSize _sizeOf(String id) => _previewSizes[id] ?? layout.sizeOf(id);

  void _startDrag(String id) => setState(() => _draggingId = id);

  void _updateDrag(DragUpdateDetails details, double unit, double wide) {
    final id = _draggingId;
    final renderObject = _gridKey.currentContext?.findRenderObject();
    if (id == null || renderObject is! RenderBox) return;
    final pointer = renderObject.globalToLocal(details.globalPosition);
    final others = _order.where((cardId) => cardId != id).toList();
    final placements = _packCards(
      _order,
      _sizeOf,
      unit,
      wide,
    ).where((placement) => placement.id != id).toList();

    var target = placements.length;
    for (var index = 0; index < placements.length; index++) {
      final center = placements[index].rect.center;
      final sameRow = (pointer.dy - center.dy).abs() < unit * .55;
      if (pointer.dy < center.dy - unit * .55 ||
          (sameRow && pointer.dx < center.dx)) {
        target = index;
        break;
      }
    }
    final next = <String>[...others]..insert(target, id);
    if (!listEquals(next, _order)) setState(() => _order = next);
    _autoScroll(details.globalPosition.dy);
  }

  void _autoScroll(double globalY) {
    if (!_scrollController.hasClients) return;
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    final localY = box.globalToLocal(Offset(0, globalY)).dy;
    const edge = 96.0;
    var delta = 0.0;
    if (localY < edge) {
      delta = -18;
    } else if (localY > box.size.height - edge) {
      delta = 18;
    }
    if (delta == 0) return;
    final position = _scrollController.position;
    _scrollController.jumpTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  void _finishDrag() {
    if (_draggingId == null) return;
    ref.read(homeLayoutProvider.notifier).setVisibleOrder(_order);
    setState(() => _draggingId = null);
  }

  void _startResize(String id) {
    setState(() {
      _resizingId = id;
      _resizeStartSize = _sizeOf(id);
      _resizeExtent = null;
      _resizeDelta = Offset.zero;
    });
  }

  void _updateResize(String id, Offset delta, double unit, double wide) {
    if (_resizingId != id || _resizeStartSize == null) return;
    _resizeDelta += delta;
    final start = _cardExtent(_resizeStartSize!, unit, wide);
    final wantedWidth = (start.width + _resizeDelta.dx)
        .clamp(unit, wide)
        .toDouble();
    final maxHeight = _cardExtent(HomeCardSize.square, unit, wide).height;
    final wantedHeight = (start.height + _resizeDelta.dy)
        .clamp(unit, maxHeight)
        .toDouble();
    var closest = _resizeStartSize!;
    var closestScore = double.infinity;
    for (final candidate in HomeCardSize.values) {
      final extent = _cardExtent(candidate, unit, wide);
      final score =
          (extent.width - wantedWidth).abs() +
          (extent.height - wantedHeight).abs();
      if (score < closestScore) {
        closest = candidate;
        closestScore = score;
      }
    }
    setState(() {
      _resizeExtent = Size(wantedWidth, wantedHeight);
      _previewSizes[id] = closest;
    });
  }

  void _finishResize(String id) {
    if (_resizingId != id) return;
    final size = _sizeOf(id);
    ref.read(homeLayoutProvider.notifier).setSize(id, size);
    setState(() {
      _resizingId = null;
      _resizeStartSize = null;
      _resizeExtent = null;
      _resizeDelta = Offset.zero;
      _previewSizes.remove(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(homeLayoutProvider.notifier);
    final hidden = layout.order
        .where((id) => layout.hidden.contains(id))
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth - CampusSpacing.gutter * 2;
        final unit = (wide - CampusSpacing.x3 * 3) / 4;
        final placements = _packCards(_order, _sizeOf, unit, wide);

        Rect cardRect(_GridPlacement placement) {
          final resizeExtent = _resizeExtent;
          if (_resizingId != placement.id || resizeExtent == null) {
            return placement.rect;
          }
          return Rect.fromLTWH(
            placement.rect.left,
            placement.rect.top,
            resizeExtent.width
                .clamp(unit, wide - placement.rect.left)
                .toDouble(),
            resizeExtent.height,
          );
        }

        final gridHeight = placements.isEmpty
            ? 0.0
            : placements
                  .map((placement) => cardRect(placement).bottom)
                  .reduce((a, b) => a > b ? a : b);
        return ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(CampusSpacing.gutter),
          children: <Widget>[
            Text(
              'Maintiens une carte pour la déplacer. Tire sa poignée en bas '
              'à droite pour changer sa taille.',
              style: context.text.bodyMedium?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: CampusSpacing.x3),
            SizedBox(
              key: _gridKey,
              height: gridHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  for (final placement in placements)
                    AnimatedPositioned.fromRect(
                      key: ValueKey<String>(placement.id),
                      rect: cardRect(placement),
                      duration: _resizingId == placement.id
                          ? Duration.zero
                          : const Duration(milliseconds: 210),
                      curve: Curves.easeOutCubic,
                      child: _EditableCard(
                        key: ValueKey<String>('home-edit-${placement.id}'),
                        id: placement.id,
                        extent: cardRect(placement).size,
                        preview: layout.isModule(placement.id)
                            ? null
                            : _editPreview(placement.id),
                        onHide: placement.id == kCoursesCardId
                            ? null
                            : () => notifier.toggleHidden(placement.id),
                        size: _sizeOf(placement.id),
                        dragging: _draggingId == placement.id,
                        onDragStarted: () => _startDrag(placement.id),
                        onDragUpdate: (details) =>
                            _updateDrag(details, unit, wide),
                        onDragEnd: _finishDrag,
                        onResizeStart: layout.isModule(placement.id)
                            ? () => _startResize(placement.id)
                            : null,
                        onResizeUpdate: layout.isModule(placement.id)
                            ? (delta) =>
                                  _updateResize(placement.id, delta, unit, wide)
                            : null,
                        onResizeEnd: layout.isModule(placement.id)
                            ? () => _finishResize(placement.id)
                            : null,
                      ),
                    ),
                ],
              ),
            ),
            if (hidden.isNotEmpty) ...<Widget>[
              const SizedBox(height: CampusSpacing.x6),
              Text('Cartes masquées', style: context.text.titleMedium),
              const SizedBox(height: CampusSpacing.x2),
              Wrap(
                spacing: CampusSpacing.x2,
                runSpacing: CampusSpacing.x2,
                children: <Widget>[
                  for (final id in hidden)
                    ActionChip(
                      avatar: Icon(_cardIcon(id), size: 18),
                      label: Text(_cardLabel(id)),
                      onPressed: () => notifier.toggleHidden(id),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _EditableCard extends StatelessWidget {
  const _EditableCard({
    super.key,
    required this.id,
    required this.extent,
    required this.preview,
    required this.onHide,
    required this.size,
    required this.dragging,
    required this.onDragStarted,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
  });

  final String id;
  final Size extent;
  final Widget? preview;
  final VoidCallback? onHide;
  final HomeCardSize size;
  final bool dragging;
  final VoidCallback onDragStarted;
  final DragUpdateCallback onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback? onResizeStart;
  final ValueChanged<Offset>? onResizeUpdate;
  final VoidCallback? onResizeEnd;

  @override
  Widget build(BuildContext context) {
    final module = _moduleFor(id);
    final visual = _cardVisual(context, module);
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: LongPressDraggable<String>(
            data: id,
            dragAnchorStrategy: childDragAnchorStrategy,
            onDragStarted: onDragStarted,
            onDragUpdate: onDragUpdate,
            onDragEnd: (_) => onDragEnd(),
            onDraggableCanceled: (_, _) => onDragEnd(),
            feedback: Material(
              color: Colors.transparent,
              elevation: 10,
              borderRadius: CampusRadii.cardRadius,
              child: SizedBox.fromSize(
                size: extent,
                child: _DragFeedback(id: id, size: size),
              ),
            ),
            childWhenDragging: DecoratedBox(
              decoration: BoxDecoration(
                color: context.scheme.primaryContainer.withValues(alpha: .45),
                borderRadius: CampusRadii.cardRadius,
                border: Border.all(color: context.scheme.primary, width: 2),
              ),
              child: const Center(child: Icon(Icons.drag_indicator)),
            ),
            child: AnimatedScale(
              scale: dragging ? .97 : 1,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: visual,
            ),
          ),
        ),
        if (!dragging && onResizeStart != null)
          Positioned(right: 0, bottom: 0, child: _resizeHandle(context)),
      ],
    );
  }

  Widget _resizeHandle(BuildContext context) => Semantics(
    label: 'Poignée de redimensionnement, taille ${_sizeLabel(size)}',
    child: MouseRegion(
      cursor: SystemMouseCursors.resizeDownRight,
      child: Listener(
        key: ValueKey<String>('home-resize-$id'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (event.buttons == kPrimaryButton) onResizeStart?.call();
        },
        onPointerMove: (event) {
          if (event.buttons == kPrimaryButton) {
            onResizeUpdate?.call(event.localDelta);
          }
        },
        onPointerUp: (_) => onResizeEnd?.call(),
        onPointerCancel: (_) => onResizeEnd?.call(),
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            EagerGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                  () => EagerGestureRecognizer(
                    allowedButtonsFilter: (buttons) =>
                        buttons == kPrimaryButton,
                  ),
                  (_) {},
                ),
          },
          child: Container(
            width: _compactEditChrome ? 32 : 48,
            height: _compactEditChrome ? 32 : 48,
            alignment: Alignment.bottomRight,
            padding: EdgeInsets.all(
              _compactEditChrome ? CampusSpacing.x1 : CampusSpacing.x2,
            ),
            decoration: BoxDecoration(
              color: context.scheme.surfaceContainerHighest,
              borderRadius: CampusRadii.controlRadius,
              border: Border.all(color: context.scheme.outlineVariant),
            ),
            child: Icon(
              Icons.south_east,
              size: 18,
              color: context.scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    ),
  );

  bool get _compactEditChrome =>
      size == HomeCardSize.dot || size == HomeCardSize.horizontal;

  Widget _cardVisual(BuildContext context, ReadyModule? module) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.scheme.surfaceContainerLow,
      borderRadius: CampusRadii.cardRadius,
      border: Border.all(color: context.scheme.outlineVariant),
    ),
    child: ClipRRect(
      borderRadius: CampusRadii.cardRadius,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: module == null
                    ? preview!
                    : ModuleCard(module: module, size: size, onTap: () {}),
              ),
            ),
          ),
          if (module == null)
            Positioned(
              top: CampusSpacing.x1,
              left: CampusSpacing.x1,
              child: _EditBadge(
                icon: Icons.drag_indicator,
                label: _cardLabel(id),
              ),
            ),
          if (onHide != null)
            Positioned(
              top: CampusSpacing.x1,
              left: module == null ? null : CampusSpacing.x1,
              right: module == null ? CampusSpacing.x1 : null,
              child: _RemoveCardButton(
                id: id,
                compact: module != null && _compactEditChrome,
                onPressed: onHide!,
              ),
            ),
        ],
      ),
    ),
  );
}

class _RemoveCardButton extends StatelessWidget {
  const _RemoveCardButton({
    required this.id,
    required this.compact,
    required this.onPressed,
  });

  final String id;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final dimension = compact ? 32.0 : 48.0;
    return IconButton.filledTonal(
      key: ValueKey<String>('home-remove-$id'),
      tooltip: 'Masquer la carte',
      constraints: BoxConstraints.tightFor(width: dimension, height: dimension),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
      icon: const Icon(Icons.remove, size: 18),
    );
  }
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.id, required this.size});

  final String id;
  final HomeCardSize size;

  @override
  Widget build(BuildContext context) {
    final module = _moduleFor(id);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.scheme.surfaceContainerLow,
        borderRadius: CampusRadii.cardRadius,
        border: Border.all(color: context.scheme.primary, width: 2),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(CampusSpacing.x2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(module?.icon ?? _cardIcon(id)),
              if (size != HomeCardSize.dot) ...<Widget>[
                const SizedBox(height: CampusSpacing.x1),
                Text(
                  _cardLabel(id),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: context.text.labelMedium,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EditBadge extends StatelessWidget {
  const _EditBadge({required this.icon, required this.label});

  final IconData icon;
  final String? label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: CampusSpacing.x2,
      vertical: CampusSpacing.x1,
    ),
    decoration: BoxDecoration(
      color: context.scheme.surfaceContainerHighest,
      borderRadius: CampusRadii.controlRadius,
      border: Border.all(color: context.scheme.outlineVariant),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 16),
        if (label != null) ...<Widget>[
          const SizedBox(width: CampusSpacing.x1),
          Text(label!, style: context.text.labelSmall),
        ],
      ],
    ),
  );
}

List<String> _visibleOrder(HomeLayout layout) =>
    layout.order.where((id) => !layout.hidden.contains(id)).toList();

class _GridSpan {
  const _GridSpan(this.columns, this.rows);

  final int columns;
  final int rows;
}

class _GridPlacement {
  const _GridPlacement(this.id, this.rect);

  final String id;
  final Rect rect;
}

_GridSpan _gridSpan(String id, HomeCardSize size) {
  if (!id.startsWith('module:')) {
    return id == 'weather' ? const _GridSpan(4, 1) : const _GridSpan(4, 3);
  }
  return switch (size) {
    HomeCardSize.dot => const _GridSpan(1, 1),
    HomeCardSize.horizontal => const _GridSpan(2, 1),
    HomeCardSize.square => const _GridSpan(2, 2),
    HomeCardSize.full => const _GridSpan(4, 2),
  };
}

List<_GridPlacement> _packCards(
  List<String> ids,
  HomeCardSize Function(String id) sizeOf,
  double unit,
  double fullWidth,
) {
  const columns = 4;
  const gap = CampusSpacing.x3;
  final occupied = <List<bool>>[];
  final placements = <_GridPlacement>[];

  void ensureRows(int count) {
    while (occupied.length < count) {
      occupied.add(List<bool>.filled(columns, false));
    }
  }

  for (final id in ids) {
    final span = _gridSpan(id, sizeOf(id));
    var row = 0;
    var column = 0;
    var found = false;
    while (!found) {
      ensureRows(row + span.rows);
      for (column = 0; column <= columns - span.columns; column++) {
        var fits = true;
        for (var y = row; y < row + span.rows && fits; y++) {
          for (var x = column; x < column + span.columns; x++) {
            if (occupied[y][x]) {
              fits = false;
              break;
            }
          }
        }
        if (fits) {
          found = true;
          break;
        }
      }
      if (!found) row++;
    }

    for (var y = row; y < row + span.rows; y++) {
      for (var x = column; x < column + span.columns; x++) {
        occupied[y][x] = true;
      }
    }
    final width = span.columns == columns
        ? fullWidth
        : span.columns * unit + (span.columns - 1) * gap;
    placements.add(
      _GridPlacement(
        id,
        Rect.fromLTWH(
          column * (unit + gap),
          row * (unit + gap),
          width,
          span.rows * unit + (span.rows - 1) * gap,
        ),
      ),
    );
  }
  return placements;
}

Size _cardExtent(HomeCardSize size, double unit, double fullWidth) =>
    switch (size) {
      HomeCardSize.dot => Size.square(unit),
      HomeCardSize.horizontal => Size(unit * 2 + CampusSpacing.x3, unit),
      HomeCardSize.square => Size.square(unit * 2 + CampusSpacing.x3),
      HomeCardSize.full => Size(fullWidth, unit * 2 + CampusSpacing.x3),
    };

String _sizeLabel(HomeCardSize size) => switch (size) {
  HomeCardSize.dot => 'icône',
  HomeCardSize.horizontal => 'horizontale',
  HomeCardSize.square => 'carrée',
  HomeCardSize.full => 'pleine largeur',
};

ReadyModule? _moduleFor(String id) {
  for (final module in kCampusModules.whereType<ReadyModule>()) {
    if (id == moduleCardId(module.id)) return module;
  }
  return null;
}

Widget _editPreview(String id) => switch (id) {
  kCoursesCardId => const UpcomingCoursesCard(),
  'weather' => const WeatherStrip(),
  'crous' => const CrousTodayCard(),
  'library' => const LibraryTodayCard(),
  'associations' => const AssociationsTodayCard(),
  _ => const SizedBox.shrink(),
};

IconData _cardIcon(String id) => switch (id) {
  kCoursesCardId => Icons.calendar_month_outlined,
  'weather' => Icons.wb_sunny_outlined,
  'crous' => Icons.restaurant_outlined,
  'library' => Icons.menu_book_outlined,
  'associations' => Icons.groups_outlined,
  _ =>
    kCampusModules
        .whereType<ReadyModule>()
        .where((module) => id == moduleCardId(module.id))
        .first
        .icon,
};

String _cardLabel(String id) {
  switch (id) {
    case kCoursesCardId:
      return 'Cours du jour';
    case 'weather':
      return 'Météo';
    case 'crous':
      return 'Restos U’';
    case 'library':
      return 'Bibliothèques';
    case 'associations':
      return 'Associations';
  }
  final moduleId = id.substring('module:'.length);
  for (final module in kCampusModules.whereType<ReadyModule>()) {
    if (module.id == moduleId) return module.label;
  }
  return moduleId;
}
