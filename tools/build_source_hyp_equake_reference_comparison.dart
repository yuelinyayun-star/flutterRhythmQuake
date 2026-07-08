import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const _schemaVersion = 'source_hyp_equake_reference_comparison_v1';
const _defaultReferenceCases =
    'docs/data/equake_phase_origin_reference_cases.json';
const _defaultHypReport =
    '.dart_tool/source_hyp_jma2001_experiment_report/report.json';
const _defaultCurrentCaptureReport =
    '.dart_tool/current_capture_replay_analysis/report.json';
const _defaultOutput =
    '.dart_tool/source_hyp_equake_reference_comparison/report.json';
const _defaultMarkdown =
    'docs/baselines/source_hyp_equake_reference_comparison.generated.md';

void main(List<String> args) {
  final referenceCases = File(
    _argument(args, '--reference-cases') ?? _defaultReferenceCases,
  );
  final hypReport = File(_argument(args, '--hyp-report') ?? _defaultHypReport);
  final currentCaptureReport = File(
    _argument(args, '--current-capture-report') ?? _defaultCurrentCaptureReport,
  );
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = buildSourceHypEquakeReferenceComparisonJson(
    referenceCases: referenceCases,
    hypReport: hypReport,
    currentCaptureReport: currentCaptureReport,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    sourceHypEquakeReferenceComparisonMarkdown(report),
  );

  stdout.writeln('wrote EQuake reference comparison report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');
}

Map<String, Object?> buildSourceHypEquakeReferenceComparisonJson({
  File? referenceCases,
  File? hypReport,
  File? currentCaptureReport,
}) {
  final referenceFile = referenceCases ?? File(_defaultReferenceCases);
  final hypReportFile = hypReport ?? File(_defaultHypReport);
  final currentReportFile =
      currentCaptureReport ?? File(_defaultCurrentCaptureReport);

  final reference = _readJsonMap(referenceFile);
  final hypRows = _indexRows(_list(_readJsonMap(hypReportFile)['rows']));
  final currentRows = _indexRows(
    _list(_readJsonMap(currentReportFile)['cases']),
  );
  final referencePolicy = _map(reference['policy']);

  final rows = <Map<String, Object?>>[];
  for (final rawCase in _list(reference['cases'])) {
    final referenceCase = _map(rawCase);
    if (referenceCase.isEmpty) continue;
    rows.add(_comparisonRow(referenceCase, hypRows, currentRows));
  }

  final hypMatched = rows
      .where((row) => row['hypBenchmarkMatched'] == true)
      .toList(growable: false);
  final currentMatched = rows
      .where((row) => row['currentCaptureMatched'] == true)
      .toList(growable: false);

  return {
    'schemaVersion': _schemaVersion,
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'referenceCasesPath': referenceFile.path,
    'hypReportPath': hypReportFile.path,
    'currentCaptureReportPath': currentReportFile.path,
    'status': rows.isEmpty ? 'missing_reference_cases' : 'pass',
    'policy': {
      'diagnosticOnly': true,
      'referenceOnly': referencePolicy['referenceOnly'] == true,
      'notCatalogTruth': referencePolicy['notCatalogTruth'] == true,
      'gifDerivedReference': referencePolicy['gifDerived'] == true,
      'doNotUseForFrozenMetricTruth':
          referencePolicy['doNotUseForFrozenMetricTruth'] == true,
      'productionCoordinateSwitchAllowed': false,
    },
    'summary': {
      'caseCount': rows.length,
      'hypBenchmarkMatchedCount': hypMatched.length,
      'currentCaptureMatchedCount': currentMatched.length,
      'missingHypBenchmarkCount': rows.length - hypMatched.length,
      'jqScoringNearEquake20KmCount': rows
          .where(
            (row) => (_number(row['jqScoringErrorVsEquakeKm']) ?? 999) <= 20,
          )
          .length,
      'jqScoringZeroPAgainstEquakePCount': rows
          .where(
            (row) => _list(
              row['findings'],
            ).contains('jq_scoring_zero_p_against_equake_p_support'),
          )
          .length,
      'currentCaptureFarFromEquake40KmCount': rows
          .where(
            (row) => (_number(row['currentFinalErrorVsEquakeKm']) ?? 0) > 40,
          )
          .length,
    },
    'rows': rows,
    'findings': _globalFindings(rows),
  };
}

