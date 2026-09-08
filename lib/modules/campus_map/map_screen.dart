import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/campus_navigation.dart';
import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'campus_geo.dart';
import 'campus_places.dart';
import 'map_painter.dart';

/// Carte: the INSA site drawn from baked OpenStreetMap geometry. Tapping a
/// building opens the places it holds; the search list stays as the second
/// way in.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, this.initialQuery, this.initialBuildingCode});

  /// Pre-fills the search, so another screen can point at one place.
  final String? initialQuery;

  /// Selects and frames this building once the map geometry is ready.
  final String? initialBuildingCode;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  late final TextEditingController _query = TextEditingController(
    text: widget.initialQuery ?? '',
  );
  final LabelCache _labels = LabelCache();

  CampusMapGeometry? _geometry;
  MapCamera? _camera;
  Size _size = Size.zero;
  String? _selected;
  int? _handledFocusRevision;
  bool _handledInitialBuilding = false;

  MapCamera _startCamera = const MapCamera(
    center: Offset.zero,
    metersPerPixel: 0.4,
  );
  Offset _startWorld = Offset.zero;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _openPlan() async {
    final opened = await launchUrl(
      Uri.parse(kCampusPlanUrl),
      mode: LaunchMode.externalApplication,
    );
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Impossible d’ouvrir le plan.')),
    );
  }

  void _ensureCamera(CampusGeo geo, Size size) {
    if (_geometry == null || !identical(_geometry!.geo, geo)) {
      _geometry = CampusMapGeometry(geo);
      _camera = null;
    }
    if (_camera == null || _size != size) {
      _size = size;
      _camera ??= MapCamera.fit(geo.siteBounds.inflate(30), size);
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    final cam = _camera;
    if (cam == null) return;
    _startCamera = cam;
    _startWorld = cam.toWorld(d.localFocalPoint, _size);
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Rect limit) {
    final cam = _camera;
    if (cam == null) return;
    final mpp = (_startCamera.metersPerPixel / d.scale).clamp(
      MapCamera.minMpp,
      MapCamera.maxMpp,
    );
    // Hold the world point under the fingers still, so pan and zoom come
    // out of one gesture without fighting each other.
    final probe = MapCamera(center: cam.center, metersPerPixel: mpp);
    final drift = _startWorld - probe.toWorld(d.localFocalPoint, _size);
    final next = cam.center + drift;
    setState(() {
      _camera = MapCamera(
        center: Offset(
          next.dx.clamp(limit.left, limit.right),
          next.dy.clamp(limit.top, limit.bottom),
        ),
        metersPerPixel: mpp,
      );
    });
  }

  void _onTapUp(TapUpDetails d, CampusGeo geo) {
    final cam = _camera;
    if (cam == null) return;
    final hit = geo.hitTest(cam.toWorld(d.localPosition, _size));
    setState(() => _selected = hit?.code);
    if (hit?.code != null) _showPlaces(hit!.code!, geo);
  }

  void _focus(String code, CampusGeo geo) {
    final b = geo.byCode(code);
    setState(() {
      _selected = code;
      if (b != null) {
        _camera = MapCamera(center: b.centroid, metersPerPixel: 0.22);
      }
    });
    FocusScope.of(context).unfocus();
    _showPlaces(code, geo);
  }

  void _queueFocus(String code, CampusGeo geo) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus(code, geo);
    });
  }

  void _applyRequestedFocus(CampusMapFocus? focus, CampusGeo geo) {
    final code = focus?.buildingCode;
    if (code != null && focus!.revision != _handledFocusRevision) {
      _handledFocusRevision = focus.revision;
      _queueFocus(code, geo);
      return;
    }
    final initialCode = widget.initialBuildingCode;
    if (!_handledInitialBuilding && initialCode != null) {
      _handledInitialBuilding = true;
      _queueFocus(initialCode, geo);
    }
  }

  void _showPlaces(String code, CampusGeo geo) {
    final places =
        ref.read(campusPlacesProvider).value ?? const <CampusPlace>[];
    final here = places.where((p) => p.code == code).toList();
    final building = geo.byCode(code);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            CampusSpacing.gutter,
            0,
            CampusSpacing.gutter,
            CampusSpacing.x4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bâtiment $code', style: context.text.titleLarge),
              if (building?.levels != null)
                Padding(
                  padding: const EdgeInsets.only(top: CampusSpacing.x1),
                  child: Text(
                    '${building!.levels} niveaux',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (geo.unmapped.containsKey(code))
                Padding(
                  padding: const EdgeInsets.only(top: CampusSpacing.x2),
                  child: Text(
                    'Ce bâtiment n’est pas encore situé sur la carte.',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: CampusSpacing.x3),
              for (final p in here)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(p.name),
                  subtitle: Text(p.kind.label),
                ),
              if (here.isEmpty)
                Text(
                  'Aucun lieu répertorié ici.',
                  style: context.text.bodyMedium?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  CampusMapPalette _palette(BuildContext context) {
    final c = context.campus;
    return CampusMapPalette(
      ground: c.surfaceLowest,
      path: c.outlineVariant,
      context: c.surfaceContainer,
      contextEdge: c.outlineVariant,
      building: c.surfaceContainerHighest,
      buildingEdge: c.outline,
      selected: c.now,
      selectedEdge: c.now,
    );
  }

  @override
  Widget build(BuildContext context) {
    final geoAsync = ref.watch(campusGeoProvider);
    final mapFocus = CampusNavigationScope.maybeOf(context)?.notifier;
    final places =
        ref.watch(campusPlacesProvider).value ?? const <CampusPlace>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Carte'),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Ouvrir le plan officiel',
            onPressed: _openPlan,
          ),
        ],
      ),
      body: geoAsync.when(
        // The geometry is a bundled asset, so this lasts a frame or two. A
        // spinner would only flash, and it never lets a test settle.
        loading: () => ColoredBox(color: context.campus.surfaceLowest),
        error: (_, _) => _fallback(places),
        data: (geo) =>
            geo.isEmpty ? _fallback(places) : _map(geo, places, mapFocus),
      ),
    );
  }

  Widget _map(
    CampusGeo geo,
    List<CampusPlace> places,
    CampusMapFocus? mapFocus,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _ensureCamera(geo, size);
        _applyRequestedFocus(mapFocus, geo);
        final limit = geo.siteBounds.inflate(120);
        return Stack(
          children: [
            Semantics(
              container: true,
              label:
                  'Plan du campus. Touchez un bâtiment pour voir ses '
                  'lieux, ou utilisez la recherche.',
              child: GestureDetector(
                onScaleStart: _onScaleStart,
                onScaleUpdate: (d) => _onScaleUpdate(d, limit),
                onTapUp: (d) => _onTapUp(d, geo),
                child: CustomPaint(
                  size: size,
                  painter: CampusMapPainter(
                    geometry: _geometry!,
                    camera: _camera!,
                    palette: _palette(context),
                    labels: _labels,
                    labelStyle: context.campusType.numeral.copyWith(
                      color: context.campus.onSurfaceVariant,
                    ),
                    selectedLabelStyle: context.campusType.numeral.copyWith(
                      color: context.campus.onNow,
                    ),
                    selected: _selected,
                  ),
                ),
              ),
            ),
            Positioned(
              left: CampusSpacing.gutter,
              right: CampusSpacing.gutter,
              top: CampusSpacing.x3,
              child: _search(geo, places),
            ),
            Positioned(
              left: CampusSpacing.x2,
              bottom: CampusSpacing.x2,
              child: Text(
                geo.attribution,
                style: context.text.labelSmall?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _search(CampusGeo geo, List<CampusPlace> places) {
    final q = _query.text.trim();
    final matches = q.isEmpty
        ? const <CampusPlace>[]
        : places.where((p) => p.matches(q)).take(8).toList();
    return Material(
      elevation: 2,
      borderRadius: CampusRadii.controlRadius,
      clipBehavior: Clip.antiAlias,
      color: context.campus.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'Rechercher un bâtiment, un amphi…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Effacer la recherche',
                      onPressed: () => setState(_query.clear),
                    ),
            ),
          ),
          if (q.isNotEmpty && matches.isEmpty)
            const Padding(
              padding: EdgeInsets.all(CampusSpacing.x4),
              child: Text('Aucun lieu ne correspond.'),
            ),
          for (final p in matches)
            ListTile(
              dense: true,
              leading: SizedBox(
                width: CampusSpacing.x8,
                child: Text(
                  p.code,
                  style: context.campusType.numeral,
                  semanticsLabel: 'Bâtiment ${p.code}',
                ),
              ),
              title: Text(p.name),
              onTap: () => _focus(p.code, geo),
            ),
        ],
      ),
    );
  }

  /// The v0 list, kept for when the geometry will not load.
  Widget _fallback(List<CampusPlace> places) {
    final matches = places.where((p) => p.matches(_query.text)).toList();
    return ListView(
      padding: const EdgeInsets.all(CampusSpacing.gutter),
      children: [
        Text(
          'La carte n’a pas pu se charger. En attendant :',
          style: context.text.bodyLarge,
        ),
        const SizedBox(height: CampusSpacing.x4),
        FilledButton.icon(
          onPressed: _openPlan,
          icon: const Icon(Icons.open_in_new),
          label: const Text('Ouvrir le plan officiel'),
        ),
        const SizedBox(height: CampusSpacing.x6),
        TextField(
          controller: _query,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Rechercher un bâtiment, un amphi…',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        for (final kind in PlaceKind.values)
          if (matches.any((p) => p.kind == kind)) ...[
            Padding(
              padding: const EdgeInsets.only(
                top: CampusSpacing.x5,
                bottom: CampusSpacing.x1,
              ),
              child: Text(
                kind.label,
                style: context.text.labelMedium?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final place in matches.where((p) => p.kind == kind))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: SizedBox(
                  width: CampusSpacing.x10,
                  child: Text(
                    place.code,
                    style: context.campusType.numeral,
                    semanticsLabel: 'Bâtiment ${place.code}',
                  ),
                ),
                title: Text(place.name),
              ),
          ],
      ],
    );
  }
}
