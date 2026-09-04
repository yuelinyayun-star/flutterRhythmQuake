import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../models/cenc_ir_data.dart';
import '../../models/source_status.dart';
import '../../models/unified_quake_data.dart';
import '../quake_event_adapter.dart';
import 'base_source.dart';

class NowQuakeCencIntensityService extends BaseSourceService {
  static const String preferenceKey =
      'api_source_nowquake_cenc_intensity_enabled';
  static const String _baseUrl = 'https://api-cencint-public.nowquake.cn';
  static const String _socketUrl =
      'wss://api-cencint-public.nowquake.cn/websocket';

  @override
  String get name => 'NowQuake';

  void Function(CencIrData data)? onCencIrData;
  void Function(List<Map<String, dynamic>> items)? onCencIrListUpdated;
  void Function()? onListAvailabilityChanged;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _reconnectTimer;
  Timer? _watchdogTimer;
  int _connectionSerial = 0;
  int _retrySeconds = 3;
  bool _manualClose = false;
  bool _receivedSocketPacket = false;
  DateTime _lastMessageAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<String, Map<String, dynamic>> _summariesById = {};
  final Map<String, _NowQuakeDetailCacheEntry> _detailCache = {};
  DateTime? _lastListFetchAt;
  int? _listLoadingSerial;

  bool _listRequestCompleted = false;
  bool _listRequestSucceeded = false;

  bool get hasCompletedListRequest => _listRequestCompleted;
  bool get hasUsableList => _listRequestSucceeded && _summariesById.isNotEmpty;

  @override
  void connect() {
    if (_channel != null) return;
    _manualClose = false;
    _retrySeconds = 3;
    _reconnectTimer?.cancel();
    final serial = ++_connectionSerial;
    onStatusChanged?.call(SourceStatus.connecting);
    unawaited(_refreshListIfNeeded(serial));
    _openSocket(serial);
  }

  void _openSocket(int serial) {
    if (_manualClose || serial != _connectionSerial) return;
    final channel = WebSocketChannel.connect(Uri.parse(_socketUrl));
    _channel = channel;
    _receivedSocketPacket = false;
    _lastMessageAt = DateTime.now();

    _socketSubscription = channel.stream.listen(
      (raw) {
        if (!_isCurrent(channel, serial)) return;
        _lastMessageAt = DateTime.now();
        _markSocketHealthy(serial);
        _handleSocketMessage(raw);
      },
      onError: (Object error) {
        if (!_isCurrent(channel, serial)) return;
        _log('WebSocket 错误: $error');
        _handleFailure(serial);
      },
      onDone: () {
        if (!_isCurrent(channel, serial)) return;
        _log('WebSocket 连接关闭');
        _handleFailure(serial);
      },
      cancelOnError: true,
    );

    unawaited(
      channel.ready
          .timeout(const Duration(seconds: 10))
          .then<void>((_) {
            if (!_isCurrent(channel, serial)) return;
            _log('WebSocket 已打开，等待服务器首包');
            _startWatchdog(serial);
          })
          .catchError((Object error) {
            if (!_isCurrent(channel, serial)) return;
            _log('WebSocket 握手失败: $error');
            _handleFailure(serial);
          }),
    );
  }

  bool _isCurrent(WebSocketChannel channel, int serial) {
    return !_manualClose &&
        serial == _connectionSerial &&
        identical(_channel, channel);
  }

  void _markSocketHealthy(int serial) {
    if (_receivedSocketPacket) return;
    _receivedSocketPacket = true;
    _retrySeconds = 3;
    onStatusChanged?.call(SourceStatus.connected);
    _log('WebSocket 首包已接收');
    unawaited(_refreshListIfNeeded(serial));
  }

