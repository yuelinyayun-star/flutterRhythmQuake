import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

const _trainingYears = <int>[2010, 2011, 2012, 2013, 2014, 2015, 2016];
const _validationYear = 2017;
const _frozenReuseYears = <int>[2018, 2019];
const _candidateMinimumTrainingEvents = <int>[2, 5, 10, 20];
const _selectionTolerance = 1e-12;

void main(List<String> arguments) {
  final inputDirectory =
      _value(arguments, '--input-dir') ??
      'tmp/jma_intensity_nearfield_expansion';
  final outputDirectory = Directory(
    _value(arguments, '--output-dir') ??
        '.dart_tool/matsuzaki_2006_station_bias_diagnostic_2010_2019',
  );
  final pseudoEventCount = _intValue(arguments, '--pseudo-event-count') ?? 0;
  if (pseudoEventCount < 0) {
    stderr.writeln('--pseudo-event-count must be non-negative.');
    exitCode = 64;
    return;
  }

  final years = [..._trainingYears, _validationYear, ..._frozenReuseYears];
  final inputPaths = {
    for (final year in years)
      year: '$inputDirectory/jma_final_intensity_$year.json',
  };
  final missing = inputPaths.values
      .where((path) => !File(path).existsSync())
      .toList();
  if (missing.isNotEmpty) {
    stderr.writeln('Missing input files: ${missing.join(', ')}');
    exitCode = 66;
    return;
  }

  final runs = <_ModelDiagnosticRun>[
    _ModelDiagnosticRun(
      name: 'published',
      model: const Matsuzaki2006AttenuationModel(),
      pseudoEventCount: pseudoEventCount,
    ),
    _ModelDiagnosticRun(
      name: 'finiteFaultSemanticFrozen2017',
      model: const Matsuzaki2006AttenuationModel(
        coefficients:
            Matsuzaki2006AttenuationCoefficients.finiteFaultSemanticFrozen2017,
      ),
      pseudoEventCount: pseudoEventCount,
    ),
  ];

  for (final year in _trainingYears) {
    stdout.writeln('training year $year...');
    final dataset = _readAnnualDataset(inputPaths[year]!, year);
    for (final run in runs) {
      final baseline = Matsuzaki2006JmaBaselineEvaluator(
        model: run.model,
      ).evaluate([dataset]);
      final semanticApplication =
          Matsuzaki2006SourceBackedDistanceOverrides.applyUnambiguousCalibrationOverrides(
            baseline.events,
            calibrationYears: {year},
            model: run.model,
          );
      run.trainer.addEvents(semanticApplication.events);
    }
  }

  stdout.writeln('selecting on $_validationYear...');
  final validationDataset = _readAnnualDataset(
    inputPaths[_validationYear]!,
    _validationYear,
  );
  for (final run in runs) {
    final baseline = Matsuzaki2006JmaBaselineEvaluator(
      model: run.model,
    ).evaluate([validationDataset]);
    for (final minimumEvents in _candidateMinimumTrainingEvents) {
      final stationModel = run.trainer.build(
        minimumTrainingEventCount: minimumEvents,
      );
      final diagnostic = _diagnoseEvents(
        events: baseline.events,
        stationModel: stationModel,
        shrinkage: run.shrinkage,
      );
      run.validationCandidates[minimumEvents] = diagnostic;
    }
    run.selectValidatedCandidate();
    run.evaluations[_validationYear] = run.selectedStationModel == null
        ? null
        : _diagnoseEvents(
            events: baseline.events,
            stationModel: run.selectedStationModel!,
            shrinkage: run.shrinkage,
          );
  }

  for (final year in _frozenReuseYears) {
    stdout.writeln('frozen reuse year $year...');
    final dataset = _readAnnualDataset(inputPaths[year]!, year);
    for (final run in runs) {
      final baseline = Matsuzaki2006JmaBaselineEvaluator(
        model: run.model,
      ).evaluate([dataset]);
      final semanticApplication = _applyAvailableSourceBackedGeometry(
        events: baseline.events,
        year: year,
        model: run.model,
      );
      run.evaluations[year] = run.selectedStationModel == null
          ? null
          : _diagnoseEvents(
              events: semanticApplication.events,
              stationModel: run.selectedStationModel!,
              shrinkage: run.shrinkage,
            );
    }
  }

  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_station_bias_diagnostic_v1',
    'protocolStatus':
        'diagnostic_only_trained_2010_2016_selected_2017_frozen_reuse_2018_2019_not_blind',
    'inputDirectory': inputDirectory,
    'split': {
      'trainingYears': _trainingYears,
      'validationYear': _validationYear,
      'frozenReuseYears': _frozenReuseYears,
      'newFinalHoldoutOpened': false,
    },
    'diagnosticSemantics': {
      'purpose':
          'diagnose extreme station terms and worsened validation/reuse events',
      'notUsedForRefit': true,
      'eventMetric':
          'event_equal_centered_residual_rms_after_selected_station_correction',
      'stationContribution':
          'per_station_centered_squared_residual_delta_within_the_same_event',
      'negativeStationContribution':
          'correction_reduced_centered_squared_error',
      'positiveStationContribution':
          'correction_increased_centered_squared_error',
      'missingStationPolicy': 'retained unchanged and counted unavailable',
      'shrinkage': {
        'pseudoEventCount': pseudoEventCount,
        'formula':
            'station_bias * training_event_count / '
            '(training_event_count + pseudo_event_count)',
      },
      'predeclaredStrata': {
        'trainingEventCount': _trainingCountBinLabels,
        'stationStandardError': _standardErrorBinLabels,
        'absoluteStationBias': _absoluteBiasBinLabels,
        'sourceDistanceKm': _distanceBinLabels,
        'observedInstrumentalIntensity': _intensityBinLabels,
        'jmaThresholdProximity': _thresholdProximityBinLabels,
      },
    },
    'models': {for (final run in runs) run.name: run.toJson()},
  };

  outputDirectory.createSync(recursive: true);
  final jsonFile = File('${outputDirectory.path}/report.json');
  final markdownFile = File('${outputDirectory.path}/report.md');
  jsonFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    encoding: utf8,
  );
  markdownFile.writeAsStringSync(_toMarkdown(runs), encoding: utf8);
  for (final run in runs) {
    stdout.writeln(
      '${run.name}: selectedMinimumTrainingEvents='
      '${run.selectedMinimumTrainingEvents}, '
      'worsenedEvents=${run.totalWorsenedEventCount}',
    );
  }
  stdout.writeln('wrote ${markdownFile.path}');
  stdout.writeln('wrote ${jsonFile.path}');
}

