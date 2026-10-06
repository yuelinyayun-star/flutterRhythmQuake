import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutterrhythmquake/models/nied_scan_positions.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';

void main(List<String> args) {
  if (args.length != 2) {
    throw ArgumentError('Pass pinned upstream JSON and new report path');
  }
  final bytes = File(args[0]).readAsBytesSync();
  final source = (jsonDecode(utf8.decode(bytes)) as List).cast<Map>();
  final local = NiedScanPositions.points;
  final additions = <Map<String, Object?>>[];
  final changed = <Map<String, Object?>>[];
  final unknown = <String>[];
  final noPoint = <String>[];
  final db = NiedStationDb.stations.map((s) => s['code']).toSet();
  Map<String, int> fields(NiedScanPoint p) => {
    'centerX': p.centerX,
    'centerY': p.centerY,
    'offsetX': p.offsetX,
    'offsetY': p.offsetY,
    'sampleX': p.sampleX,
    'sampleY': p.sampleY,
  };
  for (final s in source) {
    final code = s['code'] as String;
    final p = s['point'] as Map?;
    if (p == null) {
      noPoint.add(code);
      continue;
    }
    final center = p['center_point'] as Map;
    final offset = p['offset'] as Map;
    final point = NiedScanPoint(
      centerX: center['x'] as int,
      centerY: center['y'] as int,
      offsetX: offset['x'] as int,
      offsetY: offset['y'] as int,
    );
    if (!db.contains(code)) unknown.add(code);
    final previous = local[code];
    final row = <String, Object?>{
      'code': code,
      'upstream': fields(point),
      'localPixelConflicts': [
        for (final entry in local.entries)
          if (entry.key != code &&
              entry.value.sampleX == point.sampleX &&
              entry.value.sampleY == point.sampleY)
            entry.key,
      ],
    };
    if (previous == null) {
      additions.add(row);
    } else if (jsonEncode(fields(previous)) != jsonEncode(fields(point))) {
      changed.add({...row, 'local': fields(previous)});
    }
  }
  final result = {
    'upstreamSha256': sha256.convert(bytes).toString(),
    'localScanSha256': sha256
        .convert(File('lib/models/nied_scan_positions.dart').readAsBytesSync())
        .toString(),
    'localCount': local.length,
    'upstreamCount': source.length,
    'upstreamPositionCount': source.length - noPoint.length,
    'unknownStationCodes': unknown,
    'additions': additions,
    'changedShared': changed,
    'upstreamUnmapped': noPoint,
  };
  final file = File(args[1]);
  if (file.existsSync()) throw StateError('Output already exists');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(result)}\n',
    encoding: utf8,
  );
  stdout.writeln(jsonEncode({...result, 'upstreamUnmapped': noPoint.length}));
}
