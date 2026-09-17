import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../core/utils/quake_time.dart';
import 'whews_socket_client.dart';

enum WhewsStationKind { nied, snet, kma }

class WhewsStationFrame {
  const WhewsStationFrame({
    required this.kind,
    required this.dataTime,
    required this.coordinates,
    required this.values,
    this.pga = const [],
    this.pgv = const [],
  });

  final WhewsStationKind kind;
  final DateTime dataTime;
  final List<LatLng> coordinates;
  final List<double> values;
  final List<double> pga;
  final List<double> pgv;
}

class WhewsStationService {
  WhewsStationService({
    required this.kind,
    required String apiToken,
    this.socketFactory = WhewsSocketClient.new,
  }) : _apiToken = apiToken.trim();

  static const String niedEnabledPreferenceKey =
      'api_source_whews_nied_enabled';
  static const String snetEnabledPreferenceKey =
      'api_source_whews_snet_enabled';
  static const String kmaEnabledPreferenceKey =
      'api_source_whews_kma_station_enabled';

  final WhewsStationKind kind;
  final WhewsSocketClient Function({
    required String url,
    required String apiToken,
    required void Function(dynamic) onMessage,
    void Function(WhewsSocketState)? onStateChanged,
  })
  socketFactory;
  static const observationTimeout = Duration(seconds: 90);
  Timer? _observationTimer;
  String _apiToken;
  WhewsSocketClient? _client;
  List<LatLng> _coordinates = const [];
  DateTime? _lastDataTime;
  bool _startRequested = false;
  bool _hasPublishedStations = false;

  final ValueNotifier<WhewsSocketState> stateNotifier =
      ValueNotifier<WhewsSocketState>(WhewsSocketState.disconnected);
  final StreamController<WhewsStationFrame> _frameController =
      StreamController<WhewsStationFrame>.broadcast();

  Stream<WhewsStationFrame> get frameStream => _frameController.stream;

  String get _url => switch (kind) {
    WhewsStationKind.nied => 'wss://api.beecld.com/ws/nied',
    WhewsStationKind.snet => 'wss://api.beecld.com/ws/snet',
    WhewsStationKind.kma => 'wss://api.beecld.com/ws/kma_station',
  };

  String get _stationFrameType => switch (kind) {
    WhewsStationKind.nied => 'nied_stations_update',
    WhewsStationKind.snet => 'snet_stations_update',
    WhewsStationKind.kma => 'kma_stations_update',
  };

  void setApiToken(String apiToken) {
    final next = apiToken.trim();
    if (next == _apiToken) return;
    _apiToken = next;
    if (next.isEmpty) {
      _closeClient();
      if (_startRequested) {
        stateNotifier.value = WhewsSocketState.unauthorized;
      }
      return;
    }
    final client = _client;
    if (client != null) {
      client.setApiToken(next);
    } else if (_startRequested) {
      _openClient();
    }
  }

  void start() {
    _startRequested = true;
    if (_client != null) return;
    if (_apiToken.isEmpty) {
      stateNotifier.value = WhewsSocketState.unauthorized;
      return;
    }
    _openClient();
  }

  void _openClient() {
    if (_client != null || _apiToken.isEmpty) return;
    final client = socketFactory(
      url: _url,
      apiToken: _apiToken,
      onMessage: _handleMessage,
      onStateChanged: _handleSocketState,
    );
    _client = client;
    client.start();
  }

  void _handleSocketState(WhewsSocketState state) {
    if (kind != WhewsStationKind.nied) {
      stateNotifier.value = state;
      return;
    }
    if (state == WhewsSocketState.connected) {
      // Transport heartbeats cannot certify that observations are updating.
      _observationTimer ??= Timer(
        observationTimeout,
        _handleObservationTimeout,
      );
      return;
    }
    _observationTimer?.cancel();
    _observationTimer = null;
    _clearPublishedStations();
    stateNotifier.value = state;
    if (state == WhewsSocketState.connecting) {
      _coordinates = const [];
    }
  }

  void _clearPublishedStations() {
    if (kind != WhewsStationKind.nied) return;
    final lastTime = _lastDataTime;
    if (lastTime == null || !_hasPublishedStations) return;
    _hasPublishedStations = false;
    _frameController.add(
      WhewsStationFrame(
        kind: kind,
        dataTime: lastTime,
        coordinates: const [],
        values: const [],
      ),
    );
  }

