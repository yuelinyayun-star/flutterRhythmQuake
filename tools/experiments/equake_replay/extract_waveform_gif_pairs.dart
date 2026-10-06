import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as images;
import 'package:path/path.dart' as path;
import 'package:flutterrhythmquake/models/nied_scan_positions.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_observation.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_value_decoder.dart';

String digest(List<int> bytes) => sha256.convert(bytes).toString();

void main(List<String> args) {
  if (args.length < 3) {
    throw ArgumentError(
      'Pass waveform report, fixtures in archive order, new output',
    );
  }
  final output = File(args.last);
  final root = Directory('.dart_tool').resolveSymbolicLinksSync();
  final parent = output.parent.resolveSymbolicLinksSync();
  if (output.existsSync() ||
      path.extension(output.path) != '.json' ||
      (!path.equals(root, parent) && !path.isWithin(root, parent))) {
    throw StateError('Only new JSON in existing .dart_tool directories');
  }
  final hashes = <String, String>{};
  Uint8List read(String file) {
    final bytes = File(file).readAsBytesSync();
    hashes[file] = digest(bytes);
    return bytes;
  }

  final wave = jsonDecode(utf8.decode(read(args.first))) as Map;
  final archives = (wave['archives'] as List).cast<Map>();
  final fixtures = args.sublist(1, args.length - 1);
  if (archives.length != fixtures.length) {
    throw StateError('Exactly one explicit fixture per archive');
  }
  final scanHash = digest(read('lib/models/nied_scan_positions.dart'));
  final cases = <Map<String, Object?>>[];
  for (var i = 0; i < archives.length; i++) {
    final archive = archives[i];
    if (digest(read(archive['input'] as String)) != archive['sha256']) {
      throw StateError('Original waveform ZIP changed');
    }
    final fixture = jsonDecode(utf8.decode(read(fixtures[i]))) as Map;
    final capture = fixture['captureDirectory'] as String;
    final captureRoot = Directory(capture).resolveSymbolicLinksSync();
    if (path.equals(parent, captureRoot) ||
        path.isWithin(captureRoot, parent)) {
      throw StateError('Output cannot be inside a capture');
    }
    final manifest =
        jsonDecode(utf8.decode(read('$capture/capture_manifest.json'))) as Map;
    if (manifest['schemaVersion'] != 2) {
      throw StateError('Explicit observedAt timestamps required');
    }
    final stations = <String, Map<String, Object?>>{};
    for (final s in (archive['stations'] as List).cast<Map>()) {
      final code = s['station'] as String;
      if (stations.containsKey(code)) throw StateError('Duplicate station');
      stations[code] = {
        'code': code,
        'point': NiedScanPositions.positions[code],
        'samples': <Map<String, Object?>>[],
      };
    }
    final start = DateTime.parse('${fixture['startTimeJst']}+09:00');
    final end = DateTime.parse('${fixture['endTimeJst']}+09:00');
    final times = <String, Set<int>>{};
    final files = <Map<String, Object?>>[];
    const layers = {
      'jma_s': NiedGifLayer.realtimeShindo,
      'acmap_s': NiedGifLayer.peakAcceleration,
    };
    for (final record in (manifest['records'] as List).cast<Map>()) {
      final layer = layers[record['layer']];
      if (layer == null || record['ok'] != true) continue;
      final time = DateTime.parse(record['observedAt'] as String).toUtc();
      if (time.isBefore(start) || time.isAfter(end)) continue;
      final layerName = record['layer'] as String;
      if (!times
          .putIfAbsent(layerName, () => {})
          .add(time.millisecondsSinceEpoch)) {
        throw StateError('Duplicate original timestamp');
      }
      final filename = '$capture/${record['file']}';
      final bytes = read(filename);
      if (digest(bytes) != (record['sha256'] as String).toLowerCase()) {
        throw StateError('Original GIF SHA mismatch');
      }
      final decoded = images.decodeGif(bytes);
      if (decoded == null) throw StateError('Cannot decode original GIF');
      files.add({
        'path': filename,
        'timeUtc': time.toIso8601String(),
        'layer': layerName,
        'sha256': digest(bytes),
      });
      for (final s in stations.values) {
        final point = s['point'] as List<int>?;
        if (point == null) continue;
        final pixel = decoded.getPixel(point[0], point[1]);
        final rgb = [pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()];
        final value = NiedGifValueDecoder.decodeObservationFromRgba(
          rgb[0],
          rgb[1],
          rgb[2],
          layer: layer,
        );
        (s['samples'] as List).add({
          'timeUtc': time.toIso8601String(),
          'layer': layerName,
          'rgb': rgb,
          'value': layer == NiedGifLayer.realtimeShindo
              ? value?.shindo
              : value?.pga,
        });
      }
    }
    final missing = <String>[];
    for (
      var time = start;
      !time.isAfter(end);
      time = time.add(const Duration(seconds: 1))
    ) {
      if (!(times['jma_s']?.contains(time.millisecondsSinceEpoch) ?? false)) {
        missing.add(time.toUtc().toIso8601String());
      }
    }
    cases.add({
      'caseId': fixture['caseId'],
      'fixture': fixtures[i],
      'waveformArchiveSha256': archive['sha256'],
      'missingSurfaceFramesUtc': missing,
      'layerFrameCounts': {
        for (final e in times.entries) e.key: e.value.length,
      },
      'files': files,
      'stations': stations.values.toList(),
    });
  }
  for (final e in hashes.entries) {
    if (digest(File(e.key).readAsBytesSync()) != e.value) {
      throw StateError('Input changed during extraction');
    }
  }
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'feedsProduction': false, 'scanPositionsSha256': scanHash, 'decoderVersion': NiedGifValueDecoder.decoderVersion, 'inputSha256': hashes, 'cases': cases, 'scope': 'Exact station-code original surface GIF extraction. No clock shift, missing-value fill, event selection or waveform substitution.'})}\n',
    encoding: utf8,
  );
  stdout.writeln(
    jsonEncode(
      cases
          .map(
            (c) => {
              'caseId': c['caseId'],
              'frames': c['layerFrameCounts'],
              'stations': (c['stations'] as List).length,
              'missingFrames': (c['missingSurfaceFramesUtc'] as List).length,
            },
          )
          .toList(),
    ),
  );
}
