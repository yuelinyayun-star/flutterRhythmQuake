import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/io.dart';

// Bounded, read-only probe. Stored JSON is the exact decoded UTF-8 wire frame.
Future<void> main(List<String> args) async {
  final accessToken = Platform.environment['JIAN_ACCESS_TOKEN'] ?? '';
  if (!accessToken.startsWith('at_') ||
      accessToken.length <= 3 ||
      !RegExp(r'^[\x21-\x7E]+$').hasMatch(accessToken)) {
    stderr.writeln(
      'Set JIAN_ACCESS_TOKEN to a current access token before probing.',
    );
    exitCode = 64;
    return;
  }
  final output = args.isEmpty ? null : Directory(args.first);
  if (output != null) await output.create(recursive: true);
  final socket = IOWebSocketChannel.connect(
    Uri.parse('wss://api.sismotide.top/all'),
    headers: {'Authorization': 'Bearer $accessToken'},
  );
  final counts = <String, int>{};
  var requested = false;
  final done = Completer<void>();
  final sub = socket.stream.listen(
    (message) async {
      final text = message is String
          ? message
          : utf8.decode(message as List<int>);
      final frame = jsonDecode(text) as Map;
      final type = frame['type'].toString();
      counts[type] = (counts[type] ?? 0) + 1;
      if (output != null &&
          counts[type] == 1 &&
          (type == 'all' || type == 'jmalist_response')) {
        await File(
          '${output.path}/$type.json',
        ).writeAsString(text, encoding: utf8);
      }
      if (type == 'all') {
        print(
          'Snapshot sources: ${frame.keys.where((key) => key.toString().startsWith('source')).length}',
        );
        for (final entry in frame.entries) {
          if (entry.value is! Map) continue;
          final data = (entry.value as Map)['Data'];
          if (data is Map) print('${entry.key}: ${data.keys.join(', ')}');
        }
        if (!requested) {
          requested = true;
          socket.sink.add('jmalist');
        }
      } else {
        print('$type: count=${frame['count'] ?? '-'}');
      }
      if (type == 'error' && !done.isCompleted) done.complete();
    },
    onError: (Object error) {
      if (!done.isCompleted) done.completeError(error);
    },
    onDone: () {
      if (!done.isCompleted) done.complete();
    },
  );
  try {
    await socket.ready.timeout(const Duration(seconds: 20));
    await done.future.timeout(const Duration(seconds: 35), onTimeout: () {});
    print(jsonEncode(counts));
  } finally {
    await sub.cancel();
    await socket.sink.close().timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
  }
}
