import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/quake_message.dart';
import '../widgets/map/map_config.dart';
import '../core/calculator.dart';
import '../core/travel_time_service.dart';
import '../core/utils/world_wrap.dart';
import '../core/utils/quake_time.dart';
import '../services/ntp_service.dart';
import 'dart:math';

enum MapCameraMode { autoFollow, manualLocked }

class MapStateProvider with ChangeNotifier {
  static const LatLng defaultCenter = LatLng(34.34127, 108.93984);
  static const double defaultZoom = 4.0;

  MapController? _mapController;
  QuakeMessage? _selectedHistoryEvent;
  String _tileKey = 'petalLight';
  final Map<String, bool> _overlayEnabled = {
    'cloudLayer': false,
    'windLayer': false,
    'rainLayer': false,
    'cnContour': false,
    'volcanoLayer': false,
    'typhoonLayer': true,
    'fdsnEarthScope': false,
    'fdsnGeofon': false,
  };

  bool _showEstimatedEpicenter = false;
  bool get showEstimatedEpicenter => _showEstimatedEpicenter;

  static const int _cameraAnimationFps = 60;

  bool _isAutoZoom = true;
  Timer? _autoZoomResumeTimer;
  Timer? _moveAnimationTimer;
  MapCameraMode _cameraMode = MapCameraMode.autoFollow;
  final Map<String, DateTime> _lastMoveBySource = {};
  String? _lastCameraKey;
  DateTime? _lastCameraMovedAt;

  QuakeMessage? get selectedHistoryEvent => _selectedHistoryEvent;
  String get tileKey => _tileKey;
  String get tileUrl => MapConfig.urlByKey(_tileKey);
  bool isOverlayEnabled(String key) => _overlayEnabled[key] ?? false;
  Map<String, bool> get overlayEnabledMap => Map.unmodifiable(_overlayEnabled);
  bool get isAutoZoom => _isAutoZoom;
  MapCameraMode get cameraMode => _cameraMode;
  bool get canAutoFollow =>
      _isAutoZoom && _cameraMode == MapCameraMode.autoFollow;

  void setTileKey(String key) {
    final normalized = MapConfig.normalizeBaseTileKey(key);
    if (_tileKey == normalized) return;
    _tileKey = normalized;
    MapConfig.currentTileUrl = MapConfig.urlByKey(normalized);
    _logBaseTileState('changed');
    notifyListeners();
  }

  void refreshTileConfig() {
    MapConfig.currentTileUrl = MapConfig.urlByKey(_tileKey);
    _logBaseTileState('refreshed');
    notifyListeners();
  }

  void _logBaseTileState(String action) {
    if (_tileKey == MapConfig.tencentJsMapKey) {
      debugPrint(
        '[MapTile] base tile $action: key=$_tileKey mode=js-api '
        'apiKey=${MapConfig.hasTencentWmtsApiKey ? "set" : "empty"}',
      );
      return;
    }
    if (_tileKey == MapConfig.tencentStaticMapKey ||
        _tileKey == MapConfig.tencentWmtsKey) {
      debugPrint(
        '[MapTile] base tile $action: key=$_tileKey '
        'url=${MapConfig.redactTencentWmtsUrl(MapConfig.currentTileUrl)}',
      );
      return;
    }
    debugPrint('[MapTile] base tile $action: key=$_tileKey');
  }

  void setOverlayEnabled(String key, bool enabled) {
    if (!_overlayEnabled.containsKey(key)) return;
    if (_overlayEnabled[key] == enabled) return;
    _overlayEnabled[key] = enabled;
    notifyListeners();
  }

  void setShowEstimatedEpicenter(bool show) {
    if (_showEstimatedEpicenter == show) return;
    _showEstimatedEpicenter = show;
    notifyListeners();
  }

  void selectHistoryEvent(QuakeMessage? event) {
    if (_selectedHistoryEvent?.eventId == event?.eventId && event != null) {
      return;
    }
    _selectedHistoryEvent = event;
    notifyListeners();
  }

