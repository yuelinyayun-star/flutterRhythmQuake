import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'jian_get_rate_limit.dart';

class GfsWindVector {
  const GfsWindVector(this.east, this.north);

  final double east;
  final double north;

  double get speed => math.sqrt(east * east + north * north);
}

class GfsWindGrid {
  const GfsWindGrid({
    required this.south,
    required this.north,
    required this.west,
    required this.east,
    required this.rows,
    required this.columns,
    required this.time,
    required this.vectors,
  });

  final double south;
  final double north;
  final double west;
  final double east;
  final int rows;
  final int columns;
  final DateTime time;
  final List<GfsWindVector?> vectors;

  bool covers({
    required double south,
    required double north,
    required double west,
    required double east,
  }) {
    if (north > this.north || south < this.south) {
      return false;
    }
    if (this.east - this.west >= 359.9) {
      return true;
    }
    final shiftedWest = _unwrap(west, (this.west + this.east) / 2);
    return shiftedWest >= this.west && shiftedWest + (east - west) <= this.east;
  }

  GfsWindVector? sample(double latitude, double longitude) {
    final lon = _unwrap(longitude, (west + east) / 2);
    if (latitude < south || latitude > north || lon < west || lon > east) {
      return null;
    }
    final x = (lon - west) / (east - west) * (columns - 1);
    final y = (latitude - south) / (north - south) * (rows - 1);
    final x0 = x.floor().clamp(0, columns - 2);
    final y0 = y.floor().clamp(0, rows - 2);
    final a = vectors[y0 * columns + x0];
    final b = vectors[y0 * columns + x0 + 1];
    final c = vectors[(y0 + 1) * columns + x0];
    final d = vectors[(y0 + 1) * columns + x0 + 1];
    if (a == null || b == null || c == null || d == null) {
      return null;
    }
    final tx = x - x0;
    final ty = y - y0;
    return GfsWindVector(
      _interpolate(a.east, b.east, c.east, d.east, tx, ty),
      _interpolate(a.north, b.north, c.north, d.north, tx, ty),
    );
  }

  static double _interpolate(
    double a,
    double b,
    double c,
    double d,
    double x,
    double y,
  ) => (a * (1 - x) + b * x) * (1 - y) + (c * (1 - x) + d * x) * y;

  static double _unwrap(double longitude, double center) =>
      longitude + 360 * ((center - longitude) / 360).round();
}

class GfsWindService {
  GfsWindService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  _JianWindField? _jianCache;
  DateTime? _jianFetchedAt;
  Future<_JianWindField>? _jianPending;

  Future<GfsWindGrid> fetch({
    required double south,
    required double north,
    required double west,
    required double east,
  }) async {
    try {
      return await _fetchOpenMeteo(
        south: south,
        north: north,
        west: west,
        east: east,
      );
    } catch (_) {
      return _fetchJian(south: south, north: north, west: west, east: east);
    }
  }

  Future<GfsWindGrid> _fetchOpenMeteo({
    required double south,
    required double north,
    required double west,
    required double east,
  }) async {
    const rows = 7;
    const columns = 9;
    final latitudes = <String>[];
    final longitudes = <String>[];
    for (var row = 0; row < rows; row++) {
      final lat = south + (north - south) * row / (rows - 1);
      for (var column = 0; column < columns; column++) {
        final lon = west + (east - west) * column / (columns - 1);
        latitudes.add(lat.toStringAsFixed(3));
        longitudes.add(
          (((lon + 180) % 360 + 360) % 360 - 180).toStringAsFixed(3),
        );
      }
    }
    final uri = Uri.https('api.open-meteo.com', '/v1/gfs', {
      'latitude': latitudes.join(','),
      'longitude': longitudes.join(','),
      'current': 'wind_speed_10m,wind_direction_10m',
      'models': 'gfs_global',
      'wind_speed_unit': 'ms',
      'timezone': 'GMT',
    });
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('GFS wind request failed: HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List || decoded.length != rows * columns) {
      throw const FormatException(
        'GFS wind response has an unexpected grid size',
      );
    }
    DateTime? time;
    final vectors = <GfsWindVector?>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic> ||
          item['current'] is! Map<String, dynamic>) {
        throw const FormatException(
          'GFS wind response is missing current values',
        );
      }
      final current = item['current'] as Map<String, dynamic>;
      final speed = current['wind_speed_10m'];
      final direction = current['wind_direction_10m'];
      final timestamp = DateTime.tryParse('${current['time']}Z');
      if (timestamp != null && (time == null || timestamp.isBefore(time))) {
        time = timestamp;
      }
      if (speed is! num ||
          direction is! num ||
          !speed.isFinite ||
          !direction.isFinite ||
          speed < 0) {
        vectors.add(null);
        continue;
      }
      final radians = direction * math.pi / 180;
      // Meteorological directions point to where wind comes from.
      vectors.add(
        GfsWindVector(-speed * math.sin(radians), -speed * math.cos(radians)),
      );
    }
    if (time == null || vectors.every((vector) => vector == null)) {
      throw const FormatException(
        'GFS wind response has no usable observations',
      );
    }
    return GfsWindGrid(
      south: south,
      north: north,
      west: west,
      east: east,
      rows: rows,
      columns: columns,
      time: time,
      vectors: vectors,
    );
  }

  Future<GfsWindGrid> _fetchJian({
    required double south,
    required double north,
    required double west,
    required double east,
  }) async {
    final field = await _loadJianField();
    const rows = 7;
    const columns = 9;
    final vectors = <GfsWindVector?>[];
    for (var row = 0; row < rows; row++) {
      final latitude = south + (north - south) * row / (rows - 1);
      for (var column = 0; column < columns; column++) {
        final longitude = west + (east - west) * column / (columns - 1);
        vectors.add(field.sample(latitude, longitude));
      }
    }
    if (vectors.every((vector) => vector == null)) {
      throw const FormatException('Jian wind grid has no usable vectors');
    }
    return GfsWindGrid(
      south: south,
      north: north,
      west: west,
      east: east,
      rows: rows,
      columns: columns,
      time: field.time,
      vectors: vectors,
    );
  }

  Future<_JianWindField> _loadJianField() async {
    final cached = _jianCache;
    final fetchedAt = _jianFetchedAt;
    final cacheAge = fetchedAt == null
        ? null
        : DateTime.now().difference(fetchedAt);
    if (cached != null &&
        cacheAge != null &&
        !cacheAge.isNegative &&
        cacheAge < const Duration(minutes: 30)) {
      return cached;
    }
    final pending = _jianPending;
    if (pending != null) return pending;
    final request = _requestJianField();
    _jianPending = request;
    try {
      final field = await request;
      _jianCache = field;
      _jianFetchedAt = DateTime.now();
      return field;
    } finally {
      if (identical(_jianPending, request)) _jianPending = null;
    }
  }

  Future<_JianWindField> _requestJianField() async {
    final uri = Uri.https('api.sismotide.top', '/get/wind.php');
    final response = await (_ownsClient
        ? JianGetRateLimit.run(
            () => _client.get(uri).timeout(const Duration(seconds: 20)),
          )
        : _client.get(uri).timeout(const Duration(seconds: 20)));
    if (response.statusCode != 200) {
      throw StateError('Jian wind request failed: HTTP ${response.statusCode}');
    }
    return _JianWindField.parse(jsonDecode(utf8.decode(response.bodyBytes)));
  }

  void close() {
    _jianCache = null;
    _jianFetchedAt = null;
    if (_ownsClient) _client.close();
  }
}

