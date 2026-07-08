import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/event_detection/event_detection_models.dart';
import 'package:flutterrhythmquake/core/event_detection/robust_station_trigger_detector.dart';
import 'package:flutterrhythmquake/core/event_detection/spatiotemporal_event_detector.dart';
import 'package:flutterrhythmquake/core/source_estimation/seismic_source_tracker.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_trigger.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimator.dart';
import 'package:flutterrhythmquake/models/nied_scan_positions.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_observation.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_value_decoder.dart';
import 'package:flutterrhythmquake/services/sources/shindo_color_util.dart';
import 'package:image/image.dart' as image_lib;
import 'package:latlong2/latlong.dart';

void main(List<String> args) {
  evaluateNiedMultilayerGain(args);
}

void evaluateNiedMultilayerGain(List<String> args) {
  final capturePath = _argument(args, '--capture');
  final truthPath = _argument(args, '--truth');
  final outputPath = _argument(args, '--output');
  final markdownPath = _argument(args, '--markdown');
  if (capturePath == null || truthPath == null || outputPath == null) {
    stderr.writeln(
      'Usage: dart run tools/evaluate_nied_multilayer_gain.dart '
      '--capture <directory> --truth <fixture.json> --output <report.json> '
      '[--markdown <report.md>]',
    );
    exitCode = 64;
    return;
  }

  final capture = Directory(capturePath);
  final manifest =
      jsonDecode(
            File(
              '${capture.path}${Platform.pathSeparator}capture_manifest.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  final truthFixture =
      jsonDecode(File(truthPath).readAsStringSync()) as Map<String, Object?>;
  final truth = truthFixture['truth']! as Map<String, Object?>;
  final originTime = DateTime.parse(
    truthFixture['originTime']! as String,
  ).toUtc();
  final truthLatitude = _number(truth['latitude']);
  final truthLongitude = _number(truth['longitude']);

  final recordsByTime = <DateTime, Map<String, Map<String, Object?>>>{};
  for (final record
      in (manifest['records']! as List<Object?>).cast<Map<String, Object?>>()) {
    if (record['ok'] != true) continue;
    final observedAt = DateTime.parse(record['observedAt']! as String).toUtc();
    recordsByTime.putIfAbsent(
      observedAt,
      () => {},
    )[record['layer']! as String] = record;
  }
  final timestamps = recordsByTime.keys.toList(growable: false)..sort();
  final stationMetadata = _stationMetadata();
  final stationDetectors = <String, RobustStationTriggerDetector>{};
  final eventDetector = SpatiotemporalEventDetector(
    detectorId: 'multilayer_gain_event_detector_v2',
    sourceId: 'nied_multilayer_gain',
    config: const SpatiotemporalEventDetectorConfig(
      candidateMinStations: 4,
      confirmedMinStations: 5,
    ),
  );
  const sourceGate = SourceEstimationTriggerGate();
  final jmaTracker = SeismicSourceTracker()
    ..setEstimator('jma_only', const NiedGifHybridSourceEstimator());
  final physicalTracker = SeismicSourceTracker()
    ..setEstimator(
      'jma_physical',
      const NiedGifPhysicalFusionExperimentalEstimator(),
    );
  final jmaEstimates = <_TimedEstimate>[];
  final physicalEstimates = <_TimedEstimate>[];
  final stationSignalDiagnostics = <String, _StationSignalDiagnostic>{};
  final triggerDiagnostics = <Map<String, Object?>>[];
  var decodedFrames = 0;
  var completePhysicalStationSeconds = 0;
  var triggeredFrameCount = 0;
  String? associatedEventId;
  final associatedStationIds = <String>{};

  for (final timestamp in timestamps) {
    final images = _decodeImages(capture, recordsByTime[timestamp]!);
    final observations = <StationObservationFrame>[];
    final jmaSamples = <SeismicStationSample>[];
    final physicalSamples = <SeismicStationSample>[];
    var maxRawLevel = -1;
    for (final station in stationMetadata) {
      final suffix = station.sensorRole == StationSensorRole.borehole
          ? 'b'
          : 's';
      final jmaPosition = _positionAt(
        images['jma_$suffix'],
        station.pixelX,
        station.pixelY,
      );
      final shindo = jmaPosition == null ? null : 10 * jmaPosition - 3;
      final rawLevel = shindo == null
          ? null
          : ShindoColorUtil.shindoToRawLevel(shindo);
      if (rawLevel != null) maxRawLevel = math.max(maxRawLevel, rawLevel);
      final observation = StationObservationFrame(
        stationId: station.code,
        code: station.code,
        sourceId: 'nied_multilayer_gain',
        observedAt: timestamp,
        latitude: station.latitude,
        longitude: station.longitude,
        intensity: shindo,
        rawLevel: rawLevel,
        detectLevel: rawLevel,
        sensorRole: station.sensorRole == StationSensorRole.borehole
            ? ObservationSensorRole.borehole
            : ObservationSensorRole.surface,
        qualityFlags: {
          if (jmaPosition == null) 'pixel_undecodable',
          'gif_layer:jma',
        },
      );
      observations.add(observation);
      stationSignalDiagnostics
          .putIfAbsent(
            station.code,
            () => _StationSignalDiagnostic(station: station),
          )
          .add(
            timestamp: timestamp,
            originTime: originTime,
            rawLevel: rawLevel,
          );
    }

    final triggers = <StationTriggerSnapshot>[];
    for (final observation in observations) {
      final detector = stationDetectors.putIfAbsent(
        observation.stationId,
        () => RobustStationTriggerDetector(
          detectorId: 'multilayer_station_trigger_v1',
        ),
      );
      triggers.add(detector.update(observation));
    }
    final detection = eventDetector.update(
      observedAt: timestamp,
      stations: triggers,
    );
    final networkDiagnostics = eventDetector.diagnose(triggers);
    triggerDiagnostics.add({
      'observedAt': timestamp.toIso8601String(),
      'risingCount': triggers
          .where((trigger) => trigger.state == StationTriggerState.rising)
          .length,
      'triggeredCount': triggers
          .where((trigger) => trigger.state == StationTriggerState.triggered)
          .length,
      'strongCount': triggers
          .where((trigger) => trigger.state == StationTriggerState.strong)
          .length,
      'largestComponentSize': networkDiagnostics.largestComponentSize,
      'largestComponentStationIds':
          networkDiagnostics.largestComponentStationIds,
      'largestComponentCentroidLatitude':
          networkDiagnostics.largestComponentCentroidLatitude,
      'largestComponentCentroidLongitude':
          networkDiagnostics.largestComponentCentroidLongitude,
    });
    final gate = sourceGate.evaluate(detection);
    if (gate.shouldRunEstimator) triggeredFrameCount++;
    if (detection.eventId != null && detection.eventId != associatedEventId) {
      associatedEventId = detection.eventId;
      associatedStationIds.clear();
    }
    associatedStationIds.addAll(detection.memberStationIds);

    for (var index = 0; index < stationMetadata.length; index++) {
      final station = stationMetadata[index];
      final observation = observations[index];
      final trigger = triggers[index];
      final suffix = station.sensorRole == StationSensorRole.borehole
          ? 'b'
          : 's';
      final pga = _physicalValue(
        images['acmap_$suffix'],
        station,
        NiedGifLayer.peakAcceleration,
      );
      final pgv = _physicalValue(
        images['vcmap_$suffix'],
        station,
        NiedGifLayer.peakVelocity,
      );
      final pgd = _physicalValue(
        images['dcmap_$suffix'],
        station,
        NiedGifLayer.peakDisplacement,
      );
      if (observation.intensity != null &&
          pga != null &&
          pgv != null &&
          pgd != null) {
        completePhysicalStationSeconds++;
      }
      final descriptor = SeismicStationDescriptor(
        stationId: station.code,
        code: station.code,
        sourceId: 'nied_multilayer_gain',
        network: station.network,
        coordinate: LatLng(station.latitude, station.longitude),
        sensorRole: station.sensorRole,
      );
      final common = SeismicStationSample(
        descriptor: descriptor,
        observedAt: timestamp,
        receivedAt: timestamp,
        valueType: StationValueType.jmaShindo,
        value: observation.intensity,
        rawLevel: observation.rawLevel,
        detectLevel: observation.detectLevel,
        activity: trigger.activity,
        ascend: trigger.ascend,
        isTriggered:
            trigger.state == StationTriggerState.triggered ||
            trigger.state == StationTriggerState.strong,
        firstRiseInterval: trigger.firstRiseInterval,
        firstTriggerInterval: trigger.firstTriggerInterval,
        qualityFlags: observation.qualityFlags,
        provenance: const {
          StationValueType.jmaShindo: ObservationProvenance(
            origin: ObservationOrigin.niedGifLayer,
            quantity: StationValueType.jmaShindo,
            layerId: 'jma',
            isIndependentPhysicalMeasurement: true,
          ),
        },
      );
      jmaSamples.add(common);
      physicalSamples.add(
        SeismicStationSample(
          descriptor: descriptor,
          observedAt: timestamp,
          receivedAt: timestamp,
          valueType: StationValueType.jmaShindo,
          value: observation.intensity,
          observedPga: pga,
          observedPgv: pgv,
          observedPgd: pgd,
          rawLevel: observation.rawLevel,
          detectLevel: observation.detectLevel,
          activity: trigger.activity,
          ascend: trigger.ascend,
          isTriggered:
              trigger.state == StationTriggerState.triggered ||
              trigger.state == StationTriggerState.strong,
          firstRiseInterval: trigger.firstRiseInterval,
          firstTriggerInterval: trigger.firstTriggerInterval,
          qualityFlags: observation.qualityFlags,
          provenance: {
            ...common.provenance,
            if (pga != null)
              StationValueType.pga: const ObservationProvenance(
                origin: ObservationOrigin.niedGifLayer,
                quantity: StationValueType.pga,
                layerId: 'acmap',
                isIndependentPhysicalMeasurement: true,
              ),
            if (pgv != null)
              StationValueType.pgv: const ObservationProvenance(
                origin: ObservationOrigin.niedGifLayer,
                quantity: StationValueType.pgv,
                layerId: 'vcmap',
                isIndependentPhysicalMeasurement: true,
              ),
            if (pgd != null)
              StationValueType.pgd: const ObservationProvenance(
                origin: ObservationOrigin.niedGifLayer,
                quantity: StationValueType.pgd,
                layerId: 'dcmap',
                isIndependentPhysicalMeasurement: true,
              ),
          },
        ),
      );
    }

    final stage = gate.stageName;
    _ingestAndCollect(
      tracker: jmaTracker,
      sourceId: 'jma_only',
      timestamp: timestamp,
      stage: stage,
      maxRawLevel: maxRawLevel,
      samples: jmaSamples,
      eventId: gate.eventId,
      estimates: jmaEstimates,
      truthLatitude: truthLatitude,
      truthLongitude: truthLongitude,
      metadata: {
        'nied_input_kind': 'gif',
        'evaluation_gate': 'independent_source_trigger_v2',
        'source_trigger_member_ids': List<String>.unmodifiable(
          associatedStationIds,
        ),
        ...gate.metadata,
      },
    );
    _ingestAndCollect(
      tracker: physicalTracker,
      sourceId: 'jma_physical',
      timestamp: timestamp,
      stage: stage,
      maxRawLevel: maxRawLevel,
      samples: physicalSamples,
      eventId: gate.eventId,
      estimates: physicalEstimates,
      truthLatitude: truthLatitude,
      truthLongitude: truthLongitude,
      metadata: {
        'nied_input_kind': 'gif',
        'evaluation_gate': 'independent_source_trigger_v2',
        'source_trigger_member_ids': List<String>.unmodifiable(
          associatedStationIds,
        ),
        ...gate.metadata,
      },
    );
    decodedFrames++;
  }

  final jmaSummary = _summarize(jmaEstimates, originTime);
  final physicalSummary = _summarize(physicalEstimates, originTime);
  final report = <String, Object?>{
    'schemaVersion': 'nied_multilayer_gain_evaluation_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'caseId': truthFixture['caseId'],
    'captureDirectory': capturePath,
    'truthPath': truthPath,
    'truth': truth,
    'originTimeUtc': originTime.toIso8601String(),
    'splitStatus': truthFixture['splitStatus'],
    'policy': const {
      'pairedFrames': true,
      'jmaOnlyMethod': 'nied_gif_hybrid_v1',
      'physicalMethod': 'nied_gif_physical_fusion_experimental_v1',
      'physicalWeights': {'pga': 0.35, 'pgv': 0.20, 'pgd': 0.10},
      'weightsTunedOnThisEvent': false,
      'productionEnabled': false,
      'localizationGate': 'independent_source_trigger_v2',
      'sourceConfirmedMinStations': 5,
    },
    'frameCount': timestamps.length,
    'decodedFrameCount': decodedFrames,
    'triggeredFrameCount': triggeredFrameCount,
    'sourceTriggerMissedEvent': triggeredFrameCount == 0,
    'completePhysicalStationSecondCount': completePhysicalStationSeconds,
    'diagnostics': {
      'triggerFrames': triggerDiagnostics,
      'topStationRawLevelChanges': _topStationChanges(
        stationSignalDiagnostics.values,
      ),
    },
    'methods': {'jmaOnly': jmaSummary, 'jmaPhysical': physicalSummary},
    'deltaPhysicalMinusJma': _delta(jmaSummary, physicalSummary),
    'limitations': const [
      'single_event_development_evaluation',
      'unassigned_reference_not_frozen_test',
      'no_parameter_tuning_allowed',
      'physical_fusion_not_enabled_in_production',
      'source_trigger_threshold_requires_noise_window_validation',
    ],
  };
  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  if (markdownPath != null) {
    final markdown = File(markdownPath)..parent.createSync(recursive: true);
    markdown.writeAsStringSync(_markdown(report));
  }
  stdout.writeln('wrote paired gain evaluation to $outputPath');
}

void _ingestAndCollect({
  required SeismicSourceTracker tracker,
  required String sourceId,
  required DateTime timestamp,
  required String stage,
  required int maxRawLevel,
  required List<SeismicStationSample> samples,
  required String? eventId,
  required List<_TimedEstimate> estimates,
  required double truthLatitude,
  required double truthLongitude,
  required Map<String, Object?> metadata,
}) {
  tracker.ingestFrame(
    sourceId: sourceId,
    observedAt: timestamp,
    stageName: stage,
    maxShindo: maxRawLevel,
    samples: samples,
    eventId: eventId,
    metadata: metadata,
  );
  final estimate = tracker.currentEvent(sourceId)?.estimate;
  if (estimate == null) return;
  estimates.add(
    _TimedEstimate(
      timestamp: timestamp,
      errorKm: _haversineKm(
        truthLatitude,
        truthLongitude,
        estimate.latitude,
        estimate.longitude,
      ),
      latitude: estimate.latitude,
      longitude: estimate.longitude,
      supportingStationCount: estimate.supportingStationCount,
      method: estimate.method,
      diagnostics: estimate.diagnostics,
    ),
  );
}

Map<String, Object?> _summarize(
  List<_TimedEstimate> estimates,
  DateTime originTime,
) {
  final postOrigin = estimates
      .where((estimate) => !estimate.timestamp.isBefore(originTime))
      .toList(growable: false);
  final jumps = <double>[];
  for (var index = 1; index < postOrigin.length; index++) {
    jumps.add(
      _haversineKm(
        postOrigin[index - 1].latitude,
        postOrigin[index - 1].longitude,
        postOrigin[index].latitude,
        postOrigin[index].longitude,
      ),
    );
  }
  final first = postOrigin.isEmpty ? null : postOrigin.first;
  final last = postOrigin.isEmpty ? null : postOrigin.last;
  return {
    'estimateCount': postOrigin.length,
    'firstEstimateDelaySeconds': first == null
        ? null
        : first.timestamp.difference(originTime).inMilliseconds / 1000.0,
    'firstEstimateErrorKm': first?.errorKm,
    'errorAt5SecondsKm': _errorAt(postOrigin, originTime, 5),
    'errorAt10SecondsKm': _errorAt(postOrigin, originTime, 10),
    'finalEstimateErrorKm': last?.errorKm,
    'medianErrorKm': _percentile(
      postOrigin.map((value) => value.errorKm).toList(growable: false),
      0.5,
    ),
    'p90ErrorKm': _percentile(
      postOrigin.map((value) => value.errorKm).toList(growable: false),
      0.9,
    ),
    'medianJumpKm': _percentile(jumps, 0.5),
    'p90JumpKm': _percentile(jumps, 0.9),
    'firstEstimate': first?.toJson(),
    'estimateAt5Seconds': _estimateAt(postOrigin, originTime, 5)?.toJson(),
    'estimateAt10Seconds': _estimateAt(postOrigin, originTime, 10)?.toJson(),
    'finalEstimate': last?.toJson(),
  };
}

Map<String, Object?> _delta(
  Map<String, Object?> jma,
  Map<String, Object?> physical,
) {
  const keys = [
    'firstEstimateErrorKm',
    'errorAt5SecondsKm',
    'errorAt10SecondsKm',
    'finalEstimateErrorKm',
    'medianErrorKm',
    'p90ErrorKm',
    'medianJumpKm',
    'p90JumpKm',
  ];
  return {
    for (final key in keys)
      key: jma[key] is num && physical[key] is num
          ? (physical[key]! as num).toDouble() - (jma[key]! as num).toDouble()
          : null,
  };
}

double? _errorAt(
  List<_TimedEstimate> estimates,
  DateTime originTime,
  int seconds,
) {
  final target = originTime.add(Duration(seconds: seconds));
  for (final estimate in estimates) {
    if (estimate.timestamp == target) return estimate.errorKm;
  }
  return null;
}

_TimedEstimate? _estimateAt(
  List<_TimedEstimate> estimates,
  DateTime originTime,
  int seconds,
) {
  final target = originTime.add(Duration(seconds: seconds));
  for (final estimate in estimates) {
    if (estimate.timestamp == target) return estimate;
  }
  return null;
}

List<_StationMetadata> _stationMetadata() {
  final result = <_StationMetadata>[];
  for (final station in NiedStationDb.stations) {
    final code = station['code'] as String;
    final position = NiedScanPositions.positions[code];
    if (position == null) continue;
    final network = station['network'] as String? ?? 'K-NET';
    result.add(
      _StationMetadata(
        code: code,
        network: network,
        latitude: _number(station['lat']),
        longitude: _number(station['lng']),
        pixelX: position[0],
        pixelY: position[1],
        sensorRole: StationSensorRole.surface,
      ),
    );
  }
  return result;
}

Map<String, image_lib.Image> _decodeImages(
  Directory capture,
  Map<String, Map<String, Object?>> records,
) {
  final result = <String, image_lib.Image>{};
  for (final entry in records.entries) {
    final file = File(
      '${capture.path}${Platform.pathSeparator}${entry.value['file']}',
    );
    final image = image_lib.decodeImage(file.readAsBytesSync());
    if (image != null) result[entry.key] = image;
  }
  return result;
}

double? _positionAt(image_lib.Image? image, int x, int y) {
  if (image == null ||
      x < 0 ||
      y < 0 ||
      x >= image.width ||
      y >= image.height) {
    return null;
  }
  final pixel = image.getPixel(x, y);
  return ShindoColorUtil.rgbaToPosition(
    pixel.r.toInt(),
    pixel.g.toInt(),
    pixel.b.toInt(),
  );
}

double? _physicalValue(
  image_lib.Image? image,
  _StationMetadata station,
  NiedGifLayer layer,
) {
  final position = _positionAt(image, station.pixelX, station.pixelY);
  if (position == null) return null;
  final observation = NiedGifValueDecoder.decodeObservationFromPosition(
    position,
    layer: layer,
  );
  return switch (layer) {
    NiedGifLayer.peakAcceleration => observation.pga,
    NiedGifLayer.peakVelocity => observation.pgv,
    NiedGifLayer.peakDisplacement => observation.pgd,
    _ => null,
  };
}

String _markdown(Map<String, Object?> report) {
  final methods = report['methods']! as Map<String, Object?>;
  final jma = methods['jmaOnly']! as Map<String, Object?>;
  final physical = methods['jmaPhysical']! as Map<String, Object?>;
  final delta = report['deltaPhysicalMinusJma']! as Map<String, Object?>;
  final buffer = StringBuffer()
    ..writeln('# NIED Multilayer Gain Evaluation')
    ..writeln()
    ..writeln('- Case: `${report['caseId']}`')
    ..writeln('- Split: `${report['splitStatus']}`')
    ..writeln(
      '- Frames: ${report['decodedFrameCount']}/${report['frameCount']}',
    )
    ..writeln(
      '- Source trigger missed event: `${report['sourceTriggerMissedEvent']}`',
    )
    ..writeln('- Localization gate: `independent source trigger v2`')
    ..writeln('- Production enabled: `false`')
    ..writeln()
    ..writeln('| Metric | JMA only | JMA + physical | Delta |')
    ..writeln('|---|---:|---:|---:|');
  const metrics = {
    'firstEstimateErrorKm': 'First error',
    'errorAt5SecondsKm': 'Error at +5s',
    'errorAt10SecondsKm': 'Error at +10s',
    'finalEstimateErrorKm': 'Final error',
    'medianErrorKm': 'Median error',
    'p90ErrorKm': 'P90 error',
    'medianJumpKm': 'Median jump',
    'p90JumpKm': 'P90 jump',
  };
  for (final entry in metrics.entries) {
    buffer.writeln(
      '| ${entry.value} | ${_format(jma[entry.key])} | '
      '${_format(physical[entry.key])} | ${_format(delta[entry.key])} |',
    );
  }
  buffer
    ..writeln()
    ..writeln(
      'Negative delta means the fixed experimental physical fusion was better. '
      'This single unassigned event cannot be used for production tuning.',
    );
  return buffer.toString();
}

String _format(Object? value) =>
    value is num ? '${value.toStringAsFixed(2)} km' : '-';

double? _percentile(List<double> values, double percentile) {
  if (values.isEmpty) return null;
  final sorted = values.toList(growable: false)..sort();
  final position = percentile * (sorted.length - 1);
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];
  return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
}

double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const radius = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _number(Object? value) => (value! as num).toDouble();

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

class _StationMetadata {
  const _StationMetadata({
    required this.code,
    required this.network,
    required this.latitude,
    required this.longitude,
    required this.pixelX,
    required this.pixelY,
    required this.sensorRole,
  });

  final String code;
  final String network;
  final double latitude;
  final double longitude;
  final int pixelX;
  final int pixelY;
  final StationSensorRole sensorRole;
}

class _TimedEstimate {
  const _TimedEstimate({
    required this.timestamp,
    required this.errorKm,
    required this.latitude,
    required this.longitude,
    required this.supportingStationCount,
    required this.method,
    required this.diagnostics,
  });

  final DateTime timestamp;
  final double errorKm;
  final double latitude;
  final double longitude;
  final int supportingStationCount;
  final String method;
  final Map<String, Object?> diagnostics;

  Map<String, Object?> toJson() => {
    'observedAt': timestamp.toIso8601String(),
    'errorKm': errorKm,
    'latitude': latitude,
    'longitude': longitude,
    'supportingStationCount': supportingStationCount,
    'method': method,
    'diagnostics': diagnostics,
  };
}

class _StationSignalDiagnostic {
  _StationSignalDiagnostic({required this.station});

  final _StationMetadata station;
  final List<int> _baseline = [];
  final List<int> _postOrigin = [];
  DateTime? _postPeakAt;
  int? _postPeak;

  void add({
    required DateTime timestamp,
    required DateTime originTime,
    required int? rawLevel,
  }) {
    if (rawLevel == null) return;
    if (timestamp.isBefore(originTime)) {
      _baseline.add(rawLevel);
      return;
    }
    if (timestamp.isAfter(originTime.add(const Duration(seconds: 30)))) {
      return;
    }
    _postOrigin.add(rawLevel);
    if (_postPeak == null || rawLevel > _postPeak!) {
      _postPeak = rawLevel;
      _postPeakAt = timestamp;
    }
  }

  Map<String, Object?> toJson() {
    final baselineMedian = _medianInt(_baseline);
    return {
      'code': station.code,
      'network': station.network,
      'latitude': station.latitude,
      'longitude': station.longitude,
      'baselineSampleCount': _baseline.length,
      'postOriginSampleCount': _postOrigin.length,
      'baselineMedianRawLevel': baselineMedian,
      'postOriginPeakRawLevel': _postPeak,
      'postOriginPeakAt': _postPeakAt?.toIso8601String(),
      'rawLevelDelta': baselineMedian == null || _postPeak == null
          ? null
          : _postPeak! - baselineMedian,
    };
  }
}

double? _medianInt(List<int> values) {
  if (values.isEmpty) return null;
  final sorted = values.toList(growable: false)..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle].toDouble();
  return (sorted[middle - 1] + sorted[middle]) / 2.0;
}

List<Map<String, Object?>> _topStationChanges(
  Iterable<_StationSignalDiagnostic> diagnostics, {
  int limit = 50,
}) {
  final rows = diagnostics
      .map((diagnostic) => diagnostic.toJson())
      .where((diagnostic) => diagnostic['rawLevelDelta'] != null)
      .toList(growable: false);
  rows.sort(
    (a, b) => ((b['rawLevelDelta'] as num?) ?? -999).compareTo(
      (a['rawLevelDelta'] as num?) ?? -999,
    ),
  );
  return rows.take(limit).toList(growable: false);
}
