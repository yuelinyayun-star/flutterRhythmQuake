import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _defaultUrls = <String>[
  'wss://ws.fanstudio.hk/all',
  'wss://ws.fanstudio.tech/all',
];

const _initialMessages = <String>[
  // 等待 FAN API 授权后恢复：'cwalist',
  // 等待 FAN API 授权后恢复：'cenclist',
  'fssnlist',
];
const _automaticMessages = <String>[
  'query',
  // 等待 FAN API 授权后恢复：'cwalist',
  // 等待 FAN API 授权后恢复：'cenclist',
  'fssnlist',
];

Future<void> main(List<String> args) async {
  final urls = args.isEmpty ? _defaultUrls : args;
  for (final url in urls) {
    if (await _probe(url)) return;
  }
  stderr.writeln('All FAN endpoints failed.');
  exitCode = 1;
}

Future<bool> _probe(String url) async {
  stdout.writeln('\n=== FAN application session: $url ===');
  final uri = Uri.parse(url);
  try {
    final addresses = await InternetAddress.lookup(
      uri.host,
    ).timeout(const Duration(seconds: 10));
    stdout.writeln(
      'DNS: ${addresses.map((address) => address.address).join(', ')}',
    );
  } catch (error) {
    stdout.writeln('DNS failed: $error');
    return false;
  }

  WebSocket socket;
  try {
    socket = await WebSocket.connect(url).timeout(const Duration(seconds: 10));
  } catch (error) {
    stdout.writeln('Handshake failed: ${error.runtimeType}: $error');
    return false;
  }

  stdout.writeln('WebSocket open');
  final startedAt = DateTime.now();
  final done = Completer<void>();
  var packetCount = 0;
  final typeCounts = <String, int>{};
  late final StreamSubscription subscription;
  subscription = socket.listen(
    (raw) {
      packetCount++;
      final elapsed = DateTime.now().difference(startedAt);
      try {
        final decoded = jsonDecode(raw.toString());
        if (decoded is! Map) {
          stdout.writeln('[+${_seconds(elapsed)}s] non-map packet');
          return;
        }
        final data = Map<String, dynamic>.from(decoded);
        final type = data['type']?.toString() ?? 'unknown';
        typeCounts[type] = (typeCounts[type] ?? 0) + 1;
        stdout.writeln('[+${_seconds(elapsed)}s] ${_describe(data)}');
        if (type == 'heartbeat') socket.add('ping');
      } catch (error) {
        stdout.writeln('[+${_seconds(elapsed)}s] decode failed: $error');
      }
    },
    onError: (Object error) {
      stdout.writeln('Stream error: $error');
      if (!done.isCompleted) done.complete();
    },
    onDone: () {
      stdout.writeln('Remote closed: code=${socket.closeCode}');
      if (!done.isCompleted) done.complete();
    },
    cancelOnError: true,
  );

  unawaited(_sendSequence(socket, _initialMessages, startedAt));
  unawaited(() async {
    await Future<void>.delayed(const Duration(seconds: 10));
    await _sendSequence(socket, _automaticMessages, startedAt);
  }());

  await Future.any([
    done.future,
    Future<void>.delayed(const Duration(seconds: 24)),
  ]);
  stdout.writeln('Packets: $packetCount; types: $typeCounts');
  await subscription.cancel();
  try {
    await socket.close(WebSocketStatus.normalClosure, 'probe complete');
  } catch (_) {}
  return true;
}

Future<void> _sendSequence(
  WebSocket socket,
  List<String> messages,
  DateTime startedAt,
) async {
  for (final message in messages) {
    final elapsed = DateTime.now().difference(startedAt);
    stdout.writeln('[+${_seconds(elapsed)}s] SEND $message');
    socket.add(message);
    await Future<void>.delayed(const Duration(seconds: 2));
  }
}

String _describe(Map<String, dynamic> packet) {
  final type = packet['type']?.toString() ?? 'unknown';
  if (type == 'heartbeat' || type == 'pong') {
    return '$type ver=${packet['ver']} timestamp=${packet['timestamp']}';
  }
  if (type == 'auth_required') {
    return 'auth_required message=${packet['message']}';
  }
  if (type == 'initial' || type == 'update') {
    final source = packet['source']?.toString() ?? '';
    return '$type source=$source ${_dataSummary(packet['Data'])}';
  }
  if (type == 'query_response' || type == 'initial_all') {
    final sources = packet.keys
        .where((key) => !const {'type', 'ver', 'id', 'timestamp'}.contains(key))
        .toList();
    final details = sources
        .map((source) => '$source=${_dataSummary(packet[source])}')
        .join('; ');
    return '$type sources=$sources${details.isEmpty ? '' : ' | $details'}';
  }
  if (type.endsWith('list_response')) {
    return '$type ${_dataSummary(packet['Data'])}';
  }
  if (type == 'error') return 'error message=${packet['message']}';
  return '$type keys=${packet.keys.toList()} ${_dataSummary(packet['Data'])}';
}

String _dataSummary(Object? value) {
  if (value is List) {
    return 'list(${value.length})${value.isEmpty ? '' : ' first=${_eventSummary(value.first)}'}';
  }
  if (value is Map) return _eventSummary(value);
  if (value == null) return 'null';
  return value.toString();
}

String _eventSummary(Object? value) {
  if (value is! Map) return value.toString();
  if (value.containsKey('Data')) {
    final md5 = value['md5']?.toString() ?? '';
    final md5Text = md5.isEmpty
        ? ''
        : ' md5=${md5.substring(0, md5.length.clamp(0, 8))}...';
    return 'envelope(${_dataSummary(value['Data'])}$md5Text)';
  }
  const keys = <String>[
    'id',
    'eventId',
    'shockTime',
    'createTime',
    'updateTime',
    'placeName',
    'locationDesc',
    'title',
    'magnitude',
    'magnitudel',
    'maxIntensity',
    'epiIntensity',
    'updates',
    'isactive',
    'name',
    'tfid',
  ];
  final selected = <String, Object?>{};
  for (final key in keys) {
    if (value.containsKey(key)) selected[key] = value[key];
  }
  if (selected.isNotEmpty) return jsonEncode(selected);
  return 'map keys=${value.keys.take(12).toList()}';
}

String _seconds(Duration duration) =>
    (duration.inMilliseconds / 1000).toStringAsFixed(1);