String sourceHypEquakeReferenceComparisonMarkdown(Map<String, Object?> report) {
  final summary = _map(report['summary']);
  final rows = _list(report['rows']).map(_map).toList(growable: false);
  final b = StringBuffer()
    ..writeln('# HYP vs EQuake reference comparison')
    ..writeln()
    ..writeln('- Schema: `${report['schemaVersion']}`')
    ..writeln('- Status: `${report['status']}`')
    ..writeln(
      '- Reference-only / not truth: `${_map(report['policy'])['referenceOnly']}` / `${_map(report['policy'])['notCatalogTruth']}`',
    )
    ..writeln('- Cases: `${summary['caseCount']}`')
    ..writeln(
      '- HYP benchmark matched: `${summary['hypBenchmarkMatchedCount']}`',
    )
    ..writeln(
      '- Current capture matched: `${summary['currentCaptureMatchedCount']}`',
    )
    ..writeln()
    ..writeln(
      '| Case | EQ final | Catalog error | EQ P/S/O | HYP case | JQ-EQ | JQ P/S/O | Current case | Current-EQ | Findings |',
    )
    ..writeln('|---|---|---:|---|---|---:|---|---|---:|---|');

  for (final row in rows) {
    final eq = _map(row['equakeFinal']);
    b.writeln(
      '| `${row['caseId']}` '
      '| ${_fmtLocation(eq['latitude'], eq['longitude'], eq['depthKm'])} '
      '| ${_fmt(row['equakeErrorVsCatalogKm'])} '
      '| ${row['equakePhasePCount']}/${row['equakePhaseSCount']}/${row['equakePhaseOtherCount']} '
      '| ${_dash(row['hypBenchmarkCaseId'])} '
      '| ${_fmt(row['jqScoringErrorVsEquakeKm'])} '
      '| ${_phase(row, 'jqScoring')} '
      '| ${_dash(row['currentCaptureCaseId'])} '
      '| ${_fmt(row['currentFinalErrorVsEquakeKm'])} '
      '| ${_list(row['findings']).join(', ')} |',
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

Map<String, Object?> _comparisonRow(
  Map<String, Object?> referenceCase,
  Map<String, Map<String, Object?>> hypRows,
  Map<String, Map<String, Object?>> currentRows,
) {
  final caseId = _string(referenceCase['caseId']) ?? 'unknown_case';
  final equakeFinal = _map(referenceCase['equakeFinalReport']);
  final phaseCounts = _map(equakeFinal['phaseCounts']);
  final catalog = _map(referenceCase['catalogReference']);
  final replay = _map(referenceCase['localReplay']);
  final hypCaseIds = _stringList(replay['hypBenchmarkCaseIds']);
  final currentCaseIds = _stringList(replay['currentCaptureCaseIds']);
  final hypCaseId = hypCaseIds.cast<String?>().firstWhere(
    (id) => id != null && hypRows.containsKey(id),
    orElse: () => null,
  );
  final currentCaseId = currentCaseIds.cast<String?>().firstWhere(
    (id) => id != null && currentRows.containsKey(id),
    orElse: () => null,
  );
  final hypRow = hypCaseId == null ? null : hypRows[hypCaseId];
  final currentRow = currentCaseId == null ? null : currentRows[currentCaseId];
  final currentEstimate = _map(currentRow?['finalEstimate']);
  final currentDiagnostics = _map(currentEstimate['diagnostics']);
  final currentHyp = _map(currentDiagnostics['nied_gif_hyp_v1']);

  final eqLat = _number(equakeFinal['latitude']);
  final eqLng = _number(equakeFinal['longitude']);
  final catalogLat = _number(catalog['latitude']);
  final catalogLng = _number(catalog['longitude']);
  final eqCatalogError = _distanceOrNull(eqLat, eqLng, catalogLat, catalogLng);
  final jqLat = _number(hypRow?['jqScoringHypLatitude']);
  final jqLng = _number(hypRow?['jqScoringHypLongitude']);
  final jqEquakeError = _distanceOrNull(jqLat, jqLng, eqLat, eqLng);
  final currentLat = _number(currentEstimate['latitude']);
  final currentLng = _number(currentEstimate['longitude']);
  final currentEquakeError = _distanceOrNull(
    currentLat,
    currentLng,
    eqLat,
    eqLng,
  );
  final currentHypLat = _number(currentHyp['latitude']);
  final currentHypLng = _number(currentHyp['longitude']);
  final currentHypEquakeError = _distanceOrNull(
    currentHypLat,
    currentHypLng,
    eqLat,
    eqLng,
  );

  final eqP = _int(phaseCounts['p']);
  final eqS = _int(phaseCounts['s']);
  final eqOther = _int(phaseCounts['other']);
  final jqP = _int(hypRow?['jqScoringHypPhasePCount']);
  final jqS = _int(hypRow?['jqScoringHypPhaseSCount']);
  final jqOther = _int(hypRow?['jqScoringHypPhaseOtherCount']);
  final hypFindings = _stringList(hypRow?['findings']);
  final currentHypP = _int(currentHyp['phase_p_count']);
  final currentHypS = _int(currentHyp['phase_s_count']);
  final currentHypOther = _int(currentHyp['phase_other_count']);

  final findings = _rowFindings(
    hypMatched: hypRow != null,
    currentMatched: currentRow != null,
    eqP: eqP,
    eqS: eqS,
    jqP: jqP,
    jqS: jqS,
    jqSupported: hypRow?['jqScoringHypSupported'] == true,
    jqEquakeError: jqEquakeError,
    hypFindings: hypFindings,
    currentEquakeError: currentEquakeError,
    currentHypP: currentHypP,
    progression: _list(referenceCase['phaseProgression']).map(_map).toList(),
  );

  return {
    'caseId': caseId,
    'region': referenceCase['region'],
    'equakeFinal': equakeFinal,
    'catalogReference': catalog,
    'equakeErrorVsCatalogKm': eqCatalogError,
    'equakePhasePCount': eqP,
    'equakePhaseSCount': eqS,
    'equakePhaseOtherCount': eqOther,
    'hypBenchmarkMatched': hypRow != null,
    'hypBenchmarkCaseId': hypCaseId,
    'hypBenchmarkDecodedFrameCount': _int(hypRow?['decodedFrameCount']),
    'hypBenchmarkRequestedFrameCount': _int(hypRow?['requestedFrameCount']),
    'hypBenchmarkFindings': hypFindings,
    'jqScoringErrorVsEquakeKm': jqEquakeError,
    'jqScoringErrorVsCatalogKm': _distanceOrNull(
      jqLat,
      jqLng,
      catalogLat,
      catalogLng,
    ),
    'jqScoringLatitude': jqLat,
    'jqScoringLongitude': jqLng,
    'jqScoringDepthKm': _number(hypRow?['jqScoringHypDepthKm']),
    'jqScoringSupported': hypRow?['jqScoringHypSupported'],
    'jqScoringPhasePCount': jqP,
    'jqScoringPhaseSCount': jqS,
    'jqScoringPhaseOtherCount': jqOther,
    'jqScoringPhaseDeltaP': jqP == null ? null : jqP - (eqP ?? 0),
    'jqScoringPhaseDeltaS': jqS == null ? null : jqS - (eqS ?? 0),
    'jqScoringPhaseDeltaOther': jqOther == null
        ? null
        : jqOther - (eqOther ?? 0),
    'jqScoringPhaseBalancePenalty': _number(
      hypRow?['jqScoringHypPhaseBalancePenalty'],
    ),
    'currentCaptureMatched': currentRow != null,
    'currentCaptureCaseId': currentCaseId,
    'currentFinalLatitude': currentLat,
    'currentFinalLongitude': currentLng,
    'currentFinalErrorVsEquakeKm': currentEquakeError,
    'currentFinalMethod': currentEstimate['method'],
    'currentFinalSupportingStationCount':
        currentEstimate['supportingStationCount'],
    'currentHypErrorVsEquakeKm': currentHypEquakeError,
    'currentHypPhasePCount': currentHypP,
    'currentHypPhaseSCount': currentHypS,
    'currentHypPhaseOtherCount': currentHypOther,
    'findings': findings,
  };
}

List<String> _rowFindings({
  required bool hypMatched,
  required bool currentMatched,
  required int? eqP,
  required int? eqS,
  required int? jqP,
  required int? jqS,
  required bool jqSupported,
  required double? jqEquakeError,
  required List<String> hypFindings,
  required double? currentEquakeError,
  required int? currentHypP,
  required List<Map<String, Object?>> progression,
}) {
  final findings = <String>[];
  if (hypMatched) {
    findings.add('matched_hyp_benchmark');
  } else {
    findings.add('missing_hyp_benchmark');
  }
  if (currentMatched) findings.add('matched_current_capture');
  if ((jqEquakeError ?? 999) <= 10) {
    findings.add('jq_scoring_near_equake_10km');
  } else if ((jqEquakeError ?? 999) <= 20) {
    findings.add('jq_scoring_near_equake_20km');
  }
  if ((jqEquakeError ?? 0) > 40) {
    findings.add('jq_scoring_far_from_equake_40km');
  }
  if (jqSupported && (jqEquakeError ?? 0) > 40) {
    findings.add('jq_scoring_supported_far_from_equake_40km');
  }
  if (hypFindings.contains('low_decoded_frame_coverage')) {
    findings.add('hyp_benchmark_low_decoded_frame_coverage');
  }
  if ((jqP ?? -1) == 0 && (eqP ?? 0) >= 5) {
    findings.add('jq_scoring_zero_p_against_equake_p_support');
  }
  if ((eqS ?? 0) > (eqP ?? 0)) findings.add('equake_s_rich_final');
  if ((currentEquakeError ?? 0) > 40) {
    findings.add('current_capture_far_from_equake_40km');
  }
  if ((currentHypP ?? -1) == 0 && (eqP ?? 0) >= 5) {
    findings.add('current_hyp_zero_p_against_equake_p_support');
  }
  if (_startsPOnlyThenGainsS(progression)) {
    findings.add('equake_progression_p_only_to_mixed');
  }
  return findings;
}

bool _startsPOnlyThenGainsS(List<Map<String, Object?>> progression) {
  if (progression.length < 3) return false;
  final early = progression.take(math.min(3, progression.length));
  final earlyS = early.fold<int>(0, (sum, row) => sum + (_int(row['s']) ?? 0));
  final finalS = _int(progression.last['s']) ?? 0;
  return earlyS == 0 && finalS > 0;
}

List<String> _globalFindings(List<Map<String, Object?>> rows) {
  final findings = <String>[];
  if (rows.any((row) => row['hypBenchmarkMatched'] != true)) {
    findings.add('some_equake_references_need_hyp_benchmark_replay');
  }
  if (rows.any(
    (row) => _list(
      row['findings'],
    ).contains('jq_scoring_zero_p_against_equake_p_support'),
  )) {
    findings.add('phase_origin_assignment_needs_p_support_recovery');
  }
  if (rows.any(
    (row) =>
        _list(row['findings']).contains('current_capture_far_from_equake_40km'),
  )) {
    findings.add('current_capture_production_estimate_has_large_reference_gap');
  }
  if (rows.any(
    (row) => _list(
      row['findings'],
    ).contains('jq_scoring_supported_far_from_equake_40km'),
  )) {
    findings.add('jq_scoring_support_gate_allows_large_reference_gap');
  }
  if (rows.any(
    (row) => _list(
      row['findings'],
    ).contains('hyp_benchmark_low_decoded_frame_coverage'),
  )) {
    findings.add('some_hyp_benchmarks_have_low_decoded_frame_coverage');
  }
  findings.add('reference_only_do_not_promote_to_truth');
  findings.add('diagnostic_only_do_not_promote_to_production_coordinates');
  return findings;
}

Map<String, Map<String, Object?>> _indexRows(List<Object?> rows) {
  final indexed = <String, Map<String, Object?>>{};
  for (final raw in rows) {
    final row = _map(raw);
    final id = _string(row['caseId']) ?? _string(row['id']);
    if (id != null) indexed[id] = row;
  }
  return indexed;
}

Map<String, Object?> _readJsonMap(File file) {
  if (!file.existsSync()) return {};
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is Map) return decoded.cast<String, Object?>();
  return {};
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};

List<Object?> _list(Object? value) => value is List ? value : const [];

List<String> _stringList(Object? value) => [
  for (final item in _list(value))
    if (item is String) item,
];

String? _string(Object? value) => value is String ? value : null;

num? _num(Object? value) => value is num ? value : null;

double? _number(Object? value) => _num(value)?.toDouble();

int? _int(Object? value) => _num(value)?.toInt();

double? _distanceOrNull(
  double? aLat,
  double? aLng,
  double? bLat,
  double? bLng,
) {
  if (aLat == null || aLng == null || bLat == null || bLng == null) {
    return null;
  }
  return _distanceKm(aLat, aLng, bLat, bLng);
}

double _distanceKm(double aLat, double aLng, double bLat, double bLng) {
  const radiusKm = 6371.0;
  final dLat = _rad(bLat - aLat);
  final dLng = _rad(bLng - aLng);
  final lat1 = _rad(aLat);
  final lat2 = _rad(bLat);
  final h =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * radiusKm * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

double _rad(double deg) => deg * math.pi / 180;

String _fmt(Object? value) => value is num ? value.toStringAsFixed(1) : '--';

String _dash(Object? value) {
  final text = value?.toString();
  return text == null || text.isEmpty ? '--' : '`$text`';
}

String _phase(Map<String, Object?> row, String prefix) {
  final p = row['${prefix}PhasePCount'];
  final s = row['${prefix}PhaseSCount'];
  final o = row['${prefix}PhaseOtherCount'];
  if (p == null && s == null && o == null) return '--';
  return '$p/$s/$o';
}

String _fmtLocation(Object? lat, Object? lng, Object? depthKm) {
  final latText = lat is num ? lat.toStringAsFixed(2) : '--';
  final lngText = lng is num ? lng.toStringAsFixed(2) : '--';
  final depthText = depthKm is num ? depthKm.toStringAsFixed(0) : '--';
  return '$latText, $lngText / ${depthText}km';
}