class _ModelDiagnosticRun {
  _ModelDiagnosticRun({
    required this.name,
    required this.model,
    required this.pseudoEventCount,
  });

  final String name;
  final Matsuzaki2006AttenuationModel model;
  final int pseudoEventCount;
  late final Matsuzaki2006StationBiasShrinkage shrinkage =
      Matsuzaki2006StationBiasShrinkage(pseudoEventCount: pseudoEventCount);
  final Matsuzaki2006StationBiasTrainer trainer =
      Matsuzaki2006StationBiasTrainer();
  final Map<int, _DiagnosticResult> validationCandidates = {};
  final Map<int, _DiagnosticResult?> evaluations = {};
  int? selectedMinimumTrainingEvents;

  Matsuzaki2006StationBiasModel? get selectedStationModel {
    final selected = selectedMinimumTrainingEvents;
    return selected == null
        ? null
        : trainer.build(minimumTrainingEventCount: selected);
  }

  int get totalWorsenedEventCount => evaluations.values
      .whereType<_DiagnosticResult>()
      .fold(0, (sum, result) => sum + result.worsenedEvents.length);

  void selectValidatedCandidate() {
    final accepted = validationCandidates.entries.where((entry) {
      final summary = entry.value.summary;
      return summary.correctedEventEqualCenteredRms + _selectionTolerance <
          summary.baselineEventEqualCenteredRms;
    }).toList();
    accepted.sort((left, right) {
      final difference =
          left.value.summary.correctedEventEqualCenteredRms -
          right.value.summary.correctedEventEqualCenteredRms;
      if (difference.abs() <= _selectionTolerance) {
        return right.key.compareTo(left.key);
      }
      return difference < 0 ? -1 : 1;
    });
    selectedMinimumTrainingEvents = accepted.isEmpty
        ? null
        : accepted.first.key;
  }

  Map<String, Object?> toJson() => {
    'baseCoefficients': model.coefficients.toJson(),
    'training': {
      'acceptedEventCount': trainer.eventCount,
      'acceptedObservationCount': trainer.observationCount,
      'distinctStationCount': trainer.distinctStationCount,
    },
    'selection': {
      'candidateMinimumTrainingEventCounts': _candidateMinimumTrainingEvents,
      'selectedMinimumTrainingEventCount': selectedMinimumTrainingEvents,
      'validationCandidates': {
        for (final entry in validationCandidates.entries)
          entry.key.toString(): entry.value.summary.toJson(),
      },
    },
    'shrinkage': shrinkage.toJson(),
    'selectedStationModel': selectedStationModel?.toJson(),
    'diagnostics': {
      for (final year in [_validationYear, ..._frozenReuseYears])
        year.toString(): evaluations[year]?.toJson(),
    },
  };
}

class _DiagnosticResult {
  _DiagnosticResult({
    required this.summary,
    required this.strata,
    required this.extremeStationsByAbsoluteBias,
    required this.extremeStationsByStandardError,
    required this.worsenedEvents,
    required this.topAdverseStationApplications,
    required this.topHelpfulStationApplications,
  });

  final _EvaluationSummary summary;
  final Map<String, List<_StratumSummary>> strata;
  final List<Matsuzaki2006StationBiasEstimate> extremeStationsByAbsoluteBias;
  final List<Matsuzaki2006StationBiasEstimate> extremeStationsByStandardError;
  final List<_EventDiagnostic> worsenedEvents;
  final List<_StationApplicationDiagnostic> topAdverseStationApplications;
  final List<_StationApplicationDiagnostic> topHelpfulStationApplications;

  Map<String, Object?> toJson() => {
    'summary': summary.toJson(),
    'strata': {
      for (final entry in strata.entries)
        entry.key: [for (final value in entry.value) value.toJson()],
    },
    'extremeStationsByAbsoluteBias': [
      for (final station in extremeStationsByAbsoluteBias) station.toJson(),
    ],
    'extremeStationsByStandardError': [
      for (final station in extremeStationsByStandardError) station.toJson(),
    ],
    'worsenedEvents': [for (final event in worsenedEvents) event.toJson()],
    'topAdverseStationApplications': [
      for (final station in topAdverseStationApplications) station.toJson(),
    ],
    'topHelpfulStationApplications': [
      for (final station in topHelpfulStationApplications) station.toJson(),
    ],
  };
}

