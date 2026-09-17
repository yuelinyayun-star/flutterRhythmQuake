import 'dart:convert';

import '../../models/quake_message.dart';
import '../../models/unified_quake_data.dart';
import '../../models/whews_catalog.dart';
import 'quake_time.dart';

/// Comparison keys only. Original IDs, timestamps and payloads stay untouched.
String catalogEventId(String source, String id) {
  if (source == 'whews_gsras' && RegExp(r'^gsras_\d{8}$').hasMatch(id)) {
    return id.substring('gsras_'.length);
  }
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
  final review = _catalogReview(event);
  return '$observation|report|$intensity|$review|${event.isCanceled}|'
      '${event.isWarn}|${event.isFinal}|${event.warnArea}';
}

String _catalogReview(UnifiedQuakeData event) {
  final text = '${event.titleText} ${event.reportNumText}'.toLowerCase();
  return text.contains('unverified') ||
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
}

const _gaReportPrefix = 'whews_ga|cross-api-v1|';

bool _gaTransportId(String id, String api) => switch (api) {
  'WHEWS' => RegExp(r'^ga\d{4}[a-z]+$').hasMatch(id),
  'Jian Project' => RegExp(
    r'^ga_\d{4}-\d{2}-\d{2}_\d{2}:\d{2}:\d{2}_-?\d+(?:\.\d+)?_-?\d+(?:\.\d+)?$',
  ).hasMatch(id),
  _ => false,
};

String? _gaObservation({
  required DateTime? instant,
  required double? lat,
  required double? lng,
  required double magnitude,
  required double depth,
}) {
  if (_observationKey(
        source: 'whews_ga',
        instant: instant,
        lat: lat,
        lng: lng,
        magnitude: magnitude,
        depth: depth,
      ) ==
      null) {
    return null;
  }
  // The captured Jian GA feed exposes 3-decimal coordinates and integer km.
  // This projection is only for cross-transport comparison, never raw storage.
  return '${instant!.microsecondsSinceEpoch}|${lat!.toStringAsFixed(3)}|'
      '${lng!.toStringAsFixed(3)}|$magnitude|${depth.round()}';
}

Map<String, dynamic>? _gaReport(UnifiedQuakeData event) {
  if (event.source != 'whews_ga' ||
      event.isEew ||
      !_gaTransportId(event.eventId, event.apiTypeLabel)) {
    return null;
  }
  final observation = _gaObservation(
    instant: event.originTime == null
        ? null
        : QuakeTime.unifiedInstantUtc(event),
    lat: event.lat,
    lng: event.lng,
    magnitude: event.magnitude,
    depth: event.depth,
  );
  if (observation == null) return null;
  return {
    'observation': observation,
    'identity': event.eventId,
    'exact': catalogReportKey(event),
    'id': event.eventId,
    'api': event.apiTypeLabel,
    'review': _catalogReview(event),
    'state': jsonEncode([
      double.tryParse(event.maxIntensity)?.toString() ?? event.maxIntensity,
      event.isCanceled,
      event.isWarn,
      event.isFinal,
      event.warnArea,
    ]),
  };
}

/// GA comparison identity is separate from the upstream ID carried by the event.
String catalogCanonicalEventId(
  UnifiedQuakeData event,
  Map<String, DateTime> seen,
) {
  final incoming = _gaReport(event);
  if (incoming == null) return catalogEventId(event.source, event.eventId);
  Map<String, dynamic>? first;
  DateTime? firstSeen;
  for (final entry in seen.entries) {
    if (!entry.key.startsWith(_gaReportPrefix)) continue;
    dynamic old;
    try {
      old = jsonDecode(entry.key.substring(_gaReportPrefix.length));
    } on FormatException {
      continue;
    }
    if (old is! Map || old['identity'] is! String) {
      continue;
    }
    final sameTransportId = old['id'] == incoming['id'] &&
        old['api'] == incoming['api'];
    final provenCrossApi = old['api'] != incoming['api'] &&
        old['observation'] == incoming['observation'];
    if (!sameTransportId && !provenCrossApi) continue;
    if (firstSeen == null || entry.value.isBefore(firstSeen)) {
      first = Map<String, dynamic>.from(old);
      firstSeen = entry.value;
    }
  }
  return 'ga-cross-api|${first?['identity'] ?? incoming['identity']}';
}

/// Stored in the existing bounded/expiring seen-report cache on both platforms.
Iterable<String> catalogReportKeys(
  UnifiedQuakeData event, [
  Map<String, DateTime> seen = const {},
]) sync* {
  final exact = catalogReportKey(event);
  if (exact != null) yield exact;
  final ga = _gaReport(event);
  if (ga != null) {
    ga['identity'] = catalogCanonicalEventId(
      event,
      seen,
    ).substring('ga-cross-api|'.length);
    yield '$_gaReportPrefix${jsonEncode(ga)}';
  }
}

bool hasSeenCatalogReport(UnifiedQuakeData event, Map<String, DateTime> seen) {
  final exact = catalogReportKey(event);
  if (exact != null && seen.containsKey(exact)) return true;
  final incoming = _gaReport(event);
  if (incoming == null) return false;
  var crossApiMatch = false;
  for (final key in seen.keys) {
    if (!key.startsWith(_gaReportPrefix)) continue;
    dynamic old;
    try {
      old = jsonDecode(key.substring(_gaReportPrefix.length));
    } on FormatException {
      continue;
    }
    if (old is! Map) continue;
    // A changed report from a previously seen transport is a real revision,
    // not permission to hide it behind the other transport's lower precision.
    if (old['api'] == incoming['api'] &&
        old['id'] == incoming['id'] &&
        old['exact'] != incoming['exact']) {
      return false;
    }
    if (old['api'] == incoming['api'] ||
        old['observation'] != incoming['observation'] ||
        old['state'] != incoming['state']) {
      continue;
    }
    final review = incoming['review'];
    if (old['review'] == review || old['review'] == '' || review == '') {
      crossApiMatch = true;
    }
  }
  return crossApiMatch;
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
  if (first != null && first == key(b)) return true;
  if (bucket != 'whews_ga' ||
      a.apiTypeLabel == b.apiTypeLabel ||
      !_gaTransportId(a.eventId, a.apiTypeLabel ?? '') ||
      !_gaTransportId(b.eventId, b.apiTypeLabel ?? '')) {
    return false;
  }
  String? gaKey(QuakeMessage event) => _gaObservation(
    instant: QuakeTime.eventInstantUtc(event),
    lat: event.latitude,
    lng: event.longitude,
    magnitude: event.magnitude,
    depth: event.depth,
  );
  final ga = gaKey(a);
  return ga != null && ga == gaKey(b);
}
