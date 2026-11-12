import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/native_station_runtime.dart';
import 'package:flutterrhythmquake/services/sources/seisjs_service.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/services/station_history_capture.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';
import 'package:flutterrhythmquake/widgets/map/station_summary_projection.dart';
import 'package:flutterrhythmquake/widgets/map/station_summary_worker.dart';
import 'support/seisjs_service_before_20261017.dart' as frozen;

const fixtureRoot = 'test/fixtures/source_ws_followup_20261016';
List<int> original(int i) =>
    File('$fixtureRoot/seisjs_0$i.original.bytes').readAsBytesSync();
Future<void> until(
  bool Function() f, {
  int seconds = 10,
  String label = '',
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!f()) {
    if (DateTime.now().isAfter(end)) {
      fail('Native SeisJS did not reach expected state: $label');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

List<Object?> values(dynamic s) => [
  s.id,
  s.region,
  s.coordinate,
  s.shindo,
  s.calcShindo,
  s.intensity,
  s.pga,
  s.pgv,
  s.maxPga,
  s.maxPgv,
  s.maxIntensity,
  s.isDesktop,
  s.lastUpdate?.toUtc(),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = !NativeStationRuntime.supported;

  test(
    'unchanged original ingress matches frozen domain, map, automation, sidebar and history',
    () async {
      final service = SeisJsService.detached(
        useNative: true,
        nativeSettings: {'testing': true},
      );
      final reference = frozen.SeisJsService.detached();
      final views = <List<SeisJsStation>>[];
      final sub = service.stationStream.listen(views.add);
      final projection = StationSummaryProjection();
      final worker = StationSummaryWorker();
      addTearDown(() async {
        service.dispose();
        reference.dispose();
        projection.dispose();
        worker.dispose();
        await sub.cancel();
        await until(() => NativeStationRuntime.workers == 0);
      });
      service.connect();
      await until(
        () => service.nativeSummary != null,
        label: 'initial summary',
      );
      expect(service.nativeStatus, 'connecting');
      final clock = DateTime.parse('2026-10-16 16:50:53');
      reference.clock = () => clock;
      var previousViews = views.length;
      for (var i = 0; i < 8; i++) {
        final bytes = original(i);
        final raw = jsonDecode(utf8.decode(bytes)) as Map;
        reference.handleOriginal(bytes);
        service.handleOriginalForTesting(bytes, clock);
        if (raw['type'] == 'heartbeat') {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(service.nativeStatus, 'connecting');
          continue;
        }
        await until(
          () => views.length > previousViews,
          label: 'original frame $i',
        );
        previousViews = views.length;
        expect(
          service.stations.map(values).toList(),
          reference.stations.map(values).toList(),
        );
        expect(
          service.dataTimeNotifier.value!.toUtc(),
          reference.dataTimeNotifier.value!.toUtc(),
        );
        expect(service.nativeStatus, 'connected');
        final signature = StringBuffer()..write(reference.stations.length);
        for (final s in reference.stations) {
          signature.write('|${s.id}:${s.intensity.toStringAsFixed(3)}');
        }
        expect(service.nativeLayerSignature, signature.toString());
        for (var j = 0; j < service.stations.length; j++) {
          final a = service.stations[j],
              b = reference.stations[j],
              obs = service.nativeAutomationSamples[j];
          expect(a.preparedMapLevel, b.intensity.round().clamp(0, 12));
          expect(a.preparedMapActive, b.intensity.isFinite && b.intensity >= 0);
          expect(
            [
              obs.stationId,
              obs.stationName,
              obs.intensityLevel,
              obs.intensity,
              obs.latitude,
              obs.longitude,
              obs.observedAt.toUtc(),
              obs.strong,
            ],
            [
              b.id,
              b.region,
              b.shindo,
              b.intensity,
              b.coordinate.latitude,
              b.coordinate.longitude,
              b.lastUpdate!.toUtc(),
              b.shindo >= 4,
            ],
          );
        }
        final legacyViews = [
          for (final s in reference.stations)
            SeisJsStation(
              id: s.id,
              region: s.region,
              coordinate: s.coordinate,
              intensity: s.intensity,
            ),
        ];
        final expected = projection.project(
          nied: [],
          kma: [],
          cwa: [],
          palert: [],
          seisjs: legacyViews,
          snet: [],
          detection: ShakeDetectionService.idleSnapshot,
          lpgm: null,
          windowEnd: clock,
        );
        final actual = await worker.project(
          StationSummaryRequest(
            nied: [],
            kma: [],
            cwa: [],
            palert: [],
            seisjs: [],
            seisjsSummary: service.nativeSummary,
            snet: [],
            detection: ShakeDetectionService.idleSnapshot,
            lpgm: null,
            windowEnd: clock,
          ),
        );
        expect(actual!.seisJsStation?.id, expected.seisJsStation?.id);
        expect(actual.seisJsMaxStation?.id, expected.seisJsMaxStation?.id);
        // The native lazy frame is bound to the displayed revision, never the current network buffer.
        final saved = StationHistoryCapture.instance.latest.singleWhere(
          (f) => f.kind == 'seisjs',
        );
        expect(saved.originalJson!['data'], raw);
        expect(
          ForegroundStationPayload.decodeSeisJs(
            saved.snapshot['stations'],
          ).map(values),
          service.stations.map(values),
        );
      }
      reference.clock = () => clock.add(const Duration(seconds: 40));
      reference.expireOriginal();
      service.handleOriginalForTesting(original(0), reference.clock());
      await until(() => service.stations.isEmpty, label: 'expire');
      expect(reference.stations, isEmpty);
      expect(service.nativeSummary!.maximum, isNull);
      // Closing removes the lazy archive's dependency on a released native owner.
      service.disconnect();
      expect(
        StationHistoryCapture.instance.latest.where((f) => f.kind == 'seisjs'),
        isEmpty,
      );
    },
    skip: skip,
  );

  test(
    'real native WS transport reconnects and stops without Dart source sockets',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <WebSocket>[];
      final pings = <String>[];
      final requests = server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        peers.add(socket);
        socket.listen((data) {
          if (data == 'ping') pings.add(data as String);
        });
        socket.add(original(0));
        socket.add(original(1));
      });
      var dartSockets = 0;
      final service = SeisJsService.detached(
        useNative: true,
        socketFactory: (_) {
          dartSockets++;
          throw StateError('Dart ingress must not run');
        },
        nativeSettings: {
          'seisjsEndpoint': {
            'host': '127.0.0.1',
            'port': server.port,
            'secure': false,
            'path': '/all_seis',
          },
        },
      );
      final states = <bool>[];
      service.onStatusChanged = states.add;
      service.connect();
      try {
        await until(() => service.stations.isNotEmpty);
        expect(dartSockets, 0);
        expect(service.nativeStatus, 'connected');
        await peers.first.close();
        await until(() => states.contains(false) && peers.length >= 2);
        await until(() => service.nativeStatus == 'connected');
        expect(
          service.stations.single.id,
          (jsonDecode(utf8.decode(original(1))) as Map)['type'],
        );
        service.disconnect();
        final count = peers.length;
        await until(() => NativeStationRuntime.workers == 0);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(peers.length, count);
        expect(dartSockets, 0);
        expect(service.dataTimeNotifier.value, isNull);
      } finally {
        service.dispose();
        for (final socket in peers) {
          await socket.close();
        }
        await requests.cancel();
        await server.close(force: true);
      }
    },
    skip: skip,
  );
}
