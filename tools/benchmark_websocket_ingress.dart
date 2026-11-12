import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:web_socket_channel/io.dart';
import 'package:flutterrhythmquake/services/sources/api_json_decoder.dart';
import 'package:flutterrhythmquake/services/sources/native_websocket_channel.dart';

const captures = [
  'test/fixtures/jma_cancellation_20261016/wolfx_original.json',
  'test/fixtures/catalog_20260917/whews_all.json',
  'test/fixtures/catalog_20260917/jian_all.json',
  'test/fixtures/emsc_ws_20261008.original.json',
];

// The local websocket server runs in another isolate in BOTH modes. Recorded
// payloads are repeated verbatim, not redated or represented as new events.
Future<void> _serve(SendPort parent) async {
  final texts = captures
      .map((p) => File(p).readAsStringSync(encoding: utf8))
      .toList();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  parent.send(server.port);
  server.listen((request) async {
    final socket = await WebSocketTransformer.upgrade(
      request,
      compression: CompressionOptions.compressionOff,
    );
    var sent = 0;
    socket.listen((_) {
      for (var n = 0; n < 16; n++) {
        socket.add(texts[sent++ % texts.length]);
      }
    });
  });
}

int _cpu100ns() {
  final dll = DynamicLibrary.open('kernel32.dll');
  final process = dll
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'GetCurrentProcess',
      )();
  final read = dll
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
        ),
        int Function(
          Pointer<Void>,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
        )
      >('GetProcessTimes');
  return using((arena) {
    final times = arena<Uint64>(4);
    if (read(process, times, times + 1, times + 2, times + 3) == 0) {
      throw StateError('GetProcessTimes failed');
    }
    return times[2] + times[3];
  });
}

Future<void> main(List<String> args) async {
  final native = args.first == 'native';
  final frames = args.length > 1 ? int.parse(args[1]) : 4096;
  if (frames % 16 != 0) throw ArgumentError('frames must be a multiple of 16');
  final originals = captures.map((p) => File(p).readAsBytesSync()).toList();
  final texts = originals.map(utf8.decode).toList();
  final expected = texts.map(jsonDecode).toList();
  final port = ReceivePort();
  final server = await Isolate.spawn(_serve, port.sendPort);
  final socketPort = await port.first as int;
  port.close();
  final uri = Uri.parse('ws://127.0.0.1:$socketPort/');
  final channel = native
      ? NativeWebSocketChannel.connect(uri, textAsBytes: true)
      : IOWebSocketChannel.connect(uri);
  final warm = Completer<void>(), finished = Completer<void>();
  var received = 0, checksum = 0, bytes = 0;
  var timed = false;
  final timer = Stopwatch();
  var startCpu = 0, startRss = 0, peakRss = 0;
  final gaps = <int>[];
  final gapsClock = Stopwatch()..start();
  var lastTick = 0;
  final sample = Timer.periodic(const Duration(milliseconds: 8), (_) {
    final now = gapsClock.elapsedMicroseconds;
    if (timed) {
      gaps.add(now - lastTick);
      final rss = ProcessInfo.currentRss;
      if (rss > peakRss) peakRss = rss;
    }
    lastTick = now;
  });
  final subscription = channel.stream.listen(
    (frame) {
      final index = received % originals.length;
      final decoded = frame is String
          ? decodeApiJson(frame)
          : decodeApiJsonBytes(frame as List<int>);
      if (!timed && received < originals.length) {
        if (frame is String
            ? frame != texts[index]
            : sha256.convert(frame as List<int>).toString() !=
                  sha256.convert(originals[index]).toString()) {
          throw StateError('Original wire bytes changed');
        }
        if (jsonEncode(decoded) != jsonEncode(expected[index])) {
          throw StateError('Decoded source fields changed');
        }
      }
      if (timed) {
        checksum += decoded is Map ? decoded.length : (decoded as List).length;
        bytes += originals[index].length;
      }
      received++;
      if (!timed && received == 64) {
        warm.complete();
        return;
      }
      if (timed && received == frames) {
        timer.stop();
        finished.complete();
        return;
      }
      if (received % 16 == 0) channel.sink.add('batch');
    },
    onError: (Object error) {
      if (!warm.isCompleted) warm.completeError(error);
      if (!finished.isCompleted) finished.completeError(error);
    },
  );
  try {
    await channel.ready;
    channel.sink.add('warmup');
    await warm.future;
    received = 0;
    timed = true;
    startRss = peakRss = ProcessInfo.currentRss;
    startCpu = _cpu100ns();
    timer.start();
    channel.sink.add('measure');
    await finished.future.timeout(const Duration(minutes: 2));
    final cpuMs = (_cpu100ns() - startCpu) / 10000;
    timed = false;
    sample.cancel();
    gaps.sort();
    final endRss = ProcessInfo.currentRss;
    await channel.sink.close();
    await subscription.cancel();
    server.kill(priority: Isolate.immediate);
    disposeApiJsonResources();
    final workersDeadline = DateTime.now().add(const Duration(seconds: 5));
    if (native) {
      while (NativeWebSocketChannel.activeWorkers != 0 &&
          DateTime.now().isBefore(workersDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
    stdout.writeln(
      jsonEncode({
        'mode': native ? 'native' : 'dart',
        'frames': frames,
        'rawBytes': bytes,
        'checksum': checksum,
        'elapsedMs': timer.elapsedMicroseconds / 1000,
        'processCpuMs': cpuMs,
        'startRssMiB': startRss / 1048576,
        'peakRssMiB': peakRss / 1048576,
        'endRssMiB': endRss / 1048576,
        'tickGapP99Ms': gaps.isEmpty
            ? null
            : gaps[((gaps.length - 1) * .99).round()] / 1000,
        'remainingWorkers': native ? NativeWebSocketChannel.activeWorkers : 0,
        'inputs': [
          for (var i = 0; i < captures.length; i++)
            {
              'path': captures[i],
              'sha256': sha256.convert(originals[i]).toString(),
            },
        ],
      }),
    );
  } finally {
    sample.cancel();
    await channel.sink.close();
    await subscription.cancel();
    server.kill(priority: Isolate.immediate);
  }
}
