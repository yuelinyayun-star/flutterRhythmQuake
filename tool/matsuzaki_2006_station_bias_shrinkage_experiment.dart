import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

const _trainingYears = <int>[2010, 2011, 2012, 2013, 2014, 2015, 2016];
const _validationYear = 2017;
const _frozenReuseYears = <int>[2018, 2019];
const _candidateMinimumTrainingEvents = <int>[2, 5, 10, 20];
const _candidatePseudoEventCounts = <int>[0, 1, 2, 5, 10];
const _selectionTolerance = 1e-12;

void main(List<String> arguments) {
  final inputDirectory =
      _value(arguments, '--input-dir') ??
      'tmp/jma_intensity_nearfield_expansion';
  final outputDirectory = Directory(
    _value(arguments, '--output-dir') ??
        '.dart_tool/matsuzaki_2006_station_bias_shrinkage_2010_2019',
  );
  final allYears = [..._trainingYears, _validationYear, ..._frozenReuseYears];
  final inputPaths = {
    for (final year in allYears)
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

  final runs = <String, _ModelRun>{
    'published': _ModelRun(
      name: 'published',
      model: const Matsuzaki2006AttenuationModel(),
    ),
    'finiteFaultSemanticFrozen2017': _ModelRun(
      name: 'finiteFaultSemanticFrozen2017',
      model: const Matsuzaki2006AttenuationModel(
        coefficients:
            Matsuzaki2006AttenuationCoefficients.finiteFaultSemanticFrozen2017,
      ),
    ),
  };

  for (final year in _trainingYears) {
    stdout.writeln('training year $year...');
    final dataset = _readAnnualDataset(inputPaths[year]!, year);
    for (final run in runs.values) {
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
      run.trainingYears.add(
        _yearInputSummary(
          year: year,
          baseline: baseline,
          semanticApplication: semanticApplication,
        ),
      );
    }
  }

  stdout.writeln('validation year $_validationYear...');
  final validationDataset = _readAnnualDataset(
    inputPaths[_validationYear]!,
    _validationYear,
  );
  for (final run in runs.values) {
    final baseline = Matsuzaki2006JmaBaselineEvaluator(
      model: run.model,
    ).evaluate([validationDataset]);
    run.validationInput = _baselineInputSummary(baseline);
    for (final minimumEvents in _candidateMinimumTrainingEvents) {
      final stationModel = run.trainer.build(
        minimumTrainingEventCount: minimumEvents,
      );
      for (final pseudoEventCount in _candidatePseudoEventCounts) {
        final candidate = _CandidateEvaluation(
          stationModel: stationModel,
          pseudoEventCount: pseudoEventCount,
          evaluation: Matsuzaki2006StationBiasEvaluator(
            shrinkage: Matsuzaki2006StationBiasShrinkage(
              pseudoEventCount: pseudoEventCount,
            ),
          ).evaluate(events: baseline.events, stationBiasModel: stationModel),
        );
        run.validationCandidates[candidate.id] = candidate;
      }
    }
    run.selectValidatedCandidate();
  }

  for (final year in _frozenReuseYears) {
    stdout.writeln('frozen reuse year $year...');
    final dataset = _readAnnualDataset(inputPaths[year]!, year);
    for (final run in runs.values) {
      final baseline = Matsuzaki2006JmaBaselineEvaluator(
        model: run.model,
      ).evaluate([dataset]);
      final semanticApplication = _applyAvailableSourceBackedGeometry(
        events: baseline.events,
        year: year,
        model: run.model,
      );
      run.frozenReuseInputs[year] = _yearInputSummary(
        year: year,
        baseline: baseline,
        semanticApplication: semanticApplication,
      );
      final selected = run.selectedCandidate;
      run.frozenReuseEvaluations[year] = selected == null
          ? null
          : Matsuzaki2006StationBiasEvaluator(
              shrinkage: Matsuzaki2006StationBiasShrinkage(
                pseudoEventCount: selected.pseudoEventCount,
              ),
            ).evaluate(
              events: semanticApplication.events,
              stationBiasModel: selected.stationModel,
            );
    }
  }

  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_station_bias_shrinkage_experiment_v1',
    'protocolStatus':
        'trained_2010_2016_selected_2017_frozen_reuse_2018_2019_not_blind',
    'inputDirectory': inputDirectory,
    'split': {
      'trainingYears': _trainingYears,
      'validationYear': _validationYear,
      'frozenReuseYears': _frozenReuseYears,
      'newFinalHoldoutOpened': false,
    },
    'semantics': {
      'observations':
          'unaltered JMA archive instrumental intensity records at least 0.5',
      'trainingTarget':
          'raw_residual_minus_same_event_source_term_before_station_estimation',
      'stationEstimate':
          'arithmetic_mean_centered_residual_over_distinct_training_events',
      'shrinkage':
          'station_bias * training_event_count / (training_event_count + pseudo_event_count)',
      'missingStationPolicy':
          'no_station_correction_and_no_intensity_or_residual_imputation',
      'coordinatePolicy':
          'exact_station_coordinate_match_required; conflicts are not fitted',
      'distanceSemantics':
          'source-backed preferred finite-fault distance where already archived; point-source hypocentral distance otherwise',
    },
    'predeclaredSelection': {
      'candidateMinimumTrainingEventCounts': _candidateMinimumTrainingEvents,
      'candidatePseudoEventCounts': _candidatePseudoEventCounts,
      'metric': '2017_event_equal_centered_residual_mean_rms_all_observations',
      'unavailableCorrectionTreatment':
          'observation retained unchanged and counted unavailable',
      'acceptance': 'strictly_below_same_candidate_baseline_by_more_than_1e-12',
      'selection': 'lowest_accepted_corrected_metric',
      'tieBreak':
          'higher_minimum_training_event_count_then_higher_pseudo_event_count_within_1e-12',
      'selectionTolerance': _selectionTolerance,
    },
    'models': {for (final run in runs.entries) run.key: run.value.toJson()},
  };

  outputDirectory.createSync(recursive: true);
  final jsonFile = File('${outputDirectory.path}/report.json');
  final markdownFile = File('${outputDirectory.path}/report.md');
  jsonFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    encoding: utf8,
  );
  markdownFile.writeAsStringSync(_toMarkdown(runs), encoding: utf8);
  for (final run in runs.values) {
    final selected = run.selectedCandidate;
    stdout.writeln(
      '${run.name}: selectedMinimumTrainingEvents='
      '${selected?.stationModel.minimumTrainingEventCount}, '
      'selectedPseudoEventCount=${selected?.pseudoEventCount}, '
      'validationCenteredRms=${selected?.evaluation.correctedEventEqualCenteredRms}',
    );
  }
  stdout.writeln('wrote ${markdownFile.path}');
  stdout.writeln('wrote ${jsonFile.path}');
}

