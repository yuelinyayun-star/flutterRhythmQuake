import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Explicit compatibility on platforms without the Windows Rust backend.
abstract final class NativeDyfiGrid {
  static bool get supported => false;
  static int get outputs => 0;
  static Map<String, dynamic> select(List<String> files) {
    for (final spec in [
      ('dyfi_geo_10km.geojson', 'geojson', 10),
      ('dyfi_geo_1km.geojson', 'geojson', 1),
      ('dyfi_geo.kmz', 'kmz', null),
    ]) {
      if (files.contains(spec.$1)) {
        return {'name': spec.$1, 'format': spec.$2, 'gridKm': spec.$3};
      }
    }
    return {};
  }

  static Future<Map<String, dynamic>> decodeKmz(Uint8List document) async {
    if (document.length > 16 * 1024 * 1024) {
      throw const FormatException('DYFI KMZ too large');
    }
    final archive = ZipDecoder().decodeBytes(document, verify: true);
    final file = archive.files
        .where((f) => f.isFile && f.name.toLowerCase().endsWith('.kml'))
        .firstOrNull;
    if (file == null || file.size > 64 * 1024 * 1024) {
      throw const FormatException('Invalid DYFI KMZ');
    }
    final xml = XmlDocument.parse(utf8.decode(file.content));
    final features = <Map<String, dynamic>>[];
    final resolutions = <int>{};
    for (final place in xml.descendants.whereType<XmlElement>().where(
      (n) => n.name.local == 'Placemark',
    )) {
      final polygons = place.descendants
          .whereType<XmlElement>()
          .where((n) => n.name.local == 'Polygon')
          .toList();
      if (polygons.isEmpty) {
        continue;
      }
      if (polygons.length != 1) {
        throw const FormatException('Unsupported DYFI KML multipolygon');
      }
      String field(String name) => place.descendants
          .whereType<XmlElement>()
          .firstWhere(
            (n) => n.name.local == 'Data' && n.getAttribute('name') == name,
          )
          .childElements
          .firstWhere((n) => n.name.local == 'value')
          .innerText;
      final name = field('id');
      final resolution = int.tryParse(name.replaceAll(')', '').split(' ').last);
      if (resolution != null && resolution > 0 && resolution % 1000 == 0) {
        resolutions.add(resolution ~/ 1000);
      }
      final rings = [
        for (final ring
            in polygons.single.descendants.whereType<XmlElement>().where(
              (n) => n.name.local == 'LinearRing',
            ))
          [
            for (final point
                in ring.childElements
                    .firstWhere((n) => n.name.local == 'coordinates')
                    .innerText
                    .trim()
                    .split(RegExp(r'\s+')))
              [
                double.parse(point.split(',')[0]),
                double.parse(point.split(',')[1]),
              ],
          ],
      ];
      features.add({
        'type': 'Feature',
        'properties': {
          'name': name,
          'cdi': double.parse(field('cdi')),
          'dist': double.parse(field('dist')),
          'nresp': int.parse(field('nresp')),
        },
        'geometry': {'type': 'Polygon', 'coordinates': rings},
      });
    }
    return {
      'geojson': {'type': 'FeatureCollection', 'features': features},
      'gridKm': resolutions.length == 1 ? resolutions.single : null,
    };
  }
}