class _EvaluationSummary {
  const _EvaluationSummary({
    required this.eventCount,
    required this.observationCount,
    required this.correctionAppliedCount,
    required this.correctionUnavailableCount,
    required this.coordinateMismatchCount,
    required this.baselineEventEqualCenteredRms,
    required this.correctedEventEqualCenteredRms,
    required this.improvedEventCount,
    required this.worsenedEventCount,
    required this.unchangedEventCount,
  });

  final int eventCount;
  final int observationCount;
  final int correctionAppliedCount;
  final int correctionUnavailableCount;
  final int coordinateMismatchCount;
  final double baselineEventEqualCenteredRms;
  final double correctedEventEqualCenteredRms;
  final int improvedEventCount;
  final int worsenedEventCount;
  final int unchangedEventCount;

  double get coverage =>
      observationCount == 0 ? 0 : correctionAppliedCount / observationCount;

  double get fractionalImprovement => baselineEventEqualCenteredRms == 0
      ? 0
      : (baselineEventEqualCenteredRms - correctedEventEqualCenteredRms) /
            baselineEventEqualCenteredRms;

  Map<String, Object> toJson() => {
    'eventCount': eventCount,
    'observationCount': observationCount,
    'correctionAppliedCount': correctionAppliedCount,
    'correctionUnavailableCount': correctionUnavailableCount,
    'coordinateMismatchCount': coordinateMismatchCount,
    'correctionCoverage': coverage,
    'baselineEventEqualCenteredRms': baselineEventEqualCenteredRms,
    'correctedEventEqualCenteredRms': correctedEventEqualCenteredRms,
    'centeredMeanRmsFractionalImprovement': fractionalImprovement,
    'improvedEventCount': improvedEventCount,
    'worsenedEventCount': worsenedEventCount,
    'unchangedEventCount': unchangedEventCount,
  };
}

class _EventDiagnostic {
  _EventDiagnostic({
    required this.event,
    required this.baselineCenteredRms,
    required this.correctedCenteredRms,
    required this.baselineRawRms,
    required this.correctedRawRms,
    required this.correctionAppliedCount,
    required this.correctionUnavailableCount,
    required this.coordinateMismatchCount,
    required this.sourceDistanceSummary,
    required this.observedIntensitySummary,
    required this.adverseStations,
    required this.helpfulStations,
  });

  final Matsuzaki2006EventBaseline event;
  final double baselineCenteredRms;
  final double correctedCenteredRms;
  final double baselineRawRms;
  final double correctedRawRms;
  final int correctionAppliedCount;
  final int correctionUnavailableCount;
  final int coordinateMismatchCount;
  final _SimpleSummary sourceDistanceSummary;
  final _SimpleSummary observedIntensitySummary;
  final List<_StationApplicationDiagnostic> adverseStations;
  final List<_StationApplicationDiagnostic> helpfulStations;

  double get centeredRmsDelta => correctedCenteredRms - baselineCenteredRms;
  double get rawRmsDelta => correctedRawRms - baselineRawRms;

  Map<String, Object?> toJson() => {
    'eventId': event.eventId,
    'year': event.year,
    'originTime': event.originTime,
    'latitude': event.latitude,
    'longitude': event.longitude,
    'depthKm': event.depthKm,
    'magnitude': event.magnitude,
    'magnitudeType': event.magnitudeType,
    'maximumIntensityClass': event.maximumIntensityClass,
    'stationCount': event.stationResiduals.length,
    'correctionAppliedCount': correctionAppliedCount,
    'correctionUnavailableCount': correctionUnavailableCount,
    'coordinateMismatchCount': coordinateMismatchCount,
    'baselineCenteredRms': baselineCenteredRms,
    'correctedCenteredRms': correctedCenteredRms,
    'centeredRmsDelta': centeredRmsDelta,
    'baselineRawRms': baselineRawRms,
    'correctedRawRms': correctedRawRms,
    'rawRmsDelta': rawRmsDelta,
    'sourceDistanceKm': sourceDistanceSummary.toJson(),
    'observedInstrumentalIntensity': observedIntensitySummary.toJson(),
    'topAdverseStations': [
      for (final station in adverseStations) station.toJson(),
    ],
    'topHelpfulStations': [
      for (final station in helpfulStations) station.toJson(),
    ],
  };
}

class _StationApplicationDiagnostic {
  const _StationApplicationDiagnostic({
    required this.eventId,
    required this.year,
    required this.stationId,
    required this.latitude,
    required this.longitude,
    required this.sourceDistanceKm,
    required this.observedIntensity,
    required this.baselineResidual,
    required this.correctedResidual,
    required this.baselineCenteredResidual,
    required this.correctedCenteredResidual,
    required this.centeredSquaredDelta,
    required this.rawSquaredDelta,
    required this.stationBias,
    required this.appliedStationBias,
    required this.trainingEventCount,
    required this.stationStandardError,
  });

  final String eventId;
  final int year;
  final String stationId;
  final double latitude;
  final double longitude;
  final double sourceDistanceKm;
  final double observedIntensity;
  final double baselineResidual;
  final double correctedResidual;
  final double baselineCenteredResidual;
  final double correctedCenteredResidual;
  final double centeredSquaredDelta;
  final double rawSquaredDelta;
  final double stationBias;
  final double appliedStationBias;
  final int trainingEventCount;
  final double stationStandardError;

