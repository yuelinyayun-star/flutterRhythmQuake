// Frozen source before native migration. Only import paths and an injected test clock differ.
/// Wolfx SeisJS 社区地震观测服务
///
/// SeisJS 利用移动设备加速度计进行地震观测，通过 WebSocket 实时推送。
/// 每条消息代表一个设备上报的实时加速度/震度数据。
///
/// WebSocket: wss://seisjs.wolfx.jp/all_seis
///
/// 参考: https://wolfx.jp/seisjs

library;

import 'dart:async';
import 'package:flutterrhythmquake/services/sources/api_json_decoder.dart';
import 'package:flutterrhythmquake/services/station_history_capture.dart';
import 'package:flutterrhythmquake/services/foreground_station_payload.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/services/sources/seisjs_service.dart' show SeisJsStation;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutterrhythmquake/services/sources/source_socket.dart';

@visibleForTesting
double seisJsRealtimeIntensityFromJson(Map<dynamic, dynamic> json) {
  return double.tryParse(json['Intensity']?.toString() ?? '') ?? 0;
}

class SeisJsService {
  static final SeisJsService _instance = SeisJsService._();
  factory SeisJsService() => _instance;
  SeisJsService._() : this.detached();

  @visibleForTesting
  SeisJsService.detached({WebSocketChannel Function(Uri)? socketFactory})
    : _socketFactory = socketFactory ?? ((uri) => connectSourceSocket(uri));

  final WebSocketChannel Function(Uri) _socketFactory;

  static const String _wsUrl = 'wss://seisjs.wolfx.jp/all_seis';

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  int _serial = 0;
  Timer? _heartbeatTimer;
  Timer? _expireTimer;
  bool _running = false;
  bool _hasRealtimeData = false;

  final _controller = StreamController<List<SeisJsStation>>.broadcast();
  Stream<List<SeisJsStation>> get stationStream => _controller.stream;
  final ValueNotifier<DateTime?> dataTimeNotifier = ValueNotifier(null);

  final Map<String, SeisJsStation> _stations = {};
  List<SeisJsStation> get stations => List.unmodifiable(_stations.values);

  void Function(bool connected)? onStatusChanged;

