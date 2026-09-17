import 'dart:convert';
import 'dart:io';

// Flutter's test clock dependency, used without adding a runtime dependency.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/sources/whews_nied_station_metadata.dart';
import 'package:flutterrhythmquake/services/sources/whews_socket_client.dart';
import 'package:flutterrhythmquake/services/sources/whews_station_service.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/whews_nied/$name.json').readAsStringSync())
        as Map<String, dynamic>;

class TestSocket extends WhewsSocketClient {
  TestSocket({
    required super.url,
    required super.apiToken,
    required super.onMessage,
    super.onStateChanged,
  });
  int reconnects = 0;
  @override
  void start() {
    onStateChanged?.call(WhewsSocketState.connecting);
    onStateChanged?.call(WhewsSocketState.connected);
  }

  @override
  void reconnect() {
    reconnects++;
    onStateChanged?.call(WhewsSocketState.error);
  }

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'captured NIED arrays retain order, values and documented UTC+8',
    () async {
      final service = WhewsStationService(
        kind: WhewsStationKind.nied,
        apiToken: '',
      );
      final frames = <WhewsStationFrame>[];
      final subscription = service.frameStream.listen(frames.add);
      final raw = fixture('observations');
      final before = jsonEncode(raw);
      service.handleMessageForTesting(fixture('stations'));
      service.handleMessageForTesting(raw);
      await Future<void>.delayed(Duration.zero);
      expect(frames, hasLength(1));
      expect(frames.single.dataTime, DateTime.utc(2026, 9, 8, 11, 47, 11));
      expect(frames.single.dataTime.isUtc, isTrue);
      expect(frames.single.values, raw['Data']['shindo']);
      expect(frames.single.pga, raw['Data']['pga']);
      expect(frames.single.pgv, raw['Data']['pgv']);
      expect(jsonEncode(raw), before);
      await subscription.cancel();
      service.dispose();
    },
  );

  test('explicit source offsets are preserved, not applied twice', () async {
    final service = WhewsStationService(
      kind: WhewsStationKind.nied,
      apiToken: '',
    );
    final frames = <WhewsStationFrame>[];
    final subscription = service.frameStream.listen(frames.add);
    service.handleMessageForTesting(fixture('stations'));
    // Boundary variation of the capture, not a claimed live API sample.
    final raw = fixture('observations');
    raw['Data']['timestamp'] = '2026-09-08T19:47:11+09:00';
    service.handleMessageForTesting(raw);
    await Future<void>.delayed(Duration.zero);
    expect(frames.single.dataTime, DateTime.utc(2026, 9, 8, 10, 47, 11));
    await subscription.cancel();
    service.dispose();
  });

  test('malformed optional layer keeps captured shindo and valid PGV', () async {
    final service = WhewsStationService(
      kind: WhewsStationKind.nied,
      apiToken: '',
    );
    final frames = <WhewsStationFrame>[];
    final subscription = service.frameStream.listen(frames.add);
    service.handleMessageForTesting(fixture('stations'));
    // Deliberate malformed-layer boundary case derived from the frozen capture.
    final raw = fixture('observations');
    raw['Data']['pga'] = [];
    final before = jsonEncode(raw);
    service.handleMessageForTesting(raw);
    await Future<void>.delayed(Duration.zero);
    expect(frames.single.values, raw['Data']['shindo']);
    expect(frames.single.pga, isEmpty);
    expect(frames.single.pgv, raw['Data']['pgv']);
    expect(jsonEncode(raw), before);
    await subscription.cancel();
    service.dispose();
  });

  test('missing authorization never opens a station socket', () {
    var opened = false;
    final service = WhewsStationService(
      kind: WhewsStationKind.nied,
      apiToken: '',
      socketFactory:
          ({
            required url,
            required apiToken,
            required onMessage,
            onStateChanged,
          }) {
            opened = true;
            return TestSocket(
              url: url,
              apiToken: apiToken,
              onMessage: onMessage,
              onStateChanged: onStateChanged,
            );
          },
    );
    service.start();
    expect(opened, isFalse);
    expect(service.stateNotifier.value, WhewsSocketState.unauthorized);
    service.dispose();
  });

  test(
    'heartbeat and repeated table/frame cannot keep NIED observations alive',
    () {
      fakeAsync((time) {
        late TestSocket socket;
        final service = WhewsStationService(
          kind: WhewsStationKind.nied,
          apiToken: 'test-only',
          socketFactory:
              ({
                required url,
                required apiToken,
                required onMessage,
                onStateChanged,
              }) => socket = TestSocket(
                url: url,
                apiToken: apiToken,
                onMessage: onMessage,
                onStateChanged: onStateChanged,
              ),
        );
        final frames = <WhewsStationFrame>[];
        service.frameStream.listen(frames.add);
        service.start();
        expect(service.stateNotifier.value, WhewsSocketState.connecting);
        socket.onMessage(fixture('stations'));
        socket.onMessage(fixture('observations'));
        time.flushMicrotasks();
        expect(service.stateNotifier.value, WhewsSocketState.connected);
        time.elapse(const Duration(seconds: 60));
        socket.onStateChanged?.call(WhewsSocketState.connected);
        socket.onMessage(fixture('stations'));
        socket.onMessage(fixture('observations'));
        time.elapse(const Duration(seconds: 30));
        time.flushMicrotasks();
        expect(socket.reconnects, 1);
        expect(service.stateNotifier.value, WhewsSocketState.error);
        expect(frames, hasLength(2));
        expect(frames.last.coordinates, isEmpty);
        expect(frames.last.values, isEmpty);
        service.stop();
        time.elapse(const Duration(minutes: 3));
        expect(socket.reconnects, 1);
        service.dispose();
      });
    },
  );

  test('no first observation reconnects; a fresh frame recovers', () {
    fakeAsync((time) {
      late TestSocket socket;
      final service = WhewsStationService(
        kind: WhewsStationKind.nied,
        apiToken: 'test-only',
        socketFactory:
            ({
              required url,
              required apiToken,
              required onMessage,
              onStateChanged,
            }) => socket = TestSocket(
              url: url,
              apiToken: apiToken,
              onMessage: onMessage,
              onStateChanged: onStateChanged,
            ),
      );
      service.start();
      time.elapse(WhewsStationService.observationTimeout);
      expect(socket.reconnects, 1);
      socket.start();
      socket.onMessage(fixture('stations'));
      socket.onMessage(fixture('observations'));
      expect(service.stateNotifier.value, WhewsSocketState.connected);
      service.dispose();
    });
  });

  test(
    'captured coordinates use local station names without changing positions',
    () async {
      await loadWhewsNiedPrefectures();
      final entries = fixture('stations')['stations'] as List;
      final coordinates = entries
          .map(
            (dynamic e) => LatLng(
              (e['latitude'] as num).toDouble(),
              (e['longitude'] as num).toDouble(),
            ),
          )
          .toList();
      final stations = buildWhewsNiedStations(coordinates);
      expect(stations, hasLength(1560));
      for (var i = 0; i < stations.length; i++) {
        expect(stations[i].coordinate, coordinates[i]);
        expect(stations[i].id, i);
      }
      expect(stations.first.code, 'WHEWS-NIED-1');
      expect(stations.first.name, '尾西');
      expect(stations.first.prefecture, '愛知県');
      expect(stations[643].name, '松ヶ崎');
      expect(stations[643].prefecture, '新潟県');
      expect(stations[856].name, '山口');
      expect(stations[856].prefecture, '山口県');
      expect(stations.map((s) => s.code).toSet(), hasLength(stations.length));
      final matched = stations.where((s) => s.prefecture.isNotEmpty).length;
      // ignore: avoid_print
      print('Captured NIED prefectures: $matched/${stations.length} matched');
      expect(matched, 1560);
      final unknown = buildWhewsNiedStations([const LatLng(0, 0)]).single;
      expect(unknown.prefecture, isEmpty);
      expect(unknown.name, isEmpty);
      final reversed = buildWhewsNiedStations(coordinates.reversed.toList());
      expect(reversed.last.name, stations.first.name);
      expect(reversed.last.prefecture, stations.first.prefecture);
    },
  );
}
