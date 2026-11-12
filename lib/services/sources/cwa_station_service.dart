/// ExpTech TREM: public station CSV and gzip/base64 rts.v1 SSE.
library;

import 'dart:async';
import 'api_json_decoder.dart';
import 'dart:convert';
import '../station_history_capture.dart';
import '../foreground_station_payload.dart';
import 'trem_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'native_station_runtime.dart';
import 'native_station_display.dart';
import '../obs_automation_input_service.dart';

class CwaStation {
  final String id;
  final int code;
  final String net;
  final LatLng coordinate;
  final bool work;
  double pga;
  double pgv;
  double intensity;
  double alertIntensity;
  bool hasAlert;
  DateTime? lastUpdate;
  int? preparedGridLevel;

  CwaStation({
    required this.id,
    required this.code,
    required this.net,
    required this.coordinate,
    required this.work,
    this.pga = 0,
    this.pgv = 0,
    this.intensity = -3,
    this.alertIntensity = -3.1,
    this.hasAlert = false,
    this.lastUpdate,
  });

  double get currentIntensity => hasAlert ? alertIntensity : intensity;
}

class CwaStationService {
  static final CwaStationService _instance = CwaStationService._();
  factory CwaStationService() => _instance;
  CwaStationService._();
  @visibleForTesting
  CwaStationService.detached();

  NativeStationRuntime? _native;
  bool get nativeActive => _native != null;
  String nativeLayerSignature = '';
  String nativeStatus = '';
  List<NativeStationGrid> nativeGrids = const [];
  List<ObsStationInputSample> nativeAutomationSamples = const [];

  void _startNative() {
    _running = true;
    final runtime = _native = NativeStationRuntime();
    runtime.onFrame = (frame) {
      if (!identical(_native, runtime)) return;
      _isConnected = frame['status'] == 'connected';
      if (nativeStatus != frame['status']) {
        nativeStatus = frame['status'] as String;
        onStatusChanged?.call(_isConnected);
      }
      final rawTime = frame['dataTime'] as String?;
      dataTimeNotifier.value = rawTime == null ? null : DateTime.parse(rawTime);
      nativeLayerSignature = frame['signature'] as String;
      nativeGrids = NativeStationGrid.read(frame);
      nativeAutomationSamples = nativeStationAutomation(frame);
      _stations = ForegroundStationPayload.decodeCwa(frame['stations']);
      final rows = frame['stations'] as List;
      for (var i = 0; i < _stations.length; i++) {
        _stations[i].preparedGridLevel = rows[i]['gridLevel'] as int?;
      }
      for (final signal in frame['signals'] as List) {
        if (signal == -1) {
          onShakeExpired?.call();
        } else {
          onShakeDetected?.call(signal as int);
        }
      }
      final received = DateTime.parse(frame['receivedAt'] as String);
      StationHistoryCapture.instance.publish(
        'cwa',
        () => runtime.archive!,
        originalJsonLoader: () => runtime.original,
        receivedAt: received,
      );
      _stationController.add(_stations);
    };
    runtime.start({'kind': 'cwa', 'email': _email, 'password': _password});
  }

  static const Duration _requestTimeout = Duration(seconds: 8);
  static const Duration _streamReconnectDelay = Duration(seconds: 3);
  static const Duration _frameStaleAfter = Duration(milliseconds: 3500);
  int _rtsHostIndex = 0;
  int _metadataHostIndex = 0;

  final _stationController = StreamController<List<CwaStation>>.broadcast();
  Stream<List<CwaStation>> get stationStream => _stationController.stream;

  List<CwaStation> _stations = [];
  List<CwaStation> get stations => _stations;

  Map<String, CwaStation> _stationMap = {};

  Timer? _stationListTimer;
  Timer? _streamReconnectTimer;
  Timer? _frameWatchdogTimer;
  http.Client? _client;
  http.Client? _streamClient;
  bool _running = false;
  bool _fetchingStationList = false;
  bool _streamConnecting = false;
  bool _streamReceiving = false;
  bool _recoveringFromStaleFrame = false;
  int _runGeneration = 0;
  int _rtsHostFailures = 0;
  int _consecutiveFailures = 0;
  bool _isConnected = false;
  static const int _maxFailures = 3;

