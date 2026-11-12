// Offline Profile entrypoint. Never shipped as lib/main.dart.
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutterrhythmquake/models/source_payload.dart';
import 'package:flutterrhythmquake/services/sources/api_json_decoder.dart';
import 'package:flutterrhythmquake/services/sources/native_station_core_library_io.dart';
import 'package:flutterrhythmquake/services/sources/station_json_decoder.dart';
// ignore: depend_on_referenced_packages
import 'package:vm_service/vm_service_io.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final output = Platform.environment['RQ_API_MEMORY_OUTPUT'];
  if (output == null || !File(output).isAbsolute) {
    throw StateError('RQ_API_MEMORY_OUTPUT requires an isolated absolute file');
  }
  try {
    final rust = Platform.environment['RQ_API_MEMORY_MODE'] == 'rust';
    final raw = File(
      'test/fixtures/usgs_dyfi/ci41345415.versions.original.geojson',
    ).readAsStringSync();
    final info = await dev.Service.getInfo();
    if (info.serverUri == null) {
      throw StateError('Profile VM service unavailable');
    }
    final uri = info.serverUri!;
    final vm = await vmServiceConnectUri(
      uri.replace(scheme: 'ws', path: '${uri.path}ws').toString(),
    );
    try {
      final main = (await vm.getVM()).isolates!.firstWhere(
        (i) => i.name == 'main',
      );
      Future<Map<String, dynamic>?> heap() async =>
          (await vm.getAllocationProfile(
            main.id!,
            gc: true,
          )).memoryUsage?.toJson();
      int nativeBytes() => StationCoreLibrary.library
          .lookupFunction<Uint64 Function(), int Function()>(
            'rq_station_memory_current',
          )();
      final baseline = await heap();
      final retained = <dynamic>[];
      double collect() {
        var sum = 0.0;
        for (var i = 0; i < 100; i++) {
          final value = rust ? decodeApiJson(raw) : jsonDecode(raw);
          final snapshot = snapshotSourceJsonValue(value);
          sum += (snapshot as Map).length;
          retained.add(snapshot);
        }
        return sum;
      }

      final watch = Stopwatch()..start();
      final checksum = collect();
      watch.stop();
      final live = await heap();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final result = <String, dynamic>{
        'mode': rust ? 'rust' : 'dart',
        'frames': retained.length,
        'processing_ms': watch.elapsedMicroseconds / 1000,
        'baseline_heap': baseline,
        'live_heap': live,
        'live_rss_mb': ProcessInfo.currentRss / 1048576,
        'live_native_sessions': StationJsonDecoder.diagnostics['sessions'],
        'live_native_bytes': nativeBytes(),
        'checksum': checksum,
        'retained_checksum': retained.fold<int>(
          0,
          (sum, row) => sum + (row as Map).length,
        ),
      };
      retained.clear();
      disposeApiJsonResources();
      result['released_heap'] = await heap();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      result['released_native_sessions'] =
          StationJsonDecoder.diagnostics['sessions'];
      result['released_native_bytes'] = nativeBytes();
      result['released_rss_mb'] = ProcessInfo.currentRss / 1048576;
      result['original_characters'] = raw.length;
      if (result['released_native_sessions'] != 0 ||
          result['released_native_bytes'] != 0) {
        throw StateError(
          'Native API resources remain after teardown/GC: $result',
        );
      }
      await File(output).writeAsString(jsonEncode(result));
    } finally {
      await vm.dispose();
    }
    exit(0);
  } catch (error, stack) {
    await File(
      output,
    ).writeAsString(jsonEncode({'error': '$error', 'stack': '$stack'}));
    exit(1);
  }
}
