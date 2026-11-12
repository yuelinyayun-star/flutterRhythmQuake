// Standalone Android verification entrypoint; never imported by the APP.
// Serve test/fixtures on 127.0.0.1:18765, then build this target for an emulator.
// Test-only entrypoint uses the existing raw-input seam and machine-readable logs.
// ignore_for_file: invalid_use_of_visible_for_testing_member, avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutterrhythmquake/services/native_core_bootstrap.dart';
import 'package:flutterrhythmquake/services/native_replay_history_files_io.dart';
import 'package:flutterrhythmquake/services/sources/native_station_core_library_io.dart';
import 'package:flutterrhythmquake/services/sources/native_station_runtime.dart';
import 'package:flutterrhythmquake/services/sources/native_http_client.dart';
import 'package:flutterrhythmquake/services/sources/native_websocket_channel.dart';
import 'package:flutterrhythmquake/services/sources/native_tcp_socket.dart';
import 'package:flutterrhythmquake/services/sources/native_jma_tile_owner.dart';
import 'package:flutterrhythmquake/services/sources/native_replay_log_session.dart';
import 'package:flutterrhythmquake/services/sources/native_station_image_decoder.dart';
import 'package:flutterrhythmquake/services/sources/palert_service.dart';
import 'package:flutterrhythmquake/services/sources/source_http_client.dart';
import 'package:flutterrhythmquake/services/sources/source_socket_error.dart';

const fixtureRoot = String.fromEnvironment(
  'RQ_SMOKE_FIXTURE_ROOT',
  defaultValue: 'http://10.0.2.2:18765',
);
void require(bool value, String message) {
  if (!value) throw StateError(message);
}

bool equalJson(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && equalJson(a[k], b[k]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(a.length, (i) => i).every((i) => equalJson(a[i], b[i]));
  }
  return a == b;
}

