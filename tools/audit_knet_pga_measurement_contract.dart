import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/replay/knet_waveform_archive.dart';

/// Audits raw K-NET/KiK-net acceleration peak definitions without changing
/// source samples. This is intentionally a diagnostics-only tool: the output
/// is not response corrected or band-pass filtered, so it must not be treated
/// as the PGA definition used by an attenuation relation.
void main(List<String> args) {
  final inputs = _arguments(args, '--input');
  final outputPath = _argument(args, '--output');
  if (inputs.isEmpty || outputPath == null) {
    stderr.writeln(
      'Usage: dart run tools/audit_knet_pga_measurement_contract.dart '
      '--input <ascii|csv|zip> [--input <...>] --output <audit.json>',
    );
    exitCode = 64;
    return;
  }

  final parser = KnetWaveformArchiveParser();
  final channels = <KnetWaveformChannel>[];
  for (final input in inputs) {
    final file = File(input);
    if (!file.existsSync()) {
      throw FileSystemException('Input not found', input);
    }
    channels.addAll(_parseInput(parser, file));
  }

  final stations = _auditChannels(channels);
  final horizontalVectorRatios = stations
      .map((station) => station.horizontalVectorToComponentRatio)
      .whereType<double>()
      .toList(growable: false);
  final threeComponentVectorRatios = stations
      .map((station) => station.threeComponentVectorToComponentRatio)
      .whereType<double>()
      .toList(growable: false);

  final output = <String, Object?>{
    'schemaVersion': 'knet_pga_measurement_contract_audit_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'inputs': inputs,
    'channelCount': channels.length,
    'stationSeriesCount': stations.length,
    'measurementDefinitions': const {
      'paperPgaCandidate':
          'largest absolute peak of the NS or EW component after only raw constant-offset removal',
      'horizontalVector':
          'largest instantaneous sqrt(NS^2 + EW^2) after only raw constant-offset removal',
      'threeComponentVector':
          'largest instantaneous sqrt(NS^2 + EW^2 + UD^2) after only raw constant-offset removal',
    },
    'qualityLimitations': const [
      'diagnostic_only_raw_digit_scale_factor_or_csv_physical_values',
      'no_instrument_response_correction',
      'no_noise_selected_band_pass_filter',
      'not_a_si_midorikawa_1999_pga_measurement_contract',
      'does_not_modify_raw_waveform_samples',
    ],
    'ratioSummary': {
      'horizontalVectorToPaperCandidate': _summary(horizontalVectorRatios),
      'threeComponentVectorToPaperCandidate': _summary(
        threeComponentVectorRatios,
      ),
    },
    'stations': stations.map((station) => station.toJson()).toList(),
  };

  final outputFile = File(outputPath);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(output)}\n',
    encoding: utf8,
  );
  stdout.writeln(
    'wrote ${stations.length} raw PGA measurement-contract audits to '
    '${outputFile.path}',
  );
}

List<KnetWaveformChannel> _parseInput(
  KnetWaveformArchiveParser parser,
  File file,
) {
  final path = file.path;
  final lower = path.toLowerCase();
  if (lower.endsWith('.zip')) {
    return parser.parseZipBytes(file.readAsBytesSync(), sourcePath: path);
  }
  final text = file.readAsStringSync(encoding: utf8);
  if (lower.endsWith('.csv')) {
    return parser.parseCsv(text, sourcePath: path);
  }
  if (RegExp(r'\.(ns|ew|ud|ns1|ew1|ud1|ns2|ew2|ud2)$').hasMatch(lower)) {
    return [parser.parseAscii(text, sourcePath: path)];
  }
  throw FormatException('Unsupported K-NET/KiK-net waveform input: $path');
}

List<_StationAudit> _auditChannels(List<KnetWaveformChannel> channels) {
  final groups = <_StationKey, List<KnetWaveformChannel>>{};
  for (final channel in channels) {
    groups
        .putIfAbsent(
          _StationKey(channel.stationCode, channel.sensorRole),
          () => <KnetWaveformChannel>[],
        )
        .add(channel);
  }

  final audits =
      groups.values.map(_auditGroup).whereType<_StationAudit>().toList()
        ..sort((a, b) {
          final station = a.stationCode.compareTo(b.stationCode);
          return station != 0
              ? station
              : a.sensorRole.name.compareTo(b.sensorRole.name);
        });
  return List<_StationAudit>.unmodifiable(audits);
}

