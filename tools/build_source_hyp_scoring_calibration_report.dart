import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/source_estimation/source_estimator.dart';

import '../test/support/source_estimation_benchmark.dart';

const _schemaVersion = 'source_hyp_scoring_calibration_report_v1';
const _defaultFixtureDirectory = 'test/fixtures/source_estimation';
const _defaultOutput =
    '.dart_tool/source_hyp_scoring_calibration_report/report.json';
const _defaultMarkdown =
    'docs/baselines/source_hyp_scoring_calibration_report.generated.md';
const _hybridMethod = SourceEstimationBenchmarkRunner.hybridMethod;

void main(List<String> args) async {
  final fixtureDirectory =
      _argument(args, '--fixture-directory') ?? _defaultFixtureDirectory;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = await buildSourceHypScoringCalibrationReportJson(
    fixtureDirectory: fixtureDirectory,
  );
  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(sourceHypScoringCalibrationMarkdown(report));

  stdout.writeln('wrote HYP scoring calibration report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');
  if (report['status'] != 'pass') exitCode = 1;
}

Future<Map<String, Object?>> buildSourceHypScoringCalibrationReportJson({
  String fixtureDirectory = _defaultFixtureDirectory,
  List<HypScoringVariant> variants = _defaultVariants,
}) async {
  final fixtureDir = Directory(fixtureDirectory);
  if (!fixtureDir.existsSync()) {
    return {
      'schemaVersion': _schemaVersion,
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'status': 'fail',
      'errors': ['fixture_directory_missing:$fixtureDirectory'],
      'skippedCases': const [],
      'variants': const [],
      'findings': const ['missing_fixture_directory'],
    };
  }

  final manifestFiles =
      fixtureDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .where(
            (file) => _includedManifestNames.contains(_basename(file.path)),
          )
          .toList(growable: false)
        ..sort((left, right) => left.path.compareTo(right.path));

  final skipped = <Map<String, Object?>>[];
  final variantReports = <Map<String, Object?>>[];
  for (final variant in variants) {
    final rows = <Map<String, Object?>>[];
    for (final manifest in manifestFiles) {
      SourceEstimationReplayCase replayCase;
      try {
        replayCase = SourceEstimationReplayCase.fromManifest(
          manifest,
          workspaceRoot: Directory.current,
        );
      } catch (error) {
        skipped.add({
          'variant': variant.id,
          'manifest': manifest.path,
          'reason': 'manifest_parse_failed',
          'error': error.toString(),
        });
        continue;
      }
      if (replayCase.truth == null) {
        skipped.add({
          'variant': variant.id,
          'caseId': replayCase.caseId,
          'manifest': manifest.path,
          'reason': 'missing_truth',
        });
        continue;
      }
      if (!replayCase.captureDirectory.existsSync()) {
        skipped.add({
          'variant': variant.id,
          'caseId': replayCase.caseId,
          'manifest': manifest.path,
          'reason': 'capture_directory_missing',
          'captureDirectory': replayCase.captureDirectory.path,
        });
        continue;
      }
      try {
        final report = await SourceEstimationBenchmarkRunner(
          replayCase,
          hybridEstimator: variant.estimator,
        ).run();
        final row = _variantCaseRow(variant, report);
        if (row != null) rows.add(row);
      } catch (error) {
        skipped.add({
          'variant': variant.id,
          'caseId': replayCase.caseId,
          'manifest': manifest.path,
          'reason': 'runner_failed',
          'error': error.toString(),
        });
      }
    }
    variantReports.add({
      'variantId': variant.id,
      'description': variant.description,
      'config': variant.configJson,
      'summary': _summary(rows),
      'rows': rows,
    });
  }

  return _withFindings({
    'schemaVersion': _schemaVersion,
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': variantReports.isEmpty ? 'fail' : 'pass',
    'policy': const {
      'diagnosticOnly': true,
      'productionCoordinateSwitchAllowed': false,
      'referenceAlgorithmInput': 'nied_kmoni_gif_reverse_decoded',
      'calibrates': 'hyp_candidate_search_scoring_not_support_gate',
      'historicalGifRedownload': false,
    },
    'inputs': {
      'fixtureDirectory': fixtureDirectory,
      'includedManifests': _includedManifestNames,
      'method': _hybridMethod,
    },
    'skippedCases': skipped,
    'variants': variantReports,
  });
}

