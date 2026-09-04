/// 台湾 ExpTech (TREM) 测站监测服务
///
/// 通过 ExpTech API 获取台湾地区 MEMS 强震仪的实时 PGA/PGV/震度数据。
///
/// API 端点：
/// - 认证:     POST /api/v1/auth/login
/// - 刷新:     POST /api/v1/auth/refresh
/// - Station:  GET /api/v1/trem/station
/// - 实时 RTS: GET /api/v2/trem/rts
///
/// 区域节点 SSE 主链路 + JSON 轮询备用链路 + JWT 认证

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

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

  static const String _stationPath = '/api/v1/trem/station';
  static const String _rtsPath = '/api/v2/trem/rts';
  static const String _loginPath = '/api/v1/auth/login';
  static const String _refreshPath = '/api/v1/auth/refresh';

  static const List<String> _apiHosts = ['https://api-1.exptech.dev'];

  static const List<String> _rtsHosts = [
    'https://api.lb-tpe1.exptech.dev',
    'https://api.lb-khh1.exptech.dev',
  ];
  static const Duration _requestTimeout = Duration(seconds: 8);
  static const Duration _streamReconnectDelay = Duration(seconds: 3);
  static const Duration _frameStaleAfter = Duration(milliseconds: 3500);

  int _apiHostIndex = 0;
  String get _currentHost => _apiHosts[_apiHostIndex % _apiHosts.length];

  void _nextHost() {
    _apiHostIndex = (_apiHostIndex + 1) % _apiHosts.length;
  }

  final _stationController = StreamController<List<CwaStation>>.broadcast();
  Stream<List<CwaStation>> get stationStream => _stationController.stream;

  List<CwaStation> _stations = [];
  List<CwaStation> get stations => _stations;

  Map<String, CwaStation> _stationMap = {};

  Timer? _rtsTimer;
  Timer? _stationListTimer;
  Timer? _tokenRefreshTimer;
  Timer? _streamReconnectTimer;
  Timer? _frameWatchdogTimer;
  HttpClient? _client;
  HttpClient? _streamClient;
  bool _running = false;
  bool _fetchingRts = false;
  bool _fetchingStationList = false;
  bool _streamConnecting = false;
  bool _streamReceiving = false;
  bool _recoveringFromStaleFrame = false;
  int _runGeneration = 0;
  int _rtsHostIndex = 0;
  int _rtsHostFailures = 0;
  int _consecutiveFailures = 0;
  bool _isConnected = false;
  static const int _maxFailures = 3;

  String? _email;
  String? _password;
  String? _token;
  String? _refreshToken;
  DateTime? _tokenExpiresAt;
  bool _isLoggingIn = false;

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
    _running = true;
    final generation = ++_runGeneration;
    _consecutiveFailures = 0;
    _rtsHostFailures = 0;
    _isConnected = false;
    _recoveringFromStaleFrame = false;
    _lastFrameReceivedAt = null;
    _client = HttpClient()..badCertificateCallback = (cert, host, port) => true;
    _client!.connectionTimeout = const Duration(seconds: 8);
    unawaited(_loginAndStart(generation));
  }

  Future<void> _loginAndStart(int generation) async {
    if (hasCredentials) {
      await _tryLogin();
    }
    if (!_isCurrentRun(generation)) return;
    await _fetchStationList();
    if (!_isCurrentRun(generation)) return;
    _stationListTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _fetchStationList(),
    );
    _frameWatchdogTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkFrameFreshness(generation),
    );
    unawaited(_connectRtsStream(generation));
  }

  bool _isCurrentRun(int generation) =>
      _running && generation == _runGeneration;

  Future<bool> _tryLogin() async {
    if (_isLoggingIn) return false;
    if (!hasCredentials) return false;
    _isLoggingIn = true;
    final triedHosts = <int>{};
    while (triedHosts.length < _apiHosts.length) {
      final host = _currentHost;
      triedHosts.add(_apiHostIndex);
      try {
        final c = HttpClient()
          ..badCertificateCallback = (cert, host, port) => true;
        c.connectionTimeout = const Duration(seconds: 10);
        final req = await c.postUrl(Uri.parse('$host$_loginPath'));
        req.headers.contentType = ContentType.json;
        req.headers.set('User-Agent', 'FlutterRhythmQuake/1.0');
        req.write(jsonEncode({'email': _email, 'password': _password}));
        final resp = await req.close().timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          final body = await resp.transform(utf8.decoder).join();
          c.close();
          final data = jsonDecode(body) as Map<String, dynamic>;
          _token = data['token'] as String?;
          _refreshToken = data['refresh_token'] as String?;
          final expiresAt = data['expires_at'] as String?;
          _tokenExpiresAt = expiresAt != null
              ? DateTime.tryParse(expiresAt)
              : null;
          if (_token != null) {
            _scheduleTokenRefresh();
            debugPrint('CWA login OK: $host');
            _isLoggingIn = false;
            return true;
          }
        }
        c.close();
      } catch (e) {
        debugPrint('CWA login fail $host: $e');
      }
      _nextHost();
    }
    _isLoggingIn = false;
    return false;
  }

  Future<bool> _refreshTokenIfNeeded() async {
    if (_token != null &&
        _tokenExpiresAt != null &&
        DateTime.now().isBefore(
          _tokenExpiresAt!.subtract(const Duration(minutes: 5)),
        )) {
      return true;
    }
    if (_refreshToken != null) return _tryRefresh();
    if (hasCredentials) return _tryLogin();
    return false;
  }

  Future<bool> _tryRefresh() async {
    final host = _currentHost;
    try {
      final c = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;
      c.connectionTimeout = const Duration(seconds: 10);
      final req = await c.postUrl(Uri.parse('$host$_refreshPath'));
      req.headers.contentType = ContentType.json;
      req.headers.set('User-Agent', 'FlutterRhythmQuake/1.0');
      req.write(jsonEncode({'refresh_token': _refreshToken}));
      final resp = await req.close().timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        c.close();
        final data = jsonDecode(body) as Map<String, dynamic>;
        _token = data['token'] as String?;
        final expiresAt = data['expires_at'] as String?;
        _tokenExpiresAt = expiresAt != null
            ? DateTime.tryParse(expiresAt)
            : null;
        if (_token != null) {
          _scheduleTokenRefresh();
          return true;
        }
      }
      c.close();
      return false;
    } catch (e) {
      debugPrint('CWA refresh error: $e');
      return false;
    }
  }

  void _scheduleTokenRefresh() {
    _tokenRefreshTimer?.cancel();
    if (_tokenExpiresAt == null) return;
    final remaining = _tokenExpiresAt!.difference(DateTime.now());
    if (remaining.isNegative) return;
    final refreshIn = remaining ~/ 2;
    _tokenRefreshTimer = Timer(
      Duration(seconds: refreshIn.inSeconds),
      _tryRefresh,
    );
  }

  Future<HttpClientResponse?> _authRequest(String host, String path) async {
    if (_client == null) return null;
    if (_token == null && hasCredentials) {
      final ok = await _tryLogin();
      if (!ok) return _directRequest(host, path);
    } else if (_token != null) {
      await _refreshTokenIfNeeded();
    }
    if (_token != null) {
      try {
        final req = await _client!.getUrl(Uri.parse('$host$path'));
        _setJsonRequestHeaders(req);
        req.headers.set('Authorization', 'Bearer $_token');
        final resp = await req.close().timeout(_requestTimeout);
        if (resp.statusCode == 401) {
          final ok = await _tryLogin();
          if (!ok) return _directRequest(host, path);
          final req2 = await _client!.getUrl(Uri.parse('$host$path'));
          _setJsonRequestHeaders(req2);
          req2.headers.set('Authorization', 'Bearer $_token');
          return req2.close().timeout(_requestTimeout);
        }
        return resp;
      } catch (e) {
        return null;
      }
    }
    return _directRequest(host, path);
  }

  Future<HttpClientResponse?> _directRequest(String host, String path) async {
    if (_client == null) return null;
    try {
      final req = await _client!.getUrl(Uri.parse('$host$path'));
      _setJsonRequestHeaders(req);
      return req.close().timeout(_requestTimeout);
    } catch (e) {
      return null;
    }
  }

  void _setJsonRequestHeaders(HttpClientRequest request) {
    request.headers.set('User-Agent', 'FlutterRhythmQuake/1.0');
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
  }

  Future<HttpClientResponse?> _tryRequest(String path) async {
    final triedHosts = <int>{};
    while (triedHosts.length < _apiHosts.length) {
      final host = _currentHost;
      triedHosts.add(_apiHostIndex);
      final resp = await _authRequest(host, path);
      if (resp != null && resp.statusCode == 200) return resp;
      if (resp != null && resp.statusCode != 200) {
        debugPrint('CWA HTTP ${resp.statusCode} on $host$path');
      }
      _nextHost();
    }
    return null;
  }

  void stop() {
    final wasConnected = _isConnected;
    _running = false;
    _runGeneration++;
    _fetchingRts = false;
    _streamConnecting = false;
    _streamReceiving = false;
    _recoveringFromStaleFrame = false;
    _rtsTimer?.cancel();
    _rtsTimer = null;
    _stationListTimer?.cancel();
    _stationListTimer = null;
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
    _streamReconnectTimer?.cancel();
    _streamReconnectTimer = null;
    _frameWatchdogTimer?.cancel();
    _frameWatchdogTimer = null;
    _streamClient?.close(force: true);
    _streamClient = null;
    _client?.close();
    _client = null;
    _lastRtsDataTime = null;
    _lastFrameReceivedAt = null;
    dataTimeNotifier.value = null;
    _isConnected = false;
    _clearRuntimeState(emitStations: true);
    if (wasConnected) {
      onStatusChanged?.call(false);
    }
  }

  Future<void> _fetchStationList() async {
    if (!_running || _client == null || _fetchingStationList) return;
    _fetchingStationList = true;
    try {
      final resp = await _tryRequest(_stationPath);
      if (resp == null || resp.statusCode != 200) return;
      final body = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
      final data = jsonDecode(body);
      if (data is! Map) return;

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
      _stationMap = newMap;
    } catch (e) {
      debugPrint('CWA station list error: $e');
    } finally {
      _fetchingStationList = false;
    }
  }

  String get _currentRtsHost => _rtsHosts[_rtsHostIndex % _rtsHosts.length];

  void _nextRtsHost() {
    _rtsHostIndex = (_rtsHostIndex + 1) % _rtsHosts.length;
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
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;
    client.connectionTimeout = _requestTimeout;
    _streamClient?.close(force: true);
    _streamClient = client;
    var receivedFrame = false;

    try {
      if (_token != null) {
        await _refreshTokenIfNeeded();
      }
      if (!_isCurrentRun(generation) || !identical(_streamClient, client)) {
        return;
      }

      final request = await client.getUrl(Uri.parse('$host$_rtsPath'));
      request.headers.set('User-Agent', 'FlutterRhythmQuake/1.0');
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      if (_token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      }
      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'HTTP ${response.statusCode}',
          uri: Uri.parse('$host$_rtsPath'),
        );
      }

      final contentType = response.headers.contentType?.mimeType ?? '';
      if (contentType != 'text/event-stream') {
        final body = await response
            .transform(utf8.decoder)
            .join()
            .timeout(_requestTimeout);
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          receivedFrame = _acceptRtsPayload(decoded, generation);
        }
        return;
      }

      _streamConnecting = false;
      _streamReceiving = true;
      await for (final line
          in response.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!_isCurrentRun(generation) || !identical(_streamClient, client)) {
          return;
        }
        final payload = decodeSseDataLine(line);
        if (payload == null || payload['station'] is! Map) continue;
        if (_acceptRtsPayload(payload, generation)) {
          receivedFrame = true;
          _rtsHostFailures = 0;
          _stopPollingFallback();
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
        client.close(force: true);
        _recordRtsTransportFailure(receivedFrame: receivedFrame);
        _startPollingFallback(generation);
        _scheduleStreamReconnect(generation);
      } else {
        client.close(force: true);
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

  void _startPollingFallback(int generation) {
    if (!_isCurrentRun(generation) || _rtsTimer?.isActive == true) return;
    unawaited(_fetchRtsFallback(generation));
    _rtsTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _fetchRtsFallback(generation),
    );
  }

  void _stopPollingFallback() {
    _rtsTimer?.cancel();
    _rtsTimer = null;
  }

  Future<void> _fetchRtsFallback(int generation) async {
    if (!_isCurrentRun(generation) || _fetchingRts || _client == null) return;
    if (_stationMap.isEmpty) {
      unawaited(_fetchStationList());
      return;
    }

    _fetchingRts = true;
    final host = _currentRtsHost;
    try {
      final request = await _client!.getUrl(Uri.parse('$host$_rtsPath'));
      _setJsonRequestHeaders(request);
      if (_token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      }
      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('RTS payload is not a map');
      }
      if (_acceptRtsPayload(decoded, generation)) {
        _rtsHostFailures = 0;
      }
    } catch (error) {
      if (_isCurrentRun(generation)) {
        debugPrint('TREM RTS fallback error on $host: $error');
        _recordRtsTransportFailure();
      }
    } finally {
      if (generation == _runGeneration) {
        _fetchingRts = false;
      }
    }
  }

  bool _acceptRtsPayload(Map data, int generation) {
    if (!_isCurrentRun(generation)) return false;
    final stationData = data['station'];
    final dataTime = _parseRtsTime(data['time']);
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
      final existing = _stationMap[id];
      if (existing == null || !existing.work) continue;

      existing.pga =
          double.tryParse(vals['pga']?.toString() ?? '') ?? existing.pga;
      existing.pgv =
          double.tryParse(vals['pgv']?.toString() ?? '') ?? existing.pgv;
      existing.intensity =
          double.tryParse(vals['i']?.toString() ?? '') ?? existing.intensity;
      existing.alertIntensity =
          double.tryParse(vals['I']?.toString() ?? '') ??
          existing.alertIntensity;
      existing.hasAlert = isActiveAlertValue(vals['alert']);
      existing.lastUpdate = now;
      updated.add(existing);
    }

    if (updated.isEmpty) {
      unawaited(_fetchStationList());
      return false;
    }

    updated.sort((a, b) => b.currentIntensity.compareTo(a.currentIntensity));
    _lastRtsDataTime = dataTime;
    _lastFrameReceivedAt = now;
    _recoveringFromStaleFrame = false;
    dataTimeNotifier.value = dataTime;
    _stations = updated;
    _stationController.add(updated);
    _checkShakeNotification();
    _handleSuccess();
    return true;
  }

  void _checkFrameFreshness(int generation) {
    if (!_isCurrentRun(generation)) return;
    final lastReceived = _lastFrameReceivedAt;
    if (lastReceived == null) {
      _startPollingFallback(generation);
      return;
    }
    if (DateTime.now().difference(lastReceived) <= _frameStaleAfter ||
        _recoveringFromStaleFrame) {
      return;
    }

    _recoveringFromStaleFrame = true;
    _markDisconnected();
    _nextRtsHost();
    _streamClient?.close(force: true);
    _streamClient = null;
    _streamConnecting = false;
    _streamReceiving = false;
    _startPollingFallback(generation);
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
    if (!line.startsWith('data:')) return null;
    final raw = line.substring(5).trimLeft();
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
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
