import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutterrhythmquake/core/source_estimation/srev_kaizou_magnitude.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';

double percentile(List<double> values, double probability) {
  if (values.isEmpty) throw StateError('Cannot summarize an empty sample');
  final sorted = [...values]..sort();
  final index = (sorted.length - 1) * probability;
  final lower = index.floor();
  final upper = index.ceil();
  return sorted[lower] + (sorted[upper] - sorted[lower]) * (index - lower);
}

Map<String, Object?> statistics(List<double> values) => values.isEmpty
    ? {'count': 0, 'median': null, 'iqr': null}
    : {
        'count': values.length,
        'median': percentile(values, 0.5),
        'p25': percentile(values, 0.25),
        'p75': percentile(values, 0.75),
        'iqr': percentile(values, 0.75) - percentile(values, 0.25),
      };

void main(List<String> args) {
  if (args.length != 2) {
    throw ArgumentError('Pass original candidate report and new output path');
  }
  final input = File(args[0]);
  final output = File(args[1]);
  if (output.existsSync()) throw StateError('Output already exists');
  final bytes = input.readAsBytesSync();
  final inputHash = sha256.convert(bytes).toString();
  final report = jsonDecode(utf8.decode(bytes)) as Map;
  final stations = {
    for (final station in NiedStationDb.stations)
      station['code'] as String: station,
  };
  final cases = <Map<String, Object?>>[];
  var examinedFrames = 0;
  var examinedStationPeaks = 0;
  for (final replay in (report['cases'] as List).cast<Map>()) {
    final frames = <Map<String, Object?>>[];
    List<Map<String, Object?>> lastStations = [];
    for (final frame in (replay['frames'] as List).cast<Map>()) {
      final audit = frame['magnitudeAudit'] as Map?;
      final experiment = audit?['experiment'] as Map?;
      final candidate = experiment?['eventPeakCandidate'] as Map?;
      if (candidate?['supported'] != true) continue;
      final estimate = frame['estimate'] as Map;
      final latitude = (estimate['latitude'] as num).toDouble();
      final longitude = (estimate['longitude'] as num).toDouble();
      final depth = (estimate['depthKm'] as num).toDouble();
      final multiple = candidate!['multipleSources'] == true;
      final peaks = (candidate['stationPeaks'] as Map).cast<String, num>();
      final maximum = (candidate['peakIntensity'] as num).toDouble();
      final original = calculateSrevKaizouMagnitude(
        sourceLatitude: latitude,
        sourceLongitude: longitude,
        inputIntensity: maximum,
        multipleSources: multiple,
      )!;
      if ((original.magnitude - (candidate['magnitude'] as num)).abs() >
          1e-10) {
        throw StateError('Baseline magnitude changed');
      }
      final rows = <Map<String, Object?>>[];
      final magnitudes = <double>[];
      final depthMagnitudes = <double>[];
      final strongestMagnitudes = <double>[];
      final bands = <String, List<double>>{
        '0_50km': [],
        '50_100km': [],
        '100_200km': [],
        '200km_plus': [],
      };
      for (final peak in peaks.entries) {
        final station = stations[peak.key];
        if (station == null || !peak.value.isFinite) {
          throw StateError(
            'Missing station or nonfinite observation: ${peak.key}',
          );
        }
        final distance = srevKaizouStationDistanceKm(
          roundedSourceLatitude: original.roundedSourceLatitude,
          roundedSourceLongitude: original.roundedSourceLongitude,
          stationLatitude: (station['lat'] as num).toDouble(),
          stationLongitude: (station['lng'] as num).toDouble(),
        );
        double calculate(double distance) =>
            srevKaizouMagnitudeFromDistanceAndIntensity(
              stationDistanceKm: math.max(20.0, distance),
              inputIntensity: peak.value.toDouble(),
              multipleSources: multiple,
            )!;
        final magnitude = calculate(distance);
        final depthMagnitude = calculate(
          math.sqrt(distance * distance + depth * depth),
        );
        magnitudes.add(magnitude);
        depthMagnitudes.add(depthMagnitude);
        if (peak.value == maximum) strongestMagnitudes.add(magnitude);
        final band = distance < 50
            ? '0_50km'
            : distance < 100
            ? '50_100km'
            : distance < 200
            ? '100_200km'
            : '200km_plus';
        bands[band]!.add(magnitude);
        rows.add({
          'code': peak.key,
          'name': station['name'],
          'peakIntensity': peak.value,
          'latitude': station['lat'],
          'longitude': station['lng'],
          'epicentralDistanceKm': distance,
          'pairedEpicentralMagnitude': magnitude,
          'geometricDepthSensitivityMagnitude': depthMagnitude,
          'isStrongest': peak.value == maximum,
        });
      }
      examinedFrames++;
      examinedStationPeaks += rows.length;
      lastStations = rows;
      frames.add({
        'observedAtJst': frame['observedAtJst'],
        'eventKey': candidate['eventKey'],
        'sourceLatitude': latitude,
        'sourceLongitude': longitude,
        'depthKm': depth,
        'multipleSources': multiple,
        'productionMagnitude': estimate['magnitude'],
        'peakNearestMagnitude': original.magnitude,
        'peakIntensity': maximum,
        'nearestDistanceKm': original.nearestStationDistanceKm,
        'strongestPaired': statistics(strongestMagnitudes),
        'allPaired': statistics(magnitudes),
        'depthSensitivity': statistics(depthMagnitudes),
        'distanceBands': {
          for (final entry in bands.entries) entry.key: statistics(entry.value),
        },
        'strongestStations': rows
            .where((row) => row['isStrongest'] == true)
            .toList(),
      });
    }
    cases.add({
      'id': replay['id'],
      'rawInputSha256': replay['rawInputSha256'],
      'referenceLabel': replay['referenceLabel'],
      'eventLabels': replay['eventLabels'],
      'missingFrameCount': replay['missingFrameCount'],
      'comparedFrames': frames.length,
      'first': frames.firstOrNull,
      'last': frames.lastOrNull,
      'lastStationPairs': lastStations,
      'frames': frames,
    });
  }
  if (sha256.convert(input.readAsBytesSync()).toString() != inputHash) {
    throw StateError('Input report was changed');
  }
  final result = {
    'diagnosticOnly': true,
    'feedsProduction': false,
    'readyForProduction': false,
    'labelsUsedInInference': false,
    'inputReportSha256': inputHash,
    'stationDbVersion': NiedStationDb.stationDbVersion,
    'stationDbSha256': sha256
        .convert(File('lib/models/nied_station_db.dart').readAsBytesSync())
        .toString(),
    'policy':
        'No fitted constants or station cuts. Existing formula and 20km floor retained.',
    'limits': [
      'Paired inversions are sensitivity tests, not validated JMA magnitudes.',
      'All-associated median includes weak and distant stations; no post-hoc station selection.',
      'Hypocentral substitution is geometry sensitivity only, not a calibrated depth correction.',
      'Existing source rounding and multi-source intensity branch retained.',
    ],
    'examinedFrames': examinedFrames,
    'examinedStationPeaks': examinedStationPeaks,
    'cases': cases,
  };
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(result)}\n',
    encoding: utf8,
  );
  stdout.writeln(
    jsonEncode({
      'output': output.path,
      'examinedFrames': examinedFrames,
      'examinedStationPeaks': examinedStationPeaks,
      'summaries': [
        for (final c in cases) {'id': c['id'], 'last': c['last']},
      ],
    }),
  );
}
