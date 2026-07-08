import 'dart:math' as math;

import '../source_estimation/station_observation_history.dart';

const waveformProjectedGifBaselineVersion =
    'waveform_projected_gif_spatial_baseline_v1';

class ProjectedGifStation {
  const ProjectedGifStation({
    required this.key,
    required this.sensorRole,
    required this.latitude,
    required this.longitude,
  });

  final String key;
  final String sensorRole;
  final double latitude;
  final double longitude;
}

class ProjectedGifPoint {
  const ProjectedGifPoint({
    required this.stationKey,
    required this.observedAtUtc,
    required this.intensity,
    required this.projectedLevel,
  });

  final String stationKey;
  final DateTime observedAtUtc;
  final double intensity;
  final int projectedLevel;
}

class ProjectedGifFieldEvent {
  const ProjectedGifFieldEvent({
    required this.eventId,
    required this.originTimeUtc,
    required this.latitude,
    required this.longitude,
    required this.stations,
    required this.points,
  });

  final String eventId;
  final DateTime originTimeUtc;
  final double latitude;
  final double longitude;
  final Map<String, ProjectedGifStation> stations;
  final List<ProjectedGifPoint> points;

  factory ProjectedGifFieldEvent.fromJson(Map<String, Object?> json) {
    if (json['domain'] != 'waveform_projected_gif') {
      throw FormatException('Expected waveform_projected_gif package.');
    }
    final event = json['event'] as Map<String, Object?>?;
    if (event == null) {
      throw FormatException('Projected package has no event truth.');
    }
    final stations = <String, ProjectedGifStation>{};
    for (final raw
        in (json['stations']! as List<Object?>).cast<Map<String, Object?>>()) {
      final code = raw['stationCode']! as String;
      final role = raw['sensorRole']! as String;
      final key = '$code:$role';
      stations[key] = ProjectedGifStation(
        key: key,
        sensorRole: role,
        latitude: _number(raw['latitude']),
        longitude: _number(raw['longitude']),
      );
    }
    final points = <ProjectedGifPoint>[];
    for (final raw
        in (json['observations']! as List<Object?>)
            .cast<Map<String, Object?>>()) {
      final role = raw['sensorRole']! as String;
      points.add(
        ProjectedGifPoint(
          stationKey: '${raw['stationCode']}:$role',
          observedAtUtc: DateTime.parse(
            raw['observedAtUtc']! as String,
          ).toUtc(),
          intensity: _number(raw['gifEquivalentShindo']),
          projectedLevel: (raw['projectedLevel']! as num).toInt(),
        ),
      );
    }
    return ProjectedGifFieldEvent(
      eventId: json['eventId']! as String,
      originTimeUtc: DateTime.parse(event['originTimeUtc']! as String).toUtc(),
      latitude: _number(event['latitude']),
      longitude: _number(event['longitude']),
      stations: stations,
      points: points,
    );
  }
}

class ProjectedGifBaselineConfig {
  const ProjectedGifBaselineConfig({
    required this.minimumIntensity,
    required this.intensityWeightExponent,
    this.minimumStations = 4,
    this.surfaceOnly = true,
    this.maximumSecondsAfterOrigin = 120,
    this.useRunningPeak = false,
    this.arrivalDecaySeconds,
  });

  final double minimumIntensity;
  final double intensityWeightExponent;
  final int minimumStations;
  final bool surfaceOnly;
  final int maximumSecondsAfterOrigin;
  final bool useRunningPeak;
  final double? arrivalDecaySeconds;

  Map<String, Object?> toJson() => {
    'minimumIntensity': minimumIntensity,
    'intensityWeightExponent': intensityWeightExponent,
    'minimumStations': minimumStations,
    'surfaceOnly': surfaceOnly,
    'maximumSecondsAfterOrigin': maximumSecondsAfterOrigin,
    'useRunningPeak': useRunningPeak,
    'arrivalDecaySeconds': arrivalDecaySeconds,
  };
}

