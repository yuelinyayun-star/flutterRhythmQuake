import 'dart:async';
import 'api_json_decoder.dart';
import '../station_history_capture.dart';
import '../native_jian_connection.dart';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'source_socket.dart';
import 'source_socket_error.dart';
import 'source_connection_lifecycle.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'whews_socket_client.dart';
import 'whews_station_service.dart';
import 'station_json_decoder.dart';
import 'station_json_values.dart';

typedef JianStationSocketFactory = WebSocketChannel Function(Uri uri);

class JianStationService {
  JianStationService({
    required this.kind,
    JianStationSocketFactory? socketFactory,
    StationJsonDecoder? jsonDecoder,
    this.reconnectDelay = const Duration(seconds: 15),
    this.observationTimeout = const Duration(seconds: 90),
  }) : _socketFactory = socketFactory ?? _connectSocket,
       _jsonDecoder = jsonDecoder ?? StationJsonDecoder();

  static WebSocketChannel _connectSocket(Uri uri) => kIsWeb
      ? WebSocketChannel.connect(uri)
      : connectSourceSocket(uri, connectTimeout: const Duration(seconds: 15));

  final WhewsStationKind kind;
  final StationJsonDecoder _jsonDecoder;
  final JianStationSocketFactory _socketFactory;
  final Duration reconnectDelay;
  final Duration observationTimeout;
  final ValueNotifier<WhewsSocketState> stateNotifier = ValueNotifier(
    WhewsSocketState.disconnected,
  );
  final StreamController<WhewsStationFrame> _frames =
      StreamController<WhewsStationFrame>.broadcast();

  Stream<WhewsStationFrame> get frameStream => _frames.stream;

  WebSocketChannel? _socket;
  final _closing = SourceConnectionBarrier();
  bool _blocked = false;
  Future<void> get closed => _closing.wait();
  StreamSubscription<dynamic>? _subscription;
  Timer? _retryTimer;
  Timer? _observationTimer;
  DateTime? _observationDeadline;
  List<LatLng> _coordinates = const [];
  List<String> _codes = const [];
  List<String> _names = const [];
  List<String> _regions = const [];
  List<String> _stationTypes = const [];
  DateTime? _lastDataTime;
  bool _hasPublishedFrame = false;
  bool _running = false;
  int _generation = 0;
  int _endpointIndex = 0;
  Uri get activeEndpoint => Uri.parse(
    (NativeJianConnection.prepare({
              'op': 'endpoint',
              'index': _endpointIndex,
              'path': '/$_path',
            })
            as Map)['url']
        as String,
  );

  String get _path => switch (kind) {
    WhewsStationKind.nied => 'kmoni',
    WhewsStationKind.snet => 's-net',
    WhewsStationKind.kma => 'kma-station',
  };

  // S-net observations are minute-granular and can arrive over 90 seconds late.
  Duration get _maxDataAge => kind == WhewsStationKind.snet
      ? const Duration(minutes: 3)
      : observationTimeout;

  void start() {
    if (_running) return;
    _running = true;
    _endpointIndex = 0;
    _blocked = false;
    _open();
  }

  Future<void> _open() async {
    if (!_running || _blocked || _socket != null) return;
    final generation = ++_generation;
    stateNotifier.value = WhewsSocketState.connecting;
    try {
      await _closing.wait();
      if (!_running || _blocked || generation != _generation) return;
      final socket = _socketFactory(activeEndpoint);
      _socket = socket;
      _subscription = socket.stream.listen(
        (message) {
          if (_running && generation == _generation) _handleMessage(message);
        },
        onDone: () => _failed(generation),
        onError: (Object error) =>
            _failed(generation, code: sourceSocketStatusCode(error)),
        cancelOnError: true,
      );
      await sourceReady(socket.ready, const Duration(seconds: 15));
      if (_running && generation == _generation && _lastDataTime == null) {
        _observationTimer?.cancel();
        _armObservationTimer(generation);
      }
    } catch (_) {
      _failed(generation);
    }
  }

