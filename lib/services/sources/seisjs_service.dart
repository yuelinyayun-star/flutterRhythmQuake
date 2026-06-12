/// Wolfx SeisJS 社区地震观测服务
///
/// SeisJS 利用移动设备加速度计进行地震观测，通过 WebSocket 实时推送。
/// 每条消息代表一个设备上报的实时加速度/震度数据。
///
/// WebSocket: wss://seisjs.wolfx.jp/all_seis
///
/// 参考: https://wolfx.jp/seisjs

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class SeisJsStation {
  final String id;
  final String region;
  final LatLng coordinate;
  int shindo;
  double calcShindo;
  double pga;
  double pgv;
  double maxPga;
  double maxPgv;
  double maxIntensity;
  bool isDesktop;
  DateTime? lastUpdate;

  SeisJsStation({
    required this.id,
    required this.region,
    required this.coordinate,
    this.shindo = 0,
    this.calcShindo = -3.0,
    this.pga = 0,
    this.pgv = 0,
    this.maxPga = 0,
    this.maxPgv = 0,
    this.maxIntensity = 0,
    this.isDesktop = false,
    this.lastUpdate,
  });
}

class SeisJsService {
  static final SeisJsService _instance = SeisJsService._();
  factory SeisJsService() => _instance;
  SeisJsService._();

  static const String _wsUrl = 'wss://seisjs.wolfx.jp/all_seis';

  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _expireTimer;
  bool _running = false;

  final _controller = StreamController<List<SeisJsStation>>.broadcast();
  Stream<List<SeisJsStation>> get stationStream => _controller.stream;

  final Map<String, SeisJsStation> _stations = {};
  List<SeisJsStation> get stations => List.unmodifiable(_stations.values);

  void Function(bool connected)? onStatusChanged;

  void connect() {
    if (_running) return;
    _running = true;
    _doConnect();
  }

  void disconnect() {
    _running = false;
    _heartbeatTimer?.cancel();
    _expireTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    onStatusChanged?.call(false);
  }

  void _doConnect() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      onStatusChanged?.call(true);
      debugPrint('SeisJS: 已连接');

      _channel!.stream.listen(
        (data) {
          _handleMessage(data.toString());
        },
        onDone: () {
          debugPrint('SeisJS: 连接关闭');
          if (_running) {
            onStatusChanged?.call(false);
            Future.delayed(const Duration(seconds: 5), () {
              if (_running) _doConnect();
            });
          }
        },
        onError: (err) {
          debugPrint('SeisJS: 错误 $err');
          if (_running) {
            onStatusChanged?.call(false);
          }
        },
        cancelOnError: true,
      );

      _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _channel?.sink.add('ping');
      });

      _expireTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _expireStaleStations();
      });
    } catch (e) {
      debugPrint('SeisJS: 连接失败 $e');
      onStatusChanged?.call(false);
      if (_running) {
        Future.delayed(const Duration(seconds: 10), () {
          if (_running) _doConnect();
        });
      }
    }
  }

  void _handleMessage(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map) return;

      final type = json['type']?.toString() ?? '';
      if (type == 'heartbeat' || type == 'pong') return;

      final id = type;
      if (id.isEmpty) return;

      final lat = double.tryParse(json['latitude']?.toString() ?? '') ?? 0;
      final lon = double.tryParse(json['longitude']?.toString() ?? '') ?? 0;
      if (lat == 0 && lon == 0) return;

      final shindo = int.tryParse(json['Shindo']?.toString() ?? '') ?? 0;
      final calcShindo = double.tryParse(json['CalcShindo']?.toString() ?? '') ?? -3.0;
      final pga = double.tryParse(json['PGA']?.toString() ?? '') ?? 0;
      final pgv = double.tryParse(json['PGV']?.toString() ?? '') ?? 0;
      final maxPga = double.tryParse(json['Max_PGA']?.toString() ?? '') ?? 0;
      final maxPgv = double.tryParse(json['Max_PGV']?.toString() ?? '') ?? 0;
      final maxIntensity = double.tryParse(json['Max_Intensity']?.toString() ?? '') ?? 0;
      final region = json['region']?.toString() ?? '';
      final isDesktop = json['is_desktop'] == true;
      final updateAt = json['update_at']?.toString();

      final existing = _stations[id];
      if (existing != null) {
        existing.shindo = shindo;
        existing.calcShindo = calcShindo;
        existing.pga = pga;
        existing.pgv = pgv;
        existing.maxPga = maxPga;
        existing.maxPgv = maxPgv;
        existing.maxIntensity = maxIntensity;
        existing.lastUpdate = updateAt != null ? DateTime.tryParse(updateAt) : DateTime.now();
      } else {
        _stations[id] = SeisJsStation(
          id: id,
          region: region,
          coordinate: LatLng(lat, lon),
          shindo: shindo,
          calcShindo: calcShindo,
          pga: pga,
          pgv: pgv,
          maxPga: maxPga,
          maxPgv: maxPgv,
          maxIntensity: maxIntensity,
          isDesktop: isDesktop,
          lastUpdate: updateAt != null ? DateTime.tryParse(updateAt) : DateTime.now(),
        );
      }

      _controller.add(List.of(_stations.values));
    } catch (e) {
      // skip malformed messages
    }
  }

  void _expireStaleStations() {
    final now = DateTime.now();
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
      _controller.add(List.of(_stations.values));
    }
  }
}
