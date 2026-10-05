import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../core/seedlink_station_style.dart';
import '../../core/fdsn_intensity.dart';
import '../../core/intensity_calculator.dart';
import '../../services/sources/fdsn_station_service.dart';

class FdsnStationLayer extends StatefulWidget {
  final List<FdsnStation> stations;
  @visibleForTesting
  final FdsnLayerDiagnostics? diagnostics;
  const FdsnStationLayer({super.key, required this.stations, this.diagnostics});
  @override
  State<FdsnStationLayer> createState() => _FdsnStationLayerState();
}

@visibleForTesting
class FdsnLayerDiagnostics {
  int projections = 0;
  int paints = 0;
  int pictureRecordings = 0;
  int recordedStations = 0;
  int atlasBuilds = 0;
  int atlasDraws = 0;
  int preparationMicros = 0;
  int glyphCreations = 0;
  int selectionVisits = 0;
  int spatialIndexBuilds = 0;
  int bufferAllocations = 0;
  int atlasSlots = 0;
  int eventPaints = 0;
}

class _FdsnStationLayerState extends State<FdsnStationLayer> {
  List<_StationGlyph> _glyphs = const [];
  List<_StationGlyph> _inputGlyphs = const [];
  List<FdsnStation> _preparedStations = const [];
  List<_StationGlyph?> _preparedGlyphs = const [];
  final _scene = _FdsnScene();
  bool _dirty = true;
  Crs? _crs;
  FdsnIntensityScale? _preparedScale;
  Timer? _expiry;

  @override
  void initState() {
    super.initState();
    SeedLinkStationStyle.shape.addListener(_scaleChanged);
    FdsnIntensity.scale.addListener(_scaleChanged);
  }

  void _scaleChanged() => setState(() => _dirty = true);

