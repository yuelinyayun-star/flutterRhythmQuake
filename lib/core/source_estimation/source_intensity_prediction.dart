import '../intensity_calculator.dart';
import '../utils/jma_seis_int_loc.dart';

/// Exact source parameters, fixed JMA network/model. No coordinate quantization.
class SourceIntensityPrediction {
  SourceIntensityPrediction({
    this.capacity = 32,
    double Function(double, double, double, double)? calculate,
  }) : _calculate = calculate ?? _predict;

  final int capacity;
  final double Function(double, double, double, double) _calculate;
  final _cache = <(double, double, double, double), int?>{};
  static const labels = ['0', '1', '2', '3', '4', '5-', '5+', '6-', '6+', '7'];
  static final _locations = [
    for (final station in JmaSeisIntLoc.getStations())
      <String, dynamic>{
        'lat': station.lat,
        'lng': station.lng,
        'arv': station.arv,
      },
  ];
  static double _predict(double m, double d, double lat, double lng) =>
      IntensityCalculator.calcMaxJmaShindo(m, d, lat, lng, _locations);

  int? index({
    required double? magnitude,
    required double? depthKm,
    required double latitude,
    required double longitude,
  }) {
    final m = magnitude;
    final d = depthKm;
    if (m == null ||
        !m.isFinite ||
        m < 0 ||
        d == null ||
        !d.isFinite ||
        d < 0 ||
        d > 150 ||
        !latitude.isFinite ||
        !longitude.isFinite) {
      return null;
    }
    final key = (m, d, latitude, longitude);
    if (_cache.containsKey(key)) {
      final result = _cache.remove(key);
      _cache[key] = result;
      return result;
    }
    final value = _calculate(m, d, latitude, longitude);
    final index = value.isFinite && value > -3
        ? labels.indexOf(IntensityCalculator.getJmaShindoLevel(value))
        : -1;
    final result = index < 0 ? null : index;
    if (capacity > 0) {
      _cache[key] = result;
      if (_cache.length > capacity) _cache.remove(_cache.keys.first);
    }
    return result;
  }
}
