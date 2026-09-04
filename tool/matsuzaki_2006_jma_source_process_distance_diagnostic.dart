import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

const _targetEventIds = <String>{
  '2011041214074228-37.0525-140.6435',
  '2014112222081790-36.6928-137.8910',
  '2016041421263443-32.7417-130.8087',
  '2016102114072257-35.3805-133.8562',
  '2016122821384904-36.7202-140.5742',
};

void main(List<String> arguments) {
  final inputPaths = _values(arguments, '--input');
  final auditPath =
      _value(arguments, '--source-process-report') ??
      '.dart_tool/matsuzaki_2006_jma_source_process_audit/report.json';
  final outputDirectory = Directory(
    _value(arguments, '--output-dir') ??
        '.dart_tool/matsuzaki_2006_jma_source_process_distance_diagnostic',
  );
  if (inputPaths.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/matsuzaki_2006_jma_source_process_distance_diagnostic.dart '
      '--input <annual.json> [...] [--source-process-report <report.json>] '
      '[--output-dir <directory>]',
    );
    exitCode = 64;
    return;
  }
  final missing = inputPaths.where((path) => !File(path).existsSync()).toList();
  if (missing.isNotEmpty) {
    throw StateError('Missing input files: ${missing.join(', ')}');
  }
  if (!File(auditPath).existsSync()) {
    throw StateError('Missing source-process audit report: $auditPath');
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
  final baseline = const Matsuzaki2006JmaBaselineEvaluator().evaluate(datasets);
  final eventsById = {
    for (final event in baseline.events) event.eventId: event,
  };
  final sourceReport = jsonDecode(
    File(auditPath).readAsStringSync(encoding: utf8),
  );
  if (sourceReport is! Map<String, Object?> ||
      sourceReport['events'] is! List<Object?>) {
    throw FormatException('Invalid source-process audit report: $auditPath');
  }
  final sourceEventsById = <String, Map<String, Object?>>{
    for (final raw in sourceReport['events']! as List<Object?>)
      if (raw is Map<String, Object?> && raw['eventId'] is String)
        raw['eventId']! as String: raw,
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
  for (final eventId in _targetEventIds.toList()..sort()) {
    final event = eventsById[eventId];
    final source = sourceEventsById[eventId];
    if (event == null) {
      throw StateError('Missing accepted event: $eventId');
    }
    if (source == null) {
      throw StateError('Missing source-process event: $eventId');
    }
    final sourcePlane = _sourcePlane(source);
    final currentGeometry = Matsuzaki2006SourceBackedDistanceOverrides
        .eventGeometries
        .singleWhere((geometry) => geometry.eventId == eventId);
    final currentVariant = currentGeometry.variants.single;
    final pairedStations = <Map<String, double>>[];
    for (final station in event.stationResiduals) {
      final jmaDistance =
          Matsuzaki2006FiniteFaultGeometry.shortestDistanceToFaultUnion(
            faultPlanes: [sourcePlane],
            stationLatitude: station.latitude,
            stationLongitude: station.longitude,
          );
      final currentDistance =
          Matsuzaki2006FiniteFaultGeometry.shortestDistanceToFaultUnion(
            faultPlanes: currentVariant.faultPlanes,
            stationLatitude: station.latitude,
            stationLongitude: station.longitude,
          );
      if (!_inFormulaDomain(jmaDistance) ||
          !_inFormulaDomain(currentDistance)) {
        continue;
      }
      pairedStations.add({
        'jmaDistanceKm': jmaDistance,
        'currentDistanceKm': currentDistance,
        'observedIntensity': station.observedIntensity,
      });
    }
    final modelReports = <String, Object?>{};
    for (final entry in models.entries) {
      final jmaResiduals = <double>[];
      final currentResiduals = <double>[];
      for (final row in pairedStations) {
        final jmaPrediction = entry.value.predictIntensity(
          magnitude: event.magnitude,
          sourceDistanceKm: row['jmaDistanceKm']!,
          depthKm: event.depthKm,
        );
        final currentPrediction = entry.value.predictIntensity(
          magnitude: event.magnitude,
          sourceDistanceKm: row['currentDistanceKm']!,
          depthKm: event.depthKm,
        );
        jmaResiduals.add(row['observedIntensity']! - jmaPrediction);
        currentResiduals.add(row['observedIntensity']! - currentPrediction);
      }
      final report = {
        'pairedStationCount': pairedStations.length,
        'jmaSourceProcessResidualRms': _rms(jmaResiduals),
        'currentGeometryResidualRms': _rms(currentResiduals),
        'rmsChangeJmaMinusCurrent': _rms(jmaResiduals) - _rms(currentResiduals),
        'jmaImprovesRms': _rms(jmaResiduals) < _rms(currentResiduals),
      };
      modelReports[entry.key] = report;
      aggregateRows.add({
        'eventId': eventId,
        'regionName': currentGeometry.regionName,
        'model': entry.key,
        ...report,
      });
    }
    eventReports.add({
      'eventId': eventId,
      'regionName': currentGeometry.regionName,
      'sourceProcessPlane': sourcePlane.toJson(),
      'currentGeometryVariantId': currentVariant.id,
      'pairedStationCount': pairedStations.length,
      'jmaSourceProcessDistanceKm': _summary(
        pairedStations.map((row) => row['jmaDistanceKm']!),
      ),
      'currentGeometryDistanceKm': _summary(
        pairedStations.map((row) => row['currentDistanceKm']!),
      ),
      'modelReports': modelReports,
    });
  }

  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_jma_source_process_distance_diagnostic_v1',
    'purpose':
        'Compare source-process JMA active-subfault geometry with the current source-backed geometry using paired station distances and the same forward models.',
    'inputPolicy': {
      'rawAnnualDatasetsRead': inputPaths,
      'sourceProcessAuditReport': auditPath,
      'observationsModified': false,
      'catalogTruthUsedFor': 'event selection and post-hoc comparison only',
      'productionAlgorithmChanged': false,
      'unknownEventSearchChanged': false,
      'geometrySelectionByThisTool': false,
      'pairedStationRule':
          'Both JMA and current finite-fault distances must be inside the 1-500 km formula domain.',
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

Matsuzaki2006RectangularFaultPlane _sourcePlane(Map<String, Object?> source) {
  final fault = source['faultFile']! as Map<String, Object?>;
  final reference = fault['referencePoint']! as Map<String, Object?>;
  final origin = fault['originGrid']! as Map<String, Object?>;
  final spacing = fault['gridSpacingKm']! as Map<String, Object?>;
  final xRange = fault['activeXRange']! as Map<String, Object?>;
  final wRange = fault['activeWRange']! as Map<String, Object?>;
  final strikeValues = (fault['activeStrikeDegrees']! as List<Object?>)
      .whereType<num>()
      .toList();
  final dipValues = (fault['activeDipDegrees']! as List<Object?>)
      .whereType<num>()
      .toList();
  if (strikeValues.length != 1 || dipValues.length != 1) {
    throw StateError(
      'Source geometry is not a single strike/dip: ${source['eventId']}',
    );
  }
  final rows = (fault['activeSubfaultRows']! as List<Object?>)
      .whereType<Map<String, Object?>>()
      .toList();
  final x = (origin['x']! as num).toInt();
  final w = (origin['w']! as num).toInt();
  final originRow = rows.singleWhere((row) => row['x'] == x && row['w'] == w);
  final downDipRow = rows.singleWhere(
    (row) => row['x'] == x && row['w'] == w + 1,
    orElse: () => throw StateError(
      'No active w+1 subfault to derive source down-dip azimuth: ${source['eventId']}',
    ),
  );
  final rawDownDipAzimuth = _bearingDegrees(
    (originRow['latitude']! as num).toDouble(),
    (originRow['longitude']! as num).toDouble(),
    (downDipRow['latitude']! as num).toDouble(),
    (downDipRow['longitude']! as num).toDouble(),
  );
  final strike = strikeValues.single.toDouble();
  final downDipAzimuth = _nearestOrthogonalDirection(
    strike: strike,
    observedDirection: rawDownDipAzimuth,
  );
  final length =
      ((xRange['maximum']! as num).toInt() -
          (xRange['minimum']! as num).toInt() +
          1) *
      (spacing['alongStrikeKm']! as num).toDouble();
  final width =
      ((wRange['maximum']! as num).toInt() -
          (wRange['minimum']! as num).toInt() +
          1) *
      (spacing['downDipKm']! as num).toDouble();
  final referenceAlong =
      (x - (xRange['minimum']! as num).toInt() + 0.5) *
      (spacing['alongStrikeKm']! as num).toDouble();
  final referenceDownDip =
      (w - (wRange['minimum']! as num).toInt() + 0.5) *
      (spacing['downDipKm']! as num).toDouble();
  return Matsuzaki2006RectangularFaultPlane.fromPointOnPlane(
    id: 'jma-source-process-${source['eventId']}',
    referencePointRole: 'jma_source_process_rupture_start_subfault_center',
    referenceLatitude: (reference['latitude']! as num).toDouble(),
    referenceLongitude: (reference['longitude']! as num).toDouble(),
    referenceDepthKm: (reference['depthKm']! as num).toDouble(),
    referenceAlongLengthKm: referenceAlong,
    referenceDownDipKm: referenceDownDip,
    lengthKm: length,
    widthKm: width,
    upperEdgeAzimuthDegrees: strike,
    downDipAzimuthDegrees: downDipAzimuth,
    dipDegrees: dipValues.single.toDouble(),
  );
}

double _nearestOrthogonalDirection({
  required double strike,
  required double observedDirection,
}) {
  final plus = (strike + 90) % 360;
  final minus = (strike + 270) % 360;
  return _circularAngleDifference(observedDirection, plus) <=
          _circularAngleDifference(observedDirection, minus)
      ? plus
      : minus;
}

double _circularAngleDifference(double left, double right) {
  final raw = (left - right).abs() % 360;
  return raw > 180 ? 360 - raw : raw;
}

double _bearingDegrees(
  double latitude1,
  double longitude1,
  double latitude2,
  double longitude2,
) {
  final lat1 = latitude1 * math.pi / 180;
  final lat2 = latitude2 * math.pi / 180;
  final deltaLongitude = (longitude2 - longitude1) * math.pi / 180;
  final bearing = math.atan2(
    math.sin(deltaLongitude) * math.cos(lat2),
    math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(deltaLongitude),
  );
  return (bearing * 180 / math.pi + 360) % 360;
}

bool _inFormulaDomain(double distanceKm) =>
    distanceKm >= Matsuzaki2006AttenuationModel.minimumSourceDistanceKm &&
    distanceKm <= Matsuzaki2006AttenuationModel.maximumSourceDistanceKm;

Map<String, Object> _summary(Iterable<double> values) {
  final list = values.toList()..sort();
  if (list.isEmpty) return const {'count': 0};
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
    list.fold<double>(0, (sum, value) => sum + value * value) / list.length,
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
    ..writeln('# JMA 源过程矩形与当前几何逐站距离诊断')
    ..writeln()
    ..writeln(
      '本报告从 JMA `02fault.txt` 有效子断层中心坐标推导下倾方位，构造仅用于诊断的 JMA 活跃矩形，并与当前实验几何在相同观测站、相同前向公式下比较。它不选择几何、不改变未知事件搜索。',
    )
    ..writeln()
    ..writeln(
      '| 事件 | 模型 | 配对站数 | JMA 源过程 RMS | 当前几何 RMS | JMA - 当前 | JMA 是否更低 |',
    )
    ..writeln('|---|---|---:|---:|---:|---:|---|');
  for (final row in rows) {
    buffer.writeln(
      '| `${row['eventId']}` | `${row['model']}` | ${row['pairedStationCount']} | '
      '${_fixed(row['jmaSourceProcessResidualRms'])} | '
      '${_fixed(row['currentGeometryResidualRms'])} | '
      '${_fixed(row['rmsChangeJmaMinusCurrent'])} | ${row['jmaImprovesRms']} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## 解释边界')
    ..writeln()
    ..writeln('- JMA 矩形的下倾方位由原始子断层中心坐标的 `w -> w+1` 方位计算，不使用固定 `strike+90°` 假设。')
    ..writeln(
      '- `JMA - 当前 < 0` 只表示在已知事件、已知来源模型和当前前向式下 JMA 矩形的逐站 RMS 更低；它不是未知事件定位精度证明。',
    )
    ..writeln('- 熊本、鸟取的 JMA 与当前几何来自不同来源，只能并列诊断；不能将 JMA 尺寸、NIED 起点或另一来源的下倾方向拼接。')
    ..writeln('- 配对站只保留两种距离都在松崎式 `1-500 km` 域内的站，原始观测和原始 ZIP 不修改。')
    ..writeln()
    ..writeln('事件数：${events.length}；模型行数：${rows.length}。');
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