  bool get isHistoryEventSelected => _selectedHistoryEvent != null;

  bool isSelectedHistoryEvent(QuakeMessage event) {
    return _selectedHistoryEvent?.eventId == event.eventId &&
        _selectedHistoryEvent?.source == event.source;
  }

  void clearSelectedHistoryEvent() {
    if (_selectedHistoryEvent == null) return;
    _selectedHistoryEvent = null;
    notifyListeners();
  }

  MapController? get mapController => _mapController;

  void setController(MapController controller, TickerProvider _) {
    final changed = !identical(_mapController, controller);
    _mapController = controller;
    if (changed) {
      notifyListeners();
    }
  }

  void pauseAutoZoom({Duration resumeAfter = const Duration(seconds: 60)}) {
    final wasAutoFollow = canAutoFollow;
    _isAutoZoom = false;
    _cameraMode = MapCameraMode.manualLocked;
    _autoZoomResumeTimer?.cancel();
    _autoZoomResumeTimer = Timer(resumeAfter, () {
      resumeAutoZoom();
    });
    if (wasAutoFollow) {
      notifyListeners();
    }
  }

  void resumeAutoZoom() {
    _isAutoZoom = true;
    _autoZoomResumeTimer?.cancel();
    _cameraMode = MapCameraMode.autoFollow;
    notifyListeners();
  }

  void recenterToDefaultView({bool animate = true}) {
    pauseAutoZoom();
    if (_mapController == null) return;
    _doAnimatedMove(defaultCenter, defaultZoom, animate, wrapLongitude: false);
  }

  void animatedMove(LatLng destLocation, double destZoom) {
    if (_mapController == null) return;
    _doAnimatedMove(destLocation, destZoom, true);
  }

  void animatedMoveNoAnimate(LatLng destLocation, double destZoom) {
    if (_mapController == null) return;
    _doAnimatedMove(destLocation, destZoom, false);
  }

  void moveToDefaultView({bool animate = true, bool pauseAuto = true}) {
    if (pauseAuto) {
      pauseAutoZoom();
    } else {
      _cameraMode = MapCameraMode.autoFollow;
    }
    if (_mapController == null) return;
    _doAnimatedMove(defaultCenter, defaultZoom, animate, wrapLongitude: false);
  }

  void animatedMoveWithScreenOffset(
    LatLng focusLocation,
    double destZoom,
    Offset screenOffset,
  ) {
    if (_mapController == null) return;

    final currCenter = _mapController!.camera.center;
    final wrappedFocus = LatLng(
      focusLocation.latitude,
      WorldWrap.longitudeClosestTo(
        focusLocation.longitude,
        currCenter.longitude,
      ),
    );
    final proj = _mapController!.camera.crs.projection;
    final focusPoint = proj.project(wrappedFocus);
    final adjustedCenter = proj.unproject(
      Point(focusPoint.dx - screenOffset.dx, focusPoint.dy - screenOffset.dy),
    );
    _doAnimatedMove(adjustedCenter, destZoom, true);
  }

  void _doAnimatedMove(
    LatLng destLocation,
    double destZoom,
    bool animate, {
    bool wrapLongitude = true,
  }) {
    if (_mapController == null) return;

    final currCenter = _mapController!.camera.center;
    final dest = wrapLongitude
        ? LatLng(
            destLocation.latitude,
            WorldWrap.longitudeClosestTo(
              destLocation.longitude,
              currCenter.longitude,
            ),
          )
        : destLocation;
    final currZoom = _mapController!.camera.zoom;
    final zoomDiff = (destZoom - currZoom).abs();

    _stopMoveAnimation();

    if (!animate || zoomDiff > 4) {
      _mapController!.move(dest, destZoom);
      return;
    }

    final latTween = Tween<double>(
      begin: currCenter.latitude,
      end: dest.latitude,
    );
    final lngTween = Tween<double>(
      begin: currCenter.longitude,
      end: dest.longitude,
    );
    final zoomTween = Tween<double>(begin: currZoom, end: destZoom);

    const duration = Duration(milliseconds: 800);
    final stopwatch = Stopwatch()..start();

    void tick() {
      final rawT = stopwatch.elapsedMicroseconds / duration.inMicroseconds;
      final t = rawT.clamp(0.0, 1.0);
      final eased = Curves.fastOutSlowIn.transform(t);
      _mapController!.move(
        LatLng(latTween.transform(eased), lngTween.transform(eased)),
        zoomTween.transform(eased),
      );
      if (t >= 1.0) {
        _stopMoveAnimation();
      }
    }

    tick();
    _moveAnimationTimer = Timer.periodic(
      const Duration(milliseconds: 1000 ~/ _cameraAnimationFps),
      (_) => tick(),
    );
  }

