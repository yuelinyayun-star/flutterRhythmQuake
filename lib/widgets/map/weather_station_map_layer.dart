import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/sources/cma_local_weather_service.dart';
import '../../services/sources/precipitation_stations_service.dart';

/// 气象站展示模式
enum WeatherStationDisplayMode {
  /// 综合模式：降雨优先（有降雨测站突出降雨量级，无雨测站展示气温）
  auto,

  /// 降水雨量模式：专属雨量色阶，高亮展示小雨/中雨/大雨/暴雨等降水
  rain,

  /// 气温模式：全国气温冷暖色阶与温度数值
  temperature,

  /// 风向风力模式：风向旋转指针与风力等级
  wind;

  static WeatherStationDisplayMode fromKey(String? key) {
    switch (key?.trim().toLowerCase()) {
      case 'rain':
        return WeatherStationDisplayMode.rain;
      case 'temperature':
      case 'temp':
        return WeatherStationDisplayMode.temperature;
      case 'wind':
        return WeatherStationDisplayMode.wind;
      case 'auto':
      default:
        return WeatherStationDisplayMode.auto;
    }
  }

  String get key {
    switch (this) {
      case WeatherStationDisplayMode.auto:
        return 'auto';
      case WeatherStationDisplayMode.rain:
        return 'rain';
      case WeatherStationDisplayMode.temperature:
        return 'temperature';
      case WeatherStationDisplayMode.wind:
        return 'wind';
    }
  }

  String get label {
    switch (this) {
      case WeatherStationDisplayMode.auto:
        return '综合(降雨优先)';
      case WeatherStationDisplayMode.rain:
        return '降水雨量';
      case WeatherStationDisplayMode.temperature:
        return '气温实况';
      case WeatherStationDisplayMode.wind:
        return '风向风力';
    }
  }
}

/// Keeps station markers at all zooms and shows readings in the close view.
class WeatherStationMapLayer extends StatefulWidget {
  static const labelMinZoom = 8.4;

  final List<CmaStationSummary> stations;
  final WeatherStationDisplayMode mode;

  const WeatherStationMapLayer({
    super.key,
    required this.stations,
    this.mode = WeatherStationDisplayMode.auto,
  });

  @override
  State<WeatherStationMapLayer> createState() => _WeatherStationMapLayerState();
}

class _WeatherStationMapLayerState extends State<WeatherStationMapLayer> {
  Timer? _preloadTimer;
  List<CmaStationSummary>? _stations;
  Crs? _crs;
  List<Offset> _projected = const [];
  WeatherStationDisplayMode? _mode;
  Map<String, CmaLocalWeatherObservation>? _observations;
  List<_StationReading> _readings = const [];
  List<_StationReading> _markers = const [];
  final _readingAtlas = _WeatherStationAtlas();
  final _markerAtlas = _WeatherStationAtlas();

  void _scheduleViewportPreload(MapCamera camera) {
    _preloadTimer?.cancel();
    _preloadTimer = Timer(const Duration(milliseconds: 120), () {
      final bounds = camera.visibleBounds;
      CmaLocalWeatherService.preloadStations([
        for (final station in widget.stations)
          if (bounds.contains(LatLng(station.latitude, station.longitude)))
            station.id,
      ]);
    });
  }

  void _prepareReadings(Map<String, CmaLocalWeatherObservation> observations) {
    if (_mode == widget.mode && identical(_observations, observations)) return;
    final readings = [
      for (final station in widget.stations)
        _stationReading(station, observations[station.id], widget.mode),
    ];
    if (!listEquals(_readings, readings)) {
      _readings = readings;
      final markers = [
        for (final reading in readings)
          (label: null, color: reading.color, windPointer: reading.windPointer),
      ];
      if (!listEquals(_markers, markers)) _markers = markers;
    }
    _mode = widget.mode;
    _observations = observations;
  }

  @override
  void dispose() {
    _preloadTimer?.cancel();
    _readingAtlas.dispose();
    _markerAtlas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stations.isEmpty) {
      _preloadTimer?.cancel();
      _readingAtlas.dispose();
      _markerAtlas.dispose();
      return const SizedBox.shrink();
    }
    final camera = MapCamera.of(context);
    if (_crs != camera.crs || !identical(_stations, widget.stations)) {
      _projected = [
        for (final station in widget.stations)
          camera.projectAtZoom(LatLng(station.latitude, station.longitude), 0),
      ];
      _crs = camera.crs;
      _stations = widget.stations;
      _observations = null;
    }
    _scheduleViewportPreload(camera);
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final showLabels = camera.zoom >= WeatherStationMapLayer.labelMinZoom;

