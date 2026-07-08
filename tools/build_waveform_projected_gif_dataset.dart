import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/replay/waveform_projected_gif.dart';

void main(List<String> args) {
  final indexPath = _argument(args, '--feature-index');
  final outputDirectory = _argument(args, '--output');
  final preferFormat = _argument(args, '--prefer-format') ?? 'csv';
  final includeAllFormats = args.contains('--include-all-formats');

  if (indexPath == null || outputDirectory == null) {
    stderr.writeln(
      'Usage: dart run tools/build_waveform_projected_gif_dataset.dart '
      '--feature-index <knet_waveform_feature_index.json> '
      '--output <directory> [--prefer-format csv|ascii] [--include-all-formats]',
    );
    exitCode = 64;
    return;
  }

  final index =
      jsonDecode(File(indexPath).readAsStringSync()) as Map<String, Object?>;
  final entries = (index['entries']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final selectedEntries = includeAllFormats
      ? entries
      : _selectPreferredEntries(entries, preferFormat);
  final outputRoot = Directory(outputDirectory);
  outputRoot.createSync(recursive: true);
  final converter = WaveformProjectedGifConverter();
  final outputEntries = <Map<String, Object?>>[];

  for (final entry in selectedEntries) {
    final featurePath = entry['featurePackagePath']! as String;
    final eventId = entry['eventId']! as String;
    final format = entry['format']! as String;
    final featurePackage =
        jsonDecode(File(featurePath).readAsStringSync())
            as Map<String, Object?>;
    final projected = converter.convertFeaturePackage(
      featurePackage,
      eventId: eventId,
      sourceFeaturePackagePath: featurePath,
      sourceFeatureFormat: format,
      niedDirectoryId: entry['niedDirectoryId'] as String?,
    );
    final outputFileName = '${eventId}_${format}_waveform_projected_gif.json';
    final outputPath =
        '${outputRoot.path}${Platform.pathSeparator}$outputFileName';
    File(outputPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(projected.toJson()),
    );
    outputEntries.add({
      'eventId': eventId,
      'format': format,
      'niedDirectoryId': entry['niedDirectoryId'],
      'projectedPackagePath': outputPath.replaceAll('\\', '/'),
      'sourceFeaturePackagePath': featurePath,
      'stationCount': projected.stationCount,
      'stationSecondCount': projected.stationSecondCount,
      'startTimeUtc': projected.startTimeUtc?.toIso8601String(),
      'endTimeUtc': projected.endTimeUtc?.toIso8601String(),
      'qualityFlags': projected.qualityFlags,
    });
  }

  final datasetIndex = {
    'schemaVersion': 'waveform_projected_gif_dataset_index_v1',
    'domain': 'waveform_projected_gif',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'sourceFeatureIndexPath': indexPath,
    'preferFormat': preferFormat,
    'includeAllFormats': includeAllFormats,
    'entryCount': outputEntries.length,
    'entries': outputEntries,
    'qualityFlags': const [
      'projected_from_official_waveform',
      'not_real_nied_gif',
      'does_not_include_untriggered_full_network',
      'does_not_include_real_gif_transport_or_pixel_errors',
    ],
  };
  final datasetIndexPath =
      '${outputRoot.path}${Platform.pathSeparator}waveform_projected_gif_index.json';
  File(
    datasetIndexPath,
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(datasetIndex));
  stdout.writeln(
    'wrote ${outputEntries.length} waveform_projected_gif packages to ${outputRoot.path}',
  );
}

List<Map<String, Object?>> _selectPreferredEntries(
  List<Map<String, Object?>> entries,
  String preferFormat,
) {
  final byEvent = <String, List<Map<String, Object?>>>{};
  for (final entry in entries) {
    byEvent.putIfAbsent(entry['eventId']! as String, () => []).add(entry);
  }
  final selected = <Map<String, Object?>>[];
  for (final eventEntries in byEvent.values) {
    eventEntries.sort((a, b) {
      final aFormat = a['format']! as String;
      final bFormat = b['format']! as String;
      if (aFormat == preferFormat && bFormat != preferFormat) return -1;
      if (aFormat != preferFormat && bFormat == preferFormat) return 1;
      final aSeries = (a['seriesCount'] as num?)?.toInt() ?? 0;
      final bSeries = (b['seriesCount'] as num?)?.toInt() ?? 0;
      return bSeries.compareTo(aSeries);
    });
    selected.add(eventEntries.first);
  }
  selected.sort(
    (a, b) => (a['eventId']! as String).compareTo(b['eventId']! as String),
  );
  return selected;
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
