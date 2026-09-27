import 'dart:convert';
import 'dart:io';

const _defaultSourceReportPath =
    '.dart_tool/matsuzaki_2006_jma_source_process_audit/report.json';
const _defaultDistanceReportPath =
    '.dart_tool/matsuzaki_2006_jma_source_process_distance_diagnostic/report.json';
const _defaultTemporalReportPath =
    '.dart_tool/matsuzaki_2006_jma_source_process_temporal_audit/report.json';
const _defaultInversionReportPath =
    '.dart_tool/matsuzaki_2006_source_backed_point_source_inversion/report.json';
const _defaultOutputDirectory =
    '.dart_tool/matsuzaki_2006_jma_source_process_family_correlation_diagnostic';

void main(List<String> arguments) {
  final sourceReportPath =
      _value(arguments, '--source-process-report') ?? _defaultSourceReportPath;
  final distanceReportPath =
      _value(arguments, '--distance-report') ?? _defaultDistanceReportPath;
  final temporalReportPath =
      _value(arguments, '--temporal-report') ?? _defaultTemporalReportPath;
  final inversionReportPath =
      _value(arguments, '--inversion-report') ?? _defaultInversionReportPath;
  final outputDirectory = Directory(
    _value(arguments, '--output-dir') ?? _defaultOutputDirectory,
  );

  final sourceReport = _readJsonMap(sourceReportPath);
  final distanceReport = _readJsonMap(distanceReportPath);
  final temporalReport = _readJsonMap(temporalReportPath);
  final inversionReport = _readJsonMap(inversionReportPath);

  final sourceById = {
    for (final event in _asObjectList(sourceReport['events']))
      (event['eventId']?.toString() ?? ''): event,
  }..removeWhere((key, _) => key.isEmpty);
  final distanceById = {
    for (final event in _asObjectList(distanceReport['events']))
      (event['eventId']?.toString() ?? ''): event,
  }..removeWhere((key, _) => key.isEmpty);
  final temporalById = {
    for (final event in _asObjectList(temporalReport['events']))
      (event['eventId']?.toString() ?? ''): event,
  }..removeWhere((key, _) => key.isEmpty);
  final inversionById = {
    for (final event in _asObjectList(inversionReport['events']))
      (event['eventId']?.toString() ?? ''): event,
  }..removeWhere((key, _) => key.isEmpty);

  final eventIds = sourceById.keys.toList()..sort();
  final events = <Map<String, Object?>>[];
  final byType = <String, Map<String, dynamic>>{};
  final byRelation = <String, Map<String, dynamic>>{};

  for (final eventId in eventIds) {
    final source = sourceById[eventId]!;
    final distance = distanceById[eventId];
    final temporal = temporalById[eventId];
    if (distance == null || temporal == null) {
      // Only join source + distance + temporal; inversion is optional.
      continue;
    }
    final inversion = inversionById[eventId];

    final eventFile = source['eventFile'];
    final relation =
        source['relationshipToCurrentGeometry']?.toString() ??
        'relationship_unknown';
    final eventType = eventFile is Map<String, Object?>
        ? eventFile['type']?.toString()
        : null;
    final faultWindow = temporal['faultWindow'] as Map<String, Object?>?;
    final coverage = temporal['momentWindowCoverage'] as Map<String, Object?>?;

    final expectedCoverage = _toNum(faultWindow?['expectedCoverageSeconds']);
    final observedCoverage = _toNum(coverage?['observedCoverageSeconds']);
    final coverageRatio = (expectedCoverage == null ||
            observedCoverage == null ||
            expectedCoverage == 0)
        ? null
        : observedCoverage / expectedCoverage;
    final coverageDelta = (observedCoverage != null && expectedCoverage != null)
        ? observedCoverage - expectedCoverage
        : null;

    final publishedDistance = _readDistanceModel(
      distance,
      'published',
    );
    final frozenDistance = _readDistanceModel(
      distance,
      'finiteFaultSemanticFrozen2017',
    );
    final publishedInversion = _readInversionModel(
      inversion,
      'published',
    );
    final frozenInversion = _readInversionModel(
      inversion,
      'finiteFaultSemanticFrozen2017',
    );

    final eventRow = {
      'eventId': eventId,
      'regionName': source['regionName'],
      'type': eventType,
      'relationship': relation,
      'distance': {
        'pairedStationCount': distance['pairedStationCount'],
        'published': publishedDistance,
        'finiteFaultSemanticFrozen2017': frozenDistance,
      },
      'temporal': {
        'momentWindowCount': _toNum(faultWindow?['momentWindowCount']),
        'momentWindowDurationSeconds':
            _toNum(faultWindow?['momentWindowDurationSeconds']),
        'momentWindowShiftSeconds':
            _toNum(faultWindow?['momentWindowShiftSeconds']),
        'expectedCoverageSeconds': expectedCoverage,
        'observedCoverageSeconds': observedCoverage,
        'coverageToExpectedRatio': coverageRatio,
        'coverageDeltaSeconds': coverageDelta,
        'startOffsetFromShiftSeconds': _toNum(
          coverage?['startOffsetFromShiftSeconds'],
        ),
      },
      'inversion': {
        'published': publishedInversion,
        'finiteFaultSemanticFrozen2017': frozenInversion,
      },
    };
    events.add(eventRow);

    _appendEventAggregate(byType, eventType ?? 'type_unknown', eventRow);
    _appendEventAggregate(byRelation, relation, eventRow);
  }

  final aggregateByType = byType.values.map(_finalizeAggregate).toList()
    ..sort((a, b) => a['key'].toString().compareTo(b['key'].toString()));
  final aggregateByRelation = byRelation.values.map(_finalizeAggregate).toList()
    ..sort((a, b) => a['key'].toString().compareTo(b['key'].toString()));

  final report = <String, Object?>{
    'schemaVersion':
        'matsuzaki_2006_jma_source_process_family_correlation_v1',
    'purpose':
        'Cross-link temporal and distance diagnostics for family/relationship review only.',
    'inputPolicy': {
      'sourceProcessReport': sourceReportPath,
      'distanceReport': distanceReportPath,
      'temporalReport': temporalReportPath,
      'inversionReport': inversionReportPath,
      'productionAlgorithmChanged': false,
    },
    'events': events,
    'aggregateByType': aggregateByType,
    'aggregateByRelationship': aggregateByRelation,
    'counts': {
      'sourceEvents': sourceById.length,
      'distanceMatchedEvents': distanceById.length,
      'temporalMatchedEvents': temporalById.length,
      'inversionMatchedEvents': inversionById.length,
      'joinedEvents': events.length,
    },
  };

  outputDirectory.createSync(recursive: true);
  File('${outputDirectory.path}/report.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    encoding: utf8,
  );
  File(
    '${outputDirectory.path}/report.md',
  ).writeAsStringSync(_markdown(events, aggregateByType, aggregateByRelation),
      encoding: utf8);
  stdout.writeln('wrote ${outputDirectory.path}/report.json');
  stdout.writeln('wrote ${outputDirectory.path}/report.md');
}

