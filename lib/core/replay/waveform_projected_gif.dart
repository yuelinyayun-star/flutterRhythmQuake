import 'dart:math' as math;

import 'knet_waveform_archive.dart';

const waveformProjectedGifVersion = 'waveform_projected_gif_v2';

class WaveformProjectedGifPackage {
  const WaveformProjectedGifPackage({
    required this.eventId,
    required this.sourceFeaturePackagePath,
    required this.sourceFeatureFormat,
    required this.niedDirectoryId,
    required this.stationSecondCount,
    required this.stationCount,
    required this.startTimeUtc,
    required this.endTimeUtc,
    required this.event,
    required this.stations,
    required this.observations,
    required this.qualityFlags,
  });

  final String eventId;
  final String sourceFeaturePackagePath;
  final String sourceFeatureFormat;
  final String? niedDirectoryId;
  final int stationSecondCount;
  final int stationCount;
  final DateTime? startTimeUtc;
  final DateTime? endTimeUtc;
  final WaveformProjectedGifEvent? event;
  final List<WaveformProjectedGifStation> stations;
  final List<WaveformProjectedGifObservation> observations;
  final List<String> qualityFlags;

  Map<String, Object?> toJson({bool includeObservations = true}) => {
    'schemaVersion': waveformProjectedGifVersion,
    'domain': 'waveform_projected_gif',
    'eventId': eventId,
    'sourceFeaturePackagePath': sourceFeaturePackagePath,
    'sourceFeatureFormat': sourceFeatureFormat,
    'niedDirectoryId': niedDirectoryId,
    'stationSecondCount': stationSecondCount,
    'stationCount': stationCount,
    'startTimeUtc': startTimeUtc?.toIso8601String(),
    'endTimeUtc': endTimeUtc?.toIso8601String(),
    'event': event?.toJson(),
    'stations': stations.map((value) => value.toJson()).toList(),
    'qualityFlags': qualityFlags,
    if (includeObservations)
      'observations': observations.map((value) => value.toJson()).toList(),
  };
}

class WaveformProjectedGifEvent {
  const WaveformProjectedGifEvent({
    required this.originTimeUtc,
    required this.latitude,
    required this.longitude,
    required this.depthKm,
    required this.magnitude,
  });

  final DateTime originTimeUtc;
  final double latitude;
  final double longitude;
  final double depthKm;
  final double magnitude;

  Map<String, Object?> toJson() => {
    'originTimeUtc': originTimeUtc.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'depthKm': depthKm,
    'magnitude': magnitude,
  };
}

class WaveformProjectedGifStation {
  const WaveformProjectedGifStation({
    required this.stationCode,
    required this.sensorRole,
    required this.network,
    required this.latitude,
    required this.longitude,
  });

  final String stationCode;
  final KnetSensorRole sensorRole;
  final KnetNetwork network;
  final double latitude;
  final double longitude;

  String get key => '$stationCode:${sensorRole.name}';

  Map<String, Object?> toJson() => {
    'stationCode': stationCode,
    'sensorRole': sensorRole.name,
    'network': network.name,
    'latitude': latitude,
    'longitude': longitude,
  };
}

class WaveformProjectedGifObservation {
  const WaveformProjectedGifObservation({
    required this.stationCode,
    required this.sensorRole,
    required this.network,
    required this.observedAtUtc,
    required this.gifEquivalentShindo,
    required this.colorPosition,
    required this.projectedLevel,
    required this.pgaGal,
    required this.pgvCms,
    required this.energyRatioToPreviousBaseline,
    required this.qualityFlags,
  });

  final String stationCode;
  final KnetSensorRole sensorRole;
  final KnetNetwork network;
  final DateTime observedAtUtc;
  final double gifEquivalentShindo;
  final double colorPosition;
  final int projectedLevel;
  final double pgaGal;
  final double pgvCms;
  final double? energyRatioToPreviousBaseline;
  final List<String> qualityFlags;

  Map<String, Object?> toJson() => {
    'stationCode': stationCode,
    'sensorRole': sensorRole.name,
    'network': network.name,
    'observedAtUtc': observedAtUtc.toIso8601String(),
    'gifEquivalentShindo': gifEquivalentShindo,
    'colorPosition': colorPosition,
    'projectedLevel': projectedLevel,
    'pgaGal': pgaGal,
    'pgvCms': pgvCms,
    'energyRatioToPreviousBaseline': energyRatioToPreviousBaseline,
    'qualityFlags': qualityFlags,
  };
}

class WaveformProjectedGifConverter {
  const WaveformProjectedGifConverter();

