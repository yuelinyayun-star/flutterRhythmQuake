import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/models/nied_scan_positions.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';
import 'package:flutterrhythmquake/services/sources/shindo_color_util.dart';
import 'package:image/image.dart' as image_lib;

const _defaultOutputPath =
    '.dart_tool/nied_station_layer_role_audit/report.json';
const _defaultMarkdownPath =
    'docs/baselines/nied_station_layer_role_audit.generated.md';
const _defaultProbeRoot = 'tmp/captures';

void main(List<String> args) {
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;
  final probeRoot = _argument(args, '--probe-root') ?? _defaultProbeRoot;
  final maxProbeFrames =
      int.tryParse(_argument(args, '--max-probe-frames') ?? '') ?? 12;

  final report = buildNiedStationLayerRoleAuditJson(
    probeRoot: probeRoot,
    maxProbeFrames: maxProbeFrames,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(niedStationLayerRoleAuditMarkdown(report));

  stdout.writeln('wrote NIED station layer role audit');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');
}

Map<String, Object?> buildNiedStationLayerRoleAuditJson({
  String? probeRoot = _defaultProbeRoot,
  int maxProbeFrames = 12,
}) {
  final rows = _stationRows();
  final scanMappedRows = rows
      .where((row) => row['hasScanPosition'] == true)
      .toList(growable: false);
  final currentSurface = rows
      .where((row) => row['currentPrimaryLayer'] == 'jma_s')
      .length;
  final currentBorehole = rows
      .where((row) => row['currentPrimaryLayer'] == 'jma_b')
      .length;
  final codeNetworkMismatches = rows
      .where((row) => row['codePatternMatchesNetwork'] == false)
      .toList(growable: false);

  final probe = probeRoot == null || maxProbeFrames <= 0
      ? null
      : _probeLayerPixels(
          rows: scanMappedRows,
          probeRoot: probeRoot,
          maxProbeFrames: maxProbeFrames,
        );

  final report = {
    'schemaVersion': 'nied_station_layer_role_audit_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'policy': {
      'productionBehaviorChanged': true,
      'currentRoutingRule': 'all scan-mapped stations default to jma_s',
      'supersededRoutingRule':
          'network contains "kik" => jma_b, otherwise jma_s',
      'currentRoutingLimitation':
          'jma_b is retained only as explicit auxiliary borehole provenance',
      'recommendedSeparation': [
        'network',
        'physicalSensorRole',
        'gifDisplayPrimaryLayer',
        'sourceEstimationSensorSelection',
      ],
    },
    'summary': {
      'stationCount': rows.length,
      'scanMappedStationCount': scanMappedRows.length,
      'networkCounts': _countBy(rows, 'network'),
      'codePatternCounts': _countBy(rows, 'codePatternRole'),
      'currentPrimaryLayerCounts': {
        'jma_s': currentSurface,
        'jma_b': currentBorehole,
      },
      'scanMappedCurrentPrimaryLayerCounts': _countBy(
        scanMappedRows,
        'currentPrimaryLayer',
      ),
      'codeNetworkMismatchCount': codeNetworkMismatches.length,
    },
    'codeNetworkMismatches': codeNetworkMismatches
        .take(50)
        .toList(growable: false),
    'stations': rows,
  };
  if (probe != null) {
    report['gifLayerProbe'] = probe;
  }
  return report;
}

List<Map<String, Object?>> _stationRows() {
  return [
    for (final station in NiedStationDb.stations)
      _stationRow(station.cast<String, Object?>()),
  ];
}

