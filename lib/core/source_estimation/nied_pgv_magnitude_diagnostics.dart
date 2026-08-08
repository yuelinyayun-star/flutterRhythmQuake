import 'dart:math' as math;

import 'jshis_surface_structure_api.dart';
import 'jma2001_travel_time_approximation.dart';
import 'source_estimation_models.dart';

// NIED Strong Motion Monitor describes vcmap_s as the maximum velocity per
// second after acceleration integration, using a vector synthesis of the N-S,
// E-W, and U-D components. This is not the filtered horizontal PGV600
// measurement required by Si and Midorikawa (1999).
const _niedVcmapSMeasurementContract =
    'per_second_maximum_integrated_acceleration_velocity_three_component_vector_synthesis';
const _niedVcmapSIsSiMidorikawa1999Pgv600Equivalent = false;
const _niedVcmapSContractStatus =
    'not_equivalent_to_si_midorikawa_1999_filtered_horizontal_pgv600';

/// Fault categories used by Si and Midorikawa's 1999 PGA attenuation model.
///
/// This is deliberately separate from the application's source labels. The
/// paper's fault terms are a physical input and must come from a reviewed
/// event/rupture classification, not from a display-source guess.
enum NiedPgaFaultType { crustal, interPlate, intraPlate }

/// Supplies the shortest source-fault distance required by the PGA model.
///
/// A point-source hypocentral distance is not the same quantity. Callers that
/// only have a point-source HYP must not pass it here as if it were a fault
/// distance without separately validating that approximation.
typedef NiedPgaFaultDistanceKm =
    double? Function(SeismicStationEventRecord record);

/// Produces a diagnostics-only PGA inversion using the surface-PGA,
/// fault-distance relation of Si and Midorikawa (1999).
///
/// The NIED `acmap_s` pixels are independent PGA observations. Unlike the
/// existing PGV diagnostic, this relation needs a reviewed fault type and a
/// shortest distance to the rupture surface for every station. The current
/// real-time HYP output has neither a finite-fault geometry nor a reviewed
/// fault classification, so this function is intentionally not called from a
/// production estimator, map, UI, or notification path.
///
/// Reference: 司宏俊・翠川三郎 (1999), "断層タイプ及び地盤条件を考慮
/// した最大加速度・最大速度の距離減衰式", Table 6 and equation (6).
Map<String, Object?> niedGifPgaMagnitudeDiagnostics({
  required Iterable<SeismicStationEventRecord> stations,
  required double averageFocalDepthKm,
  required NiedPgaFaultType faultType,
  required NiedPgaFaultDistanceKm faultDistanceKmFor,
  required String distanceDefinition,
  Set<String> sourceTriggerMemberIds = const {},
}) {
  const model = 'si_midorikawa_1999_surface_pga_fault_distance_v1';
  if (!averageFocalDepthKm.isFinite || averageFocalDepthKm < 0) {
    return {
      'nied_gif_pga_magnitude_model': model,
      'nied_gif_pga_magnitude_supported': false,
      'nied_gif_pga_station_count': 0,
      'nied_gif_pga_source_quality':
          'diagnostic_only_invalid_average_focal_depth',
    };
  }
  if (distanceDefinition.trim().isEmpty) {
    throw ArgumentError.value(
      distanceDefinition,
      'distanceDefinition',
      'Must state how fault distances were obtained.',
    );
  }

  final stationMagnitudes = <double>[];
  final distancesKm = <double>[];
  final peakTimes = <DateTime>[];
  var rejectedCount = 0;
  var nonParticipantCount = 0;
  var saturatedCount = 0;
  var invalidDistanceCount = 0;
  var outOfModelRangeStationCount = 0;

  for (final record in stations) {
    if (record.descriptor.sensorRole != StationSensorRole.surface) continue;
    final isEventParticipant =
        record.hasTriggered ||
        record.firstRiseAt != null ||
        sourceTriggerMemberIds.contains(record.descriptor.code);
    if (!isEventParticipant) {
      nonParticipantCount += 1;
      continue;
    }
    final provenance = record.provenance[StationValueType.pga];
    final observation = record.eventPhysicalPeaks[StationValueType.pga];
    if (observation == null ||
        !observation.isUsable ||
        provenance?.mayBeUsedAsIndependentEvidence != true) {
      rejectedCount += 1;
      continue;
    }
    // The palette endpoint is a censored lower bound, not an exact PGA.
    if (observation.colorPosition != null &&
        observation.colorPosition! >= 0.999) {
      saturatedCount += 1;
      continue;
    }
    final faultDistanceKm = faultDistanceKmFor(record);
    if (faultDistanceKm == null ||
        !faultDistanceKm.isFinite ||
        faultDistanceKm <= 0) {
      invalidDistanceCount += 1;
      continue;
    }
    final magnitude = _invertSiMidorikawa1999SurfacePgaMagnitude(
      observedPgaGal: observation.value,
      averageFocalDepthKm: averageFocalDepthKm,
      faultDistanceKm: faultDistanceKm,
      faultType: faultType,
    );
    if (magnitude == null) {
      // The finite-fault PGA relation approaches an upper amplitude limit at
      // a fixed distance. A value above that limit has no root in the
      // diagnostic search interval, so returning the artificial M9.5 bound
      // would turn an out-of-model observation into a fake magnitude.
      outOfModelRangeStationCount += 1;
      continue;
    }
    stationMagnitudes.add(magnitude);
    distancesKm.add(faultDistanceKm);
    peakTimes.add(observation.dataTime);
  }

  final common = <String, Object?>{
    'nied_gif_pga_magnitude_model': model,
    'nied_gif_pga_fault_type': faultType.name,
    'nied_gif_pga_distance_definition': distanceDefinition,
    'nied_gif_pga_average_focal_depth_km': averageFocalDepthKm,
    'nied_gif_pga_rejected_station_count': rejectedCount,
    'nied_gif_pga_nonparticipant_station_count': nonParticipantCount,
    'nied_gif_pga_saturated_station_count': saturatedCount,
    'nied_gif_pga_invalid_distance_station_count': invalidDistanceCount,
    'nied_gif_pga_out_of_model_range_station_count':
        outOfModelRangeStationCount,
    'nied_gif_pga_source_quality':
        'diagnostic_only_unvalidated_requires_reviewed_rupture_geometry',
  };
  if (stationMagnitudes.length < 3) {
    return {
      ...common,
      'nied_gif_pga_magnitude_supported': false,
      'nied_gif_pga_station_count': stationMagnitudes.length,
    };
  }

  final p25 = _percentile(stationMagnitudes, 0.25);
  final p75 = _percentile(stationMagnitudes, 0.75);
  final earliestPeak = peakTimes.reduce(
    (left, right) => left.isBefore(right) ? left : right,
  );
  final latestPeak = peakTimes.reduce(
    (left, right) => left.isAfter(right) ? left : right,
  );
  return {
    ...common,
    // Frozen raw-waveform replays have rejected direct inversion of this
    // average-field relation. The spread remains useful for diagnostics, but
    // it must not be reported as a usable magnitude.
    'nied_gif_pga_magnitude_supported': false,
    'nied_gif_pga_dispersion_acceptable':
        outOfModelRangeStationCount == 0 && p75 - p25 <= 1.2,
    'nied_gif_pga_median': _median(stationMagnitudes),
    'nied_gif_pga_p25': p25,
    'nied_gif_pga_p75': p75,
    'nied_gif_pga_iqr': p75 - p25,
    'nied_gif_pga_station_count': stationMagnitudes.length,
    'nied_gif_pga_peak_window_seconds':
        latestPeak.difference(earliestPeak).inMilliseconds / 1000.0,
    'nied_gif_pga_distance_min_km': distancesKm.reduce(math.min),
    'nied_gif_pga_distance_max_km': distancesKm.reduce(math.max),
  };
}

