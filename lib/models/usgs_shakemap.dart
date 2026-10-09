import 'package:latlong2/latlong.dart';

import 'quake_message.dart';

/// Metadata and bounds supplied by the preferred USGS ShakeMap product.
/// MMI remains in the upstream scale; it is not converted to CSIS.
class UsgsShakeMapProduct {
  const UsgsShakeMapProduct({
    required this.eventId,
    required this.source,
    required this.code,
    required this.updated,
    required this.version,
    this.contoursUrl,
    required this.south,
    required this.north,
    required this.west,
    required this.east,
    this.maxMmi,
  });

  final String eventId, source, code, version;
  final DateTime updated;
  final Uri? contoursUrl;
  final double south, north, west, east;
  final double? maxMmi;
  String get identity => '$source:$code:${updated.millisecondsSinceEpoch}';

  static UsgsShakeMapProduct? fromDetail(Map<String, dynamic> detail) {
    final properties = detail['properties'];
    if (properties is! Map || properties['products'] is! Map) return null;
    final raw = properties['products']['shakemap'];
    if (raw is! List) return null;
    final products = raw.whereType<Map>().toList()
      ..sort((a, b) {
        final weight = _number(
          b['preferredWeight'],
        ).compareTo(_number(a['preferredWeight']));
        return weight != 0
            ? weight
            : _number(b['updateTime']).compareTo(_number(a['updateTime']));
      });
    if (products.isEmpty) return null;
    // A deletion of the preferred product must not revive a superseded map.
    final product = products.first;
    if (product['status'] != 'UPDATE') return null;
    final p = product['properties'];
    final contents = product['contents'];
    if (p is! Map || contents is! Map) return null;
    double? value(String key) => double.tryParse(p[key]?.toString() ?? '');
    final south = value('minimum-latitude');
    final north = value('maximum-latitude');
    final west = value('minimum-longitude');
    final east = value('maximum-longitude');
    final milliseconds = int.tryParse(product['updateTime']?.toString() ?? '');
    Uri? url(String key) {
      final content = contents[key];
      final uri = content is Map
          ? Uri.tryParse(content['url']?.toString() ?? '')
          : null;
      return uri != null && uri.scheme == 'https' && uri.hasAuthority
          ? uri
          : null;
    }

    final eventId = detail['id']?.toString() ?? '';
    if (eventId.isEmpty ||
        milliseconds == null ||
        milliseconds <= 0 ||
        south == null ||
        north == null ||
        west == null ||
        east == null ||
        ![south, north, west, east].every((v) => v.isFinite) ||
        south < -90 ||
        north > 90 ||
        north <= south ||
        east <= west ||
        east - west > 360) {
      return null;
    }
    return UsgsShakeMapProduct(
      eventId: eventId,
      source: product['source']?.toString() ?? '',
      code: product['code']?.toString() ?? '',
      updated: DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true),
      version: p['version']?.toString() ?? '',
      contoursUrl: url('download/cont_mmi.json'),
      south: south,
      north: north,
      west: west,
      east: east,
      maxMmi: value('maxmmi'),
    );
  }

  static num _number(Object? value) =>
      num.tryParse(value?.toString() ?? '') ?? 0;
}

class UsgsShakeMapFrame {
  const UsgsShakeMapFrame({
    required this.event,
    required this.product,
    required this.contours,
  });
  final QuakeMessage event;
  final UsgsShakeMapProduct product;
  final List<UsgsMmiContour> contours;
}

/// Official GeoJSON values, colors, weights and coordinates, without resampling.
class UsgsMmiContour {
  const UsgsMmiContour({
    required this.value,
    required this.colorArgb,
    required this.weight,
    required this.lines,
  });
  final double value, weight;
  final int colorArgb;
  final List<List<LatLng>> lines;

  static List<UsgsMmiContour> parse(Map<String, dynamic> geojson) {
    if (geojson['type'] != 'FeatureCollection' ||
        geojson['features'] is! List) {
      throw const FormatException('USGS MMI FeatureCollection');
    }
    final contours = <UsgsMmiContour>[];
    for (final feature in geojson['features'] as List) {
      if (feature is! Map || feature['type'] != 'Feature') {
        throw const FormatException('USGS MMI feature');
      }
      final properties = feature['properties'];
      final geometry = feature['geometry'];
      if (properties is! Map || geometry is! Map) {
        throw const FormatException('USGS MMI properties/geometry');
      }
      final value = properties['value'];
      final weight = properties['weight'];
      final color = properties['color'];
      if (properties['units'] != 'mmi' ||
          value is! num ||
          !value.isFinite ||
          value < 0 ||
          value > 12 ||
          weight is! num ||
          !weight.isFinite ||
          weight <= 0 ||
          color is! String ||
          !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
        throw const FormatException('USGS MMI style/value');
      }
      final coordinates = geometry['coordinates'];
      final List<dynamic> rawLines;
      if (geometry['type'] == 'MultiLineString' && coordinates is List) {
        rawLines = coordinates;
      } else if (geometry['type'] == 'LineString' && coordinates is List) {
        rawLines = [coordinates];
      } else {
        throw const FormatException('USGS MMI lines');
      }
      final lines = <List<LatLng>>[];
      for (final rawLine in rawLines) {
        if (rawLine is! List || rawLine.length < 2) {
          throw const FormatException('USGS MMI line');
        }
        final points = <LatLng>[];
        for (final point in rawLine) {
          if (point is! List ||
              point.length < 2 ||
              point[0] is! num ||
              point[1] is! num ||
              !(point[0] as num).isFinite ||
              !(point[1] as num).isFinite ||
              (point[0] as num).abs() > 360 ||
              (point[1] as num).abs() > 90) {
            throw const FormatException('USGS MMI coordinate');
          }
          points.add(
            LatLng((point[1] as num).toDouble(), (point[0] as num).toDouble()),
          );
        }
        lines.add(List.unmodifiable(points));
      }
      contours.add(
        UsgsMmiContour(
          value: value.toDouble(),
          weight: weight.toDouble(),
          colorArgb: 0xFF000000 | int.parse(color.substring(1), radix: 16),
          lines: List.unmodifiable(lines),
        ),
      );
    }
    return List.unmodifiable(contours);
  }
}
