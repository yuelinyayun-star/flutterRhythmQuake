import 'dart:math' as math;

import 'knet_waveform_archive.dart';

const knetWaveformFeatureVersion = 'knet_waveform_features_v1';

class KnetWaveformFeatureExtractor {
  const KnetWaveformFeatureExtractor({this.config = const KnetFeatureConfig()});

  final KnetFeatureConfig config;

  List<KnetWaveformFeatureSeries> extract(List<KnetWaveformChannel> channels) {
    final groups = <_WaveformGroupKey, List<KnetWaveformChannel>>{};
    for (final channel in channels) {
      final key = _WaveformGroupKey(channel.stationCode, channel.sensorRole);
      groups.putIfAbsent(key, () => []).add(channel);
    }

    final series = <KnetWaveformFeatureSeries>[];
    for (final entry in groups.entries) {
      final groupSeries = _extractGroup(entry.value);
      if (groupSeries != null) series.add(groupSeries);
    }
    series.sort((a, b) {
      final stationCompare = a.stationCode.compareTo(b.stationCode);
      if (stationCompare != 0) return stationCompare;
      return a.sensorRole.name.compareTo(b.sensorRole.name);
    });
    return series;
  }

  KnetWaveformFeatureSeries? _extractGroup(List<KnetWaveformChannel> channels) {
    if (channels.isEmpty) return null;
    final byComponent = _selectComponents(channels);
    if (byComponent.isEmpty) return null;

    final first = byComponent.values.first;
    final samplingHz = first.samplingHz;
    for (final channel in byComponent.values) {
      if ((channel.samplingHz - samplingHz).abs() > 1e-6) {
        throw FormatException(
          'Mixed sampling rates for ${first.stationCode}/${first.sensorRole.name}',
        );
      }
    }

    final sampleStart = byComponent.values
        .map((channel) => channel.sampleStartTimeUtc)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final sampleEnd = byComponent.values
        .map((channel) => _sampleEndTime(channel))
        .reduce((a, b) => a.isBefore(b) ? a : b);
    if (!sampleEnd.isAfter(sampleStart)) return null;

    final sampleCount = _durationToSamples(
      sampleEnd.difference(sampleStart),
      samplingHz,
    );
    final samplesPerSecond = samplingHz.round();
    if (sampleCount < samplesPerSecond || samplesPerSecond <= 0) {
      return null;
    }

    final componentValues = <String, List<double>>{};
    final qualityFlags = <String>{
      'offset_corrected_acceleration',
      'pgv_integrated_without_instrument_response_correction',
      'jma_intensity_unfiltered_duration_proxy',
    };
    for (final component in const ['NS', 'EW', 'UD']) {
      final channel = byComponent[component];
      if (channel == null) {
        qualityFlags.add('missing_${component.toLowerCase()}_component');
        continue;
      }
      final offset = _durationToSamples(
        sampleStart.difference(channel.sampleStartTimeUtc),
        samplingHz,
      );
      componentValues[component] = List<double>.generate(
        sampleCount,
        (index) => channel.accelerationGal[index + offset] - channel.offsetGal,
        growable: false,
      );
    }

    final secondCount = sampleCount ~/ samplesPerSecond;
    final velocities = <String, double>{
      for (final component in componentValues.keys) component: 0,
    };
    final rmsHistory = <double>[];
    final seconds = <KnetWaveformSecondFeature>[];
    final dt = 1.0 / samplingHz;

    for (var secondIndex = 0; secondIndex < secondCount; secondIndex++) {
      final startSample = secondIndex * samplesPerSecond;
      final endSample = startSample + samplesPerSecond;
      final vectorAcceleration = <double>[];
      double pgaGal = 0;
      double pgvCms = 0;
      double sumSquare = 0;
      double maxHorizontalGal = 0;

      for (var sample = startSample; sample < endSample; sample++) {
        final ns = componentValues['NS']?[sample] ?? 0;
        final ew = componentValues['EW']?[sample] ?? 0;
        final ud = componentValues['UD']?[sample] ?? 0;
        final horizontalGal = math.sqrt(ns * ns + ew * ew);
        final vectorGal = math.sqrt(horizontalGal * horizontalGal + ud * ud);
        vectorAcceleration.add(vectorGal);
        pgaGal = math.max(pgaGal, vectorGal);
        maxHorizontalGal = math.max(maxHorizontalGal, horizontalGal);
        sumSquare += vectorGal * vectorGal;

        for (final entry in componentValues.entries) {
          velocities[entry.key] =
              velocities[entry.key]! + entry.value[sample] * dt;
        }
        final nsVelocity = velocities['NS'] ?? 0;
        final ewVelocity = velocities['EW'] ?? 0;
        final udVelocity = velocities['UD'] ?? 0;
        pgvCms = math.max(
          pgvCms,
          math.sqrt(
            nsVelocity * nsVelocity +
                ewVelocity * ewVelocity +
                udVelocity * udVelocity,
          ),
        );
      }

      final rmsAccelerationGal = math.sqrt(sumSquare / samplesPerSecond);
      final baselineRms = _rollingMean(
        rmsHistory,
        config.energyBaselineSeconds,
      );
      final energyRatio = baselineRms == null || baselineRms <= config.epsilon
          ? null
          : rmsAccelerationGal / baselineRms;
      final jmaIntensityApprox = _durationProxyIntensity(
        vectorAcceleration,
        samplingHz,
        config.jmaDurationSeconds,
      );
      seconds.add(
        KnetWaveformSecondFeature(
          secondIndex: secondIndex,
          startTimeUtc: sampleStart.add(Duration(seconds: secondIndex)),
          pgaGal: pgaGal,
          maxHorizontalAccelerationGal: maxHorizontalGal,
          pgvCms: pgvCms,
          rmsAccelerationGal: rmsAccelerationGal,
          energyRatioToPreviousBaseline: energyRatio,
          jmaIntensityApprox: jmaIntensityApprox,
          qualityFlags: const [],
        ),
      );
      rmsHistory.add(rmsAccelerationGal);
    }

    return KnetWaveformFeatureSeries(
      stationCode: first.stationCode,
      network: first.network,
      sensorRole: first.sensorRole,
      stationLatitude: first.stationLatitude,
      stationLongitude: first.stationLongitude,
      sampleStartTimeUtc: sampleStart,
      samplingHz: samplingHz,
      sourcePaths:
          byComponent.values
              .map((channel) => channel.sourcePath)
              .whereType<String>()
              .toSet()
              .toList(growable: false)
            ..sort(),
      availableComponents: byComponent.keys.toList(growable: false)..sort(),
      seconds: seconds,
      qualityFlags: qualityFlags.toList(growable: false)..sort(),
      processingVersion: knetWaveformFeatureVersion,
    );
  }