    return ValueListenableBuilder<Map<String, CmaLocalWeatherObservation>>(
      valueListenable: CmaLocalWeatherService.stationObservationMapNotifier,
      builder: (context, observations, _) {
        _prepareReadings(observations);
        final sprites = showLabels
            ? _readingAtlas.prepare(_readings, ratio)
            : _markerAtlas.prepare(_markers, ratio);
        return MobileLayerTransformer(
          child: RepaintBoundary(
            child: CustomPaint(
              size: camera.size,
              painter: _WeatherStationPainter(camera, _projected, sprites),
            ),
          ),
        );
      },
    );
  }
}

/// Same atlas and zoom behavior as the existing station layer, with readings
/// from the displayed precipitation hour instead of the live station cache.
class PrecipitationStationsLayer extends StatefulWidget {
  const PrecipitationStationsLayer({
    super.key,
    required this.time,
    this.service,
  });

  final DateTime time;
  final PrecipitationStationsService? service;

  @override
  State<PrecipitationStationsLayer> createState() =>
      _PrecipitationStationsLayerState();
}

class _PrecipitationStationsLayerState extends State<PrecipitationStationsLayer> {
  late final _source = widget.service ?? PrecipitationStationsService();
  final _cache = <DateTime, Float64List>{};
  final _atlas = _WeatherStationAtlas();
  Completer<void>? _abort;
  Timer? _debounce;
  Float64List? _rows;
  Float64List? _prepared;
  Crs? _crs;
  List<Offset> _projected = const [];
  List<_StationReading> _labels = const [];
  List<_StationReading> _markers = const [];

  @override
  void initState() {
    super.initState();
    _selectHour();
  }

  @override
  void didUpdateWidget(covariant PrecipitationStationsLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.time != widget.time) _selectHour();
  }

  void _cancel() {
    _debounce?.cancel();
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
    _abort = null;
  }

  void _selectHour() {
    _cancel();
    final time = widget.time.toUtc();
    final cached = _cache.remove(time);
    _rows = cached;
    if (cached != null) {
      _cache[time] = cached;
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 100), () async {
      final abort = _abort = Completer<void>();
      final rows = await _source.fetch(time, abort);
      if (!mounted || !identical(_abort, abort) || rows == null) return;
      _cache[time] = rows;
      if (_cache.length > 24) _cache.remove(_cache.keys.first);
      setState(() => _rows = rows);
    });
  }

  @override
  void dispose() {
    _cancel();
    _source.close();
    _atlas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows == null || rows.isEmpty) {
      _atlas.dispose();
      return const SizedBox.shrink();
    }
    final camera = MapCamera.of(context);
    if (!identical(_prepared, rows) || camera.crs != _crs) {
      _projected = [
        for (var i = 0; i < rows.length; i += 3)
          camera.projectAtZoom(LatLng(rows[i], rows[i + 1]), 0),
      ];
      _labels = [
        for (var i = 2; i < rows.length; i += 3)
          (
            label: '${rows[i].toStringAsFixed(1)}mm',
            color: _hourlyRainColor(rows[i]),
            windPointer: null,
          ),
      ];
      _markers = [
        for (final label in _labels)
          (label: null, color: label.color, windPointer: null),
      ];
      _prepared = rows;
      _crs = camera.crs;
    }
    final sprites = _atlas.prepare(
      camera.zoom >= WeatherStationMapLayer.labelMinZoom ? _labels : _markers,
      MediaQuery.devicePixelRatioOf(context),
    );
    return MobileLayerTransformer(
      child: RepaintBoundary(
        child: CustomPaint(
          key: const ValueKey('precipitation-station-points'),
          size: camera.size,
          painter: _WeatherStationPainter(camera, _projected, sprites),
        ),
      ),
    );
  }

  // China Weather's hourly station palette.
  static Color _hourlyRainColor(double mm) => switch (mm) {
    < 1 => const Color(0xFFCEFFFE),
    < 2 => const Color(0xFF22FFFC),
    < 4 => const Color(0xFF23B7FF),
    < 6 => const Color(0xFF2376FF),
    < 8 => const Color(0xFF092FD1),
    < 10 => const Color(0xFF7B4DF2),
    < 20 => const Color(0xFF8716EF),
    < 50 => const Color(0xFF6A059F),
    _ => const Color(0xFF4C0669),
  };
}

typedef _StationReading = ({String? label, Color color, Offset? windPointer});

double? _observedRain(CmaLocalWeatherObservation? observation) {
  final value = observation?.precipitation;
  return value != null && value >= 0 && value < 9000 ? value : null;
}

