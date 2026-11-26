import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/precipitation_stations_decoder.dart';
import 'package:flutterrhythmquake/services/sources/precipitation_stations_decoder_portable.dart'
    as portable;
import 'package:flutterrhythmquake/services/sources/precipitation_stations_service.dart';
import 'package:flutterrhythmquake/widgets/map/weather_station_map_layer.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

void main() {
  final noon = DateTime.utc(2026, 11, 25, 4);
  final afternoon = DateTime.utc(2026, 11, 25, 5);
  final original = {
    for (final hour in [12, 13])
      hour: File(
        'test/fixtures/weather_precipitation_20261125/$hour.jsonp',
      ).readAsBytesSync(),
  };

  test(
    'station series matches the entire Beijing-time observation hour',
    () async {
      final service = PrecipitationStationsService(
        client: MockClient((request) async {
          final hour = int.parse(request.url.pathSegments[2]);
          expect(request.url.host, 'img.weather.com.cn');
          expect(request.url.queryParameters['callback'], 'webgisDot');
          return http.Response.bytes(original[hour]!, 200);
        }),
      );
      addTearDown(service.close);
      final rows = (await service.fetch(noon, Completer<void>()))!;
      expect(rows.length ~/ 3, 111);
      expect(rows[2], 0.3);
      expect(rows[0], closeTo(23.9, 0.02));
      expect(rows[1], closeTo(106.6, 0.02));
      expect(
        await service.fetch(
          noon.subtract(const Duration(days: 1)),
          Completer<void>(),
        ),
        isNull,
      );
      final later = (await service.fetch(afternoon, Completer<void>()))!;
      expect(later.length ~/ 3, 109);
      expect(later[2], 0.1);
      final crossPlatform = portable.decodePrecipitationStations(
        original[12]!,
        2026112512,
      )!;
      for (var i = 0; i < rows.length; i++) {
        expect(rows[i], closeTo(crossPlatform[i], 1e-9));
      }
      expect(decodePrecipitationStations(original[12]!, 2026112513), isNull);
    },
  );

  testWidgets('pending hour never paints over the currently selected frame', (
    tester,
  ) async {
    final oldResponse = Completer<http.Response>();
    final currentResponse = Completer<http.Response>();
    final requests = <int>[];
    final service = PrecipitationStationsService(
      client: MockClient((request) {
        final hour = int.parse(request.url.pathSegments[2]);
        requests.add(hour);
        return (hour == 12 ? oldResponse : currentResponse).future;
      }),
    );
    Widget map(DateTime? time) => MaterialApp(
      home: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(24, 107),
          initialZoom: 9,
        ),
        children: [
          if (time != null)
            PrecipitationStationsLayer(time: time, service: service),
        ],
      ),
    );
    final points = find.byKey(const ValueKey('precipitation-station-points'));
    await tester.pumpWidget(map(noon));
    await tester.pump(const Duration(milliseconds: 150));
    expect(requests, [12]);
    await tester.pumpWidget(map(afternoon));
    await tester.pump(const Duration(milliseconds: 150));
    expect(requests, [12, 13]);
    oldResponse.complete(http.Response.bytes(original[12]!, 200));
    await tester.pump();
    expect(points, findsNothing);
    currentResponse.complete(http.Response.bytes(original[13]!, 200));
    await tester.pumpAndSettle();
    expect(points, findsOneWidget);
    await tester.pumpWidget(map(null));
    expect(points, findsNothing);
  });
}