/// Produces a traceable, diagnostics-only PGV inversion for an active NIED
/// source estimate. The returned number is intentionally not an official JMA
/// magnitude and must not be used as a production magnitude before replay
/// calibration is complete.
Map<String, Object?> niedGifPgvMagnitudeDiagnostics({
  required Iterable<SeismicStationEventRecord> stations,
  required double sourceLatitude,
  required double sourceLongitude,
  required double? depthKm,
  Set<String> sourceTriggerMemberIds = const {},
}) {
  const model =
      'si_midorikawa_1999_pgv600_hypocentral_placeholder_diagnostic_v2';
  if (!sourceLatitude.isFinite ||
      !sourceLongitude.isFinite ||
      depthKm == null ||
      !depthKm.isFinite ||
      depthKm < 0) {
    return {
      'nied_gif_pgv_magnitude_model': model,
      'nied_gif_pgv_magnitude_supported': false,
      'nied_gif_pgv_station_count': 0,
      'nied_gif_pgv_source_quality': 'missing_or_invalid_source_geometry',
      'nied_gif_pgv_measurement_contract': _niedVcmapSMeasurementContract,
      'nied_gif_pgv_measurement_equivalent_to_si_midorikawa_1999_pgv600':
          _niedVcmapSIsSiMidorikawa1999Pgv600Equivalent,
      'nied_gif_pgv_measurement_contract_status': _niedVcmapSContractStatus,
    };
  }
  final stationMagnitudes = <double>[];
  final distancesKm = <double>[];
  final peakTimes = <DateTime>[];
  var rejectedCount = 0;
  var nonParticipantCount = 0;
  var saturatedCount = 0;

  for (final record in stations) {
    if (record.descriptor.sensorRole != StationSensorRole.surface) continue;
    final isEventParticipant =
        record.hasTriggered ||
        record.firstRiseAt != null ||
        sourceTriggerMemberIds.contains(record.descriptor.code);
    if (!isEventParticipant) {
      nonParticipantCount += 1;
      continue;
    }
    final provenance = record.provenance[StationValueType.pgv];
    final observation = record.eventPhysicalPeaks[StationValueType.pgv];
    if (observation == null ||
        !observation.isUsable ||
        provenance?.mayBeUsedAsIndependentEvidence != true) {
      rejectedCount += 1;
      continue;
    }
    // The final color position is a display-boundary value. It does not carry
    // an uncensored PGV, so do not treat it as a usable amplitude constraint.
    if (observation.colorPosition != null &&
        observation.colorPosition! >= 0.999) {
      saturatedCount += 1;
      continue;
    }
    final surfaceDistanceKm = _haversineKm(
      sourceLatitude,
      sourceLongitude,
      record.descriptor.coordinate.latitude,
      record.descriptor.coordinate.longitude,
    );
    final hypocentralDistanceKm = math.sqrt(
      surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
    );
    final magnitude = _invertJmaStylePgvMagnitude(
      observedPgv: observation.value,
      depthKm: depthKm,
      hypocentralDistanceKm: hypocentralDistanceKm,
    );
    if (magnitude == null) {
      rejectedCount += 1;
      continue;
    }
    stationMagnitudes.add(magnitude);
    distancesKm.add(hypocentralDistanceKm);
    peakTimes.add(observation.dataTime);
  }

  if (stationMagnitudes.length < 3) {
    return {
      'nied_gif_pgv_magnitude_model': model,
      'nied_gif_pgv_magnitude_supported': false,
      'nied_gif_pgv_station_count': stationMagnitudes.length,
      'nied_gif_pgv_rejected_station_count': rejectedCount,
      'nied_gif_pgv_nonparticipant_station_count': nonParticipantCount,
      'nied_gif_pgv_saturated_station_count': saturatedCount,
      'nied_gif_pgv_source_quality':
          'diagnostic_only_blocked_nied_vcmap_not_horizontal_pgv600',
      'nied_gif_pgv_measurement_contract': _niedVcmapSMeasurementContract,
      'nied_gif_pgv_measurement_equivalent_to_si_midorikawa_1999_pgv600':
          _niedVcmapSIsSiMidorikawa1999Pgv600Equivalent,
      'nied_gif_pgv_measurement_contract_status': _niedVcmapSContractStatus,
    };
  }

  final median = _median(stationMagnitudes);
  final p25 = _percentile(stationMagnitudes, 0.25);
  final p75 = _percentile(stationMagnitudes, 0.75);
  final earliestPeak = peakTimes.reduce(
    (left, right) => left.isBefore(right) ? left : right,
  );
  final latestPeak = peakTimes.reduce(
    (left, right) => left.isAfter(right) ? left : right,
  );
  final iqr = p75 - p25;
  return {
    'nied_gif_pgv_magnitude_model': model,
    // Si and Midorikawa (1999) requires filtered horizontal PGV reduced to
    // Vs=600 m/s and a fault distance. NIED vcmap_s is documented as a
    // three-component vector-synthesis maximum per second, while this branch
    // has only a point-source hypocentral distance. IQR is not usability
    // evidence.
    'nied_gif_pgv_magnitude_supported': false,
    'nied_gif_pgv_dispersion_acceptable': iqr <= 1.2,
    'nied_gif_pgv_median': median,
    'nied_gif_pgv_p25': p25,
    'nied_gif_pgv_p75': p75,
    'nied_gif_pgv_iqr': iqr,
    'nied_gif_pgv_station_count': stationMagnitudes.length,
    'nied_gif_pgv_rejected_station_count': rejectedCount,
    'nied_gif_pgv_nonparticipant_station_count': nonParticipantCount,
    'nied_gif_pgv_saturated_station_count': saturatedCount,
    'nied_gif_pgv_peak_window_seconds':
        latestPeak.difference(earliestPeak).inMilliseconds / 1000.0,
    'nied_gif_pgv_distance_min_km': distancesKm.reduce(math.min),
    'nied_gif_pgv_distance_max_km': distancesKm.reduce(math.max),
    'nied_gif_pgv_source_quality':
        'diagnostic_only_blocked_nied_vcmap_not_horizontal_pgv600',
    'nied_gif_pgv_measurement_contract': _niedVcmapSMeasurementContract,
    'nied_gif_pgv_measurement_equivalent_to_si_midorikawa_1999_pgv600':
        _niedVcmapSIsSiMidorikawa1999Pgv600Equivalent,
    'nied_gif_pgv_measurement_contract_status': _niedVcmapSContractStatus,
  };
}

