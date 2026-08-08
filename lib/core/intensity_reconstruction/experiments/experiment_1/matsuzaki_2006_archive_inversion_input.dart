import 'dart:math' as math;

import 'matsuzaki_2006_attenuation_model.dart';
import 'matsuzaki_2006_candidate_scoring.dart';
import 'matsuzaki_2006_geometry.dart';
import 'matsuzaki_2006_joint_inversion.dart';

enum Matsuzaki2006ArchiveInputStatus {
  ready,
  invalidEventRecord,
  insufficientValidObservations,
  insufficientDomainSafeObservations,
}

class Matsuzaki2006ArchiveInputSpec {
  const Matsuzaki2006ArchiveInputSpec({
    required this.initialSearchRadiusKm,
    required this.maximumHorizontalSearchDistanceKm,
    required this.minimumSearchDepthKm,
    required this.maximumSearchDepthKm,
    required this.minimumObservations,
    required this.maximumObservations,
    required this.minimumInstrumentalIntensity,
  });

  final double initialSearchRadiusKm;
  final double maximumHorizontalSearchDistanceKm;
  final double minimumSearchDepthKm;
  final double maximumSearchDepthKm;
  final int minimumObservations;
  final int maximumObservations;
  final double minimumInstrumentalIntensity;

  void validate() {
    if (!initialSearchRadiusKm.isFinite || initialSearchRadiusKm <= 0) {
      throw ArgumentError.value(
        initialSearchRadiusKm,
        'initialSearchRadiusKm',
        'Must be finite and positive.',
      );
    }
    if (!maximumHorizontalSearchDistanceKm.isFinite ||
        maximumHorizontalSearchDistanceKm < initialSearchRadiusKm ||
        maximumHorizontalSearchDistanceKm >=
            Matsuzaki2006AttenuationModel.maximumSourceDistanceKm) {
      throw ArgumentError.value(
        maximumHorizontalSearchDistanceKm,
        'maximumHorizontalSearchDistanceKm',
        'Must be at least the initial radius and below 500 km.',
      );
    }
    if (!minimumSearchDepthKm.isFinite ||
        !maximumSearchDepthKm.isFinite ||
        minimumSearchDepthKm <
            Matsuzaki2006AttenuationModel.minimumSourceDistanceKm ||
        maximumSearchDepthKm >
            Matsuzaki2006AttenuationModel.maximumObservedDepthKm ||
        minimumSearchDepthKm >= maximumSearchDepthKm) {
      throw ArgumentError(
        'Search depth bounds must keep every point-source distance at or '
        'above 1 km and remain inside the published depth range.',
      );
    }
    if (minimumObservations <= 0) {
      throw ArgumentError.value(
        minimumObservations,
        'minimumObservations',
        'Must be positive.',
      );
    }
    if (maximumObservations < minimumObservations) {
      throw ArgumentError.value(
        maximumObservations,
        'maximumObservations',
        'Must be at least minimumObservations.',
      );
    }
    if (!minimumInstrumentalIntensity.isFinite) {
      throw ArgumentError.value(
        minimumInstrumentalIntensity,
        'minimumInstrumentalIntensity',
        'Must be finite.',
      );
    }
  }
}

class Matsuzaki2006ArchiveInversionInput {
  Matsuzaki2006ArchiveInversionInput({
    required this.status,
    required this.eventId,
    required this.anchorLatitude,
    required this.anchorLongitude,
    required this.initialHorizontalBounds,
    required this.hardHorizontalBounds,
    required this.radialSearchConstraint,
    required List<Matsuzaki2006IntensityObservation> observations,
    required this.rawObservationCount,
    required this.validObservationCount,
    required this.domainSafeObservationCount,
    required Map<String, int> rejectionCounts,
  }) : observations = List.unmodifiable(observations),
       rejectionCounts = Map.unmodifiable(rejectionCounts);

  final Matsuzaki2006ArchiveInputStatus status;
  final String? eventId;
  final double? anchorLatitude;
  final double? anchorLongitude;
  final Matsuzaki2006HorizontalBounds? initialHorizontalBounds;
  final Matsuzaki2006HorizontalBounds? hardHorizontalBounds;
  final Matsuzaki2006RadialSearchConstraint? radialSearchConstraint;
  final List<Matsuzaki2006IntensityObservation> observations;
  final int rawObservationCount;
  final int validObservationCount;
  final int domainSafeObservationCount;
  final Map<String, int> rejectionCounts;

