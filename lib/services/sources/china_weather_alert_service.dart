import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/calculator.dart';
import '../../models/weather_alarm.dart';

enum ChinaWeatherAdminLevel { province, city, county }

/// Pulls China Weather alerts and emits one best local alert.
///
/// List endpoint:
/// https://forecast.weather.com.cn/api/v1/traffic/alarm/alarmMap
/// Detail endpoint:
/// https://product.weather.com.cn/alarm/webdata/{file}
class ChinaWeatherAlertService {
  static const String _endpoint =
      'https://forecast.weather.com.cn/api/v1/traffic/alarm/alarmMap';
  static const String _detailBase =
      'https://product.weather.com.cn/alarm/webdata/';
  static const Map<String, (double, double)> _provinceCenters = {
    '\u5317\u4eac\u5e02': (39.90, 116.40),
    '\u5929\u6d25\u5e02': (39.13, 117.20),
    '\u4e0a\u6d77\u5e02': (31.23, 121.47),
    '\u91cd\u5e86\u5e02': (29.56, 106.55),
    '\u6cb3\u5317\u7701': (38.04, 114.51),
    '\u5c71\u897f\u7701': (37.87, 112.55),
    '\u8fbd\u5b81\u7701': (41.80, 123.43),
    '\u5409\u6797\u7701': (43.90, 125.32),
    '\u9ed1\u9f99\u6c5f\u7701': (45.75, 126.63),
    '\u6c5f\u82cf\u7701': (32.06, 118.78),
    '\u6d59\u6c5f\u7701': (30.25, 120.17),
    '\u5b89\u5fbd\u7701': (31.86, 117.28),
    '\u798f\u5efa\u7701': (26.08, 119.30),
    '\u6c5f\u897f\u7701': (28.68, 115.85),
    '\u5c71\u4e1c\u7701': (36.65, 117.00),
    '\u6cb3\u5357\u7701': (34.75, 113.62),
    '\u6e56\u5317\u7701': (30.60, 114.30),
    '\u6e56\u5357\u7701': (28.21, 112.98),
    '\u5e7f\u4e1c\u7701': (23.13, 113.27),
    '\u6d77\u5357\u7701': (20.04, 110.20),
    '\u56db\u5ddd\u7701': (30.67, 104.06),
    '\u8d35\u5dde\u7701': (26.58, 106.71),
    '\u4e91\u5357\u7701': (25.04, 102.71),
    '\u9655\u897f\u7701': (34.34, 108.94),
    '\u7518\u8083\u7701': (36.06, 103.82),
    '\u9752\u6d77\u7701': (36.62, 101.78),
    '\u53f0\u6e7e\u7701': (25.03, 121.56),
    '\u5185\u8499\u53e4\u81ea\u6cbb\u533a': (40.82, 111.67),
    '\u5e7f\u897f\u58ee\u65cf\u81ea\u6cbb\u533a': (22.82, 108.32),
    '\u897f\u85cf\u81ea\u6cbb\u533a': (29.65, 91.10),
    '\u5b81\u590f\u56de\u65cf\u81ea\u6cbb\u533a': (38.48, 106.23),
    '\u65b0\u7586\u7ef4\u543e\u5c14\u81ea\u6cbb\u533a': (43.82, 87.62),
    '\u9999\u6e2f\u7279\u522b\u884c\u653f\u533a': (22.28, 114.16),
    '\u6fb3\u95e8\u7279\u522b\u884c\u653f\u533a': (22.19, 113.54),
  };
  static final List<String> _provinceNames = _provinceCenters.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));

  Timer? _timer;
  double _lat = 29.30;
  double _lng = 120.09;
  List<String> _keywords = const [];
  ChinaWeatherAdminLevel _adminLevel = ChinaWeatherAdminLevel.county;
  bool _includeLowerLevels = true;
  String _lastAlarmId = '';
  String? _detectedProvince;

  void Function(WeatherAlarm?)? onLocalAlarmChanged;
  String? get detectedProvince => _detectedProvince;

  void setLocalAnchor(double lat, double lng) {
    _lat = lat;
    _lng = lng;
  }

  void setProvinceKeywords(List<String> keywords) {
    _keywords = keywords
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  void setAdminLevel(ChinaWeatherAdminLevel level) {
    _adminLevel = level;
  }

  void setIncludeLowerLevels(bool value) {
    _includeLowerLevels = value;
  }

  void start({int intervalSeconds = 90}) {
    _timer?.cancel();
    fetchNow();
    _timer = Timer.periodic(Duration(seconds: intervalSeconds), (_) {
      fetchNow();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> fetchNow() async {
    try {
      final resp = await http
          .get(
            Uri.parse(_endpoint),
            headers: const {
              'Referer': 'https://www.weather.com.cn/alarm/index.shtml',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return;

      final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
      final obj = json.decode(body);
      final result = obj is Map ? obj['result'] : null;
      final data = result is Map ? result['data'] : null;
      if (data is! List) return;

      final selected = _pickBestLocalAlarm(data);
      if (selected == null) {
        if (_lastAlarmId.isNotEmpty) {
          _lastAlarmId = '';
          onLocalAlarmChanged?.call(null);
        }
        return;
      }

      final detail = await _fetchAlarmDetail(selected.file);
      final alarm = WeatherAlarm(
        id: selected.id,
        headline: (detail?.head.isNotEmpty ?? false)
            ? detail!.head
            : selected.headline,
        effective: (detail?.issueTime.isNotEmpty ?? false)
            ? detail!.issueTime
            : selected.effective,
        description: (detail?.issueContent.isNotEmpty ?? false)
            ? detail!.issueContent
            : '${selected.area} (China Weather)',
        latitude: selected.lat,
        longitude: selected.lon,
        type: selected.code,
        source: WeatherAlarmSource.chinaWeatherLocal,
      );

      if (_lastAlarmId != alarm.id) {
        _lastAlarmId = alarm.id;
        onLocalAlarmChanged?.call(alarm);
      }
    } catch (_) {}
  }

  _SelectedAlarm? _pickBestLocalAlarm(List rows) {
    final targetProvince = _provinceFromAnchor();
    _detectedProvince = targetProvince;
    final provinceLocked = targetProvince != null;

    // Determine user's city/county from alert data
    String? targetCity;
    if (provinceLocked && _adminLevel != ChinaWeatherAdminLevel.province) {
      final cityCenters = <String, List<double>>{};
      for (final row in rows) {
        if (row is! List || row.length < 7) continue;
        final area = row[0]?.toString() ?? '';
        final areaProvince = _extractProvince(area);
        if (areaProvince != targetProvince) continue;
        // Try city first, fall back to county for county-level cities (e.g. 义乌市)
        final name = _extractCity(area) ?? _extractCounty(area);
        if (name == null) continue;
        final lon = double.tryParse(row[2]?.toString() ?? '');
        final lat = double.tryParse(row[3]?.toString() ?? '');
        if (lon == null || lat == null) continue;
        cityCenters.putIfAbsent(name, () => [0.0, 0.0, 0]);
        final c = cityCenters[name]!;
        c[0] += lat;
        c[1] += lon;
        c[2] += 1;
      }
      var bestCityDist = double.infinity;
      for (final entry in cityCenters.entries) {
        final c = entry.value;
        if (c[2] == 0) continue;
        final avgLat = c[0] / c[2];
        final avgLon = c[1] / c[2];
        final d = QuakeCalculator.haversineDistance(_lat, _lng, avgLat, avgLon);
        if (d < bestCityDist) {
          bestCityDist = d;
          targetCity = entry.key;
        }
      }
      // Nearest city/county center too far → user's location has no alerts
      if (bestCityDist > 60) return null;
    }

    _Candidate? best = _pickAlerts(
      rows,
      targetProvince,
      targetCity,
      provinceLocked,
    );
    return best?.selected;
  }

  _Candidate? _pickAlerts(
    List rows,
    String? targetProvince,
    String? cityFilter,
    bool provinceLocked,
  ) {
    _Candidate? best;
    for (final row in rows) {
      if (row is! List || row.length < 7) continue;
      final area = row[0]?.toString() ?? '';
      final file = row[1]?.toString() ?? '';
      final lon = double.tryParse('${row[2]}');
      final lat = double.tryParse('${row[3]}');
      final id = row[4]?.toString() ?? file;
      final headline = row[6]?.toString() ?? '';
      if (headline.isEmpty) continue;
      final areaProvince = _extractProvince(area);
      if (provinceLocked) {
        if (areaProvince == null || areaProvince != targetProvince) continue;
      }
      // City/county filter: check both levels
      if (cityFilter != null) {
        final areaCity = _extractCity(area);
        final areaCounty = _extractCounty(area);
        if (areaCity != cityFilter && areaCounty != cityFilter) continue;
      }
      if (!_matchAdminLevel(area)) continue;

      final text = '$area $headline';
      final keywordMatched =
          _keywords.isNotEmpty &&
          _keywords.any((k) => k.isNotEmpty && text.contains(k));

      var distance = 99999.0;
      if (lon != null && lat != null) {
        distance = QuakeCalculator.haversineDistance(_lat, _lng, lat, lon);
      }
      final maxDistance = _maxDistanceByLevel();
      if (distance > maxDistance) continue;

      if (!provinceLocked && !keywordMatched && distance > 260) continue;

      final code = _alarmCodeFromFile(file);
      final severity = _severityFromCode(code);
      final effective = _formatEffectiveFromId(id);
      final selected = _SelectedAlarm(
        id: id,
        file: file,
        area: area,
        headline: headline,
        effective: effective,
        lon: lon,
        lat: lat,
        code: code,
      );

      final candidate = _Candidate(
        selected: selected,
        severity: severity,
        distance: distance,
      );
      if (best == null || candidate.isBetterThan(best)) {
        best = candidate;
      }
    }
    return best;
  }

  double _maxDistanceByLevel() {
    switch (_adminLevel) {
      case ChinaWeatherAdminLevel.province:
        return 450;
      case ChinaWeatherAdminLevel.city:
        return 150;
      case ChinaWeatherAdminLevel.county:
        return 60;
    }
  }

  String? _provinceFromAnchor() {
    String? best;
    double bestDist = double.infinity;
    for (final entry in _provinceCenters.entries) {
      final d = QuakeCalculator.haversineDistance(
        _lat,
        _lng,
        entry.value.$1,
        entry.value.$2,
      );
      if (d < bestDist) {
        bestDist = d;
        best = entry.key;
      }
    }
    if (best == null || bestDist > 700) return null;
    return best;
  }

  String? _extractProvince(String areaRaw) {
    final area = areaRaw.replaceAll(RegExp(r'\s+'), '');
    if (area.isEmpty) return null;
    for (final name in _provinceNames) {
      if (area.contains(name)) return name;
    }
    return null;
  }

  /// Extract the city (地级市/州/地区) name from an area string.
  /// E.g. "浙江省丽水市莲都区" → "丽水市", "湖北省恩施土家族苗族自治州" → "恩施土家族苗族自治州"
  /// Returns null for provincial-level areas or direct municipalities.
  String? _extractCity(String areaRaw) {
    final area = areaRaw.replaceAll(RegExp(r'\s+'), '');
    if (area.isEmpty) return null;
    // Remove province prefix
    String rest = area;
    for (final name in _provinceNames) {
      if (rest.startsWith(name)) {
        rest = rest.substring(name.length);
        break;
      }
    }
    // Match city-level suffix: XX市, XX自治州, XX地区, XX盟
    final cityMatch = RegExp(r'^(.+?(?:市|自治州|地区|盟))').firstMatch(rest);
    if (cityMatch != null) return cityMatch.group(1);

    // Direct municipalities (北京市 etc.) don't have a separate city level
    const directs = {'北京市', '天津市', '上海市', '重庆市'};
    if (directs.any((d) => area.startsWith(d))) return area;

    return null;
  }

  /// Extract county/district (区/县/县级市) name from an area string.
  /// E.g. "浙江省丽水市莲都区" → "莲都区", "浙江省金华市义乌市" → "义乌市"
  String? _extractCounty(String areaRaw) {
    final area = areaRaw.replaceAll(RegExp(r'\s+'), '');
    if (area.isEmpty) return null;
    String rest = area;
    for (final name in _provinceNames) {
      if (rest.startsWith(name)) {
        rest = rest.substring(name.length);
        break;
      }
    }
    // Skip the city part
    final cityMatch = RegExp(r'^(.+?(?:市|自治州|地区|盟))').firstMatch(rest);
    if (cityMatch != null) rest = rest.substring(cityMatch.group(1)!.length);
    // Match county suffix: XX区, XX县, XX市, XX旗, XX自治县, XX林区
    final countyMatch = RegExp(r'^(.+?(?:区|县|市|旗|自治县|林区))').firstMatch(rest);
    if (countyMatch != null) return countyMatch.group(1);
    return null;
  }

  Future<_AlarmDetail?> _fetchAlarmDetail(String file) async {
    if (file.isEmpty) return null;
    try {
      final resp = await http
          .get(
            Uri.parse('$_detailBase$file'),
            headers: const {
              'Referer': 'https://www.weather.com.cn/alarm/index.shtml',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;

      final text = utf8.decode(resp.bodyBytes, allowMalformed: true);
      final m = RegExp(
        r'var\s+alarminfo\s*=\s*(\{[\s\S]*?\})\s*;?',
      ).firstMatch(text);
      if (m == null) return null;

      final jsonText = m.group(1);
      if (jsonText == null || jsonText.isEmpty) return null;
      final obj = json.decode(jsonText);
      if (obj is! Map) return null;

      return _AlarmDetail(
        head: obj['head']?.toString() ?? '',
        issueTime: obj['ISSUETIME']?.toString() ?? '',
        issueContent: obj['ISSUECONTENT']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  bool _matchAdminLevel(String area) {
    final level = _classifyAdminLevel(area);
    if (_includeLowerLevels) {
      switch (_adminLevel) {
        case ChinaWeatherAdminLevel.province:
          return true; // 省级包含全部下级
        case ChinaWeatherAdminLevel.city:
          return level != ChinaWeatherAdminLevel.province; // 市级包含市+县
        case ChinaWeatherAdminLevel.county:
          return level == ChinaWeatherAdminLevel.county; // 县级仅县/区
      }
    }
    switch (_adminLevel) {
      case ChinaWeatherAdminLevel.province:
        return level == ChinaWeatherAdminLevel.province;
      case ChinaWeatherAdminLevel.city:
        return level == ChinaWeatherAdminLevel.city;
      case ChinaWeatherAdminLevel.county:
        return level == ChinaWeatherAdminLevel.county;
    }
  }

  ChinaWeatherAdminLevel _classifyAdminLevel(String areaRaw) {
    final area = areaRaw.replaceAll(RegExp(r'\s+'), '');
    if (area.isEmpty) return ChinaWeatherAdminLevel.county;

    const directMunicipalities = {
      '\u5317\u4eac\u5e02', // 北京市
      '\u5929\u6d25\u5e02', // 天津市
      '\u4e0a\u6d77\u5e02', // 上海市
      '\u91cd\u5e86\u5e02', // 重庆市
    };
    if (directMunicipalities.contains(area)) {
      return ChinaWeatherAdminLevel.province;
    }

    final hasCountyToken =
        area.contains('\u53bf') || // 县
        area.contains('\u65d7') || // 旗
        area.contains('\u81ea\u6cbb\u53bf') || // 自治县
        area.contains('\u6797\u533a') || // 林区
        // 只有不是"自治区"/"行政区"/"地区"的"区"才是县级区
        (area.contains('\u533a') && // 区
            !area.contains('\u81ea\u6cbb\u533a') && // !自治区
            !area.contains('\u884c\u653f\u533a') && // !行政区
            !area.contains('\u5730\u533a')); // !地区
    if (hasCountyToken) return ChinaWeatherAdminLevel.county;

    final cityCount = '\u5e02'.allMatches(area).length; // 市
    if (cityCount >= 2) return ChinaWeatherAdminLevel.county;

    final hasCityToken =
        area.contains('\u5e02') || // 市
        area.contains('\u81ea\u6cbb\u5dde') || // 自治州
        area.contains('\u5730\u533a') || // 地区
        area.contains('\u76df'); // 盟
    if (hasCityToken) return ChinaWeatherAdminLevel.city;

    return ChinaWeatherAdminLevel.province;
  }

  String _alarmCodeFromFile(String file) {
    final m = RegExp(r'-(\d{4})\.html$').firstMatch(file);
    if (m != null) return m.group(1)!;
    return '';
  }

  int _severityFromCode(String code) {
    if (code.length < 2) return 0;
    final level = code.substring(code.length - 2);
    switch (level) {
      case '01':
        return 1; // blue
      case '02':
        return 2; // yellow
      case '03':
        return 3; // orange
      case '04':
        return 4; // red
      default:
        return 0;
    }
  }

  String _formatEffectiveFromId(String id) {
    final m = RegExp(r'_(\d{14})$').firstMatch(id);
    if (m == null) return '';
    final t = m.group(1)!;
    return '${t.substring(0, 4)}-${t.substring(4, 6)}-${t.substring(6, 8)} '
        '${t.substring(8, 10)}:${t.substring(10, 12)}:${t.substring(12, 14)}';
  }
}

class _Candidate {
  final _SelectedAlarm selected;
  final int severity;
  final double distance;

  const _Candidate({
    required this.selected,
    required this.severity,
    required this.distance,
  });

  bool isBetterThan(_Candidate other) {
    // 本地预警优先看“离我近”，同距离再看预警级别
    if ((distance - other.distance).abs() > 8) return distance < other.distance;
    if (severity != other.severity) return severity > other.severity;
    return distance < other.distance;
  }
}

class _SelectedAlarm {
  final String id;
  final String file;
  final String area;
  final String headline;
  final String effective;
  final double? lon;
  final double? lat;
  final String code;

  const _SelectedAlarm({
    required this.id,
    required this.file,
    required this.area,
    required this.headline,
    required this.effective,
    required this.lon,
    required this.lat,
    required this.code,
  });
}

class _AlarmDetail {
  final String head;
  final String issueTime;
  final String issueContent;

  const _AlarmDetail({
    required this.head,
    required this.issueTime,
    required this.issueContent,
  });
}
