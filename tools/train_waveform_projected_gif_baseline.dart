import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/replay/waveform_projected_gif_baseline.dart';

void main(List<String> args) {
  final indexPath = _argument(args, '--index');
  final outputPath = _argument(args, '--output');
  final markdownPath = _argument(args, '--markdown');
  final temporal = args.contains('--temporal');
  if (indexPath == null || outputPath == null) {
    stderr.writeln(
      'Usage: dart run tools/train_waveform_projected_gif_baseline.dart '
      '--index <waveform_projected_gif_index.json> --output <report.json> '
      '[--markdown <report.md>] [--temporal]',
    );
    exitCode = 64;
    return;
  }

  final index =
      jsonDecode(File(indexPath).readAsStringSync()) as Map<String, Object?>;
  if (index['domain'] != 'waveform_projected_gif') {
    throw FormatException('Unexpected dataset domain: ${index['domain']}');
  }
  final events = <ProjectedGifFieldEvent>[];
  for (final entry
      in (index['entries']! as List<Object?>).cast<Map<String, Object?>>()) {
    final packagePath = entry['projectedPackagePath']! as String;
    final package =
        jsonDecode(File(packagePath).readAsStringSync())
            as Map<String, Object?>;
    events.add(ProjectedGifFieldEvent.fromJson(package));
  }

  final trainer = ProjectedGifBaselineTrainer(useTemporalHistory: temporal);
  final folds = trainer.leaveOneEventOut(events);
  final zeroMask = folds
      .map((fold) => fold.evaluations.first)
      .toList(growable: false);
  final report = <String, Object?>{
    'schemaVersion': temporal
        ? '${waveformProjectedGifBaselineVersion}_temporal'
        : waveformProjectedGifBaselineVersion,
    'domain': 'waveform_projected_gif',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'sourceIndexPath': indexPath,
    'splitPolicy': 'leave_one_event_out; no station-second split',
    'inputPolicy':
        'surface sensors only; origin through origin+120s; minimum 25% training-frame coverage',
    'modelPolicy': temporal
        ? '60-second station history; event running peak; exponentially decayed relative first arrival'
        : 'current-frame intensity weighted centroid',
    'limitations': const [
      'projected_from_official_waveform',
      'not_real_nied_gif',
      'does_not_measure_real_detection_or_transport_delay',
      'published_waveform_stations_are_not_the_untriggered_full_network',
    ],
    'eventCount': events.length,
    'folds': folds.map((fold) => fold.toJson()).toList(),
    'heldOutSummary': {
      'medianFrameErrorKm': _median(
        zeroMask.map((value) => value.medianErrorKm).whereType<double>(),
      ),
      'medianFirstEstimateErrorKm': _median(
        zeroMask.map((value) => value.firstEstimateErrorKm).whereType<double>(),
      ),
      'medianQuantizationMae': _median(
        zeroMask.map((value) => value.quantizationMae),
      ),
    },
  };

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  if (markdownPath != null) {
    final markdown = File(markdownPath)..parent.createSync(recursive: true);
    markdown.writeAsStringSync(_markdown(report, folds));
  }
  stdout.writeln('wrote ${folds.length} held-out folds to $outputPath');
}

String _markdown(
  Map<String, Object?> report,
  List<ProjectedGifLeaveOneEventOutFold> folds,
) {
  final summary = report['heldOutSummary']! as Map<String, Object?>;
  final isTemporal = '${report['schemaVersion']}'.endsWith('_temporal');
  final buffer = StringBuffer()
    ..writeln(
      isTemporal
          ? '# Waveform Projected GIF Temporal Baseline'
          : '# Waveform Projected GIF Spatial Baseline',
    )
    ..writeln()
    ..writeln('- Schema: `${report['schemaVersion']}`')
    ..writeln('- Split: leave-one-event-out; station-seconds never cross folds')
    ..writeln('- Input: surface sensors, origin through origin+120 seconds')
    ..writeln('- Model: ${report['modelPolicy']}')
    ..writeln(
      '- Selection guard: at least 25% frame coverage in every training event',
    )
    ..writeln('- Domain: projected official waveform, not real NIED GIF')
    ..writeln()
    ..writeln(
      '| Held-out event | Min intensity | Weight exponent | Arrival decay | Drop | Frames | Coverage | First delay | First error | Median | P90 |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (final fold in folds) {
    for (final evaluation in fold.evaluations) {
      buffer.writeln(
        '| ${fold.heldOutEventId} | '
        '${fold.config.minimumIntensity.toStringAsFixed(2)} | '
        '${fold.config.intensityWeightExponent.toStringAsFixed(2)} | '
        '${_format(fold.config.arrivalDecaySeconds, 's')} | '
        '${(evaluation.dropRate * 100).toStringAsFixed(0)}% | '
        '${evaluation.eligibleFrameCount}/${evaluation.frameCount} | '
        '${(evaluation.coverage * 100).toStringAsFixed(1)}% | '
        '${_format(evaluation.firstEstimateDelaySeconds, 's')} | '
        '${_format(evaluation.firstEstimateErrorKm, 'km')} | '
        '${_format(evaluation.medianErrorKm, 'km')} | '
        '${_format(evaluation.p90ErrorKm, 'km')} |',
      );
    }
  }
  buffer
    ..writeln()
    ..writeln('## Held-out summary')
    ..writeln()
    ..writeln(
      '- Median frame error: ${_format(summary['medianFrameErrorKm'] as double?, 'km')}',
    )
    ..writeln(
      '- Median first-estimate error: ${_format(summary['medianFirstEstimateErrorKm'] as double?, 'km')}',
    )
    ..writeln(
      '- Median projected-level quantization MAE: ${(summary['medianQuantizationMae']! as num).toStringAsFixed(3)} intensity units',
    )
    ..writeln()
    ..writeln(
      'These values do not measure real GIF detection delay, missing frames, transport latency, or production readiness.',
    );
  return buffer.toString();
}

String _format(double? value, String unit) =>
    value == null ? '-' : '${value.toStringAsFixed(2)} $unit';

double? _median(Iterable<double> values) {
  final sorted = values.toList(growable: false)..sort();
  if (sorted.isEmpty) return null;
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