  void _handleSocketMessage(dynamic raw) {
    try {
      final text = raw is List<int> ? utf8.decode(raw) : raw.toString();
      final decoded = jsonDecode(text);
      if (decoded is! Map) return;
      final data = Map<String, dynamic>.from(decoded);
      final type = data['type']?.toString() ?? '';
      if (type == 'heartbeat') return;
      if (type != 'data') return;

      final detail = CencIrData.fromNowQuakeJson(data);
      final hasDrawableStation = detail.instrumentIntensities.any(
        (station) => station.hasUsableCoordinate,
      );
      if (detail.reportId.isEmpty || !hasDrawableStation) {
        _log('忽略缺少事件ID或有效测站坐标的推送');
        return;
      }
      _detailCache[detail.reportId] = _NowQuakeDetailCacheEntry(
        detail,
        DateTime.now(),
      );
      onCencIrData?.call(detail);
      final infoEvent = unifiedInfoFromJson(data);
      if (infoEvent != null) emitUnified(infoEvent);
      final summary = summaryFromJson(data);
      _summariesById[detail.reportId] = summary;
      _listRequestSucceeded = true;
      _emitSummaryList();
      onListAvailabilityChanged?.call();
    } catch (error) {
      _log('WebSocket 数据解析失败: $error');
    }
  }

  @visibleForTesting
  void handleSocketMessageForTest(dynamic raw) => _handleSocketMessage(raw);

