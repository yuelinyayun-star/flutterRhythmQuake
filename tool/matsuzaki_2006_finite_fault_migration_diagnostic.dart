import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

const _requiredYears = {2011, 2014, 2016, 2018};

void main(List<String> arguments) {
  final inputPaths = _values(arguments, '--input');
  final outputDirectory = Directory(
    _value(arguments, '--output-dir') ??
        '.dart_tool/matsuzaki_2006_finite_fault_migration_diagnostic',
  );
  if (inputPaths.isEmpty || !arguments.contains('--allow-opened-2018')) {
    stderr.writeln(
      'Usage: dart run '
      'tool/matsuzaki_2006_finite_fault_migration_diagnostic.dart '
      '--input <annual.json> [...] --allow-opened-2018 '
      '[--output-dir <directory>]',
    );
    exitCode = 64;
    return;
  }
  final missing = inputPaths.where((path) => !File(path).existsSync()).toList();
  if (missing.isNotEmpty) {
    stderr.writeln('Missing input files: ${missing.join(', ')}');
    exitCode = 66;
    return;
  }

  final datasets = <Map<String, Object?>>[];
  final seenYears = <int>{};
  for (final path in inputPaths) {
    final decoded = jsonDecode(File(path).readAsStringSync(encoding: utf8));
    if (decoded is! Map<String, Object?> || decoded['year'] is! num) {
      throw FormatException('Invalid annual dataset: $path');
    }
    final year = (decoded['year']! as num).toInt();
    if (!seenYears.add(year)) {
      throw StateError('Duplicate annual dataset: $year');
    }
    datasets.add(decoded);
  }
  final missingYears = _requiredYears.difference(seenYears);
  if (missingYears.isNotEmpty) {
    throw StateError(
      'Missing required annual datasets: ${missingYears.toList()..sort()}',
    );
  }

  final baseline = const Matsuzaki2006JmaBaselineEvaluator().evaluate(datasets);
  final eventsById = {
    for (final event in baseline.events) event.eventId: event,
  };
  final models = <String, Matsuzaki2006AttenuationModel>{
    'published': const Matsuzaki2006AttenuationModel(),
    'finiteFaultSemanticFrozen2017': const Matsuzaki2006AttenuationModel(
      coefficients:
          Matsuzaki2006AttenuationCoefficients.finiteFaultSemanticFrozen2017,
    ),
  };
  final eventReports = <Map<String, Object?>>[];
  final aggregateRows = <Map<String, Object?>>[];

  for (final geometry
      in Matsuzaki2006SourceBackedDistanceOverrides.eventGeometries) {
    final event = eventsById[geometry.eventId];
    if (event == null) {
      throw StateError('Missing accepted event ${geometry.eventId}.');
    }
    for (final variant in geometry.variants) {
      final override =
          Matsuzaki2006SourceBackedDistanceOverrides.evaluateVariant(
            event: event,
            geometry: geometry,
            variant: variant,
          );
      final evaluable = override.stations
          .where((station) => station.isInsidePublishedDistanceDomain)
          .toList();
      final modelReports = <String, Object?>{};
      for (final modelEntry in models.entries) {
        final paired = <Map<String, double>>[];
        for (final station in evaluable) {
          final pointPrediction = modelEntry.value.predictIntensity(
            magnitude: event.magnitude,
            sourceDistanceKm: station.pointSourceDistanceKm,
            depthKm: event.depthKm,
          );
          final finitePrediction = modelEntry.value.predictIntensity(
            magnitude: event.magnitude,
            sourceDistanceKm: station.finiteFaultDistanceKm,
            depthKm: event.depthKm,
          );
          paired.add({
            'observed': station.originalStation.observedIntensity,
            'pointPrediction': pointPrediction,
            'finitePrediction': finitePrediction,
            'predictionDelta': finitePrediction - pointPrediction,
            'pointResidual':
                station.originalStation.observedIntensity - pointPrediction,
            'finiteResidual':
                station.originalStation.observedIntensity - finitePrediction,
          });
        }
        final report = _metricReport(paired);
        modelReports[modelEntry.key] = report;
        aggregateRows.add({
          'eventId': event.eventId,
          'year': event.year,
          'variantId': variant.id,
          'model': modelEntry.key,
          ...report,
        });
      }
      eventReports.add({
        'eventId': event.eventId,
        'year': event.year,
        'regionName': geometry.regionName,
        'geometryVariantId': variant.id,
        'geometryLabel': variant.label,
        'sourceBackedDistanceDomain': {'minimumKm': 1.0, 'maximumKm': 500.0},
        'originalAcceptedStationCount': override.stations.length,
        'evaluableStationCount': evaluable.length,
        'excludedOutsideDomainCount':
            override.excludedOutsidePublishedDistanceDomainCount,
        'finiteFaultDistanceKm': _summary(
          evaluable.map((station) => station.finiteFaultDistanceKm),
        ),
        'pointSourceDistanceKm': _summary(
          evaluable.map((station) => station.pointSourceDistanceKm),
        ),
        'modelReports': modelReports,
      });
    }
  }

  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_finite_fault_migration_diagnostic_v1',
    'purpose':
        'Quantify point-source versus source-backed finite-fault distance migration error at catalog truth.',
    'inputPolicy': {
      'rawAnnualDatasetsRead': inputPaths,
      'observationsModified': false,
      'catalogTruthUsedFor':
          'diagnostic source geometry and post-hoc metric reference only',
      'productionAlgorithmChanged': false,
      'formulaDomainKm': [1.0, 500.0],
    },
    'models': {
      for (final entry in models.entries)
        entry.key: entry.value.coefficients.toJson(),
    },
    'events': eventReports,
    'aggregateRows': aggregateRows,
  };
  outputDirectory.createSync(recursive: true);
  File('${outputDirectory.path}/report.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    encoding: utf8,
  );
  File(
    '${outputDirectory.path}/report.md',
  ).writeAsStringSync(_markdown(eventReports, aggregateRows), encoding: utf8);
  stdout.writeln('wrote ${outputDirectory.path}/report.json');
  stdout.writeln('wrote ${outputDirectory.path}/report.md');
}

