import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sources/native_station_runtime.dart';
import 'package:flutterrhythmquake/services/sources/kma_monitor.dart';
import 'package:flutterrhythmquake/services/sources/cwa_station_service.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Harness {
  final runtime = NativeStationRuntime();
  final stream = StreamController<Map<String, dynamic>>.broadcast();
  Map<String, dynamic>? latest;
  Harness(Map<String, Object?> settings) {
    runtime.onFrame = (frame) {
      latest = frame;
      stream.add(frame);
    };
    runtime.start({...settings, 'testing': true});
  }
  Future<Map<String, dynamic>> frame(int count) async {
    if (latest != null && (latest!['frames'] as int) >= count) return latest!;
    return stream.stream
        .firstWhere((f) => (f['frames'] as int) >= count)
        .timeout(const Duration(seconds: 10));
  }

  Future<void> close() async {
    runtime.stop();
    await stream.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final enabled = NativeStationRuntime.supported;
  test(
    'KMA direct and Rhythm sockets deliver one unified event from original bytes',
    () async {
      SharedPreferences.setMockInitialValues({});
      const fixture = 'server/kma_pews_relay/test_fixtures';
      final official = File(
        '$fixture/kma_20261117141040.original.b',
      ).readAsBytesSync();
      final late = File(
        '$fixture/kma_20261117142557.original.b',
      ).readAsBytesSync();
      final earlyDetail = File(
        '$fixture/kma_2026011364.original.le',
      ).readAsBytesSync();
      final lateDetail = File(
        '$fixture/kma_2026011364.original.li',
      ).readAsBytesSync();
      final stationTable = File(
        '$fixture/kma_stations_20261117142557.original.s',
      ).readAsBytesSync();
      final earlyStamp = DateTime.parse('2026-11-17T14:10:40Z');
      final lateStamp = DateTime.parse('2026-11-17T14:25:57Z');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final api = Completer<WebSocket>();
      var tableRequests = 0;
      var lateCapture = false;
      server.listen((request) async {
        final path = request.uri.path;
        if (path == '/kma-eew') {
          final socket = await WebSocketTransformer.upgrade(request);
          api.complete(socket);
          socket.listen((_) {});
          return;
        }
        final response = request.response;
        final stamp = lateCapture ? lateStamp : earlyStamp;
        response.headers.set(
          'ST',
          '${stamp.millisecondsSinceEpoch ~/ 1000 + 1}',
        );
        if (path == '/pews/') {
          response.headers.contentType = ContentType.html;
          response.write('<html></html>');
        } else if (path == '/pews/data/20261117141040.b' && !lateCapture) {
          response.add(official);
        } else if (path == '/pews/data/20261117142557.b' && lateCapture) {
          response.add(late);
        } else if (path == '/pews/data/20261117142557.s' && lateCapture) {
          tableRequests++;
          response.add(stationTable);
        } else if (path == '/pews/data/2026011364.le') {
          response.add(earlyDetail);
        } else if (path == '/pews/data/2026011364.li') {
          response.add(lateDetail);
        } else {
          response.statusCode = HttpStatus.notFound;
        }
        await response.close();
      });
      final endpoint = {
        'host': '127.0.0.1',
        'port': server.port,
        'secure': false,
      };
      final direct = NativeStationRuntime();
      final rhythm = NativeStationRuntime();
      final stations = NativeStationRuntime();
      var sourceNow = earlyStamp;
      final provider = QuakeProvider(
        startCatalogServices: false,
        nativeUnifiedEvents: true,
        eewClock: () => sourceNow,
      );
      addTearDown(() async {
        direct.stop();
        rhythm.stop();
        stations.stop();
        provider.dispose();
        await server.close(force: true);
      });
      Future<UnifiedQuakeData> readEvent(NativeStationRuntime runtime) {
        final result = Completer<UnifiedQuakeData>();
        runtime.onFrame = (frame) {
          expect(frame['stations'], isEmpty);
          for (final raw in frame['eewEvents'] as List) {
            final event = UnifiedQuakeData.fromMap(
              Map<String, dynamic>.from(raw as Map),
            );
            if (event.hypocenter.isNotEmpty && !result.isCompleted) {
              result.complete(event);
            }
          }
        };
        return result.future.timeout(const Duration(seconds: 12));
      }

      final directEvent = readEvent(direct);
      direct.start({
        'kind': 'kma',
        'source': 'pews_local',
        'endpoint': endpoint,
        'pewsStations': false,
      });
      final apiEvent = readEvent(rhythm);
      rhythm.start({
        'kind': 'kma_eew',
        'source': 'rhythm',
        'endpoint': endpoint,
      });
      final socket = await api.future.timeout(const Duration(seconds: 12));
      socket.add(
        jsonEncode({
          'type': 'pews_binary',
          'frameEpochMs': earlyStamp.millisecondsSinceEpoch,
          'originalBase64': base64Encode(official),
          'detailOriginalBase64': base64Encode(earlyDetail),
        }),
      );
      final local = await directEvent;
      final relay = await apiEvent;
      expect(local.apiTypeLabel, 'KMA-PEWS');
      expect(relay.apiTypeLabel, 'Rhythm');
      expect(local.eventId, '2026011364');
      expect(
        QuakeTime.unifiedInstantUtc(local),
        DateTime.parse('2026-11-17T14:10:17Z'),
      );
      expect(local.hypocenter, relay.hypocenter);
      expect(local.depth, -1);
      expect(local.sourcePayload?['originalBase64'], base64Encode(official));
      expect(relay.sourcePayload?['originalBase64'], base64Encode(official));
      await provider.eewHistoryReadyForTest;
      provider.handleUnifiedEventForTest(local, suppressEffects: true);
      provider.handleUnifiedEventForTest(relay, suppressEffects: true);
      expect(provider.unifiedEvents, hasLength(1));
      expect(provider.unifiedEvents.single.eventId, local.eventId);
      expect(provider.eewHistory.single.reports, hasLength(1));
      expect(tableRequests, 0);

      direct.stop();
      lateCapture = true;
      final stationFrame = Completer<Map<String, dynamic>>();
      final decodedFinal = Completer<UnifiedQuakeData>();
      stations.onFrame = (value) {
        for (final raw in value['eewEvents'] as List) {
          if (!decodedFinal.isCompleted) {
            decodedFinal.complete(
              UnifiedQuakeData.fromMap(Map<String, dynamic>.from(raw as Map)),
            );
          }
        }
        if ((value['stations'] as List).isNotEmpty &&
            !stationFrame.isCompleted) {
          stationFrame.complete(value);
        }
      };
      stations.start({
        'kind': 'kma',
        'source': 'pews_local',
        'endpoint': endpoint,
        'pewsStations': true,
      });
      final frame = await stationFrame.future.timeout(
        const Duration(seconds: 12),
      );
      expect(frame['stations'], hasLength(265));
      expect(DateTime.parse(frame['dataTime'] as String), lateStamp);
      expect(
        stations.original?['metadataOriginalBase64'],
        base64Encode(stationTable),
      );
      expect(stations.original?['dataOriginalBase64'], base64Encode(late));
      expect(tableRequests, 1);
      final finalReport = await decodedFinal.future.timeout(
        const Duration(seconds: 12),
      );
      expect(finalReport.isFinal, isTrue);
      expect(finalReport.depth, 20);
      sourceNow = lateStamp;
      provider.handleUnifiedEventForTest(finalReport, suppressEffects: true);
      expect(provider.eewHistory.single.reports, hasLength(1));
      await socket.close();
    },
    skip: !enabled,
  );

  test(
    'original KMA socket bytes match the complete Dart display/history path',
    () async {
      final h = Harness({'kind': 'kma', 'source': 'pews', 'hold': 3});
      final reference = KmaMonitorService.detached()..setIntensityHoldFrames(3);
      final signals = <int>[];
      reference.onShakeDetected = signals.add;
      reference.onShakeExpired = () => signals.add(-1);
      addTearDown(() async {
        reference.dispose();
        await h.close();
      });
      var accepted = 0;
      final nativeSignals = <int>[];
      h.runtime.onFrame = (frame) {
        h.latest = frame;
        h.stream.add(frame);
        nativeSignals.addAll((frame['signals'] as List).cast<int>());
      };
      final clock = DateTime.parse('2026-10-16T10:00:00Z');
      for (var i = 0; i < 8; i++) {
        final bytes = File(
          'test/fixtures/source_ws_followup_20261016/kma_${i.toString().padLeft(2, '0')}.original.bytes',
        ).readAsBytesSync();
        reference.handleOriginalForTesting(utf8.decode(bytes));
        h.runtime.injectOriginal(bytes, clock);
        final v = jsonDecode(utf8.decode(bytes)) as Map;
        if (v['Data'] == null) continue;
        final frame = await h.frame(++accepted);
        final actual = ForegroundStationPayload.decodeKma(frame['stations']);
        expect(actual.length, reference.stations.length);
        expect(
          DateTime.parse(frame['dataTime'] as String),
          reference.dataTimeNotifier.value!.toUtc(),
        );
        for (var j = 0; j < actual.length; j++) {
          final a = actual[j], b = reference.stations[j];
          expect(
            [
              a.id,
              a.coordinate,
              a.intensity,
              a.activityLevel,
              a.holdLevel,
              a.ascend,
              a.isActive,
            ],
            [
              b.id,
              b.coordinate,
              b.intensity,
              b.activityLevel,
              b.holdLevel,
              b.ascend,
              b.isActive,
            ],
          );
        }
        final archive = h.runtime.archive!;
        expect(
          (archive['stations'] as List).map(
            (dynamic row) => row['recentLevel'],
          ),
          reference.stations.map((s) => s.recentLevel),
        );
        expect(h.runtime.original!['data'], v);
      }
      expect(accepted, 6);
      expect(nativeSignals, signals);
      final previous = h.latest!['dataTime'];
      final old = File(
        'test/fixtures/source_ws_followup_20261016/kma_02.original.bytes',
      ).readAsBytesSync();
      h.runtime.injectOriginal(old, clock);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(h.latest!['dataTime'], previous);
      expect(h.latest!['frames'], 6);
    },
    skip: !enabled,
  );

  test(
    'original TREM SSE observations match legacy station merge, sort and alerts',
    () async {
      final h = Harness({'kind': 'cwa'});
      final reference = CwaStationService.detached();
      addTearDown(() async {
        reference.stop();
        await h.close();
      });
      final meta = File(
        'test/fixtures/api_ingress_20261016/trem_metadata.original.bytes',
      ).readAsBytesSync();
      reference.handleOriginalForTesting(utf8.decode(meta), metadata: true);
      final clock = DateTime.parse('2026-10-17T12:00:00Z');
      h.runtime.injectOriginal(meta, clock);
      var count = 0;
      final lines = File(
        'test/fixtures/api_ingress_20261016/trem_stream.original.bytes',
      ).readAsLinesSync();
      for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final original = line.substring(5).trim();
        Map v;
        try {
          v = jsonDecode(original) as Map;
        } on FormatException {
          continue;
        } // The capture ends mid-frame; retain raw bytes.
        if (v['station'] is! Map) continue;
        final accepted = reference.handleOriginalForTesting(original);
        h.runtime.injectOriginal(utf8.encode(original), clock);
        if (!accepted) continue;
        final frame = await h.frame(++count);
        final actual = ForegroundStationPayload.decodeCwa(frame['stations']);
        final expected = {for (final s in reference.stations) s.id: s};
        expect(actual.length, expected.length);
        expect(
          DateTime.parse(frame['dataTime'] as String),
          reference.dataTimeNotifier.value!.toUtc(),
        );
        for (final a in actual) {
          final b = expected[a.id]!;
          expect(
            [
              a.code,
              a.net,
              a.coordinate,
              a.work,
              a.pga,
              a.pgv,
              a.intensity,
              a.alertIntensity,
              a.hasAlert,
            ],
            [
              b.code,
              b.net,
              b.coordinate,
              b.work,
              b.pga,
              b.pgv,
              b.intensity,
              b.alertIntensity,
              b.hasAlert,
            ],
          );
        }
        expect(
          actual.map((s) => s.currentIntensity),
          reference.stations.map((s) => s.currentIntensity),
        );
        expect(h.runtime.original!['data'], v);
      }
      expect(count, greaterThan(3));
      final archive = h.runtime.archive!;
      expect(archive['kind'], 'cwa');
      expect((archive['stations'] as List).length, reference.stations.length);
    },
    skip: !enabled,
  );

  test(
    'source actors release on stop and cannot publish into their replacement',
    () async {
      final baseline = NativeStationRuntime.workers;
      for (var i = 0; i < 12; i++) {
        final h = Harness({'kind': i.isEven ? 'kma' : 'cwa'});
        await h.frame(0);
        await h.close();
      }
      final until = DateTime.now().add(const Duration(seconds: 5));
      while (NativeStationRuntime.workers != baseline &&
          DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(NativeStationRuntime.workers, baseline);
    },
    skip: !enabled,
  );
}
