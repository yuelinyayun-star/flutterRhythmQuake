import 'dart:math' as math;

import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimator.dart';
import 'package:flutterrhythmquake/core/source_estimation/srev_kaizou_magnitude.dart';
import 'nied_magnitude_experiment.dart';

/// Test-only observer: returns the original estimator output without edits.
class NiedMagnitudeAuditEstimator extends NiedDartHypSourceEstimator {
  NiedMagnitudeAuditEstimator()
    : super(
        searchSchedule: NiedHypSearchSchedule.referenceBroadFourStage,
        writebackPolicy: NiedHypWritebackPolicy.nonIncreasingCurrent,
      );

  final _held = SrevKaizouMagnitudeIntensityState();
  final _timedHeld = SrevKaizouMagnitudeIntensityState();
  final _experiment =
      const bool.fromEnvironment('CURRENT_CAPTURE_MAGNITUDE_EXPERIMENT')
      ? NiedMagnitudeExperiment()
      : null;
  Map<String, Object?>? latestAudit;

  @override
  SourceEstimate? estimate(SourceEstimationRequest request) {
    final snapshots =
        (request.metadata['nied_hypocenter_active_stations'] as List?)
            ?.whereType<Map>()
            .toList() ??
        const <Map>[];
    final raw = <String, double?>{
      for (final station in snapshots)
        station['code'].toString(): (station['shindo'] as num?)?.toDouble(),
    };
    _held.updateFrame(raw, observedAt: request.observedAt);
    final timedSnapshots = snapshots
        .where((station) => station['triggerStamp'] != null)
        .toList();
    final timedRaw = <String, double?>{
      for (final station in timedSnapshots)
        station['code'].toString(): (station['shindo'] as num?)?.toDouble(),
    };
    _timedHeld.updateFrame(timedRaw, observedAt: request.observedAt);
    final output = super.estimate(request);
    latestAudit = {
      'observedAtUtc': request.observedAt.toUtc().toIso8601String(),
      'activeStationCount': snapshots.length,
      if (const bool.fromEnvironment('CURRENT_CAPTURE_STATION_TRACE'))
        'stationTrace': {
          'workerInputOrder':
              request.metadata['nied_dart_hyp_input_station_order'],
          'stations': [
            for (final station in snapshots)
              {
                'code': station['code'],
                'latLng': station['latLng'],
                'rawIntensity': station['shindo'],
                'triggerStamp': station['triggerStamp'],
                'updateStamp': station['updateStamp'],
                'heldConvertedIntensity': _held.maximumFor([
                  station['code'].toString(),
                ]),
                'timedHeldConvertedIntensity': _timedHeld.maximumFor([
                  station['code'].toString(),
                ]),
              },
          ],
        },
      if (_experiment != null)
        'experiment': _experiment.observe(request, output, snapshots),
    };
    if (output == null) return output;
    final diagnostics = output.diagnostics;
    final multiple =
        (diagnostics['srev_kaizou_magnitude_active_detection_count'] as num? ??
            0) >
        1;
    final heldMaximum = _held.maximumFor(raw.keys);
    final timedHeldMaximum = _timedHeld.maximumFor(timedRaw.keys);
    Map? strongest;
    for (final station in snapshots) {
      final value = station['shindo'];
      if (value is! num || !value.isFinite) continue;
      if (strongest == null || value > (strongest['shindo'] as num)) {
        strongest = station;
      }
    }
    final rawMaximum = (strongest?['shindo'] as num?)?.toDouble();
    SrevKaizouMagnitudeResult? calculate(double? intensity) => intensity == null
        ? null
        : calculateSrevKaizouMagnitude(
            sourceLatitude: output.latitude,
            sourceLongitude: output.longitude,
            inputIntensity: intensity,
            multipleSources: multiple,
          );
    final fresh = calculate(heldMaximum);
    final freshTimed = calculate(timedHeldMaximum);
    final instantaneous = calculate(rawMaximum);
    double? strongestDistance;
    final coordinate = strongest?['latLng'];
    if (coordinate is List && coordinate.length >= 2) {
      strongestDistance = srevKaizouStationDistanceKm(
        roundedSourceLatitude: srevKaizouRoundCoordinate(output.latitude),
        roundedSourceLongitude: srevKaizouRoundCoordinate(output.longitude),
        stationLatitude: (coordinate[0] as num).toDouble(),
        stationLongitude: (coordinate[1] as num).toDouble(),
      );
    }
    latestAudit!.addAll({
      'singleSourceComparable': !multiple,
      'publishedMagnitude': output.magnitude,
      'allActiveHeldConvertedIntensity': heldMaximum,
      'timedActiveHeldConvertedIntensity': timedHeldMaximum,
      'timedActiveStationCount': timedSnapshots.length,
      'freshTimedHeldMagnitude': freshTimed?.magnitude,
      'allActiveRawMaximumIntensity': rawMaximum,
      'rawMaximumConvertedIntensity': rawMaximum == null
          ? null
          : srevKaizouScratchConvertedShindo(rawMaximum),
      'strongestStationCode': strongest?['code'],
      'strongestStationHasTrigger': strongest?['triggerStamp'] != null,
      'strongestStationTriggerStamp': strongest?['triggerStamp'],
      'strongestStationDistanceKm': strongestDistance,
      // These are observational counterfactuals, never fed back to the solver.
      'freshHeldMagnitude': fresh?.magnitude,
      'freshHeldDiagnostics': fresh?.toDiagnostics(),
      'instantaneousRawMagnitude': instantaneous?.magnitude,
      'instantaneousStrongestDistanceMagnitude':
          rawMaximum == null || strongestDistance == null
          ? null
          : srevKaizouMagnitudeFromDistanceAndIntensity(
              stationDistanceKm: math.max(20.0, strongestDistance),
              inputIntensity: rawMaximum,
              multipleSources: multiple,
            ),
      'publishedDiagnostics': {
        for (final entry in diagnostics.entries)
          if (entry.key.startsWith('srev_kaizou_magnitude_'))
            entry.key: entry.value,
      },
    });
    return output;
  }
}