  Future<void> _refreshListIfNeeded(int serial) async {
    if (_listLoadingSerial == serial) return;
    final fetchedAt = _lastListFetchAt;
    if (_summariesById.isNotEmpty &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < const Duration(seconds: 120)) {
      _completeListRequest(success: true);
      _emitSummaryList();
      return;
    }
    _listLoadingSerial = serial;
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/list?pageNo=0&pageSize=20'))
          .timeout(const Duration(seconds: 15));
      if (_manualClose || serial != _connectionSerial) return;
      if (response.statusCode != 200) {
        _completeListRequest(success: false);
        _log('首次列表请求失败: HTTP ${response.statusCode}');
        return;
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List) {
        _completeListRequest(success: false);
        _log('首次列表响应格式错误');
        return;
      }
      final items = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is Map) {
          items.add(summaryFromJson(Map<String, dynamic>.from(item)));
        }
      }
      _summariesById.addEntries(
        items.map((item) => MapEntry(item['id']?.toString() ?? '', item)),
      );
      _summariesById.remove('');
      _lastListFetchAt = DateTime.now();
      _completeListRequest(success: true);
      _emitSummaryList();
      _log('首次列表已加载: ${items.length} 条');
    } catch (error) {
      if (!_manualClose && serial == _connectionSerial) {
        _completeListRequest(success: false);
        _log('首次列表请求异常: $error');
      }
    } finally {
      if (_listLoadingSerial == serial) _listLoadingSerial = null;
    }
  }

  void _completeListRequest({required bool success}) {
    _listRequestCompleted = true;
    _listRequestSucceeded = success;
    onListAvailabilityChanged?.call();
  }

  Future<CencIrData?> requestDetail(String id) async {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty || _manualClose) return null;
    final cached = _detailCache[normalizedId];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < const Duration(days: 1)) {
      return cached.data;
    }
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/event/$normalizedId'))
          .timeout(const Duration(seconds: 15));
      if (_manualClose) return null;
      if (response.statusCode != 200) {
        _log('事件详情请求失败: id=$normalizedId HTTP ${response.statusCode}');
        return null;
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) return null;
      final detail = CencIrData.fromNowQuakeJson(
        Map<String, dynamic>.from(decoded),
      );
      if (detail.reportId.isEmpty) return null;
      _detailCache[detail.reportId] = _NowQuakeDetailCacheEntry(
        detail,
        DateTime.now(),
      );
      return detail;
    } catch (error) {
      _log('事件详情请求异常: id=$normalizedId $error');
      return null;
    }
  }

  static Map<String, dynamic> summaryFromJson(Map<String, dynamic> json) {
    final id = json['eq_id']?.toString() ?? '';
    final location = json['hypocenter']?.toString() ?? '';
    final magnitude = json['magnitude'];
    return <String, dynamic>{
      'id': id,
      'uniEventId': id,
      'oriTime': json['happen_time']?.toString() ?? '',
      'shockTime': json['happen_time']?.toString() ?? '',
      'gmtCreate': json['update_time']?.toString() ?? '',
      'locName': location,
      'nameByInfo': location.isEmpty
          ? 'CENC 烈度速报'
          : '$location${magnitude == null ? '' : '$magnitude级地震'}',
      'magnitude': magnitude,
      'focDepth': json['depth'],
      'epiLat': json['latitude'],
      'epiLon': json['longitude'],
      'maxIntensity': json['maxintensity'],
      'maxForecastIntensity': json['maxforecastintensity'],
      '_source': 'nowquake',
    };
  }

  static UnifiedQuakeData? unifiedInfoFromJson(Map<String, dynamic> json) {
    final eventId = json['eq_id']?.toString().trim() ?? '';
    if (eventId.isEmpty) return null;

    final stations = json['stations'];
    double? stationMaxIntensity;
    if (stations is List) {
      for (final station in stations) {
        if (station is! Map) continue;
        final value = double.tryParse(
          (station['int'] ?? station['intensity'])?.toString() ?? '',
        );
        if (value != null &&
            value.isFinite &&
            (stationMaxIntensity == null || value > stationMaxIntensity)) {
          stationMaxIntensity = value;
        }
      }
    }

    final converted = QuakeEventAdapter.convert('cencEqlist', {
      'eventId': eventId,
      'shockTime': json['happen_time']?.toString() ?? '',
      'createTime': json['update_time']?.toString() ?? '',
      'location': json['hypocenter']?.toString() ?? '',
      'magnitude': json['magnitude'],
      'depth': json['depth'],
      'latitude': json['latitude'],
      'longitude': json['longitude'],
      'maxIntensity': json['maxintensity'] ?? stationMaxIntensity,
    }, 1);
    if (converted == null) return null;

    return converted.copyWith(
      source: 'nowQuakeCencIr',
      titleText: '中国地震台网烈度速报',
      reportNumText: '',
      apiTypeLabel: 'NowQuake',
    );
  }

  void _emitSummaryList() {
    final items =
        _summariesById.values
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
          ..sort(
            (a, b) => (b['oriTime']?.toString() ?? '').compareTo(
              a['oriTime']?.toString() ?? '',
            ),
          );
    onCencIrListUpdated?.call(items);
  }

  void _startWatchdog(int serial) {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_manualClose || serial != _connectionSerial) return;
      final idle = DateTime.now().difference(_lastMessageAt);
      if (idle <= const Duration(seconds: 90)) return;
      _log('WebSocket 超过 ${idle.inSeconds} 秒无数据，重新连接');
      _handleFailure(serial);
    });
  }

  void _handleFailure(int serial) {
    if (_manualClose || serial != _connectionSerial) return;
    _connectionSerial++;
    _closeConnection();
    onStatusChanged?.call(SourceStatus.error);
    final delay = _retrySeconds;
    _retrySeconds = (_retrySeconds + 1).clamp(3, 10);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      if (_manualClose) return;
      final nextSerial = ++_connectionSerial;
      onStatusChanged?.call(SourceStatus.connecting);
      _openSocket(nextSerial);
    });
  }

  void _closeConnection() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    unawaited(_socketSubscription?.cancel());
    _socketSubscription = null;
    try {
      unawaited(_channel?.sink.close());
    } catch (_) {}
    _channel = null;
    _receivedSocketPacket = false;
  }

  @override
  void disconnect() {
    _manualClose = true;
    _connectionSerial++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _closeConnection();
    onStatusChanged?.call(SourceStatus.disconnected);
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }

  void _log(String message) {
    // ignore: avoid_print
    print('NowQuake: $message');
  }
}

class _NowQuakeDetailCacheEntry {
  const _NowQuakeDetailCacheEntry(this.data, this.fetchedAt);

  final CencIrData data;
  final DateTime fetchedAt;
}
