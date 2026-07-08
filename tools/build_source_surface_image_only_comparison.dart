import 'dart:convert';
import 'dart:io';

import '../test/support/source_estimation_benchmark.dart';

const _defaultFixtureDirectory = 'test/fixtures/source_estimation';
const _defaultOutputPath =
    '.dart_tool/source_surface_image_only_comparison/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_surface_image_only_comparison.generated.md';
const _hybridMethod = SourceEstimationBenchmarkRunner.hybridMethod;

void main(List<String> args) async {
  final fixtureDirectory =
      _argument(args, '--fixture-directory') ?? _defaultFixtureDirectory;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = await buildSourceSurfaceImageOnlyComparisonJson(
    fixtureDirectory: fixtureDirectory,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(sourceSurfaceImageOnlyComparisonMarkdown(report));

  stdout.writeln('wrote source surface-image-only comparison');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Future<Map<String, Object?>> buildSourceSurfaceImageOnlyComparisonJson({
  String fixtureDirectory = _defaultFixtureDirectory,
}) async {
  final errors = <String>[];
  final skipped = <Map<String, Object?>>[];
  final fixtureDir = Directory(fixtureDirectory);
  if (!fixtureDir.existsSync()) {
    return {
      'schemaVersion': 'source_surface_image_only_comparison_v1',
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'status': 'fail',
      'errors': ['fixture_directory_missing:$fixtureDirectory'],
      'skippedCases': const [],
      'cases': const [],
    };
  }

  final manifestFiles =
      fixtureDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .where(
            (file) => !_excludedManifestNames.contains(_basename(file.path)),
          )
          .toList(growable: false)
        ..sort((left, right) => left.path.compareTo(right.path));

  final cases = <Map<String, Object?>>[];
  for (final manifest in manifestFiles) {
    SourceEstimationReplayCase replayCase;
    try {
      replayCase = SourceEstimationReplayCase.fromManifest(
        manifest,
        workspaceRoot: Directory.current,
      );
    } catch (error) {
      skipped.add({
        'manifest': manifest.path,
        'reason': 'manifest_parse_failed',
        'error': error.toString(),
      });
      continue;
    }
    if (!replayCase.captureDirectory.existsSync()) {
      skipped.add({
        'caseId': replayCase.caseId,
        'manifest': manifest.path,
        'reason': 'capture_directory_missing',
        'captureDirectory': replayCase.captureDirectory.path,
      });
      continue;
    }
    try {
      final dual = await SourceEstimationBenchmarkRunner(
        replayCase,
        inputMode: SourceEstimationBenchmarkInputMode.dualLayer,
      ).run();
      final surfaceOnly = await SourceEstimationBenchmarkRunner(
        replayCase,
        inputMode: SourceEstimationBenchmarkInputMode.surfaceImageOnly,
      ).run();
      cases.add(_compareCase(dual, surfaceOnly));
    } catch (error) {
      skipped.add({
        'caseId': replayCase.caseId,
        'manifest': manifest.path,
        'reason': 'runner_failed',
        'error': error.toString(),
      });
    }
  }

  final summary = _summary(cases);
  return {
    'schemaVersion': 'source_surface_image_only_comparison_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty && cases.isNotEmpty ? 'pass' : 'fail',
    'policy': const {
      'diagnosticOnly': true,
      'productionBehaviorChanged': true,
      'surfaceImageOnlyMeaning':
          'Use jma_s surface GIF pixels for every station, including KiK-net stations; do not feed jma_b borehole GIF pixels.',
      'currentDefaultInput':
          'The production default now also reads jma_s for every scan-mapped station.',
    },
    'inputs': {
      'fixtureDirectory': fixtureDirectory,
      'dualLayerMode': SourceEstimationBenchmarkInputMode.dualLayer.id,
      'surfaceImageOnlyMode':
          SourceEstimationBenchmarkInputMode.surfaceImageOnly.id,
      'method': _hybridMethod,
    },
    'summary': summary,
    'errors': errors,
    'skippedCases': skipped,
    'cases': cases,
  };
}

Map<String, Object?> _compareCase(
  SourceEstimationBenchmarkReport dual,
  SourceEstimationBenchmarkReport surfaceOnly,
) {
  final dualSummary = dual.summaries[_hybridMethod]!;
  final surfaceSummary = surfaceOnly.summaries[_hybridMethod]!;
  return {
    'caseId': dual.replayCase.caseId,
    'caseType': dual.replayCase.caseType.name,
    'truthSource': dual.replayCase.truth?.source,
    'plannedUse': dual.replayCase.classification['plannedUse'],
    'dualLayer': _methodSummary(dualSummary),
    'surfaceImageOnly': _methodSummary(surfaceSummary),
    'delta': {
      'estimateCount': surfaceSummary.estimateCount - dualSummary.estimateCount,
      'medianErrorKm': _delta(
        surfaceSummary.medianErrorKm,
        dualSummary.medianErrorKm,
      ),
      'p90ErrorKm': _delta(surfaceSummary.p90ErrorKm, dualSummary.p90ErrorKm),
      'firstEstimateDelaySeconds': _delta(
        surfaceSummary.firstEstimateDelaySeconds,
        dualSummary.firstEstimateDelaySeconds,
      ),
      'errorAt5SecondsKm': _delta(
        surfaceSummary.errorAtSeconds['5'],
        dualSummary.errorAtSeconds['5'],
      ),
      'errorAt10SecondsKm': _delta(
        surfaceSummary.errorAtSeconds['10'],
        dualSummary.errorAtSeconds['10'],
      ),
      'errorAt20SecondsKm': _delta(
        surfaceSummary.errorAtSeconds['20'],
        dualSummary.errorAtSeconds['20'],
      ),
      'p90JumpKm': _delta(surfaceSummary.p90JumpKm, dualSummary.p90JumpKm),
    },
  };
}

Map<String, Object?> _methodSummary(SourceEstimationMethodSummary summary) => {
  'estimateCount': summary.estimateCount,
  'firstEstimateDelaySeconds': summary.firstEstimateDelaySeconds,
  'medianErrorKm': summary.medianErrorKm,
  'p90ErrorKm': summary.p90ErrorKm,
  'errorAtSeconds': summary.errorAtSeconds,
  'medianJumpKm': summary.medianJumpKm,
  'p90JumpKm': summary.p90JumpKm,
  'falseEstimateFrameCount': summary.falseEstimateFrameCount,
};

Map<String, Object?> _summary(List<Map<String, Object?>> cases) {
  final eventCases = cases
      .where(
        (entry) =>
            entry['caseType'] == SourceEstimationReplayCaseType.event.name,
      )
      .toList(growable: false);
  final medianDeltas = eventCases
      .map((entry) => _number(_map(entry['delta'])['medianErrorKm']))
      .whereType<double>()
      .toList(growable: false);
  final p90Deltas = eventCases
      .map((entry) => _number(_map(entry['delta'])['p90ErrorKm']))
      .whereType<double>()
      .toList(growable: false);
  final betterMedian = medianDeltas.where((value) => value < 0).length;
  final worseMedian = medianDeltas.where((value) => value > 0).length;
  return {
    'caseCount': cases.length,
    'eventCaseCount': eventCases.length,
    'surfaceOnlyMedianDeltaMedianKm': _percentile(medianDeltas, 0.5),
    'surfaceOnlyP90DeltaMedianKm': _percentile(p90Deltas, 0.5),
    'surfaceOnlyBetterMedianErrorCaseCount': betterMedian,
    'surfaceOnlyWorseMedianErrorCaseCount': worseMedian,
    'surfaceOnlyEqualMedianErrorCaseCount':
        medianDeltas.length - betterMedian - worseMedian,
    'surfaceOnlyNoEstimateCaseCount': eventCases
        .where(
          (entry) =>
              _intValue(_map(entry['surfaceImageOnly'])['estimateCount']) == 0,
        )
        .length,
    'dualLayerNoEstimateCaseCount': eventCases
        .where(
          (entry) => _intValue(_map(entry['dualLayer'])['estimateCount']) == 0,
        )
        .length,
  };
}

String sourceSurfaceImageOnlyComparisonMarkdown(Map<String, Object?> report) {
  final summary = _map(report['summary']);
  final buffer = StringBuffer()
    ..writeln('# Source Surface-Image-Only Comparison')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Method: `$_hybridMethod`')
    ..writeln(
      '- Surface-only meaning: use `jma_s` pixels for every station, including KiK-net; do not feed `jma_b`.',
    )
    ..writeln('- Cases run: `${summary['caseCount']}`')
    ..writeln('- Event cases: `${summary['eventCaseCount']}`')
    ..writeln(
      '- Median of median-error delta: `${_fmt(summary['surfaceOnlyMedianDeltaMedianKm'])} km`',
    )
    ..writeln(
      '- Median of P90-error delta: `${_fmt(summary['surfaceOnlyP90DeltaMedianKm'])} km`',
    )
    ..writeln(
      '- Better / equal / worse median-error cases: '
      '`${summary['surfaceOnlyBetterMedianErrorCaseCount']} / '
      '${summary['surfaceOnlyEqualMedianErrorCaseCount']} / '
      '${summary['surfaceOnlyWorseMedianErrorCaseCount']}`',
    )
    ..writeln()
    ..writeln('## Cases')
    ..writeln()
    ..writeln(
      '| Case | Type | Current-default median/P90 | Surface-check median/P90 | Delta median/P90 | Current frames | Surface frames |',
    )
    ..writeln('| --- | --- | ---: | ---: | ---: | ---: | ---: |');
  for (final rawCase in _list(report['cases'])) {
    final entry = _map(rawCase);
    final dual = _map(entry['dualLayer']);
    final surface = _map(entry['surfaceImageOnly']);
    final delta = _map(entry['delta']);
    buffer.writeln(
      '| `${entry['caseId']}` | `${entry['caseType']}` | '
      '${_fmt(dual['medianErrorKm'])}/${_fmt(dual['p90ErrorKm'])} | '
      '${_fmt(surface['medianErrorKm'])}/${_fmt(surface['p90ErrorKm'])} | '
      '${_fmt(delta['medianErrorKm'])}/${_fmt(delta['p90ErrorKm'])} | '
      '${dual['estimateCount']} | ${surface['estimateCount']} |',
    );
  }
  final skipped = _list(report['skippedCases']);
  if (skipped.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Skipped')
      ..writeln()
      ..writeln('| Case/manifest | Reason |')
      ..writeln('| --- | --- |');
    for (final rawSkipped in skipped) {
      final entry = _map(rawSkipped);
      buffer.writeln(
        '| `${entry['caseId'] ?? entry['manifest']}` | `${entry['reason']}` |',
      );
    }
  }
  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- This report is a regression check for the current `jma_s` default input.',
    )
    ..writeln(
      '- The historical `dualLayer` input mode name is retained in JSON for compatibility, but current processing reads `jma_s` as the default shindo input.',
    )
    ..writeln();
  return buffer.toString();
}

String? _argument(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == name && i + 1 < args.length) return args[i + 1];
    if (arg.startsWith('$name=')) return arg.substring(name.length + 1);
  }
  return null;
}

const _excludedManifestNames = {
  'baseline_suite.json',
  'dataset_splits.json',
  'detection_suite.json',
  'knet_waveform_event_candidates.json',
};

String _basename(String path) => path.split(RegExp(r'[\\/]')).last;

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

List<Object?> _list(Object? value) => value is List ? value : const [];

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double? _delta(double? current, double? baseline) {
  if (current == null || baseline == null) return null;
  return current - baseline;
}

double? _percentile(List<double> values, double q) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final index = ((sorted.length - 1) * q).round();
  return sorted[index.clamp(0, sorted.length - 1)];
}

String _fmt(Object? value) {
  final number = _number(value);
  if (number == null) return '-';
  return number.toStringAsFixed(1);
}