  @override
  void didUpdateWidget(FdsnStationLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.stations, widget.stations)) _dirty = true;
  }

  void _prepare(MapCamera camera) {
    final watch = widget.diagnostics == null ? null : (Stopwatch()..start());
    _dirty = false;
    final sameCrs = _crs == camera.crs;
    _crs = camera.crs;
    _expiry?.cancel();
    final now = DateTime.now().microsecondsSinceEpoch;
    int? expires;
    final mode = SeedLinkStationStyle.shape.value;
    final scale = FdsnIntensity.scale.value;
    final glyphs = <_StationGlyph>[];
    final prepared = List<_StationGlyph?>.filled(widget.stations.length, null);
    Map<(String, String), (FdsnStation, _StationGlyph)>? previousByCode;
    for (var i = 0; i < widget.stations.length; i++) {
      final station = widget.stations[i];
      final shape = SeedLinkStationStyle.resolve(mode, station.sensorType);
      final updated = station.lastMotionUpdate;
      if (updated == null || updated.microsecondsSinceEpoch > now) continue;
      final end =
          updated.microsecondsSinceEpoch +
          FdsnStation.motionRetention.inMicroseconds;
      if (end <= now) continue;
      if (expires == null || end < expires) expires = end;
      var previous = i < _preparedStations.length ? _preparedStations[i] : null;
      var oldGlyph = i < _preparedGlyphs.length ? _preparedGlyphs[i] : null;
      if (previous?.network != station.network ||
          previous?.station != station.station) {
        previousByCode ??= {
          for (var n = 0; n < _preparedStations.length; n++)
            if (_preparedGlyphs[n] != null)
              (_preparedStations[n].network, _preparedStations[n].station): (
                _preparedStations[n],
                _preparedGlyphs[n]!,
              ),
        };
        final match = previousByCode[(station.network, station.station)];
        previous = match?.$1;
        oldGlyph = match?.$2;
      }
      final sameCoordinate =
          sameCrs && previous?.coordinate == station.coordinate;
      if (oldGlyph != null &&
          oldGlyph.shape == shape &&
          sameCoordinate &&
          _preparedScale == scale &&
          switch (scale) {
            FdsnIntensityScale.mmi => previous?.intensity == station.intensity,
            FdsnIntensityScale.csis =>
              previous?.pga == station.pga && previous?.pgv == station.pgv,
            FdsnIntensityScale.gq => previous?.activity == station.activity,
          }) {
        prepared[i] = oldGlyph;
        glyphs.add(oldGlyph);
        continue;
      }
      final raw = station.activity?.ratio;
      final ratio = raw != null && raw.isFinite && raw >= 0 ? raw : null;
      final intensity = FdsnIntensity.displayLevel(
        scale,
        mmi: station.intensity,
        pgaGal: station.pga,
        pgvCms: station.pgv,
      );
      final isRatio = scale == FdsnIntensityScale.gq;
      final level = isRatio
          ? (ratio == null ? -1 : SeedLinkStationStyle.colorIndex(ratio))
          : (intensity ?? -1);
      final color = isRatio
          ? SeedLinkStationStyle.ratioColor(ratio)
          : intensity == null
          ? 0xFF2F80ED
          : scale == FdsnIntensityScale.csis
          ? IntensityCalculator.getCsisColor(intensity)
          : _mmiColors[intensity - 1];
      final label = isRatio
          ? (ratio?.toStringAsFixed(1) ?? '-.-')
          : (intensity?.toString() ?? '');
      final eventColor =
          isRatio && ratio != null && station.activity?.event == true
          ? SeedLinkStationStyle.eventColor(ratio)
          : null;
      if (oldGlyph != null &&
          oldGlyph.shape == shape &&
          sameCoordinate &&
          oldGlyph.color == color &&
          oldGlyph.label == label &&
          oldGlyph.eventColor == eventColor) {
        prepared[i] = oldGlyph;
        glyphs.add(oldGlyph);
        continue;
      }
      final Offset point;
      if (oldGlyph != null && sameCoordinate) {
        point = oldGlyph.point;
      } else {
        widget.diagnostics?.projections++;
        point = camera.projectAtZoom(station.coordinate, 0);
      }
      final glyph = _StationGlyph(
        point,
        color,
        label,
        level,
        shape,
        eventColor,
      );
      widget.diagnostics?.glyphCreations++;
      prepared[i] = glyph;
      glyphs.add(glyph);
    }
    _preparedStations = widget.stations;
    _preparedGlyphs = prepared;
    _preparedScale = scale;
    // New sample timestamps must refresh expiry without invalidating unchanged pixels.
    var sameVisuals = glyphs.length == _inputGlyphs.length;
    if (sameVisuals) {
      for (var i = 0; i < glyphs.length; i++) {
        final a = glyphs[i], b = _inputGlyphs[i];
        if (!identical(a, b) &&
            (a.point != b.point ||
                a.color != b.color ||
                a.label != b.label ||
                a.shape != b.shape ||
                a.eventColor != b.eventColor)) {
          sameVisuals = false;
          break;
        }
      }
    }
    if (!sameVisuals) {
      _inputGlyphs = glyphs;
      _glyphs = glyphs;
      if (_glyphs.isEmpty) _scene.clear();
    }
    if (expires != null) {
      _expiry = Timer(Duration(microseconds: expires - now + 1000), () {
        if (mounted) setState(() => _dirty = true);
      });
    }
    widget.diagnostics?.preparationMicros += watch!.elapsedMicroseconds;
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    if (_dirty || _crs != camera.crs) _prepare(camera);
    if (_glyphs.isEmpty) return const SizedBox.shrink();
    _scene.prepare(
      camera,
      _glyphs,
      MediaQuery.devicePixelRatioOf(context),
      widget.diagnostics,
    );
    final bounds = _scene.bounds;
    return IgnorePointer(
      child: MobileLayerTransformer(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: bounds.width,
          maxWidth: bounds.width,
          minHeight: bounds.height,
          maxHeight: bounds.height,
          child: Transform.translate(
            offset: bounds.topLeft - camera.pixelOrigin,
            child: SizedBox.fromSize(
              size: bounds.size,
              child: Stack(
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      size: bounds.size,
                      isComplex: true,
                      painter: _FdsnPainter(_scene.picture, widget.diagnostics),
                    ),
                  ),
                  if (_scene.events != null)
                    _EventBlink(
                      picture: _scene.events!,
                      size: bounds.size,
                      diagnostics: widget.diagnostics,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _expiry?.cancel();
    SeedLinkStationStyle.shape.removeListener(_scaleChanged);
    FdsnIntensity.scale.removeListener(_scaleChanged);
    _scene.clear();
    super.dispose();
  }
}

const _mmiColors = [
  0xFFE8F6FF,
  0xFFACD8E9,
  0xFF7BE1F1,
  0xFFB9F26C,
  0xFFFFFF00,
  0xFFFFD200,
  0xFFFF9600,
  0xFFFF0000,
  0xFFC80000,
  0xFFC800A0,
];

class _StationGlyph {
  const _StationGlyph(
    this.point,
    this.color,
    this.label,
    this.level,
    this.shape,
    this.eventColor,
  );
  final Offset point;
  final int color;
  final String label;
  final int level;
  final SeedLinkMarkerShape shape;
  final int? eventColor;
}

class _FdsnPainter extends CustomPainter {
  const _FdsnPainter(this.picture, this.diagnostics);
  final ui.Picture picture;
  final FdsnLayerDiagnostics? diagnostics;
  @override
  void paint(Canvas canvas, Size size) {
    diagnostics?.paints++;
    canvas.drawPicture(picture);
  }

  @override
  bool shouldRepaint(_FdsnPainter old) => !identical(picture, old.picture);
}

// No timer or full station-layer repaint for an idle map.
class _EventBlink extends StatefulWidget {
  const _EventBlink({
    required this.picture,
    required this.size,
    this.diagnostics,
  });
  final ui.Picture picture;
  final Size size;
  final FdsnLayerDiagnostics? diagnostics;
  @override
  State<_EventBlink> createState() => _EventBlinkState();
}

class _EventBlinkState extends State<_EventBlink> {
  final _pulse = ValueNotifier(0);
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _pulse.value = now ~/ 500;
    _timer = Timer(Duration(milliseconds: 500 - now % 500), _tick);
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: widget.size,
      painter: _EventPainter(widget.picture, _pulse, widget.diagnostics),
    ),
  );
  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }
}

