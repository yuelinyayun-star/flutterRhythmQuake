import 'dart:math' as math;

import '../calculator.dart';

class SyntheticRevealBuildResult {
  final Map<String, Object?> manifest;
  final Map<String, Map<String, Object?>> datasetsBySplit;
  final Map<String, Object?> qualityReport;

  const SyntheticRevealBuildResult({
    required this.manifest,
    required this.datasetsBySplit,
    required this.qualityReport,
  });

  String qualityReportMarkdown() {
    final totals = qualityReport['totals']! as Map<String, Object?>;
    final bySplit = qualityReport['bySplit']! as Map<String, Object?>;
    final byMaskRate = qualityReport['byMaskRate']! as Map<String, Object?>;
    final buffer = StringBuffer()
      ..writeln('# Synthetic Reveal Quality Report')
      ..writeln()
      ..writeln('Dataset: `${qualityReport['datasetId']}`')
      ..writeln()
      ..writeln('## Totals')
      ..writeln()
      ..writeln('| Metric | Value |')
      ..writeln('| --- | ---: |');
    for (final entry in totals.entries) {
      buffer.writeln('| ${entry.key} | ${entry.value} |');
    }
    buffer
      ..writeln()
      ..writeln('## By Split')
      ..writeln()
      ..writeln('| Split | Events | Variants | Stations |')
      ..writeln('| --- | ---: | ---: | ---: |');
    for (final entry in bySplit.entries) {
      final values = entry.value! as Map<String, Object?>;
      buffer.writeln(
        '| ${entry.key} | ${values['events']} | '
        '${values['variants']} | ${values['stations']} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## By Mask Rate')
      ..writeln()
      ..writeln(
        '| Mask rate | Variants | Retained stations | Effective mask rate | S arrivals beyond reveal window |',
      )
      ..writeln('| ---: | ---: | ---: | ---: | ---: |');
    for (final entry in byMaskRate.entries) {
      final values = entry.value! as Map<String, Object?>;
      final effective = values['effectiveMaskRate']! as double;
      buffer.writeln(
        '| ${entry.key} | ${values['variants']} | '
        '${values['retainedStations']} | '
        '${(effective * 100).toStringAsFixed(2)}% | '
        '${values['stationsBeyondRevealWindow']} |',
      );
    }
    return buffer.toString();
  }
}

class SyntheticRevealDatasetBuilder {
  final List<double> maskRates;
  final List<String> generatedSplits;
  final int seed;
  final int minimumRetainedStations;
  final int maximumRevealSeconds;
  final double pWaveSpeedKmPerSec;
  final double sWaveSpeedKmPerSec;

  const SyntheticRevealDatasetBuilder({
    this.maskRates = const [0.2, 0.5, 0.8],
    this.generatedSplits = const ['train', 'validation'],
    this.seed = 20260621,
    this.minimumRetainedStations = 4,
    this.maximumRevealSeconds = 120,
    this.pWaveSpeedKmPerSec = 6.0,
    this.sWaveSpeedKmPerSec = 3.5,
  });

