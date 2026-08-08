import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/calculator.dart';
import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

const _inputSpec = Matsuzaki2006ArchiveInputSpec(
  initialSearchRadiusKm: 100,
  maximumHorizontalSearchDistanceKm: 250,
  minimumSearchDepthKm: 5,
  maximumSearchDepthKm: 100,
  minimumObservations: 10,
  maximumObservations: 300,
  minimumInstrumentalIntensity: 0.5,
);

const _stationBiasTrainingYears = <int>[
  2010,
  2011,
  2012,
  2013,
  2014,
  2015,
  2016,
];

const _modelNames = <String>['published', 'finiteFaultSemanticFrozen2017'];

const _magnitudeSearchSpec = Matsuzaki2006ForwardSearchSpec(
  magnitudeScanStep: 0.1,
  refinementTolerance: 1e-7,
  objectiveTieTolerance: 1e-10,
  maximumRefinementIterations: 100,
);

const _neighborhoodRadiusDegrees = 0.25;
const _neighborhoodStepDegrees = 0.025;

void main(List<String> arguments) {
  final inputPath = _value(arguments, '--input');
  final noBiasReportPath = _value(arguments, '--no-bias-report');
  final stationBiasReportPath = _value(arguments, '--station-bias-report');
  final outputDirectoryPath =
      _value(arguments, '--output-dir') ??
      '.dart_tool/matsuzaki_2006_joint_station_bias_effect_diagnostic';
  final stationBiasK = _optionalInt(arguments, '--station-bias-k') ?? 2;
  final stationBiasMinimumEvents =
      _optionalInt(arguments, '--station-bias-min-events') ?? 2;
  final stationBiasInputDirectory =
      _value(arguments, '--station-bias-input-dir') ??
      'tmp/jma_intensity_nearfield_expansion';
  final detailedEventId = _value(arguments, '--detailed-event');

  if (inputPath == null ||
      noBiasReportPath == null ||
      stationBiasReportPath == null) {
    stderr.writeln(
      'Usage: dart run '
      'tool/matsuzaki_2006_joint_station_bias_effect_diagnostic.dart '
      '--input <annual.json> '
      '--no-bias-report <report.json> '
      '--station-bias-report <report.json> '
      '[--station-bias-k <count>] '
      '[--station-bias-min-events <count>] '
      '[--station-bias-input-dir <directory>] '
      '[--detailed-event <event-id>] '
      '[--output-dir <directory>]',
    );
    exitCode = 64;
    return;
  }
  if (stationBiasK < 0) {
    throw ArgumentError.value(
      stationBiasK,
      '--station-bias-k',
      'Must be non-negative.',
    );
  }
  if (stationBiasMinimumEvents < 2) {
    throw ArgumentError.value(
      stationBiasMinimumEvents,
      '--station-bias-min-events',
      'Must be at least two.',
    );
  }

  final annualDataset = _readJsonMap(inputPath);
  final noBiasReport = _readJsonMap(noBiasReportPath);
  final stationBiasReport = _readJsonMap(stationBiasReportPath);
  final noBiasEvents = _eventsById(noBiasReport);
  final stationBiasEvents = _eventsById(stationBiasReport);
  if (!noBiasEvents.keys.toSet().containsAll(stationBiasEvents.keys) ||
      !stationBiasEvents.keys.toSet().containsAll(noBiasEvents.keys)) {
    throw StateError(
      'No-bias and station-bias reports contain different events.',
    );
  }

  final models = <String, Matsuzaki2006AttenuationModel>{
    'published': const Matsuzaki2006AttenuationModel(),
    'finiteFaultSemanticFrozen2017': const Matsuzaki2006AttenuationModel(
      coefficients:
          Matsuzaki2006AttenuationCoefficients.finiteFaultSemanticFrozen2017,
    ),
  };
  final stationBiasModels = {
    for (final entry in models.entries)
      entry.key: _trainStationBiasModel(
        inputDirectory: stationBiasInputDirectory,
        model: entry.value,
        minimumTrainingEventCount: stationBiasMinimumEvents,
      ),
  };
  final shrinkage = Matsuzaki2006StationBiasShrinkage(
    pseudoEventCount: stationBiasK,
  );
  const inputBuilder = Matsuzaki2006ArchiveInversionInputBuilder();
  final rawEvents = _rawEventsById(annualDataset);

  final eventDiagnostics = <Map<String, Object?>>[];
  for (final eventId in noBiasEvents.keys.toList()..sort()) {
    final rawEvent = rawEvents[eventId];
    if (rawEvent == null) {
      throw StateError('Event $eventId is missing from input dataset.');
    }
    final input = inputBuilder.build(rawEvent: rawEvent, spec: _inputSpec);
    if (!input.isReady) {
      throw StateError(
        'Event $eventId is not ready under the frozen input spec.',
      );
    }
    final noBiasEvent = noBiasEvents[eventId]!;
    final stationBiasEvent = stationBiasEvents[eventId]!;
    final modelDiagnostics = <String, Object?>{};
    for (final modelName in _modelNames) {
      modelDiagnostics[modelName] = _modelDiagnosticJson(
        modelName: modelName,
        model: models[modelName]!,
        input: input,
        observations: input.observations,
        stationBiasModel: stationBiasModels[modelName]!,
        shrinkage: shrinkage,
        noBiasModel: _modelResult(noBiasEvent, modelName),
        stationBiasModelResult: _modelResult(stationBiasEvent, modelName),
        includeDetailedResiduals: eventId == detailedEventId,
      );
    }
    eventDiagnostics.add({
      'eventId': eventId,
      'originTime': noBiasEvent['originTime'],
      'truth': noBiasEvent['truth'],
      'input': {
        'selectedObservationCount': input.observations.length,
        'domainSafeObservationCount': input.domainSafeObservationCount,
        'anchorLatitude': input.anchorLatitude,
        'anchorLongitude': input.anchorLongitude,
      },
      'models': modelDiagnostics,
    });
  }

  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_joint_station_bias_effect_diagnostic_v3',
    'inputPath': inputPath,
    'noBiasReportPath': noBiasReportPath,
    'stationBiasReportPath': stationBiasReportPath,
    'protocolStatus': stationBiasReport['protocolStatus'],
    'diagnosticBoundary':
        'This report compares existing no-bias and frozen station-bias joint '
        'evaluation outputs. It recomputes only selected-station correction '
        'coverage and correction distributions from unchanged input data.',
    'stationBias': {
      'trainingYears': _stationBiasTrainingYears,
      'minimumTrainingEventCount': stationBiasMinimumEvents,
      'pseudoEventCount': stationBiasK,
      'formula': 'model_prediction + b * n / (n + k)',
      'missingStationPolicy':
          'unavailable or coordinate-mismatched stations remain uncorrected',
    },
    'eventCount': eventDiagnostics.length,
    'modelSummaries': {
      for (final modelName in _modelNames)
        modelName: _modelSummary(eventDiagnostics, modelName),
    },
    'events': eventDiagnostics,
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
  stdout.writeln(jsonEncode(report['modelSummaries']));
  stdout.writeln('wrote ${jsonFile.path}');
  stdout.writeln('wrote ${markdownFile.path}');
}

