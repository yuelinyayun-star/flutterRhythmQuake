import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_metadata_routing.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_motion_service_io.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_seedlink_info.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_station_service.dart';

// Protocol fixtures only; no synthetic records enter an application data source.
List<int> infoPackets(String xml) {
  final text = utf8.encode(xml);
  final bytes = <int>[];
  for (var offset = 0; offset < text.length; offset += 448) {
    final count = (text.length - offset).clamp(0, 448);
    final packet = Uint8List(520);
    packet.setRange(
      0,
      8,
      ascii.encode(offset + count == text.length ? 'SLINFO  ' : 'SLINFO *'),
    );
    final data = ByteData.sublistView(packet, 8);
    data.setUint16(20, 2026);
    data.setUint16(30, count);
    data.setUint16(44, 64);
    packet.setRange(72, 72 + count, text, offset);
    bytes.addAll(packet);
  }
  return bytes;
}

String stationXml(
  String name,
  DateTime time, {
  String family = 'BH',
  String location = '',
}) =>
    '<station name="$name" network="XX"><stream location="$location" seedname="${family}Z" type="D" end_time="${time.toIso8601String()}"/></station>';

Uint8List dataPacket(String station, DateTime time) {
  final record = File(
    'test/fixtures/fdsn_codec/INT32_be.mseed',
  ).readAsBytesSync().sublist(0, 512);
  record.setRange(8, 13, ascii.encode(station.padRight(5)));
  record.setRange(13, 20, ascii.encode('  BHZXX'));
  final header = ByteData.sublistView(record);
  header.setUint16(20, time.year);
  header.setUint16(22, time.difference(DateTime.utc(time.year)).inDays + 1);
  record[24] = time.hour;
  record[25] = time.minute;
  record[26] = time.second;
  header.setUint16(28, 0);
  return Uint8List.fromList([...ascii.encode('SL000001'), ...record]);
}

