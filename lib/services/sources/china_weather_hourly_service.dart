import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// Domestic forecast wall-clock values use Beijing time, not the device zone.
const chinaWeatherOffset = Duration(hours: 8);

class ChinaWeatherHour {
  ChinaWeatherHour(this.time, Map<String, dynamic> raw)
    : raw = Map.unmodifiable(raw);

  final DateTime time;
  final Map<String, dynamic> raw;
  String get weatherCode => raw['ja']?.toString() ?? '';
  String get temperature => raw['jb']?.toString() ?? '';
  String get windScaleCode => raw['jc']?.toString() ?? '';
  String get windDirectionCode => raw['jd']?.toString() ?? '';
}

class ChinaWeatherHourlyState {
  const ChinaWeatherHourlyState({
    this.areaId = '',
    this.areaName = '',
    this.hours = const [],
    this.loading = false,
    this.failed = false,
    this.current,
    this.currentLoading = false,
    this.outlook,
  });

  final String areaId;
  final String areaName;
  final List<ChinaWeatherHour> hours;
  final bool loading;
  final bool failed;
  final ChinaWeatherCurrent? current;
  final bool currentLoading;
  final ChinaWeatherOutlook? outlook;
}

class ChinaWeatherCurrent {
  ChinaWeatherCurrent(Map<String, dynamic> raw) : raw = Map.unmodifiable(raw);

  final Map<String, dynamic> raw;
  String get weather => raw['weather']?.toString() ?? '';
  String get weatherCode => raw['weathercode']?.toString() ?? '';
  String get cityName => raw['cityname']?.toString() ?? '';
  String get date => raw['date']?.toString() ?? '';
  String get time => raw['time']?.toString() ?? '';
}

ChinaWeatherCurrent parseChinaWeatherCurrent(String source, String areaId) {
  final raw = chinaWeatherJsonVariable(source, 'dataSK');
  if (raw['city']?.toString() != areaId ||
      raw['weather'] is! String ||
      (raw['weather'] as String).trim().isEmpty) {
    throw const FormatException('Invalid current weather');
  }
  return ChinaWeatherCurrent(raw);
}

// Extract one JSON assignment without executing any remote JavaScript.
Map<String, dynamic> chinaWeatherJsonVariable(String source, String name) {
  final value = chinaWeatherJsonValue(source, name);
  if (value is! Map) throw FormatException('Expected JSON object: $name');
  return Map<String, dynamic>.from(value);
}

Object? chinaWeatherJsonValue(String source, String name) {
  final match = RegExp(
    '(?:^|[;\\s])var\\s+${RegExp.escape(name)}\\s*=\\s*',
  ).firstMatch(source);
  if (match == null ||
      match.end >= source.length ||
      !['{', '['].contains(source[match.end])) {
    throw FormatException('Missing JSON variable: $name');
  }
  var depth = 0;
  var quoted = false;
  var escaped = false;
  for (var i = match.end; i < source.length; i++) {
    final char = source[i];
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        quoted = false;
      }
      continue;
    }
    if (char == '"') quoted = true;
    if (char == '{' || char == '[') depth++;
    if ((char == '}' || char == ']') && --depth == 0) {
      return jsonDecode(source.substring(match.end, i + 1));
    }
  }
  throw const FormatException('Incomplete JSON assignment');
}

List<ChinaWeatherHour> parseChinaWeatherHours(String source) {
  final rows = chinaWeatherJsonVariable(source, 'fc1h_24')['jh'];
  if (rows is! List || rows.isEmpty) {
    throw const FormatException('Missing hourly forecast');
  }
  final result = <ChinaWeatherHour>[];
  for (final row in rows) {
    if (row is! Map) throw const FormatException('Invalid forecast row');
    final raw = Map<String, dynamic>.from(row);
    final stamp = raw['jf']?.toString() ?? '';
    if (!RegExp(r'^\d{12}$').hasMatch(stamp)) {
      throw const FormatException('Invalid forecast timestamp');
    }
    final parts = [
      int.parse(stamp.substring(0, 4)),
      for (var i = 4; i < 12; i += 2) int.parse(stamp.substring(i, i + 2)),
    ];
    final wall = DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4]);
    if (wall.year != parts[0] ||
        wall.month != parts[1] ||
        wall.day != parts[2] ||
        wall.hour != parts[3] ||
        wall.minute != parts[4]) {
      throw const FormatException('Invalid forecast date');
    }
    final instant = wall.subtract(chinaWeatherOffset);
    if (result.isNotEmpty &&
        instant.difference(result.last.time) != const Duration(hours: 1)) {
      throw const FormatException('Forecast is not hourly');
    }
    result.add(ChinaWeatherHour(instant, raw));
  }
  return List.unmodifiable(result);
}