  Map<String, Object> toJson() => {
    'eventId': eventId,
    'year': year,
    'stationId': stationId,
    'latitude': latitude,
    'longitude': longitude,
    'sourceDistanceKm': sourceDistanceKm,
    'observedIntensity': observedIntensity,
    'baselineResidual': baselineResidual,
    'correctedResidual': correctedResidual,
    'baselineCenteredResidual': baselineCenteredResidual,
    'correctedCenteredResidual': correctedCenteredResidual,
    'centeredSquaredDelta': centeredSquaredDelta,
    'rawSquaredDelta': rawSquaredDelta,
    'stationBias': stationBias,
    'appliedStationBias': appliedStationBias,
    'trainingEventCount': trainingEventCount,
    'stationStandardError': stationStandardError,
  };
}

class _StratumAccumulator {
  var observationCount = 0;
  var appliedCount = 0;
  var unavailableCount = 0;
  var coordinateMismatchCount = 0;
  var baselineCenteredSquaredSum = 0.0;
  var correctedCenteredSquaredSum = 0.0;
  var centeredSquaredDeltaSum = 0.0;

  void add({
    required bool applied,
    required bool unavailable,
    required bool coordinateMismatch,
    required double baselineCenteredResidual,
    required double correctedCenteredResidual,
  }) {
    observationCount++;
    if (applied) appliedCount++;
    if (unavailable) unavailableCount++;
    if (coordinateMismatch) coordinateMismatchCount++;
    final baselineSquared = baselineCenteredResidual * baselineCenteredResidual;
    final correctedSquared =
        correctedCenteredResidual * correctedCenteredResidual;
    baselineCenteredSquaredSum += baselineSquared;
    correctedCenteredSquaredSum += correctedSquared;
    centeredSquaredDeltaSum += correctedSquared - baselineSquared;
  }

  _StratumSummary summary(String label) => _StratumSummary(
    label: label,
    observationCount: observationCount,
    appliedCount: appliedCount,
    unavailableCount: unavailableCount,
    coordinateMismatchCount: coordinateMismatchCount,
    baselineCenteredRms: observationCount == 0
        ? 0
        : math.sqrt(baselineCenteredSquaredSum / observationCount),
    correctedCenteredRms: observationCount == 0
        ? 0
        : math.sqrt(correctedCenteredSquaredSum / observationCount),
    centeredSquaredDeltaMean: observationCount == 0
        ? 0
        : centeredSquaredDeltaSum / observationCount,
  );
}

class _StratumSummary {
  const _StratumSummary({
    required this.label,
    required this.observationCount,
    required this.appliedCount,
    required this.unavailableCount,
    required this.coordinateMismatchCount,
    required this.baselineCenteredRms,
    required this.correctedCenteredRms,
    required this.centeredSquaredDeltaMean,
  });

  final String label;
  final int observationCount;
  final int appliedCount;
  final int unavailableCount;
  final int coordinateMismatchCount;
  final double baselineCenteredRms;
  final double correctedCenteredRms;
  final double centeredSquaredDeltaMean;

  double get coverage =>
      observationCount == 0 ? 0 : appliedCount / observationCount;

  Map<String, Object> toJson() => {
    'label': label,
    'observationCount': observationCount,
    'appliedCount': appliedCount,
    'unavailableCount': unavailableCount,
    'coordinateMismatchCount': coordinateMismatchCount,
    'coverage': coverage,
    'baselineCenteredRms': baselineCenteredRms,
    'correctedCenteredRms': correctedCenteredRms,
    'centeredSquaredDeltaMean': centeredSquaredDeltaMean,
  };
}

class _SimpleSummary {
  const _SimpleSummary({
    required this.count,
    required this.minimum,
    required this.median,
    required this.maximum,
    required this.mean,
  });

  factory _SimpleSummary.fromValues(Iterable<double> values) {
    final sorted = values.toList()..sort();
    if (sorted.isEmpty) {
      return const _SimpleSummary(
        count: 0,
        minimum: 0,
        median: 0,
        maximum: 0,
        mean: 0,
      );
    }
    return _SimpleSummary(
      count: sorted.length,
      minimum: sorted.first,
      median: _percentile(sorted, 0.5),
      maximum: sorted.last,
      mean: sorted.fold(0.0, (sum, value) => sum + value) / sorted.length,
    );
  }

  final int count;
  final double minimum;
  final double median;
  final double maximum;
  final double mean;

  Map<String, Object> toJson() => {
    'count': count,
    'minimum': minimum,
    'median': median,
    'maximum': maximum,
    'mean': mean,
  };
}

