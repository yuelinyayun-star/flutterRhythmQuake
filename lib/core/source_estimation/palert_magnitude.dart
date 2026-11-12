import 'dart:math' as math;
import '../cwa_intensity_prediction.dart';

typedef PAlertMagnitudeSample = ({
  String id,
  double pga,
  double lat,
  double lng,
});

/// Preliminary equivalent magnitude: invert the APP's existing Taiwan PGA
/// attenuation model, pairing each original peak with that station's distance.
/// This is not an official P-Alert ML solution or a waveform magnitude method.
({double magnitude, Map<String, Object?> diagnostics})? palertMagnitude({
  required double lat,
  required double lng,
  required double depth,
  required Iterable<PAlertMagnitudeSample> samples,
}) {
  if (!lat.isFinite || !lng.isFinite || !depth.isFinite || depth < 0) {
    return null;
  }
  final values = <double>[];
  final ids = <String>[];
  for (final sample in samples) {
    if (!sample.pga.isFinite || sample.pga <= 0) continue;
    final surface = CwaIntensityPrediction.surfaceDistanceKm(
      lat,
      lng,
      sample.lat,
      sample.lng,
    );
    final distance = math.sqrt(surface * surface + depth * depth);
    if (!distance.isFinite || distance <= 0) continue;
    final m =
        (math.log(sample.pga / 1.657) + 1.607 * math.log(distance)) / 1.533;
    if (!m.isFinite) continue;
    values.add(m);
    ids.add(sample.id);
  }
  if (values.length < 5) return null;
  values.sort();
  final n = values.length;
  final m = n.isOdd
      ? values[n ~/ 2]
      : (values[n ~/ 2 - 1] + values[n ~/ 2]) / 2;
  if (m < 0) return null;
  return (
    magnitude: m,
    diagnostics: {
      'palert_magnitude_model': 'taiwan_pga_attenuation_inverse_median_v1',
      'palert_magnitude_preliminary': true,
      'palert_magnitude_station_codes': ids,
      'palert_magnitude_station_count': n,
      'palert_magnitude_site_corrections': 'unavailable_unit_factor',
    },
  );
}