/// Selects each station's raw GIF PGV within a fixed initial S-wave window
/// before applying the legacy PGV comparison inversion.
///
/// This is deliberately a replay-only diagnostic. It reads the existing
/// scalar [SeismicStationEventRecord.observationHistory] and neither changes
/// real-time retention nor writes a magnitude into [SourceEstimate]. The
/// `[-2 s, +20 s]` window is a predeclared experimental window, not an
/// official JMA magnitude-processing specification.
Map<String, Object?> niedGifPgvSArrivalWindowMagnitudeDiagnostics({
  required Iterable<SeismicStationEventRecord> stations,
  required double sourceLatitude,
  required double sourceLongitude,
  required double? depthKm,
  required DateTime? sourceOriginTime,
  Set<String> sourceTriggerMemberIds = const {},
}) {
  const model = 'nied_gif_pgv_s_arrival_window_diagnostic_v1';
  const preArrivalWindow = Duration(seconds: 2);
  const postArrivalWindow = Duration(seconds: 20);
  if (!sourceLatitude.isFinite ||
      !sourceLongitude.isFinite ||
      depthKm == null ||
      !depthKm.isFinite ||
      depthKm < 0 ||
      sourceOriginTime == null) {
    return {
      'nied_gif_pgv_s_arrival_window_magnitude_model': model,
      'nied_gif_pgv_s_arrival_window_magnitude_supported': false,
      'nied_gif_pgv_s_arrival_window_station_count': 0,
      'nied_gif_pgv_s_arrival_window_source_quality':
          'missing_or_invalid_source_geometry_or_origin_time',
    };
  }

  final stationMagnitudes = <double>[];
  final distancesKm = <double>[];
  var rejectedCount = 0;
  var nonParticipantCount = 0;
  var saturatedCount = 0;
  var missingHistoryCount = 0;
  var missingPgvHistoryCount = 0;
  var noPgvInWindowCount = 0;
  var partialHistoryCoverageCount = 0;
  var preSWavePeakExcludedCount = 0;
  var postSWavePeakExcludedCount = 0;

  for (final record in stations) {
    if (record.descriptor.sensorRole != StationSensorRole.surface) continue;
    final isEventParticipant =
        record.hasTriggered ||
        record.firstRiseAt != null ||
        sourceTriggerMemberIds.contains(record.descriptor.code);
    if (!isEventParticipant) {
      nonParticipantCount += 1;
      continue;
    }
    if (record
            .provenance[StationValueType.pgv]
            ?.mayBeUsedAsIndependentEvidence !=
        true) {
      rejectedCount += 1;
      continue;
    }

    final coordinate = record.descriptor.coordinate;
    final surfaceDistanceKm = _haversineKm(
      sourceLatitude,
      sourceLongitude,
      coordinate.latitude,
      coordinate.longitude,
    );
    final hypocentralDistanceKm = math.sqrt(
      surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
    );
    final sTravelSeconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: hypocentralDistanceKm,
      depthKm: depthKm,
      pWave: false,
    );
    if (!sTravelSeconds.isFinite || sTravelSeconds < 0) {
      rejectedCount += 1;
      continue;
    }
    final sArrival = sourceOriginTime.add(
      Duration(milliseconds: (sTravelSeconds * 1000).round()),
    );
    final windowStart = sArrival.subtract(preArrivalWindow);
    final windowEnd = sArrival.add(postArrivalWindow);
    final frames = record.observationHistory.frames;
    if (frames.isEmpty) {
      missingHistoryCount += 1;
      continue;
    }
    if (frames.first.dataTime.isAfter(windowStart)) {
      partialHistoryCoverageCount += 1;
    }

    final usableObservations = <SeismicPhysicalObservation>[];
    for (final frame in frames) {
      final observation = frame.physicalObservations[StationValueType.pgv];
      if (observation != null && observation.isUsable) {
        usableObservations.add(observation);
      }
    }
    if (usableObservations.isEmpty) {
      missingPgvHistoryCount += 1;
      continue;
    }

    final uncensoredObservations = usableObservations
        .where(
          (observation) =>
              observation.colorPosition == null ||
              observation.colorPosition! < 0.999,
        )
        .toList(growable: false);
    if (uncensoredObservations.isEmpty) {
      saturatedCount += 1;
      continue;
    }
    final inWindow = uncensoredObservations
        .where(
          (observation) =>
              !observation.dataTime.isBefore(windowStart) &&
              !observation.dataTime.isAfter(windowEnd),
        )
        .toList(growable: false);
    if (inWindow.isEmpty) {
      noPgvInWindowCount += 1;
      final peak = _maximumPgvObservation(uncensoredObservations);
      if (peak.dataTime.isBefore(windowStart)) {
        preSWavePeakExcludedCount += 1;
      } else if (peak.dataTime.isAfter(windowEnd)) {
        postSWavePeakExcludedCount += 1;
      }
      continue;
    }

    final selected = _maximumPgvObservation(inWindow);
    final overallPeak = _maximumPgvObservation(uncensoredObservations);
    if (overallPeak.dataTime.isBefore(windowStart)) {
      preSWavePeakExcludedCount += 1;
    } else if (overallPeak.dataTime.isAfter(windowEnd)) {
      postSWavePeakExcludedCount += 1;
    }
    final magnitude = _invertJmaStylePgvMagnitude(
      observedPgv: selected.value,
      depthKm: depthKm,
      hypocentralDistanceKm: hypocentralDistanceKm,
    );
    if (magnitude == null) {
      rejectedCount += 1;
      continue;
    }
    stationMagnitudes.add(magnitude);
    distancesKm.add(hypocentralDistanceKm);
  }

  final base = <String, Object?>{
    'nied_gif_pgv_s_arrival_window_magnitude_model': model,
    'nied_gif_pgv_s_arrival_window_station_count': stationMagnitudes.length,
    'nied_gif_pgv_s_arrival_window_pre_seconds': -preArrivalWindow.inSeconds,
    'nied_gif_pgv_s_arrival_window_post_seconds': postArrivalWindow.inSeconds,
    'nied_gif_pgv_s_arrival_window_rejected_station_count': rejectedCount,
    'nied_gif_pgv_s_arrival_window_nonparticipant_station_count':
        nonParticipantCount,
    'nied_gif_pgv_s_arrival_window_saturated_station_count': saturatedCount,
    'nied_gif_pgv_s_arrival_window_missing_history_station_count':
        missingHistoryCount,
    'nied_gif_pgv_s_arrival_window_missing_pgv_history_station_count':
        missingPgvHistoryCount,
    'nied_gif_pgv_s_arrival_window_no_pgv_in_window_station_count':
        noPgvInWindowCount,
    'nied_gif_pgv_s_arrival_window_partial_history_coverage_station_count':
        partialHistoryCoverageCount,
    'nied_gif_pgv_s_arrival_window_pre_s_peak_excluded_station_count':
        preSWavePeakExcludedCount,
    'nied_gif_pgv_s_arrival_window_post_s_peak_excluded_station_count':
        postSWavePeakExcludedCount,
    'nied_gif_pgv_s_arrival_window_source_quality':
        'diagnostic_only_experimental_s_window',
  };
  if (stationMagnitudes.length < 3) {
    return {
      ...base,
      'nied_gif_pgv_s_arrival_window_magnitude_supported': false,
    };
  }

  final p25 = _percentile(stationMagnitudes, 0.25);
  final p75 = _percentile(stationMagnitudes, 0.75);
  final iqr = p75 - p25;
  return {
    ...base,
    'nied_gif_pgv_s_arrival_window_magnitude_supported': false,
    'nied_gif_pgv_s_arrival_window_dispersion_acceptable': iqr <= 1.2,
    'nied_gif_pgv_s_arrival_window_median': _median(stationMagnitudes),
    'nied_gif_pgv_s_arrival_window_p25': p25,
    'nied_gif_pgv_s_arrival_window_p75': p75,
    'nied_gif_pgv_s_arrival_window_iqr': iqr,
    'nied_gif_pgv_s_arrival_window_distance_min_km': distancesKm.reduce(
      math.min,
    ),
    'nied_gif_pgv_s_arrival_window_distance_max_km': distancesKm.reduce(
      math.max,
    ),
  };
}

