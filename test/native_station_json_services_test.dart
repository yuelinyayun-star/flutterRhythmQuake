import 'package:flutterrhythmquake/services/whews_authorization_policy.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/station_history_frame.dart';
import 'package:flutterrhythmquake/services/debug/station_json_archive.dart';
import 'package:flutterrhythmquake/services/sources/native_station_core_library_io.dart';
import 'package:flutterrhythmquake/services/sources/station_json_decoder_io.dart';
import 'package:flutterrhythmquake/services/sources/api_json_decoder.dart';
import 'package:flutterrhythmquake/services/sources/station_json_values.dart';
import 'package:flutterrhythmquake/services/sources/whews_socket_client.dart';
import 'package:flutterrhythmquake/services/sources/whews_station_service.dart';
import 'package:flutterrhythmquake/services/sources/jian_station_service.dart';

Future<void> until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void sameDoubles(List<double> a, Iterable<num> b) {
  final expected = b.toList();
  expect(a.length, expected.length);
  for (var i = 0; i < a.length; i++) {
    final x = ByteData(8)..setFloat64(0, a[i]);
    final y = ByteData(8)..setFloat64(0, expected[i].toDouble());
    expect(x.getUint64(0), y.getUint64(0));
  }
}

void main() {
  setUp(() => WhewsAuthorizationPolicy.storeOverride = MemoryConnectionRetryStore());
  for (final binary in [false, true]) {
    test(
      'unchanged WHEWS ${binary ? 'binary' : 'text'} frames use native processing and survive disconnect',
      () async {
        final metadataBytes = File(
          'test/fixtures/whews_nied/stations.json',
        ).readAsBytesSync();
        final observationsBytes = File(
          'test/fixtures/whews_nied/observations.json',
        ).readAsBytesSync();
        final metadata = utf8.decode(metadataBytes);
        final observations = utf8.decode(observationsBytes);
        final original = jsonDecode(observations) as Map;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final peers = <WebSocket>[];
        final listener = server.listen((request) async {
          final socket = await WebSocketTransformer.upgrade(request);
          peers.add(socket);
          socket.listen((_) {});
          socket.add(binary ? metadataBytes : metadata);
          socket.add(binary ? observationsBytes : observations);
          socket.add(binary ? observationsBytes : observations);
        });
        final service = WhewsStationService(
          kind: WhewsStationKind.nied,
          apiToken: 'local-test',
          socketFactory:
              ({
                required url,
                required apiToken,
                required onMessage,
                onStateChanged,
              }) => WhewsSocketClient(
                url: 'ws://127.0.0.1:${server.port}/',
                apiToken: apiToken,
                onMessage: onMessage,
                onStateChanged: onStateChanged,
              ),
        );
        final frames = <WhewsStationFrame>[];
        final subscription = service.frameStream.listen(frames.add);
        addTearDown(() async {
          service.dispose();
          await subscription.cancel();
          for (final peer in peers) {
            await peer.close();
          }
          await listener.cancel();
          await server.close(force: true);
        });
        service.start();
        await until(() => frames.isNotEmpty);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(frames.length, 1);
        final frame = frames.single;
        final data = original['Data'] as Map;
        sameDoubles(frame.values, (data['shindo'] as List).cast<num>());
        sameDoubles(frame.pga, (data['pga'] as List).cast<num>());
        sameDoubles(frame.pgv, (data['pgv'] as List).cast<num>());
        expect(frame.originalJson!['metadata'], jsonDecode(metadata));
        expect(frame.originalJson!['data'], original);
        // Archive framing uses an empty display snapshot; the original transport
        // body is the complete unchanged captured station payload.
        final stored = StationHistoryFrame(
          receivedAt: frame.dataTime,
          snapshot: {'kind': 'nied', 'stations': []},
          originalJson: frame.originalJson,
        );
        final archive = StationJsonArchive.encode([stored]);
        final restored = StationJsonArchive.decode(
          jsonDecode(jsonEncode(archive)) as Map,
        );
        expect(restored.single.originalJson!['data'], original);
        expect(restored.single.originalJson!['metadata'], jsonDecode(metadata));
        // Dispose the shared catalogue parser before checking the independent
        // connection owner. The published catalogue remains readable.
        disposeApiJsonResources();
        expect(StationJsonDecoder.diagnostics['sessions'], 1);
        await peers.single.close();
        await until(() => StationJsonDecoder.diagnostics['sessions'] == 0);
        service.stop();
        sameDoubles(frame.values, (data['shindo'] as List).cast<num>());
        expect(() => frame.values[0] = 100, throwsUnsupportedError);
        expect(
          () =>
              (frame.values as Float64List).buffer.asByteData().setUint8(0, 0),
          throwsUnsupportedError,
        );
        expect(frame.originalJson!['data'], original);
      },
      skip: !StationCoreLibrary.supported,
    );
  }

  test('numeric conversion and range validation match original Dart rules', () {
    final decoder = StationJsonDecoder();
    addTearDown(decoder.dispose);
    for (final text in [
      '[-3,7,-0.0,0.01]',
      '[0,1e999]',
      '[7.1]',
      '[9007199254740993,-9223372036854775808]',
      '["2.5",3]',
      '[null]',
      '[]',
    ]) {
      final raw = decoder.decode(text) as List;
      final old = jsonDecode(text) as List;
      for (final allowStrings in [false, true]) {
        final expected = readStationJsonNumbers(
          old,
          minimum: -3,
          maximum: 7,
          allowStrings: allowStrings,
        );
        final actual = readStationJsonNumbers(
          raw,
          minimum: -3,
          maximum: 7,
          allowStrings: allowStrings,
        );
        expect(actual == null, expected == null);
        if (actual != null) sameDoubles(actual, expected!);
      }
      final expected = readStationJsonNumbers(old, minimum: -double.maxFinite);
      final actual = readStationJsonNumbers(raw, minimum: -double.maxFinite);
      expect(actual == null, expected == null);
      if (actual != null) sameDoubles(actual, expected!);
    }
  });

  for (final binary in [false, true]) {
    test(
      'Jian controlled lifecycle retains ${binary ? 'binary' : 'text'} frames after stop',
      () async {
        // Protocol/lifecycle input only; not a capture or performance sample.
        final service = JianStationService(kind: WhewsStationKind.kma);
        final frames = <WhewsStationFrame>[];
        final sub = service.frameStream.listen(frames.add);
        addTearDown(() async {
          service.dispose();
          await sub.cancel();
        });
        final metadata = jsonEncode({
          'type': 'kma-station',
          'stations': [
            {'lat': 37.5, 'lon': 127.0, 'code': 'protocol-test'},
          ],
        });
        service.handleMessageForTesting(
          binary ? utf8.encode(metadata) : metadata,
        );
        final now = DateTime.now().toUtc();
        String two(int n) => n.toString().padLeft(2, '0');
        final time =
            '${now.year}${two(now.month)}${two(now.day)}${two(now.hour)}${two(now.minute)}${two(now.second)}';
        final raw = jsonEncode({
          'type': 'kma-station',
          'time': time,
          'mmi': [2.5],
          'unknown': {'keep': true},
        });
        service.handleMessageForTesting(binary ? utf8.encode(raw) : raw);
        service.handleMessageForTesting(binary ? utf8.encode(raw) : raw);
        await until(() => frames.isNotEmpty);
        expect(frames.length, 1);
        expect(frames.single.values, [2.5]);
        expect(frames.single.originalJson!['data'], jsonDecode(raw));
        service.stop();
        expect(frames.single.values, [2.5]);
        if (StationCoreLibrary.supported) {
          disposeApiJsonResources();
          expect(StationJsonDecoder.diagnostics['sessions'], 0);
        }
      },
    );
  }
}
