import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_intensity_prediction.dart';
import 'package:flutterrhythmquake/core/intensity_calculator.dart';
import 'package:flutterrhythmquake/core/utils/jma_seis_int_loc.dart';

void main() {
  test('exact bounded LRU, all four parameters invalidate, unknown cached', () {
    var calls = 0;
    final cache = SourceIntensityPrediction(
      capacity: 2,
      calculate: (m, d, lat, lng) {
        calls++;
        return m == 0 ? -3 : 2.5;
      },
    );
    int? get(double m, double d, double lat, double lng) =>
        cache.index(magnitude: m, depthKm: d, latitude: lat, longitude: lng);
    expect(get(1, 10, 35, 140), 3);
    expect(get(1, 10, 35, 140), 3);
    expect(calls, 1);
    get(2, 10, 35, 140);
    get(1, 10, 35, 140); // refresh LRU
    get(1, 11, 35, 140);
    get(2, 10, 35, 140); // evicted
    get(2, 10, 35.00000001, 140);
    get(2, 10, 35.00000001, 140.00000001);
    expect(calls, 6);
    expect(get(0, 10, 35, 140), isNull);
    expect(get(0, 10, 35, 140), isNull);
    expect(calls, 7);
    expect(get(1, 151, 35, 140), isNull);
    expect(get(1, 10, double.nan, 140), isNull);
    expect(calls, 7);
  });

  test(
    'original full APP estimate inputs retain uncached prediction results',
    () {
      final input = File(
        'D:/flutterApp/flutter-source-estimation-audit/20261014-162309/original-estimate-inputs.json',
      );
      if (!input.existsSync()) {
        markTestSkipped('Local original audit inputs required');
        return;
      }
      final rows = jsonDecode(input.readAsStringSync()) as List;
      final locations = [
        for (final s in JmaSeisIntLoc.getStations())
          <String, dynamic>{'lat': s.lat, 'lng': s.lng, 'arv': s.arv},
      ];
      var calls = 0;
      final cache = SourceIntensityPrediction(
        calculate: (m, d, lat, lng) {
          calls++;
          return IntensityCalculator.calcMaxJmaShindo(
            m,
            d,
            lat,
            lng,
            locations,
          );
        },
      );
      for (final row in rows) {
        final r = (row as List).map((v) => (v as num).toDouble()).toList();
        final value = IntensityCalculator.calcMaxJmaShindo(
          r[3],
          r[2],
          r[0],
          r[1],
          locations,
        );
        expect(
          cache.index(
            magnitude: r[3],
            depthKm: r[2],
            latitude: r[0],
            longitude: r[1],
          ),
          SourceIntensityPrediction.labels.indexOf(
            IntensityCalculator.getJmaShindoLevel(value),
          ),
        );
      }
      expect(
        calls,
        rows
            .map(
              (r) => (
                (r[3] as num).toDouble(),
                (r[2] as num).toDouble(),
                (r[0] as num).toDouble(),
                (r[1] as num).toDouble(),
              ),
            )
            .toSet()
            .length,
      );
    },
  );
}