Map<String, Object?> _stationRow(Map<String, Object?> station) {
  final code = station['code']! as String;
  final network = station['network'] as String? ?? 'K-NET';
  final networkLower = network.toLowerCase();
  final isKikByNetwork = networkLower.contains('kik');
  final codePatternRole = _codePatternRole(code);
  final position = NiedScanPositions.positions[code];
  return {
    'code': code,
    'lat': station['lat'],
    'lng': station['lng'],
    'network': network,
    'networkInferredPhysicalRole': isKikByNetwork ? 'borehole' : 'surface',
    'currentPrimaryLayer': 'jma_s',
    'legacyNetworkInferredPrimaryLayer': isKikByNetwork ? 'jma_b' : 'jma_s',
    'codePatternRole': codePatternRole,
    'codePatternMatchesNetwork':
        (isKikByNetwork && codePatternRole == 'kik_like') ||
        (!isKikByNetwork && codePatternRole == 'knet_like') ||
        codePatternRole == 'unknown',
    'hasScanPosition': position != null,
    if (position != null) 'pixelX': position[0],
    if (position != null) 'pixelY': position[1],
  };
}

String _codePatternRole(String code) {
  if (RegExp(r'^[A-Z]{3}\d{3}$').hasMatch(code)) return 'knet_like';
  if (RegExp(r'^[A-Z]{3}H\d{2}$').hasMatch(code)) return 'kik_like';
  return 'unknown';
}

Map<String, int> _countBy(List<Map<String, Object?>> rows, String key) {
  final counts = <String, int>{};
  for (final row in rows) {
    counts.update('${row[key]}', (value) => value + 1, ifAbsent: () => 1);
  }
  return counts;
}

Map<String, Object?> _probeLayerPixels({
  required List<Map<String, Object?>> rows,
  required String probeRoot,
  required int maxProbeFrames,
}) {
  final pairs = _findLayerPairs(Directory(probeRoot), maxProbeFrames);
  final statsByCode = {
    for (final row in rows) row['code']! as String: _LayerProbeStats(),
  };
  final decodedPairs = <Map<String, Object?>>[];

  for (final pair in pairs) {
    final surface = image_lib.decodeImage(pair.surface.readAsBytesSync());
    final borehole = image_lib.decodeImage(pair.borehole.readAsBytesSync());
    if (surface == null || borehole == null) continue;
    decodedPairs.add({
      'surface': pair.surface.path,
      'borehole': pair.borehole.path,
    });
    for (final row in rows) {
      final code = row['code']! as String;
      final x = row['pixelX']! as int;
      final y = row['pixelY']! as int;
      final stats = statsByCode[code]!;
      final surfaceShindo = _sampleShindo(surface, x, y);
      final boreholeShindo = _sampleShindo(borehole, x, y);
      stats.add(surfaceShindo: surfaceShindo, boreholeShindo: boreholeShindo);
    }
  }

  final suspiciousKikSurfaceDominant = <Map<String, Object?>>[];
  for (final row in rows) {
    if (row['networkInferredPhysicalRole'] != 'borehole') continue;
    final stats = statsByCode[row['code']]!;
    final surfaceMax = stats.surfaceMax;
    final boreholeMax = stats.boreholeMax;
    if (surfaceMax == null) continue;
    final boreholeMissing = stats.boreholeDecodableCount == 0;
    final surfaceDominant =
        boreholeMax == null || surfaceMax - boreholeMax >= 0.5;
    if (boreholeMissing || surfaceDominant) {
      suspiciousKikSurfaceDominant.add({
        ...row,
        ...stats.toJson(),
        'reason': boreholeMissing
            ? 'borehole_not_decodable_in_probe'
            : 'surface_max_shindo_exceeds_borehole_by_0_5_or_more',
      });
    }
  }
  suspiciousKikSurfaceDominant.sort((left, right) {
    final leftDelta = (left['surfaceMinusBoreholeMax'] as num?) ?? 999;
    final rightDelta = (right['surfaceMinusBoreholeMax'] as num?) ?? 999;
    return rightDelta.compareTo(leftDelta);
  });

  return {
    'probeRoot': probeRoot,
    'maxProbeFrames': maxProbeFrames,
    'decodedPairCount': decodedPairs.length,
    'decodedPairs': decodedPairs,
    'interpretation':
        'Probe candidates are not automatic corrections; they identify KiK-net stations where sampled jma_s pixels are stronger or jma_b is unavailable in the sampled frames.',
    'suspiciousKikSurfaceDominantCount': suspiciousKikSurfaceDominant.length,
    'suspiciousKikSurfaceDominantTop': suspiciousKikSurfaceDominant
        .take(50)
        .toList(growable: false),
  };
}