  void _armObservationTimer(int generation, [Duration? delay]) {
    final wait = delay ?? observationTimeout;
    _observationTimer?.cancel();
    _observationDeadline = DateTime.now().add(wait);
    _observationTimer = Timer(wait, () {
      if (!_running || generation != _generation) return;
      if (DateTime.now().difference(_observationDeadline!) >
          const Duration(seconds: 5)) {
        _armObservationTimer(generation, const Duration(seconds: 20));
      } else {
        _failed(generation);
      }
    });
  }

  void _failed(int generation, {int? code}) {
    if (!_running || _blocked || generation != _generation) return;
    final status = code ?? _socket?.closeCode;
    if (const {401, 403, 429, 1008, 4008, 4401, 4403}.contains(status))
      _blocked = true;
    ++_generation;
    _clearPublishedFrame();
    _closeSocket();
    stateNotifier.value = WhewsSocketState.error;
    _retryTimer?.cancel();
    if (_blocked) return;
    _endpointIndex =
        (NativeJianConnection.prepare({
                  'op': 'retry',
                  'index': _endpointIndex,
                  'failures': 0,
                  'cooldownMs': reconnectDelay.inMilliseconds,
                  'switchEndpoint': true,
                })
                as Map)['index']
            as int;
    _retryTimer = Timer(reconnectDelay, () {
      _retryTimer = null;
      _open();
    });
  }

  void _handleMessage(dynamic message) {
    try {
      final decoded = _coordinates.isEmpty
          ? (message is String
                ? decodeApiJson(message)
                : decodeApiJsonBytes(message as List<int>))
          : (message is String
                ? _jsonDecoder.decode(message)
                : _jsonDecoder.decodeUtf8(message as List<int>));
      if (decoded is! Map) return;
      final frame = Map<String, dynamic>.from(decoded);
      if (frame['type'] == 'error' || frame['ok'] == false) {
        _failed(_generation, code: 4403);
        return;
      }
      if (frame['type'] != _path) return;
      if (frame['stations'] is List) {
        StationHistoryCapture.instance.retainOriginal(
          'jian.${kind.name}',
          'metadata',
          frame,
        );
        _readStations(frame['stations'] as List);
        return;
      }
      final rawValues = frame[kind == WhewsStationKind.kma ? 'mmi' : 'int'];
      if (rawValues is! List ||
          _coordinates.isEmpty ||
          rawValues.length != _coordinates.length) {
        return;
      }
      final dataTime = _parseDataTime(frame['time']);
      if (dataTime == null ||
          (_lastDataTime != null && !dataTime.isAfter(_lastDataTime!)) ||
          DateTime.now().toUtc().difference(dataTime) > _maxDataAge ||
          dataTime.difference(DateTime.now().toUtc()) >
              const Duration(seconds: 15)) {
        return;
      }
      final values = readStationJsonNumbers(
        rawValues,
        minimum: -3,
        maximum: kind == WhewsStationKind.snet
            ? 99
            : kind == WhewsStationKind.kma
            ? 11
            : 7,
        allowStrings: false,
      );
      if (values == null) return;
      _lastDataTime = dataTime;
      StationHistoryCapture.instance.retainOriginal(
        'jian.${kind.name}',
        'data',
        frame,
      );
      _hasPublishedFrame = true;
      _observationTimer?.cancel();
      _armObservationTimer(_generation);
      stateNotifier.value = WhewsSocketState.connected;
      _frames.add(
        WhewsStationFrame(
          kind: kind,
          dataTime: dataTime,
          coordinates: _coordinates,
          values: values,
          source: 'jian',
          codes: _codes,
          names: _names,
          regions: _regions,
          stationTypes: _stationTypes,
          originalJson: StationHistoryCapture.instance.original(
            'jian.${kind.name}',
          ),
        ),
      );
    } catch (_) {
      // Invalid frames must not replace the last valid station snapshot.
    }
  }