/// Repeats the raw-PGV inversion with an exact-coordinate J-SHIS V4 ARV term.
///
/// This keeps the historical ARV sensitivity experiment available for replay.
/// It is not the Si and Midorikawa (1999) measurement contract: the branch
/// still lacks documented horizontal-component PGV and fault distance.
/// Stations without an exact raw-response-backed ARV term are rejected rather
/// than receiving a nearest-mesh or constant fallback.
Map<String, Object?> niedGifPgvJshisArvMagnitudeDiagnostics({
  required Iterable<SeismicStationEventRecord> stations,
  required double sourceLatitude,
  required double sourceLongitude,
  required double? depthKm,
  required Iterable<NiedJshisArvDiagnosticTerm> jshisArvTerms,
  Set<String> sourceTriggerMemberIds = const {},
}) {
  const model =
      'nied_gif_pgv_si_midorikawa_1999_jshis_arv_sensitivity_diagnostic_v2';
  if (!sourceLatitude.isFinite ||
      !sourceLongitude.isFinite ||
      depthKm == null ||
      !depthKm.isFinite ||
      depthKm < 0) {
    return {
      'nied_gif_pgv_jshis_arv_magnitude_model': model,
      'nied_gif_pgv_jshis_arv_magnitude_supported': false,
      'nied_gif_pgv_jshis_arv_station_count': 0,
      'nied_gif_pgv_jshis_arv_source_quality':
          'missing_or_invalid_source_geometry',
    };
  }

  final termsByStationCode = <String, NiedJshisArvDiagnosticTerm>{
    for (final term in jshisArvTerms) term.stationCode: term,
  };
  final stationMagnitudes = <double>[];
  final distancesKm = <double>[];
  var rejectedCount = 0;
  var nonParticipantCount = 0;
  var saturatedCount = 0;
  var missingExactArvCount = 0;

  for (final record in stations) {
    if (record.descriptor.sensorRole != StationSensorRole.surface) continue;
    final isEventParticipant =
        record.hasTriggered ||
        record.firstRiseAt != null ||
        sourceTriggerMemberIds.contains(record.descriptor.code);
    if (!isEventParticipant) {
      nonParticipantCount += 1;
      continue;
    }
    final provenance = record.provenance[StationValueType.pgv];
    final observation = record.eventPhysicalPeaks[StationValueType.pgv];
    if (observation == null ||
        !observation.isUsable ||
        provenance?.mayBeUsedAsIndependentEvidence != true) {
      rejectedCount += 1;
      continue;
    }
    if (observation.colorPosition != null &&
        observation.colorPosition! >= 0.999) {
      saturatedCount += 1;
      continue;
    }
    final coordinate = record.descriptor.coordinate;
    final arvTerm = termsByStationCode[record.descriptor.code];
    if (arvTerm == null ||
        !arvTerm.matchesExactStationCoordinate(
          code: record.descriptor.code,
          stationLatitude: coordinate.latitude,
          stationLongitude: coordinate.longitude,
        )) {
      missingExactArvCount += 1;
      continue;
    }
    final surfaceDistanceKm = _haversineKm(
      sourceLatitude,
      sourceLongitude,
      coordinate.latitude,
      coordinate.longitude,
    );
    final hypocentralDistanceKm = math.sqrt(
      surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
    );
    final magnitude = _invertJmaStylePgvMagnitude(
      observedPgv: observation.value / arvTerm.arv,
      depthKm: depthKm,
      hypocentralDistanceKm: hypocentralDistanceKm,
    );
    if (magnitude == null) {
      rejectedCount += 1;
      continue;
    }
    stationMagnitudes.add(magnitude);
    distancesKm.add(hypocentralDistanceKm);
  }

  if (stationMagnitudes.length < 3) {
    return {
      'nied_gif_pgv_jshis_arv_magnitude_model': model,
      'nied_gif_pgv_jshis_arv_magnitude_supported': false,
      'nied_gif_pgv_jshis_arv_station_count': stationMagnitudes.length,
      'nied_gif_pgv_jshis_arv_missing_exact_station_count':
          missingExactArvCount,
      'nied_gif_pgv_jshis_arv_rejected_station_count': rejectedCount,
      'nied_gif_pgv_jshis_arv_nonparticipant_station_count':
          nonParticipantCount,
      'nied_gif_pgv_jshis_arv_saturated_station_count': saturatedCount,
      'nied_gif_pgv_jshis_arv_source_quality':
          'diagnostic_only_exact_arv_insufficient_station_coverage',
    };
  }

  final median = _median(stationMagnitudes);
  final p25 = _percentile(stationMagnitudes, 0.25);
  final p75 = _percentile(stationMagnitudes, 0.75);
  final iqr = p75 - p25;
  return {
    'nied_gif_pgv_jshis_arv_magnitude_model': model,
    'nied_gif_pgv_jshis_arv_magnitude_supported': false,
    'nied_gif_pgv_jshis_arv_dispersion_acceptable': iqr <= 1.2,
    'nied_gif_pgv_jshis_arv_median': median,
    'nied_gif_pgv_jshis_arv_p25': p25,
    'nied_gif_pgv_jshis_arv_p75': p75,
    'nied_gif_pgv_jshis_arv_iqr': iqr,
    'nied_gif_pgv_jshis_arv_station_count': stationMagnitudes.length,
    'nied_gif_pgv_jshis_arv_missing_exact_station_count': missingExactArvCount,
    'nied_gif_pgv_jshis_arv_rejected_station_count': rejectedCount,
    'nied_gif_pgv_jshis_arv_nonparticipant_station_count': nonParticipantCount,
    'nied_gif_pgv_jshis_arv_saturated_station_count': saturatedCount,
    'nied_gif_pgv_jshis_arv_distance_min_km': distancesKm.reduce(math.min),
    'nied_gif_pgv_jshis_arv_distance_max_km': distancesKm.reduce(math.max),
    'nied_gif_pgv_jshis_arv_source_quality':
        'diagnostic_only_blocked_exact_jshis_arv_but_nied_vcmap_contract_unknown',
  };
}