_DiagnosticResult _diagnoseEvents({
  required List<Matsuzaki2006EventBaseline> events,
  required Matsuzaki2006StationBiasModel stationModel,
  required Matsuzaki2006StationBiasShrinkage shrinkage,
}) {
  final eventDiagnostics = <_EventDiagnostic>[];
  final strata = <String, Map<String, _StratumAccumulator>>{
    'trainingEventCount': _newStrata(_trainingCountBinLabels),
    'stationStandardError': _newStrata(_standardErrorBinLabels),
    'absoluteStationBias': _newStrata(_absoluteBiasBinLabels),
    'sourceDistanceKm': _newStrata(_distanceBinLabels),
    'observedInstrumentalIntensity': _newStrata(_intensityBinLabels),
    'jmaThresholdProximity': _newStrata(_thresholdProximityBinLabels),
  };
  final allApplications = <_StationApplicationDiagnostic>[];

  var observationCount = 0;
  var appliedCount = 0;
  var unavailableCount = 0;
  var coordinateMismatchCount = 0;
  var baselineEventRmsSum = 0.0;
  var correctedEventRmsSum = 0.0;
  var improvedEvents = 0;
  var worsenedEvents = 0;
  var unchangedEvents = 0;

  for (final event in events) {
    if (event.stationResiduals.isEmpty) continue;
    final baselineRaw = event.stationResiduals
        .map((station) => station.residual)
        .toList();
    final stationStates = <_StationState>[];
    final correctedRaw = <double>[];
    var eventApplied = 0;
    var eventUnavailable = 0;
    var eventCoordinateMismatch = 0;

    for (final station in event.stationResiduals) {
      final estimate = stationModel.estimates[station.stationId];
      if (estimate == null) {
        eventUnavailable++;
        correctedRaw.add(station.residual);
        stationStates.add(
          _StationState(
            station: station,
            estimate: null,
            status: _CorrectionStatus.unavailable,
            correctedResidual: station.residual,
          ),
        );
      } else if (estimate.latitude != station.latitude ||
          estimate.longitude != station.longitude) {
        eventCoordinateMismatch++;
        correctedRaw.add(station.residual);
        stationStates.add(
          _StationState(
            station: station,
            estimate: estimate,
            status: _CorrectionStatus.coordinateMismatch,
            correctedResidual: station.residual,
          ),
        );
      } else {
        eventApplied++;
        final correctedResidual = station.residual - shrinkage.apply(estimate);
        correctedRaw.add(correctedResidual);
        stationStates.add(
          _StationState(
            station: station,
            estimate: estimate,
            status: _CorrectionStatus.applied,
            correctedResidual: correctedResidual,
          ),
        );
      }
    }

    final baselineMean = _mean(baselineRaw);
    final correctedMean = _mean(correctedRaw);
    final eventApplications = <_StationApplicationDiagnostic>[];
    for (var index = 0; index < stationStates.length; index++) {
      final state = stationStates[index];
      final station = state.station;
      final baselineCentered = station.residual - baselineMean;
      final correctedCentered = state.correctedResidual - correctedMean;
      final centeredSquaredDelta =
          correctedCentered * correctedCentered -
          baselineCentered * baselineCentered;
      final rawSquaredDelta =
          state.correctedResidual * state.correctedResidual -
          station.residual * station.residual;

      _addToStrata(
        strata,
        station: station,
        estimate: state.estimate,
        status: state.status,
        baselineCenteredResidual: baselineCentered,
        correctedCenteredResidual: correctedCentered,
      );

      if (state.status == _CorrectionStatus.applied) {
        final estimate = state.estimate!;
        final application = _StationApplicationDiagnostic(
          eventId: event.eventId,
          year: event.year,
          stationId: station.stationId,
          latitude: station.latitude,
          longitude: station.longitude,
          sourceDistanceKm: station.sourceDistanceKm,
          observedIntensity: station.observedIntensity,
          baselineResidual: station.residual,
          correctedResidual: state.correctedResidual,
          baselineCenteredResidual: baselineCentered,
          correctedCenteredResidual: correctedCentered,
          centeredSquaredDelta: centeredSquaredDelta,
          rawSquaredDelta: rawSquaredDelta,
          stationBias: estimate.meanCenteredResidual,
          appliedStationBias: shrinkage.apply(estimate),
          trainingEventCount: estimate.trainingEventCount,
          stationStandardError: estimate.centeredResidualStandardError,
        );
        eventApplications.add(application);
        allApplications.add(application);
      }
    }

    final baselineCenteredRms = _rms(
      baselineRaw.map((value) => value - baselineMean),
    );
    final correctedCenteredRms = _rms(
      correctedRaw.map((value) => value - correctedMean),
    );
    final baselineRawRms = _rms(baselineRaw);
    final correctedRawRms = _rms(correctedRaw);

    if (correctedCenteredRms + _selectionTolerance < baselineCenteredRms) {
      improvedEvents++;
    } else if (baselineCenteredRms + _selectionTolerance <
        correctedCenteredRms) {
      worsenedEvents++;
    } else {
      unchangedEvents++;
    }

    eventApplications.sort(
      (left, right) =>
          right.centeredSquaredDelta.compareTo(left.centeredSquaredDelta),
    );
    final adverse = eventApplications.take(10).toList();
    eventApplications.sort(
      (left, right) =>
          left.centeredSquaredDelta.compareTo(right.centeredSquaredDelta),
    );
    final helpful = eventApplications.take(10).toList();

    final diagnostic = _EventDiagnostic(
      event: event,
      baselineCenteredRms: baselineCenteredRms,
      correctedCenteredRms: correctedCenteredRms,
      baselineRawRms: baselineRawRms,
      correctedRawRms: correctedRawRms,
      correctionAppliedCount: eventApplied,
      correctionUnavailableCount: eventUnavailable,
      coordinateMismatchCount: eventCoordinateMismatch,
      sourceDistanceSummary: _SimpleSummary.fromValues(
        event.stationResiduals.map((station) => station.sourceDistanceKm),
      ),
      observedIntensitySummary: _SimpleSummary.fromValues(
        event.stationResiduals.map((station) => station.observedIntensity),
      ),
      adverseStations: adverse,
      helpfulStations: helpful,
    );
    eventDiagnostics.add(diagnostic);

    observationCount += event.stationResiduals.length;
    appliedCount += eventApplied;
    unavailableCount += eventUnavailable;
    coordinateMismatchCount += eventCoordinateMismatch;
    baselineEventRmsSum += baselineCenteredRms;
    correctedEventRmsSum += correctedCenteredRms;
  }

  final eventCount = eventDiagnostics.length;
  final stationEstimates = stationModel.estimates.values.toList();
  final extremeByBias = [...stationEstimates]
    ..sort(
      (left, right) => right.meanCenteredResidual.abs().compareTo(
        left.meanCenteredResidual.abs(),
      ),
    );
  final extremeByStandardError = [...stationEstimates]
    ..sort(
      (left, right) => right.centeredResidualStandardError.compareTo(
        left.centeredResidualStandardError,
      ),
    );
  allApplications.sort(
    (left, right) =>
        right.centeredSquaredDelta.compareTo(left.centeredSquaredDelta),
  );
  final adverseApplications = allApplications.take(30).toList();
  allApplications.sort(
    (left, right) =>
        left.centeredSquaredDelta.compareTo(right.centeredSquaredDelta),
  );
  final helpfulApplications = allApplications.take(30).toList();
  eventDiagnostics.sort(
    (left, right) => right.centeredRmsDelta.compareTo(left.centeredRmsDelta),
  );

  return _DiagnosticResult(
    summary: _EvaluationSummary(
      eventCount: eventCount,
      observationCount: observationCount,
      correctionAppliedCount: appliedCount,
      correctionUnavailableCount: unavailableCount,
      coordinateMismatchCount: coordinateMismatchCount,
      baselineEventEqualCenteredRms: eventCount == 0
          ? 0
          : baselineEventRmsSum / eventCount,
      correctedEventEqualCenteredRms: eventCount == 0
          ? 0
          : correctedEventRmsSum / eventCount,
      improvedEventCount: improvedEvents,
      worsenedEventCount: worsenedEvents,
      unchangedEventCount: unchangedEvents,
    ),
    strata: {
      for (final entry in strata.entries)
        entry.key: [
          for (final label in entry.value.keys)
            entry.value[label]!.summary(label),
        ],
    },
    extremeStationsByAbsoluteBias: extremeByBias.take(30).toList(),
    extremeStationsByStandardError: extremeByStandardError.take(30).toList(),
    worsenedEvents: eventDiagnostics
        .where((event) => event.centeredRmsDelta > _selectionTolerance)
        .take(30)
        .toList(),
    topAdverseStationApplications: adverseApplications,
    topHelpfulStationApplications: helpfulApplications,
  );
}

