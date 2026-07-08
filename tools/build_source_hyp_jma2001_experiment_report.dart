import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const _schemaVersion = 'source_hyp_jma2001_experiment_report_v1';
const _hybridMethod = 'nied_gif_hybrid_v1';
const _baselineHypKey = 'nied_gif_hyp_v1';
const _jma2001HypKey = 'nied_gif_hyp_jma2001_experiment';
const _jqScoringHypKey = 'nied_gif_hyp_jq_scoring_experiment';
const _defaultInputDirectory =
    '.dart_tool/source_hyp_jma2001_experiment_benchmark';
const _defaultOutput =
    '.dart_tool/source_hyp_jma2001_experiment_report/report.json';
const _defaultMarkdown =
    'docs/baselines/source_hyp_jma2001_experiment_report.generated.md';

void main(List<String> args) {
  final inputDirectory = Directory(
    _argument(args, '--input-dir') ?? _defaultInputDirectory,
  );
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = buildSourceHypJma2001ExperimentReportJson(
    inputDirectory: inputDirectory,
  );
  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(sourceHypJma2001ExperimentMarkdown(report));

  stdout.writeln('wrote HYP JMA2001 experiment report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');
}

Map<String, Object?> buildSourceHypJma2001ExperimentReportJson({
  Directory? inputDirectory,
}) {
  final directory = inputDirectory ?? Directory(_defaultInputDirectory);
  final files = directory.existsSync()
      ? directory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.reference.json'))
            .toList(growable: false)
      : <File>[];
  files.sort((a, b) => a.path.compareTo(b.path));

  final rows = <Map<String, Object?>>[];
  for (final file in files) {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) continue;
    final row = _caseRow(file, decoded.cast<String, Object?>());
    if (row != null) rows.add(row);
  }

  final jmaRows = rows
      .where((row) => row['jma2001HypPresent'] == true)
      .toList(growable: false);
  final jmaSupported = jmaRows
      .where((row) => row['jma2001HypSupported'] == true)
      .toList(growable: false);
  final jqRows = rows
      .where((row) => row['jqScoringHypPresent'] == true)
      .toList(growable: false);
  final jqSupported = jqRows
      .where((row) => row['jqScoringHypSupported'] == true)
      .toList(growable: false);
  final baselineSupported = rows
      .where((row) => row['baselineHypSupported'] == true)
      .toList(growable: false);
  final jmaImprovedVsHyp = jmaRows
      .where((row) => (_number(row['jma2001MinusBaselineHypErrorKm']) ?? 0) < 0)
      .toList(growable: false);
  final jmaRegressedVsHyp = jmaRows
      .where(
        (row) => (_number(row['jma2001MinusBaselineHypErrorKm']) ?? 0) > 10,
      )
      .toList(growable: false);
  final jqImprovedVsHyp = jqRows
      .where(
        (row) => (_number(row['jqScoringMinusBaselineHypErrorKm']) ?? 0) < 0,
      )
      .toList(growable: false);
  final jqRegressedVsHyp = jqRows
      .where(
        (row) => (_number(row['jqScoringMinusBaselineHypErrorKm']) ?? 0) > 10,
      )
      .toList(growable: false);

  return {
    'schemaVersion': _schemaVersion,
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'inputDirectory': directory.path,
    'status': rows.isEmpty ? 'missing_input' : 'pass',
    'policy': {
      'diagnosticOnly': true,
      'productionCoordinateSwitchAllowed': false,
      'requiresReplayWithEmitJma2001HypExperiment': true,
      'requiresReplayWithEmitJqScoringHypExperiment': true,
      'referenceAlgorithmInput': 'nied_kmoni_gif_reverse_decoded',
    },
    'summary': {
      'caseCount': rows.length,
      'jma2001HypPresentCount': jmaRows.length,
      'jqScoringHypPresentCount': jqRows.length,
      'baselineHypSupportedCount': baselineSupported.length,
      'jma2001HypSupportedCount': jmaSupported.length,
      'jqScoringHypSupportedCount': jqSupported.length,
      'jma2001ImprovedVsBaselineHypCount': jmaImprovedVsHyp.length,
      'jma2001RegressedVsBaselineHypBy10KmCount': jmaRegressedVsHyp.length,
      'jqScoringImprovedVsBaselineHypCount': jqImprovedVsHyp.length,
      'jqScoringRegressedVsBaselineHypBy10KmCount': jqRegressedVsHyp.length,
      'medianHybridFinalErrorKm': _median([
        for (final row in rows)
          if (_number(row['hybridFinalErrorKm']) != null)
            _number(row['hybridFinalErrorKm'])!,
      ]),
      'medianBaselineHypErrorKm': _median([
        for (final row in rows)
          if (_number(row['baselineHypFinalErrorKm']) != null)
            _number(row['baselineHypFinalErrorKm'])!,
      ]),
      'medianJma2001HypErrorKm': _median([
        for (final row in jmaRows)
          if (_number(row['jma2001HypFinalErrorKm']) != null)
            _number(row['jma2001HypFinalErrorKm'])!,
      ]),
      'medianJma2001MinusBaselineHypErrorKm': _median([
        for (final row in jmaRows)
          if (_number(row['jma2001MinusBaselineHypErrorKm']) != null)
            _number(row['jma2001MinusBaselineHypErrorKm'])!,
      ]),
      'medianJqScoringHypErrorKm': _median([
        for (final row in jqRows)
          if (_number(row['jqScoringHypFinalErrorKm']) != null)
            _number(row['jqScoringHypFinalErrorKm'])!,
      ]),
      'medianJqScoringMinusBaselineHypErrorKm': _median([
        for (final row in jqRows)
          if (_number(row['jqScoringMinusBaselineHypErrorKm']) != null)
            _number(row['jqScoringMinusBaselineHypErrorKm'])!,
      ]),
    },
    'rows': rows,
    'findings': _findings(rows),
  };
}

