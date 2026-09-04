class TyphoonData {
  final String tfid;
  final String name;
  final String enname;
  final bool isActive;
  final String startTime;
  final String endTime;
  final String warnLevel;
  final double? centerLng;
  final double? centerLat;
  final List<dynamic> land;
  final List<TyphoonPoint> points;
  final String ckposition;
  final String jl;

  const TyphoonData({
    required this.tfid,
    required this.name,
    required this.enname,
    required this.isActive,
    required this.startTime,
    required this.endTime,
    required this.warnLevel,
    required this.centerLng,
    required this.centerLat,
    required this.land,
    required this.points,
    required this.ckposition,
    required this.jl,
  });

  String get displayName {
    final cn = name.trim();
    final en = enname.trim();
    if (cn.isEmpty) return en;
    if (en.isEmpty) return cn;
    return '$cn $en';
  }

  TyphoonPoint? get latestPoint {
    for (final point in points.reversed) {
      if (point.hasLocation) return point;
    }
    return null;
  }

  String get signature {
    final latest = latestPoint;
    return [
      tfid,
      isActive ? '1' : '0',
      points.length.toString(),
      latest?.time ?? '',
      latest?.lat?.toStringAsFixed(3) ?? '',
      latest?.lng?.toStringAsFixed(3) ?? '',
      latest?.speedText ?? '',
      latest?.pressureText ?? '',
    ].join('|');
  }

  Map<String, dynamic> toMap() => {
    'tfid': tfid,
    'name': name,
    'enname': enname,
    'isactive': isActive ? '1' : '0',
    'starttime': startTime,
    'endtime': endTime,
    'warnlevel': warnLevel,
    'centerlng': centerLng,
    'centerlat': centerLat,
    'land': land,
    'points': points.map((point) => point.toMap()).toList(growable: false),
    'ckposition': ckposition,
    'jl': jl,
  };

  static TyphoonData? fromMap(Map<dynamic, dynamic> value) =>
      _fromAny(Map<String, dynamic>.from(value));

  static List<TyphoonData> listFromJson(dynamic decoded) {
    if (decoded is Map) {
      if (decoded.containsKey('msg')) return const [];
      final data = decoded['data'] ?? decoded['result'];
      if (data is List) {
        return data.map(_fromAny).whereType<TyphoonData>().toList();
      }
      final one = _fromAny(decoded);
      return one == null ? const [] : [one];
    }
    if (decoded is List) {
      return decoded.map(_fromAny).whereType<TyphoonData>().toList();
    }
    return const [];
  }

  static TyphoonData? _fromAny(dynamic value) {
    if (value is! Map) return null;
    final pointsRaw = value['points'];
    final points = pointsRaw is List
        ? pointsRaw
              .map(TyphoonPoint.fromJson)
              .whereType<TyphoonPoint>()
              .toList()
        : <TyphoonPoint>[];

    return TyphoonData(
      tfid: _clean(value['tfid']),
      name: _clean(value['name']),
      enname: _clean(value['enname']),
      isActive: _clean(value['isactive']) == '1',
      startTime: _clean(value['starttime']),
      endTime: _clean(value['endtime']),
      warnLevel: _clean(value['warnlevel']),
      centerLng: _toDouble(value['centerlng']),
      centerLat: _toDouble(value['centerlat']),
      land: value['land'] is List
          ? List<dynamic>.from(value['land'])
          : const [],
      points: List.unmodifiable(points),
      ckposition: _clean(value['ckposition']),
      jl: _clean(value['jl']),
    );
  }
}

class TyphoonPoint {
  final String time;
  final double? lng;
  final double? lat;
  final String strong;
  final int? power;
  final double? speed;
  final int? pressure;
  final double? movespeed;
  final String movedirection;
  final List<double> radius7;
  final List<double> radius10;
  final List<double> radius12;
  final List<TyphoonForecast> forecast;
  final String ckposition;
  final String jl;

  const TyphoonPoint({
    required this.time,
    required this.lng,
    required this.lat,
    required this.strong,
    required this.power,
    required this.speed,
    required this.pressure,
    required this.movespeed,
    required this.movedirection,
    required this.radius7,
    required this.radius10,
    required this.radius12,
    required this.forecast,
    required this.ckposition,
    required this.jl,
  });

