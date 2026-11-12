import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../models/quake_message.dart';
import '../../models/source_status.dart';
import 'api_json_decoder.dart';
import 'base_source.dart';
import 'fan_service.dart';
import 'source_socket.dart';

/// Independent FSSN feed: https://fssn-api.fanstudio.tech/ (v1.0.0).
/// Windows transport and UTF-8 decoding use the existing native ingress.
class FssnService extends BaseSourceService {
  static const sourceName = 'FSSN';
  static const enabledPreferenceKey = 'api_source_fssn_enabled';
  static final endpoint = Uri.parse('wss://fssn-api.fanstudio.tech/all');

  FssnService({Uri? uri, this.retryDelay = const Duration(seconds: 3)})
    : _uri = uri ?? endpoint;

  final Uri _uri;
  final Duration retryDelay;
  void Function(List<QuakeMessage>)? onFssnListUpdated;
  void Function(List<QuakeMessage>)? onCmtListUpdated;
  final _records = <String, Map<String, _FssnRecord>>{
    'fssn': {},
    'fssn-cmt': {},
  };
  // A list response requested at connect must not replace a subsequent update.
  final _liveKeys = <String>{};
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  Timer? _watchdog;
  DateTime _lastMessageAt = DateTime.now();
  int _generation = 0;
  int _failures = 0;
  bool _running = false;
  bool _disposed = false;

  @override
  String get name => sourceName;

  @override
  void connect() {
    if (_disposed) return;
    _running = true;
    _closeConnection();
    _liveKeys.clear();
    final generation = _generation;
    onStatusChanged?.call(SourceStatus.connecting);
    unawaited(_open(generation));
  }

  bool _active(int generation) =>
      !_disposed && _running && generation == _generation;

  Future<void> _open(int generation) async {
    try {
      final channel = connectSourceSocket(
        _uri,
        headers: const {'Origin': 'https://fssn-api.fanstudio.tech'},
      );
      if (!_active(generation)) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _lastMessageAt = DateTime.now();
      _subscription = channel.stream.listen(
        (raw) {
          if (!_active(generation)) return;
          _lastMessageAt = DateTime.now();
          _dispatch(raw);
        },
        onError: (Object error) => _failed(generation, error),
        onDone: () => _failed(generation, '连接关闭'),
        cancelOnError: true,
      );
      await channel.ready.timeout(const Duration(seconds: 20));
      if (!_active(generation)) return;
      _failures = 0;
      onStatusChanged?.call(SourceStatus.connected);
      channel.sink.add('fssnlist');
      channel.sink.add('cmtlist');
      // Upstream sends a heartbeat every 20 seconds; no catalogue polling.
      _watchdog = Timer.periodic(const Duration(seconds: 20), (_) {
        if (_active(generation) &&
            DateTime.now().difference(_lastMessageAt).inSeconds >= 70) {
          _failed(generation, '心跳超时');
        }
      });
    } catch (error) {
      _failed(generation, error);
    }
  }

  void _failed(int generation, Object error) {
    if (!_active(generation)) return;
    debugPrint('FSSN: $error');
    _closeConnection();
    onStatusChanged?.call(SourceStatus.error);
    final multiplier = 1 << (_failures++).clamp(0, 4);
    _retry = Timer(retryDelay * multiplier, () {
      if (_running && !_disposed) connect();
    });
  }

  void _closeConnection() {
    _generation++;
    _retry?.cancel();
    _retry = null;
    _watchdog?.cancel();
    _watchdog = null;
    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    if (subscription != null) unawaited(subscription.cancel());
    if (channel != null) {
      unawaited(channel.sink.close().catchError((Object _) {}));
    }
  }

