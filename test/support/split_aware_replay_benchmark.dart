import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/replay/replay_dataset.dart';

import 'source_estimation_benchmark.dart';

class SplitAwareBenchmarkSplitReport {
  final String splitName;
  final SourceEstimationBatchReport sourceReport;
  final EventDetectionBatchReport detectionReport;

  const SplitAwareBenchmarkSplitReport({
    required this.splitName,
    required this.sourceReport,
    required this.detectionReport,
  });

  int get caseCount => sourceReport.cases.length;

  Map<String, Object?> toJson() => {
    'splitName': splitName,
    'caseCount': caseCount,
    'caseIds': sourceReport.cases
        .map((report) => report.replayCase.caseId)
        .toList(growable: false),
    'source': sourceReport.toJson(),
    'detection': detectionReport.toJson(),
  };
}

class SplitAwareBenchmarkReport {
  final String datasetId;
  final String frozenAt;
  final String splitPolicy;
  final List<SplitAwareBenchmarkSplitReport> splits;

  const SplitAwareBenchmarkReport({
    required this.datasetId,
    required this.frozenAt,
    required this.splitPolicy,
    required this.splits,
  });

  Map<String, Object?> toJson() => {
    'reportSchemaVersion': 1,
    'datasetId': datasetId,
    'frozenAt': frozenAt,
    'splitPolicy': splitPolicy,
    'warning':
        'Current sample count is too small for algorithm superiority claims.',
    'splits': {for (final split in splits) split.splitName: split.toJson()},
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Split-aware replay evaluation: `$datasetId`')
      ..writeln()
      ..writeln(
        '> Current sample count is too small for algorithm superiority claims.',
      )
      ..writeln()
      ..writeln('Frozen at: `$frozenAt`')
      ..writeln()
      ..writeln('Split policy: $splitPolicy')
      ..writeln()
      ..writeln('## Split Summary')
      ..writeln()
      ..writeln(
        '| Split | Cases | Source methods | Detection denominator | Shadow confirmed | Noise frames |',
      )
      ..writeln('|---|---:|---|---:|---:|---:|');

    for (final split in splits) {
      final sourceMethods = split.sourceReport.summaries.keys.join(', ');
      buffer.writeln(
        '| `${_markdownCell(split.splitName)}` '
        '| ${split.caseCount} '
        '| `${_markdownCell(sourceMethods)}` '
        '| ${split.detectionReport.shadowSummary.eventCaseCount} '
        '| ${split.detectionReport.shadowSummary.eventCasesConfirmed}/${split.detectionReport.shadowSummary.eventCaseCount} '
        '| ${split.detectionReport.shadowSummary.noiseFrameCount} |',
      );
    }

    for (final split in splits) {
      buffer
        ..writeln()
        ..writeln('## ${split.splitName}')
        ..writeln()
        ..writeln(
          'Cases: ${split.sourceReport.cases.map((report) => '`'
              '${_markdownCell(report.replayCase.caseId)}`').join(', ')}',
        )
        ..writeln()
        ..writeln('### Source')
        ..writeln()
        ..writeln(
          '| Method | Event coverage | Missed events | Noise false frames | Median error | P90 error |',
        )
        ..writeln('|---|---:|---:|---:|---:|---:|');
      for (final summary in split.sourceReport.summaries.values) {
        buffer.writeln(
          '| `${_markdownCell(summary.methodId)}` '
          '| ${summary.eventCasesWithEstimates}/${summary.eventCaseCount} '
          '| ${summary.missedEventCaseCount} '
          '| ${summary.noiseEstimateFrameCount}/${summary.noiseFrameCount} '
          '| ${_formatKilometers(summary.medianEventErrorKm)} '
          '| ${_formatKilometers(summary.p90EventErrorKm)} |',
        );
      }

      buffer
        ..writeln()
        ..writeln('### Detection')
        ..writeln()
        ..writeln(
          '| Detector | Candidate coverage | Confirmed coverage | Noise candidate frames | Noise confirmed frames | Median candidate delay | Median confirmation delay |',
        )
        ..writeln('|---|---:|---:|---:|---:|---:|---:|');
      for (final summary in [
        split.detectionReport.summary,
        split.detectionReport.shadowSummary,
        split.detectionReport.temporalBridgeSummary,
      ]) {
        buffer.writeln(
          '| `${_markdownCell(summary.detectorId)}` '
          '| ${summary.eventCasesWithCandidate}/${summary.eventCaseCount} '
          '| ${summary.eventCasesConfirmed}/${summary.eventCaseCount} '
          '| ${summary.noiseCandidateFrameCount}/${summary.noiseFrameCount} '
          '| ${summary.noiseConfirmedFrameCount}/${summary.noiseFrameCount} '
          '| ${_formatSeconds(summary.medianCandidateDelaySeconds)} '
          '| ${_formatSeconds(summary.medianConfirmationDelaySeconds)} |',
        );
      }
    }

    return buffer.toString();
  }

