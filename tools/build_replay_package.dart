import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutterrhythmquake/core/replay/replay_versions.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';

void main(List<String> args) {
  final casePath = _argument(args, '--case');
  if (casePath == null) {
    stderr.writeln(
      'Usage: dart run tools/build_replay_package.dart --case <fixture.json>',
    );
    exitCode = 64;
    return;
  }

  final workspace = Directory.current;
  final caseFile = File(_absolutePath(workspace, casePath));
  final replayCase = _readJson(caseFile);
  final captureDirectory = Directory(
    _absolutePath(workspace, replayCase['captureDirectory']! as String),
  );
  final captureManifestFile = File(
    '${captureDirectory.path}${Platform.pathSeparator}capture_manifest.json',
  );
  final capture = captureManifestFile.existsSync()
      ? _readJson(captureManifestFile)
      : _synthesizeLegacyCaptureManifest(
          replayCase: replayCase,
          captureDirectory: captureDirectory,
          captureManifestFile: captureManifestFile,
        );
  _preserveLegacyManifest(captureDirectory);

  final packageId = replayCase['caseId']! as String;
  final caseType = replayCase['caseType']! as String;
  final start = DateTime.parse(replayCase['startTimeJst']! as String);
  final end = DateTime.parse(replayCase['endTimeJst']! as String);
  const layers = ['jma_s', 'jma_b'];
  const interval = Duration(seconds: 1);
  final records = (capture['records']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final recordsByKey = <String, Map<String, Object?>>{
    for (final record in records)
      '${record['timeJst']}:${record['layer']}': record,
  };
  final missingFrames = <Map<String, Object?>>[];
  final frames = <Map<String, Object?>>[];
  final captureMode = capture['captureMode'] as String? ?? 'historical';
  final receivedAtStatus =
      capture['receivedAtStatus'] as String? ??
      (captureMode == 'live'
          ? 'observed_live_fetch_completion'
          : 'unavailable_in_capture_v1');
  final decoderVersion =
      capture['decoderVersion'] as String? ?? ReplayDataVersions.niedGifDecoder;
  final stationDbVersion =
      capture['stationDbVersion'] as String? ?? NiedStationDb.stationDbVersion;
  final sensorSelectionPolicy =
      capture['sensorSelectionPolicy'] as String? ?? 'surface_jma_s_primary_v1';

  for (var time = start; !time.isAfter(end); time = time.add(interval)) {
    final timeKey = _localIso(time);
    final layerRecords = <String, Object?>{};
    final receivedTimes = <DateTime>[];
    var completeLiveFrame = captureMode == 'live';
    for (final layer in layers) {
      final record = recordsByKey['$timeKey:$layer'];
      final available = record?['ok'] == true;
      final layerReceivedAt = record?['receivedAt'] as String?;
      if (!available || layerReceivedAt == null) {
        completeLiveFrame = false;
      } else {
        receivedTimes.add(DateTime.parse(layerReceivedAt));
      }
      if (!available) {
        missingFrames.add({
          'observedAt': _jstIso(time),
          'layer': layer,
          'reason': record?['error'] ?? 'capture_record_missing',
        });
      }
      layerRecords[layer] = {
        'available': available,
        'path': available ? record!['file'] : null,
        'bytes': available ? record!['bytes'] : null,
        'sha256': available ? record!['sha256'] : null,
        'sourceUrl': record?['url'],
        'requestStartedAt': record?['requestStartedAt'],
        'receivedAt': layerReceivedAt,
        'retrievedAt': record?['retrievedAt'],
        'retrievalDurationMs': record?['retrievalDurationMs'],
        'receiveDelayMs': record?['receiveDelayMs'],
        'attempts': record?['attempts'],
        'qualityFlags': record?['qualityFlags'] ?? [if (!available) 'missing'],
      };
    }
    frames.add({
      'observedAt': _jstIso(time),
      'receivedAt': completeLiveFrame
          ? _latest(receivedTimes).toIso8601String()
          : null,
      'layers': layerRecords,
    });
  }

  final truthPath = caseType == 'event' ? 'truth.json' : null;
  final expectedTimestampCount = end.difference(start).inSeconds + 1;
  final manifest = {
    'schemaVersion': 1,
    'packageId': packageId,
    'caseType': caseType,
    'timeZone': 'Asia/Tokyo',
    'startTime': _jstIso(start),
    'endTime': _jstIso(end),
    'expectedFrameIntervalMs': interval.inMilliseconds,
    'expectedTimestampCount': expectedTimestampCount,
    'decoderVersion': decoderVersion,
    'stationDbVersion': stationDbVersion,
    'sensorSelectionPolicy': sensorSelectionPolicy,
    'rawLayout': 'flat_capture_v1',
    'frameIndexPath': 'frames/index.json',
    'stationSnapshotPath': 'stations.json',
    'truthPath': truthPath,
    'layers': layers,
    'missingFrames': missingFrames,
    'sourceUrlTemplates': {
      for (final layer in layers)
        layer:
            'https://smi.lmoniexp.bosai.go.jp/data/map_img/RealTimeImg/'
            '$layer/{yyyyMMdd}/{yyyyMMddHHmmss}.$layer.gif',
    },
    'provenance': {
      'captureManifest': 'capture_manifest.json',
      'caseFixture': casePath.replaceAll('\\', '/'),
      'capturedAt': capture['capturedAt'],
      'captureMode': captureMode,
      'receivedAtStatus': receivedAtStatus,
      'clock': capture['clock'],
      'builder': 'tools/build_replay_package.dart',
    },
  };
  final frameIndex = {
    'schemaVersion': 1,
    'packageId': packageId,
    'frames': frames,
  };
  final stations = {
    'schemaVersion': 1,
    'packageId': packageId,
    'stationDbVersion': stationDbVersion,
    'sensorSelectionPolicy': sensorSelectionPolicy,
    'stations': NiedStationDb.stations,
  };

  _writeJson(File('${captureDirectory.path}/manifest.json'), manifest);
  _writeJson(File('${captureDirectory.path}/frames/index.json'), frameIndex);
  _writeJson(File('${captureDirectory.path}/stations.json'), stations);
  if (truthPath != null) {
    final truth = replayCase['truth']! as Map<String, Object?>;
    final labels = replayCase['eventLabels']! as Map<String, Object?>;
    final catalog = truth['catalog'] as Map<String, Object?>?;
    _writeJson(File('${captureDirectory.path}/truth.json'), {
      'schemaVersion': 1,
      'packageId': packageId,
      'status': labels['catalogTruthVerified'] == true
          ? 'catalog_verified'
          : 'reference_only',
      'agency': catalog?['agency'] ?? _truthAgency(truth['source']! as String),
      'eventId': catalog?['eventId'],
      'resourceId': catalog?['resourceId'],
      'revision': catalog?['revision'],
      'catalogId': catalog?['catalogId'],
      'catalogRevision': catalog?['catalogRevision'],
      'source': truth['source'],
      'sourceUrl': catalog?['sourceUrl'],
      'preferredOrigin': {
        'time': _jstIso(DateTime.parse(truth['originTimeJst']! as String)),
        'latitude': truth['latitude'],
        'longitude': truth['longitude'],
        'depthKm': truth['depthKm'],
      },
      'magnitude': truth['magnitude'],
      'eventLabels': labels,
      'catalogMatch': catalog?['match'],
    });
  }

  stdout.writeln(
    jsonEncode({
      'packageId': packageId,
      'directory': captureDirectory.path,
      'timestamps': frames.length,
      'layers': layers.length,
      'missingFrames': missingFrames.length,
      'stations': NiedStationDb.stations.length,
    }),
  );
}

Map<String, Object?> _synthesizeLegacyCaptureManifest({
  required Map<String, Object?> replayCase,
  required Directory captureDirectory,
  required File captureManifestFile,
}) {
  final caseId = replayCase['caseId']! as String;
  final start = DateTime.parse(replayCase['startTimeJst']! as String);
  final end = DateTime.parse(replayCase['endTimeJst']! as String);
  final pattern =
      replayCase['gifNamePattern'] as String? ?? '{stamp}.{layer}.gif';
  const layers = ['jma_s', 'jma_b'];
  const interval = Duration(seconds: 1);
  final records = <Map<String, Object?>>[];
  var downloaded = 0;
  var failed = 0;

  for (var time = start; !time.isAfter(end); time = time.add(interval)) {
    final stamp = _stamp(time);
    final date = _dateStamp(time);
    for (final layer in layers) {
      final fileName = pattern
          .replaceAll('{stamp}', stamp)
          .replaceAll('{layer}', layer);
      final file = File('${captureDirectory.path}/$fileName');
      final ok = file.existsSync() && file.lengthSync() > 0;
      if (ok) {
        downloaded++;
      } else {
        failed++;
      }
      records.add({
        'timeJst': _localIso(time),
        'observedAt': _jstIso(time),
        'receivedAt': null,
        'retrievedAt': null,
        'retrievalDurationMs': null,
        'cacheStatus': ok ? 'legacy_existing' : 'missing',
        'layer': layer,
        'file': fileName,
        'bytes': ok ? file.lengthSync() : 0,
        'sha256': ok ? sha256.convert(file.readAsBytesSync()).toString() : null,
        'ok': ok,
        'qualityFlags': ['legacy_synthesized_manifest', if (!ok) 'missing'],
        'url':
            'https://smi.lmoniexp.bosai.go.jp/data/map_img/RealTimeImg/'
            '$layer/$date/$stamp.$layer.gif',
        if (!ok) 'error': 'legacy_file_missing',
      });
    }
  }

  final manifest = <String, Object?>{
    'schemaVersion': 0,
    'captureMode': 'historical',
    'capturedAt': null,
    'caseId': caseId,
    'event': replayCase['truth'] == null
        ? null
        : {
            'originTimeJst':
                (replayCase['truth']! as Map<String, Object?>)['originTimeJst'],
            'latitude':
                (replayCase['truth']! as Map<String, Object?>)['latitude'],
            'longitude':
                (replayCase['truth']! as Map<String, Object?>)['longitude'],
            'depthKm':
                (replayCase['truth']! as Map<String, Object?>)['depthKm'],
            'magnitude':
                (replayCase['truth']! as Map<String, Object?>)['magnitude'],
            'truthSource':
                (replayCase['truth']! as Map<String, Object?>)['source'],
          },
    'startTimeJst': _localIso(start),
    'endTimeJst': _localIso(end),
    'expectedGifCount': records.length,
    'expectedFrameIntervalMs': 1000,
    'decoderVersion': ReplayDataVersions.niedGifDecoder,
    'stationDbVersion': NiedStationDb.stationDbVersion,
    'sensorSelectionPolicy': 'surface_jma_s_primary_v1',
    'receivedAtStatus': 'unavailable_legacy_synthesized',
    'downloadedGifCount': downloaded,
    'failedGifCount': failed,
    'records': records,
  };

  _writeJson(captureManifestFile, manifest);
  return manifest;
}

void _preserveLegacyManifest(Directory captureDirectory) {
  final manifestFile = File('${captureDirectory.path}/manifest.json');
  if (!manifestFile.existsSync()) return;

  final parsed = jsonDecode(manifestFile.readAsStringSync());
  if (parsed is Map<String, Object?> && parsed['schemaVersion'] == 1) return;

  final legacyFile = File('${captureDirectory.path}/legacy_manifest.json');
  if (legacyFile.existsSync()) return;
  manifestFile.copySync(legacyFile.path);
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

String _absolutePath(Directory workspace, String path) {
  if (File(path).isAbsolute) return path;
  return File.fromUri(workspace.uri.resolve(path.replaceAll('\\', '/'))).path;
}

Map<String, Object?> _readJson(File file) {
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

void _writeJson(File file, Map<String, Object?> json) {
  file.parent.createSync(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  file.writeAsStringSync('${encoder.convert(json)}\n');
}

String _localIso(DateTime value) => value.toIso8601String().split('.').first;

String _jstIso(DateTime value) => '${_localIso(value)}+09:00';

String _stamp(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}'
      '${two(value.month)}'
      '${two(value.day)}'
      '${two(value.hour)}'
      '${two(value.minute)}'
      '${two(value.second)}';
}

String _dateStamp(DateTime value) => _stamp(value).substring(0, 8);

DateTime _latest(List<DateTime> values) {
  return values.reduce(
    (current, next) => next.isAfter(current) ? next : current,
  );
}

String _truthAgency(String source) {
  if (source.toLowerCase().contains('jma')) return 'JMA';
  if (source.toLowerCase().contains('hinet') ||
      source.toLowerCase().contains('hi-net')) {
    return 'Hi-net';
  }
  if (source.toLowerCase().contains('equake')) return 'EQuake';
  return 'project';
}
