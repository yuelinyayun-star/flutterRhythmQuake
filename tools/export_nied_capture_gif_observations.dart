import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/replay/knet_waveform_archive.dart';
import 'package:flutterrhythmquake/core/replay/nied_gif_observation_export.dart';

void main(List<String> args) {
  final capturePath = _argument(args, '--capture');
  final outputPath = _argument(args, '--output');
  final sensorRoleName = _argument(args, '--sensor-role') ?? 'surface';
  if (capturePath == null || outputPath == null) {
    stderr.writeln(
      'Usage: dart run tools/export_nied_capture_gif_observations.dart '
      '--capture <directory> --output <gif_observations.json> '
      '[--sensor-role surface|borehole]',
    );
    exitCode = 64;
    return;
  }

  final sensorRole = _parseSensorRole(sensorRoleName);
  if (sensorRole == null) {
    stderr.writeln(
      'Invalid --sensor-role: $sensorRoleName. Expected surface or borehole.',
    );
    exitCode = 64;
    return;
  }

  final exported = const NiedGifObservationExporter()
      .exportFromCaptureDirectory(capturePath, sensorRole: sensorRole);
  final outputFile = File(outputPath);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(exported),
  );
  stdout.writeln(
    'wrote ${exported['observationCount']} observations to ${outputFile.path}',
  );
}

KnetSensorRole? _parseSensorRole(String value) {
  for (final role in KnetSensorRole.values) {
    if (role.name == value) return role;
  }
  return null;
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
