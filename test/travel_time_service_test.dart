import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/travel_time_service.dart';

// Independent original full-row interpolation, read from the unchanged asset.
List<double> _row(Map<String, dynamic> table, bool p, double depth) {
  if (depth < 0) depth = 0;
  final depths = table['depths'] as List;
  final data = table[p ? 'p_times' : 's_times'] as List;
  var i = 1;
  while (i < depths.length - 1 && (depths[i] as num) < depth) {
    i++;
  }
  final k1 = (depths[i] as num).toDouble() - depth;
  final k2 = depth - (depths[i - 1] as num).toDouble();
  return List.generate(
    (data[0] as List).length,
    (j) =>
        (k1 * (data[i - 1][j] as num).toDouble() +
            k2 * (data[i][j] as num).toDouble()) /
        (k1 + k2),
  );
}

double _reach(Map<String, dynamic> table, List<double> times, double distance) {
  if (distance < 0) distance = 0;
  final distances = (table['distances'] as List).cast<num>();
  var j = 1;
  while (j < distances.length - 1 && distances[j] < distance) {
    j++;
  }
  final k =
      (times[j] - times[j - 1]) /
      (distances[j].toDouble() - distances[j - 1].toDouble());
  final b = times[j] - k * distances[j].toDouble();
  return k * distance + b;
}

(double, double) _wave(
  Map<String, dynamic> table,
  List<double> times,
  double time,
) {
  if (time < 0) time = 0;
  if (time <= times[0]) return (times[0] > 0 ? time / times[0] : 0, 0);
  final distances = (table['distances'] as List).cast<num>();
  var j = 1;
  while (j < times.length - 1 && times[j] < time) {
    j++;
  }
  final k =
      (distances[j].toDouble() - distances[j - 1].toDouble()) /
      (times[j] - times[j - 1]);
  final b = distances[j].toDouble() - k * times[j];
  return (1, k * time + b);
}

void _sameDouble(double actual, double expected) {
  if (expected.isNaN) {
    expect(actual.isNaN, isTrue);
    return;
  }
  final a = ByteData(8)..setFloat64(0, actual);
  final b = ByteData(8)..setFloat64(0, expected);
  expect(a.getInt64(0), b.getInt64(0));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> tables;
  setUpAll(() async {
    tables =
        jsonDecode(
              await rootBundle.loadString(
                'assets/travel_times.json',
                cache: false,
              ),
            )
            as Map<String, dynamic>;
    await TravelTimeService().ensureLoaded();
  });
  for (final name in ['jma2001', 'jb']) {
    test(
      '$name P/S results match original interpolation at every asset node',
      () {
        final table = tables[name] as Map<String, dynamic>;
        for (final p in [true, false]) {
          final depths = table['depths'] as List;
          final distances = table['distances'] as List;
          final data = table[p ? 'p_times' : 's_times'] as List;
          for (var i = 0; i < depths.length; i++) {
            final depth = (depths[i] as num).toDouble();
            final times = _row(table, p, depth);
            for (var j = 0; j < distances.length; j++) {
              final distance = (distances[j] as num).toDouble();
              final time = (data[i][j] as num).toDouble();
              _sameDouble(
                TravelTimeService().calcReachTime(name, p, depth, distance),
                _reach(table, times, distance),
              );
              final wave = TravelTimeService().calcWaveDistance(
                name,
                p,
                depth,
                time,
              );
              final expected = _wave(table, times, time);
              _sameDouble(wave.reach, expected.$1);
              _sameDouble(wave.radius, expected.$2);
            }
          }
        }
      },
    );
    test('$name preserves intermediate interpolation and extrapolation', () {
      final table = tables[name] as Map<String, dynamic>;
      final depths = (table['depths'] as List).cast<num>();
      final distances = (table['distances'] as List).cast<num>();
      final queryDepths = [
        -1.0,
        -0.0,
        depths.last.toDouble() + 10,
        double.nan,
        double.infinity,
        for (var i = 1; i < depths.length; i++)
          (depths[i - 1].toDouble() + depths[i].toDouble()) / 2,
      ];
      final queryDistances = [
        -1.0,
        -0.0,
        distances.last.toDouble() + 10,
        double.nan,
        double.infinity,
        for (var j = 1; j < distances.length; j += 7)
          (distances[j - 1].toDouble() + distances[j].toDouble()) / 2,
      ];
      for (final p in [true, false]) {
        for (final depth in queryDepths) {
          final times = _row(table, p, depth);
          for (final distance in queryDistances) {
            final reach = _reach(table, times, distance);
            _sameDouble(
              TravelTimeService().calcReachTime(name, p, depth, distance),
              reach,
            );
            final wave = TravelTimeService().calcWaveDistance(
              name,
              p,
              depth,
              reach,
            );
            final expected = _wave(table, times, reach);
            _sameDouble(wave.reach, expected.$1);
            _sameDouble(wave.radius, expected.$2);
          }
        }
      }
    });
  }
}