class _JianWindField {
  const _JianWindField({
    required this.time,
    required this.nx,
    required this.ny,
    required this.u,
    required this.v,
  });

  final DateTime time;
  final int nx;
  final int ny;
  final List<dynamic> u;
  final List<dynamic> v;

  static _JianWindField parse(dynamic raw) {
    if (raw is! Map<String, dynamic> ||
        raw['status'] != 'success' ||
        raw['source'] != 'gfs' ||
        raw['level'] != '10m' ||
        raw['data'] is! List) {
      throw const FormatException('Invalid Jian wind response');
    }
    final layers = raw['data'] as List;
    if (layers.length != 2 ||
        layers[0] is! Map<String, dynamic> ||
        layers[1] is! Map<String, dynamic>) {
      throw const FormatException('Invalid Jian wind components');
    }
    final uLayer = layers[0] as Map<String, dynamic>;
    final vLayer = layers[1] as Map<String, dynamic>;
    final uHeader = uLayer['header'];
    final vHeader = vLayer['header'];
    final nx = raw['nx'];
    final ny = raw['ny'];
    final timeText = raw['time'];
    final time = timeText is String
        ? DateTime.tryParse('${timeText.replaceFirst(' ', 'T')}+08:00')
        : null;
    if (uHeader is! Map<String, dynamic> ||
        vHeader is! Map<String, dynamic> ||
        nx is! int ||
        ny is! int ||
        nx != 360 ||
        ny != 181 ||
        uHeader['parameterNumber'] != 2 ||
        vHeader['parameterNumber'] != 3 ||
        uHeader['nx'] != nx ||
        vHeader['nx'] != nx ||
        uHeader['ny'] != ny ||
        vHeader['ny'] != ny ||
        uHeader['lo1'] != 0 ||
        vHeader['lo1'] != 0 ||
        uHeader['la1'] != 90 ||
        vHeader['la1'] != 90 ||
        uHeader['dx'] != 1 ||
        vHeader['dx'] != 1 ||
        uHeader['dy'] != 1 ||
        vHeader['dy'] != 1 ||
        uLayer['data'] is! List ||
        vLayer['data'] is! List ||
        time == null) {
      throw const FormatException('Invalid Jian wind grid metadata');
    }
    final u = uLayer['data'] as List;
    final v = vLayer['data'] as List;
    if (u.length != nx * ny || v.length != nx * ny) {
      throw const FormatException('Incomplete Jian wind grid');
    }
    return _JianWindField(time: time.toUtc(), nx: nx, ny: ny, u: u, v: v);
  }

  GfsWindVector? sample(double latitude, double longitude) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90) {
      return null;
    }
    final wrappedLongitude = (longitude % 360 + 360) % 360;
    final x0 = wrappedLongitude.floor();
    final x1 = (x0 + 1) % nx;
    final y = 90 - latitude;
    final y0 = y.floor().clamp(0, ny - 2);
    final y1 = y0 + 1;
    final indexes = [y0 * nx + x0, y0 * nx + x1, y1 * nx + x0, y1 * nx + x1];
    final components = <num>[];
    for (final index in indexes) {
      final east = u[index];
      final north = v[index];
      if (east is! num || north is! num || !east.isFinite || !north.isFinite) {
        return null;
      }
      components
        ..add(east)
        ..add(north);
    }
    final tx = wrappedLongitude - x0;
    final ty = y - y0;
    return GfsWindVector(
      GfsWindGrid._interpolate(
        components[0].toDouble(),
        components[2].toDouble(),
        components[4].toDouble(),
        components[6].toDouble(),
        tx,
        ty,
      ),
      GfsWindGrid._interpolate(
        components[1].toDouble(),
        components[3].toDouble(),
        components[5].toDouble(),
        components[7].toDouble(),
        tx,
        ty,
      ),
    );
  }
}