Map<String, Object?> _readDistanceModel(
  Map<String, Object?> distance,
  String modelName,
) {
  final modelReports = distance['modelReports'];
  final model = modelReports is Map
      ? modelReports[modelName]
      : null;
  if (model is! Map<String, Object?>) return const {};
  return {
    'pairedStationCount': model['pairedStationCount'],
    'jmaSourceProcessResidualRms':
        _toNum(model['jmaSourceProcessResidualRms']),
    'currentGeometryResidualRms':
        _toNum(model['currentGeometryResidualRms']),
    'rmsChangeJmaMinusCurrent':
        _toNum(model['rmsChangeJmaMinusCurrent']),
    'jmaImprovesRms': model['jmaImprovesRms'],
  };
}

Map<String, Object?> _readInversionModel(
  Map<String, Object?>? inversion,
  String modelName,
) {
  if (inversion == null) return const {};
  final models = inversion['models'];
  final model = models is Map ? models[modelName] : null;
  if (model is! Map<String, Object?>) return const {};
  final contacts = model['hardBoundaryContacts'];
  final contactList = contacts is List
      ? contacts.whereType<String>().toList(growable: false)
      : const <String>[];
  return {
    'status': model['status'],
    'isConverged': model['isConverged'],
    'hardBoundaryReached': model['status']?.toString() == 'hardBoundaryReached' ||
        contactList.contains('depthMinimum'),
    'hardBoundaryContacts': contactList,
    'minimumIntensityRms': _toNum(model['minimumIntensityRms']),
    'candidateEvaluationCount': model['candidateEvaluationCount'],
    'elapsedMilliseconds': model['elapsedMilliseconds'],
    'depthAbsoluteErrorKmMinimumEquivalent':
        _toNum(model['depthAbsoluteErrorKmMinimumEquivalent']),
    'epicentralErrorKmMinimumEquivalent':
        _toNum(model['epicentralErrorKmMinimumEquivalent']),
    'magnitudeAbsoluteErrorMinimumEquivalent':
        _toNum(model['magnitudeAbsoluteErrorMinimumEquivalent']),
  };
}

