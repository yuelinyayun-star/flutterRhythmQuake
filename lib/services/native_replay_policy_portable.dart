import '../core/utils/quake_time.dart';
import 'quake_event_adapter.dart';

/// Only for platforms without the Windows native backend (including web).
abstract final class NativeReplayPolicy {
  static bool get supported => false;
  static int get calls => 0;
  static int get outputs => 0;
  static dynamic prepare(Map<String, dynamic> request) {
    switch (request['op']) {
      case 'needsHistory':
        return (request['hasStoredReports'] == true &&
                (request['storedSelection'] == true ||
                    request['hasFileReports'] != true)) ||
            request['hasStoredStations'] == true;
      case 'reportInstant':
        final zone = request['timeZone'] as int;
        if (zone < -12 || zone > 14) {
          throw StateError('Invalid replay time zone');
        }
        final reportTime = request['reportTime'] as String?;
        final payload = request['sourcePayload'] as Map<String, dynamic>?;
        final raw = payload == null
            ? null
            : QuakeEventAdapter.savedReportTime(payload, zone);
        final micros = reportTime != null
            ? QuakeTime.wallClockToUtc(
                DateTime.parse(reportTime),
                Duration(hours: zone),
              ).microsecondsSinceEpoch
            : request['storedReportInstant'] as int? ??
                  (raw == null
                      ? null
                      : QuakeTime.wallClockToUtc(
                          raw,
                          Duration(hours: zone),
                        ).microsecondsSinceEpoch);
        return {
          'micros': micros,
          'needsPayload':
              micros == null &&
              request['hasStoredRef'] == true &&
              payload == null,
        };
      default:
        throw StateError('Unknown replay policy operation');
    }
  }
}