  String? _email;
  String? _password;
  void Function(bool connected)? onStatusChanged;
  void Function(int maxShindo)? onShakeDetected;
  void Function()? onShakeExpired;

  int _prevMaxAlertShindo = -1;
  bool _shake1Notified = false;
  bool _shake2Notified = false;
  DateTime? _lastRtsDataTime;
  DateTime? _lastFrameReceivedAt;
  final ValueNotifier<DateTime?> dataTimeNotifier = ValueNotifier(null);

  static int gridLevelFromInstShindo(num instShindo) {
    final value = instShindo.toDouble();
    if (value < -3.0) return -1;
    if (value == -3.0) return 0;
    if (value >= 6.5) return 20;
    return (value * 2 + 7).floor();
  }

  static int shindoFromGridLevel(int level) {
    if (level < 0) return -1;
    if (level <= 7) return 0;
    if (level <= 9) return 1;
    if (level <= 11) return 2;
    if (level <= 13) return 3;
    if (level <= 15) return 4;
    if (level <= 17) return 5;
    if (level <= 19) return 6;
    return 7;
  }

  static int shindoFromInstShindo(num instShindo) {
    return shindoFromGridLevel(gridLevelFromInstShindo(instShindo));
  }

  void setCredentials(String email, String password) {
    _email = email;
    _password = password;
  }

  bool get hasCredentials => _email != null && _password != null;
  bool get isRunning => _running;

  void start() {
    if (_running) return;
    if (NativeStationRuntime.supported) {
      _startNative();
      return;
    }
    _running = true;
    final generation = ++_runGeneration;
    _consecutiveFailures = 0;
    _rtsHostFailures = 0;
    _isConnected = false;
    _recoveringFromStaleFrame = false;
    _lastFrameReceivedAt = null;
    _client = http.Client();
    unawaited(_startTransport(generation));
  }

  Future<void> _startTransport(int generation) async {
    await _fetchStationList();
    if (!_isCurrentRun(generation)) return;
    _stationListTimer = Timer.periodic(
      const Duration(minutes: 5), (_) => unawaited(_fetchStationList()),
    );
    _frameWatchdogTimer = Timer.periodic(
      const Duration(seconds: 1), (_) => _checkFrameFreshness(generation),
    );
    unawaited(_connectRtsStream(generation));
  }

  bool _isCurrentRun(int generation) => _running && generation == _runGeneration;

  Future<void> _fetchStationList() async {
    if (!_running || _client == null || _fetchingStationList) return;
    final generation = _runGeneration;
    _fetchingStationList = true;
    try {
      for (var attempt = 0; attempt < TremProtocol.stationHosts.length; attempt++) {
        final host = TremProtocol.stationHosts[_metadataHostIndex % TremProtocol.stationHosts.length];
        try {
          final response = await _client!.get(
            Uri.parse('$host${TremProtocol.stationPath}'),
            headers: const {'Accept': 'text/csv', 'Cache-Control': 'no-cache'},
          ).timeout(_requestTimeout);
          if (!_isCurrentRun(generation)) return;
          if (response.statusCode == 200 && _applyStationCsv(utf8.decode(response.bodyBytes))) return;
        } catch (error) {
          if (!_isCurrentRun(generation)) return;
          debugPrint('TREM station catalogue error on $host: $error');
        }
        _metadataHostIndex++;
      }
    } finally {
      if (_isCurrentRun(generation)) _fetchingStationList = false;
    }
  }

  bool _applyStationCsv(String csv) {
    final entries = TremProtocol.catalogue(csv);
    if (entries.isEmpty) return false;
    _stationMap = {
      for (final s in entries) s.id:
        _stationMap[s.id]?.copyWith(code: s.code, net: s.net, work: s.work, coordinate: LatLng(s.lat, s.lon)) ??
        CwaStation(id: s.id, code: s.code, net: s.net, work: s.work, coordinate: LatLng(s.lat, s.lon)),
    };
    StationHistoryCapture.instance.restoreOriginal('cwa', {
      ...?StationHistoryCapture.instance.original('cwa'), 'metadata': csv,
    });
    return true;
  }