  void writeJson(File output) {
    output.parent.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    output.writeAsStringSync('${encoder.convert(toJson())}\n');
  }

  void writeMarkdown(File output) {
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(toMarkdown());
  }
}

class SplitAwareBenchmarkRunner {
  final ReplayDatasetSplitManifest dataset;
  final Directory workspaceRoot;

  const SplitAwareBenchmarkRunner({
    required this.dataset,
    required this.workspaceRoot,
  });

  Future<SplitAwareBenchmarkReport> run({Directory? outputDirectory}) async {
    final splitReports = <SplitAwareBenchmarkSplitReport>[];
    for (final splitName in dataset.splits.keys) {
      final suite = SourceEstimationBenchmarkSuite(
        schemaVersion: dataset.schemaVersion,
        suiteId: '${dataset.datasetId}_$splitName',
        caseManifests: dataset.caseManifestsFor(splitName),
      );
      final splitOutputDirectory = outputDirectory == null
          ? null
          : Directory.fromUri(outputDirectory.uri.resolve('$splitName/'));
      final sourceReport =
          await SourceEstimationBatchRunner(
            suite: suite,
            workspaceRoot: workspaceRoot,
          ).run(
            perCaseOutputDirectory: splitOutputDirectory == null
                ? null
                : Directory.fromUri(
                    splitOutputDirectory.uri.resolve('source_cases/'),
                  ),
          );
      final detectionReport =
          await EventDetectionBatchRunner(
            suite: suite,
            workspaceRoot: workspaceRoot,
          ).run(
            perCaseOutputDirectory: splitOutputDirectory == null
                ? null
                : Directory.fromUri(
                    splitOutputDirectory.uri.resolve('detection_cases/'),
                  ),
          );

      if (splitOutputDirectory != null) {
        sourceReport.writeJson(
          File.fromUri(splitOutputDirectory.uri.resolve('source.json')),
        );
        sourceReport.writeMarkdown(
          File.fromUri(splitOutputDirectory.uri.resolve('source.md')),
        );
        detectionReport.writeJson(
          File.fromUri(splitOutputDirectory.uri.resolve('detection.json')),
        );
        detectionReport.writeMarkdown(
          File.fromUri(splitOutputDirectory.uri.resolve('detection.md')),
        );
      }

      splitReports.add(
        SplitAwareBenchmarkSplitReport(
          splitName: splitName,
          sourceReport: sourceReport,
          detectionReport: detectionReport,
        ),
      );
    }

    final report = SplitAwareBenchmarkReport(
      datasetId: dataset.datasetId,
      frozenAt: dataset.frozenAt,
      splitPolicy: dataset.splitPolicy,
      splits: List.unmodifiable(splitReports),
    );
    if (outputDirectory != null) {
      report.writeJson(
        File.fromUri(outputDirectory.uri.resolve('summary.json')),
      );
      report.writeMarkdown(
        File.fromUri(outputDirectory.uri.resolve('summary.md')),
      );
    }
    return report;
  }
}

String _formatKilometers(double? value) {
  if (value == null) return '-';
  final formatted = value.toStringAsFixed(1);
  final number = formatted.endsWith('.0')
      ? formatted.substring(0, formatted.length - 2)
      : formatted;
  return '$number km';
}

String _formatSeconds(double? value) {
  if (value == null) return '-';
  final formatted = value.toStringAsFixed(1);
  final number = formatted.endsWith('.0')
      ? formatted.substring(0, formatted.length - 2)
      : formatted;
  return '${number}s';
}

String _markdownCell(String value) {
  return value.replaceAll('|', r'\|').replaceAll(RegExp(r'[\r\n]+'), ' ');
}
