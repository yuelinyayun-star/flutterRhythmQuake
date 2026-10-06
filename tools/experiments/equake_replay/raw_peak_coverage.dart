import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as images;
import 'package:flutterrhythmquake/core/source_estimation/srev_kaizou_magnitude.dart';
import 'package:flutterrhythmquake/models/nied_scan_positions.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_observation.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_value_decoder.dart';

String hash(List<int> bytes) => sha256.convert(bytes).toString();

void main(List<String> args) {
  if (args.length != 3) {
    throw ArgumentError('Pass fixture, candidate report, new output path');
  }
  final fixtureBytes = File(args[0]).readAsBytesSync();
  final reportBytes = File(args[1]).readAsBytesSync();
  final output = File(args[2]);
  if (output.existsSync()) throw StateError('Output already exists');
  final fixture = jsonDecode(utf8.decode(fixtureBytes)) as Map;
  final report = jsonDecode(utf8.decode(reportBytes)) as Map;
  final scanFile = File('lib/models/nied_scan_positions.dart');
  final scanHash = hash(scanFile.readAsBytesSync());
  if (report['scanPositionsSha256'] != scanHash) {
    throw StateError(
      'Replay report and raw audit must use the same scan table',
    );
  }
  final replay = (report['cases'] as List).cast<Map>().singleWhere(
    (c) => c['id'] == fixture['caseId'],
  );
  final frames = (replay['frames'] as List).cast<Map>();
  final finalFrame = frames.lastWhere((f) => f['estimate'] != null);
  Map? candidate(Map f) => (f['magnitudeAudit'] as Map?)?['experiment'] is Map
      ? ((f['magnitudeAudit'] as Map)['experiment']
                as Map)['eventPeakCandidate']
            as Map?
      : null;
  final finalCandidate = candidate(finalFrame)!;
  final finalKey = finalCandidate['eventKey'];
  final peaks = (finalCandidate['stationPeaks'] as Map).cast<String, num>();
  final estimate = finalFrame['estimate'] as Map;
  final latitude = (estimate['latitude'] as num).toDouble();
  final longitude = (estimate['longitude'] as num).toDouble();
  final selectedFrames = frames
      .where((f) => candidate(f)?['eventKey'] == finalKey)
      .toList();
  final firstSelected = selectedFrames.first['observedAtJst'] as String;
  final lastSelected = selectedFrames.last['observedAtJst'] as String;
  final frameMap = {for (final f in frames) f['observedAtJst'] as String: f};
  final stationMap = {
    for (final s in NiedStationDb.stations) s['code'] as String: s,
  };
  final tracked = <String, Map<String, Object?>>{};
  final unavailableScanPositions = <String>[];
  for (final station in NiedStationDb.stations) {
    final code = station['code'] as String;
    final distance = srevKaizouStationDistanceKm(
      roundedSourceLatitude: srevKaizouRoundCoordinate(latitude),
      roundedSourceLongitude: srevKaizouRoundCoordinate(longitude),
      stationLatitude: (station['lat'] as num).toDouble(),
      stationLongitude: (station['lng'] as num).toDouble(),
    );
    // Fixed diagnostic window, not a magnitude station-selection policy.
    if (distance > 100 && !peaks.containsKey(code)) continue;
    if (!NiedScanPositions.positions.containsKey(code)) {
      unavailableScanPositions.add(code);
      continue;
    }
    tracked[code] = {
      'code': code,
      'name': station['name'],
      'distanceKm': distance,
      'candidatePeak': peaks[code],
      'validFrames': 0,
      'maximum': null,
      'peakRows': <Map<String, Object?>>[],
      'samples': <Map<String, Object?>>[],
      'physicalSamples': <Map<String, Object?>>[],
    };
  }
  final capture = fixture['captureDirectory'] as String;
  final manifestFile = File('$capture/capture_manifest.json');
  final manifestBytes = manifestFile.readAsBytesSync();
  final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map;
  final files = <Map<String, Object?>>[];
  final start = DateTime.parse(fixture['startTimeJst'] as String);
  final end = DateTime.parse(fixture['endTimeJst'] as String);
  var matchedSnapshotValues = 0;
  var unequalSnapshotValues = 0;
  final snapshotDifferences = <Map<String, Object?>>[];
  const layers = {
    'jma_s': NiedGifLayer.realtimeShindo,
    'acmap_s': NiedGifLayer.peakAcceleration,
    'vcmap_s': NiedGifLayer.peakVelocity,
    'dcmap_s': NiedGifLayer.peakDisplacement,
  };
  for (final record in (manifest['records'] as List).cast<Map>()) {
    final layer = layers[record['layer']];
    if (layer == null || record['ok'] != true) continue;
    final timestamp = switch (manifest['schemaVersion']) {
      1 => '${record['timeJst'] as String}+09:00',
      2 => record['observedAt'] as String,
      _ => throw StateError('Unsupported capture manifest schema'),
    };
    final utc = DateTime.parse(timestamp).toUtc();
    final wall = DateTime.parse(
      utc.add(const Duration(hours: 9)).toIso8601String().replaceFirst('Z', ''),
    );
    if (wall.isBefore(start) || wall.isAfter(end)) continue;
    final file = File('$capture/${record['file']}');
    final bytes = file.readAsBytesSync();
    final digest = hash(bytes);
    if (record['sha256'] != null &&
        digest.toLowerCase() != (record['sha256'] as String).toLowerCase()) {
      throw StateError('Original capture hash mismatch: ${file.path}');
    }
    final decoded = images.decodeGif(bytes);
    if (decoded == null) throw StateError('Cannot decode original GIF');
    final time = wall.toIso8601String();
    files.add({
      'path': file.path,
      'sha256': digest,
      'time': time,
      'layer': record['layer'],
      'manifestHashVerified': record['sha256'] != null,
    });
    if (layer != NiedGifLayer.realtimeShindo) {
      for (final entry in tracked.entries) {
        final position = NiedScanPositions.positions[entry.key]!;
        final pixel = decoded.getPixel(position[0], position[1]);
        final observation = NiedGifValueDecoder.decodeObservationFromRgba(
          pixel.r.toInt(),
          pixel.g.toInt(),
          pixel.b.toInt(),
          layer: layer,
        );
        (entry.value['physicalSamples'] as List<Map<String, Object?>>).add({
          'time': time,
          'layer': record['layer'],
          'rgb': [pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()],
          'colorPosition': observation?.colorPosition,
          'value': switch (layer) {
            NiedGifLayer.peakAcceleration => observation?.pga,
            NiedGifLayer.peakVelocity => observation?.pgv,
            NiedGifLayer.peakDisplacement => observation?.pgd,
            _ => throw StateError('Unsupported physical layer'),
          },
        });
      }
      continue;
    }
    final frame = frameMap[time];
    final audit = frame?['magnitudeAudit'] as Map?;
    final experiment = audit?['experiment'] as Map?;
    final isSelected = experiment?['eventKey'] == finalKey;
    final associated = isSelected
        ? (experiment?['associatedCodes'] as List? ?? []).toSet()
        : <dynamic>{};
    final trace = (audit?['stationTrace'] as Map?)?['stations'] as List? ?? [];
    final snapshots = {for (final s in trace.cast<Map>()) s['code']: s};
    final phase = time.compareTo(firstSelected) < 0
        ? 'before_final_group_selected'
        : time.compareTo(lastSelected) > 0
        ? 'after_final_group_last_output'
        : isSelected
        ? 'final_group_selected'
        : 'other_or_no_output';
    for (final entry in tracked.entries) {
      final position = NiedScanPositions.positions[entry.key];
      if (position == null) {
        throw StateError('Missing scan position: ${entry.key}');
      }
      final pixel = decoded.getPixel(position[0], position[1]);
      final intensity = NiedGifValueDecoder.decodeObservationFromRgba(
        pixel.r.toInt(),
        pixel.g.toInt(),
        pixel.b.toInt(),
      )?.shindo;
      final station = entry.value;
      (station['samples'] as List<Map<String, Object?>>).add({
        'time': time,
        'rgb': [pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()],
        'rawIntensity': intensity,
        'phase': phase,
        'inWorkerSnapshot': snapshots.containsKey(entry.key),
        'associatedToFinalGroup': associated.contains(entry.key),
      });
      if (intensity == null) continue;
      final snapshotValue = snapshots[entry.key]?['rawIntensity'];
      if (snapshotValue is num) {
        if ((intensity - snapshotValue).abs() < 1e-10) {
          matchedSnapshotValues++;
        } else {
          unequalSnapshotValues++;
          snapshotDifferences.add({
            'time': time,
            'code': entry.key,
            'gif': intensity,
            'snapshot': snapshotValue,
          });
        }
      }
      station['validFrames'] = (station['validFrames'] as int) + 1;
      final maximum = station['maximum'] as double?;
      if (maximum != null && intensity < maximum) continue;
      final peakRows = station['peakRows'] as List<Map<String, Object?>>;
      if (maximum == null || intensity > maximum) peakRows.clear();
      station['maximum'] = intensity;
      peakRows.add({
        'time': time,
        'rawIntensity': intensity,
        'phase': phase,
        'inWorkerSnapshot': snapshots.containsKey(entry.key),
        'associatedToFinalGroup': associated.contains(entry.key),
        'selectedEventKey': experiment?['eventKey'],
      });
    }
  }
  for (final row in tracked.values) {
    final peak = row['maximum'] as double?;
    final saved = row['candidatePeak'] as num?;
    row['rawPeakMinusSavedPeak'] = peak != null && saved != null
        ? peak - saved
        : null;
    row['surfaceSensorOnly'] = true;
    row['latitude'] = stationMap[row['code']]!['lat'];
    row['longitude'] = stationMap[row['code']]!['lng'];
  }
  final surfaceFiles = files.where((file) => file['layer'] == 'jma_s').toList();
  final inspectedTimes = surfaceFiles
      .map((file) => file['time'] as String)
      .toSet();
  if (inspectedTimes.length != surfaceFiles.length ||
      inspectedTimes.length != frameMap.length ||
      !inspectedTimes.containsAll(frameMap.keys)) {
    throw StateError('Capture timestamps do not match original replay frames');
  }
  final sorted = tracked.values.toList()
    ..sort(
      (a, b) => ((b['maximum'] as double?) ?? double.negativeInfinity)
          .compareTo((a['maximum'] as double?) ?? double.negativeInfinity),
    );
  for (final file in files) {
    if (hash(File(file['path'] as String).readAsBytesSync()) !=
        file['sha256']) {
      throw StateError('Original capture changed during inspection');
    }
  }
  if (hash(File(args[0]).readAsBytesSync()) != hash(fixtureBytes) ||
      hash(File(args[1]).readAsBytesSync()) != hash(reportBytes) ||
      hash(scanFile.readAsBytesSync()) != scanHash ||
      hash(manifestFile.readAsBytesSync()) != hash(manifestBytes)) {
    throw StateError('Input metadata changed');
  }
  final result = {
    'caseId': replay['id'],
    'feedsProduction': false,
    'readyForProduction': false,
    'policy':
        'All surface GIF pixels within 100km of final estimated source, plus final candidate stations. Entire original window; no reference labels used.',
    'limits': [
      'Nearby peaks are not automatically associated earthquake signals.',
      'Pre/post selection is a diagnostic phase, not an event identity decision.',
      'Does not test borehole selection or change raw observations.',
      'Physical values are independently decoded GIF layers, not original waveforms or calibrated magnitude inputs. Missing frames/values are not filled.',
    ],
    'fixtureSha256': hash(fixtureBytes),
    'reportSha256': hash(reportBytes),
    'manifestSha256': hash(manifestBytes),
    'scanPositionsVersion': NiedScanPositions.version,
    'scanPositionsSha256': scanHash,
    'decoderVersion': NiedGifValueDecoder.decoderVersion,
    'files': files,
    'finalEventKey': finalKey,
    'firstSelected': firstSelected,
    'lastSelected': lastSelected,
    'finalEstimate': {
      'latitude': latitude,
      'longitude': longitude,
      'depthKm': estimate['depthKm'],
    },
    'matchedSnapshotValues': matchedSnapshotValues,
    'unequalSnapshotValues': unequalSnapshotValues,
    'snapshotDifferences': snapshotDifferences,
    'unavailableScanPositions': unavailableScanPositions,
    'stations': sorted,
  };
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(result)}\n',
    encoding: utf8,
  );
  stdout.writeln(
    jsonEncode({
      'output': output.path,
      'files': files.length,
      'surfaceFiles': surfaceFiles.length,
      'stations': sorted.length,
      'matchedSnapshotValues': matchedSnapshotValues,
      'unequalSnapshotValues': unequalSnapshotValues,
      'topStations': [
        for (final station in sorted.take(8))
          {
            'code': station['code'],
            'maximum': station['maximum'],
            'candidatePeak': station['candidatePeak'],
            'validFrames': station['validFrames'],
            'firstPeak': (station['peakRows'] as List).firstOrNull,
          },
      ],
    }),
  );
}
