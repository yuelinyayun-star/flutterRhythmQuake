import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

const _minimumDepthKm = 5.0;
const _maximumDepthKm = 100.0;
const _depthStepKm = 5.0;
const _magnitudeSearchSpec = Matsuzaki2006ForwardSearchSpec(
  magnitudeScanStep: 0.1,
  refinementTolerance: 1e-7,
  objectiveTieTolerance: 1e-10,
  maximumRefinementIterations: 100,
);
const _inputSpec = Matsuzaki2006ArchiveInputSpec(
  initialSearchRadiusKm: 100,
  maximumHorizontalSearchDistanceKm: 250,
  minimumSearchDepthKm: _minimumDepthKm,
  maximumSearchDepthKm: _maximumDepthKm,
  minimumObservations: 10,
  maximumObservations: 300,
  minimumInstrumentalIntensity: 0.5,
);

void main(List<String> arguments) {
  final inversionReportPath = _value(arguments, '--inversion-report');
  final inputPaths = _values(arguments, '--input');
  final outputDirectory = Directory(
    _value(arguments, '--output-dir') ??
        '.dart_tool/matsuzaki_2006_source_backed_depth_profile',
  );
  if (inversionReportPath == null || inputPaths.isEmpty) {
    stderr.writeln(
      'Usage: dart run '
      'tool/matsuzaki_2006_source_backed_depth_profile_diagnostic.dart '
      '--inversion-report <report.json> --input <annual.json> [...] '
      '[--output-dir <directory>]',
    );
    exitCode = 64;
    return;
  }
  if (!File(inversionReportPath).existsSync()) {
    stderr.writeln('Inversion report does not exist: $inversionReportPath');
    exitCode = 66;
    return;
  }
  final missing = inputPaths.where((path) => !File(path).existsSync()).toList();
  if (missing.isNotEmpty) {
    stderr.writeln('Missing input files: ${missing.join(', ')}');
    exitCode = 66;
    return;
  }

  final inversion = _readObject(inversionReportPath);
  final rawEventsById = <String, Map<String, Object?>>{};
  for (final path in inputPaths) {
    final decoded = _readObject(path);
    final rawEvents = decoded['events'];
    if (rawEvents is! List<Object?>) {
      throw FormatException('Invalid annual dataset: $path');
    }
    for (final raw in rawEvents) {
      if (raw is! Map<String, Object?> || raw['eventId'] is! String) continue;
      rawEventsById[raw['eventId']! as String] = raw;
    }
  }
  final reportEvents = inversion['events'];
  if (reportEvents is! List<Object?>) {
    throw const FormatException('Inversion report has no events list.');
  }
  final models = <String, Matsuzaki2006AttenuationModel>{
    'published': const Matsuzaki2006AttenuationModel(),
    'finiteFaultSemanticFrozen2017': const Matsuzaki2006AttenuationModel(
      coefficients:
          Matsuzaki2006AttenuationCoefficients.finiteFaultSemanticFrozen2017,
    ),
  };
  const inputBuilder = Matsuzaki2006ArchiveInversionInputBuilder();
  final eventReports = <Map<String, Object?>>[];
  final rows = <Map<String, Object?>>[];

  for (final reportEventRaw in reportEvents) {
    if (reportEventRaw is! Map<String, Object?> ||
        reportEventRaw['eventId'] is! String) {
      throw const FormatException('Invalid event in inversion report.');
    }
    final eventId = reportEventRaw['eventId']! as String;
    final rawEvent = rawEventsById[eventId];
    if (rawEvent == null) throw StateError('Raw event not found: $eventId');
    final truth = _truth(rawEvent);
    final input = inputBuilder.build(rawEvent: rawEvent, spec: _inputSpec);
    if (!input.isReady) throw StateError('Input is not ready: $eventId');
    final reportModels = reportEventRaw['models'];
    if (reportModels is! Map<String, Object?>) {
      throw StateError('Inversion report has no models for $eventId');
    }
    final modelReports = <String, Object?>{};
    for (final modelEntry in models.entries) {
      final inversionModel = reportModels[modelEntry.key];
      if (inversionModel is! Map<String, Object?>) {
        throw StateError('Missing ${modelEntry.key} result for $eventId');
      }
      final bestCandidates = inversionModel['bestCandidates'];
      if (bestCandidates is! List<Object?> || bestCandidates.isEmpty) {
        throw StateError(
          'No returned candidate for $eventId/${modelEntry.key}',
        );
      }
      final best = bestCandidates.first;
      if (best is! Map<String, Object?> ||
          best['latitude'] is! num ||
          best['longitude'] is! num) {
        throw StateError(
          'Invalid returned candidate for $eventId/${modelEntry.key}',
        );
      }
      final latitude = (best['latitude']! as num).toDouble();
      final longitude = (best['longitude']! as num).toDouble();
      final scorer = Matsuzaki2006ForwardResidualScorer(
        model: modelEntry.value,
      );
      final points = <Map<String, Object?>>[];
      for (
        var depthKm = _minimumDepthKm;
        depthKm <= _maximumDepthKm + 1e-9;
        depthKm += _depthStepKm
      ) {
        final score = scorer.score(
          observations: input.observations,
          source: Matsuzaki2006CandidateSource(
            latitude: latitude,
            longitude: longitude,
            depthKm: depthKm,
          ),
          minimumObservations: _inputSpec.minimumObservations,
          searchSpec: _magnitudeSearchSpec,
        );
        if (!score.isValid || score.solutions.isEmpty) {
          throw StateError(
            'Invalid profile point $eventId/${modelEntry.key}/$depthKm',
          );
        }
        final solution = score.solutions.first;
        points.add({
          'depthKm': depthKm,
          'magnitude': solution.magnitude,
          'rms': solution.intensityRms,
          'meanResidual': solution.meanIntensityResidual,
        });
      }
      final minimumRms = points
          .map((point) => (point['rms']! as num).toDouble())
          .reduce(math.min);
      final bestPoints = points
          .where(
            (point) =>
                ((point['rms']! as num).toDouble() - minimumRms).abs() <= 1e-10,
          )
          .toList();
      final envelope = points
          .where(
            (point) =>
                (point['rms']! as num).toDouble() - minimumRms <= 0.05 + 1e-12,
          )
          .toList();
      final catalogDepthPoint = points.firstWhere(
        (point) =>
            ((point['depthKm']! as num).toDouble() - truth.depthKm).abs() <
            _depthStepKm / 2 + 1e-9,
        orElse: () => points.reduce(
          (left, right) =>
              ((left['depthKm']! as num).toDouble() - truth.depthKm).abs() <
                  ((right['depthKm']! as num).toDouble() - truth.depthKm).abs()
              ? left
              : right,
        ),
      );
      final row = <String, Object?>{
        'eventId': eventId,
        'model': modelEntry.key,
        'returnedLatitude': latitude,
        'returnedLongitude': longitude,
        'catalogLatitude': truth.latitude,
        'catalogLongitude': truth.longitude,
        'catalogDepthKm': truth.depthKm,
        'minimumRms': minimumRms,
        'bestDepthsKm': [for (final point in bestPoints) point['depthKm']],
        'bestMagnitudes': [for (final point in bestPoints) point['magnitude']],
        'bestDepthBoundaryContacts': [
          if (bestPoints.any((point) => point['depthKm'] == _minimumDepthKm))
            'depthMinimum',
          if (bestPoints.any((point) => point['depthKm'] == _maximumDepthKm))
            'depthMaximum',
        ],
        'rmsEnvelope': {
          'maximumRmsIncrease': 0.05,
          'minimumDepthKm': envelope
              .map((point) => (point['depthKm']! as num).toDouble())
              .reduce(math.min),
          'maximumDepthKm': envelope
              .map((point) => (point['depthKm']! as num).toDouble())
              .reduce(math.max),
        },
        'catalogDepthNearestGridPoint': catalogDepthPoint,
        'points': points,
      };
      modelReports[modelEntry.key] = row;
      rows.add(row);
      stdout.writeln(
        '$eventId ${modelEntry.key}: bestDepth=${bestPoints.map((point) => point['depthKm']).join(',')} '
        'rms=$minimumRms envelope=${row['rmsEnvelope']}',
      );
    }
    eventReports.add({
      'eventId': eventId,
      'truth': truth.toJson(),
      'inputSelectedObservationCount': input.observations.length,
      'models': modelReports,
    });
  }

  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_source_backed_depth_profile_diagnostic_v1',
    'protocolStatus': 'source_backed_point_source_depth_profile_diagnostic_v1',
    'purpose':
        'Profile depth at the previously returned horizontal point-source candidate with magnitude re-optimized at each depth.',
    'inputPolicy': {
      'rawAnnualDatasetsRead': inputPaths,
      'inversionReportRead': inversionReportPath,
      'observationsModified': false,
      'catalogTruthUsedFor': 'post-profile comparison only',
      'finiteFaultGeometryUsed': false,
      'productionAlgorithmChanged': false,
    },
    'profileProtocol': {
      'horizontalLocation':
          'first returned candidate from prior point-source inversion report',
      'minimumDepthKm': _minimumDepthKm,
      'maximumDepthKm': _maximumDepthKm,
      'depthStepKm': _depthStepKm,
      'magnitudeReoptimizedAtEachDepth': true,
      'rmsEnvelopeIncrease': 0.05,
    },
    'events': eventReports,
    'rows': rows,
  };
  outputDirectory.createSync(recursive: true);
  File('${outputDirectory.path}/report.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    encoding: utf8,
  );
  File(
    '${outputDirectory.path}/report.md',
  ).writeAsStringSync(_markdown(eventReports, rows), encoding: utf8);
  stdout.writeln('wrote ${outputDirectory.path}/report.json');
  stdout.writeln('wrote ${outputDirectory.path}/report.md');
}