/// Applies a distance-weighted PGV sensitivity experiment to the same raw GIF
/// candidates. The external onset-quality weight is intentionally omitted:
/// the raw NIED event record has no corresponding independently measured
/// onset-quality value. It remains blocked because the measurement and
/// distance contracts are unverified.
Map<String, Object?> niedGifPgvDistanceWeightedMagnitudeDiagnostics({
  required Iterable<SeismicStationEventRecord> stations,
  required double sourceLatitude,
  required double sourceLongitude,
  required double? depthKm,
  Set<String> sourceTriggerMemberIds = const {},
  int nearestStationCount = 8,
}) {
  const model =
      'nied_gif_pgv_distance_weighted_si_midorikawa_1999_sensitivity_v2';
  if (nearestStationCount < 3) {
    throw ArgumentError.value(
      nearestStationCount,
      'nearestStationCount',
      'Must retain at least three stations for a magnitude diagnostic.',
    );
  }
  if (!sourceLatitude.isFinite ||
      !sourceLongitude.isFinite ||
      depthKm == null ||
      !depthKm.isFinite ||
      depthKm < 0) {
    return {
      'nied_gif_pgv_distance_weighted_magnitude_model': model,
      'nied_gif_pgv_distance_weighted_magnitude_supported': false,
      'nied_gif_pgv_distance_weighted_station_count': 0,
      'nied_gif_pgv_distance_weighted_source_quality':
          'missing_or_invalid_source_geometry',
    };
  }

  final candidates = <({double magnitude, double distanceKm})>[];
  var rejectedCount = 0;
  var nonParticipantCount = 0;
  var saturatedCount = 0;
  for (final record in stations) {
    if (record.descriptor.sensorRole != StationSensorRole.surface) continue;
    final isEventParticipant =
        record.hasTriggered ||
        record.firstRiseAt != null ||
        sourceTriggerMemberIds.contains(record.descriptor.code);
    if (!isEventParticipant) {
      nonParticipantCount += 1;
      continue;
    }
    final provenance = record.provenance[StationValueType.pgv];
    final observation = record.eventPhysicalPeaks[StationValueType.pgv];
    if (observation == null ||
        !observation.isUsable ||
        provenance?.mayBeUsedAsIndependentEvidence != true) {
      rejectedCount += 1;
      continue;
    }
    if (observation.colorPosition != null &&
        observation.colorPosition! >= 0.999) {
      saturatedCount += 1;
      continue;
    }
    final surfaceDistanceKm = _haversineKm(
      sourceLatitude,
      sourceLongitude,
      record.descriptor.coordinate.latitude,
      record.descriptor.coordinate.longitude,
    );
    final hypocentralDistanceKm = math.sqrt(
      surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
    );
    final magnitude = _invertJmaStylePgvMagnitude(
      observedPgv: observation.value,
      depthKm: depthKm,
      hypocentralDistanceKm: hypocentralDistanceKm,
    );
    if (magnitude == null) {
      rejectedCount += 1;
      continue;
    }
    candidates.add((magnitude: magnitude, distanceKm: surfaceDistanceKm));
  }

  candidates.sort((left, right) => left.distanceKm.compareTo(right.distanceKm));
  final nearest = candidates.take(nearestStationCount).toList(growable: false);
  if (nearest.length < 3) {
    return {
      'nied_gif_pgv_distance_weighted_magnitude_model': model,
      'nied_gif_pgv_distance_weighted_magnitude_supported': false,
      'nied_gif_pgv_distance_weighted_station_count': nearest.length,
      'nied_gif_pgv_distance_weighted_nearest_station_limit':
          nearestStationCount,
      'nied_gif_pgv_distance_weighted_candidate_count': candidates.length,
      'nied_gif_pgv_distance_weighted_rejected_station_count': rejectedCount,
      'nied_gif_pgv_distance_weighted_nonparticipant_station_count':
          nonParticipantCount,
      'nied_gif_pgv_distance_weighted_saturated_station_count': saturatedCount,
      'nied_gif_pgv_distance_weighted_source_quality':
          'diagnostic_only_unvalidated_no_onset_quality',
    };
  }

  final magnitudes = nearest.map((candidate) => candidate.magnitude).toList();
  final p25 = _percentile(magnitudes, 0.25);
  final p75 = _percentile(magnitudes, 0.75);
  final iqr = p75 - p25;
  final weightedMedian = _weightedMedian(
    magnitudes,
    nearest
        .map((candidate) => 1.0 / (1.0 + candidate.distanceKm / 40.0))
        .toList(growable: false),
  );
  return {
    'nied_gif_pgv_distance_weighted_magnitude_model': model,
    'nied_gif_pgv_distance_weighted_magnitude_supported': false,
    'nied_gif_pgv_distance_weighted_dispersion_acceptable': iqr <= 1.2,
    'nied_gif_pgv_distance_weighted_median': weightedMedian,
    'nied_gif_pgv_distance_weighted_unweighted_median': _median(magnitudes),
    'nied_gif_pgv_distance_weighted_p25': p25,
    'nied_gif_pgv_distance_weighted_p75': p75,
    'nied_gif_pgv_distance_weighted_iqr': iqr,
    'nied_gif_pgv_distance_weighted_station_count': nearest.length,
    'nied_gif_pgv_distance_weighted_nearest_station_limit': nearestStationCount,
    'nied_gif_pgv_distance_weighted_candidate_count': candidates.length,
    'nied_gif_pgv_distance_weighted_rejected_station_count': rejectedCount,
    'nied_gif_pgv_distance_weighted_nonparticipant_station_count':
        nonParticipantCount,
    'nied_gif_pgv_distance_weighted_saturated_station_count': saturatedCount,
    'nied_gif_pgv_distance_weighted_max_distance_km': nearest.last.distanceKm,
    'nied_gif_pgv_distance_weighted_source_quality':
        'diagnostic_only_blocked_nied_vcmap_measurement_contract_unknown',
  };
}