void _appendEventAggregate(
  Map<String, Map<String, dynamic>> groups,
  String key,
  Map<String, Object?> eventRow,
) {
  final group = groups.putIfAbsent(key, () => _newAggregateBucket(key));
  group['eventCount'] = (group['eventCount'] as int) + 1;

  final distance = eventRow['distance'] as Map<String, Object?>;
  final temporal = eventRow['temporal'] as Map<String, Object?>;
  final inversion = eventRow['inversion'] as Map<String, Object?>;

  final publishedDistance =
      distance['published'] as Map<String, Object?>? ?? const {};
  final frozenDistance =
      distance['finiteFaultSemanticFrozen2017'] as Map<String, Object?>? ??
          const {};
  _appendDouble(group['publishedRmsChange'] as List<double>,
      _toNum(publishedDistance['rmsChangeJmaMinusCurrent']));
  _appendDouble(group['frozenRmsChange'] as List<double>,
      _toNum(frozenDistance['rmsChangeJmaMinusCurrent']));
  _appendDouble(group['coverageRatio'] as List<double>,
      _toNum(temporal['coverageToExpectedRatio']));
  _appendDouble(group['coverageDeltaSeconds'] as List<double>,
      _toNum(temporal['coverageDeltaSeconds']));

  final publishedInv =
      inversion['published'] as Map<String, Object?>? ?? const {};
  final frozenInv =
      inversion['finiteFaultSemanticFrozen2017'] as Map<String, Object?>? ??
          const {};
  group['publishedBoundaryCount'] =
      (group['publishedBoundaryCount'] as int) +
      ((publishedInv['hardBoundaryReached'] == true) ? 1 : 0);
  group['frozenBoundaryCount'] =
      (group['frozenBoundaryCount'] as int) +
          ((frozenInv['hardBoundaryReached'] == true) ? 1 : 0);
  _appendDouble(group['publishedInversionRms'] as List<double>,
      _toNum(publishedInv['minimumIntensityRms']));
  _appendDouble(group['frozenInversionRms'] as List<double>,
      _toNum(frozenInv['minimumIntensityRms']));
}

Map<String, dynamic> _newAggregateBucket(String key) {
  return {
    'key': key,
    'eventCount': 0,
    'publishedRmsChange': <double>[],
    'frozenRmsChange': <double>[],
    'coverageRatio': <double>[],
    'coverageDeltaSeconds': <double>[],
    'publishedBoundaryCount': 0,
    'frozenBoundaryCount': 0,
    'publishedInversionRms': <double>[],
    'frozenInversionRms': <double>[],
    'inversionEventCount': 0,
  };
}

