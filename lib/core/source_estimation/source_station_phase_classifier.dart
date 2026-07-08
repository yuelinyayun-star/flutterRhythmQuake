// ignore_for_file: unused_element

import 'dart:math' as math;

import '../calculator.dart';
import '../travel_time_service.dart';
import 'source_estimation_models.dart';
import 'package:latlong2/latlong.dart';

enum EstimatedStationPhase { p, s, other }

class EstimatedStationPhaseRecord {
  final SeismicStationEventRecord? station;
  final String stationCode;
  final LatLng coordinate;
  final EstimatedStationPhase phase;
  final double? residualSeconds;

  const EstimatedStationPhaseRecord({
    this.station,
    required this.stationCode,
    required this.coordinate,
    required this.phase,
    this.residualSeconds,
  });
}

class SourceStationPhaseSnapshot {
  final List<EstimatedStationPhaseRecord> stations;

  const SourceStationPhaseSnapshot(this.stations);

  int count(EstimatedStationPhase phase) =>
      stations.where((item) => item.phase == phase).length;
}

/// Reads station P/S/O labels emitted by the kotoho7 Scratch JS receiver.
///
/// Do not infer phases locally here. Production source-estimation display must
/// stay tied to the upstream Scratch `ten:推定用` state so the marker counts and
/// labels match the algorithm actually used for the estimate.
class SourceStationPhaseClassifier {
  const SourceStationPhaseClassifier();

  SourceStationPhaseSnapshot classify(SeismicActiveEvent event) =>
      _classifyFromKotoho7Js(event);

  SourceStationPhaseSnapshot _classifyFromKotoho7Js(SeismicActiveEvent event) {
    final rawStations =
        event.estimate?.diagnostics['best_source_phase_stations'];
    if (rawStations is! Iterable) return const SourceStationPhaseSnapshot([]);
    final recordsByCode = {
      for (final record in event.records) record.descriptor.code: record,
      for (final record in event.records) record.descriptor.stationId: record,
    };
    final recordsByScratchTenIndex = {
      for (final record in event.records)
        if (record.descriptor.tags['scratch_station_index'] != null)
          record.descriptor.tags['scratch_station_index']!: record,
    };
    final stations = <EstimatedStationPhaseRecord>[];
    for (final item in rawStations) {
      if (item is! Map) continue;
      final rawCode = item['code']?.toString();
      final tenIndex = item['tenIndex']?.toString();
      final station =
          (rawCode == null || rawCode.isEmpty
              ? null
              : recordsByCode[rawCode]) ??
          (tenIndex == null ? null : recordsByScratchTenIndex[tenIndex]);
      final code = rawCode == null || rawCode.isEmpty
          ? station?.descriptor.code
          : rawCode;
      if (code == null || code.isEmpty) continue;
      final latitude = _doubleFromKotoho7Js(item['lat']);
      final longitude =
          _doubleFromKotoho7Js(item['lng']) ??
          _doubleFromKotoho7Js(item['lon']);
      if (latitude == null || longitude == null) continue;
      stations.add(
        EstimatedStationPhaseRecord(
          station: station ?? recordsByCode[code],
          stationCode: code,
          coordinate: LatLng(latitude, longitude),
          phase: _phaseFromKotoho7Js(item['phase']),
          residualSeconds: _doubleFromKotoho7Js(item['residualSeconds']),
        ),
      );
    }
    return SourceStationPhaseSnapshot(stations);
  }

  EstimatedStationPhase _phaseFromKotoho7Js(Object? value) {
    switch (value?.toString().toLowerCase()) {
      case 'p':
        return EstimatedStationPhase.p;
      case 's':
        return EstimatedStationPhase.s;
      default:
        return EstimatedStationPhase.other;
    }
  }

