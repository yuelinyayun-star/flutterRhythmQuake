import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutterrhythmquake/services/sources/native_websocket_channel.dart';

// Public read-only endpoints only. No saved credentials, auth API, replay
// injection, source timestamp edits or app preferences are touched.
Future<void> main(List<String> args) async {
  final native = args.contains('--native');
  final results = <Map<String, Object?>>[];
  for (final entry in {
    'Wolfx': 'wss://ws-api.wolfx.jp/all_eew',
    'EMSC': 'wss://www.seismicportal.eu/standing_order/websocket',
    'SASMEX': 'wss://ws.yuelinrhythm.top/sasmex-eew',
  }.entries) {
    final uri = Uri.parse(entry.value);
    final timer = Stopwatch()..start();
    final WebSocketChannel channel = native
        ? NativeWebSocketChannel.connect(
            uri,
            textAsBytes: true,
            keepaliveInterval: entry.key == 'EMSC'
                ? const Duration(seconds: 15)
                : null,
            allowBadCertificate: entry.key == 'Wolfx',
          )
        : IOWebSocketChannel.connect(
            uri,
            pingInterval: entry.key == 'EMSC'
                ? const Duration(seconds: 15)
                : null,
            customClient: entry.key == 'Wolfx'
                ? (HttpClient()..badCertificateCallback = (_, _, _) => true)
                : null,
          );
    final first = Completer<List<int>>();
    final errors = <String>[];
    final subscription = channel.stream.listen(
      (frame) {
        final bytes = frame is String
            ? utf8.encode(frame)
            : (frame as List<int>);
        if (!first.isCompleted) first.complete(bytes);
      },
      onError: (Object e) {
        errors.add(e.toString());
      },
    );
    final result = <String, Object?>{
      'source': entry.key,
      'native': native,
      'url': entry.value,
    };
    try {
      await channel.ready.timeout(const Duration(seconds: 20));
      result['readyMs'] = timer.elapsedMicroseconds / 1000;
      if (entry.key == 'SASMEX') channel.sink.add('{"type":"ping"}');
      try {
        final bytes = await first.future.timeout(const Duration(seconds: 5));
        result['firstBytes'] = bytes.length;
        result['firstSha256'] = sha256.convert(bytes).toString();
      } on TimeoutException {
        result['firstBytes'] = 0;
      }
      result['ready'] = true;
    } catch (e) {
      result['ready'] = false;
      result['error'] = e.toString();
    }
    await channel.sink.close().timeout(
      const Duration(seconds: 4),
      onTimeout: () {},
    );
    await subscription.cancel();
    result['errors'] = errors;
    results.add(result);
  }
  if (native) {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (NativeWebSocketChannel.activeWorkers != 0 &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
  stdout.writeln(
    jsonEncode({
      'results': results,
      'remainingWorkers': native ? NativeWebSocketChannel.activeWorkers : null,
    }),
  );
}
