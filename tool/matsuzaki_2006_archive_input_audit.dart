import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

void main(List<String> arguments) {
  final inputPath = _value(arguments, '--input');
  final outputDirectoryPath =
      _value(arguments, '--output-dir') ??
      '.dart_tool/matsuzaki_2006_archive_input_audit';
  if (inputPath == null) {
    stderr.writeln(
      'Usage: dart run tool/matsuzaki_2006_archive_input_audit.dart '
      '--input <annual.json> --initial-radius-km <km> '
      '--hard-radius-km <km> --minimum-depth <km> '
      '--maximum-depth <km> --minimum-stations <count> '
      '--maximum-stations <count> [--output-dir <directory>]',
    );
    exitCode = 64;
    return;
  }
  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    stderr.writeln('Input file does not exist: $inputPath');
    exitCode = 66;
    return;
  }
  final initialRadius = _requiredDouble(arguments, '--initial-radius-km');
  final hardRadius = _requiredDouble(arguments, '--hard-radius-km');
  final minimumDepth = _requiredDouble(arguments, '--minimum-depth');
  final maximumDepth = _requiredDouble(arguments, '--maximum-depth');
  final minimumStations = _requiredInt(arguments, '--minimum-stations');
  final maximumStations = _requiredInt(arguments, '--maximum-stations');
  final spec = Matsuzaki2006ArchiveInputSpec(
    initialSearchRadiusKm: initialRadius,
    maximumHorizontalSearchDistanceKm: hardRadius,
    minimumSearchDepthKm: minimumDepth,
    maximumSearchDepthKm: maximumDepth,
    minimumObservations: minimumStations,
    maximumObservations: maximumStations,
    minimumInstrumentalIntensity: 0.5,
  );
  spec.validate();

  final decoded = jsonDecode(inputFile.readAsStringSync(encoding: utf8));
  if (decoded is! Map<String, Object?> ||
      decoded['year'] is! num ||
      decoded['events'] is! List<Object?>) {
    throw const FormatException('Invalid annual JMA intensity dataset.');
  }
  final year = (decoded['year']! as num).toInt();
  final rawEvents = decoded['events']! as List<Object?>;
  const builder = Matsuzaki2006ArchiveInversionInputBuilder();
  final statusCounts = <String, int>{};
  final events = <Map<String, Object?>>[];
  var eligibleEventCount = 0;
  for (final rawEvent in rawEvents) {
    if (rawEvent is! Map<String, Object?>) continue;
    final truth = _eligibleTruth(rawEvent, spec);
    if (truth == null) continue;
    eligibleEventCount++;
    final input = builder.build(rawEvent: rawEvent, spec: spec);
    _increment(statusCounts, input.status.name);
    final anchorErrorKm = input.anchorLatitude == null
        ? null
        : Matsuzaki2006PointSourceGeometry.hypocentralDistanceBetween(
            sourceLatitude: truth.latitude,
            sourceLongitude: truth.longitude,
            stationLatitude: input.anchorLatitude!,
            stationLongitude: input.anchorLongitude!,
            depthKm: 0,
          );
    final truthInsideHardSearchDomain =
        anchorErrorKm != null && anchorErrorKm <= hardRadius;
    events.add({
      'eventId': rawEvent['eventId'],
      'originTime': truth.originTime,
      'catalogLatitude': truth.latitude,
      'catalogLongitude': truth.longitude,
      'catalogDepthKm': truth.depthKm,
      'catalogMagnitude': truth.magnitude,
      'inputStatus': input.status.name,
      'rawObservationCount': input.rawObservationCount,
      'validObservationCount': input.validObservationCount,
      'domainSafeObservationCount': input.domainSafeObservationCount,
      'selectedObservationCount': input.observations.length,
      'anchorLatitude': input.anchorLatitude,
      'anchorLongitude': input.anchorLongitude,
      'anchorErrorKm': anchorErrorKm,
      'truthInsideHardSearchDomain': truthInsideHardSearchDomain,
    });
  }
  final ready = events
      .where((event) => event['inputStatus'] == 'ready')
      .toList();
  final anchorErrors = ready
      .map((event) => event['anchorErrorKm'])
      .whereType<num>()
      .map((value) => value.toDouble())
      .toList();
  final selectedStationCounts = ready
      .map((event) => event['selectedObservationCount'])
      .whereType<num>()
      .map((value) => value.toDouble())
      .toList();
  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_archive_input_audit_v1',
    'inputPath': inputPath,
    'year': year,
    'truthUseBoundary':
        'Catalog truth is used only for event eligibility and audit metrics.',
    'inputConstructionUsesCatalogTruth': false,
    'spec': {
      'initialRadiusKm': initialRadius,
      'hardRadiusKm': hardRadius,
      'minimumDepthKm': minimumDepth,
      'maximumDepthKm': maximumDepth,
      'minimumStations': minimumStations,
      'maximumStations': maximumStations,
      'minimumInstrumentalIntensity': spec.minimumInstrumentalIntensity,
    },
    'summary': {
      'rawEventCount': rawEvents.length,
      'eligibleEventCount': eligibleEventCount,
      'inputStatusCounts': _sortedCounts(statusCounts),
      'readyEventCount': ready.length,
      'truthInsideHardSearchDomainCount': ready
          .where((event) => event['truthInsideHardSearchDomain'] == true)
          .length,
      'anchorErrorKmMedian': _percentile(anchorErrors, 0.5),
      'anchorErrorKmP90': _percentile(anchorErrors, 0.9),
      'anchorErrorKmMaximum': anchorErrors.isEmpty
          ? null
          : anchorErrors.reduce((left, right) => left > right ? left : right),
      'selectedStationCountMinimum': selectedStationCounts.isEmpty
          ? null
          : selectedStationCounts.reduce(
              (left, right) => left < right ? left : right,
            ),
      'selectedStationCountMedian': _percentile(selectedStationCounts, 0.5),
    },
    'events': events,
  };
  final outputDirectory = Directory(outputDirectoryPath)
    ..createSync(recursive: true);
  final jsonFile = File('${outputDirectory.path}/report.json');
  jsonFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report),
    encoding: utf8,
  );
  final markdownFile = File('${outputDirectory.path}/report.md');
  markdownFile.writeAsStringSync(_markdown(report), encoding: utf8);
  stdout.writeln(jsonEncode(report['summary']));
  stdout.writeln('wrote ${jsonFile.path}');
  stdout.writeln('wrote ${markdownFile.path}');
}

