import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_connection_health.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_motion_service_io.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_source_status.dart';
import 'package:flutterrhythmquake/widgets/map/global_station_status_row.dart';

import 'fdsn_connection_test.dart' show dataPacket;

void main() {
  final now = DateTime.utc(2026, 10, 3, 12);
  test('age buckets use original observations and station-weighted ratios', () {
    final status = FdsnSourceStatus.fromObservations(
      source: 'EarthScope',
      state: FdsnSourceConnectionState.streaming,
      now: now,
      observations: [
        now,
        now.subtract(const Duration(seconds: 30)),
        now.subtract(const Duration(seconds: 31)),
        now.subtract(const Duration(seconds: 180)),
        now.subtract(const Duration(seconds: 181)),
        null,
        now.add(const Duration(seconds: 1)),
      ],
    );
    expect(status.selected, 7);
    expect(status.timely, 2);
    expect(status.delayed, 2);
    expect(status.stale, 1);
    expect(status.missing, 2);
    expect(status.linked, 4);
    expect(status.delayScore, 4 / 7);
    final payload = ForegroundStationPayload.fdsnStatus([status]);
    expect(
      ForegroundStationPayload.decodeFdsnStatus(
        jsonDecode(jsonEncode(payload)),
      ),
      [status],
    );
    expect(
      FdsnSourceStatus.fromJson({...status.toJson(), 'selected': 999}),
      isNull,
    );
    expect(
      FdsnSourceStatus.fromJson({...status.toJson(), 'state': 'invented'}),
      isNull,
    );
  });

  test('one fast channel cannot make the whole source healthy', () {
    final health = FdsnConnectionHealth()..connected(now);
    for (var i = 0; i < 1000; i++) {
      health.observe('XX.A', now, now);
    }
    health.observe('XX.B', now.subtract(const Duration(minutes: 4)), now);
    health.observe('XX.B', now.subtract(const Duration(minutes: 5)), now);
    final status = FdsnSourceStatus.fromObservations(
      source: 'GeoNet',
      state: FdsnSourceConnectionState.streaming,
      now: now,
      observations: [
        health.observationFor('XX.A'),
        health.observationFor('XX.B'),
      ],
    );
    expect(status.timely, 1);
    expect(status.stale, 1);
    expect(status.delayScore, .5);
    expect(
      health.observationFor('XX.B'),
      now.subtract(const Duration(minutes: 4)),
    );
  });

  test(
    'colors distinguish transport failure, startup and delay distribution',
    () {
      FdsnSourceStatus s(
        int delayed,
        int stale, {
        FdsnSourceConnectionState state = FdsnSourceConnectionState.streaming,
      }) => FdsnSourceStatus(
        source: 'EarthScope',
        state: state,
        selected: 100,
        timely: 100 - delayed - stale,
        delayed: delayed,
        stale: stale,
      );
      expect(globalStationStatusColor(s(0, 0)), const Color(0xFF45D483));
      expect(globalStationStatusColor(s(0, 100)), const Color(0xFFFF5252));
      expect(
        globalStationStatusColor(
          s(0, 0, state: FdsnSourceConnectionState.failed),
        ),
        const Color(0xFFFF5252),
      );
      expect(s(0, 0, state: FdsnSourceConnectionState.failed).linked, 0);
      expect(
        globalStationStatusColor(
          s(0, 0, state: FdsnSourceConnectionState.connecting),
        ),
        const Color(0xFFFFD54F),
      );
      expect(
        globalStationStatusColor(
          s(0, 0, state: FdsnSourceConnectionState.idle),
        ),
        const Color(0xFFAAAAAA),
      );
      expect(
        globalStationStatusColor(s(50, 0)),
        isNot(globalStationStatusColor(s(0, 0))),
      );
      expect(
        globalStationStatusColor(s(0, 75)),
        isNot(globalStationStatusColor(s(50, 0))),
      );
    },
  );

  test(
    'actual receiver summaries include stale records, no-data stations and close',
    () async {
      // Isolated protocol fixtures only; no production source is used.
      final server = await ServerSocket.bind('127.0.0.1', 0);
      final sockets = <Socket>[];
      server.listen((socket) {
        sockets.add(socket);
        unawaited(socket.done.catchError((Object _) {}));
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              if (line == 'END') {
                final time = DateTime.now().toUtc();
                for (var i = 0; i < 10; i++) {
                  socket.add(
                    dataPacket(
                      'AAA',
                      time.subtract(const Duration(seconds: 5)),
                    ),
                  );
                }
                socket.add(
                  dataPacket('BBB', time.subtract(const Duration(seconds: 60))),
                );
                socket.add(
                  dataPacket(
                    'CCC',
                    time.subtract(const Duration(seconds: 240)),
                  ),
                );
              } else {
                socket.add(ascii.encode('OK\r\n'));
              }
            }, onError: (_) {});
      });
      final service = FdsnMotionService.forTesting(
        streams: [
          for (final code in ['AAA', 'BBB', 'CCC', 'DDD'])
            FdsnSeedLinkStream(
              source: 'EarthScope',
              host: '127.0.0.1',
              port: server.port,
              network: 'XX',
              station: code,
              selector: 'BH?.D',
            ),
        ],
        responseClientFactory: () =>
            MockClient((_) async => http.Response('', 204)),
      );
      Future<void> until(bool Function() ready) async {
        final limit = DateTime.now().add(const Duration(seconds: 3));
        while (!ready() && DateTime.now().isBefore(limit)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(ready(), isTrue);
      }

      try {
        service.connectProvidedStreamsForTesting();
        expect(
          service.sourceStatusesNotifier.value.single.state,
          FdsnSourceConnectionState.connecting,
        );
        await until(() => service.collectSourceStatuses().single.stale == 1);
        final status = service.collectSourceStatuses().single;
        expect(status.selected, 4);
        expect(status.linked, 2);
        expect(status.timely, 1);
        expect(status.delayed, 1);
        expect(status.stale, 1);
        expect(status.missing, 1);
        expect(status.delayScore, .625);
        final later = service
            .collectSourceStatuses(
              now: DateTime.now().add(const Duration(minutes: 4)),
            )
            .single;
        expect(later.linked, 0);
        expect(later.stale, 3);
        sockets.single.destroy();
        await until(
          () =>
              service.collectSourceStatuses().single.state ==
              FdsnSourceConnectionState.failed,
        );
        expect(service.collectSourceStatuses().single.linked, 0);
        service.disconnect();
        expect(service.sourceStatusesNotifier.value, isEmpty);
        expect(service.collectSourceStatuses(), isEmpty);
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
    'connection failure is published without any waveform arrival',
    () async {
      final reserved = await ServerSocket.bind('127.0.0.1', 0);
      final port = reserved.port;
      await reserved.close();
      final service = FdsnMotionService.forTesting(
        streams: [
          FdsnSeedLinkStream(
            source: 'GeoNet',
            host: '127.0.0.1',
            port: port,
            network: 'XX',
            station: 'AAA',
            selector: 'BH?.D',
          ),
        ],
      );
      try {
        service.connectProvidedStreamsForTesting();
        final deadline = DateTime.now().add(const Duration(seconds: 7));
        while (service.sourceStatusesNotifier.value.single.state !=
                FdsnSourceConnectionState.failed &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        final status = service.sourceStatusesNotifier.value.single;
        expect(status.source, 'GeoNet');
        expect(status.state, FdsnSourceConnectionState.failed);
        expect(status.linked, 0);
        expect(status.selected, 1);
        service.disconnect();
        expect(service.sourceStatusesNotifier.value, isEmpty);
      } finally {
        service.dispose();
      }
    },
  );
}
