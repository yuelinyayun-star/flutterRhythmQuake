import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutterrhythmquake/services/sources/native_websocket_channel.dart';

// Read-only public ingress capture. No auth, injection, source-clock edits or
// server changes. Every file contains exactly the bytes received in one frame.
Future<void> main() async {
  final directory = Directory('test/fixtures/source_ws_followup_20261016');
  if (directory.existsSync() && directory.listSync().isNotEmpty) {
    throw StateError('Capture directory already contains original files');
  }
  directory.createSync(recursive: true);
  final results = await Future.wait(
    {
      'kma': 'wss://ws.yuelinrhythm.top/kma-station',
      'seisjs': 'wss://seisjs.wolfx.jp/all_seis',
      'p2p': 'wss://api.p2pquake.net/v2/ws',
    }.entries.map((entry) async {
      final frames = <Map<String, Object?>>[];
      final errors = <String>[];
      final channel = NativeWebSocketChannel.connect(
        Uri.parse(entry.value),
        textAsBytes: true,
        connectTimeout: const Duration(seconds: 10),
      );
      final subscription = channel.stream.listen(
        (raw) {
          if (frames.length >= 8) return;
          final bytes = raw is String ? utf8.encode(raw) : raw as List<int>;
          final name =
              '${entry.key}_${frames.length.toString().padLeft(2, '0')}.original.bytes';
          File('${directory.path}/$name').writeAsBytesSync(bytes);
          frames.add({
            'file': name,
            'bytes': bytes.length,
            'sha256': sha256.convert(bytes).toString(),
          });
        },
        onError: (Object error) {
          errors.add(error.toString());
        },
      );
      var ready = false;
      try {
        await channel.ready;
        ready = true;
        await Future<void>.delayed(const Duration(seconds: 8));
      } catch (error) {
        errors.add(error.toString());
      }
      await channel.sink.close();
      await subscription.cancel();
      return {
        'source': entry.key,
        'url': entry.value,
        'ready': ready,
        'frames': frames,
        'errors': errors,
      };
    }),
  );
  File('${directory.path}/manifest.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(results),
    encoding: utf8,
  );
  stdout.writeln(
    jsonEncode(
      results
          .map(
            (r) => {
              'source': r['source'],
              'ready': r['ready'],
              'frames': (r['frames'] as List).length,
              'errors': r['errors'],
            },
          )
          .toList(),
    ),
  );
}