String sourceHypScoringCalibrationMarkdown(Map<String, Object?> report) {
  final variants = _list(report['variants']).map(_map).toList(growable: false);
  final b = StringBuffer()
    ..writeln('# HYP scoring calibration report')
    ..writeln()
    ..writeln('- Schema: `${report['schemaVersion']}`')
    ..writeln('- Status: `${report['status']}`')
    ..writeln(
      '- Diagnostic only: `${_map(report['policy'])['diagnosticOnly']}`',
    )
    ..writeln(
      '- Historical GIF redownload: `${_map(report['policy'])['historicalGifRedownload']}`',
    )
    ..writeln()
    ..writeln(
      '| Variant | Cases | Supported | Depth | Improved | Regressed | Median HYP | Median supported HYP | Median Δ | P-only final rows |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (final variant in variants) {
    final summary = _map(variant['summary']);
    b.writeln(
      '| `${variant['variantId']}` '
      '| ${summary['caseCount']} '
      '| ${summary['supportedCount']} '
      '| ${summary['depthSupportedCount']} '
      '| ${summary['improvedCount']} '
      '| ${summary['regressedCount']} '
      '| ${_fmt(summary['medianHypErrorKm'])} '
      '| ${_fmt(summary['medianSupportedHypErrorKm'])} '
      '| ${_fmt(summary['medianDeltaKm'])} '
      '| ${summary['pOnlyFinalRowCount']} |',
    );
  }
  b
    ..writeln()
    ..writeln('## Variant rows')
    ..writeln();
  for (final variant in variants) {
    b
      ..writeln('### `${variant['variantId']}`')
      ..writeln()
      ..writeln(
        '| Case | Hybrid final | HYP final | Δ | Supported | Depth | P/S/O | Residual | Pair | Unarrived | HYP depth | |',
      )
      ..writeln('|---|---:|---:|---:|---|---|---|---:|---:|---:|---:|');
    for (final row in _list(variant['rows']).map(_map)) {
      b.writeln(
        '| `${row['caseId']}` '
        '| ${_fmt(row['hybridFinalErrorKm'])} '
        '| ${_fmt(row['hypFinalErrorKm'])} '
        '| ${_fmt(row['hypMinusHybridFinalErrorKm'])} '
        '| ${row['hypSupported']} '
        '| ${row['hypDepthSupported']} '
        '| ${row['hypPhasePCount']}/${row['hypPhaseSCount']}/${row['hypPhaseOtherCount']} '
        '| ${_fmt(row['hypPhaseMeanResidualSeconds'])} '
        '| ${_fmt(row['hypPairMeanResidualSeconds'])} '
        '| ${_fmt(row['hypUnarrivedPenalty'])} '
        '| ${_fmt(row['hypDepthKm'], digits: 0)} |',
      );
    }
    b.writeln();
  }
  b
    ..writeln('## Findings')
    ..writeln();
  for (final finding in _list(report['findings'])) {
    b.writeln('- `$finding`');
  }
  return b.toString();
}

