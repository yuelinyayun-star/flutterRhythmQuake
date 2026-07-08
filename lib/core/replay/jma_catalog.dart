import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

class JmaCatalog {
  final int schemaVersion;
  final String catalogId;
  final String revision;
  final String sourceUrl;
  final DateTime generatedAt;
  final List<JmaCatalogEvent> events;

  const JmaCatalog({
    required this.schemaVersion,
    required this.catalogId,
    required this.revision,
    required this.sourceUrl,
    required this.generatedAt,
    required this.events,
  });

  factory JmaCatalog.fromFile(File file) {
    return JmaCatalog.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
    );
  }

  factory JmaCatalog.fromJson(Map<String, Object?> json) {
    return JmaCatalog(
      schemaVersion: json['schemaVersion']! as int,
      catalogId: json['catalogId']! as String,
      revision: json['revision']! as String,
      sourceUrl: json['sourceUrl']! as String,
      generatedAt: DateTime.parse(json['generatedAt']! as String),
      events: (json['events']! as List<Object?>)
          .map(
            (item) => JmaCatalogEvent.fromJson(item! as Map<String, Object?>),
          )
          .toList(growable: false),
    );
  }

  List<String> validate() {
    final issues = <String>[];
    if (schemaVersion != 1) issues.add('unsupported_schema_version');
    if (catalogId.trim().isEmpty) issues.add('missing_catalog_id');
    if (revision.trim().isEmpty) issues.add('missing_revision');
    if (!_isHttpUrl(sourceUrl)) issues.add('invalid_source_url');
    if (!generatedAt.isUtc) issues.add('generated_at_must_be_utc');
    final eventIds = <String>{};
    final resourceIds = <String>{};
    for (final event in events) {
      issues.addAll(event.validate());
      if (!eventIds.add(event.eventId)) {
        issues.add('duplicate_event_id:${event.eventId}');
      }
      if (!resourceIds.add(event.resourceId)) {
        issues.add('duplicate_resource_id:${event.resourceId}');
      }
    }
    return issues;
  }
}

class JmaCatalogEvent {
  final String eventId;
  final String resourceId;
  final String revision;
  final String status;
  final DateTime originTime;
  final double latitude;
  final double longitude;
  final double? depthKm;
  final double? magnitude;
  final String region;
  final String? sourceUrl;
  final Map<String, Object?> metadata;

  const JmaCatalogEvent({
    required this.eventId,
    required this.resourceId,
    required this.revision,
    required this.status,
    required this.originTime,
    required this.latitude,
    required this.longitude,
    required this.depthKm,
    required this.magnitude,
    required this.region,
    required this.sourceUrl,
    this.metadata = const {},
  });

  factory JmaCatalogEvent.fromJson(Map<String, Object?> json) {
    return JmaCatalogEvent(
      eventId: json['eventId']! as String,
      resourceId: json['resourceId']! as String,
      revision: json['revision']! as String,
      status: json['status']! as String,
      originTime: DateTime.parse(json['originTime']! as String),
      latitude: (json['latitude']! as num).toDouble(),
      longitude: (json['longitude']! as num).toDouble(),
      depthKm: (json['depthKm'] as num?)?.toDouble(),
      magnitude: (json['magnitude'] as num?)?.toDouble(),
      region: json['region'] as String? ?? '',
      sourceUrl: json['sourceUrl'] as String?,
      metadata:
          json['metadata'] as Map<String, Object?>? ??
          const <String, Object?>{},
    );
  }

  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'resourceId': resourceId,
    'revision': revision,
    'status': status,
    'originTime': originTime.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'depthKm': depthKm,
    'magnitude': magnitude,
    'region': region,
    'sourceUrl': sourceUrl,
    'metadata': metadata,
  };

  List<String> validate() {
    final issues = <String>[];
    if (eventId.trim().isEmpty) issues.add('missing_event_id');
    if (resourceId.trim().isEmpty) issues.add('missing_resource_id:$eventId');
    if (revision.trim().isEmpty) issues.add('missing_event_revision:$eventId');
    if (status != 'final' && status != 'reviewed') {
      issues.add('non_final_event_status:$eventId:$status');
    }
    if (latitude < -90 || latitude > 90) {
      issues.add('invalid_latitude:$eventId');
    }
    if (longitude < -180 || longitude > 180) {
      issues.add('invalid_longitude:$eventId');
    }
    if (depthKm != null && (depthKm! < 0 || !depthKm!.isFinite)) {
      issues.add('invalid_depth:$eventId');
    }
    if (magnitude != null && !magnitude!.isFinite) {
      issues.add('invalid_magnitude:$eventId');
    }
    if (sourceUrl != null && !_isHttpUrl(sourceUrl!)) {
      issues.add('invalid_event_source_url:$eventId');
    }
    return issues;
  }
}

