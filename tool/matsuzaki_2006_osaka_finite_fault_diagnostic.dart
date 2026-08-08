import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

const _targetEventId = '2018061807583414-34.8443-135.6217';

const _singleFault = Matsuzaki2006RectangularFaultPlane(
  id: 'gnss-single-fault',
  upperEdgeStartLatitude: 34.837,
  upperEdgeStartLongitude: 135.603,
  upperEdgeDepthKm: 7.2,
  lengthKm: 4,
  widthKm: 4,
  upperEdgeAzimuthDegrees: 49,
  downDipAzimuthDegrees: 139,
  dipDegrees: 73,
);

const _doubleFaultStrikeSlip = Matsuzaki2006RectangularFaultPlane(
  id: 'double-fault-strike-slip',
  upperEdgeStartLatitude: 34.837,
  upperEdgeStartLongitude: 135.602,
  upperEdgeDepthKm: 6.1,
  lengthKm: 4,
  widthKm: 4,
  upperEdgeAzimuthDegrees: 52,
  downDipAzimuthDegrees: 142,
  dipDegrees: 77,
);

const _doubleFaultReverse = Matsuzaki2006RectangularFaultPlane(
  id: 'double-fault-reverse',
  upperEdgeStartLatitude: 34.837,
  upperEdgeStartLongitude: 135.600,
  upperEdgeDepthKm: 9.6,
  lengthKm: 4,
  widthKm: 4,
  upperEdgeAzimuthDegrees: 351,
  downDipAzimuthDegrees: 81,
  dipDegrees: 50,
);