  void _handleObservationTimeout() {
    _observationTimer = null;
    _clearPublishedStations();
    stateNotifier.value = WhewsSocketState.error;
    _client?.reconnect();
  }

  void _handleMessage(dynamic message) {
    if (message is! Map) return;
    final frame = Map<String, dynamic>.from(message);
    if (frame['type'] == _stationFrameType) {
      _readCoordinates(frame['stations']);
      return;
    }
    final rawData = frame['Data'];
    if (rawData is! Map || _coordinates.isEmpty) return;
    final data = Map<String, dynamic>.from(rawData);
    final timestamp = _parseTimestamp(data['timestamp']);
    if (timestamp == null) return;
    final previous = _lastDataTime;
    if (previous != null && !timestamp.isAfter(previous)) return;

    final rawValues = kind == WhewsStationKind.kma
        ? data['mmi']
        : data['shindo'];
    if (rawValues is! List || rawValues.length != _coordinates.length) return;
    final values = _readPrimaryValues(rawValues);
    if (values == null) return;
    final pga = _readOptionalMotionValues(data['pga'], _coordinates.length);
    final pgv = _readOptionalMotionValues(data['pgv'], _coordinates.length);

    _lastDataTime = timestamp;
    _hasPublishedStations = true;
    if (_startRequested && kind == WhewsStationKind.nied) {
      _observationTimer?.cancel();
      _observationTimer = Timer(observationTimeout, _handleObservationTimeout);
      stateNotifier.value = WhewsSocketState.connected;
    }
    _frameController.add(
      WhewsStationFrame(
        kind: kind,
        dataTime: timestamp,
        coordinates: _coordinates,
        values: values,
        pga: pga ?? const [],
        pgv: pgv ?? const [],
      ),
    );
  }

  @visibleForTesting
  void handleMessageForTesting(dynamic message) => _handleMessage(message);

  DateTime? _parseTimestamp(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    if (parsed == null || parsed.isUtc) return parsed;
    // api.beecld.com: NIED/S-Net use UTC+8; KMA station timestamps use KST.
    return QuakeTime.wallClockToUtc(
      parsed,
      Duration(hours: kind == WhewsStationKind.kma ? 9 : 8),
    );
  }

  void _readCoordinates(dynamic rawStations) {
    if (rawStations is! List || rawStations.isEmpty) return;
    final next = <LatLng>[];
    for (final raw in rawStations) {
      if (raw is! Map) return;
      final lat = _number(raw['latitude']);
      final lng = _number(raw['longitude']);
      if (lat == null ||
          lng == null ||
          !lat.isFinite ||
          !lng.isFinite ||
          lat < -90 ||
          lat > 90 ||
          lng < -180 ||
          lng > 180) {
        return;
      }
      next.add(LatLng(lat, lng));
    }
    final changed = !listEquals(_coordinates, next);
    if (changed) _clearPublishedStations();
    _coordinates = List.unmodifiable(next);
    if (changed) _lastDataTime = null;
  }

  List<double>? _readPrimaryValues(List<dynamic> raw) {
    final values = <double>[];
    for (final item in raw) {
      final value = _number(item);
      if (value == null || !value.isFinite) return null;
      final isInRange = kind == WhewsStationKind.kma
          ? value >= -3 && value <= 11
          : value >= -3 && value <= 7;
      if (!isInRange) {
        return null;
      }
      values.add(value);
    }
    return List.unmodifiable(values);
  }

  List<double>? _readOptionalMotionValues(dynamic raw, int expectedLength) {
    if (raw == null) return const [];
    if (raw is! List || raw.length != expectedLength) return null;
    final values = <double>[];
    for (final item in raw) {
      final value = _number(item);
      if (value == null || !value.isFinite || value < 0) return null;
      values.add(value);
    }
    return List.unmodifiable(values);
  }

  double? _number(dynamic raw) {
    return switch (raw) {
      num value => value.toDouble(),
      String value => double.tryParse(value),
      _ => null,
    };
  }

  void stop() {
    _startRequested = false;
    _closeClient();
    stateNotifier.value = WhewsSocketState.disconnected;
  }

  void _closeClient() {
    _observationTimer?.cancel();
    _observationTimer = null;
    _client?.dispose();
    _client = null;
    _coordinates = const [];
    _lastDataTime = null;
    _hasPublishedStations = false;
  }

  void dispose() {
    stop();
    stateNotifier.dispose();
    _frameController.close();
  }
}

bool whewsNiedSnetValueIsValid(double value) =>
    value.isFinite && value > -3.0 && value <= 7.0;