class ProjectedGifEventEvaluation {
  const ProjectedGifEventEvaluation({
    required this.eventId,
    required this.dropRate,
    required this.frameCount,
    required this.eligibleFrameCount,
    required this.firstEstimateDelaySeconds,
    required this.firstEstimateErrorKm,
    required this.medianErrorKm,
    required this.p90ErrorKm,
    required this.quantizationMae,
  });

  final String eventId;
  final double dropRate;
  final int frameCount;
  final int eligibleFrameCount;
  final double? firstEstimateDelaySeconds;
  final double? firstEstimateErrorKm;
  final double? medianErrorKm;
  final double? p90ErrorKm;
  final double quantizationMae;

  double get coverage => frameCount == 0 ? 0 : eligibleFrameCount / frameCount;

  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'dropRate': dropRate,
    'frameCount': frameCount,
    'eligibleFrameCount': eligibleFrameCount,
    'eligibleFrameCoverage': coverage,
    'firstEstimateDelaySeconds': firstEstimateDelaySeconds,
    'firstEstimateErrorKm': firstEstimateErrorKm,
    'medianErrorKm': medianErrorKm,
    'p90ErrorKm': p90ErrorKm,
    'quantizationMae': quantizationMae,
  };
}

class ProjectedGifSpatialBaseline {
  const ProjectedGifSpatialBaseline();

  ProjectedGifEventEvaluation evaluate(
    ProjectedGifFieldEvent event,
    ProjectedGifBaselineConfig config, {
    double dropRate = 0,
    int maskSeed = 0,
  }) {
    final frames = <DateTime, List<ProjectedGifPoint>>{};
    var quantizationError = 0.0;
    var quantizationCount = 0;
    for (final point in event.points) {
      if (point.observedAtUtc.isBefore(event.originTimeUtc)) continue;
      if (point.observedAtUtc.isAfter(
        event.originTimeUtc.add(
          Duration(seconds: config.maximumSecondsAfterOrigin),
        ),
      )) {
        continue;
      }
      final station = event.stations[point.stationKey];
      if (station == null ||
          (config.surfaceOnly && station.sensorRole != 'surface')) {
        continue;
      }
      quantizationError +=
          (point.intensity - projectedLevelCenter(point.projectedLevel)).abs();
      quantizationCount++;
      frames.putIfAbsent(point.observedAtUtc, () => []).add(point);
    }

    final errors = <double>[];
    final temporalStates = <String, _TemporalStationState>{};
    double? firstDelay;
    double? firstError;
    final sortedTimes = frames.keys.toList(growable: false)..sort();
    for (final time in sortedTimes) {
      final currentPoints = <_WeightedPoint>[];
      for (final point in frames[time]!) {
        if (_isMasked(point.stationKey, dropRate, maskSeed)) continue;
        final station = event.stations[point.stationKey]!;
        if (!config.useRunningPeak) {
          if (point.intensity >= config.minimumIntensity) {
            currentPoints.add(
              _WeightedPoint(station: station, intensity: point.intensity),
            );
          }
          continue;
        }

        final state = temporalStates.putIfAbsent(
          point.stationKey,
          _TemporalStationState.new,
        );
        state.history.add(
          SeismicStationObservationFrame(
            dataTime: time,
            receivedAt: time,
            value: point.intensity,
            rawLevel: point.projectedLevel,
            detectLevel: point.projectedLevel,
            isTriggered: point.intensity >= config.minimumIntensity,
            qualityFlags: const {'projected_from_official_waveform'},
          ),
        );
        if (point.intensity >= config.minimumIntensity) {
          state.firstArrival ??= time;
          state.peakIntensity = math.max(
            state.peakIntensity ?? point.intensity,
            point.intensity,
          );
        }
      }

      DateTime? earliestArrival;
      if (config.useRunningPeak) {
        for (final state in temporalStates.values) {
          final arrival = state.firstArrival;
          if (arrival != null &&
              (earliestArrival == null || arrival.isBefore(earliestArrival))) {
            earliestArrival = arrival;
          }
        }
      }
      final weightedPoints = config.useRunningPeak
          ? <_WeightedPoint>[
              for (final entry in temporalStates.entries)
                if (entry.value.firstArrival != null &&
                    entry.value.peakIntensity != null)
                  _WeightedPoint(
                    station: event.stations[entry.key]!,
                    intensity: entry.value.peakIntensity!,
                    arrivalOffsetSeconds:
                        entry.value.firstArrival!
                            .difference(earliestArrival!)
                            .inMilliseconds /
                        1000.0,
                  ),
            ]
          : currentPoints;
      var sumWeight = 0.0;
      var sumLatitude = 0.0;
      var sumLongitude = 0.0;
      var stationCount = 0;
      for (final point in weightedPoints) {
        final weight =
            math
                .pow(10, point.intensity * config.intensityWeightExponent)
                .toDouble() *
            _arrivalWeight(point.arrivalOffsetSeconds, config);
        sumWeight += weight;
        sumLatitude += point.station.latitude * weight;
        sumLongitude += point.station.longitude * weight;
        stationCount++;
      }
      if (stationCount < config.minimumStations || sumWeight <= 0) continue;
      final error = _haversineKm(
        event.latitude,
        event.longitude,
        sumLatitude / sumWeight,
        sumLongitude / sumWeight,
      );
      errors.add(error);
      firstDelay ??=
          time.difference(event.originTimeUtc).inMilliseconds / 1000.0;
      firstError ??= error;
    }

    return ProjectedGifEventEvaluation(
      eventId: event.eventId,
      dropRate: dropRate,
      frameCount: sortedTimes.length,
      eligibleFrameCount: errors.length,
      firstEstimateDelaySeconds: firstDelay,
      firstEstimateErrorKm: firstError,
      medianErrorKm: errors.isEmpty ? null : _percentile(errors, 0.5),
      p90ErrorKm: errors.isEmpty ? null : _percentile(errors, 0.9),
      quantizationMae: quantizationCount == 0
          ? 0
          : quantizationError / quantizationCount,
    );
  }
}

