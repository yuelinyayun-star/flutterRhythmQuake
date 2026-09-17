import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../core/fdsn_intensity.dart';
import '../../core/intensity_calculator.dart';
import '../../services/sources/fdsn_station_service.dart';
import 'ka_kma_marker_style.dart';

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
}

class _FdsnStationLayerState extends State<FdsnStationLayer> {
  final _labels = <(int, Color), TextPainter>{};
  final _styles = <(FdsnIntensityScale, int?), (Color, TextPainter?)>{};
  List<_StationGlyph> _glyphs = const [];
  List<_StationGlyph> _inputGlyphs = const [];
  List<FdsnStation> _preparedStations = const [];
  List<_StationGlyph?> _preparedGlyphs = const [];
  FdsnIntensityScale? _preparedScale;
  final _scene = _FdsnScene();
  bool _dirty = true;
  Crs? _crs;
  Timer? _expiry;

  @override
  void initState() {
    super.initState();
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
    final scale = FdsnIntensity.scale.value;
    final glyphs = <_StationGlyph>[];
    final prepared = List<_StationGlyph?>.filled(widget.stations.length, null);
    for (var i = 0; i < widget.stations.length; i++) {
      final station = widget.stations[i];
      final updated = station.lastMotionUpdate;
      if (updated == null || updated.microsecondsSinceEpoch > now) continue;
      final end =
          updated.microsecondsSinceEpoch +
          FdsnStation.motionRetention.inMicroseconds;
      if (end <= now) continue;
      if (expires == null || end < expires) expires = end;
      final previous = i < _preparedStations.length
          ? _preparedStations[i]
          : null;
      final oldGlyph = i < _preparedGlyphs.length ? _preparedGlyphs[i] : null;
      final sameCoordinate =
          sameCrs && previous?.coordinate == station.coordinate;
      if (oldGlyph != null &&
          sameCoordinate &&
          _preparedScale == scale &&
          previous!.intensity == station.intensity &&
          previous.pga == station.pga &&
          previous.pgv == station.pgv) {
        // Receipt-time changes only affect expiry, not a glyph's appearance.
        prepared[i] = oldGlyph;
        glyphs.add(oldGlyph);
        continue;
      }
      final level = FdsnIntensity.displayLevel(
        scale,
        mmi: station.intensity,
        pgaGal: station.pga,
        pgvCms: station.pgv,
      );
      final (color, label) = _styles.putIfAbsent((scale, level), () {
        final color = level == null
            ? const Color(0xFF2F80ED)
            : scale == FdsnIntensityScale.csis
            ? Color(IntensityCalculator.getCsisColor(level))
            : _mmiColors[level - 1];
        TextPainter? label;
        if (level != null) {
          final foreground = color.computeLuminance() > 0.35
              ? Colors.black
              : Colors.white;
          label = _labels.putIfAbsent(
            (level, foreground),
            () => TextPainter(
              text: TextSpan(
                text: '$level',
                style: TextStyle(
                  color: foreground,
                  fontSize: 8,
                  fontFamily: 'MPLUSRounded1c',
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout(),
          );
        }
        return (color, label);
      });
      final Offset point;
      if (oldGlyph != null && sameCoordinate) {
        point = oldGlyph.point;
      } else {
        widget.diagnostics?.projections++;
        point = camera.projectAtZoom(station.coordinate, 0);
      }
      final glyph = _StationGlyph(point, color, label, level ?? 0);
      prepared[i] = glyph;
      glyphs.add(glyph);
    }
    _preparedStations = widget.stations;
    _preparedGlyphs = prepared;
    _preparedScale = scale;
    // New sample timestamps must refresh expiry without invalidating unchanged pixels.
    final sameVisuals =
        glyphs.length == _inputGlyphs.length &&
        Iterable<int>.generate(glyphs.length).every(
          (i) =>
              glyphs[i].point == _inputGlyphs[i].point &&
              glyphs[i].color == _inputGlyphs[i].color &&
              glyphs[i].label == _inputGlyphs[i].label,
        );
    if (!sameVisuals) {
      _inputGlyphs = glyphs;
      // Stable level buckets prevent equal-level overlap order changing on updates.
      final levels = List.generate(13, (_) => <_StationGlyph>[]);
      for (final glyph in glyphs) {
        levels[glyph.level].add(glyph);
      }
      _glyphs = [for (final level in levels) ...level];
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
            child: RepaintBoundary(
              child: CustomPaint(
                size: bounds.size,
                isComplex: true,
                painter: _FdsnPainter(_scene.picture, widget.diagnostics),
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
    FdsnIntensity.scale.removeListener(_scaleChanged);
    _scene.clear();
    for (final label in _labels.values) {
      label.dispose();
    }
    super.dispose();
  }
}

const _mmiColors = [
  Color(0xFFE8F6FF),
  Color(0xFFACD8E9),
  Color(0xFF7BE1F1),
  Color(0xFFB9F26C),
  Color(0xFFFFFF00),
  Color(0xFFFFD200),
  Color(0xFFFF9600),
  Color(0xFFFF0000),
  Color(0xFFC80000),
  Color(0xFFC800A0),
];

class _StationGlyph {
  const _StationGlyph(this.point, this.color, this.label, this.level);
  final Offset point;
  final Color color;
  final TextPainter? label;
  final int level;
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
  bool shouldRepaint(_FdsnPainter oldDelegate) =>
      !identical(picture, oldDelegate.picture);
}

// The viewport margin belongs to a retained repaint boundary. Camera translation
// is outside that boundary, so panning does not repaint its display list.
class _FdsnScene {
  final _atlas = _StationAtlas();
  ui.Picture? _picture;
  Rect _bounds = Rect.zero;
  double? _zoom;
  double? _world;
  List<_StationGlyph>? _sourceGlyphs;
  List<(_StationGlyph, Offset)> _visibleGlyphs = const [];
  Rect get bounds => _bounds;
  ui.Picture get picture => _picture!;

  void clear() {
    _picture?.dispose();
    _picture = null;
    _sourceGlyphs = null;
    _visibleGlyphs = const [];
    _atlas.dispose();
  }

  void prepare(
    MapCamera camera,
    List<_StationGlyph> glyphs,
    double pixelRatio,
    FdsnLayerDiagnostics? diagnostics,
  ) {
    // Keep the retained drawing origin fractional, like the actual map origin.
    final visibleBounds = (camera.pixelOrigin & camera.size).inflate(14);
    final world = camera.getWorldWidthAtZoom();
    final viewChanged =
        _picture == null ||
        _zoom != camera.zoom ||
        _world != world ||
        !_bounds.contains(visibleBounds.topLeft) ||
        !_bounds.contains(visibleBounds.bottomRight);
    if (viewChanged) {
      _zoom = camera.zoom;
      _world = world;
      _bounds = visibleBounds.inflate(128);
    }
    final densityChanged = _atlas.pixelRatio != pixelRatio;
    if (!viewChanged && !densityChanged && identical(_sourceGlyphs, glyphs)) {
      return;
    }
    final visible = _select(camera, glyphs);
    _sourceGlyphs = glyphs;
    final samePixels =
        visible.length == _visibleGlyphs.length &&
        Iterable<int>.generate(visible.length).every(
          (i) =>
              visible[i].$2 == _visibleGlyphs[i].$2 &&
              visible[i].$1.color == _visibleGlyphs[i].$1.color &&
              visible[i].$1.label == _visibleGlyphs[i].$1.label,
        );
    if (viewChanged || densityChanged || !samePixels) {
      _picture?.dispose();
      _visibleGlyphs = visible;
      _atlas.prepare(glyphs, pixelRatio, diagnostics);
      final recorder = ui.PictureRecorder();
      _record(Canvas(recorder), diagnostics);
      _picture = recorder.endRecording();
      diagnostics?.pictureRecordings++;
    }
  }

  List<(_StationGlyph, Offset)> _select(
    MapCamera camera,
    List<_StationGlyph> glyphs,
  ) {
    final factor = camera.getZoomScale(camera.zoom, 0);
    final world = camera.getWorldWidthAtZoom();
    final selected = <(_StationGlyph, Offset)>[];
    // Preserve the original order, with the strongest stations painted last.
    for (final glyph in glyphs) {
      final p = glyph.point * factor;
      if (p.dy < _bounds.top || p.dy > _bounds.bottom) continue;
      // Draw every visible world copy instead of switching one copy at its midpoint.
      final first = world > 0 ? ((_bounds.left - p.dx) / world).ceil() : 0;
      final last = world > 0 ? ((_bounds.right - p.dx) / world).floor() : 0;
      for (var copy = first; copy <= last; copy++) {
        final shifted = Offset(p.dx + copy * world, p.dy);
        if (_bounds.contains(shifted)) {
          selected.add((glyph, shifted - _bounds.topLeft));
        }
      }
    }
    return selected;
  }

  void _record(Canvas canvas, FdsnLayerDiagnostics? diagnostics) {
    if (_visibleGlyphs.isEmpty) return;
    final transforms = Float32List(_visibleGlyphs.length * 4);
    final rectangles = Float32List(transforms.length);
    final inverseRatio = 1 / _atlas.pixelRatio;
    final cell = _atlas.cellPixels;
    final half = cell * inverseRatio / 2;
    var index = 0;
    for (final (glyph, point) in _visibleGlyphs) {
      final slot = _atlas.slots[(glyph.color, glyph.label)]!;
      transforms[index] = inverseRatio;
      transforms[index + 2] = point.dx - half;
      transforms[index + 3] = point.dy - half;
      rectangles[index] = (slot % _StationAtlas.columns) * cell.toDouble();
      rectangles[index + 1] = (slot ~/ _StationAtlas.columns) * cell.toDouble();
      rectangles[index + 2] = rectangles[index] + cell;
      rectangles[index + 3] = rectangles[index + 1] + cell;
      index += 4;
    }
    canvas.drawRawAtlas(
      _atlas.image!,
      transforms,
      rectangles,
      null,
      null,
      null,
      Paint()..filterQuality = FilterQuality.low,
    );
    diagnostics?.recordedStations += _visibleGlyphs.length;
    diagnostics?.atlasDraws++;
  }
}

// Only the finite intensity styles are rasterized, never a viewport-sized image.
// Camera changes submit positions in one batch without rerasterizing each label.
class _StationAtlas {
  static const columns = 8;
  final slots = <(Color, TextPainter?), int>{};
  ui.Image? image;
  double pixelRatio = 0;
  int cellPixels = 0;
  List<_StationGlyph>? _source;

  bool prepare(
    List<_StationGlyph> glyphs,
    double ratio,
    FdsnLayerDiagnostics? diagnostics,
  ) {
    if (image != null && pixelRatio == ratio && identical(_source, glyphs)) {
      return false;
    }
    var changed = image == null || pixelRatio != ratio;
    for (final glyph in glyphs) {
      final key = (glyph.color, glyph.label);
      if (!slots.containsKey(key)) {
        slots[key] = slots.length;
        changed = true;
      }
    }
    _source = glyphs;
    if (!changed) return false;
    pixelRatio = ratio;
    cellPixels = (20 * ratio).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(ratio);
    final fill = Paint();
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final entry in slots.entries) {
      final (color, label) = entry.key;
      final slot = entry.value;
      final cell = cellPixels / ratio;
      final point = Offset(
        (slot % columns + .5) * cell,
        (slot ~/ columns + .5) * cell,
      );
      fill.color = label == null ? color.withValues(alpha: 0.48) : color;
      final radius = label == null
          ? 3.2
          : KaKmaMarkerStyle.labeledMarkerSize / 2;
      canvas.drawCircle(point, radius, fill);
      if (label != null) {
        canvas.drawCircle(point, radius, border);
        label.paint(canvas, point - Offset(label.width / 2, label.height / 2));
      }
    }
    final picture = recorder.endRecording();
    final next = picture.toImageSync(
      columns * cellPixels,
      (slots.length / columns).ceil() * cellPixels,
    );
    picture.dispose();
    image?.dispose();
    image = next;
    diagnostics?.atlasBuilds++;
    return true;
  }

  void dispose() {
    image?.dispose();
    image = null;
    slots.clear();
    _source = null;
  }
}