@visibleForTesting
String? weatherStationValueLabel(
  CmaStationSummary station,
  CmaLocalWeatherObservation? observation,
  WeatherStationDisplayMode mode,
) => _stationReading(station, observation, mode).label;

_StationReading _stationReading(
  CmaStationSummary station,
  CmaLocalWeatherObservation? observation,
  WeatherStationDisplayMode mode,
) {
  final rain = _observedRain(observation);
  if (mode == WeatherStationDisplayMode.auto) {
    mode = station.isRaining || (rain ?? 0) > 0
        ? WeatherStationDisplayMode.rain
        : WeatherStationDisplayMode.temperature;
  }
  if (mode == WeatherStationDisplayMode.rain) {
    final severity = station.rainSeverity;
    return (
      label: rain == null ? null : '${rain.toStringAsFixed(1)}mm',
      color: _WeatherStationPainter._getRainColor(severity),
      windPointer: null,
    );
  }
  if (mode == WeatherStationDisplayMode.wind) {
    final observedScale = observation?.windScale.trim();
    final scale =
        observedScale != null &&
            observedScale.isNotEmpty &&
            observedScale != '9999'
        ? observedScale
        : station.windScale;
    final observedDirection = observation?.windDirection.trim();
    final direction =
        observedDirection != null &&
            observedDirection.isNotEmpty &&
            observedDirection != '9999'
        ? observedDirection
        : station.windDirection;
    final speed = observation?.windSpeed;
    final angle = _WeatherStationPainter._windDirectionToAngle(direction);
    return (
      label: speed != null && speed >= 0 && speed < 9000
          ? '${speed.toStringAsFixed(1)}m/s'
          : scale.isEmpty
          ? null
          : scale,
      color: _WeatherStationPainter._getWindColor(scale),
      windPointer: angle == null
          ? null
          : Offset(math.sin(angle), -math.cos(angle)) * 6,
    );
  }
  final observedTemp = observation?.temperature;
  final temperature =
      observedTemp != null && observedTemp.isFinite && observedTemp < 9000
      ? observedTemp
      : station.temperature;
  return (
    label: temperature == null ? null : '${temperature.toStringAsFixed(1)}℃',
    color: _WeatherStationPainter._getTemperatureColor(temperature),
    windPointer: null,
  );
}

class _WeatherStationPainter extends CustomPainter {
  _WeatherStationPainter(this.camera, this.projected, this.sprites);

  final MapCamera camera;
  final List<Offset> projected;
  final _WeatherStationSprites sprites;

  // === CMA 中国气象局官方业务标准配色 (GB/T 28592-2012 / NMC 色标体系) ===
  static const Color _cNoRain = Color(0xFF78909C); // 无降水 (蓝灰底色)
  static const Color _cRain1 = Color(0xFFA6F28F); // 小雨/阵雨 (0.1~9.9mm: 官方标准浅翠绿)
  static const Color _cRain2 = Color(0xFF3DBA3D); // 中雨 (10~24.9mm: 官方标准深绿)
  static const Color _cRain3 = Color(0xFF61B8FF); // 大雨 (25~49.9mm: 官方标准天蓝)
  static const Color _cRain5 = Color(0xFFFA00FA); // 大暴雨 (100~249.9mm: 官方标准洋红亮紫)
  static const Color _cRain6 = Color(0xFF700000); // 特大暴雨 (>=250mm: 官方标准褐红)

  static Color _getRainColor(int severity) {
    switch (severity) {
      case 5:
        return _cRain6; // 特大暴雨
      case 4:
        return _cRain5; // 大暴雨 / 暴雨
      case 3:
        return _cRain3; // 大雨
      case 2:
        return _cRain2; // 中雨
      case 1:
        return _cRain1; // 小雨 / 阵雨
      default:
        return _cNoRain;
    }
  }