/// Produces the legacy continuous-intensity comparison against the exact
/// geometry and event-participant gate used by the PGV diagnostic.
///
/// This is a diagnostics-only comparator. Its result is not a production or
/// official magnitude and must not be exposed through [SourceEstimate].
Map<String, Object?> niedGifJmaStyleIntensityMagnitudeDiagnostics({
  required Iterable<SeismicStationEventRecord> stations,
  required double sourceLatitude,
  required double sourceLongitude,
  required double? depthKm,
  Set<String> sourceTriggerMemberIds = const {},
}) {
  const model =
      'si_midorikawa_1999_pgv_derived_intensity_hypocentral_placeholder_v2';
  if (!sourceLatitude.isFinite ||
      !sourceLongitude.isFinite ||
      depthKm == null ||
      !depthKm.isFinite ||
      depthKm < 0) {
    return {
      'nied_gif_jma_style_magnitude_model': model,
      'nied_gif_jma_style_magnitude_supported': false,
      'nied_gif_jma_style_station_count': 0,
      'nied_gif_jma_style_source_quality': 'missing_or_invalid_source_geometry',
    };
  }

  const minimumUsableIntensity = -0.8;
  final stationMagnitudes = <double>[];
  var rejectedCount = 0;
  var nonParticipantCount = 0;
  for (final record in stations) {
    if (record.descriptor.sensorRole != StationSensorRole.surface) continue;
    final isEventParticipant =
        record.hasTriggered ||
        record.firstRiseAt != null ||
        sourceTriggerMemberIds.contains(record.descriptor.code);
    if (!isEventParticipant) {
      nonParticipantCount += 1;
      continue;
    }
    final observedIntensity = math.max(
      record.peakValue ?? double.negativeInfinity,
      record.lastValue ?? double.negativeInfinity,
    );
    if (!observedIntensity.isFinite ||
        observedIntensity < minimumUsableIntensity) {
      rejectedCount += 1;
      continue;
    }
    final surfaceDistanceKm = _haversineKm(
      sourceLatitude,
      sourceLongitude,
      record.descriptor.coordinate.latitude,
      record.descriptor.coordinate.longitude,
    );
    final hypocentralDistanceKm = math.sqrt(
      surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
    );
    final magnitude = _invertJmaStyleIntensityMagnitude(
      observedIntensity: observedIntensity,
      depthKm: depthKm,
      hypocentralDistanceKm: hypocentralDistanceKm,
    );
    if (magnitude == null) {
      rejectedCount += 1;
      continue;
    }
    stationMagnitudes.add(magnitude);
  }

  if (stationMagnitudes.length < 3) {
    return {
      'nied_gif_jma_style_magnitude_model': model,
      'nied_gif_jma_style_magnitude_supported': false,
      'nied_gif_jma_style_station_count': stationMagnitudes.length,
      'nied_gif_jma_style_rejected_station_count': rejectedCount,
      'nied_gif_jma_style_nonparticipant_station_count': nonParticipantCount,
      'nied_gif_jma_style_minimum_station_intensity': minimumUsableIntensity,
      'nied_gif_jma_style_source_quality': 'diagnostic_only_unvalidated',
    };
  }

  final median = _median(stationMagnitudes);
  final p25 = _percentile(stationMagnitudes, 0.25);
  final p75 = _percentile(stationMagnitudes, 0.75);
  final iqr = p75 - p25;
  return {
    'nied_gif_jma_style_magnitude_model': model,
    'nied_gif_jma_style_magnitude_supported': false,
    'nied_gif_jma_style_dispersion_acceptable': iqr <= 1.2,
    'nied_gif_jma_style_median': median,
    'nied_gif_jma_style_p25': p25,
    'nied_gif_jma_style_p75': p75,
    'nied_gif_jma_style_iqr': iqr,
    'nied_gif_jma_style_station_count': stationMagnitudes.length,
    'nied_gif_jma_style_rejected_station_count': rejectedCount,
    'nied_gif_jma_style_nonparticipant_station_count': nonParticipantCount,
    'nied_gif_jma_style_minimum_station_intensity': minimumUsableIntensity,
    'nied_gif_jma_style_source_quality':
        'diagnostic_only_blocked_nied_intensity_to_pgv_contract_unverified',
  };
}

