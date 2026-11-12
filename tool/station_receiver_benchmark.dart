// Offline Profile harness; never an installation/release entrypoint.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as dev;
// ignore: depend_on_referenced_packages
import 'package:vm_service/vm_service_io.dart';
import 'package:flutter/widgets.dart';
import 'package:flutterrhythmquake/services/sources/station_json_decoder.dart';
import 'package:flutterrhythmquake/services/sources/whews_station_service.dart';
import '../test/support/whews_station_service_before_20261015.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final output = Platform.environment['RQ_RECEIVER_OUTPUT'];
  if (output == null || !File(output).isAbsolute) {
    throw StateError('RQ_RECEIVER_OUTPUT requires an isolated absolute file');
  }
  try {
    final mode = Platform.environment['RQ_RECEIVER_MODE'] ?? 'rust';
    final count = int.parse(
      Platform.environment['RQ_RECEIVER_FRAMES'] ?? '1000',
    );
    final raw = File(
      'test/fixtures/whews_nied/observations.json',
    ).readAsStringSync();
    final metadata = jsonDecode(
      File('test/fixtures/whews_nied/stations.json').readAsStringSync(),
    );
    final expected = jsonEncode(jsonDecode(raw));
    final decoder = StationJsonDecoder(preferNative: mode == 'rust');
    final retain = Platform.environment['RQ_RECEIVER_RETAIN'] == '1';
    final retained = <List<Object?>>[];
    var totalUs = 0, checksum = 0.0, frames = 0;
    Future<void> run(bool measured, bool verify) async {
      late final void Function(dynamic) receive;
      late final void Function() close;
      late final Stream<WhewsStationFrame> stream;
      if (mode == 'rust') {
        final service = WhewsStationService(
          kind: WhewsStationKind.nied,
          apiToken: 'offline',
        );
        receive = service.handleMessageForTesting;
        close = service.dispose;
        stream = service.frameStream;
      } else {
        final service = FrozenWhewsStationService(
          kind: WhewsStationKind.nied,
          apiToken: 'offline',
        );
        receive = service.handleMessageForTesting;
        close = service.dispose;
        stream = service.frameStream;
      }
      // Independent receivers admit the same unchanged historic observation.
      // Catalogue setup is outside the timed high-frequency receive section.
      receive(metadata);
      final done = Completer<WhewsStationFrame>();
      final subscription = stream.listen((frame) {
        var sum = 0.0;
        for (var i = 0; i < frame.values.length; i++) {
          sum += frame.values[i] + frame.pga[i] + frame.pgv[i];
        }
        if (measured) {
          checksum += sum;
          frames++;
        }
        done.complete(frame);
      });
      final clock = Stopwatch()..start();
      receive(decoder.decode(raw));
      final frame = await done.future;
      clock.stop();
      if (measured) totalUs += clock.elapsedMicroseconds;
      if (measured && retain) {
        retained.add([
          frame.originalJson!['data'],
          frame.values,
          frame.pga,
          frame.pgv,
        ]);
      }
      if (verify && jsonEncode(frame.originalJson!['data']) != expected) {
        throw StateError('Original body mismatch');
      }
      await subscription.cancel();
      close();
    }

    for (var i = 0; i < 50; i++) {
      await run(false, false);
    }
    for (var i = 0; i < count; i++) {
      await run(true, i == 0 || i == count - 1);
    }
    final result = <String, dynamic>{
      'mode': mode,
      'frames': frames,
      'processing_ms': totalUs / 1000,
      'checksum': checksum,
      'rss_mb': ProcessInfo.currentRss / 1048576,
    };
    if (retain) {
      result['retained'] = retained.length;
      final info = await dev.Service.getInfo();
      result['gc_available'] = info.serverUri != null;
      if (info.serverUri != null) {
        final uri = info.serverUri!;
        final vm = await vmServiceConnectUri(
          uri.replace(scheme: 'ws', path: '${uri.path}ws').toString(),
        );
        try {
          final main = (await vm.getVM()).isolates!.firstWhere(
            (i) => i.name == 'main',
          );
          result['live_heap'] = (await vm.getAllocationProfile(
            main.id!,
            gc: true,
          )).memoryUsage?.toJson();
          result['live_rss_mb'] = ProcessInfo.currentRss / 1048576;
          result['retained_checksum'] = retained.fold<double>(
            0,
            (sum, row) =>
                sum +
                (row[1] as List<double>).first +
                (row[2] as List<double>).last,
          );
          decoder.dispose();
          retained.clear();
          result['released_heap'] = (await vm.getAllocationProfile(
            main.id!,
            gc: true,
          )).memoryUsage?.toJson();
          result['released_rss_mb'] = ProcessInfo.currentRss / 1048576;
        } finally {
          await vm.dispose();
        }
      } else {
        decoder.dispose();
        retained.clear();
      }
    } else {
      decoder.dispose();
    }
    await File(output).writeAsString(jsonEncode(result));
    exit(0);
  } catch (error, stack) {
    await File(
      output,
    ).writeAsString(jsonEncode({'error': '$error', 'stack': '$stack'}));
    exit(1);
  }
}
