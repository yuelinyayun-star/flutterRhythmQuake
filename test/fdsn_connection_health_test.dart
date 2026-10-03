import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_connection_health.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_motion_service_io.dart';

import 'fdsn_connection_test.dart' show dataPacket, infoPackets;

void main() {
  final origin = DateTime.utc(2026, 10, 3);
  for (final reply in [true, false]) {
    test(
      'idle heartbeat (reply=$reply) does not invent fresh observations',
      () async {
        final server = await ServerSocket.bind('127.0.0.1', 0);
        final sockets = <Socket>[];
        final pings = <DateTime>[];
        server.listen((socket) {
          sockets.add(socket);
          unawaited(socket.done.catchError((Object _) {}));
          socket
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((line) {
                if (line == 'INFO ID') {
                  pings.add(DateTime.now());
                  if (reply) socket.add(infoPackets('<seedlink/>'));
                } else if (line != 'END') {
                  socket.add(ascii.encode('OK\r\n'));
                }
              }, onError: (_) {});
        });
        final service = FdsnMotionService.forTesting(
          streams: [
            FdsnSeedLinkStream(
              source: 'EarthScope',
              host: '127.0.0.1',
              port: server.port,
              network: 'XX',
              station: 'AAA',
              selector: 'BH?.D',
            ),
          ],
          watchdogInterval: const Duration(milliseconds: 10),
          heartbeatInterval: const Duration(milliseconds: 80),
          networkTimeout: const Duration(milliseconds: 250),
        );
        try {
          service.connectProvidedStreamsForTesting();
          await Future<void>.delayed(const Duration(milliseconds: 430));
          final diag = service.connectionDiagnostics.single;
          expect(pings, isNotEmpty);
          expect(diag['packets'], 0);
          expect(diag['received'], 0);
          expect(diag['lastValidAgeSeconds'], -1);
          expect(diag['socketOpen'], reply);
          expect(
            diag['lastCloseReason'],
            reply ? '' : 'network receive timeout',
          );
          for (var i = 1; i < pings.length; i++) {
            expect(
              pings[i].difference(pings[i - 1]).inMilliseconds,
              greaterThanOrEqualTo(75),
            );
          }
          service.disconnect();
          final before = pings.length;
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(pings.length, before);
        } finally {
          service.dispose();
          for (final socket in sockets) {
            socket.destroy();
          }
          await server.close();
        }
      },
    );
  }
  for (final batchSupported in [true, false]) {
    test('SeisComP batch negotiation (supported=$batchSupported)', () async {
      final server = await ServerSocket.bind('127.0.0.1', 0);
      final sockets = <Socket>[];
      final commands = <String>[];
      final ready = Completer<void>();
      server.listen((socket) {
        sockets.add(socket);
        unawaited(socket.done.catchError((Object _) {}));
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              commands.add(line);
              if (line == 'BATCH') {
                socket.add(
                  ascii.encode(batchSupported ? 'OK\r\n' : 'ERROR\r\n'),
                );
              } else if (line == 'END') {
                socket.add(dataPacket('AAA', DateTime.now().toUtc()));
              } else if (!batchSupported) {
                socket.add(ascii.encode('OK\r\n'));
              }
            }, onError: (_) {});
      });
      final service = FdsnMotionService.forTesting(
        streams: [
          FdsnSeedLinkStream(
            source: 'IPGP',
            host: '127.0.0.1',
            port: server.port,
            network: 'XX',
            station: 'AAA',
            selector: 'BH?.D',
          ),
        ],
        responseClientFactory: () =>
            MockClient((_) async => http.Response('', 204)),
      );
      final sub = service.sampleStream.listen((_) {
        if (!ready.isCompleted) ready.complete();
      });
      try {
        service.connectProvidedStreamsForTesting();
        await ready.future.timeout(const Duration(seconds: 3));
        expect(commands, [
          'BATCH',
          'STATION AAA XX',
          'SELECT BH?.D',
          'DATA',
          'END',
        ]);
        expect(service.connectionDiagnostics.single['accepted'], 1);
      } finally {
        service.dispose();
        await sub.cancel();
        for (final socket in sockets) {
          socket.destroy();
        }
        await server.close();
      }
    });
  }
  test(
    'persistent widespread lag recovers with bounded exponential cooldown',
    () {
      final health = FdsnConnectionHealth(grace: Duration.zero);
      health.connected(origin);
      void old(DateTime now) => health.observe(
        'XX.AAA',
        now.subtract(const Duration(minutes: 4)),
        now,
      );
      old(origin);
      expect(health.shouldRecover(origin), isFalse);
      final first = origin.add(const Duration(minutes: 1));
      old(first);
      expect(health.shouldRecover(first), isTrue);
      expect(health.nextRecoveryAt, first.add(const Duration(minutes: 5)));
      health.connected(first);
      old(first);
      expect(health.shouldRecover(first), isFalse);
      final before = first.add(const Duration(minutes: 4));
      old(before);
      expect(health.shouldRecover(before), isFalse);
      final second = first.add(const Duration(minutes: 5));
      old(second);
      expect(health.shouldRecover(second), isTrue);
      expect(health.nextRecoveryAt, second.add(const Duration(minutes: 10)));
      expect(health.recoveries, 2);
    },
  );

  test('one noisy stale station does not restart healthy peers', () {
    final health = FdsnConnectionHealth(grace: Duration.zero);
    health.connected(origin);
    for (var seconds = 0; seconds <= 180; seconds += 15) {
      final now = origin.add(Duration(seconds: seconds));
      for (var packet = 0; packet < 500; packet++) {
        health.observe('OLD', now.subtract(const Duration(minutes: 4)), now);
      }
      for (var station = 0; station < 4; station++) {
        health.observe('FRESH$station', now, now);
      }
      expect(health.shouldRecover(now), isFalse);
    }
  });

  test('future data, empty sockets and short lag never trigger recovery', () {
    final health = FdsnConnectionHealth(grace: Duration.zero);
    health.connected(origin);
    health.observe('A', origin.add(const Duration(hours: 1)), origin);
    expect(health.shouldRecover(origin), isFalse);
    health.observe('A', origin.subtract(const Duration(minutes: 4)), origin);
    expect(health.shouldRecover(origin), isFalse);
    final recovered = origin.add(const Duration(seconds: 45));
    health.observe('A', recovered, recovered);
    expect(health.shouldRecover(recovered), isFalse);
    expect(
      health.shouldRecover(origin.add(const Duration(minutes: 10))),
      isFalse,
    );
  });

  test('startup grace and healthy recovery prevent reconnect storms', () {
    final health = FdsnConnectionHealth();
    health.connected(origin);
    for (var minute = 0; minute <= 3; minute++) {
      final now = origin.add(Duration(minutes: minute));
      health.observe('A', now.subtract(const Duration(minutes: 4)), now);
      expect(health.shouldRecover(now), minute == 3);
    }
    final restart = origin.add(const Duration(minutes: 3));
    health.connected(restart);
    for (var minute = 4; minute <= 11; minute++) {
      final now = origin.add(Duration(minutes: minute));
      health.observe('A', now, now);
      expect(health.shouldRecover(now), isFalse);
    }
    for (var minute = 15; minute <= 16; minute++) {
      final now = origin.add(Duration(minutes: minute));
      health.observe('A', now.subtract(const Duration(minutes: 4)), now);
      expect(health.shouldRecover(now), minute == 16);
    }
    expect(health.nextRecoveryAt, origin.add(const Duration(minutes: 21)));
  });

  test('duplicate old observation cannot masquerade as current time', () {
    final health = FdsnConnectionHealth(grace: Duration.zero);
    health.connected(origin);
    for (var seconds = 0; seconds <= 240; seconds += 15) {
      final now = origin.add(Duration(seconds: seconds));
      health.observe('A', origin, now);
      expect(health.shouldRecover(now), isFalse);
    }
    final now = origin.add(const Duration(seconds: 255));
    health.observe('A', origin, now);
    expect(health.shouldRecover(now), isTrue);
  });

  test(
    'fragmented INFO replies are skipped whole and do not publish motion',
    () async {
      final server = await ServerSocket.bind('127.0.0.1', 0);
      final sockets = <Socket>[];
      final commands = <String>[];
      final received = Completer<void>();
      final service = FdsnMotionService.forTesting(
        streams: [
          FdsnSeedLinkStream(
            source: 'EarthScope',
            host: '127.0.0.1',
            port: server.port,
            network: 'XX',
            station: 'AAA',
            selector: 'BH?.D',
          ),
        ],
        responseClientFactory: () =>
            MockClient((_) async => http.Response('', 204)),
        watchdogInterval: const Duration(milliseconds: 10),
        heartbeatInterval: const Duration(milliseconds: 80),
        networkTimeout: const Duration(milliseconds: 500),
      );
      var published = 0;
      final subscription = service.sampleStream.listen((_) {
        published++;
        if (!received.isCompleted) received.complete();
      });
      server.listen((socket) {
        sockets.add(socket);
        unawaited(socket.done.catchError((Object _) {}));
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) async {
              commands.add(line);
              if (line == 'INFO ID') {
                // Contains a waveform-looking header in XML: must not scan its payload.
                final info = infoPackets('<seedlink organization="SLABCDEF"/>');
                socket.add(info.sublist(0, 7));
                await Future<void>.delayed(const Duration(milliseconds: 10));
                socket.add(info.sublist(7, 130));
                await Future<void>.delayed(const Duration(milliseconds: 10));
                socket.add([
                  ...info.sublist(130),
                  ...dataPacket('AAA', DateTime.now().toUtc()),
                ]);
              } else if (line != 'END') {
                socket.add(ascii.encode('OK\r\n'));
              }
            }, onError: (_) {});
      });
      try {
        service.connectProvidedStreamsForTesting();
        await received.future.timeout(const Duration(seconds: 3));
        final diag = service.connectionDiagnostics.single;
        expect(commands.where((c) => c == 'INFO ID').length, 1);
        expect(diag['heartbeatsSent'], 1);
        expect(diag['heartbeatReplies'], 1);
        expect(diag['packets'], 1);
        expect(published, 1);
        expect(diag['connectAttempts'], 1);
      } finally {
        service.dispose();
        await subscription.cancel();
        for (final socket in sockets) {
          socket.destroy();
        }
        await server.close();
      }
    },
  );

  test(
    'continuous stale traffic triggers bare DATA recovery, not resume',
    () async {
      final server = await ServerSocket.bind('127.0.0.1', 0);
      final sockets = <Socket>[];
      final timers = <Timer>[];
      final commands = <String>[];
      final ready = Completer<void>();
      var sessions = 0;
      server.listen((socket) {
        sockets.add(socket);
        unawaited(socket.done.catchError((Object _) {}));
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              if (line == 'END') {
                sessions++;
                if (sessions == 1) {
                  socket.add(
                    dataPacket(
                      'AAA',
                      DateTime.now().toUtc().subtract(
                        const Duration(seconds: 179),
                      ),
                    ),
                  );
                  // Same station then sends genuinely stale observations.
                  timers.add(
                    Timer.periodic(const Duration(milliseconds: 15), (_) {
                      socket.add(
                        dataPacket(
                          'AAA',
                          DateTime.now().toUtc().subtract(
                            const Duration(minutes: 5),
                          ),
                        ),
                      );
                    }),
                  );
                } else {
                  for (final timer in timers) {
                    timer.cancel();
                  }
                  socket.add(dataPacket('AAA', DateTime.now().toUtc()));
                }
              } else {
                if (line.startsWith('DATA')) commands.add(line);
                socket.add(ascii.encode('OK\r\n'));
              }
            }, onError: (_) {});
      });
      final service = FdsnMotionService.forTesting(
        streams: [
          FdsnSeedLinkStream(
            source: 'GEOFON',
            host: '127.0.0.1',
            port: server.port,
            network: 'XX',
            station: 'AAA',
            selector: 'BH?.D',
          ),
        ],
        responseClientFactory: () =>
            MockClient((_) async => http.Response('', 204)),
        watchdogInterval: const Duration(milliseconds: 10),
        networkTimeout: const Duration(seconds: 10),
        reconnectDelay: const Duration(milliseconds: 25),
        healthFactory: () => FdsnConnectionHealth(
          grace: Duration.zero,
          sustain: const Duration(milliseconds: 70),
          cooldown: const Duration(seconds: 5),
        ),
      );
      final subscription = service.sampleStream.listen((_) {
        if (sessions == 2 && !ready.isCompleted) ready.complete();
      });
      try {
        service.connectProvidedStreamsForTesting();
        await ready.future.timeout(const Duration(seconds: 5));
        expect(commands, ['DATA', 'DATA']);
        expect(service.connectionDiagnostics.single['liveRecoveries'], 1);
        expect(
          service.connectionDiagnostics.single['lastCloseReason'],
          'sustained observation lag',
        );
      } finally {
        for (final timer in timers) {
          timer.cancel();
        }
        service.dispose();
        await subscription.cancel();
        for (final socket in sockets) {
          socket.destroy();
        }
        await server.close();
      }
    },
  );
}
