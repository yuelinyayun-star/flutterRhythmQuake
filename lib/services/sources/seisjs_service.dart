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
import 'api_json_decoder.dart';
import '../station_history_capture.dart';
import '../foreground_station_payload.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'source_socket.dart';
import 'native_station_runtime.dart';
import 'native_station_display.dart';
import '../obs_automation_input_service.dart';

@visibleForTesting
double seisJsRealtimeIntensityFromJson(Map<dynamic, dynamic> json) {
  return double.tryParse(json['Intensity']?.toString() ?? '') ?? 0;
}

class SeisJsStation {
  final String id;
  final String region;
  final LatLng coordinate;
  int shindo;
  double calcShindo;
  double intensity;
  double pga;
  double pgv;
  double maxPga;
  double maxPgv;
  double maxIntensity;
  bool isDesktop;
  DateTime? lastUpdate;
  int? preparedMapLevel;
  bool? preparedMapActive;

  SeisJsStation({
    required this.id,
    required this.region,
    required this.coordinate,
    this.shindo = 0,
    this.calcShindo = -3.0,
    this.intensity = 0,
    this.pga = 0,
    this.pgv = 0,
    this.maxPga = 0,
    this.maxPgv = 0,
    this.maxIntensity = 0,
    this.isDesktop = false,
    this.lastUpdate,
  });
}

/// Selections prepared by the native source; only two display rows leave it.
class SeisJsPreparedSummary {
  const SeisJsPreparedSummary(this.selected, this.maximum);
  final SeisJsStation? selected;
  final SeisJsStation? maximum;
}

class SeisJsService {
  static final SeisJsService _instance = SeisJsService._();
  factory SeisJsService() => _instance;
  SeisJsService._() : this.detached(useNative: true);

  @visibleForTesting
  SeisJsService.detached({
    WebSocketChannel Function(Uri)? socketFactory,
    bool useNative = false,
    Map<String, Object?> nativeSettings = const {},
  }) : _socketFactory = socketFactory ?? ((uri) => connectSourceSocket(uri)),
       _useNative = useNative,
       _nativeSettings = nativeSettings;

  final WebSocketChannel Function(Uri) _socketFactory;
  final bool _useNative;
  final Map<String, Object?> _nativeSettings;
  NativeStationRuntime? _native;
  bool get nativeActive => _native != null;
  String nativeLayerSignature = '';
  String nativeStatus = '';
  @visibleForTesting
  int nativeFrameCount = 0;
  List<SeisJsStation> _nativeViews = const [];
  List<ObsStationInputSample> nativeAutomationSamples = const [];
  SeisJsPreparedSummary? nativeSummary;

  void _startNative() {
    final runtime = _native = NativeStationRuntime();
    runtime.onFrame = (frame) {
      if (!identical(runtime, _native)) return;
      final status = frame['status'] as String;
      nativeFrameCount = frame['frames'] as int;
      if (nativeStatus != status) {
        nativeStatus = status;
        onStatusChanged?.call(status == 'connected');
      }
      final rawTime = frame['dataTime'] as String?;
      dataTimeNotifier.value = rawTime == null ? null : DateTime.parse(rawTime);
      nativeLayerSignature = frame['signature'] as String;
      nativeAutomationSamples = nativeStationAutomation(frame);
      final rows = frame['stations'] as List;
      _nativeViews = ForegroundStationPayload.decodeSeisJs(rows);
      for (var i = 0; i < _nativeViews.length; i++) {
        _nativeViews[i].preparedMapLevel = rows[i]['mapLevel'] as int;
        _nativeViews[i].preparedMapActive = rows[i]['mapActive'] as bool;
      }
      SeisJsStation? bind(dynamic row) => row == null
          ? null
          : ForegroundStationPayload.decodeSeisJs([row]).single;
      nativeSummary = SeisJsPreparedSummary(
        bind(frame['summary']['selected']),
        bind(frame['summary']['max']),
      );
      final received = DateTime.parse(frame['receivedAt'] as String);
      if (frame['dataChanged'] == true) {
        StationHistoryCapture.instance.publish(
          'seisjs',
          () => runtime.archive!,
          originalJsonLoader: () => runtime.original,
          receivedAt: received,
        );
      }
      _controller.add(_nativeViews);
    };
    runtime.start({'kind': 'seisjs', ..._nativeSettings});
  }

  @visibleForTesting
  void handleOriginalForTesting(List<int> bytes, DateTime clock) {
    if (_native case final runtime?) {
      runtime.injectOriginal(bytes, clock);
    } else {
      _handleMessage(bytes);
    }
  }

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
  List<SeisJsStation> get stations =>
      nativeActive ? _nativeViews : List.unmodifiable(_stations.values);

  void Function(bool connected)? onStatusChanged;

  void connect() {
    if (_running) return;
    _running = true;
    if (_useNative && NativeStationRuntime.supported) {
      _startNative();
      return;
    }
    _expireTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_running) _expireStaleStations();
    });
    unawaited(_doConnect());
  }

  void disconnect() {
    if (_native != null) {
      StationHistoryCapture.instance.clearLatest('seisjs');
      _native!.stop();
      _native = null;
      _nativeViews = const [];
      nativeSummary = null;
      nativeLayerSignature = '';
      nativeStatus = '';
      nativeAutomationSamples = const [];
    }
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
        existing.lastUpdate = dataTime ?? DateTime.now();
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
          lastUpdate: dataTime ?? DateTime.now(),
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
