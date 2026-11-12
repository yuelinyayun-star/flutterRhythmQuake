// The companion PowerShell script generates this part directly from production
// parser sources, so the AOT benchmark does not import Flutter's UI runtime.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutterrhythmquake/services/sources/native_station_core_library_io.dart';

part '../build/performance/global_quake_decoder_under_test.dart';

void main(List<String> args) {
  final mode = args[0];
  final workload = args[1];
  final repeats = int.parse(args[2]);
  final raw = File(
    'test/fixtures/global_quake/stream_20260921.bin',
  ).readAsBytesSync();
  final probe = _DartJavaObjectStreamDecoder()..add(raw);
  final completeLength = raw.length - probe._bytes.length;
  final complete = Uint8List.sublistView(raw, 0, completeLength);
  final reset = Uint8List.fromList([0x79, ...complete.sublist(4)]);
  final input = workload == 'stream' ? complete : raw;
  final parts = <Uint8List>[
    if (workload == 'fragmented')
      for (var offset = 0; offset < input.length; offset += 64)
        Uint8List.sublistView(
          input,
          offset,
          (offset + 64).clamp(0, input.length),
        )
    else
      input,
  ];
  var checksum = 0, packets = 0;
  late List<_JavaObject> Function(Uint8List) add;
  late void Function() close;
  void open() {
    if (mode == 'rust') {
      final decoder = _NativeJavaObjectStreamDecoder();
      add = decoder.add;
      close = decoder.dispose;
    } else {
      final decoder = _DartJavaObjectStreamDecoder();
      add = decoder.add;
      close = decoder.reset;
    }
  }

  void consume(Uint8List bytes) {
    for (final object in add(bytes)) {
      packets++;
      checksum += object.className.length + object.fields.length;
    }
  }

  // Identical original bytes and graph reconstruction on both sides. No JSON
  // snapshots, disk I/O or UI code in the timed receive/parse section.
  for (var warm = 0; warm < 300; warm++) {
    open();
    for (final bytes in parts) {
      consume(bytes);
    }
    close();
  }
  checksum = 0;
  packets = 0;
  final watch = Stopwatch()..start();
  if (workload == 'stream') {
    open();
    consume(complete);
    for (var i = 1; i < repeats; i++) {
      consume(reset);
    }
    close();
  } else {
    for (var i = 0; i < repeats; i++) {
      open();
      for (final bytes in parts) {
        consume(bytes);
      }
      close();
    }
  }
  watch.stop();
  stdout.writeln(
    jsonEncode({
      'mode': mode,
      'workload': workload,
      'repeats': repeats,
      'original_bytes': raw.length,
      'complete_bytes': completeLength,
      'checksum': checksum,
      'packets': packets,
      'processing_ms': watch.elapsedMicroseconds / 1000,
      'rss_mb': ProcessInfo.currentRss / 1048576,
      if (mode == 'rust') 'native': _NativeJavaObjectStreamDecoder.diagnostics,
    }),
  );
}
