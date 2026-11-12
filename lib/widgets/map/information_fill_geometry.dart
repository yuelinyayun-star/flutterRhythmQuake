import 'package:latlong2/latlong.dart';
import '../../core/utils/topojson_loader.dart';
import '../../models/unified_quake_data.dart';
import '../../services/native_camera_focus.dart';

/// UI packs the exact rendered polygons. Rust owns bounds and source selection.
/// Immutable topology keys keep repeated frames from rescanning polygon vertices.
class InformationFillGeometry {
  InformationFillGeometry(List<TopoJsonRegion> painted) {
    final missing = painted.where((r) => _bounds[r] == null).toList();
    final batch = <({TopoJsonRegion region, List<List<double>> points})>[];
    var batchPoints = 0;
    void flush() {
      if (batch.isEmpty) return;
      final result =
          NativeCameraFocus.prepare({
                'op': 'renderedRegionBounds',
                'regions': [
                  for (var i = 0; i < batch.length; i++)
                    {
                      'name': '$i',
                      'points': [
                        ...?_bounds[batch[i].region],
                        ...batch[i].points,
                      ],
                    },
                ],
              })
              as Map;
      for (var i = 0; i < batch.length; i++) {
        _bounds[batch[i].region] = result['$i'] as List? ?? const [];
      }
      batch.clear();
      batchPoints = 0;
    }

    for (final region in missing) {
      var points = <List<double>>[];
      for (final polygon in region.polygons) {
        if (polygon.length < 3) continue;
        for (final point in polygon) {
          points.add([point.latitude, point.longitude]);
          if (points.length >= 50000) {
            flush();
            batch.add((region: region, points: points));
            flush();
            points = [];
          }
        }
      }
      if (batchPoints + points.length > 50000) flush();
      batch.add((region: region, points: points));
      batchPoints += points.length;
    }
    flush();
    regions = {};
    for (final region in painted) {
      (regions[region.name] ??= []).addAll(_bounds[region]!);
    }
  }
  static final _bounds = Expando<List>();
  late final Map<String, List> regions;

  List<LatLng> forEvent(
    UnifiedQuakeData event, {
    required bool namedRegions,
    required bool representative,
  }) {
    final points =
        NativeCameraFocus.prepare({
              'op': 'informationFillBounds',
              'isEew': event.isEew,
              'regions': regions,
              'warnArea': event.warnArea,
              'namedRegions': namedRegions,
              'representative': representative,
            })
            as List;
    return List.unmodifiable(
      points.map(
        (p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()),
      ),
    );
  }
}