Map<String, Object?> _finalizeAggregate(Map<String, dynamic> bucket) {
  final eventCount = bucket['eventCount'] as int;
  final publishedBoundaryCount = bucket['publishedBoundaryCount'] as int;
  final frozenBoundaryCount = bucket['frozenBoundaryCount'] as int;
  return {
    'key': bucket['key'],
    'eventCount': eventCount,
    'publishedRmsChange': _summaryNumbers(
      bucket['publishedRmsChange'] as List<double>,
    ),
    'frozenRmsChange': _summaryNumbers(
      bucket['frozenRmsChange'] as List<double>,
    ),
    'coverageRatio': _summaryNumbers(
      bucket['coverageRatio'] as List<double>,
    ),
    'coverageDeltaSeconds': _summaryNumbers(
      bucket['coverageDeltaSeconds'] as List<double>,
    ),
    'publishedBoundaryRate':
        eventCount == 0 ? null : publishedBoundaryCount / eventCount,
    'frozenBoundaryRate':
        eventCount == 0 ? null : frozenBoundaryCount / eventCount,
    'publishedInversionRms': _summaryNumbers(
      bucket['publishedInversionRms'] as List<double>,
    ),
    'frozenInversionRms': _summaryNumbers(
      bucket['frozenInversionRms'] as List<double>,
    ),
  };
}

Map<String, Object> _summaryNumbers(List<double> values) {
  if (values.isEmpty) return const {'count': 0};
  final sorted = [...values]..sort();
  return {
    'count': sorted.length,
    'min': sorted.first,
    'max': sorted.last,
    'mean': sorted.reduce((a, b) => a + b) / sorted.length,
    'median': sorted[sorted.length ~/ 2],
  };
}

void _appendDouble(List<double> target, num? value) {
  if (value != null) target.add(value.toDouble());
}

Map<String, Object?> _readJsonMap(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('Missing required file: $path');
  }
  final decoded = jsonDecode(file.readAsStringSync(encoding: utf8));
  if (decoded is! Map<String, Object?>) {
    throw FormatException('Invalid report json: $path');
  }
  return decoded;
}

List<Map<String, Object?>> _asObjectList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Map<String, Object?>>().toList(growable: false);
}

num? _toNum(Object? value) => value is num ? value : null;

String? _value(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index < 0 || index + 1 >= arguments.length) return null;
  return arguments[index + 1];
}

