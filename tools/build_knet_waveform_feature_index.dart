import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final outputPath = _argument(args, '--output');
  final inputs = _arguments(args, '--input');
  final inputDirectory = _argument(args, '--input-directory');
  if (outputPath == null || (inputs.isEmpty && inputDirectory == null)) {
    stderr.writeln(
      'Usage: dart run tools/build_knet_waveform_feature_index.dart '
      '--input-directory <dir> --output <index.json>',
    );
    exitCode = 64;
    return;
  }

  final files = <File>[
    ...inputs.map(File.new),
    if (inputDirectory != null)
      ...Directory(inputDirectory).listSync().whereType<File>().where(
        (file) => file.path.endsWith('_features.json'),
      ),
  ]..sort((a, b) => a.path.compareTo(b.path));

  final entries = files.map(_summarizeFeaturePackage).toList(growable: false);
  final output = {
    'schemaVersion': 'knet_waveform_feature_index_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'entryCount': entries.length,
    'entries': entries,
  };
  final outputFile = File(outputPath);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(output),
  );
  stdout.writeln(
    'wrote ${entries.length} K-NET/KiK-net feature entries to $outputPath',
  );
}

Map<String, Object?> _summarizeFeaturePackage(File file) {
  final head = _readPrefix(file, 128 * 1024);
  final input = _matchString(head, 'inputs') ?? '';
  final fileName = file.uri.pathSegments.last;
  final eventId = _eventIdFromPath(input).isEmpty
      ? _eventIdFromFeatureName(fileName)
      : _eventIdFromPath(input);
  final zipName = input.split(RegExp(r'[\\\\/]')).last;
  final format = zipName.contains('_csv') || fileName.contains('_csv')
      ? 'csv'
      : 'ascii';
  final directoryId =
      RegExp(r'(\d{14})').firstMatch(zipName)?.group(1) ??
      RegExp(r'(\d{14})').firstMatch(fileName)?.group(1);

  return {
    'eventId': eventId,
    'format': format,
    'niedDirectoryId': directoryId,
    'featurePackagePath': file.path.replaceAll('\\', '/'),
    'featurePackageBytes': file.lengthSync(),
    'inputZipPath': input.replaceAll('\\', '/'),
    'channelCount': _matchInt(head, 'channelCount'),
    'seriesCount': _matchInt(head, 'seriesCount'),
    'parserVersion': _matchString(head, 'parserVersion'),
    'featureVersion': _matchString(head, 'featureVersion'),
    'qualityFlags': [
      'official_knet_kiknet_waveform',
      if (format == 'csv') 'csv_physical_gal_0.01',
      if (format == 'ascii') 'raw_digit_scale_factor',
      'jma_intensity_unfiltered_duration_proxy',
      'pgv_integrated_without_instrument_response_correction',
    ],
  };
}

String _readPrefix(File file, int byteLimit) {
  final stream = file.openSync();
  try {
    final length = file.lengthSync();
    final size = length < byteLimit ? length : byteLimit;
    return utf8.decode(stream.readSync(size), allowMalformed: true);
  } finally {
    stream.closeSync();
  }
}

int? _matchInt(String text, String key) {
  final match = RegExp('"$key"\\s*:\\s*(\\d+)').firstMatch(text);
  return match == null ? null : int.parse(match.group(1)!);
}

String? _matchString(String text, String key) {
  if (key == 'inputs') {
    final match = RegExp('"inputs"\\s*:\\s*\\[\\s*"([^"]+)"').firstMatch(text);
    return match?.group(1);
  }
  final match = RegExp('"$key"\\s*:\\s*"([^"]+)"').firstMatch(text);
  return match?.group(1);
}

String _eventIdFromPath(String path) {
  final parts = path.split(RegExp(r'[\\\\/]'));
  final index = parts.indexOf('knet_downloads');
  if (index >= 0 && index + 1 < parts.length) return parts[index + 1];
  return '';
}

String _eventIdFromFeatureName(String fileName) {
  return fileName
      .replaceFirst(RegExp(r'_\d{14}_(ascii|csv)_features\.json$'), '')
      .replaceFirst(RegExp(r'_(ascii|csv)_features\.json$'), '');
}

List<String> _arguments(List<String> args, String name) {
  final values = <String>[];
  for (var index = 0; index < args.length - 1; index++) {
    if (args[index] == name) values.add(args[index + 1]);
  }
  return values;
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