String sourceHypJma2001ExperimentMarkdown(Map<String, Object?> report) {
  final summary = _map(report['summary']);
  final rows = _list(report['rows']).map(_map).toList(growable: false);
  final b = StringBuffer()
    ..writeln('# HYP JMA2001 experiment report')
    ..writeln()
    ..writeln('- Schema: `${report['schemaVersion']}`')
    ..writeln('- Status: `${report['status']}`')
    ..writeln(
      '- Diagnostic only: `${_map(report['policy'])['diagnosticOnly']}`',
    )
    ..writeln('- Cases: `${summary['caseCount']}`')
    ..writeln(
      '- JMA2001 diagnostic present: `${summary['jma2001HypPresentCount']}`',
    )
    ..writeln(
      '- JQ scoring diagnostic present: `${summary['jqScoringHypPresentCount']}`',
    )
    ..writeln(
      '- Baseline/JMA/JQ supported: `${summary['baselineHypSupportedCount']}` / `${summary['jma2001HypSupportedCount']}` / `${summary['jqScoringHypSupportedCount']}`',
    )
    ..writeln(
      '- Median baseline/JMA/JQ HYP error: `${_fmt(summary['medianBaselineHypErrorKm'])}` / `${_fmt(summary['medianJma2001HypErrorKm'])}` / `${_fmt(summary['medianJqScoringHypErrorKm'])}` km',
    )
    ..writeln()
    ..writeln(
      '| Case | Hybrid | HYP fixed | HYP JMA2001 | HYP JQ | JMA-fixed | JQ-fixed | Fixed supported | JMA supported | JQ supported | Fixed P/S/O | JMA P/S/O | JQ P/S/O | Fixed residual | JMA residual | JQ residual | Finding |',
    )
    ..writeln(
      '|---|---:|---:|---:|---:|---:|---:|---|---|---|---|---|---|---:|---:|---:|---|',
    );
  for (final row in rows) {
    b.writeln(
      '| `${row['caseId']}` '
      '| ${_fmt(row['hybridFinalErrorKm'])} '
      '| ${_fmt(row['baselineHypFinalErrorKm'])} '
      '| ${_fmt(row['jma2001HypFinalErrorKm'])} '
      '| ${_fmt(row['jqScoringHypFinalErrorKm'])} '
      '| ${_fmt(row['jma2001MinusBaselineHypErrorKm'])} '
      '| ${_fmt(row['jqScoringMinusBaselineHypErrorKm'])} '
      '| ${row['baselineHypSupported']} '
      '| ${row['jma2001HypSupported']} '
      '| ${row['jqScoringHypSupported']} '
      '| ${row['baselineHypPhasePCount']}/${row['baselineHypPhaseSCount']}/${row['baselineHypPhaseOtherCount']} '
      '| ${row['jma2001HypPhasePCount']}/${row['jma2001HypPhaseSCount']}/${row['jma2001HypPhaseOtherCount']} '
      '| ${row['jqScoringHypPhasePCount']}/${row['jqScoringHypPhaseSCount']}/${row['jqScoringHypPhaseOtherCount']} '
      '| ${_fmt(row['baselineHypPhaseMeanResidualSeconds'])} '
      '| ${_fmt(row['jma2001HypPhaseMeanResidualSeconds'])} '
      '| ${_fmt(row['jqScoringHypPhaseMeanResidualSeconds'])} '
      '| ${(row['findings'] as List).join(', ')} |',
    );
  }
  b
    ..writeln()
    ..writeln('## Findings')
    ..writeln();
  for (final finding in _list(report['findings'])) {
    b.writeln('- `$finding`');
  }
  return b.toString();
}

