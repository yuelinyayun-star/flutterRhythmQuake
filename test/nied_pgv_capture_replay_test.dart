import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_event_tracker.dart';
import 'package:flutterrhythmquake/core/source_estimation/jshis_surface_structure_api.dart';
import 'package:flutterrhythmquake/core/source_estimation/nied_pgv_magnitude_diagnostics.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimator.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_observation.dart';
import 'package:flutterrhythmquake/services/sources/nied_source_estimation_driver.dart';

import 'support/nied_replay_fixture.dart';

void main() {
  test(
    'replays a complete surface multilayer P2P capture into PGV diagnostics',
    () async {
      const captureOverride = String.fromEnvironment('PGV_CAPTURE_DIRECTORY');
      const estimatorMode = String.fromEnvironment(
        'PGV_REPLAY_ESTIMATOR',
        defaultValue: 'default_dart_hyp',
      );
      const sourceGeometryMode = String.fromEnvironment(
        'PGV_REPLAY_SOURCE_GEOMETRY',
        defaultValue: 'dart_hyp',
      );
      const jshisArvManifestPath = String.fromEnvironment(
        'PGV_JSHIS_ARV_MANIFEST',
      );
      const nearestStationSweepRaw = String.fromEnvironment(
        'PGV_REPLAY_NEAREST_STATION_SWEEP',
      );
      const enableSArrivalWindowDiagnostic = bool.fromEnvironment(
        'PGV_REPLAY_S_WINDOW_DIAGNOSTIC',
      );
      final capture = Directory(
        captureOverride.isEmpty
            ? 'tmp/captures/p2p_20260802_010700_m45_6bf0ad'
            : captureOverride,
      );
      final manifestFile = File(
        '${capture.path}${Platform.pathSeparator}capture_manifest.json',
      );
      expect(
        manifestFile.existsSync(),
        isTrue,
        reason: 'Missing capture manifest',
      );

      final manifest =
          jsonDecode(await manifestFile.readAsString()) as Map<String, Object?>;
      final event = manifest['event']! as Map<String, Object?>;
      final p2pTruthOriginTime = _parseSourceOriginTime(event['originTimeJst']);
      final records = (manifest['records']! as List<Object?>)
          .whereType<Map<String, Object?>>()
          .where((record) => record['ok'] == true)
          .toList(growable: false);
      final recordsByTime = <DateTime, Map<String, Map<String, Object?>>>{};
      for (final record in records) {
        final timestamp = DateTime.parse(
          record['observedAt']! as String,
        ).toUtc();
        recordsByTime.putIfAbsent(
          timestamp,
          () => <String, Map<String, Object?>>{},
        )[record['layer']! as String] = record;
      }
      final timestamps = recordsByTime.keys.toList()..sort();
      expect(timestamps, hasLength(151));

      StationEventTracker.instance.resetNied();
      final imageService = LmoniImageService()
        ..stop()
        ..start();
      final driver = NiedSourceEstimationDriver();
      List<dynamic>? latestStations;
      final subscription = imageService.stationStream.listen((stations) {
        latestStations = stations;
      });
      final frames = <Map<String, Object?>>[];
      List<SeismicStationEventRecord>? finalSourceRecords;
      Map<String, Object?>? finalSourceMetadata;

      try {
        for (var frameIndex = 0; frameIndex < timestamps.length; frameIndex++) {
          final timestamp = timestamps[frameIndex];
          final layers = recordsByTime[timestamp]!;
          final jma = await _decodeLayer(capture, layers['jma_s']);
          if (jma == null) continue;
          imageService.processPixels(
            jma.packedRgb,
            surfaceGifBytes: jma.gifBytes,
            dataTime: timestamp,
            receivedAt: timestamp,
          );
          await Future<void>.delayed(Duration.zero);
          final jmaStations = latestStations;
          if (jmaStations == null) continue;
          driver.processStations(jmaStations.cast(), observedAt: timestamp);

          for (final entry in const <(String, NiedGifLayer)>[
            ('acmap_s', NiedGifLayer.peakAcceleration),
            ('vcmap_s', NiedGifLayer.peakVelocity),
            ('dcmap_s', NiedGifLayer.peakDisplacement),
          ]) {
            final decoded = await _decodeLayer(capture, layers[entry.$1]);
            imageService.processPhysicalLayerPixels(
              layer: entry.$2,
              dataTime: timestamp,
              receivedAt: timestamp,
              surfacePackedRgb: decoded?.packedRgb,
            );
          }
          imageService.publishStations();
          await Future<void>.delayed(Duration.zero);
          final physicalStations = latestStations;
          if (physicalStations == null) continue;
          if (estimatorMode == 'legacy_jma_style_final_frame' &&
              frameIndex == timestamps.length - 1) {
            StationEventTracker.instance.setNiedEstimator(
              const NiedGifHybridSourceEstimator(),
            );
          }
          final detection = driver.processStations(
            physicalStations.cast(),
            observedAt: timestamp,
          );
          final estimate =
              StationEventTracker.instance.currentNiedEvent.value?.estimate;
          final sourceEvent =
              StationEventTracker.instance.currentNiedEvent.value;
          if (estimate != null && sourceEvent != null) {
            finalSourceRecords = sourceEvent.records;
            finalSourceMetadata = Map<String, Object?>.from(
              sourceEvent.metadata,
            );
          }
          final frameSourceTriggerMemberIds =
              (sourceEvent?.metadata['source_trigger_member_ids'] as Iterable?)
                  ?.whereType<String>()
                  .toSet() ??
              const <String>{};
          final frameSArrivalWindowDiagnostics =
              !enableSArrivalWindowDiagnostic ||
                  estimate == null ||
                  sourceEvent == null
              ? null
              : switch (sourceGeometryMode) {
                  'dart_hyp' => niedGifPgvSArrivalWindowMagnitudeDiagnostics(
                    stations: sourceEvent.records,
                    sourceLatitude: estimate.latitude,
                    sourceLongitude: estimate.longitude,
                    depthKm: estimate.depthKm,
                    sourceOriginTime: estimate.originTime,
                    sourceTriggerMemberIds: frameSourceTriggerMemberIds,
                  ),
                  'p2p_truth' => niedGifPgvSArrivalWindowMagnitudeDiagnostics(
                    stations: sourceEvent.records,
                    sourceLatitude: (event['latitude']! as num).toDouble(),
                    sourceLongitude: (event['longitude']! as num).toDouble(),
                    depthKm: (event['depthKm']! as num).toDouble(),
                    sourceOriginTime: p2pTruthOriginTime,
                    sourceTriggerMemberIds: frameSourceTriggerMemberIds,
                  ),
                  _ => throw ArgumentError.value(
                    sourceGeometryMode,
                    'PGV_REPLAY_SOURCE_GEOMETRY',
                    'Expected dart_hyp or p2p_truth.',
                  ),
                };
          frames.add({
            'observedAtUtc': timestamp.toIso8601String(),
            'detectionState': detection.state.name,
            'estimate': estimate == null
                ? null
                : {
                    'latitude': estimate.latitude,
                    'longitude': estimate.longitude,
                    'depthKm': estimate.depthKm,
                    'magnitude': estimate.magnitude,
                    'originTime': estimate.originTime?.toIso8601String(),
                    'confidence': estimate.confidence,
                    'supportingStationCount': estimate.supportingStationCount,
                    'pgvDiagnostics': {
                      for (final entry in estimate.diagnostics.entries)
                        if (entry.key.startsWith('nied_gif_pgv_'))
                          entry.key: entry.value,
                    },
                    'jmaStyleDiagnostics': {
                      for (final entry in estimate.diagnostics.entries)
                        if (entry.key.startsWith('nied_gif_jma_style_'))
                          entry.key: entry.value,
                    },
                    'distanceWeightedPgvDiagnostics': {
                      for (final entry in estimate.diagnostics.entries)
                        if (entry.key.startsWith(
                          'nied_gif_pgv_distance_weighted_',
                        ))
                          entry.key: entry.value,
                    },
                    'srevKaizouMagnitudeDiagnostics': {
                      for (final entry in estimate.diagnostics.entries)
                        if (entry.key.startsWith('srev_kaizou_magnitude_'))
                          entry.key: entry.value,
                    },
                    ...?_optionalSArrivalWindowDiagnostics(
                      frameSArrivalWindowDiagnostics,
                    ),
                  },
          });
        }
      } finally {
        await subscription.cancel();
        imageService.stop();
        StationEventTracker.instance.resetNied();
      }

      final estimates = frames
          .map((frame) => frame['estimate'])
          .whereType<Map<String, Object?>>()
          .toList(growable: false);
      expect(estimates, isNotEmpty);
      final srevKaizouMagnitudeTrajectory = frames
          .map((frame) {
            final estimate = frame['estimate'];
            if (estimate is! Map<String, Object?>) return null;
            final diagnostics = estimate['srevKaizouMagnitudeDiagnostics'];
            if (diagnostics is! Map<String, Object?> ||
                diagnostics['srev_kaizou_magnitude_supported'] != true) {
              return null;
            }
            return <String, Object?>{
              'observedAtUtc': frame['observedAtUtc'],
              'latitude': estimate['latitude'],
              'longitude': estimate['longitude'],
              'inputIntensity':
                  diagnostics['srev_kaizou_magnitude_input_intensity'],
              'dartMagnitude': estimate['magnitude'],
            };
          })
          .whereType<Map<String, Object?>>()
          .toList(growable: false);
      final finalEstimate = estimates.last;
      expect(finalSourceRecords, isNotNull);
      final sourceRecords = finalSourceRecords!;
      final sourceTriggerMemberIds =
          (finalSourceMetadata?['source_trigger_member_ids'] as Iterable?)
              ?.whereType<String>()
              .toSet() ??
          const <String>{};
      final geometry = switch (sourceGeometryMode) {
        'dart_hyp' => (
          latitude: finalEstimate['latitude']! as double,
          longitude: finalEstimate['longitude']! as double,
          depthKm: finalEstimate['depthKm']! as double,
        ),
        'p2p_truth' => (
          latitude: (event['latitude']! as num).toDouble(),
          longitude: (event['longitude']! as num).toDouble(),
          depthKm: (event['depthKm']! as num).toDouble(),
        ),
        _ => throw ArgumentError.value(
          sourceGeometryMode,
          'PGV_REPLAY_SOURCE_GEOMETRY',
          'Expected dart_hyp or p2p_truth.',
        ),
      };
      final sourceOriginTime = switch (sourceGeometryMode) {
        'dart_hyp' => _parseSourceOriginTime(finalEstimate['originTime']),
        'p2p_truth' => p2pTruthOriginTime,
        _ => null,
      };
      final geometryDiagnostics = {
        ...niedGifPgvMagnitudeDiagnostics(
          stations: sourceRecords,
          sourceLatitude: geometry.latitude,
          sourceLongitude: geometry.longitude,
          depthKm: geometry.depthKm,
          sourceTriggerMemberIds: sourceTriggerMemberIds,
        ),
        ...niedGifJmaStyleIntensityMagnitudeDiagnostics(
          stations: sourceRecords,
          sourceLatitude: geometry.latitude,
          sourceLongitude: geometry.longitude,
          depthKm: geometry.depthKm,
          sourceTriggerMemberIds: sourceTriggerMemberIds,
        ),
        ...niedGifPgvDistanceWeightedMagnitudeDiagnostics(
          stations: sourceRecords,
          sourceLatitude: geometry.latitude,
          sourceLongitude: geometry.longitude,
          depthKm: geometry.depthKm,
          sourceTriggerMemberIds: sourceTriggerMemberIds,
        ),
        if (jshisArvManifestPath.isNotEmpty)
          ...niedGifPgvJshisArvMagnitudeDiagnostics(
            stations: sourceRecords,
            sourceLatitude: geometry.latitude,
            sourceLongitude: geometry.longitude,
            depthKm: geometry.depthKm,
            sourceTriggerMemberIds: sourceTriggerMemberIds,
            jshisArvTerms: await _loadJshisArvTerms(File(jshisArvManifestPath)),
          ),
        if (enableSArrivalWindowDiagnostic)
          ...niedGifPgvSArrivalWindowMagnitudeDiagnostics(
            stations: sourceRecords,
            sourceLatitude: geometry.latitude,
            sourceLongitude: geometry.longitude,
            depthKm: geometry.depthKm,
            sourceOriginTime: sourceOriginTime,
            sourceTriggerMemberIds: sourceTriggerMemberIds,
          ),
      };
      final nearestStationSweep = _parseNearestStationSweep(
        nearestStationSweepRaw,
      );
      final sArrivalWindowTrajectory = enableSArrivalWindowDiagnostic
          ? _extractSArrivalWindowTrajectory(frames)
          : const <Map<String, Object?>>[];
      final sArrivalWindowDispersionAcceptableSnapshots =
          sArrivalWindowTrajectory
              .where((snapshot) => snapshot['dispersionAcceptable'] == true)
              .toList(growable: false);
      final sArrivalWindowMaximumDispersionSnapshot =
          sArrivalWindowDispersionAcceptableSnapshots.isEmpty
          ? null
          : sArrivalWindowDispersionAcceptableSnapshots.reduce((
              best,
              candidate,
            ) {
              final bestCount = best['stationCount']! as int;
              final candidateCount = candidate['stationCount']! as int;
              return candidateCount > bestCount ? candidate : best;
            });
      final report = {
        'schemaVersion': 'nied_pgv_default_hyp_replay_v3',
        'captureDirectory': capture.path,
        'estimatorMode': estimatorMode,
        'sourceGeometry': {
          'mode': sourceGeometryMode,
          'latitude': geometry.latitude,
          'longitude': geometry.longitude,
          'depthKm': geometry.depthKm,
        },
        'p2pTruth': {
          'originTimeJst': event['originTimeJst'],
          'latitude': event['latitude'],
          'longitude': event['longitude'],
          'depthKm': event['depthKm'],
          'magnitude': event['magnitude'],
          'source': event['truthSource'],
        },
        'sArrivalWindowDiagnostic': {
          'enabled': enableSArrivalWindowDiagnostic,
          'sourceOriginTimeUtc': sourceOriginTime?.toUtc().toIso8601String(),
          if (enableSArrivalWindowDiagnostic)
            'trajectory': sArrivalWindowTrajectory,
          if (enableSArrivalWindowDiagnostic)
            'firstDispersionAcceptableSnapshot':
                sArrivalWindowDispersionAcceptableSnapshots.isEmpty
                ? null
                : sArrivalWindowDispersionAcceptableSnapshots.first,
          if (enableSArrivalWindowDiagnostic)
            'maximumDispersionSnapshot':
                sArrivalWindowMaximumDispersionSnapshot,
          if (enableSArrivalWindowDiagnostic)
            'lastDispersionAcceptableSnapshot':
                sArrivalWindowDispersionAcceptableSnapshots.isEmpty
                ? null
                : sArrivalWindowDispersionAcceptableSnapshots.last,
        },
        'finalEstimate': finalEstimate,
        'selectedGeometryDiagnostics': geometryDiagnostics,
        'eligiblePhysicalPgvStationCodes': _eligiblePhysicalPgvStationCodes(
          sourceRecords,
          sourceTriggerMemberIds: sourceTriggerMemberIds,
        ),
        'sourceTriggerMemberIds': sourceTriggerMemberIds.toList()..sort(),
        if (nearestStationSweep.isNotEmpty)
          'nearestStationSweepDiagnostics': {
            for (final count in nearestStationSweep)
              '$count': niedGifPgvDistanceWeightedMagnitudeDiagnostics(
                stations: sourceRecords,
                sourceLatitude: geometry.latitude,
                sourceLongitude: geometry.longitude,
                depthKm: geometry.depthKm,
                sourceTriggerMemberIds: sourceTriggerMemberIds,
                nearestStationCount: count,
              ),
          },
        'jshisArvManifest': jshisArvManifestPath.isEmpty
            ? null
            : jshisArvManifestPath,
        'frameCount': frames.length,
        'estimateFrameCount': estimates.length,
        'srevKaizouMagnitudeTrajectory': srevKaizouMagnitudeTrajectory,
        'productionMagnitudeChanged': false,
      };
      final geometrySuffix = sourceGeometryMode == 'dart_hyp'
          ? ''
          : '_$sourceGeometryMode';
      final output = File(
        '.dart_tool/nied_pgv_magnitude_replay/'
        '${manifest['caseId']}_$estimatorMode$geometrySuffix.json',
      )..parent.createSync(recursive: true);
      await output.writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

List<Map<String, Object?>> _extractSArrivalWindowTrajectory(
  Iterable<Map<String, Object?>> frames,
) {
  return [
    for (final frame in frames)
      if (frame['estimate'] case final Map<String, Object?> estimate)
        if (estimate['sArrivalWindowDiagnostics']
            case final Map<String, Object?> diagnostics)
          {
            'observedAtUtc': frame['observedAtUtc'],
            'magnitudeSupported':
                diagnostics['nied_gif_pgv_s_arrival_window_magnitude_supported'],
            'dispersionAcceptable':
                diagnostics['nied_gif_pgv_s_arrival_window_dispersion_acceptable'],
            'stationCount':
                diagnostics['nied_gif_pgv_s_arrival_window_station_count'],
            'median': diagnostics['nied_gif_pgv_s_arrival_window_median'],
            'iqr': diagnostics['nied_gif_pgv_s_arrival_window_iqr'],
            'noPgvInWindowStationCount':
                diagnostics['nied_gif_pgv_s_arrival_window_no_pgv_in_window_station_count'],
            'preSPeakExcludedStationCount':
                diagnostics['nied_gif_pgv_s_arrival_window_pre_s_peak_excluded_station_count'],
            'postSPeakExcludedStationCount':
                diagnostics['nied_gif_pgv_s_arrival_window_post_s_peak_excluded_station_count'],
            'partialHistoryCoverageStationCount':
                diagnostics['nied_gif_pgv_s_arrival_window_partial_history_coverage_station_count'],
          },
  ];
}

Map<String, Object?>? _optionalSArrivalWindowDiagnostics(
  Map<String, Object?>? diagnostics,
) => diagnostics == null ? null : {'sArrivalWindowDiagnostics': diagnostics};

DateTime? _parseSourceOriginTime(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}

List<int> _parseNearestStationSweep(String raw) {
  if (raw.trim().isEmpty) return const <int>[];
  final values = raw
      .split(',')
      .map((value) => int.tryParse(value.trim()))
      .toList(growable: false);
  if (values.any((value) => value == null || value < 3)) {
    throw ArgumentError.value(
      raw,
      'PGV_REPLAY_NEAREST_STATION_SWEEP',
      'Expected comma-separated integers greater than or equal to 3.',
    );
  }
  return values.cast<int>().toSet().toList()..sort();
}

Future<List<NiedJshisArvDiagnosticTerm>> _loadJshisArvTerms(
  File manifestFile,
) async {
  if (!manifestFile.existsSync()) {
    throw StateError('Missing J-SHIS ARV manifest: ${manifestFile.path}');
  }
  final decoded = jsonDecode(await manifestFile.readAsString());
  if (decoded is! Map) {
    throw const FormatException('J-SHIS ARV manifest must be a JSON object.');
  }
  final records = decoded['records'];
  if (records is! Map) {
    throw const FormatException('J-SHIS ARV manifest is missing records.');
  }
  final items = records['items'];
  if (items is! List) {
    throw const FormatException('J-SHIS ARV manifest records must be a list.');
  }
  return [
    for (final item in items)
      if (item is Map)
        ?NiedJshisArvDiagnosticTerm.tryFromAcquisitionRecord(item),
  ];
}

List<String> _eligiblePhysicalPgvStationCodes(
  Iterable<SeismicStationEventRecord> records, {
  required Set<String> sourceTriggerMemberIds,
}) {
  return [
    for (final record in records)
      if (record.descriptor.sensorRole == StationSensorRole.surface &&
          (record.hasTriggered ||
              record.firstRiseAt != null ||
              sourceTriggerMemberIds.contains(record.descriptor.code)) &&
          record
                  .provenance[StationValueType.pgv]
                  ?.mayBeUsedAsIndependentEvidence ==
              true &&
          record.eventPhysicalPeaks[StationValueType.pgv]?.isUsable == true &&
          (record.eventPhysicalPeaks[StationValueType.pgv]?.colorPosition ==
                  null ||
              record.eventPhysicalPeaks[StationValueType.pgv]!.colorPosition! <
                  0.999))
        record.descriptor.code,
  ]..sort();
}

Future<NiedDecodedGifFrame?> _decodeLayer(
  Directory capture,
  Map<String, Object?>? record,
) {
  if (record == null) return Future<NiedDecodedGifFrame?>.value(null);
  return decodeNiedGifFile(
    File(
      '${capture.path}${Platform.pathSeparator}${record['file']! as String}',
    ),
  );
}
