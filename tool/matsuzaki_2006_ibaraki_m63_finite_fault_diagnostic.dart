import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

const _targetEventId = '2016122821384904-36.7202-140.5742';

const _ibarakiM63Fault = Matsuzaki2006RectangularFaultPlane.fromPointOnPlane(
  id: 'jma-ibaraki-20161228-m63-near-revised-2017',
  referencePointRole: 'rupture_start',
  referenceLatitude: 36.7223,
  referenceLongitude: 140.5686,
  referenceDepthKm: 10.93,
  referenceAlongLengthKm: 22.5,
  referenceDownDipKm: 13.5,
  lengthKm: 30,
  widthKm: 24,
  upperEdgeAzimuthDegrees: 156,
  downDipAzimuthDegrees: 246,
  dipDegrees: 50,
);

void main(List<String> arguments) {
  final inputPath = _value(arguments, '--input');
  final selectionPath = _value(arguments, '--selection');
  final outputDirectory = Directory(
    _value(arguments, '--output-dir') ??
        '.dart_tool/matsuzaki_2006_ibaraki_m63_finite_fault_diagnostic',
  );
  if (inputPath == null || selectionPath == null) {
    stderr.writeln(
      'Usage: dart run '
      'tool/matsuzaki_2006_ibaraki_m63_finite_fault_diagnostic.dart '
      '--input <2016.json> --selection <frozen-selection.json> '
      '[--output-dir <directory>]',
    );
    exitCode = 64;
    return;
  }
  final missing = [
    inputPath,
    selectionPath,
  ].where((path) => !File(path).existsSync()).toList();
  if (missing.isNotEmpty) {
    stderr.writeln('Missing input files: ${missing.join(', ')}');
    exitCode = 66;
    return;
  }

  final dataset = _readJsonObject(inputPath);
  if (dataset['year'] != 2016) {
    throw FormatException('Expected JMA annual year 2016 in $inputPath.');
  }
  final selection = _readJsonObject(selectionPath);
  if (selection['selectedModel'] != 'fixedNearWeight75AllSource' ||
      selection['status'] != 'frozen_before_2018_evaluation') {
    throw const FormatException('Unexpected frozen model selection.');
  }
  final selectedCoefficients = _readFrozenCoefficients(selection);

  const evaluator = Matsuzaki2006JmaBaselineEvaluator();
  final baseline = evaluator.evaluate([dataset]);
  final matches = baseline.events
      .where((event) => event.eventId == _targetEventId)
      .toList();
  if (matches.length != 1) {
    throw StateError(
      'Expected one accepted $_targetEventId event, found ${matches.length}.',
    );
  }
  final event = matches.single;
  final nearStations =
      event.stationResiduals
          .where((station) => station.sourceDistanceKm < 30)
          .toList()
        ..sort(
          (left, right) =>
              left.sourceDistanceKm.compareTo(right.sourceDistanceKm),
        );
  if (nearStations.length != 20) {
    throw StateError(
      'Expected the audited count of 20 point-source nearfield stations, '
      'found ${nearStations.length}.',
    );
  }

  const publishedModel = Matsuzaki2006AttenuationModel();
  final selectedModel = Matsuzaki2006AttenuationModel(
    coefficients: selectedCoefficients,
  );
  final residuals = <String, List<double>>{
    'publishedPointSource': [],
    'publishedFiniteFault': [],
    'selectedPointSource': [],
    'selectedFiniteFault': [],
  };
  final pointDistances = <double>[];
  final faultDistances = <double>[];
  final finiteFaultDistanceExclusions = <Map<String, Object>>[];
  final stations = <Map<String, Object>>[];

  for (final station in nearStations) {
    final pointDistance = station.sourceDistanceKm;
    final faultDistance =
        Matsuzaki2006FiniteFaultGeometry.shortestDistanceToFaultUnion(
          faultPlanes: const [_ibarakiM63Fault],
          stationLatitude: station.latitude,
          stationLongitude: station.longitude,
        );
    pointDistances.add(pointDistance);
    faultDistances.add(faultDistance);

    final predictions = <String, double>{
      'publishedPointSource': publishedModel.predictIntensity(
        magnitude: event.magnitude,
        sourceDistanceKm: pointDistance,
        depthKm: event.depthKm,
      ),
      'selectedPointSource': selectedModel.predictIntensity(
        magnitude: event.magnitude,
        sourceDistanceKm: pointDistance,
        depthKm: event.depthKm,
      ),
    };
    final finiteFaultDistanceIsEvaluable =
        faultDistance >=
            Matsuzaki2006AttenuationModel.minimumSourceDistanceKm &&
        faultDistance <= Matsuzaki2006AttenuationModel.maximumSourceDistanceKm;
    if (finiteFaultDistanceIsEvaluable) {
      predictions.addAll({
        'publishedFiniteFault': publishedModel.predictIntensity(
          magnitude: event.magnitude,
          sourceDistanceKm: faultDistance,
          depthKm: event.depthKm,
        ),
        'selectedFiniteFault': selectedModel.predictIntensity(
          magnitude: event.magnitude,
          sourceDistanceKm: faultDistance,
          depthKm: event.depthKm,
        ),
      });
    } else {
      finiteFaultDistanceExclusions.add({
        'stationId': station.stationId,
        'finiteFaultDistanceKm': faultDistance,
        'reason': 'outside_published_source_distance_domain_1_to_500_km',
      });
    }
    final stationResiduals = <String, double>{
      for (final entry in predictions.entries)
        entry.key: station.observedIntensity - entry.value,
    };
    if (finiteFaultDistanceIsEvaluable) {
      for (final entry in stationResiduals.entries) {
        residuals[entry.key]!.add(entry.value);
      }
    }
    stations.add({
      'stationId': station.stationId,
      'latitude': station.latitude,
      'longitude': station.longitude,
      'observedIntensity': station.observedIntensity,
      'pointSourceDistanceKm': pointDistance,
      'finiteFaultDistanceKm': faultDistance,
      'finiteFaultEvaluationStatus': finiteFaultDistanceIsEvaluable
          ? 'evaluated'
          : 'outside_published_source_distance_domain',
      'predictions': predictions,
      'residuals': stationResiduals,
    });
  }

  final summaries = {
    for (final entry in residuals.entries)
      entry.key: Matsuzaki2006ResidualSummary.fromResiduals(entry.value),
  };
  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_ibaraki_m63_finite_fault_diagnostic_v1',
    'event': {
      'eventId': event.eventId,
      'originTime': event.originTime,
      'regionName': '茨城県北部',
      'regionNameSource':
          'preferredHypocenter.rawRegionHex decoded as Windows-31J/CP932',
      'latitude': event.latitude,
      'longitude': event.longitude,
      'catalogDepthKm': event.depthKm,
      'magnitude': event.magnitude,
      'magnitudeType': event.magnitudeType,
      'maximumIntensityClass': event.maximumIntensityClass,
      'acceptedStationCount': event.stationResiduals.length,
      'pointSourceNearfieldStationCount': nearStations.length,
      'finiteFaultEvaluableStationCount':
          nearStations.length - finiteFaultDistanceExclusions.length,
      'finiteFaultDistanceExclusionCount': finiteFaultDistanceExclusions.length,
    },
    'experimentPolicy': {
      'productionAdoption': false,
      'coefficientsRefitted': false,
      'modelReselected': false,
      'distanceOnlyComparison': true,
      'nearfieldDefinition': 'point_source_distance_below_30_km',
      'attenuationDepth': 'unchanged_jma_catalog_depth',
      'distanceFloorApplied': false,
      'residualComparisonPopulation':
          'same_paired_stations_with_finite_fault_distance_in_published_1_to_500_km_domain',
    },
    'sources': {
      'attenuationDistanceDefinition':
          'references/papers/2006_松崎久田福島_断層近傍まで適用可能な震度の距離減衰式の開発.pdf',
      'jmaSourceProcessReport':
          'references/papers/2016_JMA_Northern_Ibaraki_M63_source_process.pdf',
      'jmaSourceProcessData':
          'references/papers/2016_JMA_Northern_Ibaraki_M63_source_process_data.zip',
      'peerReviewedPaper':
          'references/papers/2023_EPS_2011_2016_Northern_Ibaraki_rupture_processes.pdf',
    },
    'faultParameterSemantics': {
      'reportedFaultPlaneCount': 1,
      'reportedStrikeDegrees': 156,
      'reportedDipDegrees': 50,
      'reportedRakeDegrees': -59,
      'reportedSubfaultLengthKm': 3,
      'reportedSubfaultWidthKm': 3,
      'reportedAlongStrikeSubfaultCount': 10,
      'reportedDownDipSubfaultCount': 8,
      'reportedLengthKm': 30,
      'reportedWidthKm': 24,
      'reportedRuptureStartSubfault': {
        'alongStrikeNumber': 8,
        'downDipNumber': 5,
      },
      'ruptureStartGridCentre': {
        'alongStrikeKmFromUpperEdgeStart': 22.5,
        'downDipKmFromUpperEdge': 13.5,
        'basis': 'centre_of_Xorg_8_Worg_5_in_reported_3_km_subfault_grid',
      },
      'reportedRuptureSpeedKmPerSecond': 2.6,
      'downDipAzimuthRule': 'reported_strike_plus_90_degrees_right_hand_rule',
      'catalogDepthAndRuptureStartDepthAreDistinct': true,
      'epsTwoPlaneGeometryUsedForDistance': false,
      'epsTwoPlaneExclusionReason':
          'paper_does_not_report_complete_numeric_plane_boundaries_and_reference_points',
    },
    'faultPlane': _ibarakiM63Fault.toJson(),
    'distanceSummaries': {
      'pointSource': _distanceSummary(pointDistances),
      'finiteFault': _distanceSummary(faultDistances),
      'finiteFaultMinusPoint': _differenceSummary(
        faultDistances,
        pointDistances,
      ),
    },
    'finiteFaultDistanceExclusions': finiteFaultDistanceExclusions,
    'residualSummaries': {
      for (final entry in summaries.entries) entry.key: entry.value.toJson(),
    },
    'absoluteResidualComparisons': {
      'publishedFiniteFaultVersusPoint': _absoluteResidualComparison(
        residuals['publishedFiniteFault']!,
        residuals['publishedPointSource']!,
      ),
      'selectedFiniteFaultVersusPoint': _absoluteResidualComparison(
        residuals['selectedFiniteFault']!,
        residuals['selectedPointSource']!,
      ),
    },
    'stations': stations,
  };

  outputDirectory.createSync(recursive: true);
  final jsonFile = File('${outputDirectory.path}/report.json');
  final markdownFile = File('${outputDirectory.path}/report.md');
  jsonFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    encoding: utf8,
  );
  markdownFile.writeAsStringSync(
    _toMarkdown(
      event: event,
      summaries: summaries,
      pointDistances: pointDistances,
      faultDistances: faultDistances,
      finiteFaultDistanceExclusions: finiteFaultDistanceExclusions,
      finiteFaultEvaluableStationCount:
          nearStations.length - finiteFaultDistanceExclusions.length,
    ),
    encoding: utf8,
  );
  stdout.writeln(
    'evaluated event=${event.eventId} nearStations=${nearStations.length}',
  );
  stdout.writeln('wrote ${markdownFile.path}');
  stdout.writeln('wrote ${jsonFile.path}');
}