_CatalogTruth? _eligibleTruth(
  Map<String, Object?> rawEvent,
  Matsuzaki2006ArchiveInputSpec spec,
) {
  final alternate = rawEvent['alternateHypocenters'];
  if (alternate is List<Object?> && alternate.isNotEmpty) return null;
  final raw = rawEvent['preferredHypocenter'];
  if (raw is! Map<String, Object?>) return null;
  final latitude = _number(raw['latitude']);
  final longitude = _number(raw['longitude']);
  final depthKm = _number(raw['depthKm']);
  final magnitude = _number(raw['magnitude']);
  final magnitudeType = (raw['magnitudeType'] as String?)?.trim();
  if (latitude == null ||
      latitude < -90 ||
      latitude > 90 ||
      longitude == null ||
      longitude < -180 ||
      longitude > 180 ||
      depthKm == null ||
      depthKm < spec.minimumSearchDepthKm ||
      depthKm > spec.maximumSearchDepthKm ||
      magnitude == null ||
      magnitude < Matsuzaki2006AttenuationModel.minimumMagnitude ||
      magnitude > Matsuzaki2006AttenuationModel.maximumMagnitude ||
      magnitudeType == null ||
      !Matsuzaki2006JmaBaselineEvaluator.supportedMagnitudeTypes.contains(
        magnitudeType,
      )) {
    return null;
  }
  return _CatalogTruth(
    originTime: (raw['originTime'] as String?) ?? '',
    latitude: latitude,
    longitude: longitude,
    depthKm: depthKm,
    magnitude: magnitude,
  );
}

String _markdown(Map<String, Object?> report) {
  final spec = report['spec']! as Map<String, Object?>;
  final summary = report['summary']! as Map<String, Object?>;
  final buffer = StringBuffer()
    ..writeln('# Matsuzaki 2006 Archive Input Audit')
    ..writeln()
    ..writeln('Year: `${report['year']}`')
    ..writeln()
    ..writeln(
      'Catalog truth is used only for eligibility and post-build audit metrics. '
      'Input construction does not read it.',
    )
    ..writeln()
    ..writeln('## Specification')
    ..writeln()
    ..writeln('| Field | Value |')
    ..writeln('|---|---:|');
  for (final entry in spec.entries) {
    buffer.writeln('| ${entry.key} | ${entry.value} |');
  }
  buffer
    ..writeln()
    ..writeln('## Summary')
    ..writeln()
    ..writeln('| Metric | Value |')
    ..writeln('|---|---:|');
  for (final entry in summary.entries) {
    buffer.writeln('| ${entry.key} | ${entry.value} |');
  }
  return buffer.toString();
}

double? _percentile(List<double> values, double fraction) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final position = (sorted.length - 1) * fraction;
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];
  final weight = position - lower;
  return sorted[lower] * (1 - weight) + sorted[upper] * weight;
}

String? _value(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  return index >= 0 && index + 1 < arguments.length
      ? arguments[index + 1]
      : null;
}

double _requiredDouble(List<String> arguments, String name) {
  final raw = _value(arguments, name);
  final value = raw == null ? null : double.tryParse(raw);
  if (value == null || !value.isFinite) {
    throw FormatException('$name must be a finite number.');
  }
  return value;
}

int _requiredInt(List<String> arguments, String name) {
  final raw = _value(arguments, name);
  final value = raw == null ? null : int.tryParse(raw);
  if (value == null) throw FormatException('$name must be an integer.');
  return value;
}

double? _number(Object? value) => value is num ? value.toDouble() : null;

void _increment(Map<String, int> counts, String key) {
  counts[key] = (counts[key] ?? 0) + 1;
}

Map<String, int> _sortedCounts(Map<String, int> counts) {
  final keys = counts.keys.toList()..sort();
  return {for (final key in keys) key: counts[key]!};
}

class _CatalogTruth {
  const _CatalogTruth({
    required this.originTime,
    required this.latitude,
    required this.longitude,
    required this.depthKm,
    required this.magnitude,
  });

  final String originTime;
  final double latitude;
  final double longitude;
  final double depthKm;
  final double magnitude;
}