String _markdown(
  List<Map<String, Object?>> events,
  List<Map<String, Object?>> typeAggregate,
  List<Map<String, Object?>> relationAggregate,
) {
  final buffer = StringBuffer()
    ..writeln('# 源过程族群联动审计（仅审计）')
    ..writeln()
    ..writeln(
      '把 `source_process` 的几何族群信息、时间窗核对、几何距离核对与同源点源反演结果按 `eventId` 对齐，'
      ' 输出“边界一致性 + 距离改变量 + 覆盖口径”三线并行证据，用于 `Type` 和几何关系分桶判断。',
    )
    ..writeln()
    ..writeln(
      '| 事件 | Type | 关系 | 覆盖比 | published ΔRMS | frozen ΔRMS | Ntmw×Dtmw | 观测/预期(s) | published状态 | frozen状态 |',
    )
    ..writeln(
      '|---|---|---|---:|---:|---:|---:|---:|---|---|',
    );
  for (final event in events) {
    final distance = event['distance'] as Map<String, Object?>;
    final temporal = event['temporal'] as Map<String, Object?>;
    final inversion = event['inversion'] as Map<String, Object?>;
    final publishedDistance =
        distance['published'] as Map<String, Object?>? ?? const {};
    final frozenDistance =
        distance['finiteFaultSemanticFrozen2017'] as Map<String, Object?>? ??
            const {};
    final nt = temporal['momentWindowCount'];
    final dt = temporal['momentWindowDurationSeconds'];
    final expected = _toNum(temporal['expectedCoverageSeconds']);
    final observed = _toNum(temporal['observedCoverageSeconds']);
    buffer.writeln(
      '| `${event['eventId']}` | ${event['type']} | ${event['relationship']} | '
      '${_formatPercent(_toNum(temporal['coverageToExpectedRatio']))} | '
      '${_formatDouble(_toNum(publishedDistance['rmsChangeJmaMinusCurrent']))} | '
      '${_formatDouble(_toNum(frozenDistance['rmsChangeJmaMinusCurrent']))} | '
      '${_formatDouble(nt)}×${_formatDouble(dt)} | '
      '${_formatDouble(observed)}/${_formatDouble(expected)} | '
      '${_formatInversion(inversion['published'] as Map<String, Object?>?)} | '
      '${_formatInversion(inversion['finiteFaultSemanticFrozen2017'] as Map<String, Object?>?)} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## 按 Type 聚合')
    ..writeln()
    ..writeln(
      '| Type | 事件数 | published ΔRMS 中位 | frozen ΔRMS 中位 | coverage比 中位 | coverage差 中位(s) | published边界率 | frozen边界率 |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|---:|');
    for (final summary in typeAggregate) {
    buffer.writeln(
      '| ${summary['key']} | ${summary['eventCount']} | '
      '${_formatDouble(_median(summary['publishedRmsChange']))} | '
      '${_formatDouble(_median(summary['frozenRmsChange']))} | '
      '${_formatDouble(_median(summary['coverageRatio']), missing: '--')} | '
      '${_formatDouble(_median(summary['coverageDeltaSeconds']))} | '
      '${_formatPercent(_toNum(summary['publishedBoundaryRate']))} | '
      '${_formatPercent(_toNum(summary['frozenBoundaryRate']))} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## 按几何关系聚合')
    ..writeln()
    ..writeln(
      '| 几何关系 | 事件数 | published ΔRMS 中位 | frozen ΔRMS 中位 | coverage比 中位 | coverage差 中位(s) |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|');
  for (final summary in relationAggregate) {
    buffer.writeln(
      '| ${summary['key']} | ${summary['eventCount']} | '
      '${_formatDouble(_median(summary['publishedRmsChange']))} | '
      '${_formatDouble(_median(summary['frozenRmsChange']))} | '
      '${_formatDouble(_median(summary['coverageRatio']), missing: '--')} | '
      '${_formatDouble(_median(summary['coverageDeltaSeconds']))} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## 说明')
    ..writeln('- `published/frozen ΔRMS` 为 `JMA矩形RMS - 当前几何RMS`，负值是 JMA 矩形更优。')
    ..writeln(
      '- `coverage 比` 为 `observed/expected`，大于 1 表示 `03mom` 盖测语义超出 `Ntmw*Dtmw`。',
    )
    ..writeln(
      '- 边界率是事件内硬边界事件比例（按同分桶事件数）。反演为空表示该事件未出现在反演日志（如大阪）。',
    )
    ..writeln('- 仅审计用途，边界和发现不用于直接改算法。');
  return buffer.toString();
}

String _formatDouble(Object? value, {String missing = ''}) {
  if (value == null) return missing;
  if (value is num) return value.toStringAsFixed(3);
  return value.toString();
}

String _formatPercent(num? ratio, {bool forcePercent = true}) {
  if (ratio == null) return '';
  if (forcePercent) return '${(ratio * 100).toStringAsFixed(1)}%';
  return ratio.toStringAsFixed(3);
}

String _formatInversion(Map<String, Object?>? inversion) {
  if (inversion == null || inversion.isEmpty) return '';
  final status = inversion['status']?.toString() ?? '';
  final rms = _formatDouble(inversion['minimumIntensityRms']);
  final boundary = inversion['hardBoundaryReached'] == true ? 'B' : 'NoB';
  return '$status / $rms / $boundary';
}

num? _median(Object? summary) {
  if (summary is! Map || summary['median'] == null) return null;
  final value = summary['median'];
  return value is num ? value : null;
}
