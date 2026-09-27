import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/jma_ashfall_forecast_service.dart';
import 'package:flutterrhythmquake/widgets/map/volcano_ashfall_layer.dart';

void main() {
  test('renders every severity polygon in a JMA VFVO55 window', () {
    // Original JMA bulletin: https://www.data.jma.go.jp/developer/xml/data/20260923145625_0_VFVO55_010000.xml
    final xml = File(
      'test/fixtures/jma_ashfall/20260923145625_0_VFVO55_010000.xml',
    ).readAsStringSync();
    final windows = JmaAshfallForecastService().parseDetailForTesting(xml);

    expect(windows, hasLength(6));
    expect(windows.first.items.map((item) => item.phenomenonCode), [
      '72',
      '71',
    ]);

    final polygons = VolcanoAshfallLayer.polygonsForWindow(windows.first);
    expect(polygons, hasLength(2));
    expect(
      polygons.first.color,
      const Color(0xFFB8C4D0).withValues(alpha: 0.2),
    );
    expect(polygons.last.color, const Color(0xFFFFD34A).withValues(alpha: 0.3));

    final splitWindowPolygons = VolcanoAshfallLayer.polygonsForWindow(
      windows[2],
    );
    expect(splitWindowPolygons, hasLength(3));
  });
}