class _ModelRun {
  _ModelRun({required this.name, required this.model});

  final String name;
  final Matsuzaki2006AttenuationModel model;
  final Matsuzaki2006StationBiasTrainer trainer =
      Matsuzaki2006StationBiasTrainer();
  final List<Map<String, Object?>> trainingYears = [];
  final Map<String, _CandidateEvaluation> validationCandidates = {};
  final Map<int, Map<String, Object?>> frozenReuseInputs = {};
  final Map<int, Matsuzaki2006StationBiasEvaluation?> frozenReuseEvaluations =
      {};
  Map<String, Object?>? validationInput;
  String? selectedCandidateId;

  _CandidateEvaluation? get selectedCandidate => selectedCandidateId == null
      ? null
      : validationCandidates[selectedCandidateId];

  void selectValidatedCandidate() {
    final accepted = validationCandidates.values.where((candidate) {
      return candidate.evaluation.correctedEventEqualCenteredRms +
              _selectionTolerance <
          candidate.evaluation.baselineEventEqualCenteredRms;
    }).toList();
    accepted.sort((left, right) {
      final difference =
          left.evaluation.correctedEventEqualCenteredRms -
          right.evaluation.correctedEventEqualCenteredRms;
      if (difference.abs() > _selectionTolerance) {
        return difference < 0 ? -1 : 1;
      }
      final minimumDifference =
          right.stationModel.minimumTrainingEventCount -
          left.stationModel.minimumTrainingEventCount;
      if (minimumDifference != 0) return minimumDifference;
      return right.pseudoEventCount.compareTo(left.pseudoEventCount);
    });
    selectedCandidateId = accepted.isEmpty ? null : accepted.first.id;
  }