Map<String, Object?> _readJsonObject(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync(encoding: utf8));
  if (decoded is! Map<String, Object?>) {
    throw FormatException('Expected a JSON object in $path.');
  }
  return decoded;
}

Matsuzaki2006AttenuationCoefficients _readFrozenCoefficients(
  Map<String, Object?> selection,
) {
  final raw = selection['coefficients'];
  if (raw is! Map<String, Object?>) {
    throw const FormatException('Frozen selection has no coefficients.');
  }
  return Matsuzaki2006AttenuationCoefficients(
    magnitudeCoefficient: _number(raw, 'magnitudeCoefficient'),
    logDistanceCoefficient: _number(raw, 'logDistanceCoefficient'),
    saturationCoefficient: _number(raw, 'saturationCoefficient'),
    saturationMagnitudeExponent: _number(raw, 'saturationMagnitudeExponent'),
    depthCoefficient: _number(raw, 'depthCoefficient'),
    intercept: _number(raw, 'intercept'),
  );
}

double _number(Map<String, Object?> values, String name) {
  final value = values[name];
  if (value is! num || !value.toDouble().isFinite) {
    throw FormatException('Invalid coefficient $name.');
  }
  return value.toDouble();
}

Map<String, Object> _distanceSummary(List<double> values) => {
  'count': values.length,
  'minimumKm': values.reduce((left, right) => left < right ? left : right),
  'meanKm': values.reduce((left, right) => left + right) / values.length,
  'maximumKm': values.reduce((left, right) => left > right ? left : right),
};