double? _invertJmaStylePgvMagnitude({
  required double observedPgv,
  required double depthKm,
  required double hypocentralDistanceKm,
}) {
  if (!observedPgv.isFinite ||
      observedPgv <= 0 ||
      !depthKm.isFinite ||
      depthKm < 0 ||
      !hypocentralDistanceKm.isFinite ||
      hypocentralDistanceKm <= 0) {
    return null;
  }
  var low = 0.0;
  var high = 9.5;
  for (var i = 0; i < 36; i++) {
    final middle = (low + high) / 2.0;
    final predicted = _siMidorikawa1999Pgv600Placeholder(
      magnitude: middle,
      depthKm: depthKm,
      hypocentralDistanceKm: hypocentralDistanceKm,
    );
    if (predicted < observedPgv) {
      low = middle;
    } else {
      high = middle;
    }
  }
  final magnitude = (low + high) / 2.0;
  return magnitude.isFinite ? magnitude.clamp(0.0, 9.5) : null;
}

double? _invertSiMidorikawa1999SurfacePgaMagnitude({
  required double observedPgaGal,
  required double averageFocalDepthKm,
  required double faultDistanceKm,
  required NiedPgaFaultType faultType,
}) {
  if (!observedPgaGal.isFinite ||
      observedPgaGal <= 0 ||
      !averageFocalDepthKm.isFinite ||
      averageFocalDepthKm < 0 ||
      !faultDistanceKm.isFinite ||
      faultDistanceKm <= 0) {
    return null;
  }
  var low = 0.0;
  var high = 9.5;
  final highestSearchAmplitude = _siMidorikawa1999SurfacePgaGal(
    magnitude: high,
    averageFocalDepthKm: averageFocalDepthKm,
    faultDistanceKm: faultDistanceKm,
    faultType: faultType,
  );
  if (!highestSearchAmplitude.isFinite ||
      observedPgaGal > highestSearchAmplitude) {
    return null;
  }
  for (var index = 0; index < 36; index++) {
    final middle = (low + high) / 2.0;
    final predicted = _siMidorikawa1999SurfacePgaGal(
      magnitude: middle,
      averageFocalDepthKm: averageFocalDepthKm,
      faultDistanceKm: faultDistanceKm,
      faultType: faultType,
    );
    if (predicted < observedPgaGal) {
      low = middle;
    } else {
      high = middle;
    }
  }
  final magnitude = (low + high) / 2.0;
  return magnitude.isFinite ? magnitude.clamp(0.0, 9.5) : null;
}