Map<String, Object?> _modelDiagnosticJson({
  required String modelName,
  required Matsuzaki2006AttenuationModel model,
  required Matsuzaki2006ArchiveInversionInput input,
  required List<Matsuzaki2006IntensityObservation> observations,
  required Matsuzaki2006StationBiasModel stationBiasModel,
  required Matsuzaki2006StationBiasShrinkage shrinkage,
  required Map<String, Object?> noBiasModel,
  required Map<String, Object?> stationBiasModelResult,
  required bool includeDetailedResiduals,
}) {
  final correctionSummary = _correctionSummary(
    observations: observations,
    stationBiasModel: stationBiasModel,
    shrinkage: shrinkage,
  );
  final noBiasEpicentralError = _number(
    noBiasModel['epicentralErrorKmMaximumEquivalent'],
  );
  final stationBiasEpicentralError = _number(
    stationBiasModelResult['epicentralErrorKmMaximumEquivalent'],
  );
  final noBiasDepthError = _number(
    noBiasModel['depthAbsoluteErrorKmMaximumEquivalent'],
  );
  final stationBiasDepthError = _number(
    stationBiasModelResult['depthAbsoluteErrorKmMaximumEquivalent'],
  );
  final noBiasMagnitudeError = _number(
    noBiasModel['magnitudeAbsoluteErrorMaximumEquivalent'],
  );
  final stationBiasMagnitudeError = _number(
    stationBiasModelResult['magnitudeAbsoluteErrorMaximumEquivalent'],
  );
  return {
    'stationCorrection': correctionSummary.toJson(),
    'noBias': _compactResult(noBiasModel),
    'stationBias': _compactResult(stationBiasModelResult),
    'candidateMotion': _candidateMotion(noBiasModel, stationBiasModelResult),
    'candidateCrossScores': _candidateCrossScores(
      model: model,
      observations: observations,
      stationBiasModel: stationBiasModel,
      shrinkage: shrinkage,
      noBiasModel: noBiasModel,
      stationBiasModelResult: stationBiasModelResult,
      includeDetailedResiduals: includeDetailedResiduals,
    ),
    if (includeDetailedResiduals)
      'candidateNeighborhoods': _candidateNeighborhoods(
        input: input,
        model: model,
        observations: observations,
        stationBiasModel: stationBiasModel,
        shrinkage: shrinkage,
        noBiasModel: noBiasModel,
        stationBiasModelResult: stationBiasModelResult,
      ),
    'deltas': {
      'epicentralErrorKm': _difference(
        stationBiasEpicentralError,
        noBiasEpicentralError,
      ),
      'depthAbsoluteErrorKm': _difference(
        stationBiasDepthError,
        noBiasDepthError,
      ),
      'magnitudeAbsoluteError': _difference(
        stationBiasMagnitudeError,
        noBiasMagnitudeError,
      ),
      'intensityRms': _difference(
        _number(stationBiasModelResult['minimumIntensityRms']),
        _number(noBiasModel['minimumIntensityRms']),
      ),
      'elapsedMilliseconds': _difference(
        _number(stationBiasModelResult['elapsedMilliseconds']),
        _number(noBiasModel['elapsedMilliseconds']),
      ),
    },
    'classification': {
      'epicentralErrorChange': _changeLabel(
        noBiasEpicentralError,
        stationBiasEpicentralError,
      ),
      'noBiasStatus': noBiasModel['status'],
      'stationBiasStatus': stationBiasModelResult['status'],
      'noBiasHardBoundaryContacts': noBiasModel['hardBoundaryContacts'],
      'stationBiasHardBoundaryContacts':
          stationBiasModelResult['hardBoundaryContacts'],
    },
  };
}

Map<String, Object?> _candidateNeighborhoods({
  required Matsuzaki2006ArchiveInversionInput input,
  required Matsuzaki2006AttenuationModel model,
  required List<Matsuzaki2006IntensityObservation> observations,
  required Matsuzaki2006StationBiasModel stationBiasModel,
  required Matsuzaki2006StationBiasShrinkage shrinkage,
  required Map<String, Object?> noBiasModel,
  required Map<String, Object?> stationBiasModelResult,
}) {
  final noBiasScorer = Matsuzaki2006ForwardResidualScorer(model: model);
  final stationBiasScorer = Matsuzaki2006ForwardResidualScorer(
    model: model,
    stationBiasModel: stationBiasModel,
    stationBiasShrinkage: shrinkage,
  );
  return {
    'radiusDegrees': _neighborhoodRadiusDegrees,
    'stepDegrees': _neighborhoodStepDegrees,
    'noBiasBestCandidate': _candidateNeighborhood(
      candidate: _firstCandidate(noBiasModel['bestCandidates']),
      input: input,
      observations: observations,
      noBiasScorer: noBiasScorer,
      stationBiasScorer: stationBiasScorer,
    ),
    'stationBiasBestCandidate': _candidateNeighborhood(
      candidate: _firstCandidate(stationBiasModelResult['bestCandidates']),
      input: input,
      observations: observations,
      noBiasScorer: noBiasScorer,
      stationBiasScorer: stationBiasScorer,
    ),
  };
}