  SyntheticRevealBuildResult build({
    required Iterable<Map<String, Object?>> annualDatasets,
    required Map<String, Object?> splitManifest,
    DateTime? generatedAt,
  }) {
    _validateConfig();
    final eventsById = <String, Map<String, Object?>>{};
    for (final dataset in annualDatasets) {
      for (final rawEvent in dataset['events']! as List<Object?>) {
        final event = rawEvent! as Map<String, Object?>;
        final eventId = event['eventId']! as String;
        if (eventsById[eventId] != null) {
          throw FormatException('Duplicate annual event: $eventId');
        }
        eventsById[eventId] = event;
      }
    }

    final rawSplits = splitManifest['splits']! as Map<String, Object?>;
    final splitIds = <String, List<String>>{};
    final seenIds = <String>{};
    for (final entry in rawSplits.entries) {
      final ids = (entry.value! as List<Object?>).cast<String>();
      for (final eventId in ids) {
        if (!seenIds.add(eventId)) {
          throw FormatException('Event appears in multiple splits: $eventId');
        }
        if (eventsById[eventId] == null) {
          throw FormatException(
            'Split event missing from annual data: $eventId',
          );
        }
      }
      splitIds[entry.key] = ids;
    }

    final generatedAtIso = (generatedAt ?? DateTime.now())
        .toUtc()
        .toIso8601String();
    final sourceDatasetId = splitManifest['datasetId']! as String;
    final datasetId = '${sourceDatasetId}_synthetic_reveal_v1';
    final outputs = <String, Map<String, Object?>>{};
    final splitStats = <String, Map<String, Object?>>{};
    final rateStats = <String, _MaskRateStats>{
      for (final rate in maskRates) _rateKey(rate): _MaskRateStats(),
    };
    var totalEvents = 0;
    var totalVariants = 0;
    var totalStations = 0;

    for (final splitName in generatedSplits) {
      final generatedEvents = <Map<String, Object?>>[];
      var splitStations = 0;
      for (final eventId in splitIds[splitName] ?? const <String>[]) {
        final event = eventsById[eventId]!;
        final generatedEvent = _buildEvent(
          event,
          splitName: splitName,
          rateStats: rateStats,
        );
        generatedEvents.add(generatedEvent);
        splitStations += (generatedEvent['stations']! as List<Object?>).length;
      }
      final variantCount = generatedEvents.length * maskRates.length;
      outputs[splitName] = {
        'schemaVersion': 1,
        'datasetId': '${datasetId}_$splitName',
        'domain': 'synthetic_reveal',
        'split': splitName,
        'generatedAt': generatedAtIso,
        'processingVersion': 'station_mask_synthetic_reveal_v1',
        'sourceDatasetId': sourceDatasetId,
        'temporalSemantics':
            'theoretical_arrival_reveal_of_final_peak_intensity',
        'events': generatedEvents,
      };
      splitStats[splitName] = {
        'events': generatedEvents.length,
        'variants': variantCount,
        'stations': splitStations,
      };
      totalEvents += generatedEvents.length;
      totalVariants += variantCount;
      totalStations += splitStations;
    }

    final testIds = splitIds['test'] ?? const <String>[];
    final manifest = <String, Object?>{
      'schemaVersion': 1,
      'datasetId': datasetId,
      'domain': 'synthetic_reveal',
      'generatedAt': generatedAtIso,
      'processingVersion': 'station_mask_synthetic_reveal_v1',
      'sourceDatasetId': sourceDatasetId,
      'seed': seed,
      'maskRates': maskRates,
      'minimumRetainedStations': minimumRetainedStations,
      'maximumRevealSeconds': maximumRevealSeconds,
      'travelTimeModel': {
        'modelId': 'constant_velocity_hypocentral_v1',
        'pWaveSpeedKmPerSec': pWaveSpeedKmPerSec,
        'sWaveSpeedKmPerSec': sWaveSpeedKmPerSec,
      },
      'splitPolicy': {
        'generatedSplits': generatedSplits,
        'testDerivedSampleCount': generatedSplits.contains('test')
            ? (splitStats['test']?['variants'] as int? ?? 0)
            : 0,
        'frozenTestEventCount': testIds.length,
        'derivedSamplesInheritSourceSplit': true,
      },
      'outputs': {
        for (final splitName in generatedSplits)
          splitName: 'synthetic_reveal_$splitName.json',
      },
      'qualityFlags': [
        'synthetic_reveal',
        'final_peak_intensity_not_realtime_value',
        'theoretical_arrival_not_observed_pick',
      ],
    };
    final qualityReport = <String, Object?>{
      'schemaVersion': 1,
      'datasetId': datasetId,
      'generatedAt': generatedAtIso,
      'totals': {
        'sourceEvents': totalEvents,
        'generatedVariants': totalVariants,
        'sourceStations': totalStations,
        'frozenTestEvents': testIds.length,
        'testDerivedSamples': generatedSplits.contains('test')
            ? (splitStats['test']?['variants'] as int? ?? 0)
            : 0,
      },
      'bySplit': splitStats,
      'byMaskRate': {
        for (final entry in rateStats.entries) entry.key: entry.value.toJson(),
      },
    };
    return SyntheticRevealBuildResult(
      manifest: manifest,
      datasetsBySplit: outputs,
      qualityReport: qualityReport,
    );
  }

