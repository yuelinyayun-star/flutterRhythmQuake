import 'dart:async';
import 'api_json_decoder.dart';
import '../station_history_capture.dart';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../core/utils/quake_time.dart';
import 'whews_socket_client.dart';
import 'source_connection_lifecycle.dart';
import 'station_json_decoder.dart';
import 'station_json_values.dart';

enum WhewsStationKind { nied, snet, kma }

class WhewsStationFrame {
  const WhewsStationFrame({
    required this.kind,
    required this.dataTime,
    required this.coordinates,
    required this.values,
    this.source = 'whews',
    this.codes = const [],
    this.names = const [],
    this.regions = const [],
    this.stationTypes = const [],
    this.pga = const [],
    this.pgv = const [],
    this.originalJson,
  });

  final WhewsStationKind kind;
  final DateTime dataTime;
  final List<LatLng> coordinates;
  final List<double> values;
  final String source;
  final List<String> codes;
  final List<String> names;
  final List<String> regions;
  final List<String> stationTypes;
  final List<double> pga;
  final List<double> pgv;
  final Map<String, dynamic>? originalJson;
}

class WhewsStationService {
  WhewsStationService({
    required this.kind,
    required String apiToken,
    this.socketFactory = WhewsSocketClient.new,
    StationJsonDecoder? jsonDecoder,
  }) : _apiToken = apiToken.trim(),
       _jsonDecoder = jsonDecoder ?? StationJsonDecoder();

  static const String niedEnabledPreferenceKey =
      'api_source_whews_nied_enabled';
  static const String snetEnabledPreferenceKey =
      'api_source_whews_snet_enabled';
  static const String kmaEnabledPreferenceKey =
      'api_source_whews_kma_station_enabled';

  final WhewsStationKind kind;
  final StationJsonDecoder _jsonDecoder;
  bool _hasDecodeCatalogue = false;
  final WhewsSocketClient Function({
    required String url,
    required String apiToken,
    required void Function(dynamic) onMessage,
    void Function(WhewsSocketState)? onStateChanged,
  })
  socketFactory;
  static const observationTimeout = Duration(seconds: 90);
  Timer? _observationTimer;
  DateTime? _observationDeadline;
  String _apiToken;
  WhewsSocketClient? _client;
  final _closing = SourceConnectionBarrier();
  Future<void> get closed => _closing.wait();
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
    client.frameDecoder = _decodeFrame;
    client.binaryFrameDecoder = _decodeFrameBytes;
    client.start();
  }

  void _handleSocketState(WhewsSocketState state) {
    if (state != WhewsSocketState.connected) {
      _jsonDecoder.dispose();
      _hasDecodeCatalogue = false;
    }
    if (kind != WhewsStationKind.nied) {
      stateNotifier.value = state;
      return;
    }
    if (state == WhewsSocketState.connected) {
      // Transport heartbeats cannot certify that observations are updating.
      if (_observationTimer == null) _armObservationTimer();
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

  void _armObservationTimer([Duration delay = observationTimeout]) {
    _observationTimer?.cancel();
    _observationDeadline = DateTime.now().add(delay);
    _observationTimer = Timer(delay, _handleObservationTimeout);
  }

  void _handleObservationTimeout() {
    final deadline = _observationDeadline;
    _observationTimer = null;
    if (deadline != null && DateTime.now().difference(deadline) > const Duration(seconds: 5)) {
      _armObservationTimer(const Duration(seconds: 20));
      return;
    }
    _clearPublishedStations();
    stateNotifier.value = WhewsSocketState.error;
    _client?.reconnect();
  }

  void _handleMessage(dynamic message) {
    if (message is! Map) return;
    final frame = Map<String, dynamic>.from(message);
    if (frame['type'] == _stationFrameType) {
      StationHistoryCapture.instance.retainOriginal(
        'whews.${kind.name}',
        'metadata',
        frame,
      );
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
    StationHistoryCapture.instance.retainOriginal(
      'whews.${kind.name}',
      'data',
      frame,
    );
    _hasPublishedStations = true;
    if (_startRequested && kind == WhewsStationKind.nied) {
      _observationTimer?.cancel();
      _armObservationTimer();
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
        originalJson: StationHistoryCapture.instance.original(
          'whews.${kind.name}',
        ),
      ),
    );
  }

  @visibleForTesting
  void handleMessageForTesting(dynamic message) => _handleMessage(message);

  dynamic _decodeFrame(String raw) =>
      _hasDecodeCatalogue ? _jsonDecoder.decode(raw) : decodeApiJson(raw);
  dynamic _decodeFrameBytes(List<int> raw) => _hasDecodeCatalogue
      ? _jsonDecoder.decodeUtf8(raw)
      : decodeApiJsonBytes(raw);

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
    _hasDecodeCatalogue = true;
    if (changed) _lastDataTime = null;
  }

  List<double>? _readPrimaryValues(List<dynamic> raw) {
    return readStationJsonNumbers(
      raw,
      minimum: -3,
      maximum: kind == WhewsStationKind.kma ? 11 : 7,
    );
  }

  List<double>? _readOptionalMotionValues(dynamic raw, int expectedLength) {
    if (raw == null) return const [];
    if (raw is! List || raw.length != expectedLength) return null;
    return readStationJsonNumbers(raw, minimum: 0);
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
    _jsonDecoder.dispose();
    _hasDecodeCatalogue = false;
    _observationTimer?.cancel();
    _observationTimer = null;
    final client = _client;
    _client = null;
    if (client != null) _closing.close(() async { client.dispose(); await client.closed; });
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