Map<String, Object?> _candidateNeighborhood({
  required Map<String, Object?>? candidate,
  required Matsuzaki2006ArchiveInversionInput input,
  required List<Matsuzaki2006IntensityObservation> observations,
  required Matsuzaki2006ForwardResidualScorer noBiasScorer,
  required Matsuzaki2006ForwardResidualScorer stationBiasScorer,
}) {
  final anchor = _sourceFromCandidate(candidate);
  if (anchor == null) {
    return {'available': false, 'reason': 'no numeric best candidate'};
  }
  final noBias = _neighborhoodPath(
    anchor: anchor,
    input: input,
    observations: observations,
    scorer: noBiasScorer,
  );
  final stationBias = _neighborhoodPath(
    anchor: anchor,
    input: input,
    observations: observations,
    scorer: stationBiasScorer,
  );
  return {
    'available': true,
    'anchor': {
      'latitude': anchor.latitude,
      'longitude': anchor.longitude,
      'depthKm': anchor.depthKm,
    },
    'noBias': noBias,
    'stationBias': stationBias,
  };
}

Map<String, Object?> _neighborhoodPath({
  required Matsuzaki2006CandidateSource anchor,
  required Matsuzaki2006ArchiveInversionInput input,
  required List<Matsuzaki2006IntensityObservation> observations,
  required Matsuzaki2006ForwardResidualScorer scorer,
}) {
  final samples = <Map<String, Object?>>[];
  var legalGridPointCount = 0;
  var invalidScoreCount = 0;
  final stepCount = (_neighborhoodRadiusDegrees / _neighborhoodStepDegrees)
      .round();
  for (
    var latitudeIndex = -stepCount;
    latitudeIndex <= stepCount;
    latitudeIndex++
  ) {
    for (
      var longitudeIndex = -stepCount;
      longitudeIndex <= stepCount;
      longitudeIndex++
    ) {
      final source = Matsuzaki2006CandidateSource(
        latitude: anchor.latitude + latitudeIndex * _neighborhoodStepDegrees,
        longitude: anchor.longitude + longitudeIndex * _neighborhoodStepDegrees,
        depthKm: anchor.depthKm,
      );
      if (!_insideOriginalSearchDomain(source, input)) continue;
      legalGridPointCount++;
      final score = scorer.score(
        observations: observations,
        source: source,
        minimumObservations: _inputSpec.minimumObservations,
        searchSpec: _magnitudeSearchSpec,
      );
      if (!score.isValid || score.solutions.isEmpty) {
        invalidScoreCount++;
        continue;
      }
      final solution = score.solutions.first;
      samples.add({
        'latitude': source.latitude,
        'longitude': source.longitude,
        'depthKm': source.depthKm,
        'latitudeOffsetDegrees': latitudeIndex * _neighborhoodStepDegrees,
        'longitudeOffsetDegrees': longitudeIndex * _neighborhoodStepDegrees,
        'isSampleGridEdge':
            latitudeIndex.abs() == stepCount ||
            longitudeIndex.abs() == stepCount,
        'magnitude': solution.magnitude,
        'intensityRms': solution.intensityRms,
      });
    }
  }
  samples.sort(
    (left, right) => (left['intensityRms']! as double).compareTo(
      right['intensityRms']! as double,
    ),
  );
  final anchorSample = samples.where(
    (sample) =>
        sample['latitudeOffsetDegrees'] == 0 &&
        sample['longitudeOffsetDegrees'] == 0,
  );
  final anchorRms = anchorSample.isEmpty
      ? null
      : anchorSample.first['intensityRms']! as double;
  final minimumRms = samples.isEmpty
      ? null
      : samples.first['intensityRms']! as double;
  return {
    'legalGridPointCount': legalGridPointCount,
    'validScoreCount': samples.length,
    'invalidScoreCount': invalidScoreCount,
    'anchorRms': anchorRms,
    'minimumRms': minimumRms,
    'minimumRmsDeltaFromAnchor': _difference(minimumRms, anchorRms),
    'minimumAtSampleGridEdge': samples.isNotEmpty
        ? samples.first['isSampleGridEdge']
        : null,
    'bestSamples': samples.take(12).toList(),
  };
}

bool _insideOriginalSearchDomain(
  Matsuzaki2006CandidateSource source,
  Matsuzaki2006ArchiveInversionInput input,
) {
  final bounds = input.hardHorizontalBounds;
  final radial = input.radialSearchConstraint;
  if (bounds == null || radial == null) return false;
  const tolerance = 1e-9;
  if (source.latitude < bounds.minimumLatitude - tolerance ||
      source.latitude > bounds.maximumLatitude + tolerance ||
      source.longitude < bounds.minimumLongitude - tolerance ||
      source.longitude > bounds.maximumLongitude + tolerance) {
    return false;
  }
  return QuakeCalculator.haversineDistance(
        radial.centerLatitude,
        radial.centerLongitude,
        source.latitude,
        source.longitude,
      ) <=
      radial.maximumEpicentralDistanceKm + tolerance;
}

Map<String, Object?> _candidateCrossScores({
  required Matsuzaki2006AttenuationModel model,
  required List<Matsuzaki2006IntensityObservation> observations,
  required Matsuzaki2006StationBiasModel stationBiasModel,
  required Matsuzaki2006StationBiasShrinkage shrinkage,
  required Map<String, Object?> noBiasModel,
  required Map<String, Object?> stationBiasModelResult,
  required bool includeDetailedResiduals,
}) {
  final noBiasScorer = Matsuzaki2006ForwardResidualScorer(model: model);
  final stationBiasScorer = Matsuzaki2006ForwardResidualScorer(
    model: model,
    stationBiasModel: stationBiasModel,
    stationBiasShrinkage: shrinkage,
  );
  final stationCorrections = _stationCorrections(
    observations: observations,
    stationBiasModel: stationBiasModel,
    shrinkage: shrinkage,
  );
  return {
    'noBiasBestCandidate': _scoreCandidateUnderBothPaths(
      candidate: _firstCandidate(noBiasModel['bestCandidates']),
      observations: observations,
      noBiasScorer: noBiasScorer,
      stationBiasScorer: stationBiasScorer,
      stationCorrections: stationCorrections,
      includeDetailedResiduals: includeDetailedResiduals,
    ),
    'stationBiasBestCandidate': _scoreCandidateUnderBothPaths(
      candidate: _firstCandidate(stationBiasModelResult['bestCandidates']),
      observations: observations,
      noBiasScorer: noBiasScorer,
      stationBiasScorer: stationBiasScorer,
      stationCorrections: stationCorrections,
      includeDetailedResiduals: includeDetailedResiduals,
    ),
  };
}

