import 'package:latlong2/latlong.dart' show LatLng;
import 'quake_message.dart';
import '../services/native_dyfi_grid.dart';

/// Preferred native DYFI product. CDI is retained in its upstream scale.
class UsgsDyfiProduct {
  const UsgsDyfiProduct({
    required this.eventId,
    required this.source,
    required this.code,
    required this.updated,
    required this.original,
    this.maxCdi,
    this.responses,
    this.gridUrl,
    this.gridKm,
    this.gridFormat = 'geojson',
  });
  final String eventId, source, code;
  final DateTime updated;
  final double? maxCdi;
  final int? responses, gridKm;
  final Uri? gridUrl;
  final String gridFormat;
  final Map<String, dynamic> original;
  String get identity => '$source:$code:${updated.millisecondsSinceEpoch}';

  /// USGS can publish maxmmi=0 with questionnaires but no intensity grid.
  /// Retain that source value; zero is outside the CDI scale shown by the UI.
  String get maxCdiText => maxCdi == null || maxCdi == 0 ? '未知' : '$maxCdi';

  static UsgsDyfiProduct? fromDetail(Map<String, dynamic> detail) {
    final properties = detail['properties'];
    final products = properties is Map ? properties['products'] : null;
    final raw = products is Map ? products['dyfi'] : null;
    if (raw is! List || raw.isEmpty) return null;
    num number(Object? v) => num.tryParse('$v') ?? 0;
    final sorted = raw.whereType<Map>().toList()
      ..sort((a, b) {
        final weight = number(
          b['preferredWeight'],
        ).compareTo(number(a['preferredWeight']));
        return weight != 0
            ? weight
            : number(b['updateTime']).compareTo(number(a['updateTime']));
      });
    if (sorted.isEmpty || sorted.first['status'] != 'UPDATE') return null;
    final product = sorted.first;
    final p = product['properties'], contents = product['contents'];
    final id = detail['id']?.toString() ?? '';
    final ms = int.tryParse('${product['updateTime']}');
    if (p is! Map || contents is! Map || id.isEmpty || ms == null || ms <= 0) {
      throw const FormatException('USGS DYFI product');
    }
    Uri? uri(String name) {
      final content = contents[name];
      final value = content is Map ? Uri.tryParse('${content['url']}') : null;
      return value?.scheme == 'https' && value!.hasAuthority ? value : null;
    }

    final grid = NativeDyfiGrid.select([
      for (final name in [
        'dyfi_geo_10km.geojson',
        'dyfi_geo_1km.geojson',
        'dyfi_geo.kmz',
      ])
        if (uri(name) != null) name,
    ]);
    final max = double.tryParse('${p['maxmmi']}');
    final count = int.tryParse('${p['numResp'] ?? p['num-responses']}');
    if ((max != null && (!max.isFinite || (max != 0 && max < 1) || max > 12)) ||
        (count != null && count < 0)) {
      throw const FormatException('USGS DYFI values');
    }
    return UsgsDyfiProduct(
      eventId: id,
      source: '${product['source'] ?? ''}',
      code: '${product['code'] ?? ''}',
      updated: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
      maxCdi: max,
      responses: count,
      gridUrl: grid['name'] == null ? null : uri(grid['name'] as String),
      gridKm: grid['gridKm'] as int?,
      gridFormat: grid['format'] as String? ?? 'geojson',
      original: Map<String, dynamic>.unmodifiable(
        Map<String, dynamic>.from(product),
      ),
    );
  }

  UsgsDyfiProduct withGridResolution(int? kilometers) => UsgsDyfiProduct(
    eventId: eventId,
    source: source,
    code: code,
    updated: updated,
    original: original,
    maxCdi: maxCdi,
    responses: responses,
    gridUrl: gridUrl,
    gridKm: kilometers,
    gridFormat: gridFormat,
  );
}

class UsgsDyfiCell {
  const UsgsDyfiCell({
    required this.rings,
    required this.cdi,
    required this.responses,
    required this.distance,
    required this.name,
  });
  final List<List<LatLng>> rings;
  final double cdi, distance;
  final int responses;
  final String name;

  static List<UsgsDyfiCell> parse(Map<String, dynamic> json) {
    if (json['type'] != 'FeatureCollection' || json['features'] is! List) {
      throw const FormatException('USGS DYFI FeatureCollection');
    }
    final cells = <UsgsDyfiCell>[];
    for (final feature in json['features']) {
      if (feature is! Map ||
          feature['properties'] is! Map ||
          feature['geometry'] is! Map) {
        throw const FormatException('USGS DYFI feature');
      }
      final p = feature['properties'], g = feature['geometry'];
      final cdi = p['cdi'], responses = p['nresp'], distance = p['dist'];
      if (cdi is! num ||
          !cdi.isFinite ||
          cdi < 1 ||
          cdi > 12 ||
          responses is! int ||
          responses < 0 ||
          distance is! num ||
          !distance.isFinite ||
          distance < 0 ||
          g['type'] != 'Polygon' ||
          g['coordinates'] is! List ||
          (g['coordinates'] as List).isEmpty) {
        throw const FormatException('USGS DYFI grid values');
      }
      final rings = <List<LatLng>>[];
      for (final ring in g['coordinates']) {
        if (ring is! List || ring.length < 3) {
          throw const FormatException('USGS DYFI polygon');
        }
        final points = <LatLng>[];
        for (final point in ring) {
          if (point is! List ||
              point.length < 2 ||
              point[0] is! num ||
              point[1] is! num ||
              !(point[0] as num).isFinite ||
              !(point[1] as num).isFinite ||
              (point[0] as num).abs() > 360 ||
              (point[1] as num).abs() > 90) {
            throw const FormatException('USGS DYFI coordinates');
          }
          points.add(
            LatLng((point[1] as num).toDouble(), (point[0] as num).toDouble()),
          );
        }
        rings.add(List.unmodifiable(points));
      }
      cells.add(
        UsgsDyfiCell(
          rings: List.unmodifiable(rings),
          cdi: cdi.toDouble(),
          responses: responses,
          distance: distance.toDouble(),
          name: '${p['name'] ?? ''}',
        ),
      );
    }
    return List.unmodifiable(cells);
  }
}

class UsgsDyfiFrame {
  const UsgsDyfiFrame({
    required this.event,
    required this.product,
    required this.cells,
  });
  final QuakeMessage event;
  final UsgsDyfiProduct product;

  /// null means the product has no grid file; [] is an actual empty grid.
  final List<UsgsDyfiCell>? cells;
  List<LatLng> get focusPoints => [
    LatLng(event.latitude, event.longitude),
    for (final cell in cells ?? <UsgsDyfiCell>[]) ...cell.rings.first,
  ];
}