void main() {
  test('stale traffic is not fresh data or a network timeout', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    final streaming = Completer<void>();
    Timer? sender;
    server.listen((socket) {
      sockets.add(socket);
      unawaited(socket.done.catchError((Object _) {}));
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line == 'END') {
              sender = Timer.periodic(const Duration(milliseconds: 20), (_) {
                socket.add(
                  dataPacket(
                    'AAA',
                    DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
                  ),
                );
              });
              if (!streaming.isCompleted) streaming.complete();
            } else {
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
      responseClientFactory: () =>
          MockClient((_) async => http.Response('', 204)),
      watchdogInterval: const Duration(milliseconds: 25),
      networkTimeout: const Duration(milliseconds: 150),
    );
    var published = 0;
    final sub = service.sampleStream.listen((_) => published++);
    try {
      service.connect(stationLimit: 1, enabledSources: {'EarthScope'});
      await streaming.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(service.connectionDiagnostics.single['connectAttempts'], 1);
      expect(service.connectionDiagnostics.single['connected'], isTrue);
      expect(service.connectionDiagnostics.single['lastValidAgeSeconds'], -1);
      expect(service.connectionDiagnostics.single['stale'], greaterThan(0));
      expect(service.linkedStationCountNotifier.value, 0);
      expect(published, 0);
      sender!.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(
        service.connectionDiagnostics.single['lastCloseReason'],
        'network receive timeout',
      );
      expect(service.connectionDiagnostics.single['socketOpen'], isFalse);
    } finally {
      sender?.cancel();
      service.dispose();
      await sub.cancel();
      for (final socket in sockets) {
        socket.destroy();
      }
      await server.close();
    }
  });
  test(
    'EarthScope peer reconnect requests live data instead of old replay',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final commands = <String>[];
      final recovered = Completer<void>();
      var sessions = 0;
      late DateTime originalTime;
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
                  originalTime = DateTime.now().toUtc().subtract(
                    const Duration(seconds: 178),
                  );
                }
                socket.add(
                  dataPacket(
                    'AAA',
                    sessions == 1
                        ? originalTime
                        : DateTime.now().toUtc().subtract(
                            const Duration(seconds: 1),
                          ),
                  ),
                );
                if (sessions == 1) {
                  Timer(const Duration(milliseconds: 25), socket.destroy);
                }
              } else if (line == 'INFO STREAMS') {
                socket.add(
                  infoPackets(
                    '<seedlink>${stationXml('AAA', DateTime.now().toUtc())}</seedlink>',
                  ),
                );
              } else {
                if (line.startsWith('DATA')) commands.add(line);
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
        responseClientFactory: () =>
            MockClient((_) async => http.Response('', 204)),
        watchdogInterval: const Duration(milliseconds: 25),
        networkTimeout: const Duration(seconds: 10),
        reconnectDelay: const Duration(milliseconds: 25),
      );
      final sub = service.sampleStream.listen((_) {
        if (sessions == 2 && !recovered.isCompleted) recovered.complete();
      });
      try {
        service.connect(enabledSources: {'EarthScope'});
        await recovered.future.timeout(const Duration(seconds: 5));
        expect(commands, ['DATA', 'DATA']);
        expect(
          service.connectionDiagnostics.single['lastCloseReason'],
          'peer closed',
        );
        expect(service.linkedStationCountNotifier.value, 1);
      } finally {
        service.dispose();
        await sub.cancel();
        for (final socket in sockets) {
          socket.destroy();
        }
        await server.close();
      }
    },
  );
  test(
    'observation expiry removes fresh stations without disconnecting transport',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final commands = <String>[];
      final recovered = Completer<void>();
      final timers = <Timer>[];
      var sessions = 0;
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
                    '<seedlink>${stationXml('AAA', DateTime.now().toUtc())}</seedlink>',
                  ),
                );
              } else if (line == 'END') {
                sessions++;
                socket.add(
                  dataPacket(
                    'AAA',
                    DateTime.now().toUtc().subtract(
                      Duration(seconds: sessions == 1 ? 178 : 1),
                    ),
                  ),
                );
                timers.add(
                  Timer(const Duration(seconds: 3), () {
                    socket.add(
                      dataPacket(
                        'AAA',
                        DateTime.now().toUtc().subtract(
                          const Duration(seconds: 1),
                        ),
                      ),
                    );
                  }),
                );
              } else {
                if (line.startsWith('DATA')) commands.add(line);
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
        responseClientFactory: () =>
            MockClient((_) async => http.Response('', 204)),
        watchdogInterval: const Duration(milliseconds: 25),
        networkTimeout: const Duration(seconds: 10),
        reconnectDelay: const Duration(milliseconds: 25),
      );
      final sub = service.sampleStream.listen((sample) {
        if (DateTime.now().toUtc().difference(sample.timestamp).inSeconds < 3 &&
            !recovered.isCompleted) {
          recovered.complete();
        }
      });
      var expired = false;
      void countChanged() {
        if (sessions > 0 && service.linkedStationCountNotifier.value == 0) {
          expired = true;
        }
      }

      service.linkedStationCountNotifier.addListener(countChanged);
      try {
        service.connect(enabledSources: {'EarthScope'});
        await recovered.future.timeout(const Duration(seconds: 5));
        expect(commands, ['DATA']);
        expect(expired, isTrue);
        expect(sessions, 1);
        expect(service.connectionDiagnostics.single['lastCloseReason'], '');
        expect(service.linkedStationCountNotifier.value, 1);
      } finally {
        service.linkedStationCountNotifier.removeListener(countChanged);
        for (final timer in timers) {
          timer.cancel();
        }
        service.dispose();
        await sub.cancel();
        for (final socket in sockets) {
          socket.destroy();
        }
        await server.close();
      }
    },
  );
  test(
    '3000 subscriptions recover after peer closes during station growth',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final recovered = Completer<void>();
      var sessions = 0;
      final streams = [
        for (var i = 0; i < 3000; i++)
          FdsnSeedLinkStream(
            source: 'EarthScope',
            host: '127.0.0.1',
            port: server.port,
            network: 'XX',
            station: 'S${i.toString().padLeft(4, '0')}',
            selector: 'BH?.D',
          ),
      ];
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
                final bytes = BytesBuilder(copy: false);
                final now = DateTime.now().toUtc().subtract(
                  const Duration(seconds: 1),
                );
                for (final s in streams.take(sessions == 1 ? 2500 : 3000)) {
                  bytes.add(dataPacket(s.station, now));
                }
                socket.add(bytes.takeBytes());
              } else {
                socket.add(ascii.encode('OK\r\n'));
              }
            }, onError: (_) {});
      });
      final service = FdsnMotionService.forTesting(
        streams: streams,
        useChannelCatalog: true,
        responseClientFactory: () =>
            MockClient((_) async => http.Response('', 204)),
        reconnectDelay: const Duration(milliseconds: 25),
      );
      var dropped = false;
      void countChanged() {
        final count = service.linkedStationCountNotifier.value;
        if (!dropped && count == 2500) {
          dropped = true;
          // Same settings (e.g. a camera-only notification) must not restart it.
          service.connect(stationLimit: 3000, enabledSources: {'EarthScope'});
          sockets.last.destroy();
        }
        if (dropped &&
            sessions >= 2 &&
            count == 3000 &&
            !recovered.isCompleted) {
          recovered.complete();
        }
      }

      service.linkedStationCountNotifier.addListener(countChanged);
      try {
        service.connect(stationLimit: 3000, enabledSources: {'EarthScope'});
        await recovered.future.timeout(const Duration(seconds: 15));
        expect(sessions, 2);
        expect(service.connectionDiagnostics.single['connectAttempts'], 2);
        expect(service.linkedStationCountNotifier.value, 3000);
      } finally {
        service.linkedStationCountNotifier.removeListener(countChanged);
        service.dispose();
        for (final s in sockets) {
          s.destroy();
        }
        await server.close();
      }
    },
  );
  test(
    'stalled resume returns to live DATA and rebuilds linked stations',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final commands = <String>[];
      final recovered = Completer<void>();
      var ended = 0;
      server.listen((socket) {
        sockets.add(socket);
        unawaited(socket.done.catchError((Object _) {}));
        var resume = false;
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              if (line == 'INFO STREAMS') {
                socket.add(
                  infoPackets(
                    '<seedlink>${stationXml('AAA', DateTime.now().toUtc())}</seedlink>',
                  ),
                );
              } else if (line == 'END') {
                ended++;
                if (ended == 1 || !resume) {
                  socket.add(
                    dataPacket(
                      'AAA',
                      DateTime.now().toUtc().subtract(
                        const Duration(seconds: 1),
                      ),
                    ),
                  );
                  if (ended == 1) {
                    Timer(const Duration(milliseconds: 20), socket.destroy);
                  }
                } else {
                  socket.add(
                    dataPacket(
                      'AAA',
                      DateTime.now().toUtc().subtract(
                        const Duration(minutes: 5),
                      ),
                    ),
                  );
                }
              } else {
                if (line.startsWith('DATA')) {
                  commands.add(line);
                  resume = line != 'DATA';
                }
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
        responseClientFactory: () =>
            MockClient((_) async => http.Response('', 204)),
        watchdogInterval: const Duration(milliseconds: 25),
        networkTimeout: const Duration(milliseconds: 200),
        liveReconnectSources: const {},
        reconnectDelay: const Duration(milliseconds: 25),
      );
      final sub = service.sampleStream.listen((sample) {
        if (ended >= 3 && !recovered.isCompleted) recovered.complete();
      });
      try {
        service.connect(enabledSources: {'EarthScope'});
        await recovered.future.timeout(const Duration(seconds: 2));
        expect(commands.take(3), ['DATA', 'DATA 000002', 'DATA']);
        expect(service.linkedStationCountNotifier.value, 1);
      } finally {
        service.dispose();
        await sub.cancel();
        for (final socket in sockets) {
          socket.destroy();
        }
        await server.close();
      }
    },
  );
  test(
    'linked station expires by observation time, not packet arrival',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final received = Completer<void>();
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
                    '<seedlink>${stationXml('AAA', DateTime.now().toUtc())}</seedlink>',
                  ),
                );
              } else if (line == 'END') {
                socket.add(
                  dataPacket(
                    'AAA',
                    DateTime.now().toUtc().subtract(
                      const Duration(seconds: 170),
                    ),
                  ),
                );
              } else {
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
        responseClientFactory: () =>
            MockClient((_) async => http.Response('', 204)),
      );
      final subscription = service.sampleStream.listen((s) {
        if (!received.isCompleted) received.complete();
      });
      try {
        service.connect(enabledSources: {'EarthScope'});
        await received.future.timeout(const Duration(seconds: 5));
        expect(service.linkedStationCountNotifier.value, 1);
        await Future<void>.delayed(const Duration(seconds: 16));
        expect(service.linkedStationCountNotifier.value, 0);
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
    'late overlapping provider preserves existing station subscriptions',
    () async {
      final first = await ServerSocket.bind('127.0.0.1', 0);
      final second = await ServerSocket.bind('127.0.0.2', 0);
      final sockets = <Socket>[];
      final firstReady = Completer<void>();
      final secondReady = Completer<void>();
      var firstFullSubscriptions = 0;
      void serve(ServerSocket server, bool isFirst) {
        server.listen((socket) {
          sockets.add(socket);
          unawaited(socket.done.catchError((Object _) {}));
          final selected = <String>[];
          socket
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((line) async {
                if (line == 'INFO STREAMS') {
                  if (!isFirst) await firstReady.future;
                  final names = isFirst
                      ? [
                          for (var i = 0; i < 20; i++)
                            'T${i.toString().padLeft(2, '0')}',
                        ]
                      : [
                          'T00',
                          'T01',
                          'T02',
                          'T03',
                          'T04',
                          'U00',
                          'U01',
                          'U02',
                        ];
                  socket.add(
                    infoPackets(
                      '<seedlink>${names.map((s) => stationXml(s, DateTime.now().toUtc())).join()}</seedlink>',
                    ),
                  );
                } else if (line == 'END') {
                  for (final s in selected) {
                    socket.add(
                      dataPacket(
                        s,
                        DateTime.now().toUtc().subtract(
                          const Duration(seconds: 1),
                        ),
                      ),
                    );
                  }
                  if (isFirst && selected.length == 20) {
                    firstFullSubscriptions++;
                    if (!firstReady.isCompleted) firstReady.complete();
                  }
                  if (!isFirst &&
                      selected.length >= 3 &&
                      !secondReady.isCompleted) {
                    secondReady.complete();
                  }
                } else {
                  if (line.startsWith('STATION ')) {
                    selected.add(line.split(' ')[1]);
                  }
                  socket.add(ascii.encode('OK\r\n'));
                }
              }, onError: (_) {});
        });
      }

      serve(first, true);
      serve(second, false);
      final service = FdsnMotionService.forTesting(
        streams: [
          FdsnSeedLinkStream(
            source: 'EarthScope',
            host: '127.0.0.1',
            port: first.port,
            network: 'XX',
            station: 'T00',
            selector: 'BH?.D',
          ),
          FdsnSeedLinkStream(
            source: 'GEOFON',
            host: '127.0.0.2',
            port: second.port,
            network: 'XX',
            station: 'U00',
            selector: 'BH?.D',
          ),
        ],
        responseClientFactory: () =>
            MockClient((_) async => http.Response('', 204)),
      );
      try {
        service.connect(stationLimit: 100);
        await secondReady.future.timeout(const Duration(seconds: 8));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final diagnostics = service.connectionDiagnostics;
        expect(
          diagnostics.firstWhere((c) => c['host'] == '127.0.0.1')['selected'],
          20,
        );
        expect(
          diagnostics.firstWhere((c) => c['host'] == '127.0.0.2')['selected'],
          3,
        );
        expect(service.linkedStationCountNotifier.value, 23);
        expect(firstFullSubscriptions, 1);
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
  test(
    'official routing is shared per network and failed lookups are cooled down',
    () async {
      var calls = 0;
      final routing = FdsnMetadataRouting();
      final client = MockClient((request) async {
        calls++;
        if (request.url.queryParameters['network'] == 'XX') {
          return http.Response('', 503);
        }
        return http.Response(
          'https://eida.bgr.de/fdsnws/station/1/query?net=GR&sta=FUR\n'
          'https://eida.bgr.de/fdsnws/station/1/query?net=GR&sta=GRC2\n',
          200,
        );
      });
      final routes = await Future.wait([
        routing.resolve(client, 'GR'),
        routing.resolve(client, 'GR'),
      ]);
      expect(calls, 1);
      expect(routes.first.single.host, 'eida.bgr.de');
      await routing.resolve(client, 'XX');
      await routing.resolve(client, 'XX');
      expect(calls, 2);
      client.close();
    },
  );

  test(
    'relay metadata is retained through refresh without relabeling the source',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        r.response.write('XX|AAA|30|105|0|Test|2020-01-01T00:00:00|');
        await r.response.close();
      });
      final service = FdsnStationService(
        endpoint: FdsnStationEndpoint(
          name: 'GEOFON',
          stationUrl: 'http://127.0.0.1:${server.port}/query',
        ),
      );
      try {
        await service.start();
        const station = FdsnStation(
          network: 'GR',
          station: 'FUR',
          location: '',
          coordinate: LatLng(48.1639, 11.2768),
          source: 'GEOFON',
        );
        service.acceptChannelStation(station);
        service.acceptChannelStation(station);
        await service.refresh();
        expect(service.stations.length, 2);
        expect(service.stations.last.source, 'GEOFON');
        expect(service.stations.last.coordinate, station.coordinate);
      } finally {
        service.dispose();
        await server.close(force: true);
      }
    },
  );

  test(
    'resume-enabled source reconnects with the next per-station sequence',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final resumed = Completer<String>();
      var streamingConnections = 0;
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
                    '<seedlink>${stationXml('AAA', DateTime.now().toUtc())}</seedlink>',
                  ),
                );
              } else if (line == 'END') {
                streamingConnections++;
                socket.add(
                  dataPacket(
                    'AAA',
                    DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
                  ),
                );
                if (streamingConnections == 1) {
                  Timer(const Duration(milliseconds: 100), socket.destroy);
                }
              } else {
                if (line.startsWith('DATA ') && !resumed.isCompleted) {
                  resumed.complete(line);
                }
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
        responseClientFactory: () =>
            MockClient((_) async => http.Response('', 204)),
        liveReconnectSources: const {},
      );
      try {
        service.connect(enabledSources: {'EarthScope'});
        expect(
          await resumed.future.timeout(const Duration(seconds: 15)),
          'DATA 000002',
        );
      } finally {
        service.dispose();
        for (final socket in sockets) {
          socket.destroy();
        }
        await server.close();
      }
    },
  );

  test('invalid record time is rejected, never replaced with local time', () {
    final packet = dataPacket('AAA', DateTime.now().toUtc());
    final record = Uint8List.sublistView(packet, 8);
    ByteData.sublistView(record).setUint16(22, 0);
    expect(decodeFdsnRecordForTest(record), isNull);
  });

  test(
    'TCP and rejected subscriptions do not count as linked stations',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final sent = Completer<void>();
      server.listen((socket) {
        sockets.add(socket);
        unawaited(socket.done.catchError((Object _) {}));
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              if (line == 'INFO STREAMS') {
                socket.add(infoPackets('<seedlink></seedlink>'));
              } else if (line == 'END') {
                socket.add(
                  dataPacket(
                    'AAA',
                    DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
                  ),
                );
                if (!sent.isCompleted) sent.complete();
              } else {
                socket.add(ascii.encode('ERROR\r\n'));
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
            selector: 'BH?',
          ),
        ],
      );
      try {
        service.connect(enabledSources: {'EarthScope'});
        await sent.future.timeout(const Duration(seconds: 4));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(service.linkedStationCountNotifier.value, 0);
        expect(service.dataTimeNotifier.value, isNull);
      } finally {
        service.dispose();
        for (final socket in sockets) {
          socket.destroy();
        }
        await server.close();
      }
    },
  );

  test(
    'INFO supports split packets, UTF8, complete stations and fresh family selection',
    () {
      final now = DateTime.utc(2026, 9, 9, 12);
      final old = now.subtract(const Duration(days: 2));
      final xml =
          '<seedlink organization="测站テスト">'
          '<station name="AAA" network="XX">'
          '<stream seedname="HNZ" type="D" end_time="${old.toIso8601String()}"/>'
          '<stream location="00" seedname="BHZ" type="D" end_time="${now.toIso8601String()}"/>'
          '</station>${stationXml('OLD', old)}${stationXml('BBB', now, family: 'HH')}'
          '<station name="CCC" network="XX"><stream seedname="BHZ" type="D" end_time="2026/09/09 11:59:59.5683"/></station></seedlink>';
      final info = FdsnSeedLinkInfo(now: now, limit: 100);
      final packets = infoPackets(xml);
      for (var i = 0; i < packets.length; i += 17) {
        info.addBytes(packets.sublist(i, (i + 17).clamp(0, packets.length)));
      }
      expect(info.complete, isTrue);
      expect(info.stations.map((s) => s.station), ['AAA', 'BBB', 'CCC']);
      expect(info.stations.first.selector, '00BH?.D');
      expect(info.stations[1].selector, 'HH?.D');
      expect(info.stations[2].selector, 'BH?.D');
      final limited = FdsnSeedLinkInfo(now: now, limit: 1)..addBytes(packets);
      expect(limited.stations.length, 1);
      expect(limited.enough, isTrue);
    },
  );

  test(
    'summary clock never rewrites records, regresses, or accepts future time',
    () {
      final service = FdsnMotionService.forTesting(streams: []);
      final t = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
      service.recordDataTime(t);
      service.recordDataTime(t.subtract(const Duration(seconds: 30)));
      expect(service.dataTimeNotifier.value, t);
      service.recordDataTime(
        DateTime.now().toUtc().add(const Duration(days: 1)),
      );
      expect(service.dataTimeNotifier.value, t);
      service.recordDataTime(t.add(const Duration(seconds: 10)));
      expect(
        service.dataTimeNotifier.value,
        t.add(const Duration(seconds: 10)),
      );
      service.disconnect();
      expect(service.dataTimeNotifier.value, isNull);
      service.dispose();
    },
  );

  for (final bulk in [false, true]) {
    test('220 subscriptions survive metadata wait (bulk=$bulk)', () async {
      final now = DateTime.now().toUtc().subtract(const Duration(seconds: 2));
      final names = [
        for (var i = 0; i < 220; i++) 'T${i.toString().padLeft(3, '0')}',
      ];
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final gate = Completer<void>();
      final sent = Completer<void>();
      var dataCommands = 0;
      server.listen((socket) {
        sockets.add(socket);
        unawaited(socket.done.catchError((Object _) {}));
        final selected = <String>[];
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((command) {
              if (command == 'INFO STREAMS') {
                socket.add(
                  infoPackets(
                    '<seedlink>${names.map((n) => stationXml(n, now)).join()}</seedlink>',
                  ),
                );
              } else if (command == 'END') {
                for (var i = 0; i < selected.length; i++) {
                  socket.add(
                    dataPacket(
                      selected[i],
                      now.subtract(Duration(seconds: i % 20)),
                    ),
                  );
                }
                if (selected.length == names.length && !sent.isCompleted) {
                  sent.complete();
                }
              } else {
                if (command.startsWith('STATION ')) {
                  selected.add(command.split(' ')[1]);
                }
                if (command == 'DATA') dataCommands++;
                socket.add(ascii.encode('OK\r\n'));
              }
            }, onError: (_) {});
      });
      final service = FdsnMotionService.forTesting(
        useChannelCatalog: bulk,
        streams: [
          FdsnSeedLinkStream(
            source: 'EarthScope',
            host: '127.0.0.1',
            port: server.port,
            network: 'XX',
            station: names.first,
            selector: 'BH?',
          ),
        ],
        responseClientFactory: () => MockClient((request) async {
          await gate.future;
          final q = request.url.queryParameters;
          return http.Response(
            (bulk ? names : [q['station']!])
                .map(
                  (name) =>
                      'XX|$name||BHZ|30|105|0|0|0|0|test|1000|1|M/S|100|2020-01-01T00:00:00|',
                )
                .join('\n'),
            200,
          );
        }),
      );
      final measured = <String>{};
      final done = Completer<void>();
      final sub = service.sampleStream.listen((s) {
        if (s.hasMeasurement) measured.add(s.code);
        if (measured.length == names.length && !done.isCompleted) {
          done.complete();
        }
      });
      try {
        service.connect(stationLimit: 300, enabledSources: {'EarthScope'});
        await sent.future.timeout(const Duration(seconds: 8));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(dataCommands, inInclusiveRange(names.length, names.length + 1));
        expect(
          service.linkedStationCountNotifier.value,
          lessThanOrEqualTo(220),
        );
        if (bulk) {
          expect(
            service.linkedStationCountNotifier.value,
            220,
            reason: 'metadata must not block receipt from other stations',
          );
          expect(measured, isEmpty);
        }
        gate.complete();
        await done.future.timeout(const Duration(seconds: 10));
        expect(service.linkedStationCountNotifier.value, 220);
        expect(measured.length, 220);
        expect(
          service.dataTimeNotifier.value!.difference(now).abs(),
          lessThan(const Duration(seconds: 1)),
        );
      } finally {
        if (!gate.isCompleted) gate.complete();
        service.disconnect();
        await sub.cancel();
        for (final socket in sockets) {
          socket.destroy();
        }
        await server.close();
        service.dispose();
      }
    });
  }

  test(
    'station metadata retries failed first load rather than waiting 12 hours',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((r) async {
        requests++;
        if (requests == 1) {
          r.response.statusCode = 503;
        } else {
          r.response.write('XX|AAA|30|105|0|Test Station|2020-01-01T00:00:00|');
        }
        await r.response.close();
      });
      final service = FdsnStationService(
        endpoint: FdsnStationEndpoint(
          name: 'Test',
          stationUrl: 'http://127.0.0.1:${server.port}/query',
        ),
        retryInterval: const Duration(milliseconds: 50),
      );
      try {
        final result = service.stationStream.first;
        await service.start();
        final stations = await result.timeout(const Duration(seconds: 5));
        expect(requests, 2);
        expect(stations.single.startTime!.isUtc, isTrue);
      } finally {
        service.dispose();
        await server.close(force: true);
      }
    },
  );
}
