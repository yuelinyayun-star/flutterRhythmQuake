import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/replay/knet_gif_domain_alignment.dart';
import 'package:flutterrhythmquake/core/replay/knet_waveform_archive.dart';
import 'package:flutterrhythmquake/core/replay/knet_waveform_features.dart';

void main(List<String> args) {
  final eventId = _argument(args, '--event-id');
  final featuresPath = _argument(args, '--features');
  final gifPath = _argument(args, '--gif-observations');
  final outputPath = _argument(args, '--output');
  final includeSamples = !args.contains('--summary-only');

  if (eventId == null ||
      featuresPath == null ||
      gifPath == null ||
      outputPath == null) {
    stderr.writeln(
      'Usage: dart run tools/build_knet_gif_waveform_alignment.dart '
      '--event-id <id> --features <features.json> '
      '--gif-observations <gif_observations.json> --output <alignment.json> '
      '[--summary-only]',
    );
    exitCode = 64;
    return;
  }

  final featuresJson =
      jsonDecode(File(featuresPath).readAsStringSync()) as Map<String, Object?>;
  final gifJson =
      jsonDecode(File(gifPath).readAsStringSync()) as Map<String, Object?>;
  final series = _parseFeatureSeries(featuresJson);
  final observations = _parseGifObservations(gifJson);

  final report = const KnetGifDomainAligner().align(
    eventId: eventId,
    waveformSeries: series,
    gifObservations: observations,
  );

  final outputFile = File(outputPath);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(
    const JsonEncoder.withIndent(
      '  ',
    ).convert(report.toJson(includeSamples: includeSamples)),
  );
  stdout.writeln(
    'wrote ${report.summary.sampleCount} aligned samples across '
    '${report.summary.stationCount} stations to $outputPath',
  );
}

List<KnetWaveformFeatureSeries> _parseFeatureSeries(Map<String, Object?> json) {
  final rawSeries = json['features']! as List<Object?>;
  return rawSeries
      .cast<Map<String, Object?>>()
      .map((series) {
        return KnetWaveformFeatureSeries(
          stationCode: series['stationCode']! as String,
          network: _enumByName(
            KnetNetwork.values,
            series['network']! as String,
          ),
          sensorRole: _enumByName(
            KnetSensorRole.values,
            series['sensorRole']! as String,
          ),
          stationLatitude: _number(series['stationLatitude']),
          stationLongitude: _number(series['stationLongitude']),
          sampleStartTimeUtc: DateTime.parse(
            series['sampleStartTimeUtc']! as String,
          ).toUtc(),
          samplingHz: _number(series['samplingHz']),
          sourcePaths: (series['sourcePaths'] as List<Object?>? ?? const [])
              .cast<String>()
              .toList(growable: false),
          availableComponents:
              (series['availableComponents'] as List<Object?>? ?? const [])
                  .cast<String>()
                  .toList(growable: false),
          seconds: (series['seconds']! as List<Object?>)
              .cast<Map<String, Object?>>()
              .map(_parseSecondFeature)
              .toList(growable: false),
          qualityFlags: (series['qualityFlags'] as List<Object?>? ?? const [])
              .cast<String>()
              .toList(growable: false),
          processingVersion: series['processingVersion']! as String,
        );
      })
      .toList(growable: false);
}

KnetWaveformSecondFeature _parseSecondFeature(Map<String, Object?> json) {
  return KnetWaveformSecondFeature(
    secondIndex: (json['secondIndex']! as num).toInt(),
    startTimeUtc: DateTime.parse(json['startTimeUtc']! as String).toUtc(),
    pgaGal: _number(json['pgaGal']),
    maxHorizontalAccelerationGal: _number(json['maxHorizontalAccelerationGal']),
    pgvCms: _number(json['pgvCms']),
    rmsAccelerationGal: _number(json['rmsAccelerationGal']),
    energyRatioToPreviousBaseline: json['energyRatioToPreviousBaseline'] == null
        ? null
        : _number(json['energyRatioToPreviousBaseline']),
    jmaIntensityApprox: json['jmaIntensityApprox'] == null
        ? null
        : _number(json['jmaIntensityApprox']),
    qualityFlags: (json['qualityFlags'] as List<Object?>? ?? const [])
        .cast<String>()
        .toList(growable: false),
  );
}

List<GifDecodedStationSecond> _parseGifObservations(Map<String, Object?> json) {
  final raw = json['observations']! as List<Object?>;
  return raw
      .cast<Map<String, Object?>>()
      .map((observation) {
        return GifDecodedStationSecond(
          stationCode: observation['stationCode']! as String,
          observedAtUtc: DateTime.parse(
            observation['observedAtUtc']! as String,
          ).toUtc(),
          gifDecodedShindo: _number(observation['gifDecodedShindo']),
          sensorRole: _enumByName(
            KnetSensorRole.values,
            observation['sensorRole'] as String? ?? KnetSensorRole.surface.name,
          ),
          qualityFlags:
              (observation['qualityFlags'] as List<Object?>? ?? const [])
                  .cast<String>()
                  .toList(growable: false),
        );
      })
      .toList(growable: false);
}

T _enumByName<T extends Enum>(List<T> values, String name) =>
    values.firstWhere((value) => value.name == name);

double _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.parse(value);
  throw FormatException('Expected number, got $value');
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