class ProjectedGifLeaveOneEventOutFold {
  const ProjectedGifLeaveOneEventOutFold({
    required this.heldOutEventId,
    required this.config,
    required this.trainingMedianErrorKm,
    required this.evaluations,
  });

  final String heldOutEventId;
  final ProjectedGifBaselineConfig config;
  final double trainingMedianErrorKm;
  final List<ProjectedGifEventEvaluation> evaluations;

  Map<String, Object?> toJson() => {
    'heldOutEventId': heldOutEventId,
    'selectedConfig': config.toJson(),
    'trainingMedianErrorKm': trainingMedianErrorKm,
    'heldOutEvaluations': evaluations.map((value) => value.toJson()).toList(),
  };
}

class ProjectedGifBaselineTrainer {
  const ProjectedGifBaselineTrainer({
    this.minimumIntensityGrid = const [-0.5, 0.0, 0.5, 1.0, 1.5, 2.0, 2.5],
    this.weightExponentGrid = const [0.25, 0.5, 0.75, 1.0, 1.25],
    this.dropRates = const [0.0, 0.2, 0.5, 0.8],
    this.minimumTrainingCoverage = 0.25,
    this.useTemporalHistory = false,
    this.arrivalDecayGrid = const [5.0, 10.0, 20.0, 40.0],
  });

  final List<double> minimumIntensityGrid;
  final List<double> weightExponentGrid;
  final List<double> dropRates;
  final double minimumTrainingCoverage;
  final bool useTemporalHistory;
  final List<double> arrivalDecayGrid;

