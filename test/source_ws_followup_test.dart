import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/sources/kma_monitor.dart';
import 'package:flutterrhythmquake/services/sources/seisjs_service.dart';
import 'package:flutterrhythmquake/services/sources/p2pquake_service.dart';
import 'package:flutterrhythmquake/services/sources/native_websocket_channel.dart';
import 'package:flutterrhythmquake/services/station_history_capture.dart';

const captureRoot = 'test/fixtures/source_ws_followup_20261016';
List<int> raw(String name) =>
    File('$captureRoot/$name.original.bytes').readAsBytesSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'SeisJS retries once, owns one expiry timer and rejects callbacks from old sockets',
    () {
      fakeAsync((clock) {
        final sockets = <_Channel>[];
        final service = SeisJsService.detached(
          socketFactory: (_) {
            final socket = _Channel();
            sockets.add(socket);
            return socket;
          },
        );
        service.connect();
        clock.flushMicrotasks();
        expect(clock.periodicTimerCount, 2);
        for (var attempt = 0; attempt < 4; attempt++) {
          final old = sockets.last;
          old.frames.error();
          old.frames.finish();
          clock.flushMicrotasks();
          expect(clock.periodicTimerCount, 1);
          clock.elapse(const Duration(seconds: 5));
          clock.flushMicrotasks();
          expect(sockets.length, attempt + 2);
          expect(clock.periodicTimerCount, 2);
          final current = sockets.last;
          old.frames.send(raw('seisjs_01'));
          old.frames.error();
          old.frames.finish();
          clock.flushMicrotasks();
          expect(service.stations, isEmpty);
          expect(current.output.closed, isFalse);
        }
        sockets.last.frames.send(raw('seisjs_01'));
        clock.flushMicrotasks();
        final original = jsonDecode(utf8.decode(raw('seisjs_01'))) as Map;
        expect(service.stations.single.id, original['type']);
        expect(
          service.stations.single.intensity,
          (original['Intensity'] as num).toDouble(),
        );
        expect(
          service.stations.single.lastUpdate,
          DateTime.parse(original['update_at'] as String),
        );
        expect(
          StationHistoryCapture.instance.original('seisjs')!['data'],
          original,
        );
        service.disconnect();
        clock.flushMicrotasks();
        expect(clock.periodicTimerCount, 0);
        clock.elapse(const Duration(minutes: 1));
        clock.flushMicrotasks();
        expect(sockets, hasLength(5));
        expect(
          sockets.every(
            (s) => s.frames.subscription.cancelled && s.output.closed,
          ),
          isTrue,
        );
        service.dispose();
        clock.flushMicrotasks();
      });
    },
  );

  test('SeisJS late ready failure cannot close a replacement session', () {
    fakeAsync((clock) {
      final old = _Channel(ready: false), current = _Channel();
      var calls = 0;
      final service = SeisJsService.detached(
        socketFactory: (_) => calls++ == 0 ? old : current,
      );
      service.connect();
      service.disconnect();
      service.connect();
      clock.flushMicrotasks();
      old.handshake.completeError(StateError('delayed handshake failure'));
      old.frames.error();
      old.frames.finish();
      old.frames.send(raw('seisjs_01'));
      clock.flushMicrotasks();
      expect(service.stations, isEmpty);
      expect(current.output.closed, isFalse);
      current.frames.send(raw('seisjs_01'));
      clock.flushMicrotasks();
      expect(service.stations, hasLength(1));
      service.dispose();
      clock.flushMicrotasks();
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test(
    'KMA handshake status, byte frames, source-clock admission and single retry',
    () {
      fakeAsync((clock) {
        final sockets = <_Channel>[];
        final uris = <Uri>[];
        final service = KmaMonitorService.detached(
          socketFactory: (uri) {
            uris.add(uri);
            final socket = _Channel(ready: sockets.isNotEmpty);
            sockets.add(socket);
            return socket;
          },
        );
        service.setConnectionSource('fan');
        service.connect();
        clock.flushMicrotasks();
        expect(service.isConnected, isFalse);
        sockets.first.handshake.complete();
        clock.flushMicrotasks();
        expect(service.isConnected, isTrue);
        sockets.first.frames.send(raw('kma_01'));
        sockets.first.frames.send(raw('kma_02'));
        clock.flushMicrotasks();
        final original = jsonDecode(utf8.decode(raw('kma_02'))) as Map;
        final values = original['Data']['mmi'] as List;
        expect(service.stations.map((s) => s.intensity).toList(), values);
        final firstTime = service.dataTimeNotifier.value;
        sockets.first.frames.send(raw('kma_03'));
        clock.flushMicrotasks();
        final latest = service.dataTimeNotifier.value;
        sockets.first.frames.send(raw('kma_02'));
        clock.flushMicrotasks();
        expect(service.dataTimeNotifier.value, latest);
        expect(latest!.isAfter(firstTime!), isTrue);
        final old = sockets.first;
        old.frames.error();
        old.frames.finish();
        clock.flushMicrotasks();
        expect(service.isConnected, isFalse);
        clock.elapse(const Duration(seconds: 10));
        clock.flushMicrotasks();
        expect(sockets, hasLength(2));
        expect(uris.last.host, 'ws.fanstudio.hk');
        old.frames.send(raw('kma_01'));
        old.frames.send(raw('kma_02'));
        old.frames.error();
        old.frames.finish();
        clock.flushMicrotasks();
        expect(sockets.last.output.closed, isFalse);
        expect(service.isConnected, isTrue);
        service.dispose();
        clock.flushMicrotasks();
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );

  test(
    'KMA delayed failed handshake and busy-server rotation cannot duplicate retry',
    () {
      fakeAsync((clock) {
        final sockets = <_Channel>[];
        final service = KmaMonitorService.detached(
          socketFactory: (_) {
            final s = _Channel(ready: sockets.isNotEmpty);
            sockets.add(s);
            return s;
          },
        );
        service.setConnectionSource('fan');
        service.connect();
        service.disconnect();
        service.connect();
        clock.flushMicrotasks();
        sockets.first.handshake.completeError(StateError('old handshake'));
        sockets.first.frames.finish();
        clock.flushMicrotasks();
        expect(service.isConnected, isTrue);
        // Explicit controlled protocol case; not an upstream earthquake sample.
        sockets.last.frames.send(
          utf8.encode('{"type":"error","message":"连接数超限"}'),
        );
        sockets.last.frames.finish();
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 3));
        clock.flushMicrotasks();
        expect(sockets, hasLength(3));
        service.disconnect();
        clock.flushMicrotasks();
        clock.elapse(const Duration(minutes: 2));
        expect(sockets, hasLength(3));
        expect(clock.pendingTimers, isEmpty);
        service.dispose();
        clock.flushMicrotasks();
      });
    },
  );

  test(
    'P2P original text and UTF-8 produce identical unified events and source payloads',
    () async {
      final bytes = File(
        'test/fixtures/jma_voice/p2p_scale_prompt.json',
      ).readAsBytesSync();
      final textService = P2PQuakeService(), byteService = P2PQuakeService();
      final textEvents = <UnifiedQuakeData>[],
          byteEvents = <UnifiedQuakeData>[];
      final a = textService.onUnifiedEvent.listen(textEvents.add),
          b = byteService.onUnifiedEvent.listen(byteEvents.add);
      textService.handleMessageForTesting(utf8.decode(bytes));
      byteService.handleMessageForTesting(bytes);
      await Future<void>.delayed(Duration.zero);
      expect(byteEvents, hasLength(2));
      expect(
        byteEvents.map((e) => e.toMap()).toList(),
        textEvents.map((e) => e.toMap()).toList(),
      );
      final originals = jsonDecode(utf8.decode(bytes)) as List;
      for (var i = 0; i < originals.length; i++) {
        expect(byteEvents[i].sourcePayload, originals[i]);
      }
      await a.cancel();
      await b.cancel();
      textService.dispose();
      byteService.dispose();
    },
  );

  test(
    'P2P invalidates stopped handshakes, old frames and simultaneous failure callbacks',
    () {
      fakeAsync((clock) {
        final sockets = <_Channel>[];
        final service = P2PQuakeService(
          socketFactory: (_) {
            final s = _Channel(ready: sockets.isNotEmpty);
            sockets.add(s);
            return s;
          },
        );
        final events = <UnifiedQuakeData>[];
        final sub = service.onUnifiedEvent.listen(events.add);
        service.connect();
        service.disconnect();
        service.connect();
        clock.flushMicrotasks();
        final old = sockets.first;
        old.handshake.completeError(StateError('old handshake failure'));
        old.frames.send(
          File(
            'test/fixtures/jma_voice/p2p_scale_prompt.json',
          ).readAsBytesSync(),
        );
        old.frames.error();
        old.frames.finish();
        clock.flushMicrotasks();
        expect(events, isEmpty);
        expect(sockets.last.output.sent, ['ping']);
        expect(sockets.last.output.closed, isFalse);
        sockets.last.frames.error();
        sockets.last.frames.finish();
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 3));
        clock.flushMicrotasks();
        expect(sockets, hasLength(3));
        service.disconnect();
        clock.flushMicrotasks();
        clock.elapse(const Duration(minutes: 2));
        expect(sockets, hasLength(3));
        expect(clock.pendingTimers, isEmpty);
        unawaited(sub.cancel());
        service.dispose();
        clock.flushMicrotasks();
      });
    },
  );

  test(
    'three source services consume captured frames over actual native sockets and release workers',
    () async {
      final baseline = NativeWebSocketChannel.activeWorkers;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <WebSocket>[];
      final originals = <String, List<List<int>>>{
        '/kma': [raw('kma_01'), raw('kma_02')],
        '/seisjs': [raw('seisjs_01')],
        '/p2p': [
          File(
            'test/fixtures/jma_voice/p2p_scale_prompt.json',
          ).readAsBytesSync(),
        ],
      };
      final requests = server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        peers.add(socket);
        socket.listen((_) {});
        for (final bytes in originals[request.uri.path]!) {
          socket.add(utf8.decode(bytes));
        }
      });
      WebSocketChannel factory(String path) => NativeWebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:${server.port}$path'),
        textAsBytes: true,
      );
      final kma = KmaMonitorService.detached(
        socketFactory: (_) => factory('/kma'),
      );
      final seis = SeisJsService.detached(
        socketFactory: (_) => factory('/seisjs'),
      );
      final p2p = P2PQuakeService(socketFactory: (_) => factory('/p2p'));
      final k = kma.stationStream.first, s = seis.stationStream.first;
      final p = p2p.onUnifiedEvent.take(2).toList();
      try {
        kma.connect();
        seis.connect();
        p2p.connect();
        await Future.wait([k, s, p]).timeout(const Duration(seconds: 10));
        expect(kma.stations, isNotEmpty);
        expect(seis.stations, hasLength(1));
        expect(await p, hasLength(2));
      } finally {
        kma.dispose();
        seis.dispose();
        p2p.dispose();
        for (final peer in peers) {
          await peer.close();
        }
        await requests.cancel();
        await server.close(force: true);
      }
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (NativeWebSocketChannel.activeWorkers != baseline &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(NativeWebSocketChannel.activeWorkers, baseline);
    },
    skip:
        !Platform.isWindows ||
        !Platform.environment.containsKey('RQ_STATION_CORE_LIBRARY'),
  );
}