Map<String, Object?>? _caseRow(File file, Map<String, Object?> report) {
  final caseData = _map(report['case']);
  final truth = _map(caseData['truth']);
  final truthLat = _number(truth['latitude']);
  final truthLng = _number(truth['longitude']);
  if (truthLat == null || truthLng == null) return null;

  final estimateFrames = <Map<String, Object?>>[];
  for (final rawFrame in _list(report['frames'])) {
    final frame = _map(rawFrame);
    final method = _map(_map(frame['methods'])[_hybridMethod]);
    final estimate = _mapOrNull(method['estimate']);
    if (estimate != null) {
      estimateFrames.add({'method': method, 'estimate': estimate});
    }
  }
  if (estimateFrames.isEmpty) return null;

  final finalFrame = estimateFrames.last;
  final finalMethod = _map(finalFrame['method']);
  final finalEstimate = _map(finalFrame['estimate']);
  final diagnostics = _map(finalEstimate['diagnostics']);
  final baselineHyp = _mapOrNull(diagnostics[_baselineHypKey]);
  final jmaHyp = _mapOrNull(diagnostics[_jma2001HypKey]);
  final jqHyp = _mapOrNull(diagnostics[_jqScoringHypKey]);
  final hybridError = _number(finalMethod['errorKm']);
  final baselineHypError = _hypErrorKm(baselineHyp, truthLat, truthLng);
  final jmaHypError = _hypErrorKm(jmaHyp, truthLat, truthLng);
  final jqHypError = _hypErrorKm(jqHyp, truthLat, truthLng);
  final jmaMinusBaseline = jmaHypError == null || baselineHypError == null
      ? null
      : jmaHypError - baselineHypError;
  final jqMinusBaseline = jqHypError == null || baselineHypError == null
      ? null
      : jqHypError - baselineHypError;

  final decodedFrameCount = _integer(report['decodedFrameCount']);
  final requestedFrameCount = _integer(report['requestedFrameCount']);
  final findings = _rowFindings(
    decodedFrameCount: decodedFrameCount,
    requestedFrameCount: requestedFrameCount,
    baselineHypPresent: baselineHyp != null,
    jmaHypPresent: jmaHyp != null,
    jqHypPresent: jqHyp != null,
    baselineHypError: baselineHypError,
    jmaHypError: jmaHypError,
    jqHypError: jqHypError,
    baselineSupported: baselineHyp?['supported'] == true,
    jmaSupported: jmaHyp?['supported'] == true,
    jqSupported: jqHyp?['supported'] == true,
    jmaMinusBaseline: jmaMinusBaseline,
    jqMinusBaseline: jqMinusBaseline,
  );

  return {
    'caseId': caseData['caseId']?.toString() ?? file.uri.pathSegments.last,
    'inputPath': file.path,
    'decodedFrameCount': decodedFrameCount,
    'requestedFrameCount': requestedFrameCount,
    'estimateFrameCount': estimateFrames.length,
    'hybridFinalErrorKm': hybridError,
    'baselineHypPresent': baselineHyp != null,
    'jma2001HypPresent': jmaHyp != null,
    'jqScoringHypPresent': jqHyp != null,
    ..._hypFields('baselineHyp', baselineHyp, baselineHypError),
    ..._hypFields('jma2001Hyp', jmaHyp, jmaHypError),
    ..._hypFields('jqScoringHyp', jqHyp, jqHypError),
    'jma2001MinusBaselineHypErrorKm': jmaMinusBaseline,
    'jqScoringMinusBaselineHypErrorKm': jqMinusBaseline,
    'findings': findings,
  };
}

