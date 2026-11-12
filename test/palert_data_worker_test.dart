import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/palert_service.dart';
import 'package:flutterrhythmquake/services/station_history_capture.dart';
import 'package:flutterrhythmquake/models/station_history_frame.dart';
import 'package:flutterrhythmquake/services/debug/station_archive_storage.dart';
import 'package:flutterrhythmquake/services/debug/station_json_archive.dart';
import 'support/palert_level_history_before_20261015.dart';

const _fixture = 'test/fixtures/palert_cadence_20261014';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'real earthquake frames commit confirmed detection with their observations',
    () async {
      const fixture = 'test/fixtures/palert_cwa_1150077_20261017';
      final manifest =
          jsonDecode(
                File('$fixture/manifest.json').readAsStringSync(encoding: utf8),
              )
              as List;
      final saved = <StationHistoryFrame>[];
      for (final entry in manifest) {
        final stored = jsonDecode(
          File('$fixture/${entry['file']}').readAsStringSync(encoding: utf8),
        );
        saved.addAll(
          StationJsonArchive.decode(
            StationArchiveStorage.decode(stored['value']),
          ),
        );
      }
      saved.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
      var frameIndex = 0;
      final metadata = saved.first.originalJson!['metadata'];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serving = server.listen((request) async {
        final query = jsonDecode(await utf8.decoder.bind(request).join());
        final raw = query['query'].toString().contains('stationList')
            ? metadata
            : saved[frameIndex].originalJson!['data'];
        // JSON serialization transports the complete archived response, without
        // changing source time, PGA, PGV or metadata.
        request.response.add(utf8.encode(jsonEncode(raw)));
        await request.response.close();
      });
      final service = PAlertService.workerForTesting(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/graphql/'),
        pollInterval: const Duration(milliseconds: 50),
      );
      var confirmedFrames = 0;
      var detectionChanges = 0;
      final subscription = service.stationStream.listen((stations) {
        if (service.detectionSnapshot.detectedStations.isEmpty) return;
        confirmedFrames++;
        final ids = stations.map((s) => s.id).toSet();
        expect(
          service.detectionSnapshot.detectedStations.every(
            (s) => ids.contains(s.code),
          ),
          isTrue,
        );
        expect(
          service.historySnapshot()['detectedStationIds'],
          service.detectionSnapshot.detectedStations
              .map((s) => s.code)
              .toList(),
        );
      });
      service.onDetectionChanged = (_) => detectionChanges++;
      try {
        service.start();
        for (var i = 0; i < saved.length; i++) {
          frameIndex = i;
          final raw = saved[i].originalJson!['data'];
          final time = PAlertService.parseTimestamp(
            raw['data']['pga']['timestamp'],
          )!;
          final deadline = DateTime.now().add(const Duration(seconds: 20));
          while (service.dataTimeNotifier.value != time) {
            if (DateTime.now().isAfter(deadline)) {
              fail('earthquake frame timeout at $i');
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          await Future<void>.delayed(Duration.zero);
        }
        expect(confirmedFrames, greaterThan(0));
        expect(detectionChanges, greaterThan(0));
        expect(service.processingIsolateName, 'palert-data-processing');
      } finally {
        service.stop();
        await subscription.cancel();
        await serving.cancel();
        await server.close(force: true);
      }
    },
  );

  test(
    'original HTTP bytes are processed off UI, archived and restart safely',
    () async {
      final metadataBytes = File(
        '$_fixture/station-list.json',
      ).readAsBytesSync();
      final metadata = jsonDecode(utf8.decode(metadataBytes));
      final rawFrames = [
        for (var i = 0; i < 12; i++)
          File(
            '$_fixture/${i.toString().padLeft(2, '0')}.json',
          ).readAsBytesSync(),
      ];
      var metadataRequests = 0;
      var frameIndex = 0;
      var failRequests = false;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serving = server.listen((request) async {
        final query = jsonDecode(await utf8.decoder.bind(request).join());
        if (query['query'].toString().contains('stationList')) {
          metadataRequests++;
          request.response.add(metadataBytes);
        } else if (failRequests) {
          request.response.statusCode = 503;
        } else {
          request.response.add(rawFrames[frameIndex]);
        }
        await request.response.close();
      });
      final service = PAlertService.workerForTesting(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/graphql/'),
        pollInterval: const Duration(milliseconds: 50),
      );
      final frames = <StationHistoryFrame>[];
      final capture = StationHistoryCapture.instance;
      capture.addListener(frames.add);
      final statuses = <bool>[];
      service.onStatusChanged = statuses.add;
      final reference = DartPAlertLevelHistoryReference();
      final ids = [
        for (final row in metadata['data']['stationList']['staInfos'])
          row['station'].toString().trim(),
      ];
      reference.setStations(ids);
      Future<void> waitUntil(bool Function() predicate) async {
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (!predicate()) {
          if (DateTime.now().isAfter(deadline)) fail('worker response timeout');
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      try {
        service.start();
        for (var i = 0; i < rawFrames.length; i++) {
          frameIndex = i;
          final raw = jsonDecode(utf8.decode(rawFrames[i]));
          final pga = raw['data']['pga'];
          final pgv = raw['data']['pgv'];
          final time = PAlertService.parseTimestamp(pga['timestamp'])!;
          await waitUntil(() => service.dataTimeNotifier.value == time);
          expect(service.processingIsolateName, 'palert-data-processing');
          final levels = reference.process(
            time,
            Map<String, double>.from(
              (pga['dataVals'] as Map).map(
                (key, value) => MapEntry(key, (value as num).toDouble()),
              ),
            ),
            pga['timestamp'] == pgv['timestamp']
                ? Map<String, double>.from(
                    (pgv['dataVals'] as Map).map(
                      (key, value) => MapEntry(key, (value as num).toDouble()),
                    ),
                  )
                : <String, double>{},
          );
          final stations = {
            for (final station in service.stations) station.id: station,
          };
          for (var s = 0; s < ids.length; s++) {
            final value = pga['dataVals'][ids[s]];
            if (value == null) continue;
            expect(stations[ids[s]]!.pgaGal, value);
            expect(stations[ids[s]]!.currentGridLevel, levels[s * 2]);
            expect(stations[ids[s]]!.dataTime, time);
          }
          expect(capture.original('palert')!['metadata'], metadata);
          expect(capture.original('palert')!['data'], raw);
          expect(frames.last.originalJson!['data'], raw);
          expect(
            identical(service.historySnapshot(), service.historySnapshot()),
            isTrue,
          );
          expect(
            service.historySnapshot()['stations'],
            hasLength(stations.length),
          );
        }
        expect(metadataRequests, 1);
        final count = frames.length;
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(
          frames.length,
          count,
          reason: 'duplicates must not publish frames',
        );
        failRequests = true;
        await waitUntil(() => statuses.isNotEmpty && statuses.last == false);
        expect(service.detectionSnapshot.detectedStations, isEmpty);
        failRequests = false;
        service.stop();
        expect(service.stations, isEmpty);
        frameIndex = 0;
        service.start();
        await waitUntil(
          () => metadataRequests == 2 && service.dataTimeNotifier.value != null,
        );
        expect(service.processingIsolateName, 'palert-data-processing');
        service.stop();
        final stoppedFrames = frames.length;
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(service.stations, isEmpty);
        expect(frames.length, stoppedFrames);
      } finally {
        service.stop();
        capture.removeListener(frames.add);
        await serving.cancel();
        await server.close(force: true);
      }
    },
  );
}