  void stop() {
    if (_native != null) StationHistoryCapture.instance.clearLatest('cwa');
    _native?.stop();
    _native = null;
    nativeLayerSignature = '';
    nativeStatus = '';
    nativeGrids = const [];
    nativeAutomationSamples = const [];
    final wasConnected = _isConnected;
    _running = false;
    _runGeneration++;
    _fetchingStationList = false;
    _streamConnecting = false;
    _streamReceiving = false;
    _recoveringFromStaleFrame = false;
    _stationListTimer?.cancel();
    _stationListTimer = null;
    _streamReconnectTimer?.cancel();
    _streamReconnectTimer = null;
    _frameWatchdogTimer?.cancel();
    _frameWatchdogTimer = null;
    _streamClient?.close();
    _streamClient = null;
    _client?.close();
    _client = null;
    _lastRtsDataTime = null;
    _lastFrameReceivedAt = null;
    dataTimeNotifier.value = null;
    _isConnected = false;
    _clearRuntimeState(emitStations: true);
    if (wasConnected) onStatusChanged?.call(false);
  }

  void _applyStationMetadata(Map data) {
    final newMap = <String, CwaStation>{};
    for (final entry in data.entries) {
      final id = entry.key;
      final val = entry.value;
      if (val is! Map) continue;
      final net = val['net']?.toString() ?? '';
      final work = val['work'] == true;
      final info = val['info'];
      if (info is! List || info.isEmpty) continue;
      final lastInfo = info.last;
      if (lastInfo is! Map) continue;
      final code = int.tryParse(lastInfo['code']?.toString() ?? '') ?? 0;
      final lat = double.tryParse(lastInfo['lat']?.toString() ?? '') ?? 0;
      final lon = double.tryParse(lastInfo['lon']?.toString() ?? '') ?? 0;
      if (lat == 0 && lon == 0) continue;

      final existing = _stationMap[id];
      newMap[id] =
          existing?.copyWith(
            code: code,
            net: net,
            work: work,
            coordinate: LatLng(lat, lon),
          ) ??
          CwaStation(
            id: id,
            code: code,
            net: net,
            coordinate: LatLng(lat, lon),
            work: work,
          );
    }
    if (newMap.isNotEmpty) _stationMap = newMap;
  }

  @visibleForTesting
  bool handleOriginalForTesting(String original, {bool metadata = false}) {
    if (metadata && !original.trimLeft().startsWith('{')) {
      _applyStationCsv(original);
      return false;
    }
    final data = decodeApiJson(original);
    if (data is! Map) return false;
    if (metadata) {
      _applyStationMetadata(data);
      return false;
    }
    _running = true;
    return _acceptRtsPayload(data, _runGeneration);
  }

  String get _currentRtsHost => TremProtocol.rtsHosts[_rtsHostIndex % TremProtocol.rtsHosts.length];

  void _nextRtsHost() {
    _rtsHostIndex = (_rtsHostIndex + 1) % TremProtocol.rtsHosts.length;
    _rtsHostFailures = 0;
  }

  Future<void> _connectRtsStream(int generation) async {
    if (!_isCurrentRun(generation) || _streamConnecting || _streamReceiving) {
      return;
    }

    _streamReconnectTimer?.cancel();
    _streamReconnectTimer = null;
    _streamConnecting = true;
    final host = _currentRtsHost;
    final client = http.Client();
    _streamClient?.close();
    _streamClient = client;
    var receivedFrame = false;

    try {
      final request = http.Request('GET', Uri.parse('$host${TremProtocol.rtsPath}'));
      request.headers.addAll(const {'Accept': 'text/event-stream', 'Cache-Control': 'no-cache'});
      final response = await client.send(request).timeout(_requestTimeout);
      if (!_isCurrentRun(generation) || !identical(_streamClient, client)) return;
      if (response.statusCode != 200 ||
          !(response.headers['content-type'] ?? '').contains('text/event-stream')) {
        throw StateError('TREM SSE HTTP ${response.statusCode}');
      }

      _streamConnecting = false;
      _streamReceiving = true;
      await for (final payload in TremProtocol.decode(response.stream.timeout(const Duration(seconds: 90)))) {
        if (!_isCurrentRun(generation) || !identical(_streamClient, client)) {
          return;
        }
        if (_acceptRtsPayload(payload, generation)) {
          receivedFrame = true;
          _rtsHostFailures = 0;
        }
      }
    } catch (error) {
      if (_isCurrentRun(generation) && identical(_streamClient, client)) {
        debugPrint('TREM RTS stream error on $host: $error');
      }
    } finally {
      if (_isCurrentRun(generation) && identical(_streamClient, client)) {
        _streamConnecting = false;
        _streamReceiving = false;
        _streamClient = null;
        client.close();
        _recordRtsTransportFailure(receivedFrame: receivedFrame);
        _scheduleStreamReconnect(generation);
      } else {
        client.close();
      }
    }
  }