void main(List<String> arguments) {
  final inputPath = _value(arguments, '--input');
  final selectionPath = _value(arguments, '--selection');
  final outputDirectory = Directory(
    _value(arguments, '--output-dir') ??
        '.dart_tool/matsuzaki_2006_osaka_finite_fault_diagnostic',
  );
  if (inputPath == null || selectionPath == null) {
    stderr.writeln(
      'Usage: dart run '
      'tool/matsuzaki_2006_osaka_finite_fault_diagnostic.dart '
      '--input <2018.json> --selection <frozen-selection.json> '
      '--allow-opened-2018 [--output-dir <directory>]',
    );
    exitCode = 64;
    return;
  }
  if (!arguments.contains('--allow-opened-2018')) {
    stderr.writeln(
      'Refusing to read the opened 2018 audit year without explicit '
      '--allow-opened-2018.',
    );
    exitCode = 65;
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
  if (dataset['year'] != 2018) {
    throw FormatException('Expected the opened audit year 2018 in $inputPath.');
  }
  final selection = _readJsonObject(selectionPath);
  final selectedModelName = selection['selectedModel'];
  if (selectedModelName != 'fixedNearWeight75AllSource' ||
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
  if (nearStations.length != 98) {
    throw StateError(
      'Expected the frozen-report count of 98 nearfield stations, '
      'found ${nearStations.length}.',
    );
  }

  const publishedModel = Matsuzaki2006AttenuationModel();
  final selectedModel = Matsuzaki2006AttenuationModel(
    coefficients: selectedCoefficients,
  );
  final residuals = <String, List<double>>{
    'publishedPointSource': [],
    'publishedSingleFault': [],
    'publishedDoubleFault': [],
    'selectedPointSource': [],
    'selectedSingleFault': [],
    'selectedDoubleFault': [],
  };
  final pointDistances = <double>[];
  final singleFaultDistances = <double>[];
  final doubleFaultDistances = <double>[];
  final stations = <Map<String, Object>>[];

  for (final station in nearStations) {
    final pointDistance = station.sourceDistanceKm;
    final singleFaultDistance =
        Matsuzaki2006FiniteFaultGeometry.shortestDistanceToFaultUnion(
          faultPlanes: const [_singleFault],
          stationLatitude: station.latitude,
          stationLongitude: station.longitude,
        );
    final doubleFaultDistance =
        Matsuzaki2006FiniteFaultGeometry.shortestDistanceToFaultUnion(
          faultPlanes: const [_doubleFaultStrikeSlip, _doubleFaultReverse],
          stationLatitude: station.latitude,
          stationLongitude: station.longitude,
        );
    pointDistances.add(pointDistance);
    singleFaultDistances.add(singleFaultDistance);
    doubleFaultDistances.add(doubleFaultDistance);

    final predictions = <String, double>{
      'publishedPointSource': publishedModel.predictIntensity(
        magnitude: event.magnitude,
        sourceDistanceKm: pointDistance,
        depthKm: event.depthKm,
      ),
      'publishedSingleFault': publishedModel.predictIntensity(
        magnitude: event.magnitude,
        sourceDistanceKm: singleFaultDistance,
        depthKm: event.depthKm,
      ),
      'publishedDoubleFault': publishedModel.predictIntensity(
        magnitude: event.magnitude,
        sourceDistanceKm: doubleFaultDistance,
        depthKm: event.depthKm,
      ),
      'selectedPointSource': selectedModel.predictIntensity(
        magnitude: event.magnitude,
        sourceDistanceKm: pointDistance,
        depthKm: event.depthKm,
      ),
      'selectedSingleFault': selectedModel.predictIntensity(
        magnitude: event.magnitude,
        sourceDistanceKm: singleFaultDistance,
        depthKm: event.depthKm,
      ),
      'selectedDoubleFault': selectedModel.predictIntensity(
        magnitude: event.magnitude,
        sourceDistanceKm: doubleFaultDistance,
        depthKm: event.depthKm,
      ),
    };
    final stationResiduals = <String, double>{
      for (final entry in predictions.entries)
        entry.key: station.observedIntensity - entry.value,
    };
    for (final entry in stationResiduals.entries) {
      residuals[entry.key]!.add(entry.value);
    }
    stations.add({
      'stationId': station.stationId,
      'latitude': station.latitude,
      'longitude': station.longitude,
      'observedIntensity': station.observedIntensity,
      'pointSourceDistanceKm': pointDistance,
      'singleFaultDistanceKm': singleFaultDistance,
      'doubleFaultDistanceKm': doubleFaultDistance,
      'predictions': predictions,
      'residuals': stationResiduals,
    });
  }

  final summaries = {
    for (final entry in residuals.entries)
      entry.key: Matsuzaki2006ResidualSummary.fromResiduals(entry.value),
  };
  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_osaka_finite_fault_diagnostic_v1',
    'event': {
      'eventId': event.eventId,
      'originTime': event.originTime,
      'regionName': '大阪府北部',
      'latitude': event.latitude,
      'longitude': event.longitude,
      'depthKm': event.depthKm,
      'magnitude': event.magnitude,
      'magnitudeType': event.magnitudeType,
      'nearfieldStationCount': nearStations.length,
    },
    'experimentPolicy': {
      'productionAdoption': false,
      'coefficientsRefitted': false,
      'modelReselected': false,
      'frozenModel': selectedModelName,
      'distanceOnlyComparison': true,
      'nearfieldDefinition': 'point_source_distance_below_30_km',
    },
    'sources': {
      'attenuationDistanceDefinition':
          'references/papers/2006_松崎久田福島_断層近傍まで適用可能な震度の距離減衰式の開発.pdf',
      'singleAndDoubleRectangles':
          'references/papers/2020_DPRI_2018_northern_Osaka_crustal_deformation_fault_model.pdf',
      'twoFaultSeismologicalSupport':
          'references/papers/2019_Kato_Ueda_2018_northern_Osaka_source_fault_model_EPS.pdf',
    },
    'faultParameterSemantics': {
      'reportedReferencePoint': 'northern_upper_edge',
      'upperEdgeAzimuthRule':
          'reported_strike_direction_from_reference_point_confirmed_against_figure_5',
      'downDipAzimuthRule': 'reported_strike_plus_90_degrees_right_hand_rule',
      'singleReported': {
        'strikeDegrees': 49,
        'dipDegrees': 73,
        'rakeDegrees': 152,
        'slipMetres': 0.30,
        'momentMagnitude': 5.38,
      },
      'doubleStrikeSlipReported': {
        'strikeDegrees': 52,
        'dipDegrees': 77,
        'rakeDegrees': 151,
        'slipMetres': 0.24,
      },
      'doubleReverseReported': {
        'strikeDegrees': 351,
        'dipDegrees': 50,
        'rakeDegrees': 90,
        'slipMetres': 0.13,
      },
      'doubleTotalMomentMagnitude': 5.41,
    },
    'faultPlanes': {
      'single': [_singleFault.toJson()],
      'double': [_doubleFaultStrikeSlip.toJson(), _doubleFaultReverse.toJson()],
    },
    'distanceSummaries': {
      'pointSource': _distanceSummary(pointDistances),
      'singleFault': _distanceSummary(singleFaultDistances),
      'doubleFault': _distanceSummary(doubleFaultDistances),
      'singleMinusPoint': _differenceSummary(
        singleFaultDistances,
        pointDistances,
      ),
      'doubleMinusPoint': _differenceSummary(
        doubleFaultDistances,
        pointDistances,
      ),
    },
    'residualSummaries': {
      for (final entry in summaries.entries) entry.key: entry.value.toJson(),
    },
    'absoluteResidualComparisons': {
      'publishedSingleVersusPoint': _absoluteResidualComparison(
        residuals['publishedSingleFault']!,
        residuals['publishedPointSource']!,
      ),
      'publishedDoubleVersusPoint': _absoluteResidualComparison(
        residuals['publishedDoubleFault']!,
        residuals['publishedPointSource']!,
      ),
      'selectedSingleVersusPoint': _absoluteResidualComparison(
        residuals['selectedSingleFault']!,
        residuals['selectedPointSource']!,
      ),
      'selectedDoubleVersusPoint': _absoluteResidualComparison(
        residuals['selectedDoubleFault']!,
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
      singleFaultDistances: singleFaultDistances,
      doubleFaultDistances: doubleFaultDistances,
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
    'replacementRms': Matsuzaki2006ResidualSummary.fromResiduals(
      replacement,
    ).rootMeanSquareResidual,
    'pointSourceRms': Matsuzaki2006ResidualSummary.fromResiduals(
      pointSource,
    ).rootMeanSquareResidual,
  };
}

String _toMarkdown({
  required Matsuzaki2006EventBaseline event,
  required Map<String, Matsuzaki2006ResidualSummary> summaries,
  required List<double> pointDistances,
  required List<double> singleFaultDistances,
  required List<double> doubleFaultDistances,
}) {
  final buffer = StringBuffer()
    ..writeln('# Matsuzaki 2006 Osaka Finite-Fault Diagnostic')
    ..writeln()
    ..writeln(
      'Event `${event.eventId}` is evaluated with fixed observations and fixed '
      'coefficients. No coefficient fitting or model reselection is performed.',
    )
    ..writeln()
    ..writeln('## Distance Summary')
    ..writeln()
    ..writeln('| Distance | Minimum km | Mean km | Maximum km |')
    ..writeln('|---|---:|---:|---:|');
  _writeDistanceRow(buffer, 'Point source', pointDistances);
  _writeDistanceRow(buffer, 'Single rectangle', singleFaultDistances);
  _writeDistanceRow(buffer, 'Double rectangle', doubleFaultDistances);
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