class _StationState {
  const _StationState({
    required this.station,
    required this.estimate,
    required this.status,
    required this.correctedResidual,
  });

  final Matsuzaki2006StationResidual station;
  final Matsuzaki2006StationBiasEstimate? estimate;
  final _CorrectionStatus status;
  final double correctedResidual;
}

enum _CorrectionStatus { applied, unavailable, coordinateMismatch }

const _trainingCountBinLabels = <String>[
  'unavailable',
  '2',
  '3-4',
  '5-9',
  '10-19',
  '20+',
];

const _standardErrorBinLabels = <String>[
  'unavailable',
  '0-<0.10',
  '0.10-<0.20',
  '0.20-<0.30',
  '0.30+',
];

const _absoluteBiasBinLabels = <String>[
  'unavailable',
  '0-<0.25',
  '0.25-<0.50',
  '0.50-<1.00',
  '1.00+',
];

const _distanceBinLabels = <String>[
  '1-<30 km',
  '30-<100 km',
  '100-<300 km',
  '300-500 km',
];

const _intensityBinLabels = <String>[
  '0.5-<1.5',
  '1.5-<2.5',
  '2.5-<3.5',
  '3.5+',
];

const _thresholdProximityBinLabels = <String>[
  '0.5-<0.75',
  '0.75-<1.0',
  '1.0-<1.5',
  '1.5+',
];

Map<String, _StratumAccumulator> _newStrata(List<String> labels) => {
  for (final label in labels) label: _StratumAccumulator(),
};

void _addToStrata(
  Map<String, Map<String, _StratumAccumulator>> strata, {
  required Matsuzaki2006StationResidual station,
  required Matsuzaki2006StationBiasEstimate? estimate,
  required _CorrectionStatus status,
  required double baselineCenteredResidual,
  required double correctedCenteredResidual,
}) {
  final applied = status == _CorrectionStatus.applied;
  final unavailable = status == _CorrectionStatus.unavailable;
  final coordinateMismatch = status == _CorrectionStatus.coordinateMismatch;
  void add(String name, String label) {
    strata[name]![label]!.add(
      applied: applied,
      unavailable: unavailable,
      coordinateMismatch: coordinateMismatch,
      baselineCenteredResidual: baselineCenteredResidual,
      correctedCenteredResidual: correctedCenteredResidual,
    );
  }

  add('trainingEventCount', _trainingCountBin(estimate?.trainingEventCount));
  add(
    'stationStandardError',
    _standardErrorBin(estimate?.centeredResidualStandardError),
  );
  add(
    'absoluteStationBias',
    _absoluteBiasBin(estimate?.meanCenteredResidual.abs()),
  );
  add('sourceDistanceKm', _distanceBin(station.sourceDistanceKm));
  add(
    'observedInstrumentalIntensity',
    _intensityBin(station.observedIntensity),
  );
  add(
    'jmaThresholdProximity',
    _thresholdProximityBin(station.observedIntensity),
  );
}