  Map<String, Object?> toJson() => {
    'baseCoefficients': model.coefficients.toJson(),
    'training': {
      'years': trainingYears,
      'acceptedEventCount': trainer.eventCount,
      'acceptedObservationCount': trainer.observationCount,
      'distinctStationCount': trainer.distinctStationCount,
    },
    'validationInput': validationInput,
    'validationCandidates': {
      for (final entry in validationCandidates.entries)
        entry.key: entry.value.toJson(),
    },
    'selection': {
      'selectedCandidateId': selectedCandidateId,
      'selectedMinimumTrainingEventCount':
          selectedCandidate?.stationModel.minimumTrainingEventCount,
      'selectedPseudoEventCount': selectedCandidate?.pseudoEventCount,
      'accepted': selectedCandidate != null,
      'selectedStationModel': selectedCandidate?.stationModel.toJson(),
    },
    'frozenReuse': {
      for (final year in _frozenReuseYears)
        year.toString(): {
          'input': frozenReuseInputs[year],
          'evaluation': frozenReuseEvaluations[year]?.toJson(),
          'status': selectedCandidate == null
              ? 'not_run_no_validated_station_model'
              : 'frozen_station_model_and_shrinkage_reused_without_refit',
        },
    },
  };
}

class _CandidateEvaluation {
  const _CandidateEvaluation({
    required this.stationModel,
    required this.pseudoEventCount,
    required this.evaluation,
  });

  final Matsuzaki2006StationBiasModel stationModel;
  final int pseudoEventCount;
  final Matsuzaki2006StationBiasEvaluation evaluation;

  String get id =>
      '${stationModel.minimumTrainingEventCount}/$pseudoEventCount';

  Map<String, Object?> toJson() => {
    'minimumTrainingEventCount': stationModel.minimumTrainingEventCount,
    'pseudoEventCount': pseudoEventCount,
    'shrinkage': Matsuzaki2006StationBiasShrinkage(
      pseudoEventCount: pseudoEventCount,
    ).toJson(),
    'eligibleStationCount': stationModel.estimates.length,
    'coordinateConflictStationCount':
        stationModel.coordinateConflictStationCount,
    'evaluation': evaluation.toJson(includeEvents: false),
  };
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
      'Missing accepted source-backed events in $year: ${missing.toList()..sort()}.',
    );
  }
  return Matsuzaki2006DistanceSemanticApplication(
    events: transformed,
    overrides: overrides,
  );
}

Map<String, Object?> _yearInputSummary({
  required int year,
  required Matsuzaki2006JmaBaselineResult baseline,
  required Matsuzaki2006DistanceSemanticApplication semanticApplication,
}) => {
  'year': year,
  ..._baselineInputSummary(baseline),
  'acceptedObservationCountAfterDistanceSemantics': _stationCount(
    semanticApplication.events,
  ),
  'sourceBackedOverrideCount': semanticApplication.overrides.length,
};

Map<String, Object?> _baselineInputSummary(
  Matsuzaki2006JmaBaselineResult baseline,
) => {
  'rawEventCount': baseline.inputEventCount,
  'acceptedEventCount': baseline.events.length,
  'acceptedObservationCountBeforeDistanceSemantics':
      baseline.stationResidualCount,
  'eventRejectionCounts': baseline.eventRejectionCounts,
  'observationRejectionCounts': baseline.observationRejectionCounts,
};