  bool get isReady => status == Matsuzaki2006ArchiveInputStatus.ready;
}

class Matsuzaki2006ArchiveInversionInputBuilder {
  const Matsuzaki2006ArchiveInversionInputBuilder();

  Matsuzaki2006ArchiveInversionInput build({
    required Map<String, Object?> rawEvent,
    required Matsuzaki2006ArchiveInputSpec spec,
  }) {
    spec.validate();
    final eventId = rawEvent['eventId'];
    final rawObservations = rawEvent['observations'];
    if (eventId is! String ||
        eventId.isEmpty ||
        rawObservations is! List<Object?>) {
      return _empty(
        status: Matsuzaki2006ArchiveInputStatus.invalidEventRecord,
        eventId: eventId is String ? eventId : null,
      );
    }

    final rejectionCounts = <String, int>{};
    final valid = <Matsuzaki2006IntensityObservation>[];
    final seenIds = <String>{};
    for (final raw in rawObservations) {
      if (raw is! Map<String, Object?>) {
        _increment(rejectionCounts, 'invalid_observation_record');
        continue;
      }
      final id = raw['stationId'];
      final latitude = _number(raw['latitude']);
      final longitude = _number(raw['longitude']);
      final intensity = _number(raw['instrumentalIntensity']);
      if (id is! String || id.isEmpty) {
        _increment(rejectionCounts, 'missing_station_id');
        continue;
      }
      if (!seenIds.add(id)) {
        throw FormatException('Duplicate station id $id in event $eventId.');
      }
      if (latitude == null ||
          latitude < -90 ||
          latitude > 90 ||
          longitude == null ||
          longitude < -180 ||
          longitude > 180) {
        _increment(rejectionCounts, 'invalid_station_coordinate');
        continue;
      }
      if (intensity == null || !intensity.isFinite) {
        _increment(rejectionCounts, 'missing_instrumental_intensity');
        continue;
      }
      if (intensity < spec.minimumInstrumentalIntensity) {
        _increment(rejectionCounts, 'below_minimum_instrumental_intensity');
        continue;
      }
      valid.add(
        Matsuzaki2006IntensityObservation(
          id: id,
          latitude: latitude,
          longitude: longitude,
          intensity: intensity,
        ),
      );
    }
    if (valid.length < spec.minimumObservations) {
      return Matsuzaki2006ArchiveInversionInput(
        status: Matsuzaki2006ArchiveInputStatus.insufficientValidObservations,
        eventId: eventId,
        anchorLatitude: null,
        anchorLongitude: null,
        initialHorizontalBounds: null,
        hardHorizontalBounds: null,
        radialSearchConstraint: null,
        observations: const [],
        rawObservationCount: rawObservations.length,
        validObservationCount: valid.length,
        domainSafeObservationCount: 0,
        rejectionCounts: _sortedCounts(rejectionCounts),
      );
    }

    final maximumIntensity = valid
        .map((observation) => observation.intensity)
        .reduce(math.max);
    final anchorStations = valid
        .where((observation) => observation.intensity == maximumIntensity)
        .toList();
    final anchorLatitude =
        anchorStations
            .map((observation) => observation.latitude)
            .reduce((left, right) => left + right) /
        anchorStations.length;
    final anchorLongitude =
        anchorStations
            .map((observation) => observation.longitude)
            .reduce((left, right) => left + right) /
        anchorStations.length;
    final initialBounds = _boundsAround(
      latitude: anchorLatitude,
      longitude: anchorLongitude,
      radiusKm: spec.initialSearchRadiusKm,
    );
    final hardBounds = _boundsAround(
      latitude: anchorLatitude,
      longitude: anchorLongitude,
      radiusKm: spec.maximumHorizontalSearchDistanceKm,
    );
    final radialSearchConstraint = Matsuzaki2006RadialSearchConstraint(
      centerLatitude: anchorLatitude,
      centerLongitude: anchorLongitude,
      maximumEpicentralDistanceKm: spec.maximumHorizontalSearchDistanceKm,
    );

    final domainSafe =
        valid.where((observation) {
          final stationToAnchorKm =
              Matsuzaki2006PointSourceGeometry.hypocentralDistanceBetween(
                sourceLatitude: anchorLatitude,
                sourceLongitude: anchorLongitude,
                stationLatitude: observation.latitude,
                stationLongitude: observation.longitude,
                depthKm: 0,
              );
          final maximumHorizontalDistanceKm =
              stationToAnchorKm + spec.maximumHorizontalSearchDistanceKm;
          final maximumSourceDistanceKm = math.sqrt(
            maximumHorizontalDistanceKm * maximumHorizontalDistanceKm +
                spec.maximumSearchDepthKm * spec.maximumSearchDepthKm,
          );
          return maximumSourceDistanceKm <=
              Matsuzaki2006AttenuationModel.maximumSourceDistanceKm;
        }).toList()..sort((left, right) {
          final intensityOrder = right.intensity.compareTo(left.intensity);
          return intensityOrder != 0
              ? intensityOrder
              : left.id.compareTo(right.id);
        });
    if (domainSafe.length < spec.minimumObservations) {
      return Matsuzaki2006ArchiveInversionInput(
        status:
            Matsuzaki2006ArchiveInputStatus.insufficientDomainSafeObservations,
        eventId: eventId,
        anchorLatitude: anchorLatitude,
        anchorLongitude: anchorLongitude,
        initialHorizontalBounds: initialBounds,
        hardHorizontalBounds: hardBounds,
        radialSearchConstraint: radialSearchConstraint,
        observations: const [],
        rawObservationCount: rawObservations.length,
        validObservationCount: valid.length,
        domainSafeObservationCount: domainSafe.length,
        rejectionCounts: _sortedCounts(rejectionCounts),
      );
    }
    final selected = domainSafe.take(spec.maximumObservations).toList();
    return Matsuzaki2006ArchiveInversionInput(
      status: Matsuzaki2006ArchiveInputStatus.ready,
      eventId: eventId,
      anchorLatitude: anchorLatitude,
      anchorLongitude: anchorLongitude,
      initialHorizontalBounds: initialBounds,
      hardHorizontalBounds: hardBounds,
      radialSearchConstraint: radialSearchConstraint,
      observations: selected,
      rawObservationCount: rawObservations.length,
      validObservationCount: valid.length,
      domainSafeObservationCount: domainSafe.length,
      rejectionCounts: _sortedCounts(rejectionCounts),
    );
  }

