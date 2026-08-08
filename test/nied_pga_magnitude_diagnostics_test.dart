import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutterrhythmquake/core/source_estimation/nied_pgv_magnitude_diagnostics.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';

void main() {
  const pgaProvenance = ObservationProvenance(
    origin: ObservationOrigin.niedGifLayer,
    quantity: StationValueType.pga,
    layerId: 'acmap_s',
    isIndependentPhysicalMeasurement: true,
  );

  SeismicStationEventRecord record({
    required String code,
    required double pgaGal,
    required double colorPosition,
  }) {
    final timestamp = DateTime.utc(2026, 8, 2, 12, 0, 3);
    final result = SeismicStationEventRecord(
      descriptor: SeismicStationDescriptor(
        stationId: code,
        code: code,
        sourceId: 'nied',
        network: 'K-NET',
        coordinate: const LatLng(35.0, 140.0),
        sensorRole: StationSensorRole.surface,
      ),
      firstObservedAt: timestamp,
      firstTriggerAt: timestamp,
    );
    result.provenance[StationValueType.pga] = pgaProvenance;
    result.eventPhysicalPeaks[StationValueType.pga] =
        SeismicPhysicalObservation(
          quantity: StationValueType.pga,
          layerId: 'acmap_s',
          value: pgaGal,
          colorPosition: colorPosition,
          dataTime: timestamp,
          receivedAt: timestamp,
        );
    return result;
  }

  test(
    'inverts independent surface PGA with supplied reviewed fault geometry',
    () {
      const magnitude = 6.7;
      const depthKm = 37.0;
      const distancesKm = {'A': 25.0, 'B': 75.0, 'C': 150.0};
      final diagnostics = niedGifPgaMagnitudeDiagnostics(
        stations: [
          for (final entry in distancesKm.entries)
            record(
              code: entry.key,
              pgaGal: _surfacePgaGal(
                magnitude: magnitude,
                depthKm: depthKm,
                faultDistanceKm: entry.value,
                faultType: NiedPgaFaultType.interPlate,
              ),
              colorPosition: 0.60,
            ),
        ],
        averageFocalDepthKm: depthKm,
        faultType: NiedPgaFaultType.interPlate,
        distanceDefinition: 'reviewed_shortest_rupture_distance_km',
        faultDistanceKmFor: (record) => distancesKm[record.descriptor.code],
      );

      expect(
        diagnostics['nied_gif_pga_magnitude_model'],
        'si_midorikawa_1999_surface_pga_fault_distance_v1',
      );
      expect(diagnostics['nied_gif_pga_magnitude_supported'], isFalse);
      expect(diagnostics['nied_gif_pga_dispersion_acceptable'], isTrue);
      expect(diagnostics['nied_gif_pga_station_count'], 3);
      expect(diagnostics['nied_gif_pga_median'] as double, closeTo(6.7, 1e-5));
      expect(diagnostics['nied_gif_pga_iqr'] as double, lessThan(1e-5));
    },
  );

  test('excludes PGA palette ceiling observations as censored values', () {
    const distancesKm = {'A': 25.0, 'B': 75.0, 'C': 150.0};
    final diagnostics = niedGifPgaMagnitudeDiagnostics(
      stations: [
        record(code: 'A', pgaGal: 40.0, colorPosition: 0.60),
        record(code: 'B', pgaGal: 12.0, colorPosition: 0.56),
        record(code: 'C', pgaGal: 998.5, colorPosition: 1.0),
      ],
      averageFocalDepthKm: 20.0,
      faultType: NiedPgaFaultType.crustal,
      distanceDefinition: 'reviewed_shortest_rupture_distance_km',
      faultDistanceKmFor: (record) => distancesKm[record.descriptor.code],
    );

    expect(diagnostics['nied_gif_pga_magnitude_supported'], isFalse);
    expect(diagnostics['nied_gif_pga_station_count'], 2);
    expect(diagnostics['nied_gif_pga_saturated_station_count'], 1);
  });

  test('rejects PGA values above the attenuation relation search ceiling', () {
    const distancesKm = {'A': 25.0, 'B': 75.0, 'C': 150.0, 'D': 200.0};
    final diagnostics = niedGifPgaMagnitudeDiagnostics(
      stations: [
        record(code: 'A', pgaGal: 40.0, colorPosition: 0.60),
        record(code: 'B', pgaGal: 12.0, colorPosition: 0.56),
        record(code: 'C', pgaGal: 4.0, colorPosition: 0.52),
        // This is deliberately not palette-censored. It is a finite input
        // above the model's M <= 9.5 amplitude range at 200 km, which must
        // not be reported as the numerical search upper bound.
        record(code: 'D', pgaGal: 1e9, colorPosition: 0.90),
      ],
      averageFocalDepthKm: 20.0,
      faultType: NiedPgaFaultType.crustal,
      distanceDefinition: 'reviewed_shortest_rupture_distance_km',
      faultDistanceKmFor: (record) => distancesKm[record.descriptor.code],
    );

    expect(diagnostics['nied_gif_pga_station_count'], 3);
    expect(diagnostics['nied_gif_pga_out_of_model_range_station_count'], 1);
    expect(diagnostics['nied_gif_pga_magnitude_supported'], isFalse);
    expect(diagnostics['nied_gif_pga_median'], isNot(9.5));
  });
}

double _surfacePgaGal({
  required double magnitude,
  required double depthKm,
  required double faultDistanceKm,
  required NiedPgaFaultType faultType,
}) {
  final faultTypeTerm = switch (faultType) {
    NiedPgaFaultType.crustal => 0.00,
    NiedPgaFaultType.interPlate => 0.01,
    NiedPgaFaultType.intraPlate => 0.22,
  };
  final nearSourceTerm = 0.0055 * math.pow(10.0, 0.50 * magnitude);
  final logPga =
      0.50 * magnitude +
      0.0043 * depthKm +
      faultTypeTerm -
      0.61 -
      math.log(faultDistanceKm + nearSourceTerm) / math.ln10 -
      0.003 * faultDistanceKm;
  return math.pow(10.0, logPga).toDouble();
}
