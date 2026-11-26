import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/background_station_connection.dart';
import 'package:flutterrhythmquake/providers/background_settings_provider.dart';
import 'package:flutterrhythmquake/services/sources/fssn_station_map_service.dart';
import 'package:flutterrhythmquake/services/sources/native_fssn_stations_io.dart';
import 'package:flutterrhythmquake/widgets/map/fssn_station_layer.dart';
import 'package:flutterrhythmquake/widgets/map/station_dot_painter_layer.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';

Uint8List original(String name) =>
    File('test/fixtures/fssn_stations/$name').readAsBytesSync();

Future<void> until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('FSSN map');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _DisplayService extends FssnStationMapService {
  bool connected = false;

  @override
  void start() => connected = true;

  @override
  void stop() {
    connected = false;
    super.stop();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final native = Platform.environment.containsKey('RQ_STATION_CORE_LIBRARY');

  test(
    'original layout and binary frame cross FFI with explicit ownership',
    () {
      final layout = original('stations.original.json');
      final bytes = original('overlay.original.bin');
      final data = ByteData.sublistView(bytes);
      final before = NativeFssnStations.sessions;
      for (var repeat = 0; repeat < 20; repeat++) {
        final decoder = NativeFssnStations(layout);
        expect(NativeFssnStations.sessions, before + 1);
        final frame = decoder.process(bytes);
        expect(frame.unixSeconds, data.getUint32(1, Endian.little));
        expect(frame.stations, hasLength(15));
        expect(frame.stations.first.latitude, closeTo(30.64907, 1e-10));
        expect(frame.stations.first.longitude, closeTo(104.00932, 1e-10));
        for (var i = 0; i < 15; i++) {
          final raw = data.getUint16(10 + i * 2, Endian.little);
          expect(frame.stations[i].pga, raw == 65535 ? null : raw / 10);
          expect(
            frame.stations[i].status,
            (bytes[6 + i * 2 ~/ 8] >> (i * 2 % 8)) & 3,
          );
          expect(
            frame.stations[i].argb,
            raw == 65535 ? 0xffc0c0c0 : 0xff0008d2,
          );
        }
        expect(
          () => decoder.process(Uint8List.fromList('<html>'.codeUnits)),
          throwsFormatException,
        );
        expect(decoder.process(bytes).stations.length, 15);
        decoder.dispose();
        decoder.dispose();
        expect(frame.stations.first.latitude, closeTo(30.64907, 1e-10));
        expect(NativeFssnStations.sessions, before);
        expect(() => decoder.process(bytes), throwsStateError);
      }
      expect(
        () => NativeFssnStations(Uint8List.fromList('<html>'.codeUnits)),
        throwsFormatException,
      );
      expect(NativeFssnStations.sessions, before);
    },
    skip: !native,
  );

  test(
    'original binary socket reconnects, rejects HTML and releases on stop',
    () async {
      HttpOverrides.global = null;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <WebSocket>[];
      final requests = <Uri>[];
      var closedClients = 0;
      final subscription = server.listen((request) async {
        final peer = await WebSocketTransformer.upgrade(request);
        peers.add(peer);
        peer.listen((_) {});
        peer.add(original('overlay.original.bin'));
      });
      final before = NativeFssnStations.sessions;
      final service = FssnStationMapService(
        createClient: () => MockClient((request) async {
          requests.add(request.url);
          return http.Response.bytes(original('stations.original.json'), 200);
        }),
        connect: (uri) {
          expect(uri.toString(), 'wss://seisdata.fanstudio.tech/ws/overlay');
          return IOWebSocketChannel.connect(
            'ws://127.0.0.1:${server.port}/overlay',
          );
        },
        retryDelay: const Duration(milliseconds: 20),
      );
      service.addListener(() {
        if (service.value == null) closedClients++;
      });
      addTearDown(() async {
        service.dispose();
        for (final peer in peers) {
          await peer.close();
        }
        await subscription.cancel();
        await server.close(force: true);
      });
      service.start();
      service.start();
      await until(() => service.value != null);
      expect(service.value!.stations, hasLength(15));
      expect(peers, hasLength(1));
      expect(
        requests.single.toString(),
        'https://seisdata.fanstudio.tech/api/stations',
      );
      peers.last.add('<html>upstream failure</html>');
      await until(() => peers.length == 2 && service.value != null);
      expect(closedClients, 1);
      expect(NativeFssnStations.sessions, before + 1);
      await peers.last.close();
      await until(() => peers.length == 3 && service.value != null);
      service.stop();
      expect(service.value, isNull);
      expect(NativeFssnStations.sessions, before);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(peers, hasLength(3));
      service.start();
      await until(() => peers.length == 4 && service.value != null);
      service.dispose();
      expect(NativeFssnStations.sessions, before);
    },
    skip: !native,
  );

  test(
    'stop during pending HTTP cannot create a decoder or reconnect',
    () async {
      final response = Completer<http.Response>();
      final service = FssnStationMapService(
        createClient: () => MockClient((_) => response.future),
        connect: (_) => throw StateError('Must not connect after stop'),
        retryDelay: const Duration(milliseconds: 10),
      );
      final before = NativeFssnStations.sessions;
      service.start();
      service.stop();
      response.complete(
        http.Response.bytes(original('stations.original.json'), 200),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(NativeFssnStations.sessions, before);
      expect(service.value, isNull);
      service.dispose();
    },
    skip: !native,
  );

  testWidgets(
    'only the Android background station preference pauses the FSSN overlay',
    (tester) async {
      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      SharedPreferences.setMockInitialValues({'background_enabled': true});
      final settings = BackgroundSettingsProvider();
      await settings.load(await SharedPreferences.getInstance());
      final service = _DisplayService();
      addTearDown(settings.dispose);
      addTearDown(service.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settings,
          child: MaterialApp(
            home: FlutterMap(children: [FssnStationLayer(service: service)]),
          ),
        ),
      );

      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      expect(service.connected, isFalse);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(service.connected, isTrue);
      await settings.setStationConnected(BackgroundStationConnection.fssn, true);
      await tester.pump();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      expect(service.connected, isTrue);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settings.setStationConnected(
        BackgroundStationConnection.fssn,
        false,
      );
      await tester.pump();
      expect(service.connected, isTrue);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(service.connected, isTrue);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      expect(service.connected, isFalse);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(service.connected, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'map uses our zoom-sized dots and upstream colors, clearing on disconnect',
    (tester) async {
      final service = _DisplayService();
      final decoder = native
          ? NativeFssnStations(original('stations.original.json'))
          : null;
      addTearDown(() {
        service.dispose();
        decoder?.dispose();
      });
      if (decoder != null)
        service.value = decoder.process(original('overlay.original.bin'));
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(31, 110),
              initialZoom: 4,
            ),
            children: [FssnStationLayer(service: service)],
          ),
        ),
      );
      if (decoder != null) {
        final layer = tester.widget<StationDotPainterLayer>(
          find.byType(StationDotPainterLayer),
        );
        expect(layer.sizeWithCameraZoom, isTrue);
        expect(layer.dots, hasLength(15));
        for (var i = 0; i < layer.dots.length; i++) {
          expect(
            layer.dots[i].color.toARGB32(),
            service.value!.stations[i].argb,
          );
          expect(layer.dots[i].fillOpacity, 1);
        }
        final before = layer.dots;
        service.value = decoder.process(original('overlay.original.bin'));
        await tester.pump();
        expect(
          identical(
            tester
                .widget<StationDotPainterLayer>(
                  find.byType(StationDotPainterLayer),
                )
                .dots,
            before,
          ),
          isTrue,
        );
      }
      service.value = null;
      await tester.pump();
      expect(
        tester
            .widget<StationDotPainterLayer>(find.byType(StationDotPainterLayer))
            .dots,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