  void _stopMoveAnimation() {
    final timer = _moveAnimationTimer;
    if (timer == null) return;
    _moveAnimationTimer = null;
    timer.cancel();
  }

  LatLngBounds? calcBoundsForEvents(List<QuakeMessage> events) {
    final valid = events
        .where((e) => e.latitude != 0.0 || e.longitude != 0.0)
        .toList();
    if (valid.isEmpty) return null;

    double minLat = double.infinity;
    double maxLat = double.negativeInfinity;
    double minLng = double.infinity;
    double maxLng = double.negativeInfinity;

    for (final e in valid) {
      if (e.latitude < minLat) minLat = e.latitude;
      if (e.latitude > maxLat) maxLat = e.latitude;
      if (e.longitude < minLng) minLng = e.longitude;
      if (e.longitude > maxLng) maxLng = e.longitude;
    }

    return LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }

  void smartMoveToEvents(
    List<QuakeMessage> events, {
    double padding = 2.0,
    List<QuakeMessage> waveEvents = const [],
    List<LatLng> gridPoints = const [],
    double minZoom = 3.0,
    double maxZoom = 8.0,
    Offset screenOffset = Offset.zero,
    bool respectAutoZoom = true,
    String sourceTag = 'events',
    bool force = false,
    Duration minInterval = const Duration(milliseconds: 900),
  }) {
    if (!_canApplyAutoMove(respectAutoZoom)) return;
    if (_mapController == null) return;
    if (events.isEmpty) return;

    // kanameishi: 观测网激活时用网格点代替 S 波填充 (与 kanameishi-dev 一致)
    final effectiveWaveEvents = gridPoints.isNotEmpty
        ? const <QuakeMessage>[]
        : waveEvents;
    final view = _calcWrappedEventView(
      events,
      waveEvents: effectiveWaveEvents,
      gridPoints: gridPoints,
    );
    if (view == null) return;

    final center = view.center;
    final maxDiff = max(view.latDiff, view.lngDiff) + padding * 2;
    final zoom = _zoomForDiff(maxDiff).clamp(minZoom, maxZoom).toDouble();
    final targetCenter = screenOffset == Offset.zero
        ? center
        : _centerForScreenOffset(center, zoom, screenOffset);

    final currCenter = _mapController!.camera.center;
    final currZoom = _mapController!.camera.zoom;
    final err = 1 / pow(2, zoom);
    if (currZoom == zoom &&
        (currCenter.latitude - targetCenter.latitude).abs() < err &&
        (currCenter.longitude - targetCenter.longitude).abs() < err) {
      return;
    }
    if (!_acquireMovePermit(
      sourceTag,
      targetCenter,
      zoom,
      force,
      minInterval,
    )) {
      return;
    }

    if (screenOffset == Offset.zero) {
      animatedMove(center, zoom);
    } else {
      animatedMoveWithScreenOffset(center, zoom, screenOffset);
    }
  }

