import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/quake_message.dart';
import '../widgets/map/map_config.dart';
import '../core/calculator.dart';
import '../core/travel_time_service.dart';
import '../core/utils/world_wrap.dart';
import '../core/utils/quake_time.dart';
import '../services/ntp_service.dart';
import '../services/location_service.dart';
import 'dart:math';

enum MapCameraMode { autoFollow, manualLocked }

class MapStateProvider with ChangeNotifier {
  static const LatLng fallbackCenter = LatLng(34.34127, 108.93984);
  static const double fallbackZoom = 4.0;
  static const String preferredViewModeKey = 'map_preferred_view_mode';
  static const Duration gestureAutoFollowResumeDelay = Duration(seconds: 8);

  /// 用户持久化的首选视野：'location' / 'system_default' / null（跟随智能默认）。
  String? _preferredViewMode;
  String? get preferredViewMode => _preferredViewMode;

  /// 当前生效的默认视野中心：优先按用户保存的视野模式，否则按所在地/系统默认。
  LatLng get defaultCenter {
    if (_preferredViewMode == 'system_default') return fallbackCenter;
    final pos = LocationService().currentPosition;
    if (pos != null) return LatLng(pos.latitude, pos.longitude);
    return fallbackCenter;
  }

  /// 当前生效的默认缩放：统一使用系统默认缩放。
  double get defaultZoom => fallbackZoom;