List<_LayerPair> _findLayerPairs(Directory root, int maxProbeFrames) {
  if (!root.existsSync()) return const [];
  final surfaceFiles =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.jma_s.gif'))
          .toList(growable: false)
        ..sort((left, right) => right.path.compareTo(left.path));
  final pairs = <_LayerPair>[];
  for (final surface in surfaceFiles) {
    if (pairs.length >= maxProbeFrames) break;
    final boreholePath = surface.path.replaceFirst('.jma_s.gif', '.jma_b.gif');
    final borehole = File(boreholePath);
    if (!borehole.existsSync()) continue;
    pairs.add(_LayerPair(surface: surface, borehole: borehole));
  }
  return pairs;
}

double? _sampleShindo(image_lib.Image image, int x, int y) {
  if (x < 0 || y < 0 || x >= image.width || y >= image.height) return null;
  final pixel = image.getPixel(x, y);
  return ShindoColorUtil.rgbaToShindo(
    pixel.r.toInt(),
    pixel.g.toInt(),
    pixel.b.toInt(),
  );
}

String niedStationLayerRoleAuditMarkdown(Map<String, Object?> report) {
  final summary = (report['summary']! as Map).cast<String, Object?>();
  final networkCounts = (summary['networkCounts']! as Map)
      .cast<String, Object?>();
  final layerCounts = (summary['currentPrimaryLayerCounts']! as Map)
      .cast<String, Object?>();
  final scanMappedLayerCounts =
      (summary['scanMappedCurrentPrimaryLayerCounts']! as Map)
          .cast<String, Object?>();
  final codePatternCounts = (summary['codePatternCounts']! as Map)
      .cast<String, Object?>();
  final buffer = StringBuffer()
    ..writeln('# NIED Station Layer Role Audit')
    ..writeln()
    ..writeln('- Schema: `${report['schemaVersion']}`')
    ..writeln('- Production behavior changed: `true`')
    ..writeln(
      '- Current routing rule: `all scan-mapped stations default to jma_s`',
    )
    ..writeln(
      '- Superseded routing rule: `network contains "kik" => jma_b, otherwise jma_s`',
    )
    ..writeln(
      '- Limitation: `jma_b` is an auxiliary borehole layer, not default scoring evidence.',
    )
    ..writeln()
    ..writeln('## Summary')
    ..writeln()
    ..writeln('| Metric | Value |')
    ..writeln('|---|---:|')
    ..writeln('| Stations | ${summary['stationCount']} |')
    ..writeln('| Scan-mapped stations | ${summary['scanMappedStationCount']} |')
    ..writeln('| K-NET stations | ${networkCounts['K-NET'] ?? 0} |')
    ..writeln('| KiK-net stations | ${networkCounts['KiK-net'] ?? 0} |')
    ..writeln('| Current `jma_s` primary | ${layerCounts['jma_s'] ?? 0} |')
    ..writeln('| Current `jma_b` primary | ${layerCounts['jma_b'] ?? 0} |')
    ..writeln(
      '| Scan-mapped `jma_s` primary | ${scanMappedLayerCounts['jma_s'] ?? 0} |',
    )
    ..writeln(
      '| Scan-mapped `jma_b` primary | ${scanMappedLayerCounts['jma_b'] ?? 0} |',
    )
    ..writeln(
      '| K-NET-like station codes | ${codePatternCounts['knet_like'] ?? 0} |',
    )
    ..writeln(
      '| KiK-like station codes | ${codePatternCounts['kik_like'] ?? 0} |',
    )
    ..writeln(
      '| Code/network mismatches | ${summary['codeNetworkMismatchCount']} |',
    )
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- The current project does not have an authoritative per-station GIF layer role.',
    )
    ..writeln(
      '- The superseded implementation treated every `KiK-net` station as `jma_b`, including map display sampling.',
    )
    ..writeln(
      '- Default real-time shindo input and map station display now read `jma_s` for every scan-mapped station.',
    )
    ..writeln(
      '- `physicalSensorRole` remains separate from `gifDisplayPrimaryLayer`; `jma_b` is retained for explicit auxiliary borehole diagnostics.',
    );

  final probe = report['gifLayerProbe'];
  if (probe is Map) {
    final typed = probe.cast<String, Object?>();
    buffer
      ..writeln()
      ..writeln('## GIF Probe')
      ..writeln()
      ..writeln('- Probe root: `${typed['probeRoot']}`')
      ..writeln('- Decoded jma_s/jma_b pairs: `${typed['decodedPairCount']}`')
      ..writeln(
        '- Suspicious KiK-net surface-dominant candidates: `${typed['suspiciousKikSurfaceDominantCount']}`',
      )
      ..writeln()
      ..writeln(
        '| Code | Network | Current layer | Surface max | Borehole max | Reason |',
      )
      ..writeln('|---|---|---|---:|---:|---|');
    final top = (typed['suspiciousKikSurfaceDominantTop'] as List? ?? const [])
        .cast<Map>();
    for (final raw in top.take(20)) {
      final row = raw.cast<String, Object?>();
      buffer.writeln(
        '| `${row['code']}` | `${row['network']}` | `${row['currentPrimaryLayer']}` | '
        '${_fmt(row['surfaceMaxShindo'])} | ${_fmt(row['boreholeMaxShindo'])} | '
        '`${row['reason']}` |',
      );
    }
  }

  buffer
    ..writeln()
    ..writeln('## Follow-up')
    ..writeln()
    ..writeln(
      '1. Add explicit station metadata for `gifDisplayPrimaryLayer` instead of deriving it from `network`.',
    )
    ..writeln(
      '2. Map UI should use display-layer policy; source estimation should use sensor-selection policy.',
    )
    ..writeln(
      '3. Keep candidate coordinates and source-estimation behavior unchanged until replay metrics pass.',
    );
  return buffer.toString();
}

