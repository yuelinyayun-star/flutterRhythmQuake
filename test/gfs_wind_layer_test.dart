import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutterrhythmquake/services/sources/gfs_wind_service.dart';
import 'package:flutterrhythmquake/widgets/map/gfs_wind_layer.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

void main() {
  testWidgets('GFS overlay attaches its painter after loading wind data', (
    tester,
  ) async {
    final service = GfsWindService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(
            List.generate(
              63,
              (_) => {
                'current': {
                  'time': '2026-09-23T07:00',
                  'wind_speed_10m': 15,
                  'wind_direction_10m': 270,
                },
              },
            ),
          ),
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 600,
          height: 420,
          child: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(35, 139),
              initialZoom: 5,
            ),
            children: [GfsWindLayer(service: service)],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final paints = find.descendant(
      of: find.byType(GfsWindLayer),
      matching: find.byType(CustomPaint),
    );
    expect(paints, findsOneWidget);
    expect(tester.widget<CustomPaint>(paints).painter, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    service.close();
  });
}
