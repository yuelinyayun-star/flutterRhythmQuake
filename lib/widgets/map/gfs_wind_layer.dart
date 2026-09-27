import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/sources/gfs_wind_service.dart';

class GfsWindLayer extends StatefulWidget {
  const GfsWindLayer({super.key, this.service});

  final GfsWindService? service;

  @override
  State<GfsWindLayer> createState() => _GfsWindLayerState();
}

class _GfsWindLayerState extends State<GfsWindLayer>
    with SingleTickerProviderStateMixin {
  late final GfsWindService _service;
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();
  Timer? _debounce;
  Timer? _refresh;
  GfsWindGrid? _grid;
  int _requestId = 0;
  bool _loading = false;
  _WindBounds? _wanted;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? GfsWindService();
    _refresh = Timer.periodic(const Duration(minutes: 30), (_) {
      final bounds = _wanted;
      if (bounds != null) _load(bounds, refresh: true);
    });
  }

  void _schedule(MapCamera camera) {
    final visible = _WindBounds.fromCamera(camera);
    if (visible == null) return;
    _wanted = visible;
    if (_grid?.covers(
          south: visible.south,
          north: visible.north,
          west: visible.west,
          east: visible.east,
        ) ==
        true) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _load(visible));
  }

  Future<void> _load(_WindBounds visible, {bool refresh = false}) async {
    if (!mounted || (_loading && refresh)) return;
    final expanded = visible.expanded();
    final id = ++_requestId;
    _loading = true;
    try {
      final grid = await _service.fetch(
        south: expanded.south,
        north: expanded.north,
        west: expanded.west,
        east: expanded.east,
      );
      if (mounted && id == _requestId) setState(() => _grid = grid);
    } catch (error) {
      // Keep the last valid field while the weather provider is unavailable.
      debugPrint('GFS wind layer: $error');
    } finally {
      if (id == _requestId) _loading = false;
    }
  }

  @override
  void dispose() {
    _requestId++;
    _debounce?.cancel();
    _refresh?.cancel();
    _animation.dispose();
    _service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    _schedule(camera);
    final grid = _grid;
    if (grid == null) return const SizedBox.shrink();
    return MobileLayerTransformer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: camera.size,
          isComplex: true,
          willChange: true,
          painter: _GfsWindPainter(
            camera: camera,
            grid: grid,
            animation: _animation,
          ),
        ),
      ),
    );
  }
}

class _WindBounds {
  const _WindBounds(this.south, this.north, this.west, this.east);

  final double south;
  final double north;
  final double west;
  final double east;

  static _WindBounds? fromCamera(MapCamera camera) {
    final bounds = camera.visibleBounds;
    final south = bounds.southWest.latitude.clamp(-84.0, 84.0).toDouble();
    final north = bounds.northEast.latitude.clamp(-84.0, 84.0).toDouble();
    final west = bounds.southWest.longitude;
    var east = bounds.northEast.longitude;
    if (east <= west) east += 360;
    if (!south.isFinite ||
        !north.isFinite ||
        !west.isFinite ||
        !east.isFinite ||
        north <= south) {
      return null;
    }
    return _WindBounds(south, north, west, math.min(east, west + 360));
  }

  _WindBounds expanded() {
    final latPadding = (north - south) * 0.35;
    final center = (east + west) / 2;
    final halfWidth = math.min(180.0, (east - west) * 0.85);
    return _WindBounds(
      math.max(-84, south - latPadding),
      math.min(84, north + latPadding),
      center - halfWidth,
      center + halfWidth,
    );
  }
}

class _GfsWindPainter extends CustomPainter {
  _GfsWindPainter({
    required this.camera,
    required this.grid,
    required this.animation,
  }) : super(repaint: animation);

  final MapCamera camera;
  final GfsWindGrid grid;
  final AnimationController animation;

  @override
  void paint(Canvas canvas, Size size) {
    final worldWidth = camera.getWorldWidthAtZoom();
    final origin = camera.pixelOrigin;
    final centerX = origin.dx + size.width / 2;
    final paint = Paint()
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final latStep = (grid.north - grid.south) / (grid.rows - 1) / 2;
    final lonStep = (grid.east - grid.west) / (grid.columns - 1) / 2;
    for (var row = 0; row < (grid.rows - 1) * 2; row++) {
      final lat = grid.south + (row + 0.5) * latStep;
      for (var column = 0; column < (grid.columns - 1) * 2; column++) {
        final lon = grid.west + (column + 0.5) * lonStep;
        final wind = grid.sample(lat, lon);
        if (wind == null || wind.speed < 0.2) continue;
        final normalizedLon = ((lon + 180) % 360 + 360) % 360 - 180;
        final projected = camera.projectAtZoom(LatLng(lat, normalizedLon));
        final copy = worldWidth > 0
            ? ((centerX - projected.dx) / worldWidth).round()
            : 0;
        final center = Offset(
          projected.dx + copy * worldWidth - origin.dx,
          projected.dy - origin.dy,
        );
        if (center.dx < -40 ||
            center.dx > size.width + 40 ||
            center.dy < -40 ||
            center.dy > size.height + 40) {
          continue;
        }
        final direction = Offset(wind.east, -wind.north) / wind.speed;
        final length = (wind.speed * 3.2).clamp(14.0, 38.0);
        final phase =
            (animation.value + ((row * 17 + column * 13) % 19) / 19) % 1;
        final head = center + direction * ((phase - 0.5) * length);
        final tail = head - direction * 8;
        paint.color = Color.lerp(
          const Color(0xFF7FE5F0),
          const Color(0xFFFFCE6C),
          (wind.speed / 24).clamp(0.0, 1.0),
        )!.withValues(alpha: 0.32 + 0.55 * math.sin(phase * math.pi));
        canvas.drawLine(tail, head, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GfsWindPainter oldDelegate) =>
      oldDelegate.camera != camera || oldDelegate.grid != grid;
}
