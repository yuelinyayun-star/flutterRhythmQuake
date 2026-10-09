import '../../models/cenc_ir_data.dart';
import '../../models/quake_message.dart';
import 'quake_time.dart';

class CencIrBinding {
  CencIrBinding._();

  static Map<String, dynamic>? find(
    QuakeMessage event,
    List<Map<String, dynamic>> reports,
  ) {
    if (event.source != QuakeSourceType.cenc) return null;
    final matches = reports
        .where((report) => matchesSummary(event, report))
        .toList();
    if (matches.isEmpty) return null;
    matches.sort(
      (a, b) => (b['gmtCreate']?.toString() ?? '').compareTo(
        a['gmtCreate']?.toString() ?? '',
      ),
    );
    return matches.first;
  }

  static bool matchesSummary(QuakeMessage event, Map<String, dynamic> report) {
    if (event.source != QuakeSourceType.cenc) return false;
    final idMatch = [
      report['id'],
      report['reportId'],
      report['uniEventId'],
    ].any((id) => id != null && id.toString() == event.eventId);
    final rawTime =
        (report['oriTime'] ?? report['shockTime'])?.toString() ?? '';
    final time = _instant(rawTime);
    final lat = double.tryParse(report['epiLat']?.toString() ?? '');
    final lon = double.tryParse(report['epiLon']?.toString() ?? '');
    if (time != null &&
        QuakeTime.eventInstantUtc(event).difference(time).inMilliseconds.abs() >
            1000) {
      return false;
    }
    // Catalogue coordinates are rounded to 0.01 degree. Never match by name.
    final coordinatesMatch =
        lat != null &&
        lon != null &&
        (lat - event.latitude).abs() <= 0.011 &&
        (lon - event.longitude).abs() <= 0.011;
    if (lat != null && lon != null && !coordinatesMatch) return false;
    return idMatch || (time != null && coordinatesMatch);
  }

  static bool matchesData(QuakeMessage event, CencIrData data) {
    final time = data.source == CencIrDataSource.nowQuake || data.oriTime.isUtc
        ? data.oriTime.toUtc()
        : QuakeTime.wallClockToUtc(data.oriTime, const Duration(hours: 8));
    return matchesSummary(event, {
      'id': data.reportId,
      'uniEventId': data.uniEventId,
      'oriTime': time.toIso8601String(),
      'epiLat': data.epiLat,
      'epiLon': data.epiLon,
    });
  }

  static DateTime? _instant(String raw) {
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    if (RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false).hasMatch(raw)) {
      return parsed.toUtc();
    }
    return QuakeTime.wallClockToUtc(parsed, const Duration(hours: 8));
  }
}
