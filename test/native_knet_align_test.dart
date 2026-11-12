import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/replay/knet_align.dart';

void main() {
  test('native alignment preserves exact offsets, order and source', () {
    if (!Platform.isWindows ||
        !Platform.environment.containsKey('RQ_STATION_CORE_LIBRARY')) {
      return;
    }
    final source = [100.0, -2.0, 0.0, 7.5, 10.0];
    final before = [...source];
    expect(nativeAlignKnetChannel(source, 1, 3, 0.5), [-2.5, -0.5, 7.0]);
    expect(source, before);
    expect(nativeAlignKnetChannel(source, 4, 2, 0), isNull);
  });
}