  /// CMA 中央气象台全国气温实况标准色标
  static Color _getTemperatureColor(double? temp) {
    if (temp == null) return _cNoRain;
    if (temp <= -20) return const Color(0xFF1E3CFF); // 极寒 (< -20℃: 深蓝紫)
    if (temp <= -10) return const Color(0xFF0078FF); // 严寒 (-20~-10℃: 深蓝)
    if (temp <= 0) return const Color(0xFF00D2FF); // 微寒 (-10~0℃: 天蓝)
    if (temp <= 10) return const Color(0xFF00FFC8); // 凉爽 (0~10℃: 浅青绿)
    if (temp <= 16) return const Color(0xFF70E000); // 温和 (10~16℃: 黄绿)
    if (temp <= 20) return const Color(0xFFFFFF00); // 舒适 (16~20℃: 柠檬黄)
    if (temp <= 24) return const Color(0xFFFFC800); // 温暖 (20~24℃: 金黄)
    if (temp <= 28) return const Color(0xFFFF9600); // 较热 (24~28℃: 橙色)
    if (temp <= 32) return const Color(0xFFFF6400); // 炎热 (28~32℃: 橙红)
    if (temp <= 35) return const Color(0xFFFF0000); // 酷热 (32~35℃: 正红)
    if (temp <= 37) return const Color(0xFFC80000); // 高温黄警 (35~37℃: 深红)
    if (temp <= 40) return const Color(0xFF960064); // 高温橙警 (37~40℃: 洋红)
    return const Color(0xFF640064); // 高温红警 (>=40℃: 深褐紫)
  }

  /// CMA 蒲福风级官方预警配色
  static Color _getWindColor(String scale) {
    final s = scale.trim();
    if (s.contains('微风') || s.contains('1级') || s.contains('2级')) {
      return const Color(0xFF81C784); // 0~2级: 微风浅绿
    }
    if (s.contains('3') || s.contains('4')) {
      return const Color(0xFF4DB6AC); // 3~4级: 清风青绿
    }
    if (s.contains('5') || s.contains('6')) {
      return const Color(0xFFFFB74D); // 5~6级: 强风黄橙
    }
    if (s.contains('7') || s.contains('8')) {
      return const Color(0xFFFF7043); // 7~8级: 大风橙红
    }
    if (s.contains('9') || s.contains('10')) {
      return const Color(0xFFE53935); // 9~10级: 狂风鲜红
    }
    if (s.contains('11') ||
        s.contains('12') ||
        s.contains('13') ||
        s.contains('14')) {
      return const Color(0xFF880E4F); // 11级+: 飓风紫红
    }
    return const Color(0xFF78909C);
  }

  static double? _windDirectionToAngle(String dir) {
    final d = dir.trim();
    if (d.contains('北风') && !d.contains('东') && !d.contains('西')) return 0.0;
    if (d.contains('东北')) return math.pi * 0.25;
    if (d.contains('东风')) return math.pi * 0.5;
    if (d.contains('东南')) return math.pi * 0.75;
    if (d.contains('南风')) return math.pi;
    if (d.contains('西南')) return math.pi * 1.25;
    if (d.contains('西风')) return math.pi * 1.5;
    if (d.contains('西北')) return math.pi * 1.75;
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final worldWidth = camera.getWorldWidthAtZoom();
    final scale = camera.getZoomScale(camera.zoom, 0);
    final origin = camera.pixelOrigin;
    final visible = camera.pixelBounds.inflate(36);
    sprites.begin();
    for (var i = 0; i < projected.length; i++) {
      final point = projected[i] * scale;
      if (point.dy < visible.top || point.dy >= visible.bottom) continue;
      if (worldWidth == 0) {
        if (visible.contains(point)) {
          sprites.add(canvas, i, point.dx - origin.dx, point.dy - origin.dy);
        }
        continue;
      }
      final firstWorld = ((visible.left - point.dx) / worldWidth).ceil();
      for (
        var x = point.dx + firstWorld * worldWidth;
        x < visible.right;
        x += worldWidth
      ) {
        sprites.add(canvas, i, x - origin.dx, point.dy - origin.dy);
      }
    }
    sprites.flush(canvas);
  }

  @override
  bool shouldRepaint(covariant _WeatherStationPainter oldDelegate) =>
      oldDelegate.camera != camera ||
      !identical(oldDelegate.projected, projected) ||
      !identical(oldDelegate.sprites, sprites);
}

typedef _StationSprite = ({ui.Image image, Rect source, Offset anchor});

/// Packs each distinct marker and reading once at the device's pixel ratio.
/// Camera changes reuse the texture. The active readings bound its size.
class _WeatherStationAtlas {
  static const _maxPageSize = 2048;
  static const _padding = 8.0;
  final _images = <ui.Image>[];
  final _entries = <_StationReading, _StationSprite>{};
  List<_StationReading>? _readings;
  _WeatherStationSprites? _sprites;
  double? _ratio;

  _WeatherStationSprites prepare(List<_StationReading> readings, double ratio) {
    if (_ratio == ratio && identical(_readings, readings)) return _sprites!;
    final active = readings.toSet();
    if (_ratio != ratio || !active.every(_entries.containsKey)) {
      dispose();
      _ratio = ratio;
      _pack(active, ratio);
    }
    _readings = readings;
    return _sprites = _WeatherStationSprites([
      for (final reading in readings) _entries[reading]!,
    ], ratio);
  }