class JmaCatalogReference {
  final DateTime originTime;
  final double latitude;
  final double longitude;
  final double? magnitude;

  const JmaCatalogReference({
    required this.originTime,
    required this.latitude,
    required this.longitude,
    required this.magnitude,
  });
}

class JmaCatalogMatchConfig {
  final Duration maxTimeDifference;
  final double maxDistanceKm;
  final double maxMagnitudeDifference;
  final double minimumScoreGap;

  const JmaCatalogMatchConfig({
    this.maxTimeDifference = const Duration(seconds: 120),
    this.maxDistanceKm = 120,
    this.maxMagnitudeDifference = 1.2,
    this.minimumScoreGap = 0.15,
  });
}

enum JmaCatalogMatchStatus { matched, noMatch, ambiguous }

class JmaCatalogCandidate {
  final JmaCatalogEvent event;
  final double timeDifferenceSeconds;
  final double distanceKm;
  final double? magnitudeDifference;
  final double score;

  const JmaCatalogCandidate({
    required this.event,
    required this.timeDifferenceSeconds,
    required this.distanceKm,
    required this.magnitudeDifference,
    required this.score,
  });

  Map<String, Object?> toJson() => {
    'eventId': event.eventId,
    'resourceId': event.resourceId,
    'timeDifferenceSeconds': timeDifferenceSeconds,
    'distanceKm': distanceKm,
    'magnitudeDifference': magnitudeDifference,
    'score': score,
  };
}

class JmaCatalogMatchResult {
  final JmaCatalogMatchStatus status;
  final JmaCatalogCandidate? match;
  final List<JmaCatalogCandidate> candidates;

  const JmaCatalogMatchResult({
    required this.status,
    required this.match,
    required this.candidates,
  });
}

class JmaCatalogMatcher {
  final JmaCatalogMatchConfig config;

  const JmaCatalogMatcher({this.config = const JmaCatalogMatchConfig()});

  JmaCatalogMatchResult match(
    JmaCatalog catalog,
    JmaCatalogReference reference,
  ) {
    final candidates = <JmaCatalogCandidate>[];
    for (final event in catalog.events) {
      final timeDifference = event.originTime
          .difference(reference.originTime)
          .abs();
      if (timeDifference > config.maxTimeDifference) continue;
      final distance = _haversineKm(
        reference.latitude,
        reference.longitude,
        event.latitude,
        event.longitude,
      );
      if (distance > config.maxDistanceKm) continue;
      final magnitudeDifference =
          reference.magnitude == null || event.magnitude == null
          ? null
          : (reference.magnitude! - event.magnitude!).abs();
      if (magnitudeDifference != null &&
          magnitudeDifference > config.maxMagnitudeDifference) {
        continue;
      }
      final score =
          timeDifference.inMilliseconds /
              config.maxTimeDifference.inMilliseconds +
          distance / config.maxDistanceKm +
          (magnitudeDifference == null
              ? 0.15
              : magnitudeDifference / config.maxMagnitudeDifference);
      candidates.add(
        JmaCatalogCandidate(
          event: event,
          timeDifferenceSeconds: timeDifference.inMilliseconds / 1000,
          distanceKm: distance,
          magnitudeDifference: magnitudeDifference,
          score: score,
        ),
      );
    }
    candidates.sort((a, b) => a.score.compareTo(b.score));
    if (candidates.isEmpty) {
      return const JmaCatalogMatchResult(
        status: JmaCatalogMatchStatus.noMatch,
        match: null,
        candidates: [],
      );
    }
    if (candidates.length > 1 &&
        candidates[1].score - candidates[0].score < config.minimumScoreGap) {
      return JmaCatalogMatchResult(
        status: JmaCatalogMatchStatus.ambiguous,
        match: null,
        candidates: List.unmodifiable(candidates),
      );
    }
    return JmaCatalogMatchResult(
      status: JmaCatalogMatchStatus.matched,
      match: candidates.first,
      candidates: List.unmodifiable(candidates),
    );
  }
}

bool _isHttpUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty;
}

double _haversineKm(
  double latitudeA,
  double longitudeA,
  double latitudeB,
  double longitudeB,
) {
  const earthRadiusKm = 6371.0;
  final dLat = (latitudeB - latitudeA) * math.pi / 180;
  final dLon = (longitudeB - longitudeA) * math.pi / 180;
  final latA = latitudeA * math.pi / 180;
  final latB = latitudeB * math.pi / 180;
  final h =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(latA) * math.cos(latB) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 *
      earthRadiusKm *
      math.atan2(math.sqrt(h), math.sqrt(math.max(0, 1 - h)));
}