  bool get hasLocation => lat != null && lng != null;
  String get speedText => speed == null ? '' : _formatNumber(speed!);
  String get pressureText => pressure?.toString() ?? '';

  Map<String, dynamic> toMap() => {
    'time': time,
    'lng': lng,
    'lat': lat,
    'strong': strong,
    'power': power,
    'speed': speed,
    'pressure': pressure,
    'movespeed': movespeed,
    'movedirection': movedirection,
    'radius7': radius7.join('|'),
    'radius10': radius10.join('|'),
    'radius12': radius12.join('|'),
    'forecast': forecast.map((item) => item.toMap()).toList(growable: false),
    'ckposition': ckposition,
    'jl': jl,
  };

  static TyphoonPoint? fromJson(dynamic value) {
    if (value is! Map) return null;
    final forecastRaw = value['forecast'];
    final forecast = forecastRaw is List
        ? forecastRaw
              .map(TyphoonForecast.fromJson)
              .whereType<TyphoonForecast>()
              .toList()
        : <TyphoonForecast>[];

    return TyphoonPoint(
      time: _clean(value['time']),
      lng: _toDouble(value['lng']),
      lat: _toDouble(value['lat']),
      strong: _clean(value['strong']),
      power: _toInt(value['power']),
      speed: _toDouble(value['speed']),
      pressure: _toInt(value['pressure']),
      movespeed: _toDouble(value['movespeed']),
      movedirection: _clean(value['movedirection']),
      radius7: List.unmodifiable(_parseRadius(value['radius7'])),
      radius10: List.unmodifiable(_parseRadius(value['radius10'])),
      radius12: List.unmodifiable(_parseRadius(value['radius12'])),
      forecast: List.unmodifiable(forecast),
      ckposition: _clean(value['ckposition']),
      jl: _clean(value['jl']),
    );
  }
}

class TyphoonForecast {
  final String agency;
  final List<TyphoonForecastPoint> points;

  const TyphoonForecast({required this.agency, required this.points});

  Map<String, dynamic> toMap() => {
    'tm': agency,
    'forecastpoints': points
        .map((point) => point.toMap())
        .toList(growable: false),
  };

  static TyphoonForecast? fromJson(dynamic value) {
    if (value is! Map) return null;
    final rawPoints = value['forecastpoints'];
    final points = rawPoints is List
        ? rawPoints
              .map(TyphoonForecastPoint.fromJson)
              .whereType<TyphoonForecastPoint>()
              .toList()
        : <TyphoonForecastPoint>[];
    return TyphoonForecast(
      agency: _clean(value['tm']),
      points: List.unmodifiable(points),
    );
  }
}

class TyphoonForecastPoint {
  final String time;
  final double? lng;
  final double? lat;
  final String strong;
  final int? power;
  final double? speed;
  final int? pressure;

  const TyphoonForecastPoint({
    required this.time,
    required this.lng,
    required this.lat,
    required this.strong,
    required this.power,
    required this.speed,
    required this.pressure,
  });

  bool get hasLocation => lat != null && lng != null;

  Map<String, dynamic> toMap() => {
    'time': time,
    'lng': lng,
    'lat': lat,
    'strong': strong,
    'power': power,
    'speed': speed,
    'pressure': pressure,
  };

  static TyphoonForecastPoint? fromJson(dynamic value) {
    if (value is! Map) return null;
    return TyphoonForecastPoint(
      time: _clean(value['time']),
      lng: _toDouble(value['lng']),
      lat: _toDouble(value['lat']),
      strong: _clean(value['strong']),
      power: _toInt(value['power']),
      speed: _toDouble(value['speed']),
      pressure: _toInt(value['pressure']),
    );
  }
}

String _clean(dynamic value) {
  return (value?.toString() ?? '')
      .replaceAll(RegExp(r'[\u0000-\u001f]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

double? _toDouble(dynamic value) {
  final text = _clean(value);
  if (text.isEmpty) return null;
  return double.tryParse(text);
}

int? _toInt(dynamic value) {
  final number = _toDouble(value);
  if (number == null) return null;
  return number.round();
}

List<double> _parseRadius(dynamic value) {
  final text = _clean(value);
  if (text.isEmpty) return const [];
  return text
      .split('|')
      .map((part) => double.tryParse(part.trim()))
      .whereType<double>()
      .where((radius) => radius > 0)
      .toList();
}

String _formatNumber(double value) {
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toStringAsFixed(1);
}
