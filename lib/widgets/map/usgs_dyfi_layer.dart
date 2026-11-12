import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:latlong2/latlong.dart' show LatLng;
import '../../core/intensity_class.dart';
import '../../core/utils/quake_time.dart';
import '../../core/utils/world_wrap.dart';
import '../../models/usgs_dyfi.dart';
import 'usgs_dyfi_focus.dart';

/// The existing unified-card palette, applied to original CDI values.
Color dyfiColor(double? cdi) =>
    switch (cdi == null ? 'gray' : intensityClassName(cdi)) {
      'purple' => const Color(0xFF7F007F),
      'red' => const Color(0xFFDF0F0F),
      'dark-orange' => const Color(0xFFFF4F00),
      'orange' => const Color(0xFFFF8F00),
      'yellow' => const Color(0xFFF7E757),
      'green' => const Color(0xFF5FDF8F),
      'blue' => const Color(0xFF3FAFFF),
      'sky-blue' => const Color(0xFF5FCFFF),
      'dark-gray' => const Color(0xFF9F9F9F),
      _ => const Color(0xFFCFCFCF),
    };

/// Same operations as MapCamera.latLngToScreenOffset, with the constant center
/// and origin evaluated once per painter instead of twice for every point.
class _DyfiProjection {
  _DyfiProjection(this.camera);
  final MapCamera camera;
  late final center = camera.projectAtZoom(camera.center, camera.zoom);
  late final origin = center - camera.nonRotatedSize.center(Offset.zero);

  Offset project(LatLng position) {
    var point = camera.projectAtZoom(position, camera.zoom);
    if (camera.rotation != 0) {
      point = camera.rotatePoint(center, point, counterRotation: false);
    }
    return point - origin;
  }
}

Path _path(List<List<LatLng>> rings, _DyfiProjection projection) {
  final path = Path()..fillType = PathFillType.evenOdd;
  for (final ring in rings) {
    var reference = projection.camera.center.longitude;
    final points = <Offset>[
      for (final p in ring)
        projection.project(
          LatLng(
            p.latitude,
            reference = WorldWrap.longitudeClosestTo(p.longitude, reference),
          ),
        ),
    ];
    if (points.isNotEmpty) path.addPolygon(points, true);
  }
  return path;
}

/// Project world copies only while drawing; original USGS coordinates remain
/// unchanged and never pass through Polygon's [-180,180] bounds assertion.
class UsgsDyfiGridPainter extends CustomPainter {
  UsgsDyfiGridPainter({required this.frame, required this.camera});
  final UsgsDyfiFrame frame;
  final MapCamera camera;
  late final _projection = _DyfiProjection(camera);
  late final shapes = [
    for (final cell in frame.cells ?? <UsgsDyfiCell>[])
      (cell, _path(cell.rings, _projection)),
  ];
  UsgsDyfiCell? cellAt(Offset p) {
    for (final shape in shapes.reversed) {
      if (shape.$2.contains(p)) return shape.$1;
    }
    return null;
  }