Map<String, Object> _metricReport(List<Map<String, double>> rows) {
  double rms(String key) => _rms(rows.map((row) => row[key]!));
  final deltas = rows.map((row) => row['predictionDelta']!).toList();
  final absoluteDeltas = deltas.map((value) => value.abs()).toList();
  return {
    'pairedStationCount': rows.length,
    'pointResidualRms': rms('pointResidual'),
    'finiteFaultResidualRms': rms('finiteResidual'),
    'rmsChangeFiniteMinusPoint': rms('finiteResidual') - rms('pointResidual'),
    'meanPredictionDeltaFiniteMinusPoint': _mean(deltas),
    'meanAbsolutePredictionDeltaFiniteMinusPoint': _mean(absoluteDeltas),
    'maximumAbsolutePredictionDeltaFiniteMinusPoint': absoluteDeltas.reduce(
      math.max,
    ),
    'finiteResidualImprovesRms': rms('finiteResidual') < rms('pointResidual'),
  };
}

Map<String, Object> _summary(Iterable<double> values) {
  final list = values.toList();
  if (list.isEmpty) return const {'count': 0};
  list.sort();
  return {
    'count': list.length,
    'minimumKm': list.first,
    'medianKm': list[list.length ~/ 2],
    'meanKm': _mean(list),
    'maximumKm': list.last,
  };
}

double _rms(Iterable<double> values) {
  final list = values.toList();
  if (list.isEmpty) return 0;
  return math.sqrt(
    list.fold(0.0, (sum, value) => sum + value * value) / list.length,
  );
}

double _mean(Iterable<double> values) {
  final list = values.toList();
  if (list.isEmpty) return 0;
  return list.reduce((left, right) => left + right) / list.length;
}

String _markdown(
  List<Map<String, Object?>> events,
  List<Map<String, Object?>> rows,
) {
  final buffer = StringBuffer()
    ..writeln('# 松崎式有限断层距离迁移诊断')
    ..writeln()
    ..writeln(
      '本报告只读原始 JMA 归档，在目录震源位置、深度和震级固定时，比较点源距与已审计来源有限断层距对同一前向公式的影响。它不等价于未知事件定位精度，也不把目录真值送入生产搜索。',
    )
    ..writeln()
    ..writeln('公式域外的有限断层距离保留在原始几何记录中，但不进入 RMS；没有钳到 1 km。')
    ..writeln()
    ..writeln(
      '| 年 | 事件 | 几何 | 站数 | 模型 | 点源 RMS | 有限断层 RMS | RMS 变化 | 平均预测变化 | 最大绝对预测变化 |',
    )
    ..writeln('|---:|---|---|---:|---|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buffer.writeln(
      '| ${row['year']} | `${row['eventId']}` | `${row['variantId']}` | '
      '${row['pairedStationCount']} | `${row['model']}` | '
      '${_fixed(row['pointResidualRms'])} | ${_fixed(row['finiteFaultResidualRms'])} | '
      '${_fixed(row['rmsChangeFiniteMinusPoint'])} | '
      '${_fixed(row['meanPredictionDeltaFiniteMinusPoint'])} | '
      '${_fixed(row['maximumAbsolutePredictionDeltaFiniteMinusPoint'])} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## 解释')
    ..writeln()
    ..writeln('- `有限断层 RMS - 点源 RMS < 0` 表示在已知来源几何下，有限断层距离更贴近观测；这只是前向距离语义证据。')
    ..writeln('- `平均预测变化` 为有限断层预测震度减去点源预测震度；正值表示同一站被预测得更强。')
    ..writeln('- 未知事件没有已观测断层面，因此该结果不能直接授权把有限断层距写入未知事件联合搜索。')
    ..writeln()
    ..writeln('事件级几何记录数：${events.length}；配对模型记录数：${rows.length}。');
  return buffer.toString();
}

String _fixed(Object? value) =>
    value is num ? value.toDouble().toStringAsFixed(6) : '$value';

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