// A deliberately late-callback transport double. Cancellation is recorded but
// callbacks can still be invoked to model work queued before cancellation.
class _Frames extends Stream<dynamic> {
  void Function(dynamic)? data;
  Function? onError;
  void Function()? onDone;
  final subscription = _Subscription();
  void send(dynamic value) => data?.call(value);
  void error() {
    if (onError != null) {
      Function.apply(onError!, [StateError('transport failure')]);
    }
  }

  void finish() => onDone?.call();
  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    data = onData;
    this.onError = onError;
    this.onDone = onDone;
    return subscription;
  }
}

class _Subscription implements StreamSubscription<dynamic> {
  bool cancelled = false;
  @override
  Future<void> cancel() async {
    cancelled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Channel implements WebSocketChannel {
  _Channel({bool ready = true}) {
    if (ready) handshake.complete();
  }
  final handshake = Completer<void>();
  final frames = _Frames();
  final output = _Sink();
  @override
  Future<void> get ready => handshake.future;
  @override
  Stream<dynamic> get stream => frames;
  @override
  WebSocketSink get sink => output;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sink implements WebSocketSink {
  bool closed = false;
  final sent = <dynamic>[];
  @override
  void add(dynamic value) {
    if (closed) throw StateError('closed');
    sent.add(value);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