String _trainingCountBin(int? count) {
  if (count == null) return 'unavailable';
  if (count == 2) return '2';
  if (count < 5) return '3-4';
  if (count < 10) return '5-9';
  if (count < 20) return '10-19';
  return '20+';
}

String _standardErrorBin(double? value) {
  if (value == null) return 'unavailable';
  if (value < 0.10) return '0-<0.10';
  if (value < 0.20) return '0.10-<0.20';
  if (value < 0.30) return '0.20-<0.30';
  return '0.30+';
}

String _absoluteBiasBin(double? value) {
  if (value == null) return 'unavailable';
  if (value < 0.25) return '0-<0.25';
  if (value < 0.50) return '0.25-<0.50';
  if (value < 1.00) return '0.50-<1.00';
  return '1.00+';
}

String _distanceBin(double distanceKm) {
  if (distanceKm < 30) return '1-<30 km';
  if (distanceKm < 100) return '30-<100 km';
  if (distanceKm < 300) return '100-<300 km';
  return '300-500 km';
}

String _intensityBin(double intensity) {
  if (intensity < 1.5) return '0.5-<1.5';
  if (intensity < 2.5) return '1.5-<2.5';
  if (intensity < 3.5) return '2.5-<3.5';
  return '3.5+';
}

String _thresholdProximityBin(double intensity) {
  if (intensity < 0.75) return '0.5-<0.75';
  if (intensity < 1.0) return '0.75-<1.0';
  if (intensity < 1.5) return '1.0-<1.5';
  return '1.5+';
}

Matsuzaki2006DistanceSemanticApplication _applyAvailableSourceBackedGeometry({
  required List<Matsuzaki2006EventBaseline> events,
  required int year,
  required Matsuzaki2006AttenuationModel model,
}) {
  final geometries = Matsuzaki2006SourceBackedDistanceOverrides.eventGeometries
      .where(
        (geometry) =>
            geometry.year == year &&
            (geometry.variants.length == 1 ||
                geometry.preferredVariantId != null),
      )
      .toList();
  final byEventId = {
    for (final geometry in geometries) geometry.eventId: geometry,
  };
  final seen = <String>{};
  final overrides = <Matsuzaki2006EventDistanceOverride>[];
  final transformed = <Matsuzaki2006EventBaseline>[];
  for (final event in events) {
    final geometry = byEventId[event.eventId];
    if (geometry == null) {
      transformed.add(event);
      continue;
    }
    if (!seen.add(event.eventId)) {
      throw StateError('Duplicate accepted event ${event.eventId}.');
    }
    final override = Matsuzaki2006SourceBackedDistanceOverrides.evaluateVariant(
      event: event,
      geometry: geometry,
      variant: geometry.preferredVariant,
    );
    overrides.add(override);
    transformed.add(override.toPublishedDomainEvent(model: model));
  }
  final missing = byEventId.keys.toSet().difference(seen);
  if (missing.isNotEmpty) {
    throw StateError(
      'Missing accepted source-backed events in $year: '
      '${missing.toList()..sort()}.',
    );
  }
  return Matsuzaki2006DistanceSemanticApplication(
    events: transformed,
    overrides: overrides,
  );
}

Map<String, Object?> _readAnnualDataset(String path, int expectedYear) {
  final decoded = jsonDecode(File(path).readAsStringSync(encoding: utf8));
  if (decoded is! Map<String, Object?>) {
    throw FormatException('Expected a JSON object in $path.');
  }
  final year = decoded['year'];
  if (year is! num || year.toInt() != expectedYear) {
    throw FormatException(
      'Expected year $expectedYear but found $year in $path.',
    );
  }
  return decoded;
}

