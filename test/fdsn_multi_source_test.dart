import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_channel_catalog.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_motion_service_io.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_source_catalog.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_station_service.dart';

import 'fdsn_connection_test.dart' show infoPackets, stationXml;

// Isolated allocation/transport fixtures; never injected into live sources.
FdsnSeedLinkStream stream(
  String source,
  String station, {
  String network = 'XX',
}) {
  final config = FdsnSourceCatalog.find(source)!;
  return FdsnSeedLinkStream(
    source: source,
    host: config.host,
    port: config.port,
    secure: config.secure,
    network: network,
    station: station,
    selector: 'BH?.D',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'EarthScope only owns stations absent from other enabled catalogues',
    () {
      final service = FdsnMotionService.forTesting(streams: []);
      addTearDown(service.dispose);
      final earth = [
        stream('EarthScope', 'ONLY'),
        stream('EarthScope', 'SHARED'),
      ];
      final regional = [stream('GeoNet', 'SHARED'), stream('RESIF', 'FR')];
      for (final lists in [
        [earth, regional],
        [regional, earth],
      ]) {
        final chosen = service.selectStreamsForTesting(lists, 5000);
        expect(
          chosen.where((s) => s.source == 'EarthScope').single.station,
          'ONLY',
        );
        expect(
          chosen.where((s) => s.station == 'SHARED').single.source,
          'GeoNet',
        );
        expect(chosen.length, 3);
      }
    },
  );

  test('same station code on different networks is not deduplicated', () {
    final service = FdsnMotionService.forTesting(streams: []);
    addTearDown(service.dispose);
    final chosen = service.selectStreamsForTesting([
      [stream('EarthScope', 'AAA', network: 'II')],
      [stream('GeoNet', 'AAA', network: 'NZ')],
    ], 100);
    expect(chosen.length, 2);
  });

  test('seven providers never subscribe the same station twice', () {
    final service = FdsnMotionService.forTesting(streams: []);
    addTearDown(service.dispose);
    final selected = service.selectStreamsForTesting([
      for (final source in FdsnSourceCatalog.names)
        [stream(source, 'SHARED'), stream(source, source)],
    ], 100);
    expect(selected.where((s) => s.station == 'SHARED').length, 1);
    expect(selected.where((s) => s.station == 'SHARED').single.source, 'IPGP');
    expect(selected.map((s) => '${s.network}.${s.station}').toSet().length, 8);
  });

  test('no EarthScope source cap; only the existing total limit applies', () {
    final service = FdsnMotionService.forTesting(streams: []);
    addTearDown(service.dispose);
    final earth = [for (var i = 0; i < 1500; i++) stream('EarthScope', '$i')];
    expect(service.selectStreamsForTesting([earth], 2000).length, 1500);
    expect(service.selectStreamsForTesting([earth], 1000).length, 1000);
  });

  test('regional overlap is deduplicated before applying global budget', () {
    final service = FdsnMotionService.forTesting(streams: []);
    addTearDown(service.dispose);
    final chosen = service.selectStreamsForTesting([
      [stream('EarthScope', 'SHARED'), stream('EarthScope', 'ONLY')],
      [stream('GEOFON', 'SHARED')],
      [stream('RESIF', 'SHARED'), stream('RESIF', 'OTHER')],
    ], 2);
    expect(chosen.length, 2);
    expect(chosen.map((s) => '${s.network}.${s.station}').toSet().length, 2);
    expect(chosen.where((s) => s.station == 'SHARED').single.source, 'RESIF');
  });

  test('disabling a regional provider returns its station to EarthScope', () {
    final service = FdsnMotionService.forTesting(streams: []);
    addTearDown(service.dispose);
    final earth = [stream('EarthScope', 'SHARED')];
    expect(
      service
          .selectStreamsForTesting([
            earth,
            [stream('GeoNet', 'SHARED')],
          ], 100)
          .single
          .source,
      'GeoNet',
    );
    expect(
      service.selectStreamsForTesting([earth], 100).single.source,
      'EarthScope',
    );
  });

  test(
    'new source preferences migrate once and preserve explicit off',
    () async {
      final prefs = <String, bool>{
        'map_overlay_fdsnEarthScope': true,
        'map_overlay_fdsnResif': false,
      };
      Future<bool> write(String key, bool value) async {
        prefs[key] = value;
        return true;
      }

      await FdsnSourceCatalog.initializePreferences((key) => prefs[key], write);
      expect(prefs['map_overlay_fdsnGeoNet'], isTrue);
      expect(prefs['map_overlay_fdsnResif'], isFalse);
      expect(prefs['map_overlay_fdsnIpgp'], isTrue);
      expect(prefs['map_overlay_fdsnOrfeus'], isFalse);
      expect(prefs['map_overlay_fdsnBgr'], isTrue);
      prefs['map_overlay_fdsnEarthScope'] = false;
      await FdsnSourceCatalog.initializePreferences((key) => prefs[key], write);
      expect(
        FdsnSourceCatalog.find('GeoNet')!.readEnabled((key) => prefs[key]),
        isTrue,
      );
      expect(
        FdsnSourceCatalog.find('RESIF')!.readEnabled((key) => prefs[key]),
        isFalse,
      );
      expect(
        FdsnSourceCatalog.find('GeoNet')!.readEnabled((_) => null),
        isFalse,
      );
    },
  );

  for (final source in ['GeoNet', 'RESIF', 'IPGP', 'ORFEUS', 'BGR']) {
    test('$source uses its own instrument metadata endpoint', () async {
      final config = FdsnSourceCatalog.find(source)!;
      final catalog = FdsnChannelCatalog(
        MockClient((request) async {
          if (request.url.path.contains('/routing/')) {
            return http.Response('', 204);
          }
          expect(request.url.host, Uri.parse(config.stationUrl).host);
          return http.Response(
            'XX|AAA||BHZ|30|105|2|0|0|-90|test|1000|1|M/S|20|2020-01-01T00:00:00||',
            200,
          );
        }),
      );
      addTearDown(catalog.dispose);
      catalog.selectStations([(source, 'XX', 'AAA')]);
      final response = await catalog.find(
        source: source,
        network: 'XX',
        station: 'AAA',
        location: '',
        channel: 'BHZ',
        time: DateTime.utc(2026),
      );
      expect(response?.sensitivity, 1000);
      expect((await catalog.load(source, 'XX')).keys, ['XX.AAA..BHZ']);
      catalog.selectStations([(source, 'XX', 'BBB')]);
      expect(await catalog.load(source, 'XX'), isEmpty);
      catalog.selectStations([(source, 'XX', 'AAA')]);
      expect((await catalog.load(source, 'XX')).keys, ['XX.AAA..BHZ']);
      expect(
        FdsnStationService.forSource(source)!.endpoint.stationUrl,
        config.stationUrl,
      );
    });
  }

  test('unknown metadata source never falls back to EarthScope', () async {
    var called = false;
    final catalog = FdsnChannelCatalog(
      MockClient((_) async {
        called = true;
        return http.Response('', 204);
      }),
    );
    addTearDown(catalog.dispose);
    expect(await catalog.load('unknown', 'XX'), isEmpty);
    expect(called, isFalse);
    expect(FdsnStationService.forSource('unknown'), isNull);
  });

  test(
    'map handover draws one station and Android bridge preserves provenance',
    () {
      final time = DateTime.now().toUtc();
      FdsnStation station(String source, DateTime timestamp) => FdsnStation(
        network: 'XX',
        station: 'AAA',
        location: '',
        source: source,
        coordinate: const LatLng(30, 105),
        lastMotionUpdate: timestamp,
      );
      final earth = station('EarthScope', time);
      final regional = station('GeoNet', time);
      final selected = deduplicateFdsnStations([earth, regional]);
      expect(selected.single, same(regional));
      final payload = ForegroundStationPayload.fdsnStations('GeoNet', selected);
      expect(payload['source'], 'GeoNet');
      final decoded = ForegroundStationPayload.decodeFdsnStations(
        payload['stations'],
      );
      expect(decoded.single.source, 'GeoNet');
      expect(decoded.single.lastMotionUpdate, time);
      expect(
        deduplicateFdsnStations([
          earth,
          station('GeoNet', time.subtract(const Duration(minutes: 4))),
        ]).single,
        same(earth),
      );
    },
  );

  test(
    'all-overlap removes old socket even when providers share a host',
    () async {
      final first = await ServerSocket.bind('127.0.0.1', 0);
      final second = await ServerSocket.bind('127.0.0.1', 0);
      final sockets = <Socket>[];
      final ready = Completer<void>();
      void serve(ServerSocket server, List<String> names) {
        server.listen((socket) {
          sockets.add(socket);
          unawaited(socket.done.catchError((Object _) {}));
          socket
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((line) {
                if (line == 'INFO STREAMS') {
                  socket.add(
                    infoPackets(
                      '<seedlink>${names.map((s) => stationXml(s, DateTime.now().toUtc())).join()}</seedlink>',
                    ),
                  );
                } else if (line == 'END') {
                  if (server == second && !ready.isCompleted) ready.complete();
                } else {
                  socket.add(ascii.encode('OK\r\n'));
                }
              }, onError: (_) {});
        });
      }

      serve(first, ['AAA']);
      serve(second, ['AAA', 'BBB']);
      final service = FdsnMotionService.forTesting(
        streams: [
          FdsnSeedLinkStream(
            source: 'EarthScope',
            host: '127.0.0.1',
            port: first.port,
            network: 'XX',
            station: 'AAA',
            selector: 'BH?.D',
          ),
          FdsnSeedLinkStream(
            source: 'GeoNet',
            host: '127.0.0.1',
            port: second.port,
            network: 'XX',
            station: 'BBB',
            selector: 'BH?.D',
          ),
        ],
        responseClientFactory: () =>
            MockClient((_) async => http.Response('', 204)),
      );
      try {
        service.connect(
          stationLimit: 100,
          enabledSources: {'EarthScope', 'GeoNet'},
        );
        await ready.future.timeout(const Duration(seconds: 3));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(service.connectionDiagnostics.length, 1);
        expect(service.connectionDiagnostics.single['source'], 'GeoNet');
        expect(service.connectionDiagnostics.single['selected'], 2);
      } finally {
        service.dispose();
        for (final socket in sockets) {
          socket.destroy();
        }
        await first.close();
        await second.close();
      }
    },
  );
}