  void _pack(Set<_StationReading> readings, double ratio) {
    final labels = <String, TextPainter>{};
    final pending = <_StationReading, Rect>{};
    final padding = (_padding * ratio).ceil();
    final marker = Paint()..strokeWidth = 1.5;
    final background = Paint()..color = const Color(0xDD1E1E1E);
    var recorder = ui.PictureRecorder();
    var canvas = Canvas(recorder);
    var x = 0, y = 0, rowHeight = 0, pageWidth = 0;

    void finishPage() {
      final picture = recorder.endRecording();
      if (pending.isNotEmpty) {
        final image = picture.toImageSync(pageWidth, y + rowHeight);
        _images.add(image);
        for (final entry in pending.entries) {
          _entries[entry.key] = (
            image: image,
            source: entry.value,
            anchor: Offset(padding / ratio, entry.value.height / (2 * ratio)),
          );
        }
      }
      picture.dispose();
      pending.clear();
    }

    for (final reading in readings) {
      final label = reading.label;
      final text = label == null
          ? null
          : labels.putIfAbsent(
              label,
              () => TextPainter(
                text: TextSpan(
                  text: label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                textDirection: TextDirection.ltr,
              )..layout(),
            );
      final width =
          padding +
          (text == null ? padding : ((10 + text.width) * ratio).ceil());
      final height = math.max(
        padding * 2,
        (((text?.height ?? 0) + 6) * ratio).ceil(),
      );
      if (x + width > _maxPageSize && x > 0) {
        x = 0;
        y += rowHeight;
        rowHeight = 0;
      }
      if (y + height > _maxPageSize && pending.isNotEmpty) {
        finishPage();
        recorder = ui.PictureRecorder();
        canvas = Canvas(recorder);
        x = y = rowHeight = pageWidth = 0;
      }
      pending[reading] = Rect.fromLTWH(
        x.toDouble(),
        y.toDouble(),
        width.toDouble(),
        height.toDouble(),
      );
      canvas.save();
      canvas.translate(x + padding.toDouble(), y + height / 2);
      canvas.scale(ratio);
      marker.color = reading.color;
      canvas.drawCircle(Offset.zero, 3, marker);
      if (reading.windPointer case final pointer?) {
        canvas.drawLine(Offset.zero, pointer, marker);
      }
      if (text != null) {
        final offset = Offset(7, -text.height / 2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            (offset & text.size).inflate(2),
            const Radius.circular(2),
          ),
          background,
        );
        text.paint(canvas, offset);
      }
      canvas.restore();
      x += width;
      rowHeight = math.max(rowHeight, height);
      pageWidth = math.max(pageWidth, x);
    }
    finishPage();
    for (final text in labels.values) {
      text.dispose();
    }
  }

  void dispose() {
    for (final image in _images) {
      image.dispose();
    }
    _images.clear();
    _entries.clear();
    _sprites = null;
    _readings = null;
    _ratio = null;
  }
}

/// Sends consecutive sprites on the same texture in one call, preserving the
/// station draw order even when readings span more than one texture.
class _WeatherStationSprites {
  _WeatherStationSprites(this.entries, double ratio)
    : scale = 1 / ratio,
      _transforms = Float32List(entries.length * 4),
      _rectangles = Float32List(entries.length * 4);

  final List<_StationSprite> entries;
  final double scale;
  final Float32List _transforms;
  final Float32List _rectangles;
  final _paint = Paint()..filterQuality = FilterQuality.low;
  ui.Image? _image;
  int _offset = 0;

  void begin() {
    _offset = 0;
    _image = null;
  }

  void add(Canvas canvas, int station, double x, double y) {
    final sprite = entries[station];
    if (!identical(_image, sprite.image) || _offset == _transforms.length) {
      flush(canvas);
      _image = sprite.image;
    }
    final i = _offset;
    _transforms[i] = scale;
    _transforms[i + 2] = x - sprite.anchor.dx;
    _transforms[i + 3] = y - sprite.anchor.dy;
    _rectangles[i] = sprite.source.left;
    _rectangles[i + 1] = sprite.source.top;
    _rectangles[i + 2] = sprite.source.right;
    _rectangles[i + 3] = sprite.source.bottom;
    _offset += 4;
  }

  void flush(Canvas canvas) {
    if (_offset == 0) return;
    canvas.drawRawAtlas(
      _image!,
      Float32List.sublistView(_transforms, 0, _offset),
      Float32List.sublistView(_rectangles, 0, _offset),
      null,
      null,
      null,
      _paint,
    );
    _offset = 0;
  }
}