int _stationCount(Iterable<Matsuzaki2006EventBaseline> events) =>
    events.fold(0, (sum, event) => sum + event.stationResiduals.length);

String _toMarkdown(Map<String, _ModelRun> runs) {
  final buffer = StringBuffer()
    ..writeln('# Matsuzaki 2006 Station Bias Shrinkage Experiment')
    ..writeln()
    ..writeln(
      'Protocol: `train 2010-2016 / select 2017 / frozen reuse 2018-2019 / not blind`.',
    )
    ..writeln(
      'Station terms are only shrunk by `n / (n + k)`; original JMA observations and',
    )
    ..writeln('unavailable-station residuals remain unchanged.')
    ..writeln();
  for (final run in runs.values) {
    buffer
      ..writeln('## ${run.name}')
      ..writeln()
      ..writeln(
        '| Min events | Pseudo-events k | Coverage | Baseline centered event RMS | Corrected centered event RMS | Improvement | Better/Worse/Unchanged |',
      )
      ..writeln('|---:|---:|---:|---:|---:|---:|---:|');
    final candidates = run.validationCandidates.values.toList()
      ..sort(
        (left, right) =>
            left.stationModel.minimumTrainingEventCount !=
                right.stationModel.minimumTrainingEventCount
            ? left.stationModel.minimumTrainingEventCount.compareTo(
                right.stationModel.minimumTrainingEventCount,
              )
            : left.pseudoEventCount.compareTo(right.pseudoEventCount),
      );
    for (final candidate in candidates) {
      final evaluation = candidate.evaluation;
      final improvement =
          (evaluation.toJson(includeEvents: false)['eventEqual']!
                  as Map<
                    String,
                    Object
                  >)['centeredMeanRmsFractionalImprovement']!
              as double;
      buffer.writeln(
        '| ${candidate.stationModel.minimumTrainingEventCount} | ${candidate.pseudoEventCount} | ${_fixed(evaluation.correctionCoverage)} | ${_fixed(evaluation.baselineEventEqualCenteredRms)} | ${_fixed(evaluation.correctedEventEqualCenteredRms)} | ${_fixed(improvement)} | ${evaluation.centeredRmsImprovedEventCount}/${evaluation.centeredRmsWorsenedEventCount}/${evaluation.centeredRmsUnchangedEventCount} |',
      );
    }
    final selected = run.selectedCandidate;
    buffer
      ..writeln()
      ..writeln(
        'Selected: minimum events `${selected?.stationModel.minimumTrainingEventCount}`, pseudo-events `k=${selected?.pseudoEventCount}`.',
      )
      ..writeln()
      ..writeln(
        '| Frozen year | Events | Coverage | Baseline centered event RMS | Corrected centered event RMS | Improvement | Better/Worse/Unchanged |',
      )
      ..writeln('|---:|---:|---:|---:|---:|---:|---:|');
    for (final year in _frozenReuseYears) {
      final evaluation = run.frozenReuseEvaluations[year];
      if (evaluation == null) {
        buffer.writeln('| $year | not run | | | | | |');
        continue;
      }
      final improvement =
          (evaluation.toJson(includeEvents: false)['eventEqual']!
                  as Map<
                    String,
                    Object
                  >)['centeredMeanRmsFractionalImprovement']!
              as double;
      buffer.writeln(
        '| $year | ${evaluation.events.length} | ${_fixed(evaluation.correctionCoverage)} | ${_fixed(evaluation.baselineEventEqualCenteredRms)} | ${_fixed(evaluation.correctedEventEqualCenteredRms)} | ${_fixed(improvement)} | ${evaluation.centeredRmsImprovedEventCount}/${evaluation.centeredRmsWorsenedEventCount}/${evaluation.centeredRmsUnchangedEventCount} |',
      );
    }
    buffer.writeln();
  }
  return buffer.toString();
}

String _fixed(double value) => value.toStringAsFixed(6);

String? _value(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  return index >= 0 && index + 1 < arguments.length
      ? arguments[index + 1]
      : null;
}