String _fmt(Object? value) {
  if (value is num) return value.toStringAsFixed(2);
  return '';
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

class _LayerPair {
  const _LayerPair({required this.surface, required this.borehole});

  final File surface;
  final File borehole;
}

class _LayerProbeStats {
  int surfaceDecodableCount = 0;
  int boreholeDecodableCount = 0;
  double? surfaceMax;
  double? boreholeMax;

  void add({required double? surfaceShindo, required double? boreholeShindo}) {
    if (surfaceShindo != null && surfaceShindo.isFinite) {
      surfaceDecodableCount++;
      surfaceMax = surfaceMax == null
          ? surfaceShindo
          : surfaceMax! > surfaceShindo
          ? surfaceMax
          : surfaceShindo;
    }
    if (boreholeShindo != null && boreholeShindo.isFinite) {
      boreholeDecodableCount++;
      boreholeMax = boreholeMax == null
          ? boreholeShindo
          : boreholeMax! > boreholeShindo
          ? boreholeMax
          : boreholeShindo;
    }
  }

  Map<String, Object?> toJson() => {
    'surfaceDecodableCount': surfaceDecodableCount,
    'boreholeDecodableCount': boreholeDecodableCount,
    'surfaceMaxShindo': surfaceMax,
    'boreholeMaxShindo': boreholeMax,
    'surfaceMinusBoreholeMax': surfaceMax == null || boreholeMax == null
        ? null
        : surfaceMax! - boreholeMax!,
  };
}