Map<String, Object?> _readObject(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync(encoding: utf8));
  if (decoded is! Map<String, Object?>) {
    throw FormatException('Expected JSON object: $path');
  }
  return decoded;
}

String _markdown(
  List<Map<String, Object?>> events,
  List<Map<String, Object?>> rows,
) {
  final buffer = StringBuffer()
    ..writeln('# 有来源有限断层事件的深度 RMS 剖面')
    ..writeln()
    ..writeln('水平位置固定为上一轮点源联合反演返回的第一候选；每个深度重新优化共同震级。该剖面只识别深度可辨识性，不用于调搜索参数。')
    ..writeln()
    ..writeln(
      '| 事件 | 模型 | 返回水平位置 | 最优深度 km | 最低 RMS | RMS +0.05 深度范围 | 目录深度 | 边界 |',
    )
    ..writeln('|---|---|---|---:|---:|---|---:|---|');
  for (final row in rows) {
    final envelope = row['rmsEnvelope']! as Map<String, Object?>;
    buffer.writeln(
      '| `${row['eventId']}` | `${row['model']}` | '
      '${_fixed(row['returnedLatitude'])}, ${_fixed(row['returnedLongitude'])} | '
      '${(row['bestDepthsKm']! as List<Object?>).join(', ')} | '
      '${_fixed(row['minimumRms'])} | '
      '${_fixed(envelope['minimumDepthKm'])}-${_fixed(envelope['maximumDepthKm'])} | '
      '${_fixed(row['catalogDepthKm'])} | '
      '${(row['bestDepthBoundaryContacts']! as List<Object?>).join(', ')} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## 解释')
    ..writeln()
    ..writeln('- 最优深度在边界且 RMS 曲线仍向边界下降，表示当前数据/模型下深度未被识别，不能称为收敛。')
    ..writeln('- `RMS + 0.05` 范围是网格诊断包络，不是概率置信区间。')
    ..writeln('- 水平位置来自上一轮搜索结果，目录震源只用于事后标注和误差比较。')
    ..writeln()
    ..writeln('事件数：${events.length}；剖面数：${rows.length}。');
  return buffer.toString();
}

class _Truth {
  const _Truth({
    required this.eventId,
    required this.originTime,
    required this.latitude,
    required this.longitude,
    required this.depthKm,
    required this.magnitude,
  });

  final String eventId;
  final String originTime;
  final double latitude;
  final double longitude;
  final double depthKm;
  final double magnitude;

  Map<String, Object> toJson() => {
    'originTime': originTime,
    'latitude': latitude,
    'longitude': longitude,
    'depthKm': depthKm,
    'magnitude': magnitude,
  };
}

_Truth _truth(Map<String, Object?> rawEvent) {
  final id = rawEvent['eventId'];
  final rawHypocenter = rawEvent['preferredHypocenter'];
  if (id is! String || rawHypocenter is! Map<String, Object?>) {
    throw const FormatException('Invalid target event truth.');
  }
  double number(String key) {
    final value = rawHypocenter[key];
    if (value is! num || !value.isFinite) {
      throw FormatException('Invalid $key for $id.');
    }
    return value.toDouble();
  }

  return _Truth(
    eventId: id,
    originTime: rawHypocenter['originTime'] is String
        ? rawHypocenter['originTime']! as String
        : '',
    latitude: number('latitude'),
    longitude: number('longitude'),
    depthKm: number('depthKm'),
    magnitude: number('magnitude'),
  );
}

String _fixed(Object? value) =>
    value is num ? value.toDouble().toStringAsFixed(3) : '-';

String? _value(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index < 0 || index + 1 >= arguments.length) return null;
  return arguments[index + 1];
}

List<String> _values(List<String> arguments, String name) {
  final values = <String>[];
  for (var index = 0; index < arguments.length - 1; index++) {
    if (arguments[index] == name) values.add(arguments[index + 1]);
  }
  return values;
}
