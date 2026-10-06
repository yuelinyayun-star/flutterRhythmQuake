import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/source_estimation/srev_kaizou_magnitude.dart';

// Read an existing raw-replay audit. Coordinate substitution is a labeled
// counterfactual; no observation or production estimate is overwritten.
void main(List<String> args) {
  if (args.length != 1) {
    throw ArgumentError('Pass the original-window report.json path');
  }
  final report = jsonDecode(File(args.single).readAsStringSync()) as Map;
  final replay = (report['cases'] as List).single as Map;
  final frames = replay['frames'] as List;
  final frame = frames.cast<Map>().singleWhere(
    (f) => f['observedAtJst'] == '2026-10-03T21:46:20.000',
  );
  final estimate = frame['estimate'] as Map;
  final audit = frame['magnitudeAudit'] as Map;
  final published = audit['publishedDiagnostics'] as Map;
  final intensity = (published['srev_kaizou_magnitude_input_intensity'] as num)
      .toDouble();
  final rawIntensity = (audit['allActiveRawMaximumIntensity'] as num)
      .toDouble();
  SrevKaizouMagnitudeResult calculate(
    double latitude,
    double longitude,
    double value,
  ) {
    return calculateSrevKaizouMagnitude(
      sourceLatitude: latitude,
      sourceLongitude: longitude,
      inputIntensity: value,
      multipleSources: false,
    )!;
  }

  final baseline = calculate(
    (estimate['latitude'] as num).toDouble(),
    (estimate['longitude'] as num).toDouble(),
    intensity,
  );
  // Coordinates read from EQ's final report during the supplied replay.
  final withEqCoordinates = calculate(33.91, 134.88, intensity);
  final rawBaseline = calculate(
    (estimate['latitude'] as num).toDouble(),
    (estimate['longitude'] as num).toDouble(),
    rawIntensity,
  );
  final rawWithEqCoordinates = calculate(33.91, 134.88, rawIntensity);
  if (baseline.magnitude != withEqCoordinates.magnitude ||
      rawBaseline.magnitude != rawWithEqCoordinates.magnitude) {
    throw StateError(
      'Observed coordinate substitution unexpectedly changed magnitude',
    );
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'caseId': replay['id'],
      'inputFrameJst': frame['observedAtJst'],
      'observedEqFinal': {
        'latitude': 33.91,
        'longitude': 134.88,
        'magnitude': 3.0,
        'depthKm': 4,
      },
      'eqIsCatalogTruth': false,
      'coordinateSubstitutionIsCounterfactual': true,
      'baseline': baseline.toDiagnostics(),
      'withEqCoordinates': withEqCoordinates.toDiagnostics(),
      'continuousBaseline': rawBaseline.magnitude,
      'continuousWithEqCoordinates': rawWithEqCoordinates.magnitude,
      'identicalMagnitude': true,
      'productionChanged': false,
    }),
  );
}
