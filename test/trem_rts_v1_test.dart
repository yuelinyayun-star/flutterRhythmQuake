import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/sources/cwa_station_service.dart';
import 'package:flutterrhythmquake/services/sources/trem_protocol.dart';
import 'package:flutterrhythmquake/services/sources/native_station_runtime.dart';
import 'package:flutterrhythmquake/widgets/map/cwa_station_layer.dart';
import 'package:flutterrhythmquake/widgets/map/station_dot_painter_layer.dart';
import 'package:flutterrhythmquake/widgets/map/ka_shindo_marker_style.dart';

const fixture = 'test/fixtures/trem_rts_v1_20261024';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final csv = File('$fixture/station.original.csv').readAsStringSync();
  final wire = File('$fixture/rts.original.sse').readAsBytesSync();

  testWidgets(
    'original quiet RTS stations keep pre-change KA colours and opacity without zero markers',
    (tester) async {
      final raw = (await TremProtocol.decode(
        Stream.value(wire),
      ).toList()).single;
      final original = jsonEncode(raw);
      final service = CwaStationService.detached();
      addTearDown(service.stop);
      service.handleOriginalForTesting(csv, metadata: true);
      service.handleOriginalForTesting(original);
      expect(service.stations, hasLength(121));
      expect(service.stations.every((s) => !s.hasAlert), isTrue);
      expect(service.stations.where((s) => s.intensity >= 0).length, 110);
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(23.7, 121),
              initialZoom: 7,
            ),
            children: [
              CwaStationLayer(
                stations: service.stations,
                displayShindo0: true,
                preparedGrids: const [],
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MarkerLayer), findsNothing);
      final dots = tester
          .widget<StationDotPainterLayer>(find.byType(StationDotPainterLayer))
          .dots;
      expect(dots, hasLength(121));
      for (var n = 0; n < dots.length; n++) {
        final s = service.stations[n];
        expect(dots[n].coordinate, s.coordinate);
        expect(
          dots[n].color,
          KaShindoMarkerStyle.colorForLevel(
            CwaStationService.gridLevelFromInstShindo(s.currentIntensity),
          ),
        );
        expect(dots[n].color, const Color(0xff9f9f9f));
        expect(dots[n].fillOpacity, lessThan(1));
        expect(dots[n].borderOpacity, greaterThan(0));
      }
      expect(jsonEncode(raw), original);
      expect(service.stations.where((s) => s.intensity >= 0).length, 110);
    },
  );

  test(
    'original v1 SSE and CSV match by hex ID without altering observations',
    () async {
      final frames = await TremProtocol.decode(
        Stream.fromIterable(wire.map((b) => [b])),
      ).toList();
      expect(frames, hasLength(1));
      final original = frames.single;
      expect((original['stations'] as Map).length, 121);
      expect(original['ts'], 1792839551662);
      final catalogue = {for (final s in TremProtocol.catalogue(csv)) s.id: s};
      final service = CwaStationService.detached();
      addTearDown(service.stop);
      service.handleOriginalForTesting(csv, metadata: true);
      expect(service.handleOriginalForTesting(jsonEncode(original)), isTrue);
      expect(service.stations, hasLength(121));
      for (final s in service.stations) {
        final raw = (original['stations'] as Map)[s.id] as Map;
        final meta = catalogue[s.id]!;
        expect(s.intensity, raw['i']);
        expect(s.alertIntensity, raw['i']);
        expect(s.pga, raw['pga']);
        expect(s.coordinate.latitude, meta.lat);
        expect(s.coordinate.longitude, meta.lon);
        expect(s.net, meta.net);
        expect(s.code, meta.code);
        expect(s.work, isTrue);
      }
      expect(service.handleOriginalForTesting(jsonEncode(original)), isFalse);
      // A failed catalogue refresh keeps the valid IDs and their coordinates.
      service.handleOriginalForTesting('<html>404</html>', metadata: true);
      expect(service.stations, hasLength(121));
      expect(TremProtocol.payload('invalid gzip'), isNull);
      expect(
        await TremProtocol.decode(
          Stream.value(utf8.encode(': ping 123\n\nevent: info\ndata: {}\n\n')),
        ).toList(),
        isEmpty,
      );
    },
  );

  test(
    'Rust v1 owner preserves raw catalogue and packet, archive and station values',
    () async {
      final frames = await TremProtocol.decode(Stream.value(wire)).toList();
      final raw = frames.single;
      final runtime = NativeStationRuntime();
      addTearDown(runtime.stop);
      final ready = Completer<Map<String, dynamic>>();
      runtime.onFrame = (frame) {
        if (frame['frames'] == 1 && !ready.isCompleted) ready.complete(frame);
      };
      runtime.start({'kind': 'cwa', 'testing': true});
      final clock = DateTime.fromMillisecondsSinceEpoch(raw['ts'] as int);
      runtime.injectOriginal(utf8.encode(jsonEncode(csv)), clock);
      runtime.injectOriginal(utf8.encode(jsonEncode(raw)), clock);
      final result = await ready.future.timeout(const Duration(seconds: 10));
      expect(result['status'], 'connected');
      expect(DateTime.parse(result['dataTime']), clock.toUtc());
      expect(result['stations'], hasLength(121));
      for (final s in result['stations']) {
        final observed = raw['stations'][s['id']];
        expect(s['intensity'], observed['i']);
        expect(s['alertIntensity'], observed['i']);
        expect(s['pga'], observed['pga']);
        expect(
          s['hasAlert'],
          observed['alert'] == true ||
              observed['alert'] == 1 ||
              observed['alert'] == '1',
        );
      }
      expect(runtime.original!['metadata'], csv);
      expect(runtime.original!['data'], raw);
      expect(runtime.archive!['stations'], hasLength(121));
    },
    skip: !NativeStationRuntime.supported,
  );

  test(
    'production Rust TREM actor receives continuous live v1 frames',
    () async {
      final runtime = NativeStationRuntime();
      addTearDown(runtime.stop);
      final ready = Completer<Map<String, dynamic>>();
      final times = <String>{};
      runtime.onFrame = (frame) {
        if (frame['status'] == 'connected' &&
            (frame['stations'] as List).isNotEmpty) {
          times.add(frame['dataTime'] as String);
          if (times.length >= 10 && !ready.isCompleted) ready.complete(frame);
        }
      };
      runtime.start({'kind': 'cwa'});
      final result = await ready.future.timeout(const Duration(seconds: 45));
      final raw = runtime.original!;
      expect(raw['metadata'], isA<String>());
      expect(raw['data']['stations'], isA<Map>());
      expect(result['status'], 'connected');
      expect((result['stations'] as List).length, greaterThan(100));
      expect(
        DateTime.now()
            .toUtc()
            .difference(DateTime.parse(result['dataTime']))
            .abs(),
        lessThan(const Duration(seconds: 15)),
      );
      final report = {
        'frames': result['frames'],
        'distinctDataTimes': times.length,
        'dataTime': result['dataTime'],
        'stations': (result['stations'] as List).length,
        'status': result['status'],
        'source': raw['data']['source'],
      };
      File(
        'tmp/trem_connection_20261024/native-live.json',
      ).writeAsStringSync(jsonEncode(report));
      // ignore: avoid_print
      print('TREM LIVE: ${jsonEncode(report)}');
    },
    skip:
        !(NativeStationRuntime.supported &&
            Platform.environment['RQ_TREM_LIVE'] == '1'),
  );
}