Map<String, Object?> _hypFields(
  String prefix,
  Map<String, Object?>? hyp,
  double? errorKm,
) {
  return {
    '${prefix}FinalErrorKm': errorKm,
    '${prefix}Latitude': _number(hyp?['latitude']),
    '${prefix}Longitude': _number(hyp?['longitude']),
    '${prefix}DepthKm': _number(hyp?['depth_km']),
    '${prefix}Supported': hyp?['supported'] == true,
    '${prefix}POnlySupported': hyp?['p_only_supported'] == true,
    '${prefix}DepthSupported': hyp?['depth_supported'] == true,
    '${prefix}PhasePCount': _integer(hyp?['phase_p_count']) ?? 0,
    '${prefix}PhaseSCount': _integer(hyp?['phase_s_count']) ?? 0,
    '${prefix}PhaseOtherCount': _integer(hyp?['phase_other_count']) ?? 0,
    '${prefix}POriginClusterCount': _integer(hyp?['p_origin_cluster_count']),
    '${prefix}SOriginClusterCount': _integer(hyp?['s_origin_cluster_count']),
    '${prefix}POriginMeanSeconds': _number(hyp?['p_origin_mean_s']),
    '${prefix}SOriginMeanSeconds': _number(hyp?['s_origin_mean_s']),
    '${prefix}POriginSpreadSeconds': _number(hyp?['p_origin_spread_s']),
    '${prefix}SOriginSpreadSeconds': _number(hyp?['s_origin_spread_s']),
    '${prefix}PhaseOriginMeanGapSeconds': _number(
      hyp?['phase_origin_mean_gap_s'],
    ),
    '${prefix}PhaseMeanResidualSeconds': _number(hyp?['phase_mean_residual_s']),
    '${prefix}PairMeanResidualSeconds': _number(hyp?['pair_mean_residual_s']),
    '${prefix}UnarrivedPenalty': _number(hyp?['unarrived_penalty']),
    '${prefix}MaxSupportedUnarrivedPenalty': _number(
      hyp?['max_supported_unarrived_penalty'],
    ),
    '${prefix}PhaseBalancePenalty': _number(hyp?['phase_balance_penalty']),
    '${prefix}TravelTimeModel': hyp?['travel_time_model']?.toString(),
    '${prefix}ScoringModel': hyp?['scoring_model']?.toString(),
  };
}

double? _hypErrorKm(
  Map<String, Object?>? hyp,
  double truthLat,
  double truthLng,
) {
  final lat = _number(hyp?['latitude']);
  final lng = _number(hyp?['longitude']);
  if (lat == null || lng == null) return null;
  return _haversineKm(lat, lng, truthLat, truthLng);
}

List<String> _rowFindings({
  required int? decodedFrameCount,
  required int? requestedFrameCount,
  required bool baselineHypPresent,
  required bool jmaHypPresent,
  required bool jqHypPresent,
  required double? baselineHypError,
  required double? jmaHypError,
  required double? jqHypError,
  required bool baselineSupported,
  required bool jmaSupported,
  required bool jqSupported,
  required double? jmaMinusBaseline,
  required double? jqMinusBaseline,
}) {
  final findings = <String>[];
  final decodedCoverage =
      decodedFrameCount == null ||
          requestedFrameCount == null ||
          requestedFrameCount == 0
      ? null
      : decodedFrameCount / requestedFrameCount;
  if (decodedCoverage != null && decodedCoverage < 0.5) {
    findings.add('low_decoded_frame_coverage');
  }
  if (!baselineHypPresent) findings.add('missing_baseline_hyp');
  if (!jmaHypPresent) {
    findings.add('missing_jma2001_hyp_experiment');
  }
  if (!jqHypPresent) findings.add('missing_jq_scoring_hyp_experiment');
  if (jmaMinusBaseline != null) {
    if (jmaMinusBaseline < -10) {
      findings.add('jma2001_improves_hyp_by_10km');
    } else if (jmaMinusBaseline > 10) {
      findings.add('jma2001_regresses_hyp_by_10km');
    } else {
      findings.add('jma2001_near_baseline_hyp');
    }
  }
  if (baselineSupported && !jmaSupported) {
    findings.add('jma2001_loses_supported_case');
  }
  if (!baselineSupported && jmaSupported) {
    findings.add('jma2001_gains_supported_case');
  }
  if (jmaHypError != null && baselineHypError != null && jmaHypError < 10) {
    findings.add('jma2001_low_error_candidate');
  }
  if (jqMinusBaseline != null) {
    if (jqMinusBaseline < -10) {
      findings.add('jq_scoring_improves_hyp_by_10km');
    } else if (jqMinusBaseline > 10) {
      findings.add('jq_scoring_regresses_hyp_by_10km');
    } else {
      findings.add('jq_scoring_near_baseline_hyp');
    }
  }
  if (baselineSupported && !jqSupported) {
    findings.add('jq_scoring_loses_supported_case');
  }
  if (!baselineSupported && jqSupported) {
    findings.add('jq_scoring_gains_supported_case');
  }
  if (jqSupported && jqHypError != null && jqHypError > 40) {
    findings.add('jq_scoring_supported_large_error');
  }
  if (jqHypError != null && baselineHypError != null && jqHypError < 10) {
    findings.add('jq_scoring_low_error_candidate');
  }
  return findings;
}

