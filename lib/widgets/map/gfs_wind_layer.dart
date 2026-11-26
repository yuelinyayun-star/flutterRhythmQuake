import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show VertexMode, Vertices;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../services/sources/gfs_wind_service.dart';

class GfsWindLayer extends StatefulWidget {
  const GfsWindLayer({super.key, this.service});

  final GfsWindService? service;

  @override
  State<GfsWindLayer> createState() => _GfsWindLayerState();
}

class _GfsWindLayerState extends State<GfsWindLayer> {
  late final GfsWindService _service;
  late final AppLifecycleListener _lifecycle;
  final _flow = _WindFlow();
  final _clock = Stopwatch();
  Timer? _animation;
  Timer? _debounce;
  Timer? _refresh;
  GfsWindGrid? _grid;
  int _requestId = 0;
  bool _loading = false;
  bool _animationVisible = false;
  _WindBounds? _wanted;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? GfsWindService();
    _lifecycle = AppLifecycleListener(onStateChange: (_) => _syncAnimation());
    _refresh = Timer.periodic(const Duration(minutes: 30), (_) {
      final bounds = _wanted;
      if (bounds != null) _load(bounds, refresh: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationVisible = TickerMode.valuesOf(context).enabled;
    _syncAnimation();
  }

  void _syncAnimation() {
    final state = WidgetsBinding.instance.lifecycleState;
    final visible =
        state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (_grid == null || !_animationVisible || !visible) {
      _animation?.cancel();
      _animation = null;
      _clock.stop();
      return;
    }
    if (_animation != null) return;
    _clock.start();
    _animation = Timer.periodic(const Duration(milliseconds: 40), (_) {
      _flow.tick(_clock.elapsed);
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
      if (mounted && id == _requestId) {
        setState(() => _grid = grid);
        _syncAnimation();
      }
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
    _animation?.cancel();
    _lifecycle.dispose();
    _flow.dispose();
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
          painter: _GfsWindPainter(camera: camera, grid: grid, flow: _flow),
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
    required this.flow,
  }) : super(repaint: flow);

  final MapCamera camera;
  final GfsWindGrid grid;
  final _WindFlow flow;

  @override
  void paint(Canvas canvas, Size size) =>
      flow.paint(canvas, size, camera, grid);

  @override
  bool shouldRepaint(covariant _GfsWindPainter oldDelegate) =>
      oldDelegate.camera != camera || oldDelegate.grid != grid;
}

class _WindFlow extends ChangeNotifier {
  static const _maxParticles = 480;
  static const _trailSamples = 6;
  static const _maxVertices = _maxParticles * (_trailSamples + 1) * 3;
  static const _trailRgb = 0x00F4FBFF;
  final _random = math.Random(381);
  final _particles = List.generate(_maxParticles, (_) => _WindParticle());
  final _positions = Float32List(_maxVertices * 2);
  final _colors = Int32List(_maxVertices);
  final _indices = Uint16List(_maxParticles * _trailSamples * 12);
  final _paint = Paint();
  Duration _frame = Duration.zero;
  Duration _paintedFrame = Duration.zero;
  MapCamera? _camera;
  GfsWindGrid? _grid;

  void tick(Duration elapsed) {
    _frame = elapsed;
    notifyListeners();
  }

  void paint(Canvas canvas, Size size, MapCamera camera, GfsWindGrid grid) {
    if (size.isEmpty) return;
    final previous = _camera;
    final reset = previous?.crs != camera.crs || !identical(grid, _grid);
    final origin = camera.pixelOrigin;
    final scale = camera.getZoomScale(camera.zoom, 0);
    final visible = (origin & size).inflate(24);
    final viewport = Rect.fromPoints(
      visible.topLeft / scale,
      visible.bottomRight / scale,
    );
    final worldWidth = camera.getWorldWidthAtZoom(0);
    final count = (size.width * size.height / 1550).round().clamp(
      36,
      _maxParticles,
    );
    final elapsed = (_frame - _paintedFrame).inMicroseconds;
    final dt = math.min(elapsed / 1000000, 0.08);
    _paintedFrame = _frame;
    _camera = camera;
    _grid = grid;
    if (reset) {
      for (final particle in _particles) {
        particle.remaining = 0;
      }
    }
    var vertexCount = 0;
    var indexCount = 0;
    for (var i = 0; i < count; i++) {
      final particle = _particles[i];
      final head = particle.head;
      // Keep trajectories in zoom-zero world pixels across pan and zoom.
      final worldShift = worldWidth > 0
          ? ((viewport.center.dx - head.dx) / worldWidth).round() * worldWidth
          : 0.0;
      if (worldShift != 0) particle.shift(worldShift);
      if (particle.remaining <= 0 || !viewport.contains(particle.head)) {
        particle.seed(viewport, _random);
      }
      if (dt > 0) {
        final geo = camera.unprojectAtZoom(particle.head, 0);
        final wind = grid.sample(geo.latitude, geo.longitude);
        final speed = wind?.speed ?? 0;
        if (wind == null || speed < 0.2) {
          particle.remaining = 0;
          continue;
        }
        // Visual speed in logical pixels per second. Preserve the contrast
        // between calm and fast flow while bounding motion at high wind speeds.
        final step = math.min(92.0, 7 + speed * 4.2) * dt / (speed * scale);
        particle.advance(
          particle.head + Offset(wind.east, -wind.north) * step,
          dt,
        );
      }
      final segments = particle.segments;
      if (segments == 0 || particle.remaining <= 0) continue;
      final opacity = 192 * math.min(1.0, particle.remaining / 0.24);
      var last = particle.head;
      var point = last;
      for (var age = 0; age <= segments; age++) {
        final next = age < segments ? particle.at(age + 1) : point;
        final dx = last.dx - next.dx;
        final dy = last.dy - next.dy;
        final length = math.sqrt(dx * dx + dy * dy);
        final width = length == 0 ? 0.0 : 1.2 / length;
        final normalX = -dy * width;
        final normalY = dx * width;
        final x = point.dx * scale - origin.dx;
        final y = point.dy * scale - origin.dy;
        final offset = vertexCount * 2;
        _positions[offset] = x - normalX;
        _positions[offset + 1] = y - normalY;
        _positions[offset + 2] = x;
        _positions[offset + 3] = y;
        _positions[offset + 4] = x + normalX;
        _positions[offset + 5] = y + normalY;
        final fade = 1 - age / segments;
        _colors[vertexCount] = _trailRgb;
        _colors[vertexCount + 1] = (opacity * fade).round() << 24 | _trailRgb;
        _colors[vertexCount + 2] = _trailRgb;
        if (age != 0) {
          // Connect the centers and both transparent edges into a single strip.
          for (var side = 0; side < 2; side++) {
            final a = vertexCount - 3 + side;
            final b = vertexCount + side;
            _indices[indexCount++] = a;
            _indices[indexCount++] = b;
            _indices[indexCount++] = a + 1;
            _indices[indexCount++] = a + 1;
            _indices[indexCount++] = b;
            _indices[indexCount++] = b + 1;
          }
        }
        vertexCount += 3;
        last = point;
        point = next;
      }
    }
    if (indexCount == 0) return;
    final vertices = Vertices.raw(
      VertexMode.triangles,
      Float32List.sublistView(_positions, 0, vertexCount * 2),
      colors: Int32List.sublistView(_colors, 0, vertexCount),
      indices: Uint16List.sublistView(_indices, 0, indexCount),
    );
    canvas.drawVertices(vertices, BlendMode.dst, _paint);
    vertices.dispose();
  }
}

class _WindParticle {
  final _points = List.filled(_WindFlow._trailSamples, Offset.zero);
  int _index = 0;
  double _sampleElapsed = 0;
  int segments = 0;
  double remaining = 0;
  Offset head = Offset.zero;

  Offset at(int age) => _points[(_index + 1 - age) % _points.length];

  void seed(Rect viewport, math.Random random) {
    head = Offset(
      viewport.left + random.nextDouble() * viewport.width,
      viewport.top + random.nextDouble() * viewport.height,
    );
    segments = 0;
    _sampleElapsed = 0;
    remaining = 1.4 + random.nextDouble() * 1.8;
  }

  void shift(double dx) {
    head = head.translate(dx, 0);
    for (var age = 0; age < segments; age++) {
      final i = (_index - age) % _points.length;
      _points[i] = _points[i].translate(dx, 0);
    }
  }

  void advance(Offset point, double dt) {
    _sampleElapsed += dt;
    if (segments == 0 || _sampleElapsed >= 0.12) {
      _index = (_index + 1) % _points.length;
      _points[_index] = head;
      segments = math.min(segments + 1, _points.length);
      _sampleElapsed = math.max(0, _sampleElapsed - 0.12);
    }
    head = point;
    remaining -= dt;
  }
}