class _EventPainter extends CustomPainter {
  _EventPainter(this.picture, this.pulse, this.diagnostics)
    : super(repaint: pulse);
  final ui.Picture picture;
  final ValueNotifier<int> pulse;
  final FdsnLayerDiagnostics? diagnostics;
  @override
  void paint(Canvas canvas, Size size) {
    diagnostics?.eventPaints++;
    if (pulse.value.isEven) canvas.drawPicture(picture);
  }

  @override
  bool shouldRepaint(_EventPainter old) => !identical(picture, old.picture);
}

// Retained viewport plus margin, translated outside its repaint boundary.
class _FdsnScene {
  final _atlas = _StationAtlas();
  final _index = _GlyphSpatialIndex();
  Float32List _transforms = Float32List(0), _rectangles = Float32List(0);
  Int32List _colors = Int32List(0);
  final _paint = Paint()..filterQuality = FilterQuality.low;
  ui.Picture? _picture, events;
  Rect _bounds = Rect.zero;
  double? _zoom, _world;
  bool _showLabels = false;
  double _markerScale = 1;
  List<_StationGlyph>? _sourceGlyphs;
  List<(_StationGlyph, Offset)> _visibleGlyphs = const [];
  Rect get bounds => _bounds;
  ui.Picture get picture => _picture!;

  void clear() {
    _picture?.dispose();
    events?.dispose();
    _picture = events = null;
    _sourceGlyphs = null;
    _visibleGlyphs = const [];
    _atlas.dispose();
    _index.clear();
    _transforms = _rectangles = Float32List(0);
    _colors = Int32List(0);
  }