Map<String, Object?> _withFindings(Map<String, Object?> report) {
  final variants = _list(report['variants']).map(_map).toList(growable: false);
  final findings = <String>[];
  final baseline = variants
      .where((variant) => variant['variantId'] == 'baseline')
      .cast<Map<String, Object?>>()
      .firstOrNull;
  if (baseline == null) {
    findings.add('baseline_variant_missing');
  } else {
    final baselineSummary = _map(baseline['summary']);
    final best = variants
        .where((variant) => variant['variantId'] != 'baseline')
        .where((variant) {
          final summary = _map(variant['summary']);
          return (summary['regressedCount'] as int? ?? 0) <=
              (baselineSummary['regressedCount'] as int? ?? 0);
        })
        .toList(growable: false);
    best.sort((a, b) {
      final medianA =
          _number(_map(a['summary'])['medianHypErrorKm']) ?? double.infinity;
      final medianB =
          _number(_map(b['summary'])['medianHypErrorKm']) ?? double.infinity;
      return medianA.compareTo(medianB);
    });
    if (best.isNotEmpty) {
      findings.add('best_non_regressing_variant_${best.first['variantId']}');
    }
    findings.add(
      'baseline_supported_count_${baselineSummary['supportedCount']}',
    );
  }
  findings.add('candidate_search_calibration_only');
  findings.add('keep_hyp_diagnostic_until_variant_beats_hybrid_reliably');
  return {...report, 'findings': findings};
}

Map<String, Object?>? _variantCaseRow(
  HypScoringVariant variant,
  SourceEstimationBenchmarkReport report,
) {
  final truth = report.replayCase.truth;
  if (truth == null) return null;
  final frames = report.frames
      .where((frame) {
        return frame.methods[_hybridMethod]?.estimate != null;
      })
      .toList(growable: false);
  if (frames.isEmpty) return null;
  final finalFrame = frames.last;
  final finalMethod = finalFrame.methods[_hybridMethod]!;
  final estimate = finalMethod.estimate!;
  final hyp = _mapOrNull(estimate.diagnostics['nied_gif_hyp_v1']);
  final hypLat = _number(hyp?['latitude']);
  final hypLng = _number(hyp?['longitude']);
  final hypError = hypLat == null || hypLng == null
      ? null
      : _haversineKm(
          hypLat,
          hypLng,
          truth.epicenter.latitude,
          truth.epicenter.longitude,
        );
  final delta = hypError == null || finalMethod.errorKm == null
      ? null
      : hypError - finalMethod.errorKm!;
  return {
    'variantId': variant.id,
    'caseId': report.replayCase.caseId,
    'requestedFrameCount': report.requestedFrameCount,
    'decodedFrameCount': report.decodedFrameCount,
    'hybridFinalErrorKm': finalMethod.errorKm,
    'hybridFinalLatitude': estimate.latitude,
    'hybridFinalLongitude': estimate.longitude,
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
    'hypUnarrivedPenalty': _number(hyp?['unarrived_penalty']),
    'hypUnarrivedPenaltyCount': _integer(hyp?['unarrived_penalty_count']) ?? 0,
  };
}

Map<String, Object?> _summary(List<Map<String, Object?>> rows) {
  final supported = rows
      .where((row) => row['hypSupported'] == true)
      .toList(growable: false);
  final depthSupported = rows
      .where((row) => row['hypDepthSupported'] == true)
      .toList(growable: false);
  final improved = rows.where((row) => (_delta(row) ?? 0) < 0).toList();
  final regressed = rows.where((row) => (_delta(row) ?? 0) > 10).toList();
  return {
    'caseCount': rows.length,
    'supportedCount': supported.length,
    'depthSupportedCount': depthSupported.length,
    'improvedCount': improved.length,
    'regressedCount': regressed.length,
    'pOnlyFinalRowCount': rows
        .where((row) => (_integer(row['hypPhaseSCount']) ?? 0) == 0)
        .length,
    'medianHypErrorKm': _median([
      for (final row in rows)
        if (_number(row['hypFinalErrorKm']) != null)
          _number(row['hypFinalErrorKm'])!,
    ]),
    'medianSupportedHypErrorKm': _median([
      for (final row in supported)
        if (_number(row['hypFinalErrorKm']) != null)
          _number(row['hypFinalErrorKm'])!,
    ]),
    'medianDeltaKm': _median([
      for (final row in rows)
        if (_delta(row) != null) _delta(row)!,
    ]),
  };
}