Map<String, Object> _differenceSummary(List<double> left, List<double> right) {
  final differences = [
    for (var index = 0; index < left.length; index++)
      left[index] - right[index],
  ];
  return {
    ..._distanceSummary(differences),
    'negativeCount': differences.where((value) => value < 0).length,
    'zeroCount': differences.where((value) => value == 0).length,
    'positiveCount': differences.where((value) => value > 0).length,
  };
}

Map<String, Object> _absoluteResidualComparison(
  List<double> replacement,
  List<double> pointSource,
) {
  var improves = 0;
  var unchanged = 0;
  var worsens = 0;
  for (var index = 0; index < replacement.length; index++) {
    final delta = replacement[index].abs() - pointSource[index].abs();
    if (delta < 0) {
      improves++;
    } else if (delta > 0) {
      worsens++;
    } else {
      unchanged++;
    }
  }
  return {
    'stationCount': replacement.length,
    'absoluteResidualImproves': improves,
    'absoluteResidualUnchanged': unchanged,
    'absoluteResidualWorsens': worsens,
  };
}

String _toMarkdown({
  required Matsuzaki2006EventBaseline event,
  required Map<String, Matsuzaki2006ResidualSummary> summaries,
  required List<double> pointDistances,
  required List<double> faultDistances,
  required List<Map<String, Object>> finiteFaultDistanceExclusions,
  required int finiteFaultEvaluableStationCount,
}) {
  final faultPlane = _ibarakiM63Fault.toJson();
  final buffer = StringBuffer()
    ..writeln('# Matsuzaki 2006 Northern Ibaraki M6.3 Finite-Fault Diagnostic')
    ..writeln()
    ..writeln(
      'Event `${event.eventId}` is evaluated with unchanged observations, '
      'catalog depth, and coefficients. Only distance X is replaced.',
    )
    ..writeln(
      'Residual summaries use the same $finiteFaultEvaluableStationCount '
      'paired stations whose finite-fault distance is within the published '
      '1-500 km domain. No distance floor is applied.',
    )
    ..writeln()
    ..writeln('## Fault Geometry')
    ..writeln()
    ..writeln('- Source: revised JMA near-field inversion data archive.')
    ..writeln('- Rectangle: 30 km x 24 km, strike 156 deg, dip 50 deg.')
    ..writeln(
      '- Rupture start: 36.7223 N, 140.5686 E, 10.93 km; '
      'centre of subfault Xorg=8, Worg=5.',
    )
    ..writeln(
      '- Inferred upper-edge depth: '
      '${_metric(faultPlane['inferredUpperEdgeDepthKm']! as double)} km.',
    )
    ..writeln()
    ..writeln('## Distance Summary')
    ..writeln()
    ..writeln('| Distance | Minimum km | Mean km | Maximum km |')
    ..writeln('|---|---:|---:|---:|');
  _writeDistanceRow(buffer, 'Point source', pointDistances);
  _writeDistanceRow(buffer, 'JMA finite rectangle', faultDistances);
  buffer
    ..writeln()
    ..writeln('## Residual Summary')
    ..writeln()
    ..writeln('| Coefficients and distance | Mean | MAE | RMS |')
    ..writeln('|---|---:|---:|---:|');
  for (final entry in summaries.entries) {
    buffer.writeln(
      '| ${entry.key} | ${_metric(entry.value.meanResidual)} | '
      '${_metric(entry.value.meanAbsoluteResidual)} | '
      '${_metric(entry.value.rootMeanSquareResidual)} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Outside Published Distance Domain')
    ..writeln();
  if (finiteFaultDistanceExclusions.isEmpty) {
    buffer.writeln('None.');
  } else {
    buffer
      ..writeln('| Station | Finite-fault distance km | Reason |')
      ..writeln('|---|---:|---|');
    for (final exclusion in finiteFaultDistanceExclusions) {
      buffer.writeln(
        '| ${exclusion['stationId']} | '
        '${_metric(exclusion['finiteFaultDistanceKm']! as double)} | '
        '${exclusion['reason']} |',
      );
    }
  }
  return buffer.toString();
}

void _writeDistanceRow(StringBuffer buffer, String name, List<double> values) {
  final summary = _distanceSummary(values);
  buffer.writeln(
    '| $name | ${_metric(summary['minimumKm']! as double)} | '
    '${_metric(summary['meanKm']! as double)} | '
    '${_metric(summary['maximumKm']! as double)} |',
  );
}

String _metric(double value) => value.toStringAsFixed(6);

String? _value(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  return index >= 0 && index + 1 < arguments.length
      ? arguments[index + 1]
      : null;
}