  void smartMoveToPoints(
    List<LatLng> points, {
    double padding = 1.5,
    double minZoom = 3.0,
    double maxZoom = 8.0,
    Offset screenOffset = Offset.zero,
    bool respectAutoZoom = true,
    String sourceTag = 'points',
    bool force = false,
    Duration minInterval = const Duration(milliseconds: 900),
  }) {
    if (!_canApplyAutoMove(respectAutoZoom)) return;
    if (_mapController == null) return;
    if (points.isEmpty) return;

    final view = _calcWrappedPointView(points);
    if (view == null) return;

    final maxDiff = max(view.latDiff, view.lngDiff) + padding * 2;
    final zoom = _zoomForDiff(maxDiff).clamp(minZoom, maxZoom).toDouble();
    final targetCenter = screenOffset == Offset.zero
        ? view.center
        : _centerForScreenOffset(view.center, zoom, screenOffset);
    final currCenter = _mapController!.camera.center;
    final currZoom = _mapController!.camera.zoom;
    final err = 1 / pow(2, zoom);
    if (currZoom == zoom &&
        (currCenter.latitude - targetCenter.latitude).abs() < err &&
        (currCenter.longitude - targetCenter.longitude).abs() < err) {
      return;
    }
    if (!_acquireMovePermit(
      sourceTag,
      targetCenter,
      zoom,
      force,
      minInterval,
    )) {
      return;
    }

    if (screenOffset == Offset.zero) {
      animatedMove(view.center, zoom);
    } else {
      animatedMoveWithScreenOffset(view.center, zoom, screenOffset);
    }
  }

  void smartMoveToCenter(
    LatLng center, {
    required double zoom,
    Offset screenOffset = Offset.zero,
    bool respectAutoZoom = true,
    String sourceTag = 'center',
    bool force = false,
    Duration minInterval = const Duration(milliseconds: 900),
  }) {
    if (!_canApplyAutoMove(respectAutoZoom)) return;
    if (_mapController == null) return;

    final targetCenter = screenOffset == Offset.zero
        ? LatLng(
            center.latitude,
            WorldWrap.longitudeClosestTo(
              center.longitude,
              _mapController!.camera.center.longitude,
            ),
          )
        : _centerForScreenOffset(center, zoom, screenOffset);
    final currCenter = _mapController!.camera.center;
    final currZoom = _mapController!.camera.zoom;
    final err = 1 / pow(2, zoom);
    if (currZoom == zoom &&
        (currCenter.latitude - targetCenter.latitude).abs() < err &&
        (currCenter.longitude - targetCenter.longitude).abs() < err) {
      return;
    }
    if (!_acquireMovePermit(
      sourceTag,
      targetCenter,
      zoom,
      force,
      minInterval,
    )) {
      return;
    }

    if (screenOffset == Offset.zero) {
      animatedMove(targetCenter, zoom);
    } else {
      animatedMoveWithScreenOffset(center, zoom, screenOffset);
    }
  }

  LatLng _centerForScreenOffset(
    LatLng focusLocation,
    double destZoom,
    Offset screenOffset,
  ) {
    final currCenter = _mapController!.camera.center;
    final wrappedFocus = LatLng(
      focusLocation.latitude,
      WorldWrap.longitudeClosestTo(
        focusLocation.longitude,
        currCenter.longitude,
      ),
    );
    final proj = _mapController!.camera.crs.projection;
    final focusPoint = proj.project(wrappedFocus);
    return proj.unproject(
      Point(focusPoint.dx - screenOffset.dx, focusPoint.dy - screenOffset.dy),
    );
  }

