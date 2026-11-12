import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutterrhythmquake/services/sources/native_palert_levels_io.dart';
import 'package:flutterrhythmquake/services/sources/palert_service.dart';
import 'package:flutterrhythmquake/services/sources/station_json_decoder.dart';
import 'package:flutterrhythmquake/services/station_history_capture.dart';

import 'support/palert_level_history_before_20261015.dart';

class _OriginalResponseClient extends http.BaseClient {
  _OriginalResponseClient({
    this.holdRealtime = false,
    this.holdMetadata = false,
  });
  final bool holdRealtime;
  final bool holdMetadata;
  Completer<http.StreamedResponse>? pending;
  int realtimeRequests = 0;
  final dir = 'test/fixtures/palert_cadence_20261014';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = jsonDecode(utf8.decode(await request.finalize().toBytes()));
    final metadata = body['query'].toString().contains('stationList');
    final index = realtimeRequests < 12 ? realtimeRequests : 0;
    final path = metadata
        ? 'station-list.json'
        : '${index.toString().padLeft(2, '0')}.json';
    if (!metadata) realtimeRequests++;
    if ((!metadata && holdRealtime) || (metadata && holdMetadata)) {
      pending = Completer<http.StreamedResponse>();
      return pending!.future;
    }
    // Transport the original response bytes, including its original source time.
    return http.StreamedResponse(
      Stream.value(File('$dir/$path').readAsBytesSync()),
      200,
      request: request,
    );
  }
}

void main() {
  testWidgets(
    'original HTTP frames reach service, levels, hold, duplicate gate and stop',
    (tester) async {
      final client = _OriginalResponseClient();
      final service = PAlertService.forTesting(
        clientFactory: () async => client,
      );
      final owners = NativePAlertLevels.supported
          ? NativePAlertLevels.diagnostics['sessions']
          : null;
      final reference = DartPAlertLevelHistoryReference();
      final metadata =
          jsonDecode(
                File('${client.dir}/station-list.json').readAsStringSync(),
              )['data']['stationList']['staInfos']
              as List;
      final ids = <String>{
        for (final item in metadata) item['station'].toString().trim(),
      }.toList();
      reference.setStations(ids);
      try {
        service.start();
        for (var i = 0; i < 12; i++) {
          await tester.pump(
            i == 0 ? Duration.zero : const Duration(seconds: 1),
          );
          await tester.pump();
          expect(client.realtimeRequests, i + 1);
          final data = jsonDecode(
            File(
              '${client.dir}/${i.toString().padLeft(2, '0')}.json',
            ).readAsStringSync(),
          )['data'];
          final time = PAlertService.parseTimestamp(data['pga']['timestamp'])!;
          final pga = Map<String, double>.from(
            (data['pga']['dataVals'] as Map).map(
              (key, value) => MapEntry(key, (value as num).toDouble()),
            ),
          );
          final pgv = data['pgv']['timestamp'] == data['pga']['timestamp']
              ? Map<String, double>.from(
                  (data['pgv']['dataVals'] as Map).map(
                    (key, value) => MapEntry(key, (value as num).toDouble()),
                  ),
                )
              : <String, double>{};
          final levels = reference.process(time, pga, pgv);
          final stations = {
            for (final station in service.stations) station.id: station,
          };
          for (var s = 0; s < ids.length; s++) {
            final value = pga[ids[s]];
            if (value == null) continue;
            final station = stations[ids[s]]!;
            expect(station.pgaGal, value);
            expect(station.pgvCms, pgv[ids[s]]);
            expect(station.dataTime, time);
            expect(station.currentGridLevel, levels[s * 2]);
            expect(station.detectionLevel, levels[s * 2]);
            expect(station.heldLevel, levels[s * 2 + 1]);
          }
          expect(service.dataTimeNotifier.value, time);
        }
        final previous = service.stations;
        final previousTime = service.dataTimeNotifier.value;
        final extractionCalls = StationJsonDecoder.nativeSupported
            ? StationJsonDecoder.palertDiagnostics['calls']
            : null;
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(client.realtimeRequests, 13);
        expect(service.dataTimeNotifier.value, previousTime);
        expect(identical(service.stations, previous), isTrue);
        if (extractionCalls != null) {
          expect(
            StationJsonDecoder.palertDiagnostics['calls'],
            extractionCalls,
          );
        }
      } finally {
        service.stop(clear: false);
      }
      if (owners != null) {
        expect(NativePAlertLevels.diagnostics['sessions'], owners);
      }
    },
  );
  testWidgets(
    'a previous connection cannot overwrite the raw archive after restart',
    (tester) async {
      final previous = _OriginalResponseClient(holdMetadata: true);
      final current = _OriginalResponseClient();
      var connections = 0;
      final service = PAlertService.forTesting(
        clientFactory: () async => connections++ == 0 ? previous : current,
      );
      try {
        service.start();
        await tester.pump();
        await tester.pump();
        expect(previous.pending, isNotNull);
        service.stop();
        service.start();
        await tester.pump();
        await tester.pump();
        expect(service.stations, isNotEmpty);
        final raw = StationHistoryCapture.instance.original('palert');
        final published = service.stations;
        previous.pending!.complete(
          http.StreamedResponse(
            Stream.value(
              File('${previous.dir}/station-list.json').readAsBytesSync(),
            ),
            200,
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(
          identical(StationHistoryCapture.instance.original('palert'), raw),
          isTrue,
        );
        expect(identical(service.stations, published), isTrue);
      } finally {
        service.stop();
      }
    },
  );

  testWidgets(
    'a response after stop cannot recreate a native parser or publish stations',
    (tester) async {
      final client = _OriginalResponseClient(holdRealtime: true);
      final service = PAlertService.forTesting(
        clientFactory: () async => client,
      );
      try {
        service.start();
        await tester.pump();
        await tester.pump();
        expect(client.pending, isNotNull);
        service.stop();
        final owners = StationJsonDecoder.nativeSupported
            ? StationJsonDecoder.diagnostics['sessions']
            : null;
        final calls = StationJsonDecoder.nativeSupported
            ? StationJsonDecoder.palertDiagnostics['calls']
            : null;
        client.pending!.complete(
          http.StreamedResponse(
            Stream.value(File('${client.dir}/00.json').readAsBytesSync()),
            200,
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(service.stations, isEmpty);
        expect(service.dataTimeNotifier.value, isNull);
        if (owners != null) {
          expect(
            StationJsonDecoder.diagnostics['sessions'],
            lessThanOrEqualTo(owners),
          );
          expect(StationJsonDecoder.palertDiagnostics['calls'], calls);
        }
      } finally {
        service.stop();
      }
    },
  );
}