double _siMidorikawa1999SurfacePgaGal({
  required double magnitude,
  required double averageFocalDepthKm,
  required double faultDistanceKm,
  required NiedPgaFaultType faultType,
}) {
  final faultTypeTerm = switch (faultType) {
    NiedPgaFaultType.crustal => 0.00,
    NiedPgaFaultType.interPlate => 0.01,
    NiedPgaFaultType.intraPlate => 0.22,
  };
  // Equation (6) supplies the magnitude-dependent near-source term c.
  final nearSourceTerm = 0.0055 * math.pow(10.0, 0.50 * magnitude);
  final logPga =
      0.50 * magnitude +
      0.0043 * averageFocalDepthKm +
      faultTypeTerm -
      0.61 -
      _log10(faultDistanceKm + nearSourceTerm) -
      0.003 * faultDistanceKm;
  return math.pow(10.0, logPga).toDouble();
}

SeismicPhysicalObservation _maximumPgvObservation(
  Iterable<SeismicPhysicalObservation> observations,
) {
  return observations.reduce(
    (current, candidate) =>
        candidate.value > current.value ? candidate : current,
  );
}

double _siMidorikawa1999Pgv600Placeholder({
  required double magnitude,
  required double depthKm,
  required double hypocentralDistanceKm,
}) {
  final mw = magnitude - 0.171;
  final distance = math.max(hypocentralDistanceKm, 1.0);
  final logPgv600 =
      0.58 * mw +
      0.0038 * depthKm -
      1.29 -
      _log10(distance + 0.0028 * math.pow(10, 0.50 * mw)) -
      0.002 * distance;
  return 0.90 * math.pow(10, logPgv600).toDouble();
}

double? _invertJmaStyleIntensityMagnitude({
  required double observedIntensity,
  required double depthKm,
  required double hypocentralDistanceKm,
}) {
  if (!observedIntensity.isFinite ||
      !depthKm.isFinite ||
      depthKm < 0 ||
      !hypocentralDistanceKm.isFinite ||
      hypocentralDistanceKm <= 0) {
    return null;
  }
  var low = 0.0;
  var high = 9.5;
  for (var i = 0; i < 36; i++) {
    final middle = (low + high) / 2.0;
    final predicted = _jmaStyleInstrumentalIntensity(
      magnitude: middle,
      depthKm: depthKm,
      hypocentralDistanceKm: hypocentralDistanceKm,
    );
    if (predicted < observedIntensity) {
      low = middle;
    } else {
      high = middle;
    }
  }
  final magnitude = (low + high) / 2.0;
  return magnitude.isFinite ? magnitude.clamp(0.0, 9.5) : null;
}

double _jmaStyleInstrumentalIntensity({
  required double magnitude,
  required double depthKm,
  required double hypocentralDistanceKm,
}) {
  final surfacePgv = _siMidorikawa1999Pgv600Placeholder(
    magnitude: magnitude,
    depthKm: depthKm,
    hypocentralDistanceKm: hypocentralDistanceKm,
  );
  if (surfacePgv <= 0) return -3.0;
  return 2.68 + 1.72 * _log10(surfacePgv);
}

double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusKm = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180.0;
  final dLon = (lon2 - lon1) * math.pi / 180.0;
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1 * math.pi / 180.0) *
          math.cos(lat2 * math.pi / 180.0) *
          math.pow(math.sin(dLon / 2), 2);
  return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _log10(num value) => math.log(value) / math.ln10;

double _median(List<double> values) => _percentile(values, 0.5);

double _weightedMedian(List<double> values, List<double> weights) {
  if (values.isEmpty || values.length != weights.length) {
    throw ArgumentError('values and weights must be non-empty and aligned');
  }
  final items = <({double value, double weight})>[
    for (var index = 0; index < values.length; index++)
      (value: values[index], weight: math.max(weights[index], 0.0)),
  ]..sort((left, right) => left.value.compareTo(right.value));
  final totalWeight = items.fold<double>(0.0, (sum, item) => sum + item.weight);
  if (totalWeight <= 0) return _median(values);
  var cumulativeWeight = 0.0;
  for (final item in items) {
    cumulativeWeight += item.weight;
    if (cumulativeWeight >= totalWeight / 2.0) return item.value;
  }
  return items.last.value;
}

double _percentile(List<double> values, double fraction) {
  final sorted = List<double>.from(values)..sort();
  final index = (sorted.length - 1) * fraction;
  final lower = index.floor();
  final upper = index.ceil();
  if (lower == upper) return sorted[lower];
  return sorted[lower] + (sorted[upper] - sorted[lower]) * (index - lower);
}
