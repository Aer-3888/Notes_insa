import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/campus_navigation.dart';
import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'campus_declination.dart';
import 'campus_geo.dart';
import 'campus_heading.dart';
import 'campus_location.dart';
import 'campus_places.dart';
import 'campus_route.dart';
import 'map_painter.dart';

enum _GuidanceStatus { stopped, active, paused }

enum _MapOrientation { northUp, headingUp }

/// Carte: the INSA site drawn from baked OpenStreetMap geometry. Tapping a
/// building opens the places it holds; the search list stays as the second
/// way in.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({
    super.key,
    this.initialQuery,
    this.initialBuildingCode,
    this.startGuidance = false,
  });

  /// Pre-fills the search, so another screen can point at one place.
  final String? initialQuery;

  /// Selects and frames this building once the map geometry is ready.
  final String? initialBuildingCode;

  /// Requests foreground location and starts a walking route once the initial
  /// building has been framed.
  final bool startGuidance;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// Compass samples arrive around 30 Hz and jitter by a degree or two, so
  /// the map eases toward them. Time constants in seconds, each covering
  /// about two thirds of the turn left to make.
  static const double _headingTau = 0.22;
  static const double _bearingTau = 0.12;

  /// Below this the filter snaps home, so a still phone stops repainting.
  static const double _settleDegrees = 0.25;

  /// A pinch always twists a little, so rotation starts only past this.
  static const double _rotationSlopDegrees = 10;

  late final TextEditingController _query = TextEditingController(
    text: widget.initialQuery ?? '',
  );
  final FocusNode _searchFocus = FocusNode();
  final LabelCache _labels = LabelCache();

  CampusMapGeometry? _geometry;
  MapCamera? _camera;
  Size _size = Size.zero;
  String? _selected;
  CampusRoute? _route;
  Offset? _currentLocation;
  double? _locationAccuracy;
  bool _locating = false;
  bool _locationPending = false;
  bool _searchVisible = false;
  _GuidanceStatus _guidanceStatus = _GuidanceStatus.stopped;
  String? _guidanceBuildingCode;
  StreamSubscription<CampusPosition>? _positionSubscription;
  StreamSubscription<CampusHeading>? _headingSubscription;
  _MapOrientation _mapOrientation = _MapOrientation.northUp;
  int? _handledFocusRevision;
  bool _handledInitialBuilding = false;
  bool _handledAutoLocate = false;
  bool _readDeclination = false;

  /// Added to a magnetic heading so the compass agrees with the geometry,
  /// which is drawn on true north.
  double _declination = 0;

  /// The camera rides on the walker. Any deliberate move of the map drops
  /// it, so the compass can turn a view the user aimed somewhere else.
  bool _followUser = false;

  bool _onScreen = true;
  bool _foreground = true;
  bool _rotating = false;
  bool _compassWarned = false;

  /// Smoothed device heading, drawn as the cone under the marker.
  double? _headingDegrees;
  double? _targetHeading;

  /// Where the camera is turning to when the compass is not driving it.
  double _targetBearing = 0;

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  MapCamera _startCamera = const MapCamera(
    center: Offset.zero,
    metersPerPixel: 0.4,
  );
  Offset _startWorld = Offset.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final onScreen = TickerMode.valuesOf(context).enabled;
    if (onScreen == _onScreen) return;
    _onScreen = onScreen;
    _syncSensors(rebuild: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _syncSensors();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTicker();
    _ticker.dispose();
    unawaited(_positionSubscription?.cancel());
    unawaited(_headingSubscription?.cancel());
    _searchFocus.dispose();
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

  void _toggleSearch() {
    setState(() => _searchVisible = !_searchVisible);
    if (_searchVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    } else {
      _searchFocus.unfocus();
    }
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
    _rotating = false;
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
    final twist = d.rotation * 180 / math.pi;
    if (!_rotating && twist.abs() > _rotationSlopDegrees) _rotating = true;
    final bearing = _rotating
        ? _wrapDegrees(_startCamera.bearingDegrees - twist)
        : cam.bearingDegrees;
    // Hold the world point under the fingers still, so pan, zoom and turn
    // come out of one gesture without fighting each other.
    final probe = MapCamera(
      center: cam.center,
      metersPerPixel: mpp,
      bearingDegrees: bearing,
    );
    final drift = _startWorld - probe.toWorld(d.localFocalPoint, _size);
    final next = cam.center + drift;
    // Pinching around the marker keeps following. Dragging the map away is
    // the user asking to look somewhere else.
    final panned = drift.distance / mpp > 4;
    final leavesCompass =
        _rotating && _mapOrientation == _MapOrientation.headingUp;
    setState(() {
      if (panned) _followUser = false;
      if (leavesCompass) _mapOrientation = _MapOrientation.northUp;
      _targetBearing = bearing;
      _camera = MapCamera(
        center: Offset(
          next.dx.clamp(limit.left, limit.right),
          next.dy.clamp(limit.top, limit.bottom),
        ),
        metersPerPixel: mpp,
        bearingDegrees: bearing,
      );
    });
    if (panned || leavesCompass) _syncSensors();
  }

  void _onTapUp(TapUpDetails d, CampusGeo geo) {
    final cam = _camera;
    if (cam == null) return;
    final hit = geo.hitTest(cam.toWorld(d.localPosition, _size));
    setState(() => _selected = hit?.code);
    if (hit?.code != null) _showPlaces(hit!.code!, geo);
  }

  void _focus(String code, CampusGeo geo, {bool showPlaces = true}) {
    final b = geo.byCode(code);
    setState(() {
      _selected = code;
      _followUser = false;
      if (b != null) {
        _camera = MapCamera(
          center: b.centroid,
          metersPerPixel: 0.22,
          bearingDegrees: _camera?.bearingDegrees ?? 0,
        );
      }
      _searchVisible = false;
    });
    FocusScope.of(context).unfocus();
    _syncSensors();
    if (showPlaces) _showPlaces(code, geo);
  }

  void _queueFocus(String code, CampusGeo geo, {bool startGuidance = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus(code, geo, showPlaces: false);
      if (startGuidance) {
        unawaited(_guideTo(code, geo));
        return;
      }
      // The caller asked for that building, but the walker still wants to
      // know where they stand while they look at it.
      unawaited(_locate(geo, silent: true, moveCamera: false));
    });
  }

  void _applyRequestedFocus(CampusMapFocus? focus, CampusGeo geo) {
    final code = focus?.buildingCode;
    if (code != null && focus!.revision != _handledFocusRevision) {
      _handledFocusRevision = focus.revision;
      _handledAutoLocate = true;
      _queueFocus(code, geo, startGuidance: focus.startGuidance);
      return;
    }
    final initialCode = widget.initialBuildingCode;
    if (!_handledInitialBuilding && initialCode != null) {
      _handledInitialBuilding = true;
      _handledAutoLocate = true;
      _queueFocus(initialCode, geo, startGuidance: widget.startGuidance);
      return;
    }
    if (_handledAutoLocate) return;
    _handledAutoLocate = true;
    // Opening the map is asking where you are. A refused permission or a
    // walker off campus keeps the whole site framed instead.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_locate(geo, silent: true));
    });
  }

  void _ensureDeclination(CampusGeo geo) {
    if (_readDeclination) return;
    _readDeclination = true;
    unawaited(
      ref
          .read(campusDeclinationSourceProvider)
          .at(geo.originLat, geo.originLon)
          .then((degrees) {
            if (mounted && degrees.isFinite) _declination = degrees;
          }),
    );
  }

  /// [silent] is for the fix the map takes on its own: a walker who never
  /// asked for it should not be told their permissions are wrong.
  Future<CampusPosition?> _readLocation({bool silent = false}) async {
    if (_locationPending) return null;
    _locationPending = true;
    // The spinner belongs to the button the user pressed, not to the fix the
    // map takes on its own.
    if (!silent) setState(() => _locating = true);
    try {
      return await ref.read(campusLocationSourceProvider).current();
    } on CampusLocationException catch (error) {
      if (mounted && !silent) _showLocationError(error.failure);
      return null;
    } catch (_) {
      if (mounted && !silent) {
        _showLocationError(CampusLocationFailure.unavailable);
      }
      return null;
    } finally {
      _locationPending = false;
      if (mounted && !silent) setState(() => _locating = false);
    }
  }

  void _showLocationError(CampusLocationFailure failure) {
    final message = switch (failure) {
      CampusLocationFailure.serviceDisabled =>
        'Activez la localisation de votre téléphone pour vous guider.',
      CampusLocationFailure.denied =>
        'La position est nécessaire pour calculer l’itinéraire.',
      CampusLocationFailure.deniedForever =>
        'Autorisez la localisation dans les réglages du téléphone.',
      CampusLocationFailure.unavailable =>
        'Votre position est momentanément indisponible.',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Sensors run only while this tab is on screen and the app is in front:
  /// the compass and the GPS both cost battery for a map nobody is reading.
  void _syncSensors({bool rebuild = true}) {
    final awake = _onScreen && _foreground;
    final cleared = _syncHeading(awake);
    _syncPosition(awake);
    if (!awake) _stopTicker();
    if (cleared && rebuild && mounted) setState(() {});
  }

  /// Returns true when the drawn heading was dropped, so the caller can
  /// repaint the marker without its cone.
  bool _syncHeading(bool awake) {
    // The cone under the marker is worth the sensor whenever the marker is
    // on the map, not only when the map turns.
    final wanted =
        awake &&
        (_mapOrientation == _MapOrientation.headingUp ||
            _currentLocation != null);
    if (wanted == (_headingSubscription != null)) return false;
    if (!wanted) {
      unawaited(_headingSubscription?.cancel());
      _headingSubscription = null;
      _targetHeading = null;
      final cleared = _headingDegrees != null;
      _headingDegrees = null;
      return cleared;
    }
    _headingSubscription = ref
        .read(campusHeadingSourceProvider)
        .watch()
        .listen(
          _onHeading,
          onError: (Object _, StackTrace _) => _headingUnavailable(),
        );
    return false;
  }

  void _syncPosition(bool awake) {
    // Compass mode keeps the fix alive too: CoreLocation only resolves true
    // north while a location is being tracked.
    final wanted =
        awake &&
        (_followUser ||
            _guidanceStatus == _GuidanceStatus.active ||
            (_mapOrientation == _MapOrientation.headingUp &&
                _currentLocation != null));
    if (wanted == (_positionSubscription != null)) return;
    if (!wanted) {
      unawaited(_positionSubscription?.cancel());
      _positionSubscription = null;
      return;
    }
    _positionSubscription = ref
        .read(campusLocationSourceProvider)
        .watch()
        .listen(
          _onPosition,
          onError: (Object _, StackTrace _) => _onPositionError(),
        );
  }

  void _onPosition(CampusPosition position) {
    final geo = _geometry?.geo;
    if (!mounted || geo == null) return;
    final location = geo.toLocal(position.latitude, position.longitude);
    final accuracy = position.accuracyMeters;
    final code = _guidanceStatus == _GuidanceStatus.active
        ? _guidanceBuildingCode
        : null;
    final route = code == null ? null : routeToBuilding(geo, location, code);
    setState(() {
      _currentLocation = location;
      _locationAccuracy = accuracy;
      if (route != null) _route = route;
      if (_followUser) _camera = _camera?.copyWith(center: location);
    });
    _syncSensors();
  }

  void _onPositionError() {
    if (!mounted) return;
    final guiding = _guidanceStatus == _GuidanceStatus.active;
    setState(() {
      _followUser = false;
      if (guiding) _guidanceStatus = _GuidanceStatus.paused;
    });
    _syncSensors();
    _showLocationError(CampusLocationFailure.unavailable);
  }

  void _toggleMapOrientation() {
    unawaited(HapticFeedback.selectionClick());
    if (_mapOrientation == _MapOrientation.headingUp ||
        (_camera?.bearingDegrees ?? 0) != 0) {
      _useNorthUp();
      return;
    }
    setState(() {
      _mapOrientation = _MapOrientation.headingUp;
      _compassWarned = false;
      final location = _currentLocation;
      if (location != null) {
        _followUser = true;
        _camera = _camera?.copyWith(center: location);
      }
    });
    _syncSensors();
    _startTicker();
  }

  void _onHeading(CampusHeading reading) {
    if (!mounted) return;
    final degrees = reading.degrees;
    if (degrees == null || !degrees.isFinite) {
      // One unreadable sample means hold the last heading. A compass that
      // never reads at all is the one worth a message.
      if (_targetHeading == null) _headingUnavailable();
      return;
    }
    if (reading.isCoarse) _warnCoarseCompass();
    // The sensor only moves the target and the ticker moves the map, so a
    // burst of samples cannot cost more than one rebuild per frame.
    _targetHeading = _wrapDegrees(
      reading.isTrueNorth ? degrees : degrees + _declination,
    );
    _startTicker();
  }

  void _warnCoarseCompass() {
    if (_compassWarned || _mapOrientation != _MapOrientation.headingUp) return;
    _compassWarned = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Boussole imprécise. Éloignez le téléphone des objets métalliques '
          'et dessinez un 8 dans l’air.',
        ),
      ),
    );
  }

  void _startTicker() {
    if (_ticker.isActive || !mounted) return;
    _lastTick = Duration.zero;
    _ticker.start();
  }

  void _stopTicker() {
    if (_ticker.isActive) _ticker.stop();
    _lastTick = Duration.zero;
  }

  void _onTick(Duration elapsed) {
    final dt =
        (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    if (dt <= 0) return;

    var settled = true;
    var heading = _headingDegrees;
    final target = _targetHeading;
    if (target != null) {
      if (heading == null) {
        heading = target;
      } else {
        final delta = _shortestHeadingDelta(heading, target);
        if (delta.abs() <= _settleDegrees) {
          heading = target;
        } else {
          heading = _wrapDegrees(heading + delta * _approach(dt, _headingTau));
          settled = false;
        }
      }
    }

    final camera = _camera;
    var bearing = camera?.bearingDegrees ?? 0;
    final bearingTarget = _mapOrientation == _MapOrientation.headingUp
        ? heading ?? bearing
        : _targetBearing;
    final bearingDelta = _shortestHeadingDelta(bearing, bearingTarget);
    if (bearingDelta.abs() <= _settleDegrees) {
      bearing = bearingTarget;
    } else {
      bearing = _wrapDegrees(
        bearing + bearingDelta * _approach(dt, _bearingTau),
      );
      settled = false;
    }

    if (heading != _headingDegrees ||
        (camera != null && bearing != camera.bearingDegrees)) {
      setState(() {
        _headingDegrees = heading;
        if (camera != null) _camera = camera.copyWith(bearingDegrees: bearing);
      });
    }
    if (settled) _stopTicker();
  }

  /// Share of the remaining angle to cover this frame, so the filter reads
  /// the same on a 60 Hz and a 120 Hz screen.
  double _approach(double dt, double tau) => 1 - math.exp(-dt / tau);

  double _shortestHeadingDelta(double from, double to) =>
      (to - from + 540) % 360 - 180;

  double _wrapDegrees(double degrees) => (degrees % 360 + 360) % 360;

  void _useNorthUp() {
    setState(() {
      _mapOrientation = _MapOrientation.northUp;
      _targetBearing = 0;
      _rotating = false;
    });
    _syncSensors();
    _startTicker();
  }

  void _headingUnavailable() {
    if (!mounted) return;
    final wasHeadingUp = _mapOrientation == _MapOrientation.headingUp;
    _targetHeading = null;
    setState(() => _headingDegrees = null);
    if (!wasHeadingUp) return;
    _useNorthUp();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('La boussole n’est pas disponible sur cet appareil.'),
      ),
    );
  }

  Future<void> _locate(
    CampusGeo geo, {
    bool silent = false,
    bool moveCamera = true,
  }) async {
    final position = await _readLocation(silent: silent);
    if (!mounted || position == null) return;
    final location = geo.toLocal(position.latitude, position.longitude);
    final buildingCode = _guidanceBuildingCode;
    final refreshedRoute = buildingCode == null
        ? null
        : routeToBuilding(geo, location, buildingCode);
    final onSite = geo.siteBounds.inflate(200).contains(location);
    setState(() {
      _currentLocation = location;
      _locationAccuracy = position.accuracyMeters;
      if (refreshedRoute != null) _route = refreshedRoute;
      if (moveCamera && (!silent || onSite)) {
        _followUser = true;
        _camera = MapCamera(
          center: location,
          metersPerPixel: 0.22,
          bearingDegrees: _camera?.bearingDegrees ?? 0,
        );
      }
    });
    _syncSensors();
  }

  void _toggleFollow(CampusGeo geo) {
    if (!_followUser) {
      unawaited(_locate(geo));
      return;
    }
    setState(() => _followUser = false);
    _syncSensors();
  }

  Future<void> _guideTo(String code, CampusGeo geo) async {
    final position = await _readLocation();
    if (!mounted || position == null) return;
    final location = geo.toLocal(position.latitude, position.longitude);
    final route = routeToBuilding(geo, location, code);
    if (route == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucun itinéraire piéton disponible vers ce bâtiment.'),
        ),
      );
      return;
    }
    setState(() {
      _selected = code;
      _currentLocation = location;
      _locationAccuracy = position.accuracyMeters;
      _route = route;
      _guidanceBuildingCode = code;
      _guidanceStatus = _GuidanceStatus.active;
      // The whole walk on screen reads better than its first ten metres. The
      // position button puts the camera back on the walker.
      _followUser = false;
      _camera = MapCamera.fit(
        route.bounds.inflate(12),
        _size,
        padding: 72,
      ).copyWith(bearingDegrees: _camera?.bearingDegrees ?? 0);
    });
    _syncSensors();
  }

  void _pauseGuidance() {
    if (_guidanceStatus != _GuidanceStatus.active) return;
    setState(() => _guidanceStatus = _GuidanceStatus.paused);
    _syncSensors();
  }

  void _resumeGuidance(CampusGeo geo) {
    final code = _guidanceBuildingCode;
    if (code == null || _guidanceStatus != _GuidanceStatus.paused) return;
    unawaited(_guideTo(code, geo));
  }

  void _cancelGuidance() {
    setState(() {
      _guidanceStatus = _GuidanceStatus.stopped;
      _guidanceBuildingCode = null;
      _route = null;
    });
    _syncSensors();
  }

  void _showPlaces(String code, CampusGeo geo) {
    final places =
        ref.read(campusPlacesProvider).value ?? const <CampusPlace>[];
    final here = places.where((p) => p.code == code).toList();
    final building = geo.byCode(code);
    final placeDetails = CampusPlaceDetailsScope.maybeOf(
      context,
    )?.builder(code);
    final sheetTitle = code.startsWith('RU-')
        ? building?.name ?? (here.isEmpty ? code : here.first.name)
        : 'Bâtiment $code';
    final guidanceHere = _guidanceBuildingCode == code;
    final guidancePaused =
        guidanceHere && _guidanceStatus == _GuidanceStatus.paused;
    final guidanceActive =
        guidanceHere && _guidanceStatus == _GuidanceStatus.active;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // Material 3 otherwise constrains modal sheets to 640 dp, leaving a
      // visible gap on either side on wider phones and tablets.
      constraints: BoxConstraints.tightFor(
        width: MediaQuery.sizeOf(context).width,
      ),
      builder: (context) => SizedBox(
        width: double.infinity,
        child: SafeArea(
          child: SingleChildScrollView(
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
                  Text(sheetTitle, style: context.text.titleLarge),
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
                  if (placeDetails != null) ...<Widget>[
                    const SizedBox(height: CampusSpacing.x3),
                    placeDetails,
                  ],
                  if (geo.entrances.any(
                    (entrance) => entrance.code == code && entrance.node >= 0,
                  )) ...[
                    const SizedBox(height: CampusSpacing.x3),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        if (guidancePaused) {
                          _resumeGuidance(geo);
                        } else if (guidanceActive) {
                          unawaited(_locate(geo));
                        } else {
                          unawaited(_guideTo(code, geo));
                        }
                      },
                      icon: Icon(
                        guidancePaused
                            ? Icons.play_arrow
                            : Icons.directions_walk,
                      ),
                      label: Text(
                        guidancePaused
                            ? 'Reprendre le guidage'
                            : guidanceActive
                            ? 'Revenir au guidage'
                            : 'Démarrer le guidage',
                      ),
                    ),
                  ],
                ],
              ),
            ),
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
            icon: Icon(_searchVisible ? Icons.close : Icons.search),
            tooltip: _searchVisible
                ? 'Fermer la recherche'
                : 'Rechercher un lieu',
            onPressed: _toggleSearch,
          ),
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
        _ensureDeclination(geo);
        _applyRequestedFocus(mapFocus, geo);
        final limit = geo.siteBounds.inflate(120);
        final headingUp = _mapOrientation == _MapOrientation.headingUp;
        final bearing = _camera?.bearingDegrees ?? 0;
        final turned =
            headingUp || _shortestHeadingDelta(0, bearing).abs() > 0.5;
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
                    route: _route?.points ?? const <Offset>[],
                    currentLocation: _currentLocation,
                    currentAccuracyMeters: _locationAccuracy,
                    currentHeadingDegrees: _headingDegrees,
                  ),
                ),
              ),
            ),
            if (_searchVisible)
              Positioned(
                left: CampusSpacing.gutter,
                right: CampusSpacing.gutter,
                top: CampusSpacing.x3,
                child: _search(geo, places),
              ),
            Positioned(
              right: CampusSpacing.gutter,
              bottom: _route == null ? CampusSpacing.x6 : CampusSpacing.x10 * 3,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    color: headingUp
                        ? context.scheme.secondaryContainer
                        : context.campus.surface,
                    elevation: 3,
                    shape: const CircleBorder(),
                    child: IconButton(
                      onPressed: _toggleMapOrientation,
                      tooltip: turned
                          ? 'Revenir au nord'
                          : 'Orienter selon ma direction',
                      // Off compass mode the needle keeps pointing north, so a
                      // map turned by hand still says which way it lies.
                      icon: headingUp
                          ? const Icon(Icons.navigation)
                          : Transform.rotate(
                              angle: -bearing * math.pi / 180,
                              child: const Icon(Icons.explore_outlined),
                            ),
                    ),
                  ),
                  const SizedBox(height: CampusSpacing.x2),
                  Material(
                    color: _followUser
                        ? context.scheme.secondaryContainer
                        : context.campus.surface,
                    elevation: 3,
                    shape: const CircleBorder(),
                    child: IconButton(
                      onPressed: _locating ? null : () => _toggleFollow(geo),
                      tooltip: _followUser
                          ? 'Ne plus suivre ma position'
                          : 'Afficher ma position',
                      icon: _locating
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _followUser
                                  ? Icons.my_location
                                  : Icons.location_searching,
                            ),
                    ),
                  ),
                ],
              ),
            ),
            if (_route != null) _guidancePanel(geo),
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

  Widget _guidancePanel(CampusGeo geo) {
    final route = _route!;
    final paused = _guidanceStatus == _GuidanceStatus.paused;
    final building = geo.byCode(route.buildingCode);
    final destination = route.buildingCode.startsWith('RU-')
        ? building?.name ?? route.buildingCode
        : 'bâtiment ${route.buildingCode}';
    return Positioned(
      left: CampusSpacing.gutter,
      right: CampusSpacing.gutter,
      bottom: CampusSpacing.x6,
      child: Material(
        color: context.campus.surface,
        elevation: 3,
        borderRadius: CampusRadii.cardRadius,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            CampusSpacing.x4,
            CampusSpacing.x2,
            CampusSpacing.x2,
            CampusSpacing.x2,
          ),
          child: Row(
            children: [
              Icon(paused ? Icons.pause_circle_outline : Icons.directions_walk),
              const SizedBox(width: CampusSpacing.x3),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      paused ? 'Guidage en pause' : 'Guidage en cours',
                      style: context.text.labelLarge,
                    ),
                    Text(
                      '${route.distanceMeters.round()} m · '
                      '${approximateWalkingTimeLabel(route.distanceMeters)} · '
                      '$destination',
                      style: context.text.bodySmall?.copyWith(
                        color: context.scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: paused ? () => _resumeGuidance(geo) : _pauseGuidance,
                tooltip: paused
                    ? 'Reprendre le guidage'
                    : 'Mettre le guidage en pause',
                icon: Icon(paused ? Icons.play_arrow : Icons.pause),
              ),
              IconButton(
                onPressed: _cancelGuidance,
                tooltip: 'Arrêter le guidage',
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
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
            focusNode: _searchFocus,
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
                  semanticsLabel: p.code.startsWith('RU-')
                      ? p.name
                      : 'Bâtiment ${p.code}',
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