_StationAudit? _auditGroup(List<KnetWaveformChannel> channels) {
  final byComponent = <String, KnetWaveformChannel>{};
  for (final channel in channels) {
    final previous = byComponent[channel.component];
    if (previous == null ||
        channel.sampleCount > previous.sampleCount ||
        (channel.format == KnetWaveformFormat.ascii &&
            previous.format != KnetWaveformFormat.ascii)) {
      byComponent[channel.component] = channel;
    }
  }
  if (byComponent.isEmpty) return null;
  final first = byComponent.values.first;
  final samplingHz = first.samplingHz;
  if (byComponent.values.any(
    (channel) => (channel.samplingHz - samplingHz).abs() > 1e-6,
  )) {
    throw FormatException(
      'Mixed sampling rates for ${first.stationCode}/${first.sensorRole.name}',
    );
  }

  final start = byComponent.values
      .map((channel) => channel.sampleStartTimeUtc)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  final end = byComponent.values
      .map((channel) => _sampleEnd(channel))
      .reduce((a, b) => a.isBefore(b) ? a : b);
  final sampleCount = _durationToSamples(end.difference(start), samplingHz);
  if (sampleCount <= 0) return null;

  final aligned = <String, List<double>>{};
  for (final entry in byComponent.entries) {
    final channel = entry.value;
    final offset = _durationToSamples(
      start.difference(channel.sampleStartTimeUtc),
      samplingHz,
    );
    aligned[entry.key] = List<double>.generate(
      sampleCount,
      (index) => channel.accelerationGal[index + offset] - channel.offsetGal,
      growable: false,
    );
  }
  final ns = aligned['NS'];
  final ew = aligned['EW'];
  final ud = aligned['UD'];
  if (ns == null && ew == null) return null;

  var paperPgaCandidateGal = 0.0;
  var horizontalVectorGal = 0.0;
  var threeComponentVectorGal = 0.0;
  for (var index = 0; index < sampleCount; index++) {
    final nsValue = ns?[index] ?? 0.0;
    final ewValue = ew?[index] ?? 0.0;
    final udValue = ud?[index] ?? 0.0;
    paperPgaCandidateGal = math.max(
      paperPgaCandidateGal,
      math.max(nsValue.abs(), ewValue.abs()),
    );
    final horizontal = math.sqrt(nsValue * nsValue + ewValue * ewValue);
    horizontalVectorGal = math.max(horizontalVectorGal, horizontal);
    threeComponentVectorGal = math.max(
      threeComponentVectorGal,
      math.sqrt(horizontal * horizontal + udValue * udValue),
    );
  }

  return _StationAudit(
    stationCode: first.stationCode,
    sensorRole: first.sensorRole,
    network: first.network,
    stationLatitude: first.stationLatitude,
    stationLongitude: first.stationLongitude,
    samplingHz: samplingHz,
    availableComponents: byComponent.keys.toList()..sort(),
    sourceDataPrecision:
        byComponent.values
            .map((channel) => channel.dataPrecision)
            .toSet()
            .toList()
          ..sort(),
    sampleStartTimeUtc: start,
    sampleEndTimeUtc: end,
    sampleCount: sampleCount,
    paperPgaCandidateGal: paperPgaCandidateGal,
    horizontalVectorGal: horizontalVectorGal,
    threeComponentVectorGal: threeComponentVectorGal,
  );
}

DateTime _sampleEnd(KnetWaveformChannel channel) =>
    channel.sampleStartTimeUtc.add(
      Duration(
        microseconds:
            (channel.sampleCount *
                    Duration.microsecondsPerSecond /
                    channel.samplingHz)
                .round(),
      ),
    );

int _durationToSamples(Duration duration, double samplingHz) =>
    (duration.inMicroseconds * samplingHz / Duration.microsecondsPerSecond)
        .round();

Map<String, Object?> _summary(List<double> values) {
  if (values.isEmpty) return const {'count': 0};
  final sorted = values.toList()..sort();
  return {
    'count': sorted.length,
    'min': sorted.first,
    'p25': _percentile(sorted, 0.25),
    'median': _percentile(sorted, 0.5),
    'p75': _percentile(sorted, 0.75),
    'max': sorted.last,
  };
}

double _percentile(List<double> sorted, double fraction) {
  if (sorted.length == 1) return sorted.single;
  final position = (sorted.length - 1) * fraction;
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];
  return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
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

class _StationKey {
  const _StationKey(this.code, this.role);

  final String code;
  final KnetSensorRole role;

  @override
  bool operator ==(Object other) =>
      other is _StationKey && other.code == code && other.role == role;

  @override
  int get hashCode => Object.hash(code, role);
}

class _StationAudit {
  const _StationAudit({
    required this.stationCode,
    required this.sensorRole,
    required this.network,
    required this.stationLatitude,
    required this.stationLongitude,
    required this.samplingHz,
    required this.availableComponents,
    required this.sourceDataPrecision,
    required this.sampleStartTimeUtc,
    required this.sampleEndTimeUtc,
    required this.sampleCount,
    required this.paperPgaCandidateGal,
    required this.horizontalVectorGal,
    required this.threeComponentVectorGal,
  });

  final String stationCode;
  final KnetSensorRole sensorRole;
  final KnetNetwork network;
  final double stationLatitude;
  final double stationLongitude;
  final double samplingHz;
  final List<String> availableComponents;
  final List<String> sourceDataPrecision;
  final DateTime sampleStartTimeUtc;
  final DateTime sampleEndTimeUtc;
  final int sampleCount;
  final double paperPgaCandidateGal;
  final double horizontalVectorGal;
  final double threeComponentVectorGal;

  double? get horizontalVectorToComponentRatio => paperPgaCandidateGal > 0
      ? horizontalVectorGal / paperPgaCandidateGal
      : null;

  double? get threeComponentVectorToComponentRatio => paperPgaCandidateGal > 0
      ? threeComponentVectorGal / paperPgaCandidateGal
      : null;

  Map<String, Object?> toJson() => {
    'stationCode': stationCode,
    'sensorRole': sensorRole.name,
    'network': network.name,
    'stationLatitude': stationLatitude,
    'stationLongitude': stationLongitude,
    'samplingHz': samplingHz,
    'availableComponents': availableComponents,
    'sourceDataPrecision': sourceDataPrecision,
    'sampleStartTimeUtc': sampleStartTimeUtc.toIso8601String(),
    'sampleEndTimeUtc': sampleEndTimeUtc.toIso8601String(),
    'sampleCount': sampleCount,
    'paperPgaCandidateGal': paperPgaCandidateGal,
    'horizontalVectorGal': horizontalVectorGal,
    'threeComponentVectorGal': threeComponentVectorGal,
    'horizontalVectorToPaperCandidateRatio': horizontalVectorToComponentRatio,
    'threeComponentVectorToPaperCandidateRatio':
        threeComponentVectorToComponentRatio,
  };
}