  void connect() {
    if (_running) return;
    _running = true;
    _expireTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_running) _expireStaleStations();
    });
    unawaited(_doConnect());
  }

  void disconnect() {
    _running = false;
    ++_serial;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _expireTimer?.cancel();
    _expireTimer = null;
    _closeSocket();
    _hasRealtimeData = false;
    dataTimeNotifier.value = null;
    onStatusChanged?.call(false);
  }

  bool _current(WebSocketChannel channel, int serial) =>
      _running && serial == _serial && identical(_channel, channel);

  Future<void> _doConnect() async {
    if (!_running) return;
    final serial = ++_serial;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _closeSocket();
    try {
      final channel = _socketFactory(Uri.parse(_wsUrl));
      _channel = channel;
      _subscription = channel.stream.listen(
        (data) {
          if (_current(channel, serial)) _handleMessage(data);
        },
        onDone: () {
          if (_current(channel, serial)) _failed(serial);
        },
        onError: (err) {
          if (_current(channel, serial)) _failed(serial);
        },
        cancelOnError: true,
      );
      await channel.ready.timeout(const Duration(seconds: 20));
      if (!_current(channel, serial)) return;
      debugPrint('SeisJS: 已连接');
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!_current(channel, serial)) return;
        try {
          channel.sink.add('ping');
        } catch (_) {
          _failed(serial);
        }
      });
    } catch (e) {
      _failed(serial, seconds: 10);
    }
  }

  void _failed(int serial, {int seconds = 5}) {
    if (!_running || serial != _serial) return;
    final nextSerial = ++_serial;
    _closeSocket();
    _hasRealtimeData = false;
    dataTimeNotifier.value = null;
    onStatusChanged?.call(false);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      if (!_running || nextSerial != _serial) return;
      _reconnectTimer = null;
      unawaited(_doConnect());
    });
  }

  void _closeSocket() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    if (subscription != null) unawaited(subscription.cancel());
    if (channel != null) {
      unawaited(channel.sink.close().catchError((Object _) {}));
    }
  }

  void dispose() {
    disconnect();
    unawaited(_controller.close());
    dataTimeNotifier.dispose();
  }

  DateTime Function() clock = DateTime.now;
  void handleOriginal(List<int> bytes) => _handleMessage(bytes);
  void expireOriginal() => _expireStaleStations();

  void _handleMessage(dynamic text) {
    try {
      final json = text is List<int>
          ? decodeApiJsonBytes(text)
          : decodeApiJson(text as String);
      if (json is! Map) return;

      final type = json['type']?.toString() ?? '';
      if (type == 'heartbeat' || type == 'pong') return;

      final id = type;
      if (id.isEmpty) return;

      final lat = double.tryParse(json['latitude']?.toString() ?? '') ?? 0;
      final lon = double.tryParse(json['longitude']?.toString() ?? '') ?? 0;
      if (lat == 0 && lon == 0) return;

      final shindo = int.tryParse(json['Shindo']?.toString() ?? '') ?? 0;
      final calcShindo =
          double.tryParse(json['CalcShindo']?.toString() ?? '') ?? -3.0;
      final intensity = seisJsRealtimeIntensityFromJson(json);
      final pga = double.tryParse(json['PGA']?.toString() ?? '') ?? 0;
      final pgv = double.tryParse(json['PGV']?.toString() ?? '') ?? 0;
      final maxPga = double.tryParse(json['Max_PGA']?.toString() ?? '') ?? 0;
      final maxPgv = double.tryParse(json['Max_PGV']?.toString() ?? '') ?? 0;
      final maxIntensity =
          double.tryParse(json['Max_Intensity']?.toString() ?? '') ?? 0;
      final region = json['region']?.toString() ?? '';
      final isDesktop = json['is_desktop'] == true;
      final updateAt = json['update_at']?.toString();

      final dataTime = updateAt != null ? DateTime.tryParse(updateAt) : null;
      final existing = _stations[id];
      if (existing != null) {
        existing.shindo = shindo;
        existing.calcShindo = calcShindo;
        existing.intensity = intensity;
        existing.pga = pga;
        existing.pgv = pgv;
        existing.maxPga = maxPga;
        existing.maxPgv = maxPgv;
        existing.maxIntensity = maxIntensity;
        existing.lastUpdate = dataTime ?? clock();
      } else {
        _stations[id] = SeisJsStation(
          id: id,
          region: region,
          coordinate: LatLng(lat, lon),
          shindo: shindo,
          calcShindo: calcShindo,
          intensity: intensity,
          pga: pga,
          pgv: pgv,
          maxPga: maxPga,
          maxPgv: maxPgv,
          maxIntensity: maxIntensity,
          isDesktop: isDesktop,
          lastUpdate: dataTime ?? clock(),
        );
      }
      dataTimeNotifier.value = dataTime ?? _stations[id]?.lastUpdate;
      StationHistoryCapture.instance.retainOriginal('seisjs', 'data', json);
      if (!_hasRealtimeData) {
        _hasRealtimeData = true;
        onStatusChanged?.call(true);
      }

      StationHistoryCapture.instance.publish(
        'seisjs',
        () => ForegroundStationPayload.seisjs(
          stations,
          dataTime: dataTimeNotifier.value,
        ),
        source: 'seisjs',
      );
      _controller.add(List.of(_stations.values));
    } catch (e) {
      // skip malformed messages
    }
  }

  void _expireStaleStations() {
    final now = clock();
    final stale = <String>[];
    for (final entry in _stations.entries) {
      if (entry.value.lastUpdate == null) continue;
      if (now.difference(entry.value.lastUpdate!).inSeconds > 30) {
        stale.add(entry.key);
      }
    }
    for (final id in stale) {
      _stations.remove(id);
    }
    if (stale.isNotEmpty) {
      StationHistoryCapture.instance.publish(
        'seisjs',
        () => ForegroundStationPayload.seisjs(
          stations,
          dataTime: dataTimeNotifier.value,
        ),
      );
      _controller.add(List.of(_stations.values));
    }
  }
}