Future<void> until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Native smoke timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<Uint8List> original(String path) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(
      Uri.parse('$fixtureRoot/$path'),
    )).close();
    require(response.statusCode == 200, 'Fixture unavailable: $path');
    final body = BytesBuilder(copy: false);
    await for (final chunk in response) {
      body.add(chunk);
    }
    return body.takeBytes();
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, Object?>> verify() async {
  await initializeNativeCore();
  require(StationCoreLibrary.supported, 'Rust backend disabled on Android');
  final abi = StationCoreLibrary.library
      .lookupFunction<Uint32 Function(), int Function()>(
        'rq_station_core_abi_version',
      )();
  require(abi == 1, 'ABI mismatch');
  final metadata = await original('palert_cadence_20261014/station-list.json');
  final observation = await original('palert_cadence_20261014/00.json');
  final radarIndex = await original(
    'jma_tile_runtime_20261019/radar.targetTimes.original.json',
  );
  final kmaFrames = <Uint8List>[
    for (var i = 0; i < 8; i++)
      await original(
        'source_ws_followup_20261016/kma_${i.toString().padLeft(2, '0')}.original.bytes',
      ),
  ];
  final report = <String, Object?>{
    'abi': abi,
    'pointerBytes': sizeOf<IntPtr>(),
  };
  final productionHttp = createSourceHttpClient();
  try {
    require(
      productionHttp is NativeHttpClient,
      'Android source HTTP factory did not select Rust transport',
    );
    report['sourceHttpDefaultsToRust'] = true;
  } finally {
    productionHttp.close();
  }
  final peers = <WebSocket>[];
  final stalled = Completer<void>();
  final releaseStall = Completer<void>();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final serving = server.listen((request) async {
    try {
      switch (request.uri.path) {
        case '/stall':
          if (!stalled.isCompleted) stalled.complete();
          await releaseStall.future;
          await request.response.close();
        case '/socket':
          final peer = await WebSocketTransformer.upgrade(request);
          peers.add(peer);
          peer.add(utf8.decode(kmaFrames[1]));
        case '/reject':
          request.response.statusCode = 403;
          await request.response.close();
        case '/radar':
          request.response.add(radarIndex);
          await request.response.close();
        case '/gzip':
          request.response.headers.set('Content-Encoding', 'gzip');
          request.response.add(gzip.encode(metadata));
          await request.response.close();
        default:
          request.response.add(metadata);
          await request.response.close();
      }
    } on IOException {
      /* Explicit transport cancellation closes the peer. */
    }
  });
  final base = 'http://127.0.0.1:${server.port}';
  try {
    final http = NativeHttpClient(requestTimeout: const Duration(seconds: 15));
    try {
      for (final path in ['/large?q=%E6%B5%8B%E7%AB%99', '/gzip']) {
        final response = await http.get(Uri.parse('$base$path'));
        require(
          response.statusCode == 200 &&
              sha256.convert(response.bodyBytes) == sha256.convert(metadata),
          'Buffered HTTP or gzip changed original bytes: $path',
        );
      }
      // Verify the real Android TLS/certificate path in addition to loopback.
      final tls = await http.get(
        Uri.parse(
          'https://www.jma.go.jp/bosai/jmatile/data/nowc/targetTimes_N1.json',
        ),
      );
      require(
        tls.statusCode == 200 && jsonDecode(tls.body) is List,
        'Verified HTTPS failed',
      );
      report['httpOriginalBytesAndTls'] = true;
    } finally {
      http.close();
    }
    await until(
      () =>
          NativeHttpClient.activeClients == 0 &&
          NativeHttpClient.activeRequests == 0,
    );

    final socket = NativeWebSocketChannel.connect(
      Uri.parse('ws://127.0.0.1:${server.port}/socket'),
      textAsBytes: true,
    );
    final received = socket.stream.first;
    try {
      await socket.ready;
      require(
        sha256.convert(await received as List<int>) ==
            sha256.convert(kmaFrames[1]),
        'WebSocket changed original bytes',
      );
    } finally {
      await socket.sink.close();
    }
    final rejected = NativeWebSocketChannel.connect(
      Uri.parse('ws://127.0.0.1:${server.port}/reject'),
    );
    final errors = rejected.stream.listen((_) {}, onError: (Object _) {});
    var rejection = false;
    try {
      await rejected.ready;
    } catch (error) {
      rejection = sourceSocketStatusCode(error) == 403;
    }
    await errors.cancel();
    require(rejection, 'HTTP 403 was not preserved for auth retry policy');
    await until(() => NativeWebSocketChannel.activeWorkers == 0);
    report['websocketOriginalAnd403'] = true;
    final pendingSocket = NativeWebSocketChannel.connect(
      Uri.parse('ws://127.0.0.1:${server.port}/stall'),
    );
    final pendingEvents = pendingSocket.stream.listen(
      (_) {},
      onError: (Object _) {},
    );
    try {
      await stalled.future.timeout(const Duration(seconds: 10));
      final watch = Stopwatch()..start();
      await pendingSocket.sink.close();
      require(
        watch.elapsed < const Duration(seconds: 2),
        'Cancellation left the WebSocket handshake running',
      );
    } finally {
      await pendingEvents.cancel();
      releaseStall.complete();
    }
    await until(() => NativeWebSocketChannel.activeWorkers == 0);
    report['handshakeCancellation'] = true;

    final tcpServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final tcpServing = tcpServer.listen((peer) {
      peer.add(kmaFrames[1]);
      unawaited(peer.flush().then((_) => peer.close()));
    });
    final tcp = NativeTcpSocket.open(
      InternetAddress.loopbackIPv4,
      tcpServer.port,
    );
    final data = BytesBuilder(copy: false);
    final done = Completer<void>();
    final listener = tcp.listen(
      data.add,
      onDone: done.complete,
      onError: done.completeError,
    );
    try {
      await tcp.ready;
      await done.future.timeout(const Duration(seconds: 10));
      require(
        sha256.convert(data.takeBytes()) == sha256.convert(kmaFrames[1]),
        'Native TCP changed bytes',
      );
    } finally {
      tcp.destroy();
      await listener.cancel();
      await tcpServing.cancel();
      await tcpServer.close();
    }
    await until(
      () =>
          NativeTcpSocket.activeSessions == 0 &&
          NativeTcpSocket.activeSockets == 0,
    );
    report['tcpAndRelease'] = true;

    final runtime = NativeStationRuntime();
    Map<String, dynamic>? frame;
    runtime.onFrame = (f) => frame = f;
    runtime.start({'kind': 'kma', 'source': 'pews', 'testing': true});
    try {
      for (final raw in kmaFrames) {
        runtime.injectOriginal(raw, DateTime.utc(2026, 10, 16, 10));
      }
      await until(() => (frame?['frames'] as int? ?? 0) >= 6);
      require(
        (frame!['stations'] as List).isNotEmpty,
        'Native station projection empty',
      );
      report['kmaOriginalFrames'] = frame!['frames'];
    } finally {
      runtime.stop();
    }
    await until(() => NativeStationRuntime.workers == 0);

    final palert = PAlertService.nativeForTesting(settings: {'testing': true});
    try {
      palert.start();
      palert.handleOriginalForTesting(
        metadata,
        DateTime.utc(2026, 10, 14, 9, 4, 50),
      );
      await until(() => palert.stations.isNotEmpty);
      palert.handleOriginalForTesting(
        observation,
        DateTime.utc(2026, 10, 14, 9, 4, 50),
      );
      await until(() => palert.nativeFrameCount == 1);
      require(
        palert.processingIsolateName == 'rust-palert-runtime',
        'P-Alert bypassed Rust',
      );
      require(
        palert.stations.any((s) => s.pgaGal != null),
        'Prepared numeric station payload missing',
      );
      report['palertPreparedStations'] = palert.stations.length;
    } finally {
      palert.stop();
    }
    await until(() => NativeStationRuntime.workers == 0);

    Map<String, dynamic>? selected;
    final radar = NativeJmaTileOwner(
      satellite: false,
      onFrame: (f) => selected = f,
    );
    try {
      radar.start(
        interval: const Duration(minutes: 5),
        testEndpoint: Uri.parse('$base/radar'),
      );
      await until(() => selected != null);
      require(selected!['basetime'] != null, 'Native radar frame not selected');
      report['radarIndexAndLocalTime'] = true;
    } finally {
      radar.dispose();
    }
    await until(() => NativeJmaTileOwner.workers == 0);

    final image = await original(
      'jma_tile_runtime_20261019/radar.tile.original.png',
    );
    final decoder = NativeStationImageDecoder([0, 0, 128, 128]);
    try {
      final sampled = decoder.decode(image);
      require(
        sampled.width == 256 &&
            sampled.height == 256 &&
            sampled.pixels.length == 2,
        'Rust image decoder failed',
      );
      report['imageDecoder'] = true;
    } finally {
      decoder.dispose();
    }

    final temp = await getTemporaryDirectory();
    final root = await Directory('${temp.path}/rq-android-rust-smoke').create();
    final files = NativeReplayHistoryFiles(root.path);
    try {
      final originalReport = jsonDecode(utf8.decode(kmaFrames[1])) as Map;
      final digest = await files.writeReport('smoke-event', originalReport);
      require(
        equalJson(
          await files.readReport('smoke-event', digest),
          originalReport,
        ),
        'Replay original report mismatch',
      );
      files.acceptFrame('smoke-frame', originalReport);
      await files.flushPending();
      require(
        equalJson(await files.readFrame('smoke-frame'), originalReport),
        'Replay directory frame mismatch',
      );
      report['replayFilesAndRelease'] = true;
      final archive = NativeReplayLogSession();
      try {
        archive.start(
          sessionStart: DateTime.now().toIso8601String(),
          stamp: 'android_rust_smoke',
          outputDirectory: root.path,
          writeToDisk: true,
        );
        await archive.save();
        archive.stopSync();
        require(archive.readRecords().isEmpty, 'Empty replay archive changed');
        report['replayPrivateCacheAndClock'] = true;
      } finally {
        archive.dispose();
      }
      await until(() => NativeReplayLogSession.activeWorkers == 0);
    } finally {
      files.dispose();
      await root.delete(recursive: true);
    }
    require(
      NativeReplayHistoryFiles.sessions == 0 &&
          NativeReplayHistoryFiles.results == 0,
      'Replay owner leaked',
    );
    report['passed'] = true;
    return report;
  } finally {
    if (!releaseStall.isCompleted) releaseStall.complete();
    for (final peer in peers) {
      await peer.close();
    }
    await serving.cancel();
    await server.close(force: true);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Android Rust verification'))),
    ),
  );
  try {
    final report = await verify();
    print('RQ_ANDROID_RUST_SMOKE ${jsonEncode(report)}');
  } catch (error, stack) {
    print(
      'RQ_ANDROID_RUST_SMOKE ${jsonEncode({'passed': false, 'error': '$error', 'stack': '$stack'})}',
    );
  }
}