  void prepare(
    MapCamera camera,
    List<_StationGlyph> glyphs,
    double pixelRatio,
    FdsnLayerDiagnostics? diagnostics,
  ) {
    final visibleBounds = (camera.pixelOrigin & camera.size).inflate(72);
    final world = camera.getWorldWidthAtZoom();
    final viewChanged =
        _picture == null ||
        _zoom != camera.zoom ||
        _world != world ||
        !_bounds.contains(visibleBounds.topLeft) ||
        !_bounds.contains(visibleBounds.bottomRight);
    if (viewChanged) {
      _zoom = camera.zoom;
      _showLabels = camera.zoom >= SeedLinkStationStyle.labelMinZoom;
      _markerScale = SeedLinkStationStyle.markerScale(camera.zoom);
      _world = world;
      _bounds = visibleBounds.inflate(128);
    }
    final densityChanged = _atlas.pixelRatio != pixelRatio;
    if (!viewChanged && !densityChanged && identical(_sourceGlyphs, glyphs)) {
      return;
    }
    if (!identical(_sourceGlyphs, glyphs)) {
      final previous = _sourceGlyphs;
      // Color/number changes leave the zoom-zero spatial index intact.
      if (previous == null ||
          previous.length != glyphs.length ||
          Iterable<int>.generate(
            glyphs.length,
          ).any((i) => previous[i].point != glyphs[i].point)) {
        _index.prepare(glyphs, diagnostics);
      }
    }
    final visible = _select(camera, glyphs, diagnostics);
    _sourceGlyphs = glyphs;
    final samePixels =
        visible.length == _visibleGlyphs.length &&
        Iterable<int>.generate(visible.length).every((i) {
          final a = visible[i], b = _visibleGlyphs[i];
          return a.$2 == b.$2 &&
              a.$1.color == b.$1.color &&
              a.$1.shape == b.$1.shape &&
              a.$1.eventColor == b.$1.eventColor &&
              (!_showLabels || a.$1.label == b.$1.label);
        });
    if (viewChanged || densityChanged || !samePixels) {
      _picture?.dispose();
      events?.dispose();
      events = null;
      _visibleGlyphs = visible;
      _atlas.prepare(pixelRatio, diagnostics);
      final recorder = ui.PictureRecorder();
      _record(Canvas(recorder), diagnostics);
      _picture = recorder.endRecording();
      diagnostics?.pictureRecordings++;
    }
  }

  List<(_StationGlyph, Offset)> _select(
    MapCamera camera,
    List<_StationGlyph> glyphs,
    FdsnLayerDiagnostics? diagnostics,
  ) {
    final factor = camera.getZoomScale(camera.zoom, 0);
    final world = camera.getWorldWidthAtZoom();
    final selected = <(_StationGlyph, Offset)>[];
    final candidates = _index.query(_bounds, factor, world);
    final count = candidates?.length ?? glyphs.length;
    diagnostics?.selectionVisits += count;
    final buckets = List.generate(81, (_) => <(_StationGlyph, Offset)>[]);
    for (var i = 0; i < count; i++) {
      final glyph = glyphs[candidates == null ? i : candidates[i]];
      final p = glyph.point * factor;
      if (p.dy < _bounds.top || p.dy > _bounds.bottom) continue;
      final first = world > 0 ? ((_bounds.left - p.dx) / world).ceil() : 0;
      final last = world > 0 ? ((_bounds.right - p.dx) / world).floor() : 0;
      for (var copy = first; copy <= last; copy++) {
        final shifted = Offset(p.dx + copy * world, p.dy);
        if (_bounds.contains(shifted)) {
          buckets[glyph.level + 1].add((glyph, shifted - _bounds.topLeft));
        }
      }
    }
    for (final bucket in buckets) {
      selected.addAll(bucket);
    }
    return selected;
  }