DateTime? _weatherDate(String value) {
  if (!RegExp(r'^\d{8}$').hasMatch(value)) return null;
  final year = int.parse(value.substring(0, 4));
  final month = int.parse(value.substring(4, 6));
  final day = int.parse(value.substring(6));
  final date = DateTime.utc(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}

double? chinaWeatherTemperature(String value) {
  final number = double.tryParse(value);
  return number != null && number.isFinite && number.abs() < 100
      ? number
      : null;
}

class ChinaWeatherDay {
  ChinaWeatherDay(this.date, Map<String, dynamic> raw)
    : raw = Map.unmodifiable(raw);

  // Calendar date in Beijing time, represented without the device timezone.
  final DateTime date;
  final Map<String, dynamic> raw;
  String get high => raw['003']?.toString() ?? '';
  String get low => raw['004']?.toString() ?? '';
  String get dayCode => raw['001']?.toString() ?? '';
  String get nightCode => raw['002']?.toString() ?? '';
  String get sunrise => _clock(raw['014']);
  String get sunset => _clock(raw['015']);

  String _clock(Object? value) {
    final text = value?.toString() ?? '';
    return RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(text) ? text : '';
  }
}

class ChinaWeatherIndex {
  ChinaWeatherIndex(Map<String, dynamic> raw) : raw = Map.unmodifiable(raw);
  final Map<String, dynamic> raw;
  String get code => raw['i1']?.toString() ?? '';
  String get name => raw['i2']?.toString() ?? '';
  String get level => raw['i4']?.toString() ?? '';
  String get description => raw['i5']?.toString() ?? '';
}

class ChinaWeatherOutlook {
  const ChinaWeatherOutlook({
    required this.days,
    required this.indices,
    this.indexDate,
  });
  final List<ChinaWeatherDay> days;
  final List<ChinaWeatherIndex> indices;
  final DateTime? indexDate;

  DateTime _localDay(DateTime instant) {
    final wall = instant.toUtc().add(chinaWeatherOffset);
    return DateTime.utc(wall.year, wall.month, wall.day);
  }

  List<ChinaWeatherDay> upcoming(DateTime now) => days
      .where((day) => !day.date.isBefore(_localDay(now)))
      .take(15)
      .toList(growable: false);

  ChinaWeatherDay? today(DateTime now) {
    for (final day in days) {
      if (day.date == _localDay(now)) return day;
    }
    return null;
  }

  List<ChinaWeatherIndex> todayIndices(DateTime now) =>
      indexDate == _localDay(now) ? indices : const [];
}

ChinaWeatherOutlook parseChinaWeatherOutlook(String source) {
  final rawDays = chinaWeatherJsonValue(source, 'fc40');
  if (rawDays is! List) throw const FormatException('Missing daily forecast');
  final days = <ChinaWeatherDay>[];
  for (final item in rawDays) {
    if (item is! Map) throw const FormatException('Invalid daily forecast');
    final raw = Map<String, dynamic>.from(item);
    final date = _weatherDate(raw['009']?.toString() ?? '');
    if (date == null || (days.isNotEmpty && !date.isAfter(days.last.date))) {
      throw const FormatException('Invalid daily forecast date');
    }
    days.add(ChinaWeatherDay(date, raw));
  }
  final indices = <ChinaWeatherIndex>[];
  DateTime? indexDate;
  try {
    final indexRaw = chinaWeatherJsonVariable(source, 'index3d');
    final stamp = indexRaw['i0']?.toString() ?? '';
    indexDate = stamp.length == 12 ? _weatherDate(stamp.substring(0, 8)) : null;
    if (indexDate != null && indexRaw['i'] is List) {
      for (final raw in indexRaw['i'] as List) {
        if (raw is! Map) continue;
        final item = ChinaWeatherIndex(Map<String, dynamic>.from(raw));
        if (item.code.isNotEmpty && item.level.isNotEmpty) indices.add(item);
      }
    }
  } on FormatException {
    // Daily forecast is still usable when the optional indices are unavailable.
  }
  return ChinaWeatherOutlook(
    days: List.unmodifiable(days),
    indices: List.unmodifiable(indices),
    indexDate: indexDate,
  );
}

class ChinaWeatherHourlyService {
  ChinaWeatherHourlyService({http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _now = now ?? DateTime.now;

  static const refreshInterval = Duration(minutes: 10);
  static const _headers = {'Referer': 'https://m.weather.com.cn/'};
  final http.Client _client;
  final DateTime Function() _now;
  final state = ValueNotifier(const ChinaWeatherHourlyState());
  Timer? _timer;
  (double, double)? _location;
  DateTime? _loadedAt;
  int _generation = 0;
  bool _disposed = false;
  int? _activeRequest;

  Future<void> startForLocation(double lat, double lng) async {
    if (_disposed) return;
    if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180) {
      pause(clear: true);
      return;
    }
    if (_location != (lat, lng)) {
      _generation++;
      _location = (lat, lng);
      _loadedAt = null;
      state.value = const ChinaWeatherHourlyState();
    }
    _timer ??= Timer.periodic(refreshInterval, (_) => unawaited(refresh()));
    if (_loadedAt == null || _now().difference(_loadedAt!) >= refreshInterval) {
      await refresh();
    }
  }

  Future<String> _get(Uri uri) async {
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }
    return utf8.decode(response.bodyBytes);
  }

  Future<void> refresh() async {
    final location = _location;
    final generation = _generation;
    if (_disposed ||
        _timer == null ||
        location == null ||
        _activeRequest == generation) {
      return;
    }
    _activeRequest = generation;
    final previous = state.value;
    state.value = ChinaWeatherHourlyState(
      areaId: previous.areaId,
      areaName: previous.areaName,
      hours: previous.hours,
      loading: true,
      current: previous.current,
      currentLoading: true,
      outlook: previous.outlook,
    );
    bool current() => !_disposed && generation == _generation && _timer != null;
    try {
      var areaId = previous.areaId;
      var areaName = previous.areaName;
      if (areaId.isEmpty) {
        final text = await _get(
          Uri.https('d4.weather.com.cn', '/geong/v1/api', {
            'params': jsonEncode({
              'method': 'stationinfo',
              'lat': location.$1,
              'lng': location.$2,
              'callback': 'getData',
            }),
          }),
        );
        if (!current()) return;
        final match = RegExp(
          r'^\s*getData\((.*)\)\s*;?\s*$',
          dotAll: true,
        ).firstMatch(text);
        if (match == null) {
          throw const FormatException('Invalid station response');
        }
        final payload = jsonDecode(match[1]!);
        if (payload['status'] != 'success') {
          throw const FormatException('Station lookup failed');
        }
        final station = payload['data']['station'];
        areaId = station['areaid']?.toString() ?? '';
        areaName = station['namecn']?.toString() ?? '';
        if (!RegExp(r'^101\d{6}$').hasMatch(areaId) || areaName.isEmpty) {
          throw const FormatException('Unsupported forecast area');
        }
      }
      final text = await _get(
        Uri.https('d1.weather.com.cn', '/wap_40d/$areaId.html'),
      );
      if (!current()) return;
      final hours = parseChinaWeatherHours(text);
      ChinaWeatherOutlook? outlook;
      try {
        outlook = parseChinaWeatherOutlook(text);
      } on FormatException catch (error) {
        debugPrint('[ChinaWeatherOutlook] $error');
      }
      if (!hours.last.time.isAfter(_now().toUtc())) {
        throw const FormatException('Hourly forecast expired');
      }
      _loadedAt = _now();
      state.value = ChinaWeatherHourlyState(
        areaId: areaId,
        areaName: areaName,
        hours: hours,
        currentLoading: true,
        outlook: outlook,
      );
      // The same official page loads dataSK separately from its hourly forecast.
      // A failed observation must not discard the successfully loaded forecast.
      try {
        final currentText = await _get(
          Uri.https('d1.weather.com.cn', '/sk_2d/$areaId.html'),
        );
        if (!current()) return;
        final observation = parseChinaWeatherCurrent(currentText, areaId);
        state.value = ChinaWeatherHourlyState(
          areaId: areaId,
          areaName: areaName,
          hours: hours,
          current: observation,
          outlook: outlook,
        );
      } catch (error) {
        if (!current()) return;
        debugPrint('[ChinaWeatherCurrent] $error');
        state.value = ChinaWeatherHourlyState(
          areaId: areaId,
          areaName: areaName,
          hours: hours,
          outlook: outlook,
        );
      }
    } catch (error) {
      if (!current()) return;
      debugPrint('[ChinaWeatherHourly] $error');
      state.value = ChinaWeatherHourlyState(
        areaId: previous.areaId,
        areaName: previous.areaName,
        hours: previous.hours,
        failed: true,
        outlook: previous.outlook,
      );
    } finally {
      if (_activeRequest == generation) _activeRequest = null;
    }
  }

  void pause({bool clear = false}) {
    _timer?.cancel();
    _timer = null;
    _generation++;
    if (clear && !_disposed) {
      _location = null;
      _loadedAt = null;
      state.value = const ChinaWeatherHourlyState();
    }
  }

  void dispose() {
    _disposed = true;
    pause();
    _client.close();
    state.dispose();
  }
}