  List<ProjectedGifLeaveOneEventOutFold> leaveOneEventOut(
    List<ProjectedGifFieldEvent> events,
  ) {
    if (events.length < 2) {
      throw ArgumentError('At least two events are required.');
    }
    const baseline = ProjectedGifSpatialBaseline();
    final folds = <ProjectedGifLeaveOneEventOutFold>[];
    for (final heldOut in events) {
      final training = events
          .where((event) => event.eventId != heldOut.eventId)
          .toList(growable: false);
      ProjectedGifBaselineConfig? bestConfig;
      var bestScore = double.infinity;
      for (final threshold in minimumIntensityGrid) {
        for (final exponent in weightExponentGrid) {
          final arrivalCandidates = useTemporalHistory
              ? arrivalDecayGrid.map<double?>((value) => value)
              : const <double?>[null];
          for (final arrivalDecay in arrivalCandidates) {
            final candidate = ProjectedGifBaselineConfig(
              minimumIntensity: threshold,
              intensityWeightExponent: exponent,
              useRunningPeak: useTemporalHistory,
              arrivalDecaySeconds: arrivalDecay,
            );
            final trainingEvaluations = training
                .map((event) => baseline.evaluate(event, candidate))
                .toList(growable: false);
            if (trainingEvaluations.any(
              (evaluation) =>
                  evaluation.medianErrorKm == null ||
                  evaluation.coverage < minimumTrainingCoverage,
            )) {
              continue;
            }
            final eventErrors = trainingEvaluations
                .map((evaluation) => evaluation.medianErrorKm!)
                .toList(growable: false);
            final score = _percentile(eventErrors, 0.5);
            if (score < bestScore) {
              bestScore = score;
              bestConfig = candidate;
            }
          }
        }
      }
      if (bestConfig == null) {
        throw StateError('No usable config for fold ${heldOut.eventId}.');
      }
      folds.add(
        ProjectedGifLeaveOneEventOutFold(
          heldOutEventId: heldOut.eventId,
          config: bestConfig,
          trainingMedianErrorKm: bestScore,
          evaluations: [
            for (final dropRate in dropRates)
              baseline.evaluate(
                heldOut,
                bestConfig,
                dropRate: dropRate,
                maskSeed: events.indexOf(heldOut) + 1,
              ),
          ],
        ),
      );
    }
    return folds;
  }
}

class _TemporalStationState {
  final StationObservationHistory history = StationObservationHistory();
  DateTime? firstArrival;
  double? peakIntensity;
}

class _WeightedPoint {
  const _WeightedPoint({
    required this.station,
    required this.intensity,
    this.arrivalOffsetSeconds = 0,
  });

  final ProjectedGifStation station;
  final double intensity;
  final double arrivalOffsetSeconds;
}

double _arrivalWeight(
  double arrivalOffsetSeconds,
  ProjectedGifBaselineConfig config,
) {
  final decay = config.arrivalDecaySeconds;
  if (!config.useRunningPeak || decay == null || decay <= 0) return 1;
  return math.exp(-arrivalOffsetSeconds / decay);
}

double projectedLevelCenter(int level) {
  const thresholds = [
    -3.0,
    -2.5,
    -2.0,
    -1.5,
    -1.17,
    -0.84,
    -0.5,
    -0.17,
    0.16,
    0.5,
    0.83,
    1.16,
    1.5,
    1.83,
    2.16,
    2.5,
    2.83,
    3.16,
    3.5,
    3.83,
    4.16,
    4.5,
    4.75,
    5.0,
    5.25,
    5.5,
    5.75,
    6.0,
    6.25,
    6.5,
  ];
  if (level < 0) return -3.25;
  if (level >= thresholds.length - 1) return thresholds.last + 0.125;
  return (thresholds[level] + thresholds[level + 1]) / 2;
}

bool _isMasked(String stationKey, double rate, int seed) {
  if (rate <= 0) return false;
  var hash = 0x811c9dc5 ^ seed;
  for (final codeUnit in stationKey.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return (hash & 0xffffffff) / 0x100000000 < rate;
}

double _percentile(List<double> values, double percentile) {
  final sorted = values.toList(growable: false)..sort();
  if (sorted.length == 1) return sorted.single;
  final position = percentile * (sorted.length - 1);
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];
  return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
}

double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusKm = 6371.0;
  final dLat = _radians(lat2 - lat1);
  final dLon = _radians(lon2 - lon1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_radians(lat1)) *
          math.cos(_radians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _radians(double degrees) => degrees * math.pi / 180;

double _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.parse(value);
  throw FormatException('Expected number, got $value');
}