  Matsuzaki2006ArchiveInversionInput _empty({
    required Matsuzaki2006ArchiveInputStatus status,
    required String? eventId,
  }) => Matsuzaki2006ArchiveInversionInput(
    status: status,
    eventId: eventId,
    anchorLatitude: null,
    anchorLongitude: null,
    initialHorizontalBounds: null,
    hardHorizontalBounds: null,
    radialSearchConstraint: null,
    observations: const [],
    rawObservationCount: 0,
    validObservationCount: 0,
    domainSafeObservationCount: 0,
    rejectionCounts: const {},
  );
}

const double _kilometresPerAngularDegree = 111.19492664455873;

Matsuzaki2006HorizontalBounds _boundsAround({
  required double latitude,
  required double longitude,
  required double radiusKm,
}) {
  final latitudeRadiusDegrees = radiusKm / _kilometresPerAngularDegree;
  final longitudeScale =
      _kilometresPerAngularDegree * math.cos(latitude * math.pi / 180);
  if (longitudeScale <= 0) {
    throw RangeError('A radial longitude bound cannot be built at the pole.');
  }
  final longitudeRadiusDegrees = radiusKm / longitudeScale;
  final minimumLatitude = latitude - latitudeRadiusDegrees;
  final maximumLatitude = latitude + latitudeRadiusDegrees;
  final minimumLongitude = longitude - longitudeRadiusDegrees;
  final maximumLongitude = longitude + longitudeRadiusDegrees;
  if (minimumLatitude < -90 ||
      maximumLatitude > 90 ||
      minimumLongitude < -180 ||
      maximumLongitude > 180) {
    throw RangeError('Search bounds cross a geographic coordinate limit.');
  }
  return Matsuzaki2006HorizontalBounds(
    minimumLatitude: minimumLatitude,
    maximumLatitude: maximumLatitude,
    minimumLongitude: minimumLongitude,
    maximumLongitude: maximumLongitude,
  );
}

double? _number(Object? value) => value is num ? value.toDouble() : null;

void _increment(Map<String, int> counts, String key) {
  counts[key] = (counts[key] ?? 0) + 1;
}

Map<String, int> _sortedCounts(Map<String, int> counts) {
  final keys = counts.keys.toList()..sort();
  return {for (final key in keys) key: counts[key]!};
}
