import 'dart:convert';

import '../../models/quake_message.dart';
import '../../models/unified_quake_data.dart';
import '../../models/whews_catalog.dart';
import 'quake_time.dart';

/// Agency identity only; transports and unrelated agencies never share a slot.
String? internationalCatalogSource(String source) {
  if (unifiedCatalogSources.containsKey(source)) return source;
  return switch (source) {
    'usgsEqlist' => 'usgsEqlist',
    'kmaEqlist' => 'kmaEqlist',
    'emsc' || 'emscEqlist' => 'emsc',
    'hko' || 'hkoEqlist' => 'hko',
    'bcsf' || 'bcsfEqlist' => 'bcsf',
    'gfz' || 'gfzEqlist' => 'gfz',
    'usp' || 'uspEqlist' => 'usp',
    'geonet' => 'whews_geonet',
    _ => null,
  };
}

const _internationalIdentityPrefix = 'catalog|agency-identity-v1|';

String? _internationalObservation({
  required String source,
  required DateTime? instant,
  required double? lat,
  required double? lng,
  required double depth,
}) {
  final agency = internationalCatalogSource(source);
  if (agency == null ||
      instant == null ||
      lat == null ||
      lng == null ||
      !lat.isFinite ||
      !lng.isFinite ||
      lat.abs() > 90 ||
      lng.abs() > 180 ||
      (lat == 0 && lng == 0) ||
      !depth.isFinite ||
      depth < 0) {
    return null;
  }
  // Comparison precision, not edits to the data: GeoNet transports differ in
  // milliseconds/decimal km; captured Jian GA uses integer km and 3 decimals.
  final depthKey = agency == 'whews_ga'
      ? depth.round().toString()
      : depth.toStringAsFixed(1);
  return '$agency|${instant.millisecondsSinceEpoch ~/ 1000}|'
      '${lat.toStringAsFixed(3)}|${lng.toStringAsFixed(3)}|$depthKey';
}

Map<String, dynamic>? _internationalIdentity(UnifiedQuakeData event) {
  if (event.isEew || event.isReplay || event.isVolcanoEvent) return null;
  final observation = _internationalObservation(
    source: event.source,
    instant: event.originTime == null
        ? null
        : QuakeTime.unifiedInstantUtc(event),
    lat: event.lat,
    lng: event.lng,
    depth: event.depth,
  );
  if (observation == null) return null;
  return {
    'source': internationalCatalogSource(event.source),
    'id': catalogEventId(event.source, event.eventId),
    'api': '${event.origin}|${event.apiTypeLabel}',
    'observation': observation,
  };
}

Map<String, dynamic>? _internationalIdentityFromKey(String key, String source) {
  final prefix = '$_internationalIdentityPrefix$source|';
  if (!key.startsWith(prefix)) return null;
  try {
    final value = jsonDecode(key.substring(prefix.length));
    return value is Map ? Map<String, dynamic>.from(value) : null;
  } on FormatException {
    return null;
  }
}

String _internationalCanonicalEventId(
  UnifiedQuakeData event,
  Map<String, DateTime> seen,
) {
  final incoming = _internationalIdentity(event);
  if (incoming != null) {
    String? observationMatch;
    for (final key in seen.keys) {
      final known = _internationalIdentityFromKey(
        key,
        incoming['source'] as String,
      );
      if (known == null ||
          known['source'] != incoming['source'] ||
          known['identity'] is! String) {
        continue;
      }
      if (incoming['id'] != '' &&
          catalogEventId(event.source, known['id'] as String? ?? '') ==
              incoming['id'] &&
          (known['api'] == incoming['api'] || event.source == 'earlyEst')) {
        return catalogEventId(event.source, known['identity'] as String);
      }
      if (known['observation'] == incoming['observation']) {
        observationMatch ??= known['identity'] as String;
      }
    }
    if (observationMatch != null) return observationMatch;
    if (incoming['id'] == '') return incoming['observation'] as String;
  }
  return catalogEventId(event.source, event.eventId);
}

String? _internationalReportKey(
  UnifiedQuakeData event,
  Map<String, DateTime> seen,
) {
  if (_internationalIdentity(event) == null || !event.magnitude.isFinite) {
    return null;
  }
  final state = [
    internationalCatalogSource(event.source),
    catalogCanonicalEventId(event, seen),
    QuakeTime.unifiedInstantUtc(event).microsecondsSinceEpoch,
    event.lat,
    event.lng,
    event.depth,
    event.magnitude,
    double.tryParse(event.maxIntensity)?.toString() ?? event.maxIntensity,
    _catalogReview(event),
    event.isCanceled,
    event.isWarn,
    event.isFinal,
    event.warnArea,
  ];
  return 'catalog|agency-report-v1|${jsonEncode(state)}';
}

