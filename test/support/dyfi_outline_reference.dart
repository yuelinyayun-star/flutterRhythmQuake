import 'dart:ui';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:flutterrhythmquake/core/utils/world_wrap.dart';

// Frozen drawing algorithm from before the 2026-10-11 DYFI optimization.
List<List<List<LatLng>>> referenceCountries(dynamic json) {
  final polygons = <List<List<LatLng>>>[];
  for (final f in json['features']) {
    final g = f['geometry'];
    final groups = g['type'] == 'Polygon'
        ? [g['coordinates']]
        : g['coordinates'];
    for (final polygon in groups) {
      polygons.add([
        for (final ring in polygon)
          [
            for (final p in ring)
              LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()),
          ],
      ]);
    }
  }
  return polygons;
}

Path referenceDyfiPath(List<List<LatLng>> rings, MapCamera camera) {
  final path = Path()..fillType = PathFillType.evenOdd;
  for (final ring in rings) {
    var reference = camera.center.longitude;
    final wrapped = [
      for (final p in ring)
        LatLng(
          p.latitude,
          reference = WorldWrap.longitudeClosestTo(p.longitude, reference),
        ),
    ];
    final points = wrapped.map(camera.latLngToScreenOffset).toList();
    if (points.isNotEmpty) path.addPolygon(points, true);
  }
  return path;
}

void paintReferenceCountries(
  Canvas canvas,
  Size size,
  List<List<List<LatLng>>> polygons,
  MapCamera camera,
) {
  final visible = Offset.zero & size;
  canvas.save();
  canvas.clipRect(visible);
  for (final polygon in polygons) {
    final path = referenceDyfiPath(polygon, camera);
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
