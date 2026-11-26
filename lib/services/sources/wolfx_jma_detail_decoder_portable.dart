import 'dart:convert';
import 'dart:typed_data';

Map<String, dynamic> decodeWolfxJmaDetail(Uint8List bytes) {
  final root = jsonDecode(utf8.decode(bytes));
  if (root is! Map || root['events'] is! List) {
    throw const FormatException('Wolfx JMA detail');
  }
  final reports = <Map<String, dynamic>>[];
  for (final event in root['events'] as List) {
    if (event is! Map ||
        event['eventId'] is! String ||
        (event['eventId'] as String).isEmpty ||
        event['reports'] is! List) {
      continue;
    }
    const ordinaryProducts = ['VXSE53', 'VXSE52', 'VXSE51'];
    final latest = <String, Map>{};
    for (final report in event['reports'] as List) {
      if (report is! Map ||
          report['id'] is! String ||
          (report['id'] as String).isEmpty ||
          !const {
            'issued',
            'corrected',
            'cancelled',
          }.contains(report['status'])) {
        continue;
      }
      final product = report['product'];
      if (product is! String ||
          (product != 'VXSE62' && !ordinaryProducts.contains(product))) {
        continue;
      }
      final previous = latest[product];
      if (previous == null || _compareReports(report, previous) > 0) {
        latest[product] = report;
      }
    }
    final ordinary = ordinaryProducts
        .map((product) => latest[product])
        .nonNulls;
    Map? selected;
    for (final report in ordinary) {
      if (report['status'] != 'cancelled') {
        selected = report;
        break;
      }
      if (selected == null || _compareReports(report, selected) > 0) {
        selected = report;
      }
    }
    for (final report in [?selected, ?latest['VXSE62']]) {
      final observation = report['observation'];
      final areas = observation is Map ? observation['areas'] : null;
      reports.add({
        'eventId': event['eventId'],
        'hypocenter': _indexed(event['hypocenters'], report['hypocenter']),
        'prefectures': [
          if (report['product'] == 'VXSE62' && areas is List)
            for (final area in areas)
              _prefectureName(observation['prefs'], area),
        ],
        'report': report,
      });
    }
  }
  return {'md5': root['md5'], 'reports': reports};
}

int _compareReports(Map left, Map right) {
  DateTime? published(Map report) =>
      DateTime.tryParse('${report['issuedAt'] ?? ''}') ??
      DateTime.tryParse('${report['time'] ?? ''}');
  final a = published(left);
  final b = published(right);
  final timeOrder = a == null
      ? (b == null ? 0 : -1)
      : (b == null ? 1 : a.compareTo(b));
  if (timeOrder != 0) return timeOrder;
  return (left['status'] == 'cancelled' ? 1 : 0) -
      (right['status'] == 'cancelled' ? 1 : 0);
}

Object? _indexed(Object? values, Object? index) =>
    values is List && index is int && index >= 0 && index < values.length
    ? values[index]
    : null;

String _prefectureName(Object? prefs, Object? area) {
  final pref = _indexed(prefs, area is Map ? area['pref'] : null);
  final name = pref is Map ? pref['name'] : null;
  return name is String ? name : '';
}