  void _record(Canvas canvas, FdsnLayerDiagnostics? diagnostics) {
    if (_visibleGlyphs.isEmpty) return;
    var count = _visibleGlyphs.length;
    if (_showLabels) {
      for (final item in _visibleGlyphs) {
        count += item.$1.label.length;
      }
    }
    if (_colors.length < count) {
      final capacity = math.max(count, _colors.length * 2);
      _transforms = Float32List(capacity * 4);
      _rectangles = Float32List(capacity * 4);
      _colors = Int32List(capacity);
      diagnostics?.bufferAllocations++;
    }
    final inverse = 1 / _atlas.pixelRatio;
    final cell = _atlas.cellPixels.toDouble();
    final half = cell * inverse / 2;
    var n = 0;
    void sprite(int slot, double x, double y, int color, [double scale = 1]) {
      final i = n * 4;
      _transforms[i] = inverse * scale;
      _transforms[i + 2] = x;
      _transforms[i + 3] = y;
      _rectangles[i] = (slot % _StationAtlas.columns) * cell;
      _rectangles[i + 1] = (slot ~/ _StationAtlas.columns) * cell;
      _rectangles[i + 2] = _rectangles[i] + cell;
      _rectangles[i + 3] = _rectangles[i + 1] + cell;
      _colors[n++] = color;
    }

    ui.PictureRecorder? eventRecorder;
    Canvas? eventCanvas;
    final framePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final (glyph, point) in _visibleGlyphs) {
      sprite(
        glyph.shape.index,
        point.dx - half * _markerScale,
        point.dy - half * _markerScale,
        glyph.color,
        _markerScale,
      );
      if (_showLabels) {
        var width = 0.0;
        for (final code in glyph.label.codeUnits) {
          width += _atlas.advance[code]!;
        }
        var x = point.dx - width / 2;
        for (final code in glyph.label.codeUnits) {
          sprite(
            _atlas.digits[code]!,
            x - 2,
            point.dy + 13 + 7 * _markerScale - _atlas.baseline,
            glyph.eventColor == null ? 0xFFC0C0C0 : 0xFF00FF00,
          );
          x += _atlas.advance[code]!;
        }
      }
      if (glyph.eventColor != null) {
        eventRecorder ??= ui.PictureRecorder();
        eventCanvas ??= Canvas(eventRecorder);
        framePaint.color = Color(glyph.eventColor!);
        eventCanvas.drawRect(
          Rect.fromCenter(
            center: point,
            width: 14 * math.sqrt2 * _markerScale,
            height: 14 * math.sqrt2 * _markerScale,
          ),
          framePaint,
        );
      }
    }
    events = eventRecorder?.endRecording();
    canvas.drawRawAtlas(
      _atlas.image!,
      Float32List.sublistView(_transforms, 0, n * 4),
      Float32List.sublistView(_rectangles, 0, n * 4),
      Int32List.sublistView(_colors, 0, n),
      BlendMode.modulate,
      null,
      _paint,
    );
    diagnostics?.recordedStations += _visibleGlyphs.length;
    diagnostics?.atlasDraws++;
  }
}

/// Zoom-zero grid. Queries only prune candidates: the original exact bounds,
/// wrapping and stable paint order are still applied by the scene.
class _GlyphSpatialIndex {
  static const cell = 4.0;
  final _cells = <(int, int), List<int>>{};
  Rect _extent = Rect.zero;
  int _length = 0;

  void clear() {
    _cells.clear();
    _length = 0;
  }

  void prepare(List<_StationGlyph> glyphs, FdsnLayerDiagnostics? diagnostics) {
    clear();
    _length = glyphs.length;
    if (glyphs.length < 128) return;
    var left = double.infinity, top = double.infinity;
    var right = double.negativeInfinity, bottom = double.negativeInfinity;
    for (var i = 0; i < glyphs.length; i++) {
      final p = glyphs[i].point;
      left = math.min(left, p.dx);
      right = math.max(right, p.dx);
      top = math.min(top, p.dy);
      bottom = math.max(bottom, p.dy);
      _cells
          .putIfAbsent(((p.dx / cell).floor(), (p.dy / cell).floor()), () => [])
          .add(i);
    }
    _extent = Rect.fromLTRB(left, top, right, bottom);
    diagnostics?.spatialIndexBuilds++;
  }

