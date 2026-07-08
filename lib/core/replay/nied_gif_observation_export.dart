import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image_lib;

import '../../models/nied_scan_positions.dart';
import '../../services/sources/nied_gif_observation.dart';
import '../../services/sources/nied_gif_value_decoder.dart';
import 'knet_waveform_archive.dart';
import 'replay_versions.dart';

const niedGifStationSecondObservationsVersion =
    'gif_station_second_observations_v1';

class NiedGifObservationExporter {
  const NiedGifObservationExporter();

  Map<String, Object?> exportFromCaptureDirectory(
    String captureDirectoryPath, {
    KnetSensorRole sensorRole = KnetSensorRole.surface,
  }) {
    final captureDirectory = Directory(captureDirectoryPath);
    final captureManifestFile = File(
      '${captureDirectory.path}${Platform.pathSeparator}capture_manifest.json',
    );
    if (!captureManifestFile.existsSync()) {
      throw FileSystemException(
        'capture_manifest.json not found',
        captureManifestFile.path,
      );
    }

    final manifest =
        jsonDecode(captureManifestFile.readAsStringSync())
            as Map<String, Object?>;
    final packageId =
        manifest['caseId'] as String? ?? captureDirectory.uri.pathSegments.last;
    final decoderVersion =
        manifest['decoderVersion'] as String? ??
        ReplayDataVersions.niedGifDecoder;
    final stationDbVersion =
        manifest['stationDbVersion'] as String? ??
        ReplayDataVersions.niedStationDb;
    final selectionPolicy =
        manifest['sensorSelectionPolicy'] as String? ?? 'capture_selected';
    final records = (manifest['records'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>();
    final targetLayerKey = NiedGifLayer.realtimeShindo.imageKey(
      borehole: sensorRole == KnetSensorRole.borehole,
    );

    final observations = <Map<String, Object?>>[];
    for (final record in records) {
      if (record['ok'] != true || record['layer'] != targetLayerKey) {
        continue;
      }
      final fileName = record['file'] as String?;
      final observedAtRaw = record['observedAt'] as String?;
      if (fileName == null || observedAtRaw == null) {
        continue;
      }

      final imageFile = File(
        '${captureDirectory.path}${Platform.pathSeparator}$fileName',
      );
      if (!imageFile.existsSync()) {
        continue;
      }
      final decoded = image_lib.decodeImage(imageFile.readAsBytesSync());
      if (decoded == null) {
        continue;
      }

      final observedAtUtc = DateTime.parse(observedAtRaw).toUtc();
      final baseFlags = (record['qualityFlags'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(growable: false);

      for (final entry in NiedScanPositions.positions.entries) {
        final x = entry.value[0];
        final y = entry.value[1];
        if (x < 0 || y < 0 || x >= decoded.width || y >= decoded.height) {
          continue;
        }
        final pixel = decoded.getPixel(x, y);
        final observation = NiedGifValueDecoder.decodeObservationFromRgba(
          pixel.r.toInt(),
          pixel.g.toInt(),
          pixel.b.toInt(),
          layer: NiedGifLayer.realtimeShindo,
        );
        final shindo = observation?.shindo;
        if (shindo == null) {
          continue;
        }
        observations.add({
          'stationCode': entry.key,
          'observedAtUtc': observedAtUtc.toIso8601String(),
          'gifDecodedShindo': shindo,
          'sensorRole': sensorRole.name,
          'qualityFlags': baseFlags,
        });
      }
    }

    observations.sort((a, b) {
      final timeCompare = (a['observedAtUtc']! as String).compareTo(
        b['observedAtUtc']! as String,
      );
      if (timeCompare != 0) return timeCompare;
      return (a['stationCode']! as String).compareTo(
        b['stationCode']! as String,
      );
    });

    return {
      'schemaVersion': niedGifStationSecondObservationsVersion,
      'packageId': packageId,
      'captureDirectory': captureDirectory.path,
      'sourceLayer': targetLayerKey,
      'sensorRole': sensorRole.name,
      'decoderVersion': decoderVersion,
      'stationDbVersion': stationDbVersion,
      'sensorSelectionPolicy': selectionPolicy,
      'observationCount': observations.length,
      'observations': observations,
    };
  }
}