Map<String, Object?> _scoreCandidateUnderBothPaths({
  required Map<String, Object?>? candidate,
  required List<Matsuzaki2006IntensityObservation> observations,
  required Matsuzaki2006ForwardResidualScorer noBiasScorer,
  required Matsuzaki2006ForwardResidualScorer stationBiasScorer,
  required Map<String, double> stationCorrections,
  required bool includeDetailedResiduals,
}) {
  final source = _sourceFromCandidate(candidate);
  if (source == null) {
    return {'available': false, 'reason': 'no numeric best candidate'};
  }
  return {
    'available': true,
    'source': {
      'latitude': source.latitude,
      'longitude': source.longitude,
      'depthKm': source.depthKm,
    },
    'noBias': _scoreJson(
      noBiasScorer.score(
        observations: observations,
        source: source,
        minimumObservations: _inputSpec.minimumObservations,
        searchSpec: _magnitudeSearchSpec,
      ),
      stationCorrections: const {},
      includeDetailedResiduals: includeDetailedResiduals,
    ),
    'stationBias': _scoreJson(
      stationBiasScorer.score(
        observations: observations,
        source: source,
        minimumObservations: _inputSpec.minimumObservations,
        searchSpec: _magnitudeSearchSpec,
      ),
      stationCorrections: stationCorrections,
      includeDetailedResiduals: includeDetailedResiduals,
    ),
  };
}

Matsuzaki2006CandidateSource? _sourceFromCandidate(
  Map<String, Object?>? candidate,
) {
  if (candidate == null) return null;
  final latitude = _number(candidate['latitude']);
  final longitude = _number(candidate['longitude']);
  final depthKm = _number(candidate['depthKm']);
  if (latitude == null || longitude == null || depthKm == null) return null;
  return Matsuzaki2006CandidateSource(
    latitude: latitude,
    longitude: longitude,
    depthKm: depthKm,
  );
}

Map<String, double> _stationCorrections({
  required List<Matsuzaki2006IntensityObservation> observations,
  required Matsuzaki2006StationBiasModel stationBiasModel,
  required Matsuzaki2006StationBiasShrinkage shrinkage,
}) => {
  for (final observation in observations)
    if (stationBiasModel.estimates[observation.id] case final estimate?
        when estimate.latitude == observation.latitude &&
            estimate.longitude == observation.longitude)
      observation.id: shrinkage.apply(estimate),
};

Map<String, Object?> _scoreJson(
  Matsuzaki2006ForwardCandidateScore score, {
  required Map<String, double> stationCorrections,
  required bool includeDetailedResiduals,
}) => {
  'isValid': score.isValid,
  'invalidReason': score.invalidReason?.name,
  'solutions': [
    for (final solution in score.solutions)
      {
        'magnitude': solution.magnitude,
        'intensityRms': solution.intensityRms,
        'meanIntensityResidual': solution.meanIntensityResidual,
        if (includeDetailedResiduals)
          'residualSummary': _residualSummary(
            solution.stationResiduals,
            stationCorrections,
          ),
        if (includeDetailedResiduals)
          'largestSquaredResiduals': _largestSquaredResiduals(
            solution.stationResiduals,
            stationCorrections,
          ),
      },
  ],
};

Map<String, Object?> _residualSummary(
  List<Matsuzaki2006ForwardStationResidual> residuals,
  Map<String, double> stationCorrections,
) => {
  'stationCount': residuals.length,
  'meanStationCorrection': _mean([
    for (final residual in residuals)
      stationCorrections[residual.observationId] ?? 0,
  ]),
  'meanResidual': _mean([for (final residual in residuals) residual.residual]),
  'rms': math.sqrt(
    _mean([
      for (final residual in residuals) residual.residual * residual.residual,
    ]),
  ),
};

List<Map<String, Object?>> _largestSquaredResiduals(
  List<Matsuzaki2006ForwardStationResidual> residuals,
  Map<String, double> stationCorrections,
) {
  final entries =
      [
        for (final residual in residuals)
          {
            'stationId': residual.observationId,
            'sourceDistanceKm': residual.sourceDistanceKm,
            'observedIntensity': residual.observedIntensity,
            'predictedIntensity': residual.predictedIntensity,
            'residual': residual.residual,
            'squaredResidual': residual.residual * residual.residual,
            'stationCorrection':
                stationCorrections[residual.observationId] ?? 0,
          },
      ]..sort(
        (left, right) => (right['squaredResidual']! as double).compareTo(
          left['squaredResidual']! as double,
        ),
      );
  return entries.take(12).toList();
}

_StationCorrectionSummary _correctionSummary({
  required List<Matsuzaki2006IntensityObservation> observations,
  required Matsuzaki2006StationBiasModel stationBiasModel,
  required Matsuzaki2006StationBiasShrinkage shrinkage,
}) {
  var applied = 0;
  var unavailable = 0;
  var coordinateMismatch = 0;
  var positive = 0;
  var negative = 0;
  var zero = 0;
  final corrections = <double>[];
  final trainingEventCounts = <double>[];
  final extremeCorrections = <Map<String, Object?>>[];
  for (final observation in observations) {
    final estimate = stationBiasModel.estimates[observation.id];
    if (estimate == null) {
      unavailable++;
      continue;
    }
    if (estimate.latitude != observation.latitude ||
        estimate.longitude != observation.longitude) {
      coordinateMismatch++;
      continue;
    }
    applied++;
    final correction = shrinkage.apply(estimate);
    corrections.add(correction);
    trainingEventCounts.add(estimate.trainingEventCount.toDouble());
    if (correction > 1e-12) {
      positive++;
    } else if (correction < -1e-12) {
      negative++;
    } else {
      zero++;
    }
    extremeCorrections.add({
      'stationId': observation.id,
      'intensity': observation.intensity,
      'correction': correction,
      'trainingEventCount': estimate.trainingEventCount,
    });
  }
  extremeCorrections.sort((left, right) {
    final leftAbs = ((left['correction']! as num).toDouble()).abs();
    final rightAbs = ((right['correction']! as num).toDouble()).abs();
    final order = rightAbs.compareTo(leftAbs);
    return order != 0
        ? order
        : (left['stationId']! as String).compareTo(
            right['stationId']! as String,
          );
  });
  return _StationCorrectionSummary(
    observationCount: observations.length,
    appliedCount: applied,
    unavailableCount: unavailable,
    coordinateMismatchCount: coordinateMismatch,
    positiveCount: positive,
    negativeCount: negative,
    zeroCount: zero,
    corrections: corrections,
    trainingEventCounts: trainingEventCounts,
    largestAbsoluteCorrections: extremeCorrections.take(8).toList(),
  );
}