  /// 设置并可选持久化首选视野模式。
  Future<void> setPreferredViewMode(String? mode, {bool persist = true}) async {
    if (_preferredViewMode == mode) return;
    _preferredViewMode = mode;
    notifyListeners();
    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      if (mode == null) {
        await prefs.remove(preferredViewModeKey);
      } else {
        await prefs.setString(preferredViewModeKey, mode);
      }
    }
  }

  /// 把地图切换到“所在地视野”。未设置所在地时返回 false，调用方提示。
  bool moveToLocationView({bool animate = true}) {
    final pos = LocationService().currentPosition;
    if (pos == null) return false;
    pauseAutoZoom();
    _doAnimatedMove(
      LatLng(pos.latitude, pos.longitude),
      fallbackZoom,
      animate,
      wrapLongitude: false,
    );
    unawaited(setPreferredViewMode('location'));
    return true;
  }

  /// 把地图切换到“默认视野”（系统默认中心 + 缩放）。
  void moveToSystemDefaultView({bool animate = true}) {
    pauseAutoZoom();
    _doAnimatedMove(
      fallbackCenter,
      fallbackZoom,
      animate,
      wrapLongitude: false,
    );
    unawaited(setPreferredViewMode('system_default'));
  }

  MapController? _mapController;
  QuakeMessage? _selectedHistoryEvent;
  String _tileKey = 'petalLight';
  final Map<String, bool> _overlayEnabled = {
    'cloudLayer': false,
    'windLayer': false,
    'rainLayer': false,
    'radarChinaLayer': false,
    'jmaRadarLayer': false,
    'satelliteCloudLayer': false,
    'cnContour': false,
    'volcanoLayer': false,
    'typhoonLayer': false,
    'weatherStationLayer': false,
    'fdsnEarthScope': false,
    'fdsnGeofon': false,
  };

  String _weatherStationMode = 'auto';
  String get weatherStationMode => _weatherStationMode;

  void setWeatherStationMode(String mode) {
    if (_weatherStationMode == mode) return;
    _weatherStationMode = mode;
    notifyListeners();
  }

  bool _showEstimatedEpicenter = false;
  bool get showEstimatedEpicenter => _showEstimatedEpicenter;

  static const int _cameraAnimationFps = 60;
  // EEW wave targets arrive about once per second. Keep continuous follow at
  // 25fps so average move cost stays the same as before.
  static const int _continuousCameraAnimationFps = 25;

  /// Wave radius may span a hemisphere. Using those edges in the wrap-cluster
  /// would put the camera on the antipode (e.g. Africa for a California EEW).
  static const double _maxCameraWaveSpanDeg = 30;

  /// Beyond this, fly to the epicenter first; wave-follow starts after arrival.
  static const double _longHaulLngDeg = 50;
  static const double _longHaulLatDeg = 40;

  bool _isAutoZoom = true;
  Timer? _autoZoomResumeTimer;
  Timer? _gestureAutoFollowResumeTimer;
  DateTime? _autoZoomResumeAt;
  Timer? _moveAnimationTimer;
  MapCameraMode _cameraMode = MapCameraMode.autoFollow;
  bool _isGestureAutoFollowPaused = false;
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
  bool get isGestureAutoFollowPaused => _isGestureAutoFollowPaused;
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
    _gestureAutoFollowResumeTimer?.cancel();
    _isGestureAutoFollowPaused = false;
    _pauseAutoZoom(resumeAfter);
  }

  void _pauseAutoZoom(
    Duration resumeAfter, {
    bool preserveLongerPause = false,
  }) {
    final wasAutoFollow = canAutoFollow;
    _isAutoZoom = false;
    _cameraMode = MapCameraMode.manualLocked;
    final now = DateTime.now();
    final requestedResumeAt = now.add(resumeAfter);
    final currentResumeAt = _autoZoomResumeAt;
    final resumeAt =
        preserveLongerPause &&
            currentResumeAt != null &&
            currentResumeAt.isAfter(requestedResumeAt)
        ? currentResumeAt
        : requestedResumeAt;
    _autoZoomResumeAt = resumeAt;
    _autoZoomResumeTimer?.cancel();
    _autoZoomResumeTimer = Timer(resumeAt.difference(now), () {
      resumeAutoZoom();
    });
    if (wasAutoFollow) {
      notifyListeners();
    }
  }

  void pauseAutoZoomForGesture() {
    _stopMoveAnimation();
    _isGestureAutoFollowPaused = true;
    _gestureAutoFollowResumeTimer?.cancel();
    _gestureAutoFollowResumeTimer = Timer(gestureAutoFollowResumeDelay, () {
      if (!_isGestureAutoFollowPaused) return;
      _isGestureAutoFollowPaused = false;
      notifyListeners();
    });
    _pauseAutoZoom(gestureAutoFollowResumeDelay, preserveLongerPause: true);
  }

  void resumeAutoZoom() {
    _gestureAutoFollowResumeTimer?.cancel();
    _isGestureAutoFollowPaused = false;
    _isAutoZoom = true;
    _autoZoomResumeTimer?.cancel();
    _autoZoomResumeAt = null;
    _cameraMode = MapCameraMode.autoFollow;
    notifyListeners();
  }

  void recenterToDefaultView({bool animate = true}) {
    pauseAutoZoom();
    if (_mapController == null) return;
    _doAnimatedMove(defaultCenter, defaultZoom, animate, wrapLongitude: false);
  }

  void animatedMove(
    LatLng destLocation,
    double destZoom, {
    bool continuousFollow = false,
  }) {
    if (_mapController == null) return;
    _doAnimatedMove(
      destLocation,
      destZoom,
      true,
      continuousFollow: continuousFollow,
    );
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
    Offset screenOffset, {
    bool continuousFollow = false,
  }) {
    if (_mapController == null) return;
    final adjustedCenter = _centerForScreenOffset(
      focusLocation,
      destZoom,
      screenOffset,
    );
    _doAnimatedMove(
      adjustedCenter,
      destZoom,
      true,
      continuousFollow: continuousFollow,
    );
  }

  void _doAnimatedMove(
    LatLng destLocation,
    double destZoom,
    bool animate, {
    bool wrapLongitude = true,
    bool continuousFollow = false,
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
    final latDelta = (dest.latitude - currCenter.latitude).abs();
    final lngDelta = (dest.longitude - currCenter.longitude).abs();
    final zoomDiff = (destZoom - currZoom).abs();

    _stopMoveAnimation();

    if (!animate) {
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

    final plan = _planCameraMove(
      latDelta: latDelta,
      lngDelta: lngDelta,
      zoomDelta: zoomDiff,
      continuousFollow: continuousFollow,
    );
    final duration = plan.duration;
    final animationFps = continuousFollow
        ? _continuousCameraAnimationFps
        : _cameraAnimationFps;
    final frame = Duration(
      microseconds: Duration.microsecondsPerSecond ~/ animationFps,
    );
    final stopwatch = Stopwatch()..start();

    void tick() {
      final rawT = stopwatch.elapsedMicroseconds / duration.inMicroseconds;
      final t = rawT.clamp(0.0, 1.0);
      final panT = plan.panProgress(t);
      final zoomT = plan.zoomProgress(t);
      final next = LatLng(latTween.transform(panT), lngTween.transform(panT));
      final nextZoom = zoomTween.transform(zoomT);
      final cam = _mapController!.camera;
      // Skip no-op moves so multi-event + dense station layers don't rebuild.
      if ((cam.center.latitude - next.latitude).abs() > 1e-7 ||
          (cam.center.longitude - next.longitude).abs() > 1e-7 ||
          (cam.zoom - nextZoom).abs() > 1e-5) {
        _mapController!.move(next, nextZoom);
      }
      if (t >= 1.0) {
        _stopMoveAnimation();
      }
    }

    tick();
    _moveAnimationTimer = Timer.periodic(frame, (_) => tick());
  }

  /// Pick duration/curves from jump size.
  ///
  /// Continuous EEW wave follow must stay on a ~1000ms linear tween so each
  /// ~1Hz policy retarget handoff has no idle gap (otherwise zoom stutters).
  static _CameraMovePlan _planCameraMove({
    required double latDelta,
    required double lngDelta,
    required double zoomDelta,
    required bool continuousFollow,
  }) {
    final geo = max(latDelta, lngDelta);
    final score = geo + zoomDelta * 0.35;

    if (continuousFollow) {
      // Match the pre-change wave-follow feel: bridge the second between
      // policy updates with continuous linear motion at 25fps.
      return const _CameraMovePlan(
        duration: Duration(milliseconds: 1000),
        panCurve: Curves.linear,
        zoomCurve: Curves.linear,
        panCompleteAt: 1.0,
      );
    }

    // Discrete event / history / station jumps. Pan and zoom share the same
    // curve and duration so the camera does not finish sliding then keep
    // zooming in place.
    final ms = (460 + score * 65).round().clamp(500, 1200);
    return _CameraMovePlan(
      duration: Duration(milliseconds: ms),
      panCurve: Curves.easeInOutCubic,
      zoomCurve: Curves.easeInOutCubic,
      panCompleteAt: 1.0,
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
        .where(
          (e) => QuakeCalculator.isUsableMapCoordinate(e.latitude, e.longitude),
        )
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

  double? smartMoveToEvents(
    List<QuakeMessage> events, {
    double padding = 2.0,
    List<QuakeMessage> waveEvents = const [],
    double minZoom = 3.0,
    double maxZoom = 8.0,
    Offset screenOffset = Offset.zero,
    bool respectAutoZoom = true,
    String sourceTag = 'events',
    bool force = false,
    Duration minInterval = const Duration(milliseconds: 900),
    bool continuousFollow = false,
  }) {
    if (!_canApplyAutoMove(respectAutoZoom)) return null;
    if (_mapController == null) return null;
    if (events.isEmpty) return null;

    final epicenterView = _calcWrappedEventView(events);
    if (epicenterView == null) return null;

    final currCenter = _mapController!.camera.center;
    final wrappedViewLng = WorldWrap.longitudeClosestTo(
      epicenterView.center.longitude,
      currCenter.longitude,
    );
    final farAway =
        (wrappedViewLng - currCenter.longitude).abs() > _longHaulLngDeg ||
        (epicenterView.center.latitude - currCenter.latitude).abs() >
            _longHaulLatDeg;
    final followWaves = waveEvents.isNotEmpty && !farAway;
    final followContinuously = continuousFollow && !farAway;
    final view = followWaves
        ? (_calcWrappedEventView(events, waveEvents: waveEvents) ??
              epicenterView)
        : epicenterView;

    final fittedCamera = followWaves
        ? _fitWaveViewToViewport(view, minZoom: minZoom, maxZoom: maxZoom)
        : null;
    final center = fittedCamera?.center ?? view.center;
    final zoom =
        fittedCamera?.zoom ??
        _zoomForDiff(
          max(view.latDiff, view.lngDiff) + padding * 2,
        ).clamp(minZoom, maxZoom).toDouble();
    final targetCenter = screenOffset == Offset.zero
        ? center
        : _centerForScreenOffset(center, zoom, screenOffset);

    final currZoom = _mapController!.camera.zoom;
    final err = 1 / pow(2, zoom);
    if (currZoom == zoom &&
        (currCenter.latitude - targetCenter.latitude).abs() < err &&
        (currCenter.longitude - targetCenter.longitude).abs() < err) {
      return zoom;
    }
    if (!_acquireMovePermit(
      sourceTag,
      targetCenter,
      zoom,
      force,
      minInterval,
    )) {
      return zoom;
    }

    if (screenOffset == Offset.zero) {
      animatedMove(center, zoom, continuousFollow: followContinuously);
    } else {
      animatedMoveWithScreenOffset(
        center,
        zoom,
        screenOffset,
        continuousFollow: followContinuously,
      );
    }
    return zoom;
  }

  @visibleForTesting
  LatLng? wrappedEventViewCenterForTest(
    List<QuakeMessage> events, {
    List<QuakeMessage> waveEvents = const [],
  }) {
    return _calcWrappedEventView(events, waveEvents: waveEvents)?.center;
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
    if (!QuakeCalculator.isUsableMapCoordinate(
      center.latitude,
      center.longitude,
    )) {
      return;
    }

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
    final camera = _mapController!.camera;
    final focusPoint = camera.projectAtZoom(wrappedFocus, destZoom);
    return camera.unprojectAtZoom(focusPoint - screenOffset, destZoom);
  }

  _WrappedEventView? _calcWrappedEventView(
    List<QuakeMessage> events, {
    List<QuakeMessage> waveEvents = const [],
  }) {
    final validEvents = events
        .where(
          (e) => QuakeCalculator.isUsableMapCoordinate(e.latitude, e.longitude),
        )
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
    var extraLat = 0.0;
    var extraLng = 0.0;

    for (final e in waveEvents) {
      if (!QuakeCalculator.isUsableMapCoordinate(e.latitude, e.longitude)) {
        continue;
      }
      final radiusKm = _calcAutoZoomWaveRadiusKm(e);
      if (radiusKm <= 0) continue;
      extraLat = max(
        extraLat,
        (radiusKm / 111.32).clamp(0.0, _maxCameraWaveSpanDeg),
      );
      final cosLat = max(cos(e.latitude * pi / 180).abs(), 0.15);
      extraLng = max(
        extraLng,
        (radiusKm / (111.32 * cosLat)).clamp(0.0, _maxCameraWaveSpanDeg),
      );
    }

    return _WrappedEventView(
      center: LatLng((minLat + maxLat) / 2, centerLng),
      latDiff: (maxLat - minLat) + extraLat * 2,
      lngDiff: (endLng - startLng) + extraLng * 2,
    );
  }

  _WrappedEventView? _calcWrappedPointView(List<LatLng> points) {
    final validPoints = points
        .where(
          (point) => QuakeCalculator.isUsableMapCoordinate(
            point.latitude,
            point.longitude,
          ),
        )
        .toList();
    if (validPoints.isEmpty) return null;

    double minLat = double.infinity;
    double maxLat = double.negativeInfinity;
    final longitudes = <double>[];

    for (final point in validPoints) {
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

  MapCamera? _fitWaveViewToViewport(
    _WrappedEventView view, {
    required double minZoom,
    required double maxZoom,
  }) {
    final camera = _mapController!.camera;
    final size = camera.nonRotatedSize;
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 100 ||
        size.height <= 100) {
      return null;
    }

    final centerLng = WorldWrap.normalizeLongitude(view.center.longitude);
    final halfLat = view.latDiff / 2;
    final halfLng = view.lngDiff / 2;
    final south = view.center.latitude - halfLat;
    final north = view.center.latitude + halfLat;
    final west = centerLng - halfLng;
    final east = centerLng + halfLng;
    if (south < -85 || north > 85 || west < -180 || east > 180) {
      return null;
    }

    return CameraFit.bounds(
      bounds: LatLngBounds.unsafe(
        north: north,
        south: south,
        east: east,
        west: west,
      ),
      padding: const EdgeInsets.all(50),
      minZoom: minZoom,
      maxZoom: maxZoom,
    ).fit(camera);
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
    if (tts.isLoaded) {
      var pInfo = tts.calcWaveDistance('jma2001', true, event.depth, elapsed);
      if (pInfo.radius > 2000) {
        pInfo = tts.calcWaveDistance('jb', true, event.depth, elapsed);
      }
      pRadiusKm = pInfo.radius;
    } else {
      final depthFactor = event.depth > 0
          ? (1.0 - (event.depth / 700) * 0.15).clamp(0.85, 1.0)
          : 1.0;
      pRadiusKm = elapsed * QuakeCalculator.pWaveSpeed * depthFactor;
    }

    // Keep camera bounds on the same current P-wave radius used by the layer.
    // A magnitude-based cap makes the bounds stop growing while the visible
    // wave continues expanding, leaving the circle outside the viewport.
    return pRadiusKm.isFinite && pRadiusKm > 0 ? pRadiusKm : 0;
  }

  @override
  void dispose() {
    _autoZoomResumeTimer?.cancel();
    _gestureAutoFollowResumeTimer?.cancel();
    _autoZoomResumeAt = null;
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
    if (_lastMoveBySource.length > 128) {
      final cutoff = now.subtract(const Duration(minutes: 10));
      _lastMoveBySource.removeWhere((_, movedAt) => movedAt.isBefore(cutoff));
    }
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

class _CameraMovePlan {
  final Duration duration;
  final Curve panCurve;
  final Curve zoomCurve;

  /// Fraction of [duration] by which pan should finish (zoom may continue).
  final double panCompleteAt;

  const _CameraMovePlan({
    required this.duration,
    required this.panCurve,
    required this.zoomCurve,
    required this.panCompleteAt,
  });

  double panProgress(double t) {
    final scaled = panCompleteAt >= 1.0
        ? t
        : (t / panCompleteAt).clamp(0.0, 1.0);
    return panCurve.transform(scaled);
  }

  double zoomProgress(double t) => zoomCurve.transform(t);
}
