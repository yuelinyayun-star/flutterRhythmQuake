import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutterrhythmquake/services/sources/native_http_client.dart';
import 'benchmark_tcp_ingress.dart' show cpu100ns;

const input = 'test/fixtures/jma_ashfall/20260923145625_0_VFVO55_010000.xml';
Future<void> serve(List<dynamic> args) async {
  final parent = args[0] as SendPort;
  final bytes = args[1] as Uint8List;
  final compressed = args[2] as bool;
  final payload = compressed ? gzip.encode(bytes) : bytes;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  parent.send(server.port);
  server.listen((request) async {
    request.response.headers.set(
      'content-type',
      'application/xml; charset=utf-8',
    );
    if (compressed) request.response.headers.set('content-encoding', 'gzip');
    request.response.contentLength = payload.length;
    request.response.add(payload);
    await request.response.close();
  });
}

Future<void> main(List<String> args) async {
  if (args.first == 'probe') {
    final client = NativeHttpClient(
      requestTimeout: const Duration(seconds: 25),
    );
    final rows = <Map<String, dynamic>>[];
    try {
      for (final url in [
        'https://www.jma.go.jp/bosai/common/const/area.json',
        'https://www.data.jma.go.jp/developer/xml/feed/eqvol.xml',
        'https://earthquake.usgs.gov/fdsnws/event/1/version',
      ]) {
        final response = await client.get(
          Uri.parse(url),
          headers: {
            'User-Agent': 'flutterrhythmquake/1.0',
            'Referer': url.contains('jma.go.jp')
                ? 'https://www.jma.go.jp/'
                : 'https://earthquake.usgs.gov/',
          },
        );
        if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
          throw StateError(
            'HTTPS probe failed: $url HTTP ${response.statusCode}',
          );
        }
        rows.add({
          'url': url,
          'status': response.statusCode,
          'bytes': response.bodyBytes.length,
          'sha256': sha256.convert(response.bodyBytes).toString(),
        });
      }
      stdout.writeln(jsonEncode(rows));
    } finally {
      client.close();
    }
    return;
  }
  final native = args[0] == 'native', concurrency = int.parse(args[1]);
  final compressed = args[2] == 'gzip';
  final repetitions = concurrency == 1 ? 1024 : 128;
  final original = File(input).readAsBytesSync();
  final expected = sha256.convert(original).toString();
  // Same DLL in both AOT processes; no Flutter engine, source model or UI.
  if (NativeHttpClient.activeClients != 0) throw StateError('HTTP client leak');
  final parent = ReceivePort();
  final server = await Isolate.spawn(serve, [
    parent.sendPort,
    original,
    compressed,
  ]);
  final port = await parent.first as int;
  parent.close();
  final http.Client client = native ? NativeHttpClient() : IOClient();
  final uri = Uri.parse('http://127.0.0.1:$port/original.xml');
  Timer? sample;
  try {
    Future<void> one() async {
      final response = await client.get(uri);
      if (response.statusCode != 200 ||
          sha256.convert(response.bodyBytes).toString() != expected) {
        throw StateError('Original HTTP response bytes changed');
      }
    }

    await Future.wait(List.generate(concurrency, (_) => one()));
    final startRss = ProcessInfo.currentRss;
    var peak = startRss;
    sample = Timer.periodic(const Duration(milliseconds: 5), (_) {
      if (ProcessInfo.currentRss > peak) peak = ProcessInfo.currentRss;
    });
    final watch = Stopwatch()..start(), startCpu = cpu100ns();
    await Future.wait(
      List.generate(concurrency, (_) async {
        for (var i = 0; i < repetitions; i++) {
          await one();
        }
      }),
    ).timeout(const Duration(seconds: 90));
    watch.stop();
    final cpuMs = (cpu100ns() - startCpu) / 10000;
    sample.cancel();
    final endRss = ProcessInfo.currentRss;
    client.close();
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while ((NativeHttpClient.activeClients != 0 ||
            NativeHttpClient.activeRequests != 0) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (NativeHttpClient.activeClients != 0 ||
        NativeHttpClient.activeRequests != 0) {
      throw StateError('Native HTTP resource leak');
    }
    stdout.writeln(
      jsonEncode({
        'mode': native ? 'native' : 'dart',
        'concurrency': concurrency,
        'encoding': compressed ? 'gzip' : 'plain',
        'requests': repetitions * concurrency,
        'bytes': original.length * repetitions * concurrency,
        'elapsedMs': watch.elapsedMicroseconds / 1000,
        'processCpuMs': cpuMs,
        'startRssMiB': startRss / 1048576,
        'peakRssMiB': peak / 1048576,
        'endRssMiB': endRss / 1048576,
        'inputSha256': expected,
        'allResponseHashesMatched': true,
        'remainingClients': NativeHttpClient.activeClients,
        'remainingRequests': NativeHttpClient.activeRequests,
        'peakQueuedBytesPerRequest': NativeHttpClient.queuePeakBytes,
      }),
    );
  } finally {
    sample?.cancel();
    client.close();
    server.kill(priority: Isolate.immediate);
  }
}