Map<String, Object?> _compactResult(Map<String, Object?> result) => {
  'status': result['status'],
  'isConverged': result['isConverged'],
  'hardBoundaryContacts': result['hardBoundaryContacts'],
  'candidateEvaluationCount': result['candidateEvaluationCount'],
  'elapsedMilliseconds': result['elapsedMilliseconds'],
  'minimumIntensityRms': result['minimumIntensityRms'],
  'epicentralErrorKmMaximumEquivalent':
      result['epicentralErrorKmMaximumEquivalent'],
  'depthAbsoluteErrorKmMaximumEquivalent':
      result['depthAbsoluteErrorKmMaximumEquivalent'],
  'magnitudeAbsoluteErrorMaximumEquivalent':
      result['magnitudeAbsoluteErrorMaximumEquivalent'],
  'bestCandidate': _firstCandidate(result['bestCandidates']),
  'resolutionEnvelope': result['resolutionEnvelope'],
};

Map<String, Object?>? _firstCandidate(Object? value) {
  if (value is! List || value.isEmpty || value.first is! Map) return null;
  return (value.first as Map).cast<String, Object?>();
}

Map<String, Object?> _candidateMotion(
  Map<String, Object?> noBias,
  Map<String, Object?> stationBias,
) {
  final noBiasCandidate = _firstCandidate(noBias['bestCandidates']);
  final stationBiasCandidate = _firstCandidate(stationBias['bestCandidates']);
  if (noBiasCandidate == null || stationBiasCandidate == null) {
    return {
      'available': false,
      'reason': 'one or both result sets have no best candidate',
    };
  }
  final noLatitude = _number(noBiasCandidate['latitude']);
  final noLongitude = _number(noBiasCandidate['longitude']);
  final biasLatitude = _number(stationBiasCandidate['latitude']);
  final biasLongitude = _number(stationBiasCandidate['longitude']);
  final noDepth = _number(noBiasCandidate['depthKm']);
  final biasDepth = _number(stationBiasCandidate['depthKm']);
  final noMagnitude = _number(noBiasCandidate['magnitude']);
  final biasMagnitude = _number(stationBiasCandidate['magnitude']);
  final noRms = _number(noBiasCandidate['intensityRms']);
  final biasRms = _number(stationBiasCandidate['intensityRms']);
  if ([
    noLatitude,
    noLongitude,
    biasLatitude,
    biasLongitude,
    noDepth,
    biasDepth,
    noMagnitude,
    biasMagnitude,
    noRms,
    biasRms,
  ].any((value) => value == null)) {
    return {
      'available': false,
      'reason': 'best candidate is missing a numeric field',
    };
  }
  return {
    'available': true,
    'noBiasBestCandidate': noBiasCandidate,
    'stationBiasBestCandidate': stationBiasCandidate,
    'latitudeDeltaDegrees': biasLatitude! - noLatitude!,
    'longitudeDeltaDegrees': biasLongitude! - noLongitude!,
    'horizontalMotionKm': QuakeCalculator.haversineDistance(
      noLatitude,
      noLongitude,
      biasLatitude,
      biasLongitude,
    ),
    'depthDeltaKm': biasDepth! - noDepth!,
    'magnitudeDelta': biasMagnitude! - noMagnitude!,
    'intensityRmsDelta': biasRms! - noRms!,
  };
}

Map<String, Object?> _modelSummary(
  List<Map<String, Object?>> events,
  String modelName,
) {
  final rows = [
    for (final event in events)
      _ModelRow.fromJson(
        eventId: event['eventId']! as String,
        json:
            ((event['models']! as Map<String, Object?>)[modelName]!
                as Map<String, Object?>),
      ),
  ];
  final improved = rows
      .where((row) => row.epicentralErrorChange == 'improved')
      .toList();
  final worsened = rows
      .where((row) => row.epicentralErrorChange == 'worsened')
      .toList();
  final unchanged = rows
      .where((row) => row.epicentralErrorChange == 'unchanged')
      .toList();
  final boundaryWorsened = rows
      .where(
        (row) =>
            !row.noBiasHardBoundaryReached &&
            row.stationBiasHardBoundaryReached,
      )
      .length;
  final boundaryImproved = rows
      .where(
        (row) =>
            row.noBiasHardBoundaryReached &&
            !row.stationBiasHardBoundaryReached,
      )
      .length;
  return {
    'eventCount': rows.length,
    'epicentralErrorChangeCounts': {
      'improved': improved.length,
      'worsened': worsened.length,
      'unchanged': unchanged.length,
    },
    'statusTransitionCounts': _sortedCounts({
      for (final key in rows.map((row) => row.statusTransition).toSet())
        key: rows.where((row) => row.statusTransition == key).length,
    }),
    'hardBoundaryTransitionCounts': {
      'enteredHardBoundary': boundaryWorsened,
      'leftHardBoundary': boundaryImproved,
      'unchanged': rows.length - boundaryWorsened - boundaryImproved,
    },
    'overall': _rowGroupSummary(rows),
    'improvedEvents': _rowGroupSummary(improved),
    'worsenedEvents': _rowGroupSummary(worsened),
    'correlations': {
      'deltaEpicentralErrorVsCorrectionCoverage': _pearson(
        rows,
        (row) => row.deltaEpicentralErrorKm,
        (row) => row.correctionCoverage,
      ),
      'deltaEpicentralErrorVsMeanCorrection': _pearson(
        rows,
        (row) => row.deltaEpicentralErrorKm,
        (row) => row.meanCorrection,
      ),
      'deltaEpicentralErrorVsMeanAbsoluteCorrection': _pearson(
        rows,
        (row) => row.deltaEpicentralErrorKm,
        (row) => row.meanAbsoluteCorrection,
      ),
      'deltaEpicentralErrorVsRmsCorrection': _pearson(
        rows,
        (row) => row.deltaEpicentralErrorKm,
        (row) => row.rmsCorrection,
      ),
    },
    'largestWorsenings': [
      for (final row
          in [...worsened]
            ..sort(
              (left, right) => right.deltaEpicentralErrorKm.compareTo(
                left.deltaEpicentralErrorKm,
              ),
            )
            ..take(10))
        row.toSummaryJson(),
    ],
    'largestImprovements': [
      for (final row
          in [...improved]
            ..sort(
              (left, right) => left.deltaEpicentralErrorKm.compareTo(
                right.deltaEpicentralErrorKm,
              ),
            )
            ..take(10))
        row.toSummaryJson(),
    ],
  };
}