  List<int>? query(Rect pixels, double factor, double world) {
    if (_length < 128 || !factor.isFinite || factor <= 0) return null;
    final bounds = Rect.fromLTRB(
      pixels.left / factor,
      pixels.top / factor,
      pixels.right / factor,
      pixels.bottom / factor,
    ).inflate(1e-9);
    // Dense/full-world views are cheaper as one linear scan, without a set/sort.
    if (bounds.width >= _extent.width * .5 &&
        bounds.height >= _extent.height * .5) {
      return null;
    }
    final top = math.max(bounds.top, _extent.top),
        bottom = math.min(bounds.bottom, _extent.bottom);
    if (bottom < top) return const [];
    final width = world / factor;
    final first = width > 0
        ? ((bounds.left - _extent.right) / width).ceil()
        : 0;
    final last = width > 0
        ? ((bounds.right - _extent.left) / width).floor()
        : 0;
    final found = <int>{};
    for (var copy = first; copy <= last; copy++) {
      final left = math.max(bounds.left - copy * width, _extent.left);
      final right = math.min(bounds.right - copy * width, _extent.right);
      for (var x = (left / cell).floor(); x <= (right / cell).floor(); x++) {
        for (var y = (top / cell).floor(); y <= (bottom / cell).floor(); y++) {
          final entries = _cells[(x, y)];
          if (entries != null) found.addAll(entries);
        }
      }
    }
    return found.toList()..sort();
  }
}

// Four white shapes and fourteen white characters, tinted in one GPU batch.
// Numeric changes never allocate TextPainters or grow the atlas.
class _StationAtlas {
  static const columns = 8;
  static const characters = '0123456789.-e+';
  final digits = <int, int>{};
  final advance = <int, double>{};
  ui.Image? image;
  double pixelRatio = 0, baseline = 0;
  int cellPixels = 0;

  void prepare(double ratio, FdsnLayerDiagnostics? diagnostics) {
    if (image != null && pixelRatio == ratio) return;
    pixelRatio = ratio;
    cellPixels = (24 * ratio).ceil();
    final cell = cellPixels / ratio;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(ratio);
    final paint = Paint()..color = Colors.white;
    for (final shape in SeedLinkMarkerShape.values) {
      final point = Offset(
        (shape.index % columns + .5) * cell,
        (shape.index ~/ columns + .5) * cell,
      );
      canvas.drawPath(_markerPath(point, shape), paint);
    }
    for (var i = 0; i < characters.length; i++) {
      final code = characters.codeUnitAt(i);
      final slot = SeedLinkMarkerShape.values.length + i;
      digits[code] = slot;
      final text = TextPainter(
        text: TextSpan(
          text: characters[i],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontFamily: 'Calibri',
            fontFamilyFallback: ['MPLUSRounded1c'],
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      advance[code] = text.width;
      baseline = text.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      text.paint(
        canvas,
        Offset((slot % columns) * cell + 2, (slot ~/ columns) * cell + 2),
      );
      text.dispose();
    }
    final picture = recorder.endRecording();
    final slots = SeedLinkMarkerShape.values.length + characters.length;
    final next = picture.toImageSync(
      columns * cellPixels,
      (slots / columns).ceil() * cellPixels,
    );
    picture.dispose();
    image?.dispose();
    image = next;
    diagnostics?.atlasBuilds++;
    diagnostics?.atlasSlots = slots;
  }

  void dispose() {
    image?.dispose();
    image = null;
    digits.clear();
    advance.clear();
  }

  Path _markerPath(Offset point, SeedLinkMarkerShape shape) {
    final path = Path();
    const radius = 7.0;
    switch (shape) {
      case SeedLinkMarkerShape.circle:
        path.addOval(Rect.fromCircle(center: point, radius: radius));
      case SeedLinkMarkerShape.square:
        final side = radius * 1.41 * math.sqrt2;
        path.addRect(Rect.fromCenter(center: point, width: side, height: side));
      case SeedLinkMarkerShape.triangle:
      case SeedLinkMarkerShape.invertedTriangle:
        final direction = shape == SeedLinkMarkerShape.triangle ? 1.0 : -1.0;
        const extent = radius * 1.41;
        final x = extent * math.sqrt(3) / 2;
        path
          ..moveTo(point.dx, point.dy - extent * direction)
          ..lineTo(point.dx + x, point.dy + extent * .5 * direction)
          ..lineTo(point.dx - x, point.dy + extent * .5 * direction)
          ..close();
    }
    return path;
  }
}
