import '../../models/quake_message.dart';
import '../../models/unified_quake_data.dart';
import '../../models/whews_catalog.dart';
import 'quake_time.dart';

/// Comparison keys only. Original IDs, timestamps and payloads stay untouched.
String catalogEventId(String source, String id) {
  if (source == 'whews_ingv') {
    // Jian's captured INGV ID uses scientific notation for an integer ID.
    final number = double.tryParse(id);
    if (number != null &&
        number.isFinite &&
        number > 0 &&
        number <= 9007199254740991 &&
        number == number.truncateToDouble()) {
      return number.toStringAsFixed(0);
    }
  }
  return id;
}

String? _observationKey({
  required String source,
  required DateTime? instant,
  required double? lat,
  required double? lng,
  required double magnitude,
  required double depth,
}) {
  if (!unifiedCatalogSources.containsKey(source) ||
      instant == null ||
      lat == null ||
      lng == null ||
      !lat.isFinite ||
      !lng.isFinite ||
      lat.abs() > 90 ||
      lng.abs() > 180 ||
      (lat == 0 && lng == 0) ||
      !magnitude.isFinite ||
      magnitude < 0 ||
      !depth.isFinite ||
      depth < 0) {
    return null;
  }
  // No time/distance tolerance: proximity is not proof of event identity.
  return '$source|observation|${instant.microsecondsSinceEpoch}|'
      '$lat|$lng|$magnitude|$depth';
}

String? catalogObservationKey(UnifiedQuakeData event) => event.isEew
    ? null
    : _observationKey(
        source: event.source,
        instant: event.originTime == null
            ? null
            : QuakeTime.unifiedInstantUtc(event),
        lat: event.lat,
        lng: event.lng,
        magnitude: event.magnitude,
        depth: event.depth,
      );

String? catalogReportKey(UnifiedQuakeData event) {
  final observation = catalogObservationKey(event);
  if (observation == null) return null;
  final intensity =
      double.tryParse(event.maxIntensity)?.toString() ?? event.maxIntensity;
  final text = '${event.titleText} ${event.reportNumText}'.toLowerCase();
  final review =
      text.contains('unverified') ||
          text.contains('automatic') ||
          text.contains('自动') ||
          text.contains('待核实')
      ? 'automatic'
      : text.contains('reviewed') ||
            text.contains('confirmed') ||
            text.contains('正式') ||
            text.contains('已核实')
      ? 'reviewed'
      : '';
  return '$observation|report|$intensity|$review|${event.isCanceled}|'
      '${event.isWarn}|${event.isFinal}|${event.warnArea}';
}

bool sameCatalogHistoryEvent(String bucket, QuakeMessage a, QuakeMessage b) {
  final agency = unifiedCatalogSources[bucket];
  if (agency == null || a.source != agency || b.source != agency) return false;
  final id = catalogEventId(bucket, a.eventId);
  if (id.isNotEmpty && id == catalogEventId(bucket, b.eventId)) return true;
  String? key(QuakeMessage event) => _observationKey(
    source: bucket,
    instant: QuakeTime.eventInstantUtc(event),
    lat: event.latitude,
    lng: event.longitude,
    magnitude: event.magnitude,
    depth: event.depth,
  );
  final first = key(a);
  return first != null && first == key(b);
}