  Map<String, KnetWaveformChannel> _selectComponents(
    List<KnetWaveformChannel> channels,
  ) {
    final byComponent = <String, KnetWaveformChannel>{};
    for (final channel in channels) {
      final current = byComponent[channel.component];
      if (current == null ||
          channel.sampleCount > current.sampleCount ||
          (channel.format == KnetWaveformFormat.ascii &&
              current.format != KnetWaveformFormat.ascii)) {
        byComponent[channel.component] = channel;
      }
    }
    return byComponent;
  }
}

class KnetFeatureConfig {
  const KnetFeatureConfig({
    this.jmaDurationSeconds = 0.3,
    this.energyBaselineSeconds = 10,
    this.epsilon = 1e-9,
  });

  final double jmaDurationSeconds;
  final int energyBaselineSeconds;
  final double epsilon;
}

class KnetWaveformFeatureSeries {
  const KnetWaveformFeatureSeries({
    required this.stationCode,
    required this.network,
    required this.sensorRole,
    required this.stationLatitude,
    required this.stationLongitude,
    required this.sampleStartTimeUtc,
    required this.samplingHz,
    required this.sourcePaths,
    required this.availableComponents,
    required this.seconds,
    required this.qualityFlags,
    required this.processingVersion,
  });

  final String stationCode;
  final KnetNetwork network;
  final KnetSensorRole sensorRole;
  final double stationLatitude;
  final double stationLongitude;
  final DateTime sampleStartTimeUtc;
  final double samplingHz;
  final List<String> sourcePaths;
  final List<String> availableComponents;
  final List<KnetWaveformSecondFeature> seconds;
  final List<String> qualityFlags;
  final String processingVersion;