  void _readStations(List<dynamic> stations) {
    if (stations.isEmpty) return;
    final coordinates = <LatLng>[];
    final codes = <String>[];
    final names = <String>[];
    final regions = <String>[];
    final stationTypes = <String>[];
    for (var i = 0; i < stations.length; i++) {
      final row = stations[i];
      if (row is! Map) return;
      final lat = row['lat'] ?? row['latitude'];
      final lon = row['lon'] ?? row['longitude'];
      if (lat is! num ||
          lon is! num ||
          !lat.isFinite ||
          !lon.isFinite ||
          lat < -90 ||
          lat > 90 ||
          lon < -180 ||
          lon > 180) {
        return;
      }
      coordinates.add(LatLng(lat.toDouble(), lon.toDouble()));
      final code = row['code']?.toString().trim() ?? '';
      if (kind == WhewsStationKind.nied && code.isEmpty) return;
      codes.add(code);
      names.add(row['name']?.toString().trim() ?? '');
      regions.add(row['region']?.toString().trim() ?? '');
      stationTypes.add(row['station_type']?.toString().trim() ?? '');
    }
    if (!listEquals(_coordinates, coordinates)) {
      _lastDataTime = null;
    }
    _coordinates = List.unmodifiable(coordinates);
    _codes = List.unmodifiable(codes);
    _names = List.unmodifiable(names);
    _regions = List.unmodifiable(regions);
    _stationTypes = List.unmodifiable(stationTypes);
  }

  DateTime? _parseDataTime(Object? raw) {
    final value = raw?.toString() ?? '';
    if (!RegExp(r'^\d{14}$').hasMatch(value)) return null;
    final year = int.parse(value.substring(0, 4));
    final month = int.parse(value.substring(4, 6));
    final day = int.parse(value.substring(6, 8));
    final hour = int.parse(value.substring(8, 10));
    final minute = int.parse(value.substring(10, 12));
    final second = int.parse(value.substring(12, 14));
    final wallClock = DateTime.utc(year, month, day, hour, minute, second);
    if (wallClock.year != year ||
        wallClock.month != month ||
        wallClock.day != day ||
        wallClock.hour != hour ||
        wallClock.minute != minute ||
        wallClock.second != second) {
      return null;
    }
    // Kmoni time is JST; S-net and KMA station times are UTC.
    return kind == WhewsStationKind.nied
        ? wallClock.subtract(const Duration(hours: 9))
        : wallClock;
  }

  @visibleForTesting
  void handleMessageForTesting(dynamic message) => _handleMessage(message);

  void stop() {
    _running = false;
    ++_generation;
    _retryTimer?.cancel();
    _retryTimer = null;
    _closeSocket();
    stateNotifier.value = WhewsSocketState.disconnected;
  }

  void _closeSocket() {
    _jsonDecoder.dispose();
    _observationTimer?.cancel();
    _observationTimer = null;
    final subscription = _subscription;
    final socket = _socket;
    _subscription = null;
    _socket = null;
    if (socket != null)
      _closing.close(() async {
        final closed = socket.sink.close();
        cancelSourceSubscription(subscription);
        await closed;
      });
    _coordinates = const [];
    _codes = const [];
    _names = const [];
    _regions = const [];
    _stationTypes = const [];
    _lastDataTime = null;
    _hasPublishedFrame = false;
  }

  void _clearPublishedFrame() {
    final lastTime = _lastDataTime;
    if (!_hasPublishedFrame || lastTime == null) return;
    _hasPublishedFrame = false;
    _frames.add(
      WhewsStationFrame(
        kind: kind,
        dataTime: lastTime,
        coordinates: const [],
        values: const [],
        source: 'jian',
      ),
    );
  }

  void dispose() {
    stop();
    stateNotifier.dispose();
    _frames.close();
  }
}