Map<String, Object?> _rowGroupSummary(List<_ModelRow> rows) => {
  'count': rows.length,
  'deltaEpicentralErrorKmMedian': _percentile(
    rows.map((row) => row.deltaEpicentralErrorKm).toList(),
    0.5,
  ),
  'deltaDepthAbsoluteErrorKmMedian': _percentile(
    rows.map((row) => row.deltaDepthAbsoluteErrorKm).toList(),
    0.5,
  ),
  'deltaMagnitudeAbsoluteErrorMedian': _percentile(
    rows.map((row) => row.deltaMagnitudeAbsoluteError).toList(),
    0.5,
  ),
  'correctionCoverageMedian': _percentile(
    rows.map((row) => row.correctionCoverage).toList(),
    0.5,
  ),
  'meanCorrectionMedian': _percentile(
    rows.map((row) => row.meanCorrection).toList(),
    0.5,
  ),
  'meanAbsoluteCorrectionMedian': _percentile(
    rows.map((row) => row.meanAbsoluteCorrection).toList(),
    0.5,
  ),
  'rmsCorrectionMedian': _percentile(
    rows.map((row) => row.rmsCorrection).toList(),
    0.5,
  ),
  'horizontalMotionKmMedian': _percentile(
    rows.map((row) => row.horizontalMotionKm).toList(),
    0.5,
  ),
  'depthMotionKmMedian': _percentile(
    rows.map((row) => row.depthMotionKm).toList(),
    0.5,
  ),
  'magnitudeMotionMedian': _percentile(
    rows.map((row) => row.magnitudeMotion).toList(),
    0.5,
  ),
};

