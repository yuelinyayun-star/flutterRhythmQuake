import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

class FaultStroke {
  const FaultStroke({required this.points, required this.color});

  final List<LatLng> points;
  final Color color;
}

/// Static, noninteractive traces. Source coordinates and draw order are retained.
class CachedFaultLayer extends StatefulWidget {
  const CachedFaultLayer({super.key, required this.lines});

  final List<FaultStroke> lines;
  static const strokeWidth = 1.5;

  @override
  State<CachedFaultLayer> createState() => _CachedFaultLayerState();
}

class _CachedFaultLayerState extends State<CachedFaultLayer> {
  Crs? _crs;
  List<_FaultBatch> _batches = [];

  void _clear() {
    for (final batch in _batches) {
      batch.dispose();
    }
    _batches = [];
  }

  @override
  void didUpdateWidget(CachedFaultLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lines, widget.lines)) {
      _clear();
      _crs = null;
    }
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    if (_crs != camera.crs) {
      _clear();
      _crs = camera.crs;
      // Small consecutive batches preserve translucent intersection ordering.
      for (var start = 0; start < widget.lines.length; start += 32) {
        final end = (start + 32).clamp(0, widget.lines.length);
        _batches.add(_FaultBatch(widget.lines.sublist(start, end), camera.crs));
      }
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: MobileLayerTransformer(
          child: CustomPaint(
            size: camera.size,
            painter: _FaultPainter(camera, _batches),
          ),
        ),
      ),
    );
  }
}

const _referenceZoom = 12.0;

class _FaultPath {
  _FaultPath(FaultStroke line, Crs crs) : color = line.color {
    final points = line.points
        .map((p) => crs.latLngToOffset(p, _referenceZoom))
        .toList(growable: false);
    origin = points.first;
    var minX = origin.dx, maxX = origin.dx;
    var minY = origin.dy, maxY = origin.dy;
    path.moveTo(0, 0);
    for (final point in points.skip(1)) {
      // Keep Path's float coordinates local, including at large map zooms.
      path.lineTo(point.dx - origin.dx, point.dy - origin.dy);
      if (point.dx < minX) minX = point.dx;
      if (point.dx > maxX) maxX = point.dx;
      if (point.dy < minY) minY = point.dy;
      if (point.dy > maxY) maxY = point.dy;
    }
    bounds = Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  final Color color;
  final Path path = Path();
  late final Offset origin;
  late final Rect bounds;
}

class _FaultBatch {
  _FaultBatch(List<FaultStroke> lines, Crs crs)
    : paths = lines
          .where((line) => line.points.length >= 2)
          .map((line) => _FaultPath(line, crs))
          .toList(growable: false) {
    if (paths.isEmpty) return;
    bounds = paths.first.bounds;
    for (final path in paths.skip(1)) {
      bounds = bounds.expandToInclude(path.bounds);
    }
  }

  final List<_FaultPath> paths;
  Rect bounds = Rect.zero;
  ui.Picture? _picture;
  double? _scale;
  Rect? _coverage;
  Offset _origin = Offset.zero;

  void dispose() {
    _picture?.dispose();
    _picture = null;
  }

  void paint(Canvas canvas, Rect viewport, double scale, Offset pixelOrigin) {
    if (paths.isEmpty || !bounds.overlaps(viewport)) return;
    // Reuse drawing commands during pans. Bounded overscan also avoids large
    // off-screen coordinates in pictures at street-level zooms.
    if (_picture == null ||
        _scale != scale ||
        !_coverage!.contains(viewport.topLeft) ||
        !_coverage!.contains(viewport.bottomRight)) {
      dispose();
      _scale = scale;
      _coverage = viewport.inflate(256 / scale);
      _origin = viewport.center;
      final recorder = ui.PictureRecorder();
      final recording = Canvas(recorder);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = CachedFaultLayer.strokeWidth / scale;
      for (final line in paths) {
        if (!line.bounds.overlaps(_coverage!)) continue;
        paint.color = line.color;
        final offset = (line.origin - _origin) * scale;
        recording.save();
        recording.translate(offset.dx, offset.dy);
        recording.scale(scale);
        recording.drawPath(line.path, paint);
        recording.restore();
      }
      _picture = recorder.endRecording();
    }
    final offset = _origin * scale - pixelOrigin;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.drawPicture(_picture!);
    canvas.restore();
  }
}

class _FaultPainter extends CustomPainter {
  _FaultPainter(this.camera, this.batches);

  final MapCamera camera;
  final List<_FaultBatch> batches;

  @override
  void paint(Canvas canvas, Size size) {
    final scale =
        camera.crs.scale(camera.zoom) / camera.crs.scale(_referenceZoom);
    final origin = camera.pixelOrigin;
    final viewport = Rect.fromLTWH(
      origin.dx / scale,
      origin.dy / scale,
      size.width / scale,
      size.height / scale,
    ).inflate(2 / scale);
    final worldWidth = camera.crs.replicatesWorldLongitude
        ? camera.crs.getProjectedBounds(_referenceZoom)!.width
        : 0.0;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final batch in batches) {
      final first = worldWidth == 0
          ? 0
          : ((viewport.left - batch.bounds.right) / worldWidth).ceil();
      final last = worldWidth == 0
          ? 0
          : ((viewport.right - batch.bounds.left) / worldWidth).floor();
      for (var world = first; world <= last; world++) {
        final shift = Offset(world * worldWidth, 0);
        batch.paint(
          canvas,
          viewport.shift(-shift),
          scale,
          origin - shift * scale,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FaultPainter oldDelegate) =>
      oldDelegate.camera != camera || !identical(oldDelegate.batches, batches);

  @override
  bool? hitTest(Offset position) => false;
}