  void _dispatch(dynamic raw) {
    try {
      final packet = raw is List<int>
          ? decodeApiJsonBytes(raw)
          : decodeApiJson(raw as String);
      if (packet is! Map<String, dynamic>) return;
      switch (packet['type']) {
        case 'heartbeat':
          _channel?.sink.add('ping');
          return;
        case 'pong':
          return;
        case 'initial_all':
        case 'query_response':
          for (final source in _records.keys) {
            final body = packet[source];
            if (body is Map) _accept(source, body['Data'], snapshot: true);
            _publishList(source);
          }
          return;
        case 'fssnlist_response':
        case 'cmtlist_response':
          final source = packet['type'] == 'fssnlist_response'
              ? 'fssn'
              : 'fssn-cmt';
          final rows = packet['Data'];
          if (rows is! List) return;
          for (final row in rows) {
            _accept(source, row, snapshot: true);
          }
          _publishList(source);
          return;
        case 'update':
          final source = packet['source'];
          if (source is! String || !_records.containsKey(source)) return;
          if (_accept(source, packet['Data'], snapshot: false)) {
            _publishList(source);
          }
          return;
        case 'error':
          debugPrint('FSSN: ${packet['message']}');
      }
    } catch (error) {
      debugPrint('FSSN 报文解析失败: $error');
    }
  }

  bool _accept(String source, dynamic raw, {required bool snapshot}) {
    if (raw is! Map<String, dynamic>) return false;
    final id = raw['eventId']?.toString().trim();
    final key = id != null && id.isNotEmpty ? id : raw['id']?.toString();
    final shock = DateTime.tryParse(raw['shockTime']?.toString() ?? '');
    final lat = double.tryParse(raw['latitude']?.toString() ?? '');
    final lng = double.tryParse(raw['longitude']?.toString() ?? '');
    if (key == null ||
        key.isEmpty ||
        shock == null ||
        lat == null ||
        !lat.isFinite ||
        lat.abs() > 90 ||
        lng == null ||
        !lng.isFinite ||
        lng.abs() > 180) {
      return false;
    }
    final deliveryKey = '$source|$key';
    if (snapshot && _liveKeys.contains(deliveryKey)) return false;
    final records = _records[source]!;
    final previous = records[key];
    final fingerprint = jsonEncode(raw);
    if (previous?.fingerprint == fingerprint) return false;
    final reportTime = DateTime.tryParse(raw['createTime']?.toString() ?? '');
    if (previous?.reportTime != null &&
        (reportTime == null || reportTime.isBefore(previous!.reportTime!))) {
      return false;
    }
    final decoded = FanService.decodeFssnPayload(
      raw,
      cmt: source == 'fssn-cmt',
    );
    if (decoded == null) return false;
    records.remove(key);
    records[key] = _FssnRecord(
      decoded.message.copyWith(isHistory: true),
      fingerprint,
      reportTime,
    );
    while (records.length > 50) {
      final removed = records.entries
          .reduce(
            (a, b) =>
                a.value.message.originTime.isBefore(b.value.message.originTime)
                ? a
                : b,
          )
          .key;
      records.remove(removed);
      _liveKeys.remove('$source|$removed');
    }
    if (!snapshot) {
      if (records.containsKey(key)) _liveKeys.add(deliveryKey);
      emitUnified(decoded.unified);
    }
    return true;
  }

  void _publishList(String source) {
    final rows = _records[source]!.values.map((row) => row.message).toList()
      ..sort((a, b) => b.originTime.compareTo(a.originTime));
    if (source == 'fssn') {
      onFssnListUpdated?.call(rows);
    } else {
      onCmtListUpdated?.call(rows);
    }
  }

  @override
  void disconnect() {
    _running = false;
    _closeConnection();
    onStatusChanged?.call(SourceStatus.disconnected);
  }

  @override
  void dispose() {
    if (_disposed) return;
    disconnect();
    _disposed = true;
    for (final records in _records.values) {
      records.clear();
    }
    _liveKeys.clear();
    super.dispose();
  }
}

class _FssnRecord {
  const _FssnRecord(this.message, this.fingerprint, this.reportTime);
  final QuakeMessage message;
  final String fingerprint;
  final DateTime? reportTime;
}