  void _scheduleStreamReconnect(int generation, {bool immediate = false}) {
    if (!_isCurrentRun(generation) || _streamReconnectTimer?.isActive == true) {
      return;
    }
    _streamReconnectTimer = Timer(
      immediate ? Duration.zero : _streamReconnectDelay,
      () {
        _streamReconnectTimer = null;
        unawaited(_connectRtsStream(generation));
      },
    );
  }

  bool _acceptRtsPayload(Map data, int generation) {
    if (!_isCurrentRun(generation)) return false;
    final v1 = data['stations'] is Map;
    final stationData = data[v1 ? 'stations' : 'station'];
    final dataTime = _parseRtsTime(data[v1 ? 'ts' : 'time']);
    if (stationData is! Map || stationData.isEmpty || dataTime == null) {
      return false;
    }

    final last = _lastRtsDataTime;
    if (!isNewerFrameTime(last, dataTime)) return false;

    final now = DateTime.now();
    final updated = <CwaStation>[];
    for (final entry in stationData.entries) {
      final id = entry.key.toString();
      final vals = entry.value;
      if (vals is! Map) continue;
      if (v1 && vals['i'] is! num) continue;
      final existing = _stationMap[id];
      if (existing == null || !existing.work) continue;

      existing.pga =
          double.tryParse(vals['pga']?.toString() ?? '') ?? existing.pga;
      existing.pgv =
          double.tryParse(vals['pgv']?.toString() ?? '') ?? existing.pgv;
      existing.intensity =
          double.tryParse(vals['i']?.toString() ?? '') ?? existing.intensity;
      existing.alertIntensity =
          double.tryParse(vals[v1 ? 'i' : 'I']?.toString() ?? '') ?? existing.alertIntensity;
      existing.hasAlert = v1
          ? vals['alert'] == true || vals['alert'] == 1 || vals['alert'] == '1'
          : isActiveAlertValue(vals['alert']);
      existing.lastUpdate = now;
      updated.add(existing);
    }

    if (updated.isEmpty) {
      unawaited(_fetchStationList());
      return false;
    }

    StationHistoryCapture.instance.retainOriginal('cwa', 'data', data);

    updated.sort((a, b) => b.currentIntensity.compareTo(a.currentIntensity));
    _lastRtsDataTime = dataTime;
    _lastFrameReceivedAt = now;
    _recoveringFromStaleFrame = false;
    dataTimeNotifier.value = dataTime;
    _stations = updated;
    StationHistoryCapture.instance.publish(
      'cwa',
      () => ForegroundStationPayload.cwa(_stations, dataTime: dataTime),
      source: 'cwa',
      receivedAt: now,
    );
    _stationController.add(updated);
    _checkShakeNotification();
    _handleSuccess();
    return true;
  }

  void _checkFrameFreshness(int generation) {
    if (!_isCurrentRun(generation)) return;
    final lastReceived = _lastFrameReceivedAt;
    if (_stationMap.isEmpty) unawaited(_fetchStationList());
    if (lastReceived == null) return;
    if (DateTime.now().difference(lastReceived) <= _frameStaleAfter ||
        _recoveringFromStaleFrame) {
      return;
    }

    _recoveringFromStaleFrame = true;
    _markDisconnected();
    _nextRtsHost();
    _streamClient?.close();
    _streamClient = null;
    _streamConnecting = false;
    _streamReceiving = false;
    _streamReconnectTimer?.cancel();
    _streamReconnectTimer = null;
    _scheduleStreamReconnect(generation, immediate: true);
  }

  void _recordRtsTransportFailure({bool receivedFrame = false}) {
    if (receivedFrame) {
      _rtsHostFailures = 0;
      return;
    }
    _rtsHostFailures++;
    _handleFailure();
    if (_rtsHostFailures >= _maxFailures) {
      _nextRtsHost();
    }
  }