/// Comparison keys only. Original IDs, timestamps and payloads stay untouched.
String catalogEventId(String source, String id) {
  // Captured Jian CENC history appends _M to the original CD/CC bulletin ID.
  // Its minute-only origin cannot establish identity against the full clock.
  if (source == 'cencEqlist' &&
      RegExp(r'^C[CD]\.\d{14}\.\d+_M$').hasMatch(id)) {
    return id.substring(0, id.length - 2);
  }
  // Captured Early-est: Jian adds EARLY_event_ to WHEWS's same upstream ID.
  // Compare that stable ID even when later reports revise the hypocenter.
  if (source == 'earlyEst' && RegExp(r'^EARLY_event_\d{13}$').hasMatch(id)) {
    return id.substring('EARLY_event_'.length);
  }
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

String? _cencObservationKey({
  required DateTime? instant,
  required double? lat,
  required double? lng,
}) {
  if (instant == null ||
      lat == null ||
      lng == null ||
      !lat.isFinite ||
      !lng.isFinite ||
      lat.abs() > 90 ||
      lng.abs() > 180 ||
      (lat == 0 && lng == 0)) {
    return null;
  }
  return 'cencEqlist|observation|${instant.microsecondsSinceEpoch}|$lat|$lng';
}

String? _cencReportKey(UnifiedQuakeData event) {
  if (event.source != 'cencEqlist' || event.isEew) return null;
  final observation = _cencObservationKey(
    instant: event.originTime == null
        ? null
        : QuakeTime.unifiedInstantUtc(event),
    lat: event.lat,
    lng: event.lng,
  );
  if (observation == null ||
      !event.magnitude.isFinite ||
      event.magnitude < 0 ||
      !event.depth.isFinite ||
      event.depth < 0) {
    return null;
  }
  // API-specific estimated intensity and publication time are not bulletin identity.
  return '$observation|report|${event.magnitude}|${event.depth}|'
      '${_catalogReview(event)}|${event.isCanceled}';
}

String? catalogObservationKey(UnifiedQuakeData event) => event.isEew
    ? null
    : event.source == 'cencEqlist'
    ? _cencObservationKey(
        instant: event.originTime == null
            ? null
            : QuakeTime.unifiedInstantUtc(event),
        lat: event.lat,
        lng: event.lng,
      )
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
  if (event.source == 'cencEqlist') return _cencReportKey(event);
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
const _cencIdentityPrefix = 'cencEqlist|identity-v1|';

Map<String, dynamic>? _cencIdentityFromKey(String key) {
  if (!key.startsWith(_cencIdentityPrefix)) return null;
  try {
    final value = jsonDecode(key.substring(_cencIdentityPrefix.length));
    return value is Map ? Map<String, dynamic>.from(value) : null;
  } on FormatException {
    return null;
  }
}

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
  if (event.source == 'cencEqlist' && !event.isEew) {
    final observation = catalogObservationKey(event);
    if (observation != null) {
      String? matchingObservation;
      for (final key in seen.keys) {
        final known = _cencIdentityFromKey(key);
        if (known == null || known['identity'] is! String) continue;
        if (known['id'] == event.eventId &&
            known['api'] == event.apiTypeLabel) {
          return known['identity'] as String;
        }
        if (known['observation'] == observation) {
          matchingObservation ??= known['identity'] as String;
        }
      }
      return matchingObservation ?? observation;
    }
  }
  final incoming = _gaReport(event);
  if (incoming == null) return _internationalCanonicalEventId(event, seen);
  final agencyIdentity = _internationalCanonicalEventId(event, seen);
  if (agencyIdentity != catalogEventId(event.source, event.eventId)) {
    return agencyIdentity;
  }
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
    final sameTransportId =
        old['id'] == incoming['id'] && old['api'] == incoming['api'];
    final provenCrossApi =
        old['api'] != incoming['api'] &&
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
  final identity = _internationalIdentity(event);
  if (identity != null) {
    identity['identity'] = catalogCanonicalEventId(event, seen);
    yield '$_internationalIdentityPrefix${identity['source']}|${jsonEncode(identity)}';
    final report = _internationalReportKey(event, seen);
    if (report != null) yield report;
  }
  final exact = catalogReportKey(event);
  if (exact != null) yield exact;
  if (event.source == 'cencEqlist' && !event.isEew) {
    final observation = catalogObservationKey(event);
    if (observation != null && event.eventId.trim().isNotEmpty) {
      yield '$_cencIdentityPrefix${jsonEncode({'id': event.eventId, 'api': event.apiTypeLabel, 'observation': observation, 'identity': catalogCanonicalEventId(event, seen)})}';
    }
  }
  final ga = _gaReport(event);
  if (ga != null) {
    final identity = catalogCanonicalEventId(event, seen);
    ga['identity'] = identity.startsWith('ga-cross-api|')
        ? identity.substring('ga-cross-api|'.length)
        : identity;
    yield '$_gaReportPrefix${jsonEncode(ga)}';
  }
}