String _toMarkdown(List<_ModelDiagnosticRun> runs) {
  final buffer = StringBuffer()
    ..writeln('# Matsuzaki 2006 Station Bias Diagnostic')
    ..writeln()
    ..writeln(
      'Protocol status: `diagnostic only / trained 2010-2016 / selected '
      '2017 / frozen reuse 2018-2019 / not blind`.',
    )
    ..writeln()
    ..writeln(
      'This report diagnoses station terms and worsened events only. It does '
      'not refit by 2018/2019 results and does not open a final holdout year.',
    )
    ..writeln()
    ..writeln('Predeclared strata:')
    ..writeln()
    ..writeln('- Training count: `${_trainingCountBinLabels.join('`, `')}`')
    ..writeln(
      '- Station standard error: `${_standardErrorBinLabels.join('`, `')}`',
    )
    ..writeln(
      '- Absolute station term: `${_absoluteBiasBinLabels.join('`, `')}`',
    )
    ..writeln('- Source distance: `${_distanceBinLabels.join('`, `')}`')
    ..writeln('- Observed intensity: `${_intensityBinLabels.join('`, `')}`')
    ..writeln(
      '- JMA threshold proximity: `${_thresholdProximityBinLabels.join('`, `')}`',
    )
    ..writeln();

  for (final run in runs) {
    buffer
      ..writeln('## ${run.name}')
      ..writeln()
      ..writeln('| Metric | Value |')
      ..writeln('|---|---:|')
      ..writeln('| Training events | ${run.trainer.eventCount} |')
      ..writeln('| Training observations | ${run.trainer.observationCount} |')
      ..writeln('| Distinct stations | ${run.trainer.distinctStationCount} |')
      ..writeln(
        '| Selected minimum training events | '
        '${run.selectedMinimumTrainingEvents} |',
      )
      ..writeln('| Pseudo-event shrinkage k | ${run.pseudoEventCount} |')
      ..writeln();
    for (final year in [_validationYear, ..._frozenReuseYears]) {
      final diagnostic = run.evaluations[year];
      if (diagnostic == null) continue;
      final summary = diagnostic.summary;
      buffer
        ..writeln('### $year Summary')
        ..writeln()
        ..writeln('| Metric | Value |')
        ..writeln('|---|---:|')
        ..writeln('| Events | ${summary.eventCount} |')
        ..writeln('| Observations | ${summary.observationCount} |')
        ..writeln('| Coverage | ${_percent(summary.coverage)} |')
        ..writeln(
          '| Baseline centered event RMS | '
          '${_fixed(summary.baselineEventEqualCenteredRms)} |',
        )
        ..writeln(
          '| Corrected centered event RMS | '
          '${_fixed(summary.correctedEventEqualCenteredRms)} |',
        )
        ..writeln(
          '| Improvement | ${_percent(summary.fractionalImprovement)} |',
        )
        ..writeln(
          '| Improved/Worsened/Unchanged | '
          '${summary.improvedEventCount}/${summary.worsenedEventCount}/'
          '${summary.unchangedEventCount} |',
        )
        ..writeln()
        ..writeln('Top worsened events:')
        ..writeln()
        ..writeln(
          '| Event | M | Depth | Max I | Stations | Baseline RMS | Corrected RMS | Delta | Coverage | Median distance | Median observed I |',
        )
        ..writeln('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
      for (final event in diagnostic.worsenedEvents.take(10)) {
        buffer.writeln(
          '| `${event.event.eventId}` | ${_fixed(event.event.magnitude)} | '
          '${_fixed(event.event.depthKm)} | ${event.event.maximumIntensityClass} | '
          '${event.event.stationResiduals.length} | '
          '${_fixed(event.baselineCenteredRms)} | '
          '${_fixed(event.correctedCenteredRms)} | '
          '${_fixed(event.centeredRmsDelta)} | '
          '${_percent(event.correctionAppliedCount / event.event.stationResiduals.length)} | '
          '${_fixed(event.sourceDistanceSummary.median)} | '
          '${_fixed(event.observedIntensitySummary.median)} |',
        );
      }
      buffer
        ..writeln()
        ..writeln('Worst stratum deltas:')
        ..writeln()
        ..writeln(
          '| Stratum | Label | Observations | Coverage | Baseline RMS | Corrected RMS | Mean squared delta |',
        )
        ..writeln('|---|---|---:|---:|---:|---:|---:|');
      final worstStrata =
          diagnostic.strata.entries
              .expand(
                (entry) =>
                    entry.value.map((value) => MapEntry(entry.key, value)),
              )
              .toList()
            ..sort(
              (left, right) => right.value.centeredSquaredDeltaMean.compareTo(
                left.value.centeredSquaredDeltaMean,
              ),
            );
      for (final entry in worstStrata.take(10)) {
        final value = entry.value;
        buffer.writeln(
          '| ${entry.key} | `${value.label}` | ${value.observationCount} | '
          '${_percent(value.coverage)} | ${_fixed(value.baselineCenteredRms)} | '
          '${_fixed(value.correctedCenteredRms)} | '
          '${_fixed(value.centeredSquaredDeltaMean)} |',
        );
      }
      buffer.writeln();
    }

    final selectedModel = run.selectedStationModel;
    if (selectedModel != null) {
      final estimates = selectedModel.estimates.values.toList()
        ..sort(
          (left, right) => right.meanCenteredResidual.abs().compareTo(
            left.meanCenteredResidual.abs(),
          ),
        );
      buffer
        ..writeln('### Extreme Station Terms')
        ..writeln()
        ..writeln('| Station | Lat | Lon | Train events | Bias | Std error |')
        ..writeln('|---|---:|---:|---:|---:|---:|');
      for (final estimate in estimates.take(10)) {
        buffer.writeln(
          '| `${estimate.stationId}` | ${_fixed(estimate.latitude)} | '
          '${_fixed(estimate.longitude)} | ${estimate.trainingEventCount} | '
          '${_fixed(estimate.meanCenteredResidual)} | '
          '${_fixed(estimate.centeredResidualStandardError)} |',
        );
      }
      buffer.writeln();
    }
  }
  return buffer.toString();
}

double _mean(List<double> values) =>
    values.fold(0.0, (sum, value) => sum + value) / values.length;

double _rms(Iterable<double> values) {
  var count = 0;
  var squaredSum = 0.0;
  for (final value in values) {
    count++;
    squaredSum += value * value;
  }
  return count == 0 ? 0 : math.sqrt(squaredSum / count);
}

double _percentile(List<double> sortedValues, double fraction) {
  final position = (sortedValues.length - 1) * fraction;
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sortedValues[lower];
  final weight = position - lower;
  return sortedValues[lower] * (1 - weight) + sortedValues[upper] * weight;
}

String _fixed(double value) => value.toStringAsFixed(6);

String _percent(double value) => '${(value * 100).toStringAsFixed(3)}%';

String? _value(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  return index >= 0 && index + 1 < arguments.length
      ? arguments[index + 1]
      : null;
}

int? _intValue(List<String> arguments, String name) {
  final value = _value(arguments, name);
  if (value == null) return null;
  final parsed = int.tryParse(value);
  if (parsed == null) {
    throw ArgumentError.value(value, name, 'Expected an integer.');
  }
  return parsed;
}
