import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const _schemaVersion = 'source_hyp_vs_hybrid_report_v1';
const _hybridMethod = 'nied_gif_hybrid_v1';
const _defaultInputDirectory = '.dart_tool/source_estimation_benchmark';
const _defaultOutput = '.dart_tool/source_hyp_vs_hybrid_report/report.json';
const _defaultMarkdown =
    'docs/baselines/source_hyp_vs_hybrid_report.generated.md';

void main(List<String> args) {
  final inputDirectory = Directory(
    _argument(args, '--input-dir') ?? _defaultInputDirectory,
  );
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = buildSourceHypVsHybridReportJson(
    inputDirectory: inputDirectory,
  );
  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(sourceHypVsHybridReportMarkdown(report));

  stdout.writeln('wrote HYP-vs-hybrid report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');
}

Map<String, Object?> buildSourceHypVsHybridReportJson({
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

  final supportedRows = rows
      .where((row) => row['hypSupported'] == true)
      .toList(growable: false);
  final depthSupportedRows = rows
      .where((row) => row['hypDepthSupported'] == true)
      .toList(growable: false);
  final pOnlyRows = rows
      .where((row) => row['hypPOnlySupported'] == true)
      .toList(growable: false);
  final improvedRows = rows
      .where((row) {
        final hybridError = _number(row['hybridFinalErrorKm']);
        final hypError = _number(row['hypFinalErrorKm']);
        return hybridError != null &&
            hypError != null &&
            hypError < hybridError;
      })
      .toList(growable: false);

  return {
    'schemaVersion': _schemaVersion,
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'inputDirectory': directory.path,
    'summary': {
      'caseCount': rows.length,
      'hypSupportedCount': supportedRows.length,
      'hypDepthSupportedCount': depthSupportedRows.length,
      'hypPOnlySupportedCount': pOnlyRows.length,
      'hypImprovedFinalCount': improvedRows.length,
      'medianHybridFinalErrorKm': _median([
        for (final row in rows)
          if (_number(row['hybridFinalErrorKm']) != null)
            _number(row['hybridFinalErrorKm'])!,
      ]),
      'medianHypFinalErrorKm': _median([
        for (final row in rows)
          if (_number(row['hypFinalErrorKm']) != null)
            _number(row['hypFinalErrorKm'])!,
      ]),
      'medianHypSupportedErrorKm': _median([
        for (final row in supportedRows)
          if (_number(row['hypFinalErrorKm']) != null)
            _number(row['hypFinalErrorKm'])!,
      ]),
      'maxUnarrivedPenalty': rows.isEmpty
          ? null
          : rows
                .map((row) => _number(row['hypUnarrivedPenalty']) ?? 0)
                .reduce(math.max),
    },
    'policy': {
      'diagnosticOnly': true,
      'productionCoordinateSwitchAllowed': false,
      'pOnlySupportedMeaning': 'timing_fit_only_not_location_confidence',
      'referenceAlgorithmInput': 'nied_kmoni_gif_reverse_decoded',
    },
    'rows': rows,
    'findings': _findings(rows),
  };
}

String sourceHypVsHybridReportMarkdown(Map<String, Object?> report) {
  final summary = _map(report['summary']);
  final rows = _list(report['rows']).map(_map).toList(growable: false);
  final b = StringBuffer()
    ..writeln('# Source HYP vs hybrid diagnostic report')
    ..writeln()
    ..writeln('- Schema: `${report['schemaVersion']}`')
    ..writeln(
      '- Diagnostic only: `${_map(report['policy'])['diagnosticOnly']}`',
    )
    ..writeln('- Cases: `${summary['caseCount']}`')
    ..writeln('- HYP supported: `${summary['hypSupportedCount']}`')
    ..writeln('- HYP depth supported: `${summary['hypDepthSupportedCount']}`')
    ..writeln(
      '- HYP P-only timing fits: `${summary['hypPOnlySupportedCount']}`',
    )
    ..writeln(
      '- HYP improved final error: `${summary['hypImprovedFinalCount']}`',
    )
    ..writeln()
    ..writeln(
      '| Case | Hybrid final | HYP final | Δ final | HYP supported | P-only | Depth | P/S/O | Residual | Pair | Unarrived | Finding |',
    )
    ..writeln('|---|---:|---:|---:|---|---|---:|---|---:|---:|---:|---|');
  for (final row in rows) {
    b.writeln(
      '| `${row['caseId']}` '
      '| ${_fmt(row['hybridFinalErrorKm'])} '
      '| ${_fmt(row['hypFinalErrorKm'])} '
      '| ${_fmt(row['hypMinusHybridFinalErrorKm'])} '
      '| ${row['hypSupported']} '
      '| ${row['hypPOnlySupported']} '
      '| ${_fmt(row['hypDepthKm'], digits: 0)} '
      '| ${row['hypPhasePCount']}/${row['hypPhaseSCount']}/${row['hypPhaseOtherCount']} '
      '| ${_fmt(row['hypPhaseMeanResidualSeconds'])} '
      '| ${_fmt(row['hypPairMeanResidualSeconds'])} '
      '| ${_fmt(row['hypUnarrivedPenalty'])} '
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

  final frames = _list(report['frames']);
  final estimateFrames = <Map<String, Object?>>[];
  for (final rawFrame in frames) {
    final frame = _map(rawFrame);
    final method = _map(_map(frame['methods'])[_hybridMethod]);
    final estimate = _mapOrNull(method['estimate']);
    if (estimate != null) {
      estimateFrames.add({
        'frame': frame,
        'method': method,
        'estimate': estimate,
      });
    }
  }
  if (estimateFrames.isEmpty) return null;

  final finalFrame = estimateFrames.last;
  final finalMethod = _map(finalFrame['method']);
  final finalEstimate = _map(finalFrame['estimate']);
  final bestFrame = estimateFrames.reduce((a, b) {
    final left = _number(_map(a['method'])['errorKm']) ?? double.infinity;
    final right = _number(_map(b['method'])['errorKm']) ?? double.infinity;
    return left <= right ? a : b;
  });
  final bestMethod = _map(bestFrame['method']);
  final hyp = _mapOrNull(_map(finalEstimate['diagnostics'])['nied_gif_hyp_v1']);
  final hybridFinalError = _number(finalMethod['errorKm']);
  final hybridBestError = _number(bestMethod['errorKm']);
  final hypLat = _number(hyp?['latitude']);
  final hypLng = _number(hyp?['longitude']);
  final hypError = hypLat == null || hypLng == null
      ? null
      : _haversineKm(hypLat, hypLng, truthLat, truthLng);
  final delta = hypError == null || hybridFinalError == null
      ? null
      : hypError - hybridFinalError;
  final findings = _rowFindings(
    hybridFinalError: hybridFinalError,
    hypFinalError: hypError,
    hypSupported: hyp?['supported'] == true,
    hypPOnlySupported: hyp?['p_only_supported'] == true,
    hypDepthSupported: hyp?['depth_supported'] == true,
    hypSCount: _integer(hyp?['phase_s_count']) ?? 0,
    hypUnarrivedPenalty: _number(hyp?['unarrived_penalty']),
  );
  final hypSupportReasons = _stringList(hyp?['support_reasons']);
  final hypUnsupportedReasons = _stringList(hyp?['unsupported_reasons']);
  final derivedSupportReasons = hypSupportReasons.isEmpty
      ? _supportReasons(
          supported: hyp?['supported'] == true,
          depthSupported: hyp?['depth_supported'] == true,
          pOnlySupported: hyp?['p_only_supported'] == true,
        )
      : hypSupportReasons;
  final derivedUnsupportedReasons = hypUnsupportedReasons.isEmpty
      ? _unsupportedReasons(
          supported: hyp?['supported'] == true,
          depthSupported: hyp?['depth_supported'] == true,
          pOnlySupported: hyp?['p_only_supported'] == true,
          p: _integer(hyp?['phase_p_count']) ?? 0,
          s: _integer(hyp?['phase_s_count']) ?? 0,
          residual: _number(hyp?['phase_mean_residual_s']),
          pair: _number(hyp?['pair_mean_residual_s']),
          unarrived: _number(hyp?['unarrived_penalty']),
          depthKm: _number(hyp?['depth_km']),
        )
      : hypUnsupportedReasons;

  return {
    'caseId': caseData['caseId']?.toString() ?? file.uri.pathSegments.last,
    'inputPath': file.path,
    'decodedFrameCount': _integer(report['decodedFrameCount']),
    'requestedFrameCount': _integer(report['requestedFrameCount']),
    'estimateFrameCount': estimateFrames.length,
    'hybridFinalErrorKm': hybridFinalError,
    'hybridBestErrorKm': hybridBestError,
    'hybridFinalLatitude': _number(finalEstimate['latitude']),
    'hybridFinalLongitude': _number(finalEstimate['longitude']),
    'hybridFinalSupport': _integer(finalEstimate['supportingStationCount']),
    'hypFinalErrorKm': hypError,
    'hypMinusHybridFinalErrorKm': delta,
    'hypLatitude': hypLat,
    'hypLongitude': hypLng,
    'hypDepthKm': _number(hyp?['depth_km']),
    'hypSupported': hyp?['supported'] == true,
    'hypPOnlySupported': hyp?['p_only_supported'] == true,
    'hypDepthSupported': hyp?['depth_supported'] == true,
    'hypPhasePCount': _integer(hyp?['phase_p_count']) ?? 0,
    'hypPhaseSCount': _integer(hyp?['phase_s_count']) ?? 0,
    'hypPhaseOtherCount': _integer(hyp?['phase_other_count']) ?? 0,
    'hypPhaseMeanResidualSeconds': _number(hyp?['phase_mean_residual_s']),
    'hypPairMeanResidualSeconds': _number(hyp?['pair_mean_residual_s']),
    'hypPairCount': _integer(hyp?['pair_count']) ?? 0,
    'hypUnarrivedPenalty': _number(hyp?['unarrived_penalty']),
    'hypUnarrivedPenaltyCount': _integer(hyp?['unarrived_penalty_count']) ?? 0,
    'hypSupportReasons': derivedSupportReasons,
    'hypUnsupportedReasons': derivedUnsupportedReasons,
    'findings': findings,
  };
}

List<String> _supportReasons({
  required bool supported,
  required bool depthSupported,
  required bool pOnlySupported,
}) {
  final reasons = <String>[];
  if (supported) reasons.add('two_phase_timing_supported');
  if (depthSupported) reasons.add('two_phase_depth_supported');
  if (pOnlySupported) reasons.add('p_only_timing_fit_only');
  return reasons;
}

List<String> _unsupportedReasons({
  required bool supported,
  required bool depthSupported,
  required bool pOnlySupported,
  required int p,
  required int s,
  required double? residual,
  required double? pair,
  required double? unarrived,
  required double? depthKm,
}) {
  if (supported || depthSupported || pOnlySupported) return const [];
  final reasons = <String>[];
  if (p < 3) reasons.add('insufficient_p_support');
  if (s < 2) reasons.add('insufficient_s_support');
  if (s == 0) reasons.add('no_s_support');
  if ((residual ?? 0) > 2.8) reasons.add('phase_residual_too_large');
  if ((pair ?? 0) > 3.5) reasons.add('pair_residual_too_large');
  if ((unarrived ?? 0) > 60.0) reasons.add('unarrived_penalty_too_large');
  if ((depthKm ?? 0) >= 100.0 && (unarrived ?? 0) > 60.0) {
    reasons.add('deep_candidate_with_unarrived_gap');
  }
  return reasons;
}

List<String> _rowFindings({
  required double? hybridFinalError,
  required double? hypFinalError,
  required bool hypSupported,
  required bool hypPOnlySupported,
  required bool hypDepthSupported,
  required int hypSCount,
  required double? hypUnarrivedPenalty,
}) {
  final findings = <String>[];
  if (hypFinalError == null) {
    findings.add('missing_hyp_diagnostic');
    return findings;
  }
  if (hybridFinalError != null) {
    final delta = hypFinalError - hybridFinalError;
    if (delta < -10) {
      findings.add('hyp_improves_final_error');
    } else if (delta > 10) {
      findings.add('hyp_regresses_final_error');
    } else {
      findings.add('hyp_near_hybrid_final_error');
    }
  }
  if (hypSupported) findings.add('hyp_supported');
  if (hypDepthSupported) findings.add('hyp_depth_supported');
  if (hypPOnlySupported) findings.add('p_only_timing_fit_only');
  if (hypSCount == 0) findings.add('no_s_support');
  if ((hypUnarrivedPenalty ?? 0) >= 40) {
    findings.add('large_unarrived_penalty');
  }
  return findings;
}

List<String> _findings(List<Map<String, Object?>> rows) {
  final findings = <String>[];
  if (rows.any((row) => (row['findings'] as List).contains('no_s_support'))) {
    findings.add('p_only_cases_must_not_promote_location');
  }
  if (rows.any(
    (row) => (row['findings'] as List).contains('large_unarrived_penalty'),
  )) {
    findings.add('unarrived_penalty_needs_calibration');
  }
  if (rows.any((row) => row['hypDepthSupported'] == true)) {
    findings.add('some_reference_cases_have_two_phase_depth_support');
  }
  if (!rows.any((row) => row['hypSupported'] == true)) {
    findings.add('no_supported_hyp_cases_found');
  }
  return findings;
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

Map<String, Object?> _map(Object? value) {
  if (value is Map) return value.cast<String, Object?>();
  return <String, Object?>{};
}

Map<String, Object?>? _mapOrNull(Object? value) {
  if (value is Map) return value.cast<String, Object?>();
  return null;
}

List<Object?> _list(Object? value) {
  if (value is List) return value.cast<Object?>();
  return const [];
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.map((entry) => entry.toString()).toList(growable: false);
}

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
  final sorted = List<double>.from(values)..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2.0;
}

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusKm = 6371.0;
  final dLat = _degToRad(lat2 - lat1);
  final dLng = _degToRad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_degToRad(lat1)) *
          math.cos(_degToRad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c;
}

double _degToRad(double deg) => deg * math.pi / 180.0;

String _fmt(Object? value, {int digits = 1}) {
  final number = _number(value);
  return number == null ? '--' : number.toStringAsFixed(digits);
}