String _markdown(Map<String, Object?> report) {
  final summaries = report['modelSummaries']! as Map<String, Object?>;
  final buffer = StringBuffer()
    ..writeln('# Matsuzaki 2006 Joint Station-Bias Effect Diagnostic')
    ..writeln()
    ..writeln('Protocol status: `${report['protocolStatus']}`')
    ..writeln()
    ..writeln(report['diagnosticBoundary'])
    ..writeln();
  for (final modelName in _modelNames) {
    final summary = summaries[modelName]! as Map<String, Object?>;
    final counts =
        summary['epicentralErrorChangeCounts']! as Map<String, Object?>;
    final boundary =
        summary['hardBoundaryTransitionCounts']! as Map<String, Object?>;
    final overall = summary['overall']! as Map<String, Object?>;
    final improved = summary['improvedEvents']! as Map<String, Object?>;
    final worsened = summary['worsenedEvents']! as Map<String, Object?>;
    buffer
      ..writeln('## $modelName')
      ..writeln()
      ..writeln('| Metric | Value |')
      ..writeln('|---|---:|')
      ..writeln('| Events | ${summary['eventCount']} |')
      ..writeln('| Improved | ${counts['improved']} |')
      ..writeln('| Worsened | ${counts['worsened']} |')
      ..writeln('| Unchanged | ${counts['unchanged']} |')
      ..writeln(
        '| Entered hard boundary | ${boundary['enteredHardBoundary']} |',
      )
      ..writeln('| Left hard boundary | ${boundary['leftHardBoundary']} |')
      ..writeln(
        '| Overall median delta epicentral error km | '
        '${_format(overall['deltaEpicentralErrorKmMedian'])} |',
      )
      ..writeln(
        '| Overall median correction coverage | '
        '${_format(overall['correctionCoverageMedian'])} |',
      )
      ..writeln(
        '| Improved median mean abs correction | '
        '${_format(improved['meanAbsoluteCorrectionMedian'])} |',
      )
      ..writeln(
        '| Worsened median mean abs correction | '
        '${_format(worsened['meanAbsoluteCorrectionMedian'])} |',
      )
      ..writeln(
        '| Overall median candidate horizontal motion km | '
        '${_format(overall['horizontalMotionKmMedian'])} |',
      )
      ..writeln(
        '| Overall median candidate depth motion km | '
        '${_format(overall['depthMotionKmMedian'])} |',
      )
      ..writeln(
        '| Overall median candidate magnitude motion | '
        '${_format(overall['magnitudeMotionMedian'])} |',
      )
      ..writeln()
      ..writeln('### Largest Worsenings')
      ..writeln()
      ..writeln(
        '| Event | Delta epicenter km | Coverage | Mean corr | Mean abs corr | '
        'Candidate move km | Depth move km | Magnitude move | '
        'No-bias status | Bias status |',
      )
      ..writeln('|---|---:|---:|---:|---:|---:|---:|---:|---|---|');
    for (final row in summary['largestWorsenings']! as List<Object?>) {
      final item = row! as Map<String, Object?>;
      buffer.writeln(
        '| `${item['eventId']}` | ${_format(item['deltaEpicentralErrorKm'])} | '
        '${_format(item['correctionCoverage'])} | '
        '${_format(item['meanCorrection'])} | '
        '${_format(item['meanAbsoluteCorrection'])} | '
        '${_format(item['horizontalMotionKm'])} | '
        '${_format(item['depthMotionKm'])} | '
        '${_format(item['magnitudeMotion'])} | '
        '${item['noBiasStatus']} | ${item['stationBiasStatus']} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('### Largest Improvements')
      ..writeln()
      ..writeln(
        '| Event | Delta epicenter km | Coverage | Mean corr | Mean abs corr | '
        'Candidate move km | Depth move km | Magnitude move | '
        'No-bias status | Bias status |',
      )
      ..writeln('|---|---:|---:|---:|---:|---:|---:|---:|---|---|');
    for (final row in summary['largestImprovements']! as List<Object?>) {
      final item = row! as Map<String, Object?>;
      buffer.writeln(
        '| `${item['eventId']}` | ${_format(item['deltaEpicentralErrorKm'])} | '
        '${_format(item['correctionCoverage'])} | '
        '${_format(item['meanCorrection'])} | '
        '${_format(item['meanAbsoluteCorrection'])} | '
        '${_format(item['horizontalMotionKm'])} | '
        '${_format(item['depthMotionKm'])} | '
        '${_format(item['magnitudeMotion'])} | '
        '${item['noBiasStatus']} | ${item['stationBiasStatus']} |',
      );
    }
    buffer.writeln();
  }
  return buffer.toString();
}

Matsuzaki2006StationBiasModel _trainStationBiasModel({
  required String inputDirectory,
  required Matsuzaki2006AttenuationModel model,
  required int minimumTrainingEventCount,
}) {
  final trainer = Matsuzaki2006StationBiasTrainer();
  for (final year in _stationBiasTrainingYears) {
    final path = '$inputDirectory/jma_final_intensity_$year.json';
    final decoded = _readJsonMap(path);
    if ((decoded['year']! as num).toInt() != year) {
      throw FormatException('Invalid station-bias training input: $path');
    }
    final baseline = Matsuzaki2006JmaBaselineEvaluator(
      model: model,
    ).evaluate([decoded]);
    final semanticApplication =
        Matsuzaki2006SourceBackedDistanceOverrides.applyUnambiguousCalibrationOverrides(
          baseline.events,
          calibrationYears: {year},
          model: model,
        );
    trainer.addEvents(semanticApplication.events);
  }
  return trainer.build(minimumTrainingEventCount: minimumTrainingEventCount);
}

Map<String, Object?> _readJsonMap(String path) {
  final file = File(path);
  if (!file.existsSync()) throw StateError('Missing input file: $path');
  final decoded = jsonDecode(file.readAsStringSync(encoding: utf8));
  if (decoded is! Map<String, Object?>) {
    throw FormatException('Expected a JSON object: $path');
  }
  return decoded;
}

Map<String, Map<String, Object?>> _eventsById(Map<String, Object?> report) {
  final events = report['events'];
  if (events is! List<Object?>) {
    throw const FormatException('Report does not contain an events array.');
  }
  final byId = <String, Map<String, Object?>>{};
  for (final event in events) {
    if (event is! Map<String, Object?> || event['eventId'] is! String) {
      throw const FormatException('Invalid event record in report.');
    }
    final eventId = event['eventId']! as String;
    if (byId.containsKey(eventId)) {
      throw StateError('Duplicate event in report: $eventId');
    }
    byId[eventId] = event;
  }
  return byId;
}

Map<String, Map<String, Object?>> _rawEventsById(
  Map<String, Object?> annualDataset,
) {
  final rawEvents = annualDataset['events'];
  if (rawEvents is! List<Object?>) {
    throw const FormatException('Annual dataset does not contain events.');
  }
  final byId = <String, Map<String, Object?>>{};
  for (final rawEvent in rawEvents) {
    if (rawEvent is! Map<String, Object?>) continue;
    final eventId = rawEvent['eventId'];
    if (eventId is! String) continue;
    if (byId.containsKey(eventId)) {
      throw StateError('Duplicate event in annual input: $eventId');
    }
    byId[eventId] = rawEvent;
  }
  return byId;
}

Map<String, Object?> _modelResult(
  Map<String, Object?> event,
  String modelName,
) {
  final models = event['models'];
  if (models is! Map<String, Object?> ||
      models[modelName] is! Map<String, Object?>) {
    throw FormatException(
      'Missing model $modelName for event ${event['eventId']}.',
    );
  }
  return models[modelName]! as Map<String, Object?>;
}

double? _difference(double? left, double? right) {
  if (left == null || right == null) return null;
  return left - right;
}

String _changeLabel(double? before, double? after) {
  if (before == null || after == null) return 'missing';
  const tolerance = 1e-9;
  if (after + tolerance < before) return 'improved';
  if (before + tolerance < after) return 'worsened';
  return 'unchanged';
}

double? _number(Object? value) => value is num ? value.toDouble() : null;

String? _value(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  return index >= 0 && index + 1 < arguments.length
      ? arguments[index + 1]
      : null;
}

int? _optionalInt(List<String> arguments, String name) {
  final raw = _value(arguments, name);
  if (raw == null) return null;
  final value = int.tryParse(raw);
  if (value == null) throw FormatException('$name must be an integer.');
  return value;
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

double? _pearson(
  List<_ModelRow> rows,
  double Function(_ModelRow row) x,
  double Function(_ModelRow row) y,
) {
  if (rows.length < 2) return null;
  final xs = rows.map(x).toList();
  final ys = rows.map(y).toList();
  final meanX = xs.reduce((left, right) => left + right) / xs.length;
  final meanY = ys.reduce((left, right) => left + right) / ys.length;
  var covariance = 0.0;
  var xVariance = 0.0;
  var yVariance = 0.0;
  for (var index = 0; index < rows.length; index++) {
    final dx = xs[index] - meanX;
    final dy = ys[index] - meanY;
    covariance += dx * dy;
    xVariance += dx * dx;
    yVariance += dy * dy;
  }
  if (xVariance == 0 || yVariance == 0) return null;
  return covariance / math.sqrt(xVariance * yVariance);
}

Map<String, int> _sortedCounts(Map<String, int> counts) {
  final keys = counts.keys.toList()..sort();
  return {for (final key in keys) key: counts[key]!};
}

String _format(Object? value) {
  if (value == null) return '';
  if (value is num) return value.toStringAsFixed(3);
  return value.toString();
}

class _StationCorrectionSummary {
  const _StationCorrectionSummary({
    required this.observationCount,
    required this.appliedCount,
    required this.unavailableCount,
    required this.coordinateMismatchCount,
    required this.positiveCount,
    required this.negativeCount,
    required this.zeroCount,
    required this.corrections,
    required this.trainingEventCounts,
    required this.largestAbsoluteCorrections,
  });

  final int observationCount;
  final int appliedCount;
  final int unavailableCount;
  final int coordinateMismatchCount;
  final int positiveCount;
  final int negativeCount;
  final int zeroCount;
  final List<double> corrections;
  final List<double> trainingEventCounts;
  final List<Map<String, Object?>> largestAbsoluteCorrections;

  double get coverage =>
      observationCount == 0 ? 0 : appliedCount / observationCount;
  double get meanCorrection => _mean(corrections);
  double get meanAbsoluteCorrection =>
      _mean(corrections.map((value) => value.abs()).toList());
  double get rmsCorrection => corrections.isEmpty
      ? 0
      : math.sqrt(
          corrections
                  .map((value) => value * value)
                  .reduce((left, right) => left + right) /
              corrections.length,
        );

  Map<String, Object?> toJson() => {
    'observationCount': observationCount,
    'appliedCount': appliedCount,
    'unavailableCount': unavailableCount,
    'coordinateMismatchCount': coordinateMismatchCount,
    'coverage': coverage,
    'positiveCount': positiveCount,
    'negativeCount': negativeCount,
    'zeroCount': zeroCount,
    'meanCorrection': meanCorrection,
    'meanAbsoluteCorrection': meanAbsoluteCorrection,
    'rmsCorrection': rmsCorrection,
    'minimumCorrection': _percentile(corrections, 0),
    'maximumCorrection': _percentile(corrections, 1),
    'trainingEventCountMedian': _percentile(trainingEventCounts, 0.5),
    'largestAbsoluteCorrections': largestAbsoluteCorrections,
  };
}

double _mean(List<double> values) => values.isEmpty
    ? 0
    : values.reduce((left, right) => left + right) / values.length;

class _ModelRow {
  const _ModelRow({
    required this.eventId,
    required this.deltaEpicentralErrorKm,
    required this.deltaDepthAbsoluteErrorKm,
    required this.deltaMagnitudeAbsoluteError,
    required this.correctionCoverage,
    required this.meanCorrection,
    required this.meanAbsoluteCorrection,
    required this.rmsCorrection,
    required this.horizontalMotionKm,
    required this.depthMotionKm,
    required this.magnitudeMotion,
    required this.noBiasStatus,
    required this.stationBiasStatus,
    required this.noBiasHardBoundaryReached,
    required this.stationBiasHardBoundaryReached,
  });

  factory _ModelRow.fromJson({
    required String eventId,
    required Map<String, Object?> json,
  }) {
    final correction = json['stationCorrection']! as Map<String, Object?>;
    final motion = json['candidateMotion']! as Map<String, Object?>;
    final deltas = json['deltas']! as Map<String, Object?>;
    final classification = json['classification']! as Map<String, Object?>;
    final noBiasContacts =
        classification['noBiasHardBoundaryContacts']! as List<Object?>;
    final stationBiasContacts =
        classification['stationBiasHardBoundaryContacts']! as List<Object?>;
    return _ModelRow(
      eventId: eventId,
      deltaEpicentralErrorKm:
          _number(deltas['epicentralErrorKm']) ?? double.nan,
      deltaDepthAbsoluteErrorKm:
          _number(deltas['depthAbsoluteErrorKm']) ?? double.nan,
      deltaMagnitudeAbsoluteError:
          _number(deltas['magnitudeAbsoluteError']) ?? double.nan,
      correctionCoverage: _number(correction['coverage']) ?? 0,
      meanCorrection: _number(correction['meanCorrection']) ?? 0,
      meanAbsoluteCorrection:
          _number(correction['meanAbsoluteCorrection']) ?? 0,
      rmsCorrection: _number(correction['rmsCorrection']) ?? 0,
      horizontalMotionKm: _number(motion['horizontalMotionKm']) ?? 0,
      depthMotionKm: (_number(motion['depthDeltaKm']) ?? 0).abs(),
      magnitudeMotion: (_number(motion['magnitudeDelta']) ?? 0).abs(),
      noBiasStatus: classification['noBiasStatus']! as String,
      stationBiasStatus: classification['stationBiasStatus']! as String,
      noBiasHardBoundaryReached: noBiasContacts.isNotEmpty,
      stationBiasHardBoundaryReached: stationBiasContacts.isNotEmpty,
    );
  }

  final String eventId;
  final double deltaEpicentralErrorKm;
  final double deltaDepthAbsoluteErrorKm;
  final double deltaMagnitudeAbsoluteError;
  final double correctionCoverage;
  final double meanCorrection;
  final double meanAbsoluteCorrection;
  final double rmsCorrection;
  final double horizontalMotionKm;
  final double depthMotionKm;
  final double magnitudeMotion;
  final String noBiasStatus;
  final String stationBiasStatus;
  final bool noBiasHardBoundaryReached;
  final bool stationBiasHardBoundaryReached;

  String get epicentralErrorChange {
    const tolerance = 1e-9;
    if (deltaEpicentralErrorKm < -tolerance) return 'improved';
    if (deltaEpicentralErrorKm > tolerance) return 'worsened';
    return 'unchanged';
  }

  String get statusTransition => '$noBiasStatus->$stationBiasStatus';

  Map<String, Object?> toSummaryJson() => {
    'eventId': eventId,
    'deltaEpicentralErrorKm': deltaEpicentralErrorKm,
    'deltaDepthAbsoluteErrorKm': deltaDepthAbsoluteErrorKm,
    'deltaMagnitudeAbsoluteError': deltaMagnitudeAbsoluteError,
    'correctionCoverage': correctionCoverage,
    'meanCorrection': meanCorrection,
    'meanAbsoluteCorrection': meanAbsoluteCorrection,
    'rmsCorrection': rmsCorrection,
    'horizontalMotionKm': horizontalMotionKm,
    'depthMotionKm': depthMotionKm,
    'magnitudeMotion': magnitudeMotion,
    'noBiasStatus': noBiasStatus,
    'stationBiasStatus': stationBiasStatus,
  };
}
