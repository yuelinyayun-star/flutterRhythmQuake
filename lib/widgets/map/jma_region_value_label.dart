import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/intensity_calculator.dart';
import '../../core/utils/topojson_loader.dart';
import '../../models/unified_quake_data.dart';

/// Presentation opt-in for the four ordinary JMA information cards. This does
/// not select/merge reports, calculate intensity or participate in camera fit.
bool showJmaInformationRegionValues(UnifiedQuakeData event) =>
    !event.isEew &&
    !event.isJmaLpgm &&
    const {
      '震度速報',
      '震源情報',
      '震源に関する情報',
      '震度・震源情報',
      '震源・震度情報',
      '震度・震源に関する情報',
      '震源・震度に関する情報',
      '各地の震度情報',
      '各地の震度に関する情報',
    }.contains(event.titleText.trim());

/// Match the existing fill's display scale rather than introducing a second
/// intensity model/rounding rule. Explicit CJK fallback also supports 弱/強.
String jmaRegionValueText(double fillValue, {String? className}) =>
    className == 'dark-gray'
    ? '0'
    : IntensityCalculator.getJmaShindoLevel(fillValue, useSymbol: true);

const jmaRegionValueTextStyle = TextStyle(
  fontFamily: 'MPLUSRounded1c',
  fontFamilyFallback: ['WindowsCjkFallback', 'Microsoft YaHei', 'sans-serif'],
  fontSize: 20,
  fontWeight: FontWeight.w900,
  height: 1.1,
  color: Color(0xFFF8FAFC),
);

/// One interior label on the largest component of each immutable topology
/// region. Island components are still painted, but do not duplicate the label.
/// A weak identity cache survives report/style changes without retaining old
/// topology forever. The interior point is resolved lazily by the badge layer,
/// only when its main component is actually painted, and reused on pan/zoom.
class JmaRegionValuePlacement implements PolygonLabelPlacementCalculator {
  JmaRegionValuePlacement._(this.polygonIndex);

  static final _cache = Expando<JmaRegionValuePlacement>();
  static const _interior = PolygonLabelPlacementCalculator.polylabel(
    precision: .002,
  );
  static const _centroid = PolygonLabelPlacementCalculator.centroid();
  final int polygonIndex;
  final List<LatLng> _position = [];

  static JmaRegionValuePlacement forRegion(TopoJsonRegion region) {
    if (_cache[region] case final existing?) return existing;
    var largestArea = -1.0;
    var largestIndex = -1;
    for (var i = 0; i < region.polygons.length; i++) {
      final points = region.polygons[i];
      if (points.length < 3) continue;
      // Translated shoelace area is sufficient for choosing a component for
      // typography in Japan; source geometry/coordinates remain untouched.
      final origin = points.first;
      var area = 0.0;
      for (var j = 0; j < points.length; j++) {
        final a = points[j], b = points[(j + 1) % points.length];
        area +=
            (a.longitude - origin.longitude) * (b.latitude - origin.latitude) -
            (b.longitude - origin.longitude) * (a.latitude - origin.latitude);
      }
      if (area.abs() > largestArea) {
        largestArea = area.abs();
        largestIndex = i;
      }
    }
    return _cache[region] = JmaRegionValuePlacement._(largestIndex);
  }

  @override
  LatLng call(Polygon polygon) {
    if (_position.isEmpty) {
      final center = _centroid(polygon);
      if (_contains(polygon.points, center)) {
        _position.add(center);
      } else {
        // A concave outline can put its area centroid outside. Keep the label
        // near that center, inside the outline, rather than in a distant lobe.
        final inner = _interior(polygon);
        LatLng along(double t) => LatLng(
          center.latitude + (inner.latitude - center.latitude) * t,
          center.longitude + (inner.longitude - center.longitude) * t,
        );
        var outside = 0.0, inside = 1.0;
        for (var step = 0; step < 24; step++) {
          final middle = (outside + inside) / 2;
          if (_contains(polygon.points, along(middle))) {
            inside = middle;
          } else {
            outside = middle;
          }
        }
        _position.add(along(inside + (1 - inside) * .2));
      }
    }
    return _position.single;
  }

  static bool _contains(List<LatLng> ring, LatLng point) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i], b = ring[j];
      if ((a.latitude > point.latitude) != (b.latitude > point.latitude) &&
          point.longitude <
              (b.longitude - a.longitude) *
                      (point.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude) {
        inside = !inside;
      }
    }
    return inside;
  }
}
