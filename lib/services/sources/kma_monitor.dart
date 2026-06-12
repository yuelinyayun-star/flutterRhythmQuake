import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class KmaStation {
  final int id;
  final LatLng coordinate;
  int intensity;
  DateTime? lastUpdate;

  List<int> recentLevel = [];
  static const int recentSeconds = 60;
  static const int activitySeconds = 12;

  int activityLevel = -1;
  int holdLevel = -1;
  int ascend = 0;
  bool isActive = false;
  Timer? _activeTimer;

  bool get hasAlert => isActive || intensity >= 1;

  KmaStation({
    required this.id,
    required this.coordinate,
    this.intensity = -3,
    this.lastUpdate,
  }) {
    holdLevel = intensity + 2;
    activityLevel = intensity + 2;
  }

  void update(int newIntensity) {
    intensity = newIntensity;
    final level = newIntensity + 2;
    recentLevel.insert(0, level);
    if (recentLevel.length > recentSeconds * 4) {
      recentLevel = recentLevel.sublist(0, recentSeconds * 4);
    }

    if (newIntensity == -3) {
      activityLevel = -1;
      holdLevel = -1;
      ascend = 0;
      isActive = false;
      _activeTimer?.cancel();
      return;
    }

    final activityArr = recentLevel.length >= activitySeconds
        ? recentLevel.sublist(0, activitySeconds)
        : recentLevel;
    final pastArr = recentLevel.length > activitySeconds
        ? recentLevel.sublist(activitySeconds)
        : <int>[];

    activityLevel = activityArr.fold(-1, max);

    final validPastCount = pastArr.where((l) => l >= 0).length;
    final pastLevel = validPastCount >= activitySeconds * 3
        ? pastArr.fold(-1, max)
        : -1;

    ascend = pastLevel >= 0
        ? activityArr.where((l) => l > pastLevel).length
        : 0;

    holdLevel = recentLevel.isNotEmpty
        ? recentLevel.sublist(0, min(recentLevel.length, 4)).fold(-1, max)
        : -1;
  }

  void setActive([void Function()? onExpired]) {
    isActive = true;
    _activeTimer?.cancel();
    _activeTimer = Timer(const Duration(milliseconds: 12500), () {
      isActive = false;
      onExpired?.call();
    });
  }

  void clearActive() {
    isActive = false;
    _activeTimer?.cancel();
  }

  void dispose() {
    _activeTimer?.cancel();
  }
}

class KmaMonitorService {
  static final KmaMonitorService _instance = KmaMonitorService._internal();
  factory KmaMonitorService() => _instance;
  KmaMonitorService._internal();

  static const List<String> _wsUrls = [
    'wss://ws.fanstudio.tech:443/kma-station',
    'wss://ws.fanstudio.hk:443/kma-station',
  ];

  List<KmaStation> _stations = [];
  List<KmaStation> get stations => _stations;

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _reconnectAttempts = 0;
  int _currentUrlIndex = 0;
  bool _isConnected = false;
  DateTime _lastMessageAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastDataTimestamp;
  DateTime _lastInvalidMmiLogAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _prevMaxActiveMmi = -1;
  bool get isConnected => _isConnected;

  List<List<int>> _adjStationIds = [];
  List<List<double>> _distMatrix = [];
  int _lastStationCount = 0;
  int _sensitivity = 2;

  void setSensitivity(int level) {
    _sensitivity = level.clamp(1, 3);
  }

  final _stationController = StreamController<List<KmaStation>>.broadcast();
  Stream<List<KmaStation>> get stationStream => _stationController.stream;

  void Function(int maxMmi)? onShakeDetected;
  void Function()? onShakeExpired;

  void Function(bool connected)? onStatusChanged;

  void connect() {
    if (_channel != null) return;
    _doConnect(_currentUrlIndex);
  }

  void _doConnect(int urlIndex) {
    if (urlIndex >= _wsUrls.length) {
      debugPrint('KMA: 所有WebSocket地址连接失败，${_reconnectAttempts + 1}秒后重试');
      onStatusChanged?.call(false);
      _scheduleReconnect(10, _currentUrlIndex);
      return;
    }

    try {
      final uri = Uri.parse(_wsUrls[urlIndex]);
      _channel = WebSocketChannel.connect(uri);

      _isConnected = true;
      _currentUrlIndex = urlIndex;
      _lastMessageAt = DateTime.now();
      _reconnectAttempts = 0;
      onStatusChanged?.call(true);
      debugPrint('KMA: WebSocket已连接 -> ${_wsUrls[urlIndex]}');

      _startHeartbeat();

      _channel!.stream.listen(
        (data) {
          _lastMessageAt = DateTime.now();
          _handleMessage(data, urlIndex);
        },
        onError: (error) {
          debugPrint('KMA WebSocket错误: $error');
          _reconnect(urlIndex);
        },
        onDone: () {
          debugPrint('KMA WebSocket连接关闭');
          _reconnect(urlIndex);
        },
      );
    } catch (e) {
      debugPrint('KMA WebSocket连接失败: $e');
      _doConnect(urlIndex + 1);
    }
  }

