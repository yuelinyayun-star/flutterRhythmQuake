import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'whews_socket_client.dart';
import 'whews_station_service.dart';

typedef JianStationSocketFactory = WebSocketChannel Function(Uri uri);

class JianStationService {
  JianStationService({
    required this.kind,
    JianStationSocketFactory? socketFactory,
    this.reconnectDelay = const Duration(seconds: 15),
    this.observationTimeout = const Duration(seconds: 90),
  }) : _socketFactory = socketFactory ?? _connectSocket;

  static WebSocketChannel _connectSocket(Uri uri) => IOWebSocketChannel.connect(
    uri,
    connectTimeout: const Duration(seconds: 15),
  );

  final WhewsStationKind kind;
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
  StreamSubscription<dynamic>? _subscription;
  Timer? _retryTimer;
  Timer? _observationTimer;
  List<LatLng> _coordinates = const [];
  List<String> _codes = const [];
  List<String> _names = const [];
  List<String> _regions = const [];
  List<String> _stationTypes = const [];
  DateTime? _lastDataTime;
  bool _hasPublishedFrame = false;
  bool _running = false;
  int _generation = 0;

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
    _open();
  }

  Future<void> _open() async {
    if (!_running || _socket != null) return;
    final generation = ++_generation;
    stateNotifier.value = WhewsSocketState.connecting;
    try {
      final socket = _socketFactory(
        Uri.parse('wss://api.sismotide.top/$_path'),
      );
      _socket = socket;
      _subscription = socket.stream.listen(
        (message) {
          if (_running && generation == _generation) _handleMessage(message);
        },
        onDone: () => _failed(generation),
        onError: (Object error) => _failed(generation),
        cancelOnError: true,
      );
      await socket.ready.timeout(const Duration(seconds: 15));
      if (_running && generation == _generation && _lastDataTime == null) {
        _observationTimer?.cancel();
        _observationTimer = Timer(
          observationTimeout,
          () => _failed(generation),
        );
      }
    } catch (_) {
      _failed(generation);
    }
  }

  void _failed(int generation) {
    if (!_running || generation != _generation) return;
    ++_generation;
    _clearPublishedFrame();
    _closeSocket();
    stateNotifier.value = WhewsSocketState.error;
    _retryTimer?.cancel();
    _retryTimer = Timer(reconnectDelay, () {
      _retryTimer = null;
      _open();
    });
  }

  void _handleMessage(dynamic message) {
    try {
      final decoded = jsonDecode(
        message is String ? message : utf8.decode(message as List<int>),
      );
      if (decoded is! Map) return;
      final frame = Map<String, dynamic>.from(decoded);
      if (frame['type'] != _path) return;
      if (frame['stations'] is List) {
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
      final values = <double>[];
      for (final item in rawValues) {
        if (item is! num) return;
        final value = item.toDouble();
        final valid =
            value.isFinite &&
            value >= -3 &&
            value <=
                (kind == WhewsStationKind.snet
                    ? 99
                    : kind == WhewsStationKind.kma
                    ? 11
                    : 7);
        if (!valid) return;
        values.add(value);
      }
      _lastDataTime = dataTime;
      _hasPublishedFrame = true;
      _observationTimer?.cancel();
      _observationTimer = Timer(observationTimeout, () => _failed(_generation));
      stateNotifier.value = WhewsSocketState.connected;
      _frames.add(
        WhewsStationFrame(
          kind: kind,
          dataTime: dataTime,
          coordinates: _coordinates,
          values: List.unmodifiable(values),
          source: 'jian',
          codes: _codes,
          names: _names,
          regions: _regions,
          stationTypes: _stationTypes,
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
    _observationTimer?.cancel();
    _observationTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _socket?.sink.close();
    _socket = null;
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
