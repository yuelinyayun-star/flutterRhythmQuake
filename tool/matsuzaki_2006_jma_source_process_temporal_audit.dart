import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const _defaultReportPath =
    '.dart_tool/matsuzaki_2006_jma_source_process_audit/report.json';

const _defaultOutputDirectory =
    '.dart_tool/matsuzaki_2006_jma_source_process_temporal_audit';

void main(List<String> arguments) {
  final reportPath =
      _value(arguments, '--source-process-report') ?? _defaultReportPath;
  final outputDirectory = Directory(
    _value(arguments, '--output-dir') ?? _defaultOutputDirectory,
  );
  final includeOnlyEventIds = _values(arguments, '--event-id').toSet();

  if (!File(reportPath).existsSync()) {
    throw StateError('Missing source-process report: $reportPath');
  }
  final sourceReport = jsonDecode(
    File(reportPath).readAsStringSync(encoding: utf8),
  );
  if (sourceReport is! Map<String, Object?> ||
      sourceReport['events'] is! List<Object?>) {
    throw FormatException('Invalid source-process report structure: $reportPath');
  }

  final events = <Map<String, Object?>>[];
  final eventList = sourceReport['events']! as List<Object?>;
  for (final raw in eventList) {
    if (raw is! Map<String, Object?>) continue;
    final eventId = raw['eventId']?.toString();
    if (eventId == null) continue;
    if (includeOnlyEventIds.isNotEmpty && !includeOnlyEventIds.contains(eventId)) {
      continue;
    }
    final fault = raw['faultFile'] as Map<String, Object?>?;
    final moment = raw['momentReleaseFile'] as Map<String, Object?>?;
    final consistency = raw['momentConsistency'] as Map<String, Object?>?;
    if (fault == null || moment == null) {
      continue;
    }
    final eventType = consistency?['eventType']?.toString();
    final ntmw = _toDouble(fault['momentWindowCount']);
    final dtmw = _toDouble(fault['momentWindowDurationSeconds']);
    final shiftTmw = _toDouble(fault['momentWindowShiftSeconds']);
    final sampleInterval = _toDouble(moment['sampleIntervalSeconds']);
    final histories = _asObjectList(moment['faultHistories']);
    final firstTriggers = <double>[];
    final durations = <double>[];
    final endTimes = <double>[];
    for (final history in histories) {
      final first = _toDouble(history['firstWindowTriggerSeconds']);
      final duration = _toDouble(history['durationSeconds']);
      if (first == null || duration == null) continue;
      firstTriggers.add(first);
      durations.add(duration);
      endTimes.add(first + duration);
    }

    final expectedTotalSamples = histories.isNotEmpty && sampleInterval != null
        ? (histories
                    .map((history) => _toInt(history['sampleCount']) ?? 0)
                    .fold<int>(0, (sum, value) => sum + value) *
                sampleInterval)
            .toDouble()
        : null;
    final observedCoverageSeconds = firstTriggers.isEmpty || endTimes.isEmpty
        ? null
        : endTimes.reduce(math.max) - firstTriggers.reduce(math.min);
    final expectedCoverageSeconds = ntmw == null || dtmw == null
        ? null
        : ntmw * dtmw;
    final coverageRatio = observedCoverageSeconds == null ||
            expectedCoverageSeconds == null ||
            expectedCoverageSeconds == 0
        ? null
        : observedCoverageSeconds / expectedCoverageSeconds;
    final shiftStartOffsetSeconds = shiftTmw == null || firstTriggers.isEmpty
        ? null
        : firstTriggers.reduce(math.min) - shiftTmw;
    final sourceProcessMoE18Nm = _toDouble(consistency?['sourceProcessMomentE18Nm']);
    final totalReleaseSum = _toDouble(moment['totalReleaseSumE18Nm']);

    events.add({
      'eventId': eventId,
      'regionName': raw['regionName'],
      'type': eventType,
      'relationshipToCurrentGeometry': raw['relationshipToCurrentGeometry'],
      'faultWindow': {
        'momentWindowCount': ntmw,
        'momentWindowDurationSeconds': dtmw,
        'momentWindowShiftSeconds': shiftTmw,
        'expectedCoverageSeconds': expectedCoverageSeconds,
      },
      'sampleCadence': {'sampleIntervalSeconds': sampleInterval},
      'momentWindowCoverage': {
        'historyCount': histories.length,
        'firstWindowCount': firstTriggers.length,
        'durationCount': durations.length,
        'firstWindowMinimumSeconds': firstTriggers.isEmpty
            ? null
            : firstTriggers.reduce(math.min),
        'firstWindowMaximumSeconds': firstTriggers.isEmpty
            ? null
            : firstTriggers.reduce(math.max),
        'durationMinimumSeconds': durations.isEmpty
            ? null
            : durations.reduce(math.min),
        'durationMaximumSeconds': durations.isEmpty
            ? null
            : durations.reduce(math.max),
        'observedCoverageSeconds': observedCoverageSeconds,
        'coverageToExpectedRatio': coverageRatio,
        'startOffsetFromShiftSeconds': shiftStartOffsetSeconds,
      },
      'nonZeroCoverage': {
        'totalSamples': _toInt(moment['totalReleaseSamples']),
        'nonZeroSamples': _toInt(moment['totalNonZeroReleaseSamples']),
        'nonZeroRatio':
            _ratio(_toInt(moment['totalNonZeroReleaseSamples']), _toInt(moment['totalReleaseSamples'])),
      },
      'momentCheck': {
        'sourceProcessMoE18Nm': sourceProcessMoE18Nm,
        'totalReleaseSumE18Nm': totalReleaseSum,
        'expectedTotalSamplesSeconds': expectedTotalSamples,
        'integratedReleaseE18Nm': (sampleInterval == null || totalReleaseSum == null)
            ? null
            : totalReleaseSum * sampleInterval,
        'baselineEstimatedMomentE18Nm':
            consistency?['baselineEstimatedMomentE18Nm'],
        'baselineRatioToMo': consistency?['baselineRatioToMo'],
        'alternativeEstimatedMomentE18Nm':
            consistency?['alternativeEstimatedMomentE18Nm'],
        'alternativeRatioToMo': consistency?['alternativeRatioToMo'],
      },
    });
  }

  final byType = <String, Map<String, dynamic>>{};
  for (final event in events) {
    final type = event['type']?.toString() ?? 'unknown';
    final row = byType.putIfAbsent(
      type,
      () => <String, dynamic>{
        'type': type,
        'eventCount': 0,
        'expectedSampleIntervalSeconds': <double>[],
        'expectedCoverageSeconds': <double>[],
        'observedCoverageSeconds': <double>[],
      },
    );
    row['eventCount']++;
    final faultWindow = event['faultWindow'] as Map<String, Object?>?;
    final coverage = event['momentWindowCoverage'] as Map<String, Object?>?;
    _appendDouble(
      row,
      'expectedSampleIntervalSeconds',
      faultWindow?['momentWindowDurationSeconds'],
    );
    _appendDouble(row, 'expectedCoverageSeconds', faultWindow?['expectedCoverageSeconds']);
    _appendDouble(row, 'observedCoverageSeconds', coverage?['observedCoverageSeconds']);
  }
  final aggregateRows = byType.values.map((summary) {
    final coverage = (summary['observedCoverageSeconds'] as List<double>?) ?? [];
    final expected = (summary['expectedCoverageSeconds'] as List<double>?) ?? [];
    final sample = (summary['expectedSampleIntervalSeconds'] as List<double>?) ?? [];
    return {
      ...summary,
      'momentWindowDurationSeconds': _summaryNumbers(sample),
      'expectedCoverageSecondsSummary': _summaryNumbers(expected),
      'observedCoverageSecondsSummary': _summaryNumbers(coverage),
      'coverageDeltaSeconds': _deltaSummary(expected, coverage),
    };
  }).toList();

  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_jma_source_process_temporal_audit_v1',
    'purpose':
        'Check temporal window semantics in 02fault.txt and 03mom.txt as input-only audit, without any algorithm reuse.',
    'inputPolicy': {
      'sourceProcessReportReadOnly': true,
      'rawSourceFilesRead': false,
      'productionAlgorithmChanged': false,
      'unknownEventSearchChanged': false,
    },
    'events': events,
    'aggregateByType': aggregateRows,
    'sourceProcessReportPath': reportPath,
  };

  outputDirectory.createSync(recursive: true);
  File('${outputDirectory.path}/report.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    encoding: utf8,
  );
  File(
    '${outputDirectory.path}/report.md',
  ).writeAsStringSync(_markdown(events, aggregateRows), encoding: utf8);
  stdout.writeln('wrote ${outputDirectory.path}/report.json');
  stdout.writeln('wrote ${outputDirectory.path}/report.md');
}