List<String> _findings(List<Map<String, Object?>> rows) {
  if (rows.isEmpty) return const ['missing_input_reference_reports'];
  final findings = <String>[];
  if (rows.any((row) => row['jma2001HypPresent'] != true)) {
    findings.add('some_reports_missing_jma2001_experiment');
  }
  if (rows.any((row) => row['jqScoringHypPresent'] != true)) {
    findings.add('some_reports_missing_jq_scoring_experiment');
  }
  if (rows.any(
    (row) => _list(row['findings']).contains('jma2001_improves_hyp_by_10km'),
  )) {
    findings.add('jma2001_improves_some_hyp_candidates');
  }
  if (rows.any(
    (row) => _list(row['findings']).contains('jma2001_regresses_hyp_by_10km'),
  )) {
    findings.add('jma2001_regresses_some_hyp_candidates');
  }
  if (rows.any(
    (row) => _list(row['findings']).contains('jq_scoring_improves_hyp_by_10km'),
  )) {
    findings.add('jq_scoring_improves_some_hyp_candidates');
  }
  if (rows.any(
    (row) =>
        _list(row['findings']).contains('jq_scoring_regresses_hyp_by_10km'),
  )) {
    findings.add('jq_scoring_regresses_some_hyp_candidates');
  }
  if (rows.any(
    (row) => _list(row['findings']).contains('low_decoded_frame_coverage'),
  )) {
    findings.add('some_reports_have_low_decoded_frame_coverage');
  }
  if (rows.any(
    (row) =>
        _list(row['findings']).contains('jq_scoring_supported_large_error'),
  )) {
    findings.add('jq_scoring_support_gate_allows_large_error_case');
  }
  findings.add('diagnostic_only_do_not_promote');
  return findings;
}

String? _argument(List<String> args, String name) {
  for (var index = 0; index < args.length; index++) {
    final arg = args[index];
    if (arg == name && index + 1 < args.length) return args[index + 1];
    if (arg.startsWith('$name=')) return arg.substring(name.length + 1);
  }
  return null;
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};

Map<String, Object?>? _mapOrNull(Object? value) =>
    value is Map ? value.cast<String, Object?>() : null;

List<Object?> _list(Object? value) =>
    value is List ? value.cast<Object?>() : const <Object?>[];

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _integer(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _median(List<double> values) {
  if (values.isEmpty) return null;
  values.sort();
  final middle = values.length ~/ 2;
  if (values.length.isOdd) return values[middle];
  return (values[middle - 1] + values[middle]) / 2.0;
}

String _fmt(Object? value, {int digits = 1}) {
  final number = _number(value);
  if (number == null || !number.isFinite) return '-';
  return number.toStringAsFixed(digits);
}

double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusKm = 6371.0;
  final dLat = _degToRad(lat2 - lat1);
  final dLon = _degToRad(lon2 - lon1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degToRad(lat1)) *
          math.cos(_degToRad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _degToRad(double degrees) => degrees * math.pi / 180.0;