  _WrappedEventView? _calcWrappedEventView(
    List<QuakeMessage> events, {
    List<QuakeMessage> waveEvents = const [],
    List<LatLng> gridPoints = const [],
  }) {
    final validEvents = events
        .where((e) => e.latitude != 0.0 || e.longitude != 0.0)
        .toList();
    if (validEvents.isEmpty) return null;

    double minLat = double.infinity;
    double maxLat = double.negativeInfinity;
    final longitudes = <double>[];

    for (final e in validEvents) {
      _addPointToView(e.latitude, e.longitude, longitudes, (lat) {
        if (lat < minLat) minLat = lat;
        if (lat > maxLat) maxLat = lat;
      });
    }

    for (final e in waveEvents) {
      if (e.latitude == 0.0 && e.longitude == 0.0) continue;
      final radiusKm = _calcAutoZoomWaveRadiusKm(e);
      if (radiusKm <= 0) continue;

      final latDelta = radiusKm / 111.32;
      final minWaveLat = (e.latitude - latDelta).clamp(-85.0, 85.0);
      final maxWaveLat = (e.latitude + latDelta).clamp(-85.0, 85.0);
      if (minWaveLat < minLat) minLat = minWaveLat;
      if (maxWaveLat > maxLat) maxLat = maxWaveLat;

      final cosLat = max(cos(e.latitude * pi / 180).abs(), 0.15);
      final lngDelta = (radiusKm / (111.32 * cosLat)).clamp(0.0, 180.0);
      longitudes.add(_toPositiveLongitude(e.longitude - lngDelta));
      longitudes.add(_toPositiveLongitude(e.longitude + lngDelta));
    }

    // kanameishi: 观测网网格点扩展视口 (替代 S 波填充)
    for (final pt in gridPoints) {
      _addPointToView(pt.latitude, pt.longitude, longitudes, (lat) {
        if (lat < minLat) minLat = lat;
        if (lat > maxLat) maxLat = lat;
      });
    }

    longitudes.sort();

    var largestGap = -1.0;
    var largestGapIndex = 0;
    for (int i = 0; i < longitudes.length; i++) {
      final current = longitudes[i];
      final next = i == longitudes.length - 1
          ? longitudes.first + 360
          : longitudes[i + 1];
      final gap = next - current;
      if (gap > largestGap) {
        largestGap = gap;
        largestGapIndex = i;
      }
    }

    final startIndex = (largestGapIndex + 1) % longitudes.length;
    final startLng = longitudes[startIndex];
    final endLng = startIndex == 0
        ? longitudes[largestGapIndex]
        : longitudes[largestGapIndex] + 360;
    final centerLng = (startLng + endLng) / 2;

    return _WrappedEventView(
      center: LatLng((minLat + maxLat) / 2, centerLng),
      latDiff: maxLat - minLat,
      lngDiff: endLng - startLng,
    );
  }

  _WrappedEventView? _calcWrappedPointView(List<LatLng> points) {
    if (points.isEmpty) return null;

    double minLat = double.infinity;
    double maxLat = double.negativeInfinity;
    final longitudes = <double>[];

    for (final point in points) {
      _addPointToView(point.latitude, point.longitude, longitudes, (lat) {
        if (lat < minLat) minLat = lat;
        if (lat > maxLat) maxLat = lat;
      });
    }

    longitudes.sort();

    var largestGap = -1.0;
    var largestGapIndex = 0;
    for (int i = 0; i < longitudes.length; i++) {
      final current = longitudes[i];
      final next = i == longitudes.length - 1
          ? longitudes.first + 360
          : longitudes[i + 1];
      final gap = next - current;
      if (gap > largestGap) {
        largestGap = gap;
        largestGapIndex = i;
      }
    }

    final startIndex = (largestGapIndex + 1) % longitudes.length;
    final startLng = longitudes[startIndex];
    final endLng = startIndex == 0
        ? longitudes[largestGapIndex]
        : longitudes[largestGapIndex] + 360;
    final centerLng = (startLng + endLng) / 2;

    return _WrappedEventView(
      center: LatLng((minLat + maxLat) / 2, centerLng),
      latDiff: maxLat - minLat,
      lngDiff: endLng - startLng,
    );
  }

  double _zoomForDiff(double maxDiff) {
    if (maxDiff > 20) return 3.0;
    if (maxDiff > 10) return 4.0;
    if (maxDiff > 5) return 5.0;
    if (maxDiff > 2) return 6.0;
    if (maxDiff > 1) return 7.0;
    return 8.0;
  }

