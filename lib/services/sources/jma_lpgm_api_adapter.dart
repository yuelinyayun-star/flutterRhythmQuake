import '../../models/jma_lpgm_bulletin.dart';
import 'jma_lpgm_service.dart';

/// A strictly observed (VXSE62) relay report; never parse predicted EEW LPGM.
class JmaLpgmApiAdapter {
  JmaLpgmApiAdapter._();

  static JmaLpgmBulletin? parse(Map<String, dynamic> raw, String telegram) {
    if (telegram.toUpperCase() != 'VXSE62' || raw['isTraining'] == true) {
      return null;
    }
    for (final key in ['xmlReport', 'xml', 'rawXml']) {
      final value = raw[key];
      if (value is String && value.contains('<Report')) {
        final service = JmaLpgmService();
        try {
          final bulletin = service.parseDetailXml(value);
          // If the supplied original XML is invalid/test material, do not
          // silently reinterpret the same envelope as a live JSON report.
          return bulletin;
        } finally {
          service.dispose();
        }
      }
    }
    final id = _str(raw['EventID'] ?? raw['eventId'] ?? raw['id']);
    if (id.isEmpty) return null;
    final root = _map(raw['observation']) ?? _map(raw['Observation']) ?? raw;
    final type = _str(raw['infoType'] ?? raw['infoTypeName']);
    final cancel =
        raw['cancel'] == true || raw['isCancel'] == true || type.contains('取消');
    final maximum = _integer(
      root['maxLgInt'] ?? root['MaxLgInt'] ?? raw['maxLgInt'],
    );
    final regions = <JmaLpgmRegion>[];
    final stations = <JmaLpgmStation>[];
    final seen = <String>{};
    void visit(Map<String, dynamic> item, String pref, String area) {
      final name = _str(item['name'] ?? item['Name']);
      final code = _str(item['code'] ?? item['Code']);
      final regionClass = _integer(item['maxLgInt'] ?? item['MaxLgInt']);
      final stationClass = _integer(item['lgInt'] ?? item['LgInt']);
      if (regionClass != null &&
          regionClass >= 1 &&
          regionClass <= 4 &&
          name.isNotEmpty &&
          seen.add('area:$code:$name')) {
        regions.add(
          JmaLpgmRegion(
            name: name,
            code: code,
            maxLgInt: regionClass,
            maxInt: _str(item['maxInt'] ?? item['MaxInt']),
          ),
        );
      }
      if (stationClass != null &&
          stationClass >= 1 &&
          stationClass <= 4 &&
          name.isNotEmpty &&
          seen.add('station:$code:$name')) {
        stations.add(
          JmaLpgmStation(
            name: name,
            code: code,
            intensity: _str(item['intensity'] ?? item['Int']),
            lgInt: stationClass,
            sva: _number(item['sva'] ?? item['Sva']),
            lgIntPerPeriod: _periods(
              item['lgIntPerPeriod'] ?? item['LgIntPerPeriod'],
            ),
            svaPerPeriod: _periods(
              item['svaPerPeriod'] ?? item['SvaPerPeriod'],
            ),
            prefecture: _str(item['prefecture']).isNotEmpty
                ? _str(item['prefecture'])
                : pref,
            area: _str(item['area']).isNotEmpty ? _str(item['area']) : area,
          ),
        );
      }
      for (final field in [
        'regions',
        'areas',
        'prefectures',
        'stations',
        'points',
        'intensities',
        'intensityStations',
        'IntensityStation',
        'Area',
        'Pref',
        'Observation',
      ]) {
        final child = item[field];
        final nextPref = field == 'prefectures' || field == 'Pref'
            ? name
            : pref;
        final nextArea = field == 'areas' || field == 'Area' ? name : area;
        if (child is List) {
          for (final value in child) {
            final nested = _map(value);
            if (nested != null) visit(nested, nextPref, nextArea);
          }
        } else {
          final nested = _map(child);
          if (nested != null) visit(nested, nextPref, nextArea);
        }
      }
    }

    visit(root, '', '');
    if (!identical(root, raw)) visit(raw, '', '');
    final derivedMaximum = <int>[
      for (final region in regions) region.maxLgInt,
      for (final station in stations) station.lgInt,
    ];
    final classValue =
        maximum ??
        (derivedMaximum.isEmpty
            ? null
            : derivedMaximum.reduce((a, b) => a > b ? a : b));
    if (!cancel && (classValue == null || classValue < 1 || classValue > 4)) {
      return null;
    }
    return JmaLpgmBulletin(
      eventId: id,
      serial: _integer(raw['serial'] ?? raw['updates']) ?? 1,
      infoType: cancel ? '取消' : type,
      headline: _str(raw['headline']),
      maxInt: _str(root['maxInt'] ?? raw['maxInt']),
      maxLgInt: cancel ? 0 : classValue!,
      lgCategory: _str(root['lgCategory']),
      originTime: _time(raw['originTime'] ?? raw['shockTime']),
      reportTime: _time(raw['reportTime'] ?? raw['createTime']),
      hypocenter: _str(raw['placeName'] ?? raw['hypocenter']),
      latitude: _number(raw['latitude']),
      longitude: _number(raw['longitude']),
      depthKm: _number(raw['depth'] ?? raw['depthKm']),
      magnitude: _number(raw['magnitude']),
      regions: List.unmodifiable(regions),
      stations: List.unmodifiable(stations),
    );
  }

  static Map<String, dynamic>? _map(Object? raw) =>
      raw is Map ? raw.map((key, value) => MapEntry('$key', value)) : null;
  static String _str(Object? raw) => raw?.toString().trim() ?? '';
  static int? _integer(Object? raw) => int.tryParse(_str(raw));
  static double? _number(Object? raw) {
    final v = double.tryParse(_str(raw));
    return v != null && v.isFinite ? v : null;
  }

  static List<JmaLpgmPeriodValue> _periods(Object? raw) {
    if (raw is! List) return const [];
    final out = <JmaLpgmPeriodValue>[];
    for (var index = 0; index < raw.length; index++) {
      final m = _map(raw[index]);
      if (m == null) continue;
      final band = _integer(m['band'] ?? m['PeriodicBand']) ?? index + 1;
      final value = _number(m['value'] ?? m['Value']);
      if (band >= 1 && band <= 7 && value != null) {
        out.add(JmaLpgmPeriodValue(band: band, value: value));
      }
    }
    return out;
  }

  static DateTime? _time(Object? raw) {
    if (raw is num) {
      final ms = raw.abs() > 100000000000 ? raw.toInt() : (raw * 1000).round();
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    }
    final text = _str(raw).replaceAll('/', '-').replaceFirst(' ', 'T');
    if (text.isEmpty) return null;
    final zoned = RegExp(r'(Z|[+-][0-9]{2}:[0-9]{2})$').hasMatch(text);
    return DateTime.tryParse(zoned ? text : '$text+09:00');
  }
}
