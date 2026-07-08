import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimate_quality.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('computes RMS residual and azimuthal gap from associated stations', () {
    final origin = DateTime.utc(2026, 6, 21);
    final event = _event(origin, confidence: 0.9);
    event.metadata['source_trigger_member_ids'] = [
      'north',
      'east',
      'south',
      'west',
    ];
    event.stationRecords.addAll({
      'north': _record('north', const LatLng(1, 0), origin, 18),
      'east': _record('east', const LatLng(0, 1), origin, 18),
      'south': _record('south', const LatLng(-1, 0), origin, 18),
      'west': _record('west', const LatLng(0, -1), origin, 18),
    });

    final quality = const SourceEstimateQualityCalculator().calculate(event);

    expect(quality, isNotNull);
    expect(quality!.associatedStationCount, 4);
    expect(quality.residualStationCount, 4);
    expect(quality.azimuthalGapDegrees, closeTo(90, 0.01));
    expect(quality.rmsResidualSeconds, isNotNull);
    expect(quality.horizontalUncertaintyP90Km, isNull);
    expect(quality.grade, 'C', reason: 'four stations cap quality at C');
  });

  test('returns D when timing residual or azimuth coverage is unavailable', () {
    final origin = DateTime.utc(2026, 6, 21);
    final event = _event(origin, confidence: 0.95);

    final quality = const SourceEstimateQualityCalculator().calculate(event);

    expect(quality, isNotNull);
    expect(quality!.grade, 'D');
    expect(quality.rmsResidualSeconds, isNull);
    expect(quality.azimuthalGapDegrees, isNull);
  });

  test(
    'uses geometry uncertainty diagnostics to downgrade risky estimates',
    () {
      final origin = DateTime.utc(2026, 6, 21);
      final event = _event(
        origin,
        confidence: 0.95,
        diagnostics: const {
          'horizontal_uncertainty_p50_km': 95.0,
          'horizontal_uncertainty_p90_km': 240.0,
          'station_geometry': 'one_sided',
          'search_boundary_hit': true,
        },
      );
      event.metadata['source_trigger_member_ids'] = [
        'north',
        'east',
        'south',
        'west',
      ];
      event.stationRecords.addAll({
        'north': _record('north', const LatLng(1, 0), origin, 18),
        'east': _record('east', const LatLng(0, 1), origin, 18),
        'south': _record('south', const LatLng(-1, 0), origin, 18),
        'west': _record('west', const LatLng(0, -1), origin, 18),
      });

      final quality = const SourceEstimateQualityCalculator().calculate(event);

      expect(quality, isNotNull);
      expect(quality!.grade, 'D');
      expect(quality.horizontalUncertaintyP50Km, 95);
      expect(quality.horizontalUncertaintyP90Km, 240);
      expect(quality.stationGeometry, 'one_sided');
      expect(quality.searchBoundaryHit, isTrue);
    },
  );
}

SeismicActiveEvent _event(
  DateTime origin, {
  required double confidence,
  Map<String, Object?> diagnostics = const {},
}) {
  return SeismicActiveEvent(
    eventId: 'quality-event',
    sourceId: 'nied',
    startedAt: origin,
    updatedAt: origin,
    stageName: 'confirmed',
    maxShindo: 1,
    estimate: SourceEstimate(
      latitude: 0,
      longitude: 0,
      depthKm: 10,
      originTime: origin,
      confidence: confidence,
      method: 'test',
      supportingStationCount: 4,
      diagnostics: diagnostics,
    ),
  );
}

SeismicStationEventRecord _record(
  String code,
  LatLng coordinate,
  DateTime origin,
  int triggerSeconds,
) {
  final trigger = origin.add(Duration(seconds: triggerSeconds));
  return SeismicStationEventRecord(
    descriptor: SeismicStationDescriptor(
      stationId: code,
      code: code,
      sourceId: 'nied',
      network: 'test',
      coordinate: coordinate,
    ),
    firstObservedAt: trigger,
    firstRiseAt: trigger,
    firstTriggerAt: trigger,
    state: StationLifecycleState.triggered,
  );
}
