import 'dart:convert';
import 'dart:io';

import 'build_plum_tohoku_mismatch_gap_transition_diagnostic_report.dart'
    as gap_transition;

const _defaultDataDirectory = 'tmp/jma_intensity_pretraining';
const _defaultModelPath =
    'tmp/jma_intensity_pretraining/static_attenuation_model.json';
const _defaultOutputPath =
    '.dart_tool/plum_tohoku_middle_gap_transition_zone_diagnostic/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_tohoku_middle_gap_transition_zone_diagnostic.generated.md';

const _thresholdLabels = ['shindo4', 'shindo5-'];
const _zoneDefinitions = <String, Map<String, List<String>>>{
  'middle_transition_zone': {
    'actualGapBands': ['-1.0_to_0.0', '0.0_to_1.0'],
    'evidenceGapBands': ['1.0_to_2.0', '2.0_to_3.0'],
  },
  'extreme_false_zone': {
    'actualGapBands': ['lt_-2.0', '-2.0_to_-1.0'],
    'evidenceGapBands': ['gte_3.0'],
  },
  'extreme_true_zone': {
    'actualGapBands': ['0.0_to_1.0', 'gte_1.0'],
    'evidenceGapBands': ['lt_1.0'],
  },
};

void main(List<String> args) {
  final dataDirectory =
      _argument(args, '--data-directory') ?? _defaultDataDirectory;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumTohokuMiddleGapTransitionZoneDiagnosticJson(
    dataDirectory: dataDirectory,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    plumTohokuMiddleGapTransitionZoneDiagnosticMarkdown(report),
  );

  stdout.writeln(
    'wrote PLUM Tohoku middle-gap transition-zone diagnostic report',
  );
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumTohokuMiddleGapTransitionZoneDiagnosticJson({
  String dataDirectory = _defaultDataDirectory,
  String modelPath = _defaultModelPath,
}) {
  final base = gap_transition
      .buildPlumTohokuMismatchGapTransitionDiagnosticJson(
        dataDirectory: dataDirectory,
        modelPath: modelPath,
      );
  final errors = [for (final error in _list(base['errors'])) error.toString()];
  final thresholds = _map(base['thresholds']);
  return {
    'schemaVersion': 'plum_tohoku_middle_gap_transition_zone_diagnostic_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': {
      ..._map(base['policy']),
      'method': 'PLUM Tohoku middle-gap transition-zone diagnostic',
    },
    'inputs': _map(base['inputs']),
    'focusFilter': _map(base['focusFilter']),
    'gapDefinitions': _map(base['gapDefinitions']),
    'zoneDefinitions': {
      'middle_transition_zone':
          'actual gap in [-1.0, +1.0) and evidence gap in [1.0, 3.0)',
      'extreme_false_zone': 'actual gap < -1.0 and evidence gap >= 3.0',
      'extreme_true_zone': 'actual gap >= 0.0 and evidence gap < 1.0',
      'other_mismatch_zone':
          'all remaining mismatch cells outside the three comparison zones',
    },
    'coverage': _map(base['coverage']),
    'thresholds': {
      for (final label in _thresholdLabels)
        if (thresholds[label] != null)
          label: _buildThresholdJson(_map(thresholds[label])),
    },
    'errors': errors,
  };
}

Map<String, Object?> _buildThresholdJson(Map<String, Object?> threshold) {
  final validation = _map(threshold['validation']);
  final test = _map(threshold['test']);
  final validationSummary = _map(validation['summary']);
  final testSummary = _map(test['summary']);
  final validationCells = _indexCells(validation['cells']);
  final testCells = _indexCells(test['cells']);
  final validationMismatchCount = _int(
    validationSummary['mismatchSampleCount'],
  );
  final testMismatchCount = _int(testSummary['mismatchSampleCount']);

  final zoneRows = [
    for (final label in const [
      'middle_transition_zone',
      'extreme_false_zone',
      'extreme_true_zone',
      'other_mismatch_zone',
    ])
      _buildZoneTransferRow(
        label: label,
        validationCells: validationCells,
        testCells: testCells,
        validationMismatchCount: validationMismatchCount,
        testMismatchCount: testMismatchCount,
      ),
  ];

  final dominantRow = zoneRows.reduce((left, right) {
    if (_number(right['shareDelta']) > _number(left['shareDelta'])) {
      return right;
    }
    return left;
  });
  final middleRow = zoneRows.firstWhere(
    (row) => row['zone'] == 'middle_transition_zone',
  );

  return {
    'validation': validation,
    'test': test,
    'zoneComparisons': zoneRows,
    'signatureAssessment': {
      'dominantShareDeltaZone': dominantRow['zone'],
      'dominantShareDelta': dominantRow['shareDelta'],
      'middleTransitionZoneShareDelta': middleRow['shareDelta'],
      'middleTransitionZoneTestShare': middleRow['testShare'],
      'middleTransitionZoneValidationShare': middleRow['validationShare'],
      'middleTransitionZonePrecisionDelta': middleRow['precisionDelta'],
      'middleTransitionLikelyFrozenSignature':
          dominantRow['zone'] == 'middle_transition_zone' &&
          _number(middleRow['shareDelta']) > 0,
    },
  };
}

Map<String, Map<String, Object?>> _indexCells(Object? rawRows) => {
  for (final raw in _list(rawRows))
    '${_map(raw)['actualGapBand']}|${_map(raw)['evidenceGapBand']}': _map(raw),
};

Map<String, Object?> _buildZoneTransferRow({
  required String label,
  required Map<String, Map<String, Object?>> validationCells,
  required Map<String, Map<String, Object?>> testCells,
  required int validationMismatchCount,
  required int testMismatchCount,
}) {
  final validationZone = _aggregateZone(
    label: label,
    cells: validationCells,
    mismatchCount: validationMismatchCount,
  );
  final testZone = _aggregateZone(
    label: label,
    cells: testCells,
    mismatchCount: testMismatchCount,
  );
  return {
    'zone': label,
    'validationCount': validationZone.count,
    'validationShare': validationZone.share,
    'validationPrecision': validationZone.precision,
    'testCount': testZone.count,
    'testShare': testZone.share,
    'testPrecision': testZone.precision,
    'shareDelta': testZone.share - validationZone.share,
    'precisionDelta': testZone.precision - validationZone.precision,
  };
}

_ZoneAggregate _aggregateZone({
  required String label,
  required Map<String, Map<String, Object?>> cells,
  required int mismatchCount,
}) {
  final matchingCells = [
    for (final entry in cells.entries)
      if (_isCellInZone(
        label: label,
        actualGapBand: entry.value['actualGapBand']?.toString() ?? '',
        evidenceGapBand: entry.value['evidenceGapBand']?.toString() ?? '',
      ))
        entry.value,
  ];
  var count = 0;
  var tp = 0;
  for (final cell in matchingCells) {
    final cellCount = _int(cell['count']);
    count += cellCount;
    tp += (_number(cell['precision']) * cellCount).round();
  }
  return _ZoneAggregate(
    count: count,
    share: mismatchCount == 0 ? 0.0 : count / mismatchCount,
    precision: count == 0 ? 0.0 : tp / count,
  );
}

bool _isCellInZone({
  required String label,
  required String actualGapBand,
  required String evidenceGapBand,
}) {
  if (label == 'other_mismatch_zone') {
    return !_zoneDefinitions.keys.any(
      (zone) => _isCellInZone(
        label: zone,
        actualGapBand: actualGapBand,
        evidenceGapBand: evidenceGapBand,
      ),
    );
  }
  final definition = _zoneDefinitions[label];
  if (definition == null) return false;
  return definition['actualGapBands']!.contains(actualGapBand) &&
      definition['evidenceGapBands']!.contains(evidenceGapBand);
}

String plumTohokuMiddleGapTransitionZoneDiagnosticMarkdown(
  Map<String, Object?> report,
) {
  final policy = _map(report['policy']);
  final coverage = _map(report['coverage']);
  final focusFilter = _map(report['focusFilter']);
  final definitions = _map(report['gapDefinitions']);
  final zoneDefinitions = _map(report['zoneDefinitions']);
  final thresholds = _map(report['thresholds']);
  final buffer = StringBuffer()
    ..writeln('# PLUM Tohoku Middle-Gap Transition-Zone Diagnostic')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Method: `${policy['method']}`')
    ..writeln('- Frozen test evaluated: `${policy['frozenTestEvaluated']}`')
    ..writeln('- Production ready: `${policy['productionReady']}`')
    ..writeln('- Production UI connected: `${policy['productionUiConnected']}`')
    ..writeln('- Diagnostic only: `${policy['diagnosticOnly']}`')
    ..writeln('- Parameters tuned: `${policy['parametersTuned']}`')
    ..writeln('- Suppression applied: `${policy['suppressionApplied']}`')
    ..writeln(
      '- Raw predicted intensity mutated: '
      '`${policy['rawPredictedIntensityMutated']}`',
    )
    ..writeln()
    ..writeln('## Coverage')
    ..writeln()
    ..writeln('| Split | Variants | Station forecasts |')
    ..writeln('| --- | ---: | ---: |')
    ..writeln(
      '| validation | ${coverage['validationVariants']} | '
      '${coverage['validationStationForecasts']} |',
    )
    ..writeln(
      '| test | ${coverage['testVariants']} | '
      '${coverage['testStationForecasts']} |',
    )
    ..writeln()
    ..writeln('## Focus Filter')
    ..writeln()
    ..writeln(
      '- Estimated-source region: `${focusFilter['estimatedSourceRegion']}`',
    )
    ..writeln(
      '- Minimum evidence count: `${focusFilter['minimumEvidenceCount']}`',
    )
    ..writeln(
      '- Maximum nearest evidence distance: '
      '`${focusFilter['maximumNearestEvidenceDistanceKm']} km`',
    )
    ..writeln(
      '- Minimum prediction margin: '
      '`${focusFilter['minimumPredictionMarginShindo']} shindo`',
    )
    ..writeln(
      '- Baseline threshold crossing required: '
      '`${focusFilter['baselineThresholdCrossingRequired']}`',
    )
    ..writeln()
    ..writeln('## Zone Definitions')
    ..writeln();

  for (final entry in zoneDefinitions.entries) {
    buffer.writeln('- `${entry.key}`: ${entry.value}');
  }
  buffer.writeln();

  buffer
    ..writeln('## Gap Definitions')
    ..writeln();
  for (final definitionKey in const ['actualGapBand', 'evidenceGapBand']) {
    final definition = _map(definitions[definitionKey]);
    buffer.writeln('- `$definitionKey`');
    for (final entry in definition.entries) {
      buffer.writeln('  - `${entry.key}`: ${entry.value}');
    }
  }
  buffer.writeln();

  for (final label in _thresholdLabels) {
    final threshold = _map(thresholds[label]);
    if (threshold.isEmpty) continue;
    final validation = _map(threshold['validation']);
    final test = _map(threshold['test']);
    final validationSummary = _map(validation['summary']);
    final testSummary = _map(test['summary']);
    final signature = _map(threshold['signatureAssessment']);
    final zoneComparisons = _list(threshold['zoneComparisons']);
    buffer
      ..writeln('## `$label`')
      ..writeln()
      ..writeln('### Mismatch Summary')
      ..writeln()
      ..writeln('| Split | Mismatch Samples | Mismatch Precision |')
      ..writeln('| --- | ---: | ---: |')
      ..writeln(
        '| validation | ${validationSummary['mismatchSampleCount']} | '
        '${_pct(validationSummary['mismatchPrecision'])} |',
      )
      ..writeln(
        '| test | ${testSummary['mismatchSampleCount']} | '
        '${_pct(testSummary['mismatchPrecision'])} |',
      )
      ..writeln()
      ..writeln('### Zone Comparison')
      ..writeln()
      ..writeln(
        '| Zone | Val Count | Val Share | Val Precision | Test Count | Test Share | Test Precision | Share Delta | Precision Delta |',
      )
      ..writeln(
        '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
      );
    for (final raw in zoneComparisons) {
      final row = _map(raw);
      buffer.writeln(
        '| `${row['zone']}` | ${row['validationCount']} | '
        '${_pct(row['validationShare'])} | ${_pct(row['validationPrecision'])} | '
        '${row['testCount']} | ${_pct(row['testShare'])} | '
        '${_pct(row['testPrecision'])} | ${_signedPct(_number(row['shareDelta']))} | '
        '${_signedPct(_number(row['precisionDelta']))} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('### Signature Assessment')
      ..writeln()
      ..writeln(
        '- Dominant share-delta zone: '
        '`${signature['dominantShareDeltaZone']}` '
        '(${_signedPct(_number(signature['dominantShareDelta']))})',
      )
      ..writeln(
        '- Middle-transition share: '
        '`${_pct(signature['middleTransitionZoneValidationShare'])} -> '
        '${_pct(signature['middleTransitionZoneTestShare'])}`',
      )
      ..writeln(
        '- Middle-transition precision delta: '
        '`${_signedPct(_number(signature['middleTransitionZonePrecisionDelta']))}`',
      )
      ..writeln(
        '- Middle-transition likely frozen-only signature: '
        '`${signature['middleTransitionLikelyFrozenSignature']}`',
      )
      ..writeln();
  }

  buffer
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- This report is diagnostic-only. It tests whether the frozen hotspot is '
      'best explained by a narrow middle transition zone rather than by broad '
      'mismatch labeling.',
    )
    ..writeln(
      '- It does not tune PLUM, suppress predictions, or authorize production '
      'UI/wording/notification changes.',
    )
    ..writeln();
  return buffer.toString();
}

class _ZoneAggregate {
  final int count;
  final double share;
  final double precision;

  const _ZoneAggregate({
    required this.count,
    required this.share,
    required this.precision,
  });
}

String? _argument(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == name && i + 1 < args.length) return args[i + 1];
    if (arg.startsWith('$name=')) return arg.substring(name.length + 1);
  }
  return null;
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

List<Object?> _list(Object? value) =>
    value is List ? value.cast<Object?>() : const [];

double _number(Object? value) => value is num ? value.toDouble() : 0.0;

int _int(Object? value) => value is num ? value.toInt() : 0;

String _pct(Object? value) {
  final number = _number(value);
  return '${(number * 100).toStringAsFixed(1)}%';
}

String _signedPct(double value) {
  final percent = value * 100;
  final sign = percent >= 0 ? '+' : '';
  return '$sign${percent.toStringAsFixed(1)}pp';
}