  @override
  bool hitTest(Offset position) => cellAt(position) != null;
  @override
  void paint(Canvas canvas, Size size) {
    final visible = Offset.zero & size;
    canvas.save();
    canvas.clipRect(visible);
    for (final shape in shapes) {
      if (!shape.$2.getBounds().overlaps(visible)) continue;
      canvas.drawPath(
        shape.$2,
        Paint()..color = dyfiColor(shape.$1.cdi).withValues(alpha: .7),
      );
      canvas.drawPath(
        shape.$2,
        Paint()
          ..color = const Color(0xBB172129)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .8,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(UsgsDyfiGridPainter old) =>
      old.frame != frame || old.camera != camera;
}

/// Original rings plus conservative bounds for the offline thumbnail only.
/// Rings spanning a world seam are always projected by the original path code.
class DyfiCountryPolygon {
  DyfiCountryPolygon(this.rings)
    : _bounds = [for (final ring in rings) _ringBounds(ring)];

  final List<List<LatLng>> rings;
  final List<({double west, double east, double south, double north})?> _bounds;

  static ({double west, double east, double south, double north})? _ringBounds(
    List<LatLng> ring,
  ) {
    if (ring.isEmpty) return null;
    var west = ring.first.longitude, east = west;
    var south = ring.first.latitude, north = south;
    for (final point in ring) {
      if (point.longitude < west) west = point.longitude;
      if (point.longitude > east) east = point.longitude;
      if (point.latitude < south) south = point.latitude;
      if (point.latitude > north) north = point.latitude;
    }
    if (east - west >= 180) return null;
    return (west: west, east: east, south: south, north: north);
  }

  bool mayIntersect(MapCamera camera, Rect visible) {
    return _mayIntersect(_DyfiProjection(camera), visible);
  }

  bool _mayIntersect(_DyfiProjection projection, Rect visible) {
    final camera = projection.camera;
    // Mercator is monotone in each axis; rotation is an affine transform, so
    // these four corners enclose the complete projected ring, including holes.
    if (camera.crs is! Epsg3857) return true;
    for (var i = 0; i < rings.length; i++) {
      final bounds = _bounds[i];
      if (bounds == null) return true;
      final first = rings[i].first.longitude;
      final shift =
          WorldWrap.longitudeClosestTo(first, camera.center.longitude) - first;
      final corners = [
        projection.project(LatLng(bounds.south, bounds.west + shift)),
        projection.project(LatLng(bounds.south, bounds.east + shift)),
        projection.project(LatLng(bounds.north, bounds.west + shift)),
        projection.project(LatLng(bounds.north, bounds.east + shift)),
      ];
      var left = corners.first.dx, right = left;
      var top = corners.first.dy, bottom = top;
      for (final point in corners.skip(1)) {
        if (point.dx < left) left = point.dx;
        if (point.dx > right) right = point.dx;
        if (point.dy < top) top = point.dy;
        if (point.dy > bottom) bottom = point.dy;
      }
      // Include the existing stroke and floating-point boundary roundoff.
      if (Rect.fromLTRB(
        left,
        top,
        right,
        bottom,
      ).inflate(2).overlaps(visible)) {
        return true;
      }
    }
    return false;
  }
}

List<DyfiCountryPolygon> parseDyfiCountryPolygons(dynamic json) => [
  for (final feature in json['features'])
    for (final polygon
        in feature['geometry']['type'] == 'Polygon'
            ? [feature['geometry']['coordinates']]
            : feature['geometry']['coordinates'])
      DyfiCountryPolygon([
        for (final ring in polygon)
          [
            for (final point in ring)
              LatLng(
                (point[1] as num).toDouble(),
                (point[0] as num).toDouble(),
              ),
          ],
      ]),
];

class DyfiCountriesPainter extends CustomPainter {
  DyfiCountriesPainter(this.polygons, this.camera);
  final List<DyfiCountryPolygon> polygons;
  final MapCamera camera;
  late final _projection = _DyfiProjection(camera);
  @override
  void paint(Canvas canvas, Size size) {
    final visible = Offset.zero & size;
    canvas.save();
    canvas.clipRect(visible);
    for (final polygon in polygons) {
      if (!polygon._mayIntersect(_projection, visible)) continue;
      final path = _path(polygon.rings, _projection);
      if (!path.getBounds().overlaps(visible)) continue;
      canvas.drawPath(path, Paint()..color = const Color(0xFF303639));
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF68757B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .7,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DyfiCountriesPainter old) =>
      old.polygons != polygons || old.camera != camera;
}

class UsgsDyfiGridLayer extends StatelessWidget {
  const UsgsDyfiGridLayer({
    super.key,
    required this.frame,
    this.interactive = true,
  });
  final UsgsDyfiFrame frame;
  final bool interactive;
  @override
  Widget build(BuildContext context) {
    final painter = UsgsDyfiGridPainter(
      frame: frame,
      camera: MapCamera.of(context),
    );
    final layer = CustomPaint(size: Size.infinite, painter: painter);
    if (!interactive) return IgnorePointer(child: layer);
    return GestureDetector(
      onTapUp: (details) {
        final cell = painter.cellAt(details.localPosition);
        if (cell == null) return;
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('DYFI 体感网格'),
            content: Text(
              'CDI ${cell.cdi}\n收到 ${cell.responses} 份报告\n距震源 ${cell.distance} km',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      },
      child: layer,
    );
  }
}

class UsgsDyfiLayer extends StatelessWidget {
  const UsgsDyfiLayer({super.key, this.frame, this.status});
  final UsgsDyfiFrame? frame;
  final String? status;
  @override
  Widget build(BuildContext context) {
    final data = frame;
    if (data == null && status == null) return const SizedBox.shrink();
    return Stack(
      children: [
        if (data != null) UsgsDyfiGridLayer(frame: data),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18, left: 12, right: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xDD171717),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (data != null) ...[
                    Text(
                      'USGS DYFI · 最高 CDI ${data.product.maxCdiText} · 收到 ${data.product.responses ?? '未知'} 份报告',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    Text(
                      '${data.event.location} · 更新 ${DateFormat('MM-dd HH:mm:ss').format(data.product.updated.toLocal())} (${QuakeTime.systemZoneLabel})',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (data.cells == null)
                      const Text(
                        '本产品尚无体感网格',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    if (data.cells?.isEmpty == true)
                      const Text(
                        '暂无可绘制体感网格',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                  ],
                  if (status != null)
                    Text(
                      status!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Offline thumbnail: packaged country outlines plus the actual DYFI polygons.
/// No per-card tile downloads or additional source polling.
class UsgsDyfiMiniMap extends StatelessWidget {
  const UsgsDyfiMiniMap({super.key, required this.frame});
  final UsgsDyfiFrame frame;
  static Future<List<DyfiCountryPolygon>>? _countries;
  static Future<void> prepareOutlines() async {
    await (_countries ??= _loadCountries());
  }

  static Future<List<DyfiCountryPolygon>> _loadCountries() async {
    final json = jsonDecode(
      await rootBundle.loadString(
        'assets/maps/world_countries.geojson',
        cache: false,
      ),
    );
    return parseDyfiCountryPolygons(json);
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: IgnorePointer(
      child: FlutterMap(
        key: ValueKey('dyfi-mini-${frame.product.identity}'),
        options: MapOptions(
          backgroundColor: const Color(0xFF172129),
          initialCameraFit: DyfiCameraFit(frame: frame),
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.none,
          ),
        ),
        children: [
          FutureBuilder<List<DyfiCountryPolygon>>(
            future: _countries ??= _loadCountries(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              final camera = MapCamera.of(context);
              return CustomPaint(
                size: Size.infinite,
                painter: DyfiCountriesPainter(snapshot.data!, camera),
              );
            },
          ),
          UsgsDyfiGridLayer(frame: frame, interactive: false),
        ],
      ),
    ),
  );
}