  void _handleMessage(dynamic data, int urlIndex) {
    try {
      final message = json.decode(data.toString());
      final type = message['type'] as String?;

      switch (type) {
        case 'initial_stations':
        case 'kma_stations_update':
          _handleStationList(message['stations']);
          break;
        case 'initial':
        case 'update':
          _handleData(message['Data']);
          break;
        case 'heartbeat':
          _channel?.sink.add('ping');
          break;
        case 'error':
          debugPrint('KMA FAN 服务端错误: ${message['message']}');
          final errorMsg = message['message']?.toString() ?? '';
          if (errorMsg.contains('连接数超限')) {
            _heartbeatTimer?.cancel();
            _channel?.sink.close();
            _channel = null;
            _isConnected = false;
            onStatusChanged?.call(false);
            final nextUrlIndex = (urlIndex + 1) % _wsUrls.length;
            _scheduleReconnect(3, nextUrlIndex);
          }
          break;
        case 'pong':
          break;
      }
    } catch (e) {
      debugPrint('KMA消息解析错误: $e');
    }
  }

  void _handleStationList(dynamic listData) {
    if (listData is! List || listData.isEmpty) return;

    final newStations = <KmaStation>[];
    int id = 0;
    for (var item in listData) {
      if (item is! Map) continue;
      final lat = (item['latitude'] as num?)?.toDouble();
      final lng = (item['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      newStations.add(KmaStation(id: id, coordinate: LatLng(lat, lng)));
      id++;
    }

    if (newStations.isNotEmpty) {
      _stations = newStations;
      debugPrint('KMA: 收到 ${_stations.length} 个测站');
    }
  }

  void _handleData(dynamic data) {
    if (data is! Map) return;

    final mmi = data['mmi'] as List?;
    if (mmi == null) return;
    if (mmi.length != _stations.length) {
      _logRejectedFrame('length mismatch ${mmi.length}/${_stations.length}');
      return;
    }

    final parsed = <int>[];
    for (final raw in mmi) {
      final val = _parseMmi(raw);
      if (val == null) {
        _logRejectedFrame('invalid value $raw');
        return;
      }
      if (val == -3) {
        _logRejectedFrame('contains -3');
        return;
      }
      parsed.add(val);
    }

    final now = DateTime.now();
    _applyDataGap(_parseTimestamp(data['timestamp']));

    for (int i = 0; i < parsed.length; i++) {
      final val = parsed[i];
      _stations[i].update(val);
      _stations[i].lastUpdate = now;
    }

    _processShakeDetection();

    _stationController.add(List.unmodifiable(_stations));
  }

  int? _parseMmi(dynamic raw) {
    final num? value = switch (raw) {
      num v => v,
      String s => num.tryParse(s),
      _ => null,
    };
    if (value == null || !value.isFinite) return null;

    final mmi = value.round();
    if (mmi < -3 || mmi > 11) return null;
    return mmi;
  }

  DateTime? _parseTimestamp(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  void _applyDataGap(DateTime? timestamp) {
    if (timestamp == null) return;
    final previous = _lastDataTimestamp;
    _lastDataTimestamp = timestamp;
    if (previous == null) return;

    final diffMs = timestamp.difference(previous).inMilliseconds;
    if (diffMs <= 1000) return;

    var missingFrames = (diffMs / 1000).round() - 1;
    if (missingFrames <= 0) return;
    if (missingFrames > KmaStation.recentSeconds) {
      missingFrames = KmaStation.recentSeconds;
    }

    final noData = List<int>.filled(missingFrames, -1);
    final stale = diffMs > 10000;
    for (final station in _stations) {
      station.recentLevel.insertAll(0, noData);
      if (station.recentLevel.length > KmaStation.recentSeconds) {
        station.recentLevel = station.recentLevel.sublist(
          0,
          KmaStation.recentSeconds,
        );
      }
      if (stale) {
        station.clearActive();
        station.ascend = 0;
        station.activityLevel = -1;
        station.holdLevel = -1;
      }
    }
    if (stale) {
      _checkShakeState();
    }
  }

  void _logRejectedFrame(String reason) {
    final now = DateTime.now();
    if (now.difference(_lastInvalidMmiLogAt) <= const Duration(seconds: 30)) {
      return;
    }
    _lastInvalidMmiLogAt = now;
    debugPrint('KMA: rejected frame ($reason)');
  }

  void _buildAdjacency() {
    if (_stations.isEmpty) return;
    _adjStationIds = List.generate(_stations.length, (_) => <int>[]);
    _distMatrix = List.generate(
      _stations.length,
      (_) => List.filled(_stations.length, 0.0),
    );

    for (int i = 0; i < _stations.length; i++) {
      final distances = <MapEntry<int, double>>[];
      for (int j = 0; j < _stations.length; j++) {
        if (i == j) continue;
        final d = _haversine(
          _stations[i].coordinate.latitude,
          _stations[i].coordinate.longitude,
          _stations[j].coordinate.latitude,
          _stations[j].coordinate.longitude,
        );
        _distMatrix[i][j] = d;
        if (d <= 30) {
          distances.add(MapEntry(j, d));
        }
      }
      distances.sort((a, b) => a.value.compareTo(b.value));
      _adjStationIds[i] = distances.take(6).map((e) => e.key).toList();
    }
    _lastStationCount = _stations.length;
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  void _processShakeDetection() {
    if (_stations.isEmpty) return;
    if (_stations.length != _lastStationCount) {
      _buildAdjacency();
    }

    final activeStations = <KmaStation>{};

    for (int i = 0; i < _stations.length; i++) {
      final station = _stations[i];
      bool flag = false;

      if (station.isActive && station.ascend > 0) {
        flag = true;
      } else if (station.isActive || station.ascend > 0) {
        if (i < _adjStationIds.length && _adjStationIds[i].isNotEmpty) {
          final nearbyIds = _adjStationIds[i];
          final nearbyStations = nearbyIds
              .where((id) => id < _stations.length)
              .map((id) => _stations[id])
              .toList();

          final nearbyActive = nearbyStations
              .where((s) => s.isActive || s.ascend > 0)
              .toList();

          final nearbyLevels = nearbyActive
              .map((s) => s.activityLevel)
              .toList();
          final nearbyAscends = nearbyStations.map((s) => s.ascend).toList();
          final nearbyNum = nearbyStations.length;

          final countInt1 = nearbyLevels.where((l) => l >= 3).length;
          final countInt2 = nearbyLevels.where((l) => l >= 4).length;
          final countAsc1 = nearbyAscends.where((a) => a >= 1).length;
          final countAsc2 = nearbyAscends.where((a) => a >= 2).length;

          switch (_sensitivity) {
            case 1:
              flag =
                  countInt1 >= max(0.6 * nearbyNum, 4).ceil() ||
                  countInt2 >= max(0.2 * nearbyNum, 2).ceil() ||
                  countAsc2 >= max(0.7 * nearbyNum, 4).ceil();
              break;
            case 3:
              flag =
                  countInt1 >= max(0.5 * nearbyNum, 3).ceil() ||
                  countInt2 >= max(0.15 * nearbyNum, 2).ceil() ||
                  countAsc2 >= max(0.6 * nearbyNum, 4).ceil() ||
                  countAsc1 >= max(0.8 * nearbyNum, 5).ceil();
              break;
            default:
              flag =
                  countInt1 >= max(0.5 * nearbyNum, 3).ceil() ||
                  countInt2 >= max(0.15 * nearbyNum, 2).ceil() ||
                  countAsc2 >= max(0.6 * nearbyNum, 4).ceil();
          }
        }
      }

      if (flag) {
        for (final id
            in (i < _adjStationIds.length ? _adjStationIds[i] : <int>[])) {
          if (id < _stations.length) {
            final neighbor = _stations[id];
            if ((neighbor.isActive || neighbor.ascend > 0) &&
                !activeStations.contains(neighbor)) {
              neighbor.setActive(_checkShakeState);
              activeStations.add(neighbor);
            }
          }
        }
        if (!activeStations.contains(station)) {
          station.setActive(_checkShakeState);
          activeStations.add(station);
        }
      }
    }

    _checkShakeState();
  }

  void _checkShakeState() {
    int currentMaxMmi = -1;
    for (final s in _stations) {
      if (s.isActive && s.intensity > currentMaxMmi) {
        currentMaxMmi = s.intensity;
      }
    }

    if (currentMaxMmi >= 1 && currentMaxMmi > _prevMaxActiveMmi) {
      onShakeDetected?.call(currentMaxMmi);
    } else if (currentMaxMmi < 1 && _prevMaxActiveMmi >= 1) {
      onShakeExpired?.call();
    }
    _prevMaxActiveMmi = currentMaxMmi;
  }

  void _reconnect(int failedUrlIndex) {
    _heartbeatTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    onStatusChanged?.call(false);
    _reconnectAttempts++;
    final nextUrlIndex = (failedUrlIndex + 1) % _wsUrls.length;
    _scheduleReconnect(10, nextUrlIndex);
  }

  void _scheduleReconnect(int seconds, int nextUrlIndex) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _doConnect(nextUrlIndex);
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_channel == null) return;
      final idle = DateTime.now().difference(_lastMessageAt).inSeconds;
      if (idle > 70) {
        debugPrint('KMA: 心跳超时，触发重连');
        _reconnect(_currentUrlIndex);
        return;
      }
      try {
        _channel!.sink.add('ping');
      } catch (_) {}
    });
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }

  void dispose() {
    disconnect();
    _stationController.close();
    for (final s in _stations) {
      s.dispose();
    }
  }
}
