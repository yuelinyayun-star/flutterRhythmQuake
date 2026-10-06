import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as images;
import 'package:path/path.dart' as path;
import 'package:flutterrhythmquake/models/nied_scan_positions.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_value_decoder.dart';

String hash(List<int> bytes) => sha256.convert(bytes).toString();

void main(List<String> args) {
  if (args.length < 5) {
    throw ArgumentError(
      'Pass GIF extraction, case ID, frozen upstream points, codes..., new output',
    );
  }
  final output = File(args.last);
  final root = Directory('.dart_tool').resolveSymbolicLinksSync();
  final parent = output.parent.resolveSymbolicLinksSync();
  if (output.existsSync() ||
      path.extension(output.path) != '.json' ||
      (!path.equals(root, parent) && !path.isWithin(root, parent))) {
    throw StateError('Use new JSON in existing .dart_tool directory');
  }
  final inputBytes = File(args.first).readAsBytesSync();
  final input = jsonDecode(utf8.decode(inputBytes)) as Map;
  final event = (input['cases'] as List).cast<Map>().singleWhere(
    (c) => c['caseId'] == args[1],
  );
  final scanBytes = File(
    'lib/models/nied_scan_positions.dart',
  ).readAsBytesSync();
  if (hash(scanBytes) != input['scanPositionsSha256']) {
    throw StateError('Scan table changed');
  }
  final upstreamBytes = File(args[2]).readAsBytesSync();
  final upstream = (jsonDecode(utf8.decode(upstreamBytes)) as List).cast<Map>();
  final db = {for (final s in NiedStationDb.stations) s['code']: s};
  final codes = args.sublist(3, args.length - 1);
  if (codes.toSet().length != codes.length) throw StateError('Duplicate codes');
  final stations = <String, Map<String, Object?>>{};
  for (final code in codes) {
    final point = NiedScanPositions.points[code];
    if (point == null) throw StateError('No scan point for $code');
    final saved = (event['stations'] as List).cast<Map>().singleWhere(
      (s) => s['code'] == code,
    );
    if (jsonEncode(saved['point']) !=
        jsonEncode([point.sampleX, point.sampleY])) {
      throw StateError('Original extraction point changed');
    }
    final up = upstream.singleWhere((s) => s['code'] == code);
    stations[code] = {
      'code': code,
      'stationMetadata': db[code],
      'upstream': up,
      'samplePoint': [point.sampleX, point.sampleY],
      'nearbyPoints': [
        for (final e in NiedScanPositions.points.entries)
          if (e.key != code &&
              (e.value.sampleX - point.sampleX).abs() <= 4 &&
              (e.value.sampleY - point.sampleY).abs() <= 4)
            {
              'code': e.key,
              'samplePoint': [e.value.sampleX, e.value.sampleY],
            },
      ],
      'frames': <Map<String, Object?>>[],
    };
  }
  final files = (event['files'] as List)
      .cast<Map>()
      .where((f) => f['layer'] == 'jma_s')
      .toList();
  for (final file in files) {
    final bytes = File(file['path'] as String).readAsBytesSync();
    if (hash(bytes) != file['sha256']) throw StateError('Original GIF changed');
    final decoded = images.decodeGif(bytes);
    if (decoded == null) throw StateError('Cannot decode GIF');
    for (final code in codes) {
      final point = NiedScanPositions.points[code]!;
      final pixels = <Map<String, Object?>>[];
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final pixel = decoded.getPixel(
            point.sampleX + dx,
            point.sampleY + dy,
          );
          final rgb = [pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()];
          pixels.add({
            'dx': dx,
            'dy': dy,
            'rgb': rgb,
            'intensity': NiedGifValueDecoder.decodeObservationFromRgba(
              rgb[0],
              rgb[1],
              rgb[2],
            )?.shindo,
          });
        }
      }
      final saved = (event['stations'] as List).cast<Map>().singleWhere(
        (s) => s['code'] == code,
      );
      final observation = (saved['samples'] as List).cast<Map>().singleWhere(
        (s) => s['layer'] == 'jma_s' && s['timeUtc'] == file['timeUtc'],
      );
      if (jsonEncode(pixels[4]['rgb']) != jsonEncode(observation['rgb']) ||
          pixels[4]['intensity'] != observation['value']) {
        throw StateError('Center differs from preceding extraction');
      }
      final nearby = <Map<String, Object?>>[];
      for (final n in (stations[code]!['nearbyPoints'] as List).cast<Map>()) {
        final p = (n['samplePoint'] as List).cast<int>();
        final pixel = decoded.getPixel(p[0], p[1]);
        final rgb = [pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()];
        nearby.add({
          'code': n['code'],
          'rgb': rgb,
          'intensity': NiedGifValueDecoder.decodeObservationFromRgba(
            rgb[0],
            rgb[1],
            rgb[2],
          )?.shindo,
        });
      }
      (stations[code]!['frames'] as List).add({
        'timeUtc': file['timeUtc'],
        'pixels': pixels,
        'nearby': nearby,
      });
    }
  }
  for (final s in stations.values) {
    final frames = (s['frames'] as List).cast<Map>();
    s['neighborhoodSummary'] = [
      for (var p = 0; p < 9; p++)
        {
          'dx': p % 3 - 1,
          'dy': p ~/ 3 - 1,
          'sameRgbAsCenterFrames': frames
              .where(
                (f) =>
                    jsonEncode((f['pixels'] as List)[p]['rgb']) ==
                    jsonEncode((f['pixels'] as List)[4]['rgb']),
              )
              .length,
          'validFrames': frames
              .where((f) => (f['pixels'] as List)[p]['intensity'] != null)
              .length,
        },
    ];
    s['nearbySummary'] = [
      for (final n in (s['nearbyPoints'] as List).cast<Map>())
        {
          'code': n['code'],
          'sameRgbAsCenterFrames': frames
              .where(
                (f) =>
                    jsonEncode(
                      (f['nearby'] as List).cast<Map>().singleWhere(
                        (p) => p['code'] == n['code'],
                      )['rgb'],
                    ) ==
                    jsonEncode((f['pixels'] as List)[4]['rgb']),
              )
              .length,
        },
    ];
  }
  for (final file in files) {
    if (hash(File(file['path'] as String).readAsBytesSync()) !=
        file['sha256']) {
      throw StateError('GIF changed during inspection');
    }
  }
  if (hash(File(args.first).readAsBytesSync()) != hash(inputBytes) ||
      hash(File(args[2]).readAsBytesSync()) != hash(upstreamBytes) ||
      hash(File('lib/models/nied_scan_positions.dart').readAsBytesSync()) !=
          hash(scanBytes)) {
    throw StateError('Metadata changed');
  }
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'feedsProduction': false, 'caseId': args[1], 'frameCount': files.length, 'extractionSha256': hash(inputBytes), 'upstreamSha256': hash(upstreamBytes), 'scanSha256': hash(scanBytes), 'stations': stations.values.toList(), 'scope': 'Fixed 3x3 raw neighborhood, no best-pixel selection, no mapping changes. Matching upstream does not prove historical station identity.'})}\n',
    encoding: utf8,
  );
  stdout.writeln(
    jsonEncode(
      stations.values
          .map(
            (s) => {
              'code': s['code'],
              'point': s['samplePoint'],
              'nearby': s['nearbyPoints'],
              'pixels': s['neighborhoodSummary'],
              'nearbySame': s['nearbySummary'],
            },
          )
          .toList(),
    ),
  );
}