  WaveformProjectedGifPackage convertFeaturePackage(
    Map<String, Object?> featurePackage, {
    required String eventId,
    required String sourceFeaturePackagePath,
    required String sourceFeatureFormat,
    String? niedDirectoryId,
  }) {
    final observations = <WaveformProjectedGifObservation>[];
    final stationsByKey = <String, WaveformProjectedGifStation>{};
    DateTime? startTime;
    DateTime? endTime;

    final features = (featurePackage['features']! as List<Object?>)
        .cast<Map<String, Object?>>();
    for (final series in features) {
      final stationCode = series['stationCode']! as String;
      final sensorRole = _enumByName(
        KnetSensorRole.values,
        series['sensorRole']! as String,
      );
      final network = _enumByName(
        KnetNetwork.values,
        series['network']! as String,
      );
      final seriesQuality =
          (series['qualityFlags'] as List<Object?>? ?? const [])
              .cast<String>()
              .toList(growable: false);
      final station = WaveformProjectedGifStation(
        stationCode: stationCode,
        sensorRole: sensorRole,
        network: network,
        latitude: _requiredNumber(series['stationLatitude']),
        longitude: _requiredNumber(series['stationLongitude']),
      );
      stationsByKey[station.key] = station;

      for (final rawSecond
          in (series['seconds']! as List<Object?>)
              .cast<Map<String, Object?>>()) {
        final intensity = _optionalNumber(rawSecond['jmaIntensityApprox']);
        if (intensity == null || intensity.isNaN || intensity.isInfinite) {
          continue;
        }
        final observedAt = DateTime.parse(
          rawSecond['startTimeUtc']! as String,
        ).toUtc();
        startTime = startTime == null || observedAt.isBefore(startTime)
            ? observedAt
            : startTime;
        endTime = endTime == null || observedAt.isAfter(endTime)
            ? observedAt
            : endTime;

        observations.add(
          WaveformProjectedGifObservation(
            stationCode: stationCode,
            sensorRole: sensorRole,
            network: network,
            observedAtUtc: observedAt,
            gifEquivalentShindo: intensity,
            colorPosition: gifEquivalentColorPosition(intensity),
            projectedLevel: projectedShindoLevel(intensity),
            pgaGal: _requiredNumber(rawSecond['pgaGal']),
            pgvCms: _requiredNumber(rawSecond['pgvCms']),
            energyRatioToPreviousBaseline: _optionalNumber(
              rawSecond['energyRatioToPreviousBaseline'],
            ),
            qualityFlags: <String>{
              'projected_from_official_waveform',
              'not_real_nied_gif',
              'jma_intensity_unfiltered_duration_proxy',
              ...seriesQuality,
            }.toList(growable: false)..sort(),
          ),
        );
      }
    }

    observations.sort((a, b) {
      final timeCompare = a.observedAtUtc.compareTo(b.observedAtUtc);
      if (timeCompare != 0) return timeCompare;
      final stationCompare = a.stationCode.compareTo(b.stationCode);
      if (stationCompare != 0) return stationCompare;
      return a.sensorRole.name.compareTo(b.sensorRole.name);
    });

    final stations = stationsByKey.values.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    return WaveformProjectedGifPackage(
      eventId: eventId,
      sourceFeaturePackagePath: sourceFeaturePackagePath,
      sourceFeatureFormat: sourceFeatureFormat,
      niedDirectoryId: niedDirectoryId,
      stationSecondCount: observations.length,
      stationCount: stations.length,
      startTimeUtc: startTime,
      endTimeUtc: endTime,
      event: _readEvent(featurePackage),
      stations: stations,
      observations: observations,
      qualityFlags: const [
        'projected_from_official_waveform',
        'not_real_nied_gif',
        'does_not_include_untriggered_full_network',
        'does_not_include_real_gif_transport_or_pixel_errors',
      ],
    );
  }

  WaveformProjectedGifEvent? _readEvent(Map<String, Object?> featurePackage) {
    final channels = (featurePackage['channels'] as List<Object?>? ?? const []);
    if (channels.isEmpty) return null;
    final first = channels.first as Map<String, Object?>;
    final originTime = first['eventOriginTimeUtc'] as String?;
    final latitude = _optionalNumber(first['eventLatitude']);
    final longitude = _optionalNumber(first['eventLongitude']);
    final depth = _optionalNumber(first['eventDepthKm']);
    final magnitude = _optionalNumber(first['eventMagnitude']);
    if (originTime == null ||
        latitude == null ||
        longitude == null ||
        depth == null ||
        magnitude == null) {
      return null;
    }
    return WaveformProjectedGifEvent(
      originTimeUtc: DateTime.parse(originTime).toUtc(),
      latitude: latitude,
      longitude: longitude,
      depthKm: depth,
      magnitude: magnitude,
    );
  }
}

double gifEquivalentColorPosition(double shindo) =>
    ((shindo + 3.0) / 10.0).clamp(0.0, 1.0);

int projectedShindoLevel(double shindo) {
  if (shindo < -3.0) return -1;
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
  var level = -1;
  for (var index = 0; index < thresholds.length; index++) {
    if (shindo >= thresholds[index]) level = index;
  }
  return math.min(level, thresholds.length - 1);
}

T _enumByName<T extends Enum>(List<T> values, String name) =>
    values.firstWhere((value) => value.name == name);

double _requiredNumber(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.parse(value);
  throw FormatException('Expected number, got $value');
}

double? _optionalNumber(Object? value) {
  if (value == null) return null;
  return _requiredNumber(value);
}