  Map<String, Object?> _buildEvent(
    Map<String, Object?> event, {
    required String splitName,
    required Map<String, _MaskRateStats> rateStats,
  }) {
    final eventId = event['eventId']! as String;
    final hypocenter = event['preferredHypocenter']! as Map<String, Object?>;
    final latitude = (hypocenter['latitude']! as num).toDouble();
    final longitude = (hypocenter['longitude']! as num).toDouble();
    final depthKm = (hypocenter['depthKm']! as num).toDouble();
    final stations = <Map<String, Object?>>[];
    for (final rawObservation in event['observations']! as List<Object?>) {
      final observation = rawObservation! as Map<String, Object?>;
      final stationLatitude = _number(observation['latitude']);
      final stationLongitude = _number(observation['longitude']);
      final intensity = _number(observation['instrumentalIntensity']);
      if (stationLatitude == null ||
          stationLongitude == null ||
          intensity == null) {
        continue;
      }
      final surfaceDistanceKm = QuakeCalculator.haversineDistance(
        latitude,
        longitude,
        stationLatitude,
        stationLongitude,
      );
      final hypocentralDistanceKm = math.sqrt(
        surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
      );
      stations.add({
        'stationId': observation['stationId'],
        'latitude': stationLatitude,
        'longitude': stationLongitude,
        'instrumentalIntensity': intensity,
        'intensityClass': observation['intensityClass'],
        'surfaceDistanceKm': surfaceDistanceKm,
        'theoreticalPArrivalSeconds':
            hypocentralDistanceKm / pWaveSpeedKmPerSec,
        'theoreticalSArrivalSeconds':
            hypocentralDistanceKm / sWaveSpeedKmPerSec,
        'qualityFlags': [
          'jma_final_peak_intensity',
          'theoretical_arrival_not_observed_pick',
        ],
      });
    }
    stations.sort(
      (left, right) => (left['stationId']! as String).compareTo(
        right['stationId']! as String,
      ),
    );

    final rankedStationIds =
        stations.map((station) => station['stationId']! as String).toList()
          ..sort((left, right) {
            final leftHash = _stableHash('$seed|$eventId|$left');
            final rightHash = _stableHash('$seed|$eventId|$right');
            final order = leftHash.compareTo(rightHash);
            return order != 0 ? order : left.compareTo(right);
          });
    final stationById = {
      for (final station in stations) station['stationId']! as String: station,
    };

    final variants = <Map<String, Object?>>[];
    for (final maskRate in maskRates) {
      final desiredRetained = (stations.length * (1 - maskRate)).round();
      final retainedCount = desiredRetained
          .clamp(
            math.min(minimumRetainedStations, stations.length),
            stations.length,
          )
          .toInt();
      final retainedIds = rankedStationIds
          .take(retainedCount)
          .toList(growable: false);
      final retained = [for (final id in retainedIds) stationById[id]!];
      final framesBySecond = <int, _RevealFrame>{};
      var beyondWindow = 0;
      for (final station in retained) {
        final stationId = station['stationId']! as String;
        final pSecond = (station['theoreticalPArrivalSeconds']! as double)
            .ceil();
        final sSecond = (station['theoreticalSArrivalSeconds']! as double)
            .ceil();
        if (pSecond <= maximumRevealSeconds) {
          framesBySecond
              .putIfAbsent(pSecond, () => _RevealFrame(pSecond))
              .pStationIds
              .add(stationId);
        }
        if (sSecond <= maximumRevealSeconds) {
          framesBySecond
              .putIfAbsent(sSecond, () => _RevealFrame(sSecond))
              .sStationIds
              .add(stationId);
        } else {
          beyondWindow++;
        }
      }
      final frames = framesBySecond.values.toList()
        ..sort(
          (left, right) => left.elapsedSeconds.compareTo(right.elapsedSeconds),
        );
      final effectiveMaskRate = stations.isEmpty
          ? 0.0
          : 1 - retainedCount / stations.length;
      rateStats[_rateKey(maskRate)]!.add(
        sourceStationCount: stations.length,
        retainedStationCount: retainedCount,
        stationsBeyondRevealWindow: beyondWindow,
      );
      variants.add({
        'variantId': '${eventId}_mask_${_rateKey(maskRate)}',
        'sourceEventId': eventId,
        'split': splitName,
        'domain': 'synthetic_reveal',
        'requestedMaskRate': maskRate,
        'effectiveMaskRate': effectiveMaskRate,
        'retainedStationIds': retainedIds,
        'maskedStationCount': stations.length - retainedCount,
        'stationsBeyondRevealWindow': beyondWindow,
        'revealFrames': [for (final frame in frames) frame.toJson()],
        'qualityFlags': [
          'synthetic_reveal',
          'deterministic_station_mask',
          'final_peak_intensity_not_realtime_value',
        ],
      });
    }

    return {
      'eventId': eventId,
      'split': splitName,
      'truth': {
        'originTime': hypocenter['originTime'],
        'latitude': latitude,
        'longitude': longitude,
        'depthKm': depthKm,
        'magnitude': hypocenter['magnitude'],
      },
      'stations': stations,
      'variants': variants,
    };
  }