  double _toPositiveLongitude(double longitude) {
    final normalized = WorldWrap.normalizeLongitude(longitude);
    return normalized < 0 ? normalized + 360 : normalized;
  }

  void _addPointToView(
    double latitude,
    double longitude,
    List<double> longitudes,
    void Function(double lat) addLat,
  ) {
    addLat(latitude);
    longitudes.add(_toPositiveLongitude(longitude));
  }

  double _calcAutoZoomWaveRadiusKm(QuakeMessage event) {
    final normalizedOrigin = QuakeTime.normalizedOriginLocal(event);
    final elapsed = QuakeCalculator.getElapsedSeconds(
      normalizedOrigin,
      NtpService().now,
    );
    if (elapsed <= 0) return 0;

    final tts = TravelTimeService();
    double pRadiusKm = 0;
    double sRadiusKm = 0;
    if (tts.isLoaded) {
      var pInfo = tts.calcWaveDistance('jma2001', true, event.depth, elapsed);
      if (pInfo.radius > 2000) {
        pInfo = tts.calcWaveDistance('jb', true, event.depth, elapsed);
      }
      pRadiusKm = pInfo.radius;

      var sInfo = tts.calcWaveDistance('jma2001', false, event.depth, elapsed);
      if (sInfo.radius > 2000) {
        sInfo = tts.calcWaveDistance('jb', false, event.depth, elapsed);
      }
      sRadiusKm = sInfo.radius;
    } else {
      final depthFactor = event.depth > 0
          ? (1.0 - (event.depth / 700) * 0.15).clamp(0.85, 1.0)
          : 1.0;
      pRadiusKm = elapsed * QuakeCalculator.pWaveSpeed * depthFactor;
      sRadiusKm = elapsed * QuakeCalculator.sWaveSpeed * depthFactor;
    }

    // The visual wave layer can keep expanding, but camera fitting should stay
    // near the actionable EEW area instead of zooming out to cover the whole
    // propagated wave front.
    final cameraRadiusCap = min(
      max(18 * event.magnitude * event.magnitude, 180),
      520,
    );
    return max(pRadiusKm, sRadiusKm).clamp(0.0, cameraRadiusCap).toDouble();
  }

  @override
  void dispose() {
    _autoZoomResumeTimer?.cancel();
    _stopMoveAnimation();
    super.dispose();
  }

  bool _canApplyAutoMove(bool respectAutoZoom) {
    if (!respectAutoZoom) return true;
    return canAutoFollow;
  }

  bool _acquireMovePermit(
    String sourceTag,
    LatLng center,
    double zoom,
    bool force,
    Duration minInterval,
  ) {
    if (force) {
      _rememberMove(sourceTag, center, zoom);
      return true;
    }

    final now = DateTime.now();
    final sourceAt = _lastMoveBySource[sourceTag];
    if (sourceAt != null && now.difference(sourceAt) < minInterval) {
      return false;
    }

    final key = _cameraKey(center, zoom);
    final sameCameraRecently =
        _lastCameraKey == key &&
        _lastCameraMovedAt != null &&
        now.difference(_lastCameraMovedAt!) <
            const Duration(milliseconds: 1800);
    if (sameCameraRecently) {
      return false;
    }

    _rememberMove(sourceTag, center, zoom);
    return true;
  }

  String _cameraKey(LatLng center, double zoom) {
    final lat = center.latitude.toStringAsFixed(4);
    final lng = center.longitude.toStringAsFixed(4);
    final z = zoom.toStringAsFixed(2);
    return '$lat,$lng,$z';
  }

  void _rememberMove(String sourceTag, LatLng center, double zoom) {
    final now = DateTime.now();
    _lastMoveBySource[sourceTag] = now;
    _lastCameraKey = _cameraKey(center, zoom);
    _lastCameraMovedAt = now;
  }
}

class _WrappedEventView {
  final LatLng center;
  final double latDiff;
  final double lngDiff;

  const _WrappedEventView({
    required this.center,
    required this.latDiff,
    required this.lngDiff,
  });
}
