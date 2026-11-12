import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/replay/knet_duration_proxy.dart';

void main() {
  test('native K-NET duration proxy matches sorted Dart reference', () {
    if (!Platform.isWindows ||
        !Platform.environment.containsKey('RQ_STATION_CORE_LIBRARY')) {
      return;
    }
    for (final n in [1, 4, 10, 100, 1000]) {
      final values = List<double>.generate(
        n,
        (i) => 0.1 + (i * 37 % (n + 7)) / 13,
      );
      for (final duration in [0.1, 0.3, 1.0, 10.0]) {
        final native = nativeKnetDurationProxy(values, 100, duration);
        expect(native, isNotNull);
        final sorted = [...values]..sort((a, b) => b.compareTo(a));
        final rank = math.min(n - 1, math.max(1, (duration * 100).ceil()) - 1);
        final expected = 2 * math.log(sorted[rank]) / math.ln10 + 0.94;
        expect(native!, closeTo(expected, 1e-12));
      }
    }
    expect(nativeKnetDurationProxy([0, 0], 2, 0.5)!.isNaN, isTrue);
  });
}
