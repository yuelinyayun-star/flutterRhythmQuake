import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutterrhythmquake/services/sources/native_tcp_socket.dart';
import 'package:flutterrhythmquake/services/sources/source_tcp_socket.dart';

// Component pressure load. Repeat the unchanged capture as bytes; do not parse
// repeated residual Java objects as earthquake messages or inject into the APP.
const input = 'test/fixtures/global_quake/stream_20260921.bin';
Future<void> serve(List<dynamic> args) async {
  final parent = args[0] as SendPort, payload = args[1] as Uint8List;
  final repetitions = args[2] as int;
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  parent.send(server.port);
  server.listen((socket) {
    socket.listen((commands) {
      for (final command in commands) {
        for (var i = 0; i < (command == 119 ? 4 : repetitions); i++) {
          socket.add(payload);
        }
      }
    }, onError: (_) {});
  });
}

int cpu100ns() {
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
    final t = arena<Uint64>(4);
    if (read(process, t, t + 1, t + 2, t + 3) == 0) {
      throw StateError('GetProcessTimes failed');
    }
    return t[2] + t[3];
  });
}

class DigestOutput implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest digest) {
    value = digest;
  }

  @override
  void close() {}
}

String expectedDigest(Uint8List payload, int repetitions) {
  final output = DigestOutput();
  final hash = sha256.startChunkedConversion(output);
  for (var i = 0; i < repetitions; i++) {
    hash.add(payload);
  }
  hash.close();
  return output.value.toString();
}

Future<void> main(List<String> args) async {
  final native = args[0] == 'native', count = int.parse(args[1]);
  final repetitions = count == 1 ? 1024 : 64;
  final original = File(input).readAsBytesSync();
  final payload = Uint8List.fromList([
    for (var i = 0; i < 64; i++) ...original,
  ]);
  final expected = expectedDigest(payload, repetitions);
  // Load the same DLL in both modes before measuring RSS; only the native
  // transport initializes its shared reactor. No Flutter engine/UI is present.
  if (NativeTcpSocket.activeSessions != 0) throw StateError('Leaked TCP owner');
  final parent = ReceivePort();
  final server = await Isolate.spawn(serve, [
    parent.sendPort,
    payload,
    repetitions,
  ]);
  final port = await parent.first as int;
  parent.close();
  final sockets = <SourceTcpSocket>[];
  final subscriptions = <StreamSubscription<Uint8List>>[];
  final warm = <Completer<void>>[], done = <Completer<void>>[];
  final outputs = <DigestOutput>[];
  var timed = false, peak = 0;
  Timer? sample;
  try {
    for (var i = 0; i < count; i++) {
      final socket = native
          ? await connectSourceTcpSocket('127.0.0.1', port)
          : DartSourceTcpSocket(await Socket.connect('127.0.0.1', port));
      sockets.add(socket);
      final warmed = Completer<void>(), finished = Completer<void>();
      warm.add(warmed);
      done.add(finished);
      final output = DigestOutput();
      outputs.add(output);
      final hash = sha256.startChunkedConversion(output);
      var bytes = 0;
      subscriptions.add(
        socket.listen(
          (chunk) {
            bytes += chunk.length;
            if (timed) {
              hash.add(chunk);
              if (bytes == payload.length * repetitions &&
                  !finished.isCompleted) {
                hash.close();
                finished.complete();
              }
            } else if (bytes == payload.length * 4 && !warmed.isCompleted) {
              bytes = 0;
              warmed.complete();
            }
          },
          onError: (Object error) {
            if (!warmed.isCompleted) warmed.completeError(error);
            if (!finished.isCompleted) finished.completeError(error);
          },
        ),
      );
    }
    for (final socket in sockets) {
      socket.add([119]);
    }
    await Future.wait(
      warm.map((c) => c.future),
    ).timeout(const Duration(seconds: 20));
    final startRss = ProcessInfo.currentRss;
    peak = startRss;
    sample = Timer.periodic(const Duration(milliseconds: 5), (_) {
      final rss = ProcessInfo.currentRss;
      if (rss > peak) peak = rss;
    });
    timed = true;
    final watch = Stopwatch()..start(), startCpu = cpu100ns();
    for (final socket in sockets) {
      socket.add([109]);
    }
    await Future.wait(
      done.map((c) => c.future),
    ).timeout(const Duration(seconds: 60));
    watch.stop();
    final cpuMs = (cpu100ns() - startCpu) / 10000;
    sample.cancel();
    if (outputs.any((o) => o.value.toString() != expected)) {
      throw StateError('Original TCP bytes changed');
    }
    final endRss = ProcessInfo.currentRss;
    final peakQueue = NativeTcpSocket.peakQueuedBytesPerSocket;
    if (peakQueue > 65536) {
      throw StateError('TCP receive backpressure exceeded its bound');
    }
    for (final socket in sockets) {
      socket.destroy();
    }
    await Future.wait(subscriptions.map((s) => s.cancel()));
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (NativeTcpSocket.activeSockets != 0 &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    stdout.writeln(
      jsonEncode({
        'mode': native ? 'native' : 'dart',
        'connections': count,
        'bytes': payload.length * repetitions * count,
        'elapsedMs': watch.elapsedMicroseconds / 1000,
        'processCpuMs': cpuMs,
        'startRssMiB': startRss / 1048576,
        'peakRssMiB': peak / 1048576,
        'endRssMiB': endRss / 1048576,
        'inputSha256': sha256.convert(original).toString(),
        'outputSha256PerConnection': expected,
        'remainingSessions': NativeTcpSocket.activeSessions,
        'remainingSockets': NativeTcpSocket.activeSockets,
        'reactorThreads': NativeTcpSocket.reactorThreads,
        'peakQueuedBytesPerSocket': peakQueue,
      }),
    );
  } finally {
    sample?.cancel();
    for (final socket in sockets) {
      socket.destroy();
    }
    await Future.wait(subscriptions.map((s) => s.cancel()));
    server.kill(priority: Isolate.immediate);
  }
}
