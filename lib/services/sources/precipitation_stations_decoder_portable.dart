import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'json_wire_envelope.dart';

Float64List? decodePrecipitationStations(Uint8List bytes, int stamp) {
  if (bytes.length > 512 * 1024) return null;
  final Object? raw;
  try {
    raw = decodeJsonWireEnvelope(
      utf8.decode(bytes),
      JsonWireEnvelope.jsonp,
      'webgisDot',
    );
  } on FormatException {
    return null;
  }
  if (raw is! Map || raw['d3'] != '$stamp') return null;
  final rows = raw['data'];
  if (rows is! List || rows.length > 4096) return null;
  final values = <double>[];
  double? number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value');
  for (final row in rows) {
    if (row is! Map) continue;
    final lon = number(row['x']);
    final lat = number(row['y']);
    final rain = number(row['v']);
    if (lon == null ||
        lat == null ||
        rain == null ||
        !(lon >= 73 &&
            lon <= 136 &&
            lat >= 18 &&
            lat <= 55 &&
            rain >= 0 &&
            rain < 9000)) {
      continue;
    }
    final (latitude, longitude) = _geographic(lon, lat);
    values.addAll([latitude, longitude, rain]);
  }
  return Float64List.fromList(values);
}

(double, double) _geographic(double longitude, double latitude) {
  const pi = math.pi;
  const scale = pi * 3000 / 180;
  final bx = longitude - 0.0065;
  final by = latitude - 0.006;
  final radius = math.sqrt(bx * bx + by * by) - 0.00002 * math.sin(by * scale);
  final angle = math.atan2(by, bx) - 0.000003 * math.cos(bx * scale);
  final lon = radius * math.cos(angle);
  final lat = radius * math.sin(angle);
  final x = lon - 105;
  final y = lat - 35;
  final common =
      (20 * math.sin(6 * x * pi) + 20 * math.sin(2 * x * pi)) * 2 / 3;
  final dy =
      -100 +
      2 * x +
      3 * y +
      0.2 * y * y +
      0.1 * x * y +
      0.2 * math.sqrt(x.abs()) +
      common +
      (20 * math.sin(y * pi) + 40 * math.sin(y * pi / 3)) * 2 / 3 +
      (160 * math.sin(y * pi / 12) + 320 * math.sin(y * pi / 30)) * 2 / 3;
  final dx =
      300 +
      x +
      2 * y +
      0.1 * x * x +
      0.1 * x * y +
      0.1 * math.sqrt(x.abs()) +
      common +
      (20 * math.sin(x * pi) + 40 * math.sin(x * pi / 3)) * 2 / 3 +
      (150 * math.sin(x * pi / 12) + 300 * math.sin(x * pi / 30)) * 2 / 3;
  const eccentricity = 0.006693421622965943;
  const axis = 6378245.0;
  final radians = lat * pi / 180;
  final sine = math.sin(radians);
  final magic = 1 - eccentricity * sine * sine;
  final root = math.sqrt(magic);
  return (
    lat - dy * (180 / pi) * magic * root / (axis * (1 - eccentricity)),
    lon - dx * (180 / pi) * root / (axis * math.cos(radians)),
  );
}
