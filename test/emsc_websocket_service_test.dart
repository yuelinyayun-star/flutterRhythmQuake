import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/emsc_eqlist_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final capturedText = File(
    'test/fixtures/emsc_ws_20261008.original.json',
  ).readAsStringSync(encoding: utf8);
  final captured = jsonDecode(capturedText) as Map<String, dynamic>;
  final feature = captured['data'] as Map<String, dynamic>;
  final properties = feature['properties'] as Map<String, dynamic>;
  final history =
      (jsonDecode(
                File(
                  'test/fixtures/emsc_history_20261008.original.json',
                ).readAsStringSync(encoding: utf8),
              )
              as Map)['features']
          as List;

  test(
    'unchanged official WS frame enters unified UI with original data',
    () async {
      final socket = _Channel();
      final service = EmscEqlistService.detached(
        socketFactory: (uri) {
          expect(
            uri.toString(),
            'wss://www.seismicportal.eu/standing_order/websocket',
          );
          return socket;
        },
        snapshotLoader: () async => [],
      );
      addTearDown(service.stop);
      final events = <Map<String, dynamic>>[];
      service.onCurrentUpdated = events.add;
      service.start();
      await _flush();
      socket.frames.add(capturedText);
      await _flush();
      expect(service.isConnected, isTrue);
      expect(events, hasLength(1));
      expect(events.single['originalData'], captured);
      expect(jsonDecode(capturedText), captured);
      final unified = QuakeEventAdapter.convert('emsc', events.single, 0)!;
      expect(unified.apiTypeLabel, 'EMSC');
      expect(unified.source, 'emsc');
      expect(unified.isEew, isFalse);
      expect(unified.eventId, properties['unid']);
      expect(unified.magnitude, properties['mag']);
      expect(unified.depth, properties['depth']);
      expect(unified.lat, properties['lat']);
      expect(unified.lng, properties['lon']);
      expect(unified.hypocenter, '内华达州附近');
      expect(
        QuakeTime.unifiedInstantUtc(unified),
        DateTime.parse(properties['time']),
      );
      expect(
        unified.reportTime!.toUtc(),
        DateTime.parse(properties['lastupdate']),
      );
      expect(unified.timeZone, QuakeTime.systemTimeZoneHours);
      expect(unified.sourcePayload!['originalData'], captured);
      // Actual WS capture revises a September earthquake in October. Catalog
      // maintenance must remain history-only under the existing admission rule.
      expect(unified.useSourceTimeForExpiry, isTrue);
      expect(
        QuakeTime.catalogInformationRemainingSeconds(
          unified,
          300,
          now: DateTime.parse(properties['lastupdate']),
          sourceNow: DateTime.parse(properties['lastupdate']),
        ),
        0,
      );
    },
  );

  test(
    'bootstrap preserves history and never publishes it as a new alert',
    () async {
      final socket = _Channel();
      var loads = 0;
      final service = EmscEqlistService.detached(
        socketFactory: (_) => socket,
        snapshotLoader: () async {
          ++loads;
          return history;
        },
      );
      addTearDown(service.stop);
      final events = <Map<String, dynamic>>[];
      service.onCurrentUpdated = events.add;
      service.start();
      service.start();
      await _flush();
      expect(loads, 1);
      expect(events, isEmpty);
      expect(service.latestList, hasLength(50));
      expect(
        service.latestList.first.eventId,
        history.first['properties']['unid'],
      );
      expect(
        service.latestList.first.originTime.toUtc(),
        DateTime.parse(history.first['properties']['time']),
      );
      expect(
        service.latestList.first.reportTime!.toUtc(),
        DateTime.parse(history.first['properties']['lastupdate']),
      );
      expect(service.latestList.every((quake) => quake.isHistory), isTrue);
    },
  );

  test('WS before history response and repeated frames publish once', () async {
    final socket = _Channel();
    final snapshot = Completer<List<dynamic>>();
    final service = EmscEqlistService.detached(
      socketFactory: (_) => socket,
      snapshotLoader: () => snapshot.future,
    );
    addTearDown(service.stop);
    final events = <Map<String, dynamic>>[];
    service.onCurrentUpdated = events.add;
    service.start();
    await _flush();
    socket.frames.add(capturedText);
    await _flush();
    snapshot.complete([feature]);
    socket.frames.add(utf8.encode(capturedText));
    await _flush();
    expect(events, hasLength(1));
    expect(service.latestList, hasLength(1));
    expect(service.latestList.single.eventId, properties['unid']);
  });

  test('history failure leaves the working realtime socket online', () async {
    final socket = _Channel();
    final service = EmscEqlistService.detached(
      socketFactory: (_) => socket,
      snapshotLoader: () async => throw StateError('history unavailable'),
    );
    addTearDown(service.stop);
    service.start();
    await _flush();
    socket.frames.add(capturedText);
    await _flush();
    expect(service.isConnected, isTrue);
    expect(service.latestList, hasLength(1));
  });

  test(
    'connection status waits for handshake; stop invalidates pending work',
    () async {
      final ready = Completer<void>();
      final socket = _Channel(ready: ready.future);
      var loads = 0;
      final service = EmscEqlistService.detached(
        socketFactory: (_) => socket,
        snapshotLoader: () async {
          ++loads;
          return history;
        },
      );
      service.start();
      expect(service.isConnected, isFalse);
      service.stop();
      ready.complete();
      await _flush();
      expect(loads, 0);
      expect(service.isConnected, isFalse);
      expect(service.latestList, isEmpty);
      expect(socket.sink.closed, isTrue);
    },
  );

  test('stop discards in-flight history and cancelled WS frames', () async {
    final socket = _Channel();
    final snapshot = Completer<List<dynamic>>();
    final service = EmscEqlistService.detached(
      socketFactory: (_) => socket,
      snapshotLoader: () => snapshot.future,
    );
    service.start();
    await _flush();
    service.stop();
    snapshot.complete(history);
    socket.frames.add(capturedText);
    await _flush();
    expect(service.latestList, isEmpty);
    expect(service.isRunning, isFalse);
  });

  test('disconnect reconnects once, stop cancels the retry timer', () {
    fakeAsync((clock) {
      final sockets = <_Channel>[];
      var loads = 0;
      final service = EmscEqlistService.detached(
        socketFactory: (_) {
          final socket = _Channel();
          sockets.add(socket);
          return socket;
        },
        snapshotLoader: () async {
          ++loads;
          return [];
        },
      );
      final statuses = <bool>[];
      service.onStatusChanged = statuses.add;
      service.start();
      clock.flushMicrotasks();
      expect(statuses, [true]);
      sockets.first.frames.close();
      clock.flushMicrotasks();
      expect(statuses, [true, false]);
      clock.elapse(const Duration(seconds: 2));
      clock.flushMicrotasks();
      expect(sockets, hasLength(2));
      expect(loads, 2);
      expect(service.isConnected, isTrue);
      sockets.last.frames.close();
      clock.flushMicrotasks();
      service.stop();
      clock.elapse(const Duration(minutes: 2));
      clock.flushMicrotasks();
      expect(sockets, hasLength(2));
    });
  });

  test(
    'older revisions and field-order duplicates never replace newer WS data',
    () async {
      final socket = _Channel();
      final service = EmscEqlistService.detached(
        socketFactory: (_) => socket,
        snapshotLoader: () async => [],
      );
      addTearDown(service.stop);
      final events = <Map<String, dynamic>>[];
      service.onCurrentUpdated = events.add;
      service.start();
      await _flush();
      final latest = _unitFeature(4.2, '2026-10-08T09:01:00Z');
      socket.frames.add(jsonEncode({'action': 'update', 'data': latest}));
      await _flush();
      final reordered = <String, dynamic>{
        for (final entry in latest.entries.toList().reversed)
          entry.key: entry.value,
      };
      socket.frames.add(jsonEncode({'action': 'update', 'data': reordered}));
      socket.frames.add(
        jsonEncode({
          'action': 'update',
          'data': _unitFeature(4.1, '2026-10-08T09:00:00Z'),
        }),
      );
      await _flush();
      expect(events, hasLength(1));
      expect(service.latestList.single.magnitude, 4.2);
    },
  );

  test(
    'reconnect catches up history silently and rejects replayed old revision',
    () {
      fakeAsync((clock) {
        final sockets = <_Channel>[];
        var loads = 0;
        final service = EmscEqlistService.detached(
          socketFactory: (_) {
            final socket = _Channel();
            sockets.add(socket);
            return socket;
          },
          snapshotLoader: () async => [
            loads++ == 0
                ? _unitFeature(4.1, '2026-10-08T09:00:00Z')
                : _unitFeature(4.2, '2026-10-08T09:01:00Z'),
          ],
        );
        final events = <Map<String, dynamic>>[];
        service.onCurrentUpdated = events.add;
        service.start();
        clock.flushMicrotasks();
        sockets.first.frames.close();
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 2));
        clock.flushMicrotasks();
        expect(service.latestList.single.magnitude, 4.2);
        expect(events, isEmpty);
        sockets.last.frames.add(
          jsonEncode({
            'action': 'update',
            'data': _unitFeature(4.1, '2026-10-08T09:00:00Z'),
          }),
        );
        clock.flushMicrotasks();
        expect(events, isEmpty);
        expect(service.latestList.single.magnitude, 4.2);
        service.stop();
        clock.flushMicrotasks();
      });
    },
  );

  test(
    'malformed frames cannot fabricate coordinates or clock values',
    () async {
      final socket = _Channel();
      final service = EmscEqlistService.detached(
        socketFactory: (_) => socket,
        snapshotLoader: () async => [],
      );
      addTearDown(service.stop);
      service.start();
      await _flush();
      socket.frames.add('invalid json');
      socket.frames.add(
        '{"action":"create","data":{"properties":{},"geometry":{}}}',
      );
      socket.frames.add('{"action":"delete","data":{}}');
      await _flush();
      expect(service.isConnected, isTrue);
      expect(service.latestList, isEmpty);
    },
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

// Synthetic protocol cases, separate from the unmodified upstream captures.
Map<String, dynamic> _unitFeature(double magnitude, String updated) => {
  'type': 'Feature',
  'id': 'unit-event',
  'geometry': {
    'type': 'Point',
    'coordinates': [121.0, 24.0, -10.0],
  },
  'properties': {
    'unid': 'unit-event',
    'time': '2026-10-08T08:59:00Z',
    'lastupdate': updated,
    'mag': magnitude,
    'depth': 10.0,
  },
};

class _Channel implements WebSocketChannel {
  _Channel({Future<void>? ready}) : ready = ready ?? Future<void>.value();
  final frames = StreamController<dynamic>();
  @override
  final Future<void> ready;
  @override
  Stream<dynamic> get stream => frames.stream;
  @override
  final _Sink sink = _Sink();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sink implements WebSocketSink {
  bool closed = false;
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