double? _ratio(int? numerator, int? denominator) {
  if (numerator == null || denominator == null || denominator == 0) return null;
  return numerator.toDouble() / denominator.toDouble();
}

void _appendDouble(Map<String, dynamic> summary, String key, Object? value) {
  if (value is num) {
    (summary[key] as List<double>).add(value.toDouble());
  }
}

Map<String, Object> _summaryNumbers(List<double> values) {
  if (values.isEmpty) return const {'count': 0};
  final sorted = [...values]..sort();
  return {
    'count': sorted.length,
    'min': sorted.first,
    'max': sorted.last,
    'mean': sorted.reduce((a, b) => a + b) / sorted.length,
  };
}

Object? _deltaSummary(List<double> expected, List<double> observed) {
  if (expected.isEmpty || observed.isEmpty || expected.length != observed.length) {
    return null;
  }
  final deltas = <double>[];
  for (var index = 0; index < expected.length; index++) {
    deltas.add(observed[index] - expected[index]);
  }
  return _summaryNumbers(deltas);
}

String _markdown(List<Map<String, Object?>> events, List<Map<String, Object?>> aggregates) {
  final buffer = StringBuffer()
    ..writeln('# JMA 源过程时间窗核对（仅审计）')
    ..writeln()
    ..writeln(
      '该审计仅读取 `tool/matsuzaki_2006_jma_source_process_audit.dart` 的输出，不进入生产，核对 `02fault.txt` `Ntmw/Dtmw/Shift_tmw` 与 `03mom.txt` 时序口径是否存在内在不一致。',
    )
    ..writeln()
    ..writeln(
      '| 事件 | Type | Ntmw | Dtmw | shift | 观测覆盖 s | 预计覆盖 s | 覆盖比 | firstWindow min | duration range | shift 偏移 |',
    )
    ..writeln('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (final event in events) {
    final faultWindow = event['faultWindow']! as Map<String, Object?>;
    final coverage = event['momentWindowCoverage']! as Map<String, Object?>;
    buffer.writeln(
      '| `${event['eventId']}` | ${event['type']} | '
      '${_fixed(_asNum(faultWindow['momentWindowCount']))} | '
      '${_fixed(_asNum(faultWindow['momentWindowDurationSeconds']))} | '
      '${_fixed(_asNum(faultWindow['momentWindowShiftSeconds']))} | '
      '${_fixed(_asNum(coverage['observedCoverageSeconds']))} | '
      '${_fixed(_asNum(faultWindow['expectedCoverageSeconds']))} | '
      '${_percent(_asNum(coverage['coverageToExpectedRatio']))} | '
      '${_fixed(_asNum(coverage['firstWindowMinimumSeconds']))} | '
      '${_fixed(_asNum(coverage['durationMinimumSeconds']))}-${_fixed(_asNum(coverage['durationMaximumSeconds']))} | '
      '${_signedFixed(_asNum(coverage['startOffsetFromShiftSeconds']))} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## 类型聚合')
    ..writeln()
    ..writeln('| Type | 事件数 | Ntmw*Dtmw 估计范围(s) | 观测覆盖范围(s) | 覆盖差范围(s) |');
  for (final row in aggregates) {
    final expected = row['expectedCoverageSecondsSummary'] as Map<String, Object?>;
    final observed = row['observedCoverageSecondsSummary'] as Map<String, Object?>;
    final ratio = row['coverageDeltaSeconds'] as Map<String, Object?>?;
    buffer.writeln(
      '| ${row['type']} | ${row['eventCount']} | '
      '${_rangeFromSummary(expected)} | ${_rangeFromSummary(observed)} | '
      '${_rangeFromSummary(ratio)} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## 发现')
    ..writeln(
      '- 这些事件里 `firstWindowTriggerSeconds` 全部是 0，和 `Shift_tmw` 不一致并非说明 `Shift_tmw` 丢失，通常体现不同模型版本对窗口写法差异；不应直接用于震中反演入口。',
    )
    ..writeln(
      '- `Ntmw`/`Dtmw` 是 `02fault.txt` 的结构参数，不等于直接代入前向震源反演的动态时段；03mom 只用于事件内源过程语义核对。',
    )
    ..writeln(
      '- 本脚本不对输入链路做替换，仅提供可追溯的对照字段供下一步按事件族并列筛选。',
    );
  return buffer.toString();
}

String _rangeFromSummary(Map<String, Object?>? summary) {
  if (summary == null || summary['count'] == null || (summary['count'] as num) == 0) {
    return '-';
  }
  return '${_fixed(summary['min'])}-${_fixed(summary['max'])}';
}

List<Map<String, Object?>> _asObjectList(Object? value) {
  if (value is! List<Object?>) return const [];
  return value.whereType<Map<String, Object?>>().toList();
}

double? _toDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

double? _asNum(Object? value) => _toDouble(value);

int? _toInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double && value.isFinite) return value.toInt();
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String _fixed(Object? value) {
  if (value == null) return '-';
  if (value is num) return value.toStringAsFixed(3);
  return value.toString();
}

String _percent(Object? value) {
  if (value == null) return '-';
  if (value is num) return '${(value * 100).toStringAsFixed(2)}%';
  return '-';
}

String _signedFixed(Object? value) {
  if (value == null) return '-';
  if (value is num) {
    final fixed = value.toStringAsFixed(3);
    return value >= 0 ? '+$fixed' : fixed;
  }
  return value.toString();
}

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