  void _validateConfig() {
    if (maskRates.isEmpty) throw ArgumentError('maskRates must not be empty.');
    if (generatedSplits.isEmpty) {
      throw ArgumentError('generatedSplits must not be empty.');
    }
    final seenSplits = <String>{};
    for (final split in generatedSplits) {
      if (!seenSplits.add(split)) {
        throw ArgumentError.value(split, 'generatedSplits', 'duplicate split');
      }
      if (split != 'train' && split != 'validation' && split != 'test') {
        throw ArgumentError.value(
          split,
          'generatedSplits',
          'unsupported split',
        );
      }
    }
    for (final rate in maskRates) {
      if (!rate.isFinite || rate < 0 || rate >= 1) {
        throw ArgumentError.value(rate, 'maskRates', 'must be in [0, 1).');
      }
    }
    if (minimumRetainedStations < 1) {
      throw ArgumentError.value(minimumRetainedStations);
    }
    if (maximumRevealSeconds < 1) {
      throw ArgumentError.value(maximumRevealSeconds);
    }
  }

  static double? _number(Object? value) =>
      value is num && value.isFinite ? value.toDouble() : null;

  static String _rateKey(double rate) =>
      '${(rate * 100).round().toString().padLeft(2, '0')}pct';

  static int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final byte in value.codeUnits) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}

class _RevealFrame {
  final int elapsedSeconds;
  final List<String> pStationIds = [];
  final List<String> sStationIds = [];

  _RevealFrame(this.elapsedSeconds);

  Map<String, Object?> toJson() {
    pStationIds.sort();
    sStationIds.sort();
    return {
      'elapsedSeconds': elapsedSeconds,
      'newPStationIds': pStationIds,
      'newSStationIds': sStationIds,
    };
  }
}

class _MaskRateStats {
  int variants = 0;
  int sourceStations = 0;
  int retainedStations = 0;
  int stationsBeyondRevealWindow = 0;

  void add({
    required int sourceStationCount,
    required int retainedStationCount,
    required int stationsBeyondRevealWindow,
  }) {
    variants++;
    sourceStations += sourceStationCount;
    retainedStations += retainedStationCount;
    this.stationsBeyondRevealWindow += stationsBeyondRevealWindow;
  }

  Map<String, Object?> toJson() => {
    'variants': variants,
    'sourceStations': sourceStations,
    'retainedStations': retainedStations,
    'stationsBeyondRevealWindow': stationsBeyondRevealWindow,
    'effectiveMaskRate': sourceStations == 0
        ? 0.0
        : 1 - retainedStations / sourceStations,
  };
}