double? _delta(Map<String, Object?> row) {
  final hyp = _number(row['hypFinalErrorKm']);
  final hybrid = _number(row['hybridFinalErrorKm']);
  if (hyp == null || hybrid == null) return null;
  return hyp - hybrid;
}

class HypScoringVariant {
  final String id;
  final String description;
  final double unarrivedPenaltyWeight;
  final double depthRegularizationWeight;
  final double sSupportBonusPerStation;
  final double maxSSupportBonus;

  const HypScoringVariant({
    required this.id,
    required this.description,
    required this.unarrivedPenaltyWeight,
    required this.depthRegularizationWeight,
    required this.sSupportBonusPerStation,
    required this.maxSSupportBonus,
  });

  NiedGifHybridSourceEstimator get estimator => NiedGifHybridSourceEstimator(
    fallback: const WeightedCentroidSourceEstimator(),
    emitOneSidedBoundaryCentroidGuardCandidate: true,
    oneSidedBoundaryCentroidGuardMinUncertaintyP90Km: 180.0,
    oneSidedBoundaryCentroidGuardMinNearestStationDistanceKm: 80.0,
    hypUnarrivedPenaltyScoreWeight: unarrivedPenaltyWeight,
    hypDepthRegularizationWeight: depthRegularizationWeight,
    hypSSupportBonusPerStation: sSupportBonusPerStation,
    hypMaxSSupportBonus: maxSSupportBonus,
  );

  Map<String, Object?> get configJson => {
    'unarrivedPenaltyWeight': unarrivedPenaltyWeight,
    'depthRegularizationWeight': depthRegularizationWeight,
    'sSupportBonusPerStation': sSupportBonusPerStation,
    'maxSSupportBonus': maxSSupportBonus,
  };
}

const _defaultVariants = [
  HypScoringVariant(
    id: 'baseline',
    description: 'Current HYP diagnostic scoring.',
    unarrivedPenaltyWeight: 1.0,
    depthRegularizationWeight: 0.003,
    sSupportBonusPerStation: 0.2,
    maxSSupportBonus: 1.2,
  ),
  HypScoringVariant(
    id: 'unarrived_x2',
    description: 'Push candidates away from inactive nearby station gaps.',
    unarrivedPenaltyWeight: 2.0,
    depthRegularizationWeight: 0.003,
    sSupportBonusPerStation: 0.2,
    maxSSupportBonus: 1.2,
  ),
  HypScoringVariant(
    id: 'unarrived_x4',
    description: 'Strongly penalize candidates that should have lit stations.',
    unarrivedPenaltyWeight: 4.0,
    depthRegularizationWeight: 0.003,
    sSupportBonusPerStation: 0.2,
    maxSSupportBonus: 1.2,
  ),
  HypScoringVariant(
    id: 'shallow_bias',
    description: 'Increase depth regularization to reduce max-depth drift.',
    unarrivedPenaltyWeight: 1.0,
    depthRegularizationWeight: 0.012,
    sSupportBonusPerStation: 0.2,
    maxSSupportBonus: 1.2,
  ),
];

const _includedManifestNames = [
  'iwate_east_offshore_m30_20260622_hinet.json',
  'kushiro_offshore_m30_20260622_jma.json',
  'tomakomai_south_offshore_m35_20260622_hinet.json',
  'wakayama_south_m25_20260622_hinet.json',
];

String? _argument(List<String> args, String name) {
  for (var index = 0; index < args.length; index++) {
    final arg = args[index];
    if (arg == name && index + 1 < args.length) return args[index + 1];
    if (arg.startsWith('$name=')) return arg.substring(name.length + 1);
  }
  return null;
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash < 0 ? normalized : normalized.substring(slash + 1);
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};

Map<String, Object?>? _mapOrNull(Object? value) =>
    value is Map ? value.cast<String, Object?>() : null;

List<Object?> _list(Object? value) =>
    value is List ? value.cast<Object?>() : const <Object?>[];

double? _number(Object? value) => value is num ? value.toDouble() : null;

int? _integer(Object? value) => value is num ? value.toInt() : null;

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