  double? _doubleFromKotoho7Js(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  // Kept only as an internal diagnostic reference while migrating display and
  // tests to the kotoho7 Scratch JS output. Do not call this from production
  // source-estimation display paths; `classify()` intentionally has no fallback.
  SourceStationPhaseSnapshot
  _classifyByLegacyFlutterInferenceForDiagnosticsOnly(
    SeismicActiveEvent event,
  ) {
    final estimate = event.estimate;
    final originTime = estimate?.originTime;
    if (estimate == null || originTime == null) {
      return const SourceStationPhaseSnapshot([]);
    }

    final memberIds = _memberStationIds(event.metadata);
    final records = event.records
        .where((record) {
          if (memberIds.isNotEmpty) {
            return memberIds.contains(record.descriptor.stationId) ||
                memberIds.contains(record.descriptor.code);
          }
          return record.hasTriggered;
        })
        .toList(growable: false);

    return SourceStationPhaseSnapshot([
      for (final record in records)
        _classifyRecordByLegacyFlutterInference(
          record,
          latitude: estimate.latitude,
          longitude: estimate.longitude,
          depthKm: estimate.depthKm ?? 0,
          originTime: originTime,
        ),
    ]);
  }

  EstimatedStationPhaseRecord _classifyRecordByLegacyFlutterInference(
    SeismicStationEventRecord record, {
    required double latitude,
    required double longitude,
    required double depthKm,
    required DateTime originTime,
  }) {
    final triggerTime = record.firstTriggerAt ?? record.firstRiseAt;
    if (triggerTime == null) {
      return EstimatedStationPhaseRecord(
        station: record,
        stationCode: record.descriptor.code,
        coordinate: record.descriptor.coordinate,
        phase: EstimatedStationPhase.other,
      );
    }

    final coordinate = record.descriptor.coordinate;
    final distanceKm = QuakeCalculator.haversineDistance(
      latitude,
      longitude,
      coordinate.latitude,
      coordinate.longitude,
    );
    final pTime = _reachTimeByLegacyFlutterInference(
      isPWave: true,
      depthKm: depthKm,
      distanceKm: distanceKm,
    );
    final sTime = _reachTimeByLegacyFlutterInference(
      isPWave: false,
      depthKm: depthKm,
      distanceKm: distanceKm,
    );
    final observedSeconds =
        triggerTime.difference(originTime).inMilliseconds / 1000.0;
    final pResidual = (observedSeconds - pTime).abs();
    final sResidual = (observedSeconds - sTime).abs();
    final nearestResidual = math.min(pResidual, sResidual);

    // One-second source frames and threshold lag require a wider window than
    // waveform pickers. Large outliers remain O instead of forcing P or S.
    final phaseGap = math.max(0.0, sTime - pTime);
    final acceptedResidual = math.max(2.5, phaseGap * 0.55);
    if (observedSeconds < -1.0 || nearestResidual > acceptedResidual) {
      return EstimatedStationPhaseRecord(
        station: record,
        stationCode: record.descriptor.code,
        coordinate: record.descriptor.coordinate,
        phase: EstimatedStationPhase.other,
        residualSeconds: nearestResidual,
      );
    }

    return EstimatedStationPhaseRecord(
      station: record,
      stationCode: record.descriptor.code,
      coordinate: record.descriptor.coordinate,
      phase: pResidual <= sResidual
          ? EstimatedStationPhase.p
          : EstimatedStationPhase.s,
      residualSeconds: nearestResidual,
    );
  }

  double _reachTimeByLegacyFlutterInference({
    required bool isPWave,
    required double depthKm,
    required double distanceKm,
  }) {
    final travelTimes = TravelTimeService();
    if (travelTimes.isLoaded) {
      final table = distanceKm <= 2000 ? 'jma2001' : 'jb';
      final value = travelTimes.calcReachTime(
        table,
        isPWave,
        depthKm,
        distanceKm,
      );
      if (value > 0 && value.isFinite) return value;
    }
    final speed = isPWave
        ? QuakeCalculator.pWaveSpeed
        : QuakeCalculator.sWaveSpeed;
    final hypocentralDistance = math.sqrt(
      distanceKm * distanceKm + depthKm * depthKm,
    );
    return hypocentralDistance / speed;
  }

  Set<String> _memberStationIds(Map<String, Object?> metadata) {
    final raw = metadata['source_trigger_member_ids'];
    if (raw is! Iterable) return const {};
    return raw.whereType<String>().toSet();
  }
}