  Map<String, Object?> toJson() => {
    'stationCode': stationCode,
    'network': network.name,
    'sensorRole': sensorRole.name,
    'stationLatitude': stationLatitude,
    'stationLongitude': stationLongitude,
    'sampleStartTimeUtc': sampleStartTimeUtc.toIso8601String(),
    'samplingHz': samplingHz,
    'sourcePaths': sourcePaths,
    'availableComponents': availableComponents,
    'qualityFlags': qualityFlags,
    'processingVersion': processingVersion,
    'seconds': seconds.map((second) => second.toJson()).toList(),
  };
}

class KnetWaveformSecondFeature {
  const KnetWaveformSecondFeature({
    required this.secondIndex,
    required this.startTimeUtc,
    required this.pgaGal,
    required this.maxHorizontalAccelerationGal,
    required this.pgvCms,
    required this.rmsAccelerationGal,
    required this.energyRatioToPreviousBaseline,
    required this.jmaIntensityApprox,
    required this.qualityFlags,
  });

  final int secondIndex;
  final DateTime startTimeUtc;
  final double pgaGal;
  final double maxHorizontalAccelerationGal;
  final double pgvCms;
  final double rmsAccelerationGal;
  final double? energyRatioToPreviousBaseline;
  final double? jmaIntensityApprox;
  final List<String> qualityFlags;

  Map<String, Object?> toJson() => {
    'secondIndex': secondIndex,
    'startTimeUtc': startTimeUtc.toIso8601String(),
    'pgaGal': pgaGal,
    'maxHorizontalAccelerationGal': maxHorizontalAccelerationGal,
    'pgvCms': pgvCms,
    'rmsAccelerationGal': rmsAccelerationGal,
    'energyRatioToPreviousBaseline': energyRatioToPreviousBaseline,
    'jmaIntensityApprox': jmaIntensityApprox,
    'qualityFlags': qualityFlags,
  };
}

class _WaveformGroupKey {
  const _WaveformGroupKey(this.stationCode, this.sensorRole);

  final String stationCode;
  final KnetSensorRole sensorRole;

  @override
  bool operator ==(Object other) =>
      other is _WaveformGroupKey &&
      other.stationCode == stationCode &&
      other.sensorRole == sensorRole;

  @override
  int get hashCode => Object.hash(stationCode, sensorRole);
}

DateTime _sampleEndTime(KnetWaveformChannel channel) {
  final milliseconds = (channel.sampleCount * 1000.0 / channel.samplingHz)
      .floor();
  return channel.sampleStartTimeUtc.add(Duration(milliseconds: milliseconds));
}

int _durationToSamples(Duration duration, double samplingHz) =>
    (duration.inMicroseconds * samplingHz / Duration.microsecondsPerSecond)
        .round();

double? _rollingMean(List<double> values, int window) {
  if (values.isEmpty || window <= 0) return null;
  final start = math.max(0, values.length - window);
  final slice = values.sublist(start);
  return slice.reduce((a, b) => a + b) / slice.length;
}

double? _durationProxyIntensity(
  List<double> vectorAccelerationGal,
  double samplingHz,
  double durationSeconds,
) {
  if (vectorAccelerationGal.isEmpty || samplingHz <= 0) return null;
  final durationSamples = math.max(1, (durationSeconds * samplingHz).ceil());
  final sorted = vectorAccelerationGal.toList(growable: false)
    ..sort((a, b) => b.compareTo(a));
  final threshold = sorted[math.min(sorted.length - 1, durationSamples - 1)];
  if (threshold <= 0) return null;
  return 2 * math.log(threshold) / math.ln10 + 0.94;
}