  @visibleForTesting
  static Map<String, dynamic>? decodeSseDataLine(String line) {
    // Ignore SSE metadata/blank lines without creating or disposing a parser.
    if (!line.startsWith('data:') || line.length == 5) return null;
    try {
      final decoded = decodeApiJsonEnvelope(line, JsonWireEnvelope.sseDataLine);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
    return null;
  }

  @visibleForTesting
  static bool isActiveAlertValue(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized.isNotEmpty &&
          normalized != '0' &&
          normalized != 'false' &&
          normalized != 'null';
    }
    return false;
  }

  @visibleForTesting
  static bool isNewerFrameTime(DateTime? previous, DateTime candidate) =>
      previous == null || candidate.isAfter(previous);

  void _checkShakeNotification() {
    var currentMaxLevel = -1;
    for (final s in _stations) {
      if (!s.hasAlert) continue;
      final level = gridLevelFromInstShindo(s.alertIntensity);
      if (level > currentMaxLevel) {
        currentMaxLevel = level;
      }
    }
    final currentMaxShindo = shindoFromGridLevel(currentMaxLevel);
    if (currentMaxShindo > _prevMaxAlertShindo) {
      if (currentMaxShindo >= 1 && currentMaxShindo <= 3 && !_shake1Notified) {
        _shake1Notified = true;
        onShakeDetected?.call(currentMaxShindo);
      } else if (currentMaxShindo >= 4 && !_shake2Notified) {
        _shake1Notified = true;
        _shake2Notified = true;
        onShakeDetected?.call(currentMaxShindo);
      }
    } else if (currentMaxShindo == -1 && _prevMaxAlertShindo >= 0) {
      _shake1Notified = false;
      _shake2Notified = false;
      onShakeExpired?.call();
    }
    _prevMaxAlertShindo = currentMaxShindo;
  }

  DateTime? _parseRtsTime(Object? value) {
    if (value == null) return null;
    if (value is num) return _dateTimeFromEpoch(value);
    if (value is String) {
      final numeric = num.tryParse(value);
      if (numeric != null) return _dateTimeFromEpoch(numeric);
      return DateTime.tryParse(value);
    }
    return null;
  }

  DateTime _dateTimeFromEpoch(num value) {
    final raw = value.toInt();
    final millis = raw > 100000000000 ? raw : raw * 1000;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  void _clearRuntimeState({bool emitStations = false}) {
    final hadActive =
        _prevMaxAlertShindo >= 0 || _stations.any((s) => s.hasAlert);
    _prevMaxAlertShindo = -1;
    _shake1Notified = false;
    _shake2Notified = false;
    for (final station in _stationMap.values) {
      station.pga = 0;
      station.pgv = 0;
      station.intensity = -3.1;
      station.alertIntensity = -3.1;
      station.hasAlert = false;
      station.lastUpdate = null;
    }
    _stations = _stationMap.values.toList(growable: false);
    if (emitStations) {
      _stationController.add(_stations);
    }
    if (hadActive) {
      onShakeExpired?.call();
    }
  }

  void _handleSuccess() {
    _consecutiveFailures = 0;
    if (!_isConnected) {
      _isConnected = true;
      onStatusChanged?.call(true);
    }
  }

  void _markDisconnected() {
    _consecutiveFailures = _maxFailures;
    if (_isConnected) {
      _isConnected = false;
      onStatusChanged?.call(false);
    }
  }

  void _handleFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= _maxFailures && _isConnected) {
      _isConnected = false;
      onStatusChanged?.call(false);
    }
  }
}

extension _CwaStationCopy on CwaStation {
  CwaStation copyWith({
    String? id,
    int? code,
    String? net,
    LatLng? coordinate,
    bool? work,
  }) {
    return CwaStation(
      id: id ?? this.id,
      code: code ?? this.code,
      net: net ?? this.net,
      coordinate: coordinate ?? this.coordinate,
      work: work ?? this.work,
      pga: pga,
      pgv: pgv,
      intensity: intensity,
      alertIntensity: alertIntensity,
      hasAlert: hasAlert,
      lastUpdate: lastUpdate,
    );
  }
}