bool hasSeenCatalogReport(UnifiedQuakeData event, Map<String, DateTime> seen) {
  final international = _internationalReportKey(event, seen);
  if (international != null && seen.containsKey(international)) return true;
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
  if (bucket == 'cencEqlist' &&
      a.source == QuakeSourceType.cenc &&
      b.source == QuakeSourceType.cenc) {
    final firstId = catalogEventId(bucket, a.eventId);
    if (firstId.isNotEmpty && firstId == catalogEventId(bucket, b.eventId)) {
      return true;
    }
    String? key(QuakeMessage event) => _cencObservationKey(
      instant: QuakeTime.eventInstantUtc(event),
      lat: event.latitude,
      lng: event.longitude,
    );
    final first = key(a);
    return first != null && first == key(b);
  }
  final agency =
      unifiedCatalogSources[bucket] ??
      switch (bucket) {
        'usgsEqlist' => QuakeSourceType.usgs,
        'emscEqlist' => QuakeSourceType.emsc,
        'kmaEqlist' => QuakeSourceType.kma_eq,
        _ => null,
      };
  if (agency == null || a.source != agency || b.source != agency) return false;
  final id = catalogEventId(bucket, a.eventId);
  if (id.isNotEmpty && id == catalogEventId(bucket, b.eventId)) return true;
  String? observation(QuakeMessage event) => _internationalObservation(
    source: bucket,
    instant: QuakeTime.eventInstantUtc(event),
    lat: event.latitude,
    lng: event.longitude,
    depth: event.depth,
  );
  final firstObservation = observation(a);
  if (firstObservation != null && firstObservation == observation(b)) {
    return true;
  }
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

/// Prefer the captured full-second CENC bulletin over Jian's minute-only copy.
/// Apply only to the same native bulletin and otherwise equal source elements;
/// no timestamps, IDs or source intensity estimates are rewritten.
int? compareCencHistoryOriginPrecision(
  QuakeMessage current,
  QuakeMessage incoming,
) {
  if (current.source != QuakeSourceType.cenc ||
      incoming.source != QuakeSourceType.cenc ||
      current.magnitude != incoming.magnitude ||
      current.depth != incoming.depth ||
      current.latitude != incoming.latitude ||
      current.longitude != incoming.longitude) {
    return null;
  }
  final id = catalogEventId('cencEqlist', current.eventId);
  if (!RegExp(r'^C[CD]\.\d{14}\.\d+$').hasMatch(id) ||
      id != catalogEventId('cencEqlist', incoming.eventId)) {
    return null;
  }
  String review(QuakeMessage e) {
    final value = '${e.reviewType} ${e.infoTypeName}'.toLowerCase();
    if (value.contains('正式') || value.contains('reviewed')) return 'reviewed';
    if (value.contains('自动') || value.contains('automatic')) return 'automatic';
    return '';
  }

  if (review(current) != review(incoming)) return null;
  bool minuteCopy(QuakeMessage e) =>
      e.apiTypeLabel == 'Jian Project' &&
      e.eventId.endsWith('_M') &&
      e.originTime.second == 0 &&
      e.originTime.millisecond == 0 &&
      e.originTime.microsecond == 0;
  final a = QuakeTime.eventInstantUtc(current);
  final b = QuakeTime.eventInstantUtc(incoming);
  if (a.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute !=
      b.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute) {
    return null;
  }
  if (minuteCopy(current) && incoming.eventId == id && b.second != 0) return 1;
  if (minuteCopy(incoming) && current.eventId == id && a.second != 0) return -1;
  return null;
}
