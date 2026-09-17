import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'fdsn_channel_sensitivity.dart';
import 'fdsn_channel_catalog.dart';
import 'fdsn_stream_catalog.dart';
import 'fdsn_seedlink_info.dart';
import 'fdsn_station_service.dart';
import 'fdsn_metadata_routing.dart';
import 'package:latlong2/latlong.dart';

class FdsnMotionSample {
  final String source;
  final String network;
  final String station;
  final String channel;
  final double? pga;
  final double? pgv;
  final double? intensity;
  final bool active;
  final DateTime timestamp;

  const FdsnMotionSample({
    required this.source,
    required this.network,
    required this.station,
    required this.channel,
    required this.timestamp,
    this.pga,
    this.pgv,
    this.intensity,
    this.active = false,
  });

  String get code => '$network.$station';
  bool get hasMeasurement => pga != null || pgv != null || intensity != null;
}

class FdsnSeedLinkStream {
  final String source;
  final String host;
  final int port;
  final String network;
  final String station;
  final String selector;
  final bool secure;

  const FdsnSeedLinkStream({
    required this.source,
    required this.host,
    required this.port,
    required this.network,
    required this.station,
    required this.selector,
    this.secure = false,
  });
}

class _SeedLinkSource {
  final String source;
  final String host;
  final int port;
  final Set<String> allowedNetworks;
  final bool secure;

  const _SeedLinkSource({
    required this.source,
    required this.host,
    required this.port,
    required this.allowedNetworks,
    this.secure = false,
  });
}

class FdsnMotionService {
  static final FdsnMotionService _instance = FdsnMotionService._();
  factory FdsnMotionService() => _instance;
  FdsnMotionService._()
    : _sources = _seedLinkSources,
      _defaults = defaultStreams,
      _responseClientFactory = http.Client.new,
      _useChannelCatalog = true,
      _watchdogInterval = const Duration(seconds: 15),
      _networkTimeout = const Duration(minutes: 3),
      _liveReconnectSources = const {'EarthScope'},
      _reconnectDelay = const Duration(seconds: 10);

  @visibleForTesting
  FdsnMotionService.forTesting({
    required List<FdsnSeedLinkStream> streams,
    http.Client Function()? responseClientFactory,
    bool useChannelCatalog = false,
    Duration watchdogInterval = const Duration(seconds: 15),
    Duration networkTimeout = const Duration(minutes: 3),
    Set<String> liveReconnectSources = const {'EarthScope'},
    Duration reconnectDelay = const Duration(seconds: 10),
  }) : _defaults = streams,
       _sources = {
         for (final s in streams)
           s.source: _SeedLinkSource(
             source: s.source,
             host: s.host,
             port: s.port,
             allowedNetworks: {},
             secure: s.secure,
           ),
       }.values.toList(),
       _responseClientFactory = responseClientFactory ?? http.Client.new,
       _useChannelCatalog = useChannelCatalog,
       _watchdogInterval = watchdogInterval,
       _networkTimeout = networkTimeout,
       _liveReconnectSources = Set.unmodifiable(liveReconnectSources),
       _reconnectDelay = reconnectDelay;

  final List<_SeedLinkSource> _sources;
  final List<FdsnSeedLinkStream> _defaults;
  final http.Client Function() _responseClientFactory;
  final bool _useChannelCatalog;
  final Duration _watchdogInterval;
  final Duration _networkTimeout;
  final Set<String> _liveReconnectSources;
  final Duration _reconnectDelay;
  FdsnChannelCatalog? _channelCatalog;

  static const int defaultStationLimit = 300;
  static const String stationLimitPreferenceKey = 'fdsn_station_limit';
  static const List<int> stationLimitOptions = [
    100,
    300,
    500,
    1000,
    2000,
    3000,
    4000,
    5000,
  ];

  static int normalizeStationLimit(int value) {
    if (stationLimitOptions.contains(value)) return value;
    return stationLimitOptions.reduce(
      (a, b) => (value - a).abs() <= (value - b).abs() ? a : b,
    );
  }

  static const List<_SeedLinkSource> _seedLinkSources = [
    _SeedLinkSource(
      source: 'EarthScope',
      host: 'rtserve.earthscope.org',
      port: 18500,
      secure: true,
      allowedNetworks: {},
    ),
    _SeedLinkSource(
      source: 'GEOFON',
      host: 'geofon.gfz.de',
      port: 18000,
      allowedNetworks: {},
    ),
  ];

  static const List<FdsnSeedLinkStream> defaultStreams = [
    FdsnSeedLinkStream(
      source: 'EarthScope',
      host: 'rtserve.earthscope.org',
      port: 18500,
      network: 'IU',
      station: 'ANMO',
      selector: 'BH?',
      secure: true,
    ),
    FdsnSeedLinkStream(
      source: 'EarthScope',
      host: 'rtserve.earthscope.org',
      port: 18500,
      network: 'IU',
      station: 'COLA',
      selector: 'BH?',
      secure: true,
    ),
    FdsnSeedLinkStream(
      source: 'EarthScope',
      host: 'rtserve.earthscope.org',
      port: 18500,
      network: 'II',
      station: 'PFO',
      selector: 'BH?',
      secure: true,
    ),
    FdsnSeedLinkStream(
      source: 'GEOFON',
      host: 'geofon.gfz.de',
      port: 18000,
      network: 'GE',
      station: 'ACRG',
      selector: 'BH?',
    ),
    FdsnSeedLinkStream(
      source: 'GEOFON',
      host: 'geofon.gfz.de',
      port: 18000,
      network: 'GE',
      station: 'MORC',
      selector: 'BH?',
    ),
    FdsnSeedLinkStream(
      source: 'GEOFON',
      host: 'geofon.gfz.de',
      port: 18000,
      network: 'GE',
      station: 'WLF',
      selector: 'BH?',
    ),
  ];
  static int get defaultStreamCount =>
      FdsnMotionService().targetStationLimitNotifier.value;

  final _controller = StreamController<FdsnMotionSample>.broadcast();
  Stream<FdsnMotionSample> get sampleStream => _controller.stream;
  final ValueNotifier<int> linkedStationCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> targetStationLimitNotifier = ValueNotifier<int>(
    defaultStationLimit,
  );
  final ValueNotifier<DateTime?> dataTimeNotifier = ValueNotifier(null);

  final List<_SeedLinkConnection> _connections = [];
  final Set<Socket> _discoverySockets = {};
  Timer? _discoveryRetry;
  final Map<String, List<FdsnSeedLinkStream>> _discovered = {};
  final Map<String, bool> _discoveryComplete = {};
  bool _running = false;
  int _currentStationLimit = defaultStationLimit;
  Set<String> _currentEnabledSources = const {'EarthScope', 'GEOFON'};
  int _connectionGeneration = 0;

  void Function(bool connected)? onStatusChanged;

  @visibleForTesting
  List<Map<String, Object>> get connectionDiagnostics => [
    for (final c in _connections)
      {
        'host': c.host,
        'selected': c.streams.length,
        'accepted': c._acceptedStations.length,
        'packets': c._packetCount,
        'decodeRejected': c._decodeRejected,
        'stale': c._staleCount,
        'received': c._receivedStations.length,
        'pending': c._pendingPackets.length,
        'socketOpen': c._socket != null,
        'connected': c._connected,
        'connectAttempts': c._connectAttempts,
        'reconnectPending': c._reconnectTimer != null,
        'lastCloseReason': c._lastCloseReason,
        'lastReceiveAgeSeconds': c._lastReceivedAt == null
            ? -1
            : DateTime.now().difference(c._lastReceivedAt!).inSeconds,
        'lastValidAgeSeconds': c._lastPacketAt == null
            ? -1
            : DateTime.now().difference(c._lastPacketAt!).inSeconds,
      },
  ];

  // Freeze the injected selection for connection-only live comparisons.
  @visibleForTesting
  void connectProvidedStreamsForTesting() {
    disconnect();
    _running = true;
    _installStreams(_defaults);
  }

  void connect({
    int stationLimit = defaultStationLimit,
    Set<String> enabledSources = const {'EarthScope', 'GEOFON'},
  }) {
    final normalizedLimit = normalizeStationLimit(stationLimit);
    final normalizedSources = enabledSources
        .where((source) => source == 'EarthScope' || source == 'GEOFON')
        .toSet();
    if (normalizedSources.isEmpty) {
      disconnect();
      return;
    }
    if (_running &&
        _currentStationLimit == normalizedLimit &&
        setEquals(_currentEnabledSources, normalizedSources)) {
      return;
    }
    if (_running) {
      disconnect();
    }
    _running = true;
    if (_useChannelCatalog) {
      _channelCatalog = FdsnChannelCatalog(_responseClientFactory());
    }
    final generation = ++_connectionGeneration;
    _currentStationLimit = normalizedLimit;
    _currentEnabledSources = normalizedSources;
    if (targetStationLimitNotifier.value != normalizedLimit) {
      targetStationLimitNotifier.value = normalizedLimit;
    }
    _setLinkedStationCount(0);
    _installStreams(
      _defaults
          .where((s) => normalizedSources.contains(s.source))
          .take(normalizedLimit)
          .toList(),
    );
    unawaited(
      _startConnections(normalizedLimit, normalizedSources, generation),
    );
  }

  Future<void> _startConnections(
    int stationLimit,
    Set<String> enabledSources,
    int generation,
  ) async {
    final streams = await _streamsForLimit(
      stationLimit,
      enabledSources,
      generation,
    );
    if (!_running ||
        _currentStationLimit != stationLimit ||
        !setEquals(_currentEnabledSources, enabledSources) ||
        _connectionGeneration != generation) {
      return;
    }

    _installStreams(streams);
    final incomplete = enabledSources.any((s) => _discoveryComplete[s] != true);
    _discoveryRetry?.cancel();
    _discoveryRetry = Timer(Duration(minutes: incomplete ? 1 : 15), () {
      _discoveryRetry = null;
      if (_isCurrentRun(generation)) {
        unawaited(_startConnections(stationLimit, enabledSources, generation));
      }
    });
  }

  void _installStreams(List<FdsnSeedLinkStream> streams) {
    final groups = <String, List<FdsnSeedLinkStream>>{};
    for (final stream in streams) {
      groups.putIfAbsent('${stream.host}:${stream.port}', () => []).add(stream);
    }

    for (final entry in groups.entries) {
      final first = entry.value.first;
      final previous = _connections
          .where((c) => c.host == first.host)
          .firstOrNull;
      final wanted = entry.value
          .map((s) => '${s.network}.${s.station}:${s.selector}')
          .toSet();
      if (previous != null) {
        final existing = previous.streams
            .map((s) => '${s.network}.${s.station}:${s.selector}')
            .toSet();
        if (setEquals(wanted, existing) &&
            previous.port == first.port &&
            previous.secure == first.secure) {
          continue;
        }
        _connections.remove(previous);
        previous.stop();
      }
      final connection = _SeedLinkConnection(
        host: first.host,
        port: first.port,
        secure: first.secure,
        streams: entry.value,
        onSample: _emitSample,
        onStatusChanged: _emitStatus,
        responseClientFactory: _responseClientFactory,
        channelCatalog: _channelCatalog,
        watchdogInterval: _watchdogInterval,
        networkTimeout: _networkTimeout,
        resumeAfterDisconnect: !_liveReconnectSources.contains(first.source),
        reconnectDelay: _reconnectDelay,
      );
      _connections.add(connection);
      connection.start();
    }
  }

  void disconnect() {
    _running = false;
    _connectionGeneration++;
    _discoveryRetry?.cancel();
    _discoveryRetry = null;
    _discovered.clear();
    _discoveryComplete.clear();
    _channelCatalog?.dispose();
    _channelCatalog = null;
    for (final connection in _connections) {
      connection.stop();
    }
    _connections.clear();
    for (final socket in _discoverySockets.toList(growable: false)) {
      socket.destroy();
    }
    _discoverySockets.clear();
    _setLinkedStationCount(0);
    dataTimeNotifier.value = null;
    onStatusChanged?.call(false);
  }

  void _emitSample(FdsnMotionSample sample) {
    if (!_running) return;
    recordDataTime(sample.timestamp);
    _controller.add(sample);
  }

  // This is a latest-observation summary, not the time of the last arrival.
  // Keep the sample timestamp untouched for downstream processing.
  void recordDataTime(DateTime timestamp) {
    if (timestamp.isAfter(DateTime.now().toUtc())) return;
    final previous = dataTimeNotifier.value;
    if (previous == null || timestamp.isAfter(previous)) {
      dataTimeNotifier.value = timestamp;
    }
  }

  Future<List<FdsnSeedLinkStream>> _streamsForLimit(
    int stationLimit,
    Set<String> enabledSources,
    int generation,
  ) async {
    final defaultForSources = _defaults
        .where((stream) => enabledSources.contains(stream.source))
        .toList(growable: false);
    if (stationLimit <= defaultForSources.length) {
      return defaultForSources.take(stationLimit).toList(growable: false);
    }

    final discovered = await _discoverSeedLinkStreams(
      stationLimit,
      enabledSources,
      generation,
    );
    if (discovered.isEmpty) return defaultForSources;
    return discovered.take(stationLimit).toList(growable: false);
  }

  Future<List<FdsnSeedLinkStream>> _discoverSeedLinkStreams(
    int stationLimit,
    Set<String> enabledSources,
    int generation,
  ) async {
    final targets = {for (final source in enabledSources) source: stationLimit};
    final lists = await Future.wait(
      _sources.where((source) => enabledSources.contains(source.source)).map((
        source,
      ) async {
        final loaded = await _loadSeedLinkStreams(
          source,
          generation,
          targets[source.source]!,
        );
        if (!_isCurrentRun(generation)) return <FdsnSeedLinkStream>[];
        if (loaded.isNotEmpty) {
          final previous = _discovered[source.source];
          _discovered[source.source] =
              _discoveryComplete[source.source] == true || previous == null
              ? loaded
              : {
                  for (final stream in previous)
                    '${stream.network}.${stream.station}': stream,
                  for (final stream in loaded)
                    '${stream.network}.${stream.station}': stream,
                }.values.toList();
        }
        final available =
            _discovered[source.source] ??
            _defaults.where((s) => s.source == source.source).toList();
        if (available.isNotEmpty) {
          _installStreams(_selectDiscovered(stationLimit, enabledSources));
        }
        return available;
      }),
    );
    if (!_isCurrentRun(generation)) return const [];
    return _selectStreams(lists, stationLimit);
  }

  List<FdsnSeedLinkStream> _selectDiscovered(int limit, Set<String> sources) =>
      _selectStreams([
        for (final source in sources)
          _discovered[source] ??
              _defaults.where((s) => s.source == source).toList(),
      ], limit);

  List<FdsnSeedLinkStream> _selectStreams(
    List<List<FdsnSeedLinkStream>> lists,
    int stationLimit,
  ) {
    final available = <String, FdsnSeedLinkStream>{
      for (final list in lists)
        for (final stream in list)
          '${stream.source}:${stream.network}.${stream.station}:${stream.selector}':
              stream,
    };
    final preferred = <String, FdsnSeedLinkStream>{};
    // A later catalogue must not move still-available stations between servers.
    for (final connection in _connections) {
      for (final stream in connection.streams) {
        final candidate =
            available['${stream.source}:${stream.network}.${stream.station}:${stream.selector}'];
        if (candidate != null) {
          preferred['${stream.network}.${stream.station}'] = candidate;
        }
      }
    }
    final seen = <String>{};
    final merged = <FdsnSeedLinkStream>[];

    void addStream(FdsnSeedLinkStream stream) {
      final key = '${stream.network}.${stream.station}';
      if (!seen.add(key)) return;
      merged.add(preferred[key] ?? stream);
    }

    final indices = List<int>.filled(lists.length, 0);
    while (merged.length < stationLimit) {
      var added = false;
      for (var i = 0; i < lists.length && merged.length < stationLimit; i++) {
        final list = lists[i];
        while (indices[i] < list.length) {
          final stream = list[indices[i]++];
          final before = merged.length;
          addStream(stream);
          if (merged.length > before) {
            added = true;
            break;
          }
        }
      }
      if (!added) break;
    }

    return merged;
  }

  Future<List<FdsnSeedLinkStream>> _loadSeedLinkStreams(
    _SeedLinkSource source,
    int generation,
    int limit,
  ) async {
    _discoveryComplete[source.source] = false;
    if (source.host == 'rtserve.earthscope.org' && _channelCatalog != null) {
      try {
        final response = await _channelCatalog!.client
            .get(
              Uri.https(source.host, '/streams'),
              headers: const {'User-Agent': 'FlutterRhythmQuake/1.0'},
            )
            .timeout(const Duration(seconds: 60));
        if (!_isCurrentRun(generation)) return const [];
        if (response.statusCode == 200) {
          final stations = await compute(parseFdsnStreamCatalog, (
            utf8.decode(response.bodyBytes),
            DateTime.now().toUtc(),
            limit,
          ));
          if (!_isCurrentRun(generation)) return const [];
          if (stations.isNotEmpty) {
            _discoveryComplete[source.source] = true;
            for (final network in stations.map((s) => s.network).toSet()) {
              unawaited(_channelCatalog!.load(source.source, network));
            }
            debugPrint(
              'SeedLink ${source.source}: ${stations.length} live stations from complete HTTP stream catalogue',
            );
            return [
              for (final s in stations)
                FdsnSeedLinkStream(
                  source: source.source,
                  host: source.host,
                  port: source.port,
                  secure: source.secure,
                  network: s.network,
                  station: s.station,
                  selector: s.selector,
                ),
            ];
          }
        }
      } catch (error) {
        if (!_isCurrentRun(generation)) return const [];
        debugPrint('SeedLink ${source.source} HTTP catalogue failed: $error');
      }
    }
    Socket? socket;
    Timer? timeoutTimer;
    Timer? deadline;
    final info = FdsnSeedLinkInfo(
      now: DateTime.now().toUtc(),
      limit: limit,
      clock: () => DateTime.now().toUtc(),
    );
    final done = Completer<void>();
    var preparedStations = 0;
    final preparedNetworks = <String>{};
    var finishReason = 'socket-closed';
    var bytesReceived = 0;

    void complete() {
      if (!done.isCompleted) done.complete();
    }

    try {
      socket = await (source.secure ? SecureSocket.connect : Socket.connect)(
        source.host,
        source.port,
        timeout: const Duration(seconds: 12),
      );
      if (!_isCurrentRun(generation)) {
        socket.destroy();
        return const [];
      }
      _discoverySockets.add(socket);
      deadline = Timer(const Duration(minutes: 8), () {
        finishReason = 'deadline';
        complete();
      });
      void idleTimeout() {
        finishReason = 'idle-timeout';
        complete();
      }

      timeoutTimer = Timer(const Duration(seconds: 90), idleTimeout);
      socket.listen(
        (chunk) {
          if (!_isCurrentRun(generation)) {
            complete();
            return;
          }
          timeoutTimer?.cancel();
          bytesReceived += chunk.length;
          timeoutTimer = Timer(const Duration(seconds: 90), idleTimeout);
          try {
            info.addBytes(chunk);
            for (final station in info.stations.skip(preparedStations)) {
              final catalog = _channelCatalog;
              if (catalog != null && preparedNetworks.add(station.network)) {
                unawaited(catalog.load(source.source, station.network));
              }
            }
            preparedStations = info.stations.length;
            if (info.complete || info.enough) {
              finishReason = info.complete ? 'complete' : 'limit';
              complete();
            }
          } catch (e) {
            debugPrint('SeedLink ${source.source} INFO parse failed: $e');
            finishReason = 'parse-error';
            complete();
          }
        },
        onDone: complete,
        onError: (_) {
          finishReason = 'socket-error';
          complete();
        },
        cancelOnError: true,
      );
      socket.add(ascii.encode('INFO STREAMS\r\n'));
      await done.future;
    } catch (e) {
      if (_isCurrentRun(generation)) {
        debugPrint('SeedLink ${source.host}:${source.port} INFO failed: $e');
      }
      return const [];
    } finally {
      timeoutTimer?.cancel();
      deadline?.cancel();
      if (socket != null) _discoverySockets.remove(socket);
      socket?.destroy();
    }

    if (!_isCurrentRun(generation)) return const [];
    _discoveryComplete[source.source] = info.complete || info.enough;
    final streams = [
      for (final s in info.stations)
        FdsnSeedLinkStream(
          source: source.source,
          host: source.host,
          port: source.port,
          secure: source.secure,
          network: s.network,
          station: s.station,
          selector: s.selector,
        ),
    ];
    debugPrint(
      'SeedLink ${source.source}: ${streams.length} live stations found; complete=${info.complete}; end=$finishReason; bytes=$bytesReceived',
    );
    return streams;
  }

  bool _isCurrentRun(int generation) =>
      _running && _connectionGeneration == generation;

  void _emitStatus() {
    if (!_running) {
      _setLinkedStationCount(0);
      onStatusChanged?.call(false);
      return;
    }
    final linkedStations = <String>{};
    for (final connection in _connections) {
      if (connection.isConnected) {
        linkedStations.addAll(connection.stationCodes);
      }
    }
    _setLinkedStationCount(linkedStations.length);
    onStatusChanged?.call(_connections.any((c) => c.isConnected));
  }

  void _setLinkedStationCount(int value) {
    if (linkedStationCountNotifier.value == value) return;
    linkedStationCountNotifier.value = value;
  }

  void dispose() {
    disconnect();
    linkedStationCountNotifier.dispose();
    targetStationLimitNotifier.dispose();
    dataTimeNotifier.dispose();
    _controller.close();
  }
}

typedef _ChannelResponse = FdsnChannelSensitivity;

class _MotionMetrics {
  final double? pga;
  final double? pgv;
  final double? intensity;

  const _MotionMetrics({this.pga, this.pgv, this.intensity});

  bool get hasMeasurement => pga != null || pgv != null || intensity != null;
}

class _AsyncLimiter {
  final int maxConcurrent;
  int _active = 0;
  final List<Completer<void>> _queue = [];

  _AsyncLimiter(this.maxConcurrent);

  Future<T> run<T>(Future<T> Function() task) async {
    if (_active >= maxConcurrent) {
      final completer = Completer<void>();
      _queue.add(completer);
      await completer.future;
    }

    _active++;
    try {
      return await task();
    } finally {
      _active--;
      if (_queue.isNotEmpty) {
        _queue.removeAt(0).complete();
      }
    }
  }
}

class _SeedLinkConnection {
  final bool secure;
  final FdsnChannelCatalog? channelCatalog;
  static const int _packetSize = 520;
  static final _responseLoadLimiter = _AsyncLimiter(8);

  final String host;
  final int port;
  final List<FdsnSeedLinkStream> streams;
  final void Function(FdsnMotionSample sample) onSample;
  final VoidCallback onStatusChanged;
  final http.Client Function() responseClientFactory;
  final Duration watchdogInterval;
  final Duration networkTimeout;
  final bool resumeAfterDisconnect;
  final Duration reconnectDelay;

  Socket? _socket;
  Timer? _reconnectTimer;
  Timer? _watchdog;
  http.Client? _httpClient;
  bool _running = false;
  int _runGeneration = 0;
  bool _connected = false;
  int _activePacketJobs = 0;
  final List<int> _buffer = [];
  final Map<String, Uint8List> _pendingPackets = {};
  final Map<String, DateTime> _receivedStations = {};
  final Set<String> _acceptedStations = {};
  int _replyIndex = 0;
  bool _selectionOk = true;
  DateTime? _lastPacketAt;
  DateTime? _lastReceivedAt;
  int _packetCount = 0;
  int _connectAttempts = 0;
  String _lastCloseReason = '';
  int _staleCount = 0;
  final Map<int, int> _decodeRejected = {};
  final Map<String, int> _resumeSequences = {};
  final Map<String, DateTime> _resumeObservationTimes = {};
  final Map<String, _MiniSeedRecord> _measurementRecords = {};
  final Set<String> _measurementJobs = {};
  final _metadataRouting = FdsnMetadataRouting();
  final Map<String, Future<_ChannelResponse?>> _responseCache = {};
  final Map<String, DateTime> _responseRetryAfter = {};
  late final Map<String, String> _stationSources = {
    for (final stream in streams)
      '${stream.network}.${stream.station}': stream.source,
  };

  _SeedLinkConnection({
    required this.host,
    required this.port,
    required this.streams,
    required this.onSample,
    required this.onStatusChanged,
    this.responseClientFactory = http.Client.new,
    this.channelCatalog,
    this.secure = false,
    this.watchdogInterval = const Duration(seconds: 15),
    this.networkTimeout = const Duration(minutes: 3),
    this.resumeAfterDisconnect = true,
    this.reconnectDelay = const Duration(seconds: 10),
  });

  bool get isConnected => _connected;
  Set<String> get stationCodes => _receivedStations.keys.toSet();

  void start() {
    if (_running) return;
    _running = true;
    final generation = ++_runGeneration;
    _httpClient = responseClientFactory();
    _connect(generation);
  }

  void stop() {
    _running = false;
    _runGeneration++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _watchdog?.cancel();
    _watchdog = null;
    final socket = _socket;
    _socket = null;
    socket?.destroy();
    _httpClient?.close();
    _httpClient = null;
    _responseCache.clear();
    _responseRetryAfter.clear();
    _buffer.clear();
    _pendingPackets.clear();
    _measurementRecords.clear();
    _measurementJobs.clear();
    _receivedStations.clear();
    _resumeSequences.clear();
    _resumeObservationTimes.clear();
    _setConnected(false);
  }

  Future<void> _connect(int generation) async {
    if (!_isCurrentRun(generation) || _socket != null) return;
    _connectAttempts++;
    try {
      final socket = await (secure ? SecureSocket.connect : Socket.connect)(
        host,
        port,
        timeout: const Duration(seconds: 12),
      );
      if (!_isCurrentRun(generation)) {
        socket.destroy();
        return;
      }
      _socket = socket;
      _buffer.clear();
      _acceptedStations.clear();
      _replyIndex = 0;
      _selectionOk = true;
      _lastPacketAt = null;
      _lastReceivedAt = DateTime.now();
      socket.listen(
        (bytes) {
          if (_isCurrentRun(generation) && identical(_socket, socket)) {
            if (bytes.isNotEmpty) _lastReceivedAt = DateTime.now();
            _handleBytes(bytes, generation);
          }
        },
        onDone: () => _handleClosed(socket, generation, reason: 'peer closed'),
        onError: (error) {
          debugPrint('SeedLink $host:$port error: $error');
          _handleClosed(socket, generation, reason: 'socket error: $error');
        },
        cancelOnError: true,
      );
      _sendSelections(socket);
      _watchdog?.cancel();
      _watchdog = Timer.periodic(watchdogInterval, (_) {
        if (!_isCurrentRun(generation) || !identical(_socket, socket)) return;
        final now = DateTime.now();
        final before = _receivedStations.length;
        _receivedStations.removeWhere(
          (_, t) => now.difference(t) > FdsnSeedLinkInfo.maxDataAge,
        );
        if (_receivedStations.length != before) onStatusChanged();
        // Freshness controls map eligibility, not whether the transport is alive.
        if (now.difference(_lastReceivedAt!) > networkTimeout) {
          debugPrint('SeedLink $host:$port: receive timeout, reconnecting');
          _resumeSequences.clear();
          _resumeObservationTimes.clear();
          _handleClosed(socket, generation, reason: 'network receive timeout');
        }
      });
    } catch (e) {
      if (_isCurrentRun(generation)) {
        _lastCloseReason = 'connect failed: $e';
        debugPrint('SeedLink $host:$port connect failed: $e');
        final socket = _socket;
        if (socket != null) {
          _handleClosed(socket, generation, reason: _lastCloseReason);
          return;
        }
      }
      _scheduleReconnect(generation);
    }
  }

  void _sendSelections(Socket socket) {
    final now = DateTime.now().toUtc();
    for (final stream in streams) {
      _sendLine(socket, 'STATION ${stream.station} ${stream.network}');
      _sendLine(socket, 'SELECT ${stream.selector}');
      final key = '${stream.network}.${stream.station}';
      final observed = _resumeObservationTimes[key];
      if (observed == null ||
          now.difference(observed) > FdsnSeedLinkInfo.maxDataAge) {
        _resumeSequences.remove(key);
        _resumeObservationTimes.remove(key);
      }
      final sequence = _resumeSequences[key];
      _sendLine(
        socket,
        sequence == null
            ? 'DATA'
            : 'DATA ${((sequence + 1) & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}',
      );
    }
    _sendLine(socket, 'END');
  }

  void _sendLine(Socket socket, String line) {
    socket.add(ascii.encode('$line\r\n'));
  }

  void _handleBytes(Uint8List bytes, int generation) {
    if (!_isCurrentRun(generation)) return;
    _buffer.addAll(bytes);
    while (_replyIndex < streams.length * 3 && _buffer.length >= 2) {
      if (_buffer[0] == 0x53 && _buffer[1] == 0x4c) break;
      final newline = _buffer.indexOf(10);
      if (newline < 0) return;
      final reply = ascii
          .decode(_buffer.sublist(0, newline), allowInvalid: true)
          .trim();
      _buffer.removeRange(0, newline + 1);
      if (reply.isEmpty) continue;
      _selectionOk = _selectionOk && reply == 'OK';
      final stream = streams[_replyIndex ~/ 3];
      _replyIndex++;
      if (_replyIndex % 3 == 0) {
        if (_selectionOk) {
          _acceptedStations.add('${stream.network}.${stream.station}');
        } else {
          _resumeSequences.remove('${stream.network}.${stream.station}');
          _resumeObservationTimes.remove('${stream.network}.${stream.station}');
          debugPrint(
            'SeedLink $host: subscription rejected ${stream.network}.${stream.station}',
          );
        }
        _selectionOk = true;
      }
    }
    var consumed = 0;
    while (true) {
      final start = _findSeedLinkHeader(_buffer, consumed);
      if (start < 0) {
        consumed = max(consumed, _buffer.length - 7);
        break;
      }
      if (_buffer.length - start < _packetSize) {
        consumed = start;
        break;
      }
      final packet = Uint8List(_packetSize)
        ..setRange(0, _packetSize, _buffer, start);
      consumed = start + _packetSize;
      _schedulePacket(packet, generation);
    }
    // Compact once per socket chunk, instead of shifting all remaining packets
    // after each 520-byte record.
    if (consumed > 0) _buffer.removeRange(0, consumed);
  }

  void _schedulePacket(Uint8List packet, int generation) {
    if (!_isCurrentRun(generation)) return;
    if (_activePacketJobs >= 200) {
      final key = ascii.decode(packet.sublist(16, 28), allowInvalid: true);
      // Keep the latest raw record per NSLC while metadata is loading. A busy
      // station must not discard the first records of other stations.
      _pendingPackets[key] = packet;
      return;
    }
    _activePacketJobs++;
    unawaited(
      _handlePacket(packet, generation)
          .catchError((Object error) {
            if (_isCurrentRun(generation)) {
              debugPrint('SeedLink record rejected: $error');
            }
          })
          .whenComplete(() {
            _activePacketJobs--;
            if (_running && _pendingPackets.isNotEmpty) {
              final key = _pendingPackets.keys.first;
              final next = _pendingPackets.remove(key)!;
              _schedulePacket(next, _runGeneration);
            }
          }),
    );
  }

  int _findSeedLinkHeader(List<int> data, [int offset = 0]) {
    for (var i = offset; i <= data.length - 8; i++) {
      if (data[i] != 0x53 || data[i + 1] != 0x4c) continue; // SL
      var ok = true;
      for (var j = i + 2; j < i + 8; j++) {
        final b = data[j];
        final isHex = (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x46);
        if (!isHex) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  Future<void> _handlePacket(Uint8List packet, int generation) async {
    if (!_isCurrentRun(generation)) return;
    _packetCount++;
    final record = Uint8List.sublistView(packet, 8);
    final miniSeed = _MiniSeedRecord.tryParse(record);
    if (miniSeed == null || miniSeed.samples.isEmpty) {
      final data = ByteData.sublistView(record);
      final endian = _MiniSeedRecord._detectBigEndian(data)
          ? Endian.big
          : Endian.little;
      final encoding =
          _MiniSeedBlockette1000.tryParse(
            record,
            data.getUint16(46, endian),
            endian,
          )?.encoding ??
          -1;
      _decodeRejected.update(encoding, (n) => n + 1, ifAbsent: () => 1);
      return;
    }

    final source = _stationSources['${miniSeed.network}.${miniSeed.station}'];
    if (source == null) return;
    final stationCode = '${miniSeed.network}.${miniSeed.station}';
    if (!_acceptedStations.contains(stationCode)) return;
    if (!_isCurrentRun(generation)) return;
    final now = DateTime.now().toUtc();
    if (miniSeed.startTime.isAfter(now) ||
        now.difference(miniSeed.startTime) > FdsnSeedLinkInfo.maxDataAge) {
      _staleCount++;
      _setConnected(true);
      return;
    }
    _lastPacketAt = DateTime.now();
    final sequence = int.parse(ascii.decode(packet.sublist(2, 8)), radix: 16);
    final previousSequence = _resumeSequences[stationCode];
    if (previousSequence == null ||
        ((sequence - previousSequence) & 0xffffff) < 0x800000) {
      _resumeSequences[stationCode] = sequence;
      _resumeObservationTimes[stationCode] = miniSeed.startTime;
    }
    final added = !_receivedStations.containsKey('$source:$stationCode');
    final previousObservation = _receivedStations['$source:$stationCode'];
    if (previousObservation == null ||
        miniSeed.startTime.isAfter(previousObservation)) {
      _receivedStations['$source:$stationCode'] = miniSeed.startTime;
    }
    if (!_connected) {
      _setConnected(true);
    } else if (added) {
      onStatusChanged();
    }

    onSample(
      FdsnMotionSample(
        source: source,
        network: miniSeed.network,
        station: miniSeed.station,
        channel: miniSeed.channel,
        timestamp: miniSeed.startTime,
        active: true,
      ),
    );

    if (channelCatalog != null) {
      final key =
          '${miniSeed.network}.${miniSeed.station}.${miniSeed.location}.${miniSeed.channel}';
      final previous = _measurementRecords[key];
      if (previous == null ||
          !miniSeed.startTime.isBefore(previous.startTime)) {
        _measurementRecords[key] = miniSeed;
      }
      if (_measurementJobs.add(key)) {
        unawaited(_measureLatest(key, source, miniSeed, generation));
      }
      return;
    }
    final response = await _responseFor(source, miniSeed, generation);
    if (response == null || !_isCurrentRun(generation)) return;

    final metrics = _calculateMotionMetrics(miniSeed, response);
    if (!metrics.hasMeasurement) return;

    onSample(
      FdsnMotionSample(
        source: source,
        network: miniSeed.network,
        station: miniSeed.station,
        channel: miniSeed.channel,
        timestamp: miniSeed.startTime,
        pga: metrics.pga,
        pgv: metrics.pgv,
        intensity: metrics.intensity,
        active: true,
      ),
    );
  }

  Future<void> _measureLatest(
    String key,
    String source,
    _MiniSeedRecord initial,
    int generation,
  ) async {
    try {
      var response = await _responseFor(source, initial, generation);
      if (!_isCurrentRun(generation)) return;
      final record = _measurementRecords.remove(key);
      if (record == null || response == null) return;
      if (!response.covers(record.startTime)) {
        response = await _responseFor(source, record, generation);
      }
      if (!_isCurrentRun(generation) || response == null) return;
      final now = DateTime.now().toUtc();
      if (record.startTime.isAfter(now) ||
          now.difference(record.startTime) > FdsnSeedLinkInfo.maxDataAge) {
        return;
      }
      final metrics = _calculateMotionMetrics(record, response);
      if (!metrics.hasMeasurement) return;
      onSample(
        FdsnMotionSample(
          source: source,
          network: record.network,
          station: record.station,
          channel: record.channel,
          timestamp: record.startTime,
          pga: metrics.pga,
          pgv: metrics.pgv,
          intensity: metrics.intensity,
          active: true,
        ),
      );
    } catch (error) {
      if (_isCurrentRun(generation)) debugPrint('FDSN measurement: $error');
    } finally {
      if (_isCurrentRun(generation)) {
        _measurementJobs.remove(key);
        final next = _measurementRecords[key];
        if (next != null && _measurementJobs.add(key)) {
          unawaited(_measureLatest(key, source, next, generation));
        }
      }
    }
  }

  Future<_ChannelResponse?> _responseFor(
    String source,
    _MiniSeedRecord record,
    int generation,
  ) async {
    if (!_isCurrentRun(generation)) return Future.value(null);
    final key =
        '$source:${record.network}.${record.station}.${record.location}.${record.channel}';
    final cached = _responseCache[key];
    if (cached != null) {
      final value = await cached;
      if (!_isCurrentRun(generation)) return null;
      if (value != null && value.covers(record.startTime)) return value;
      final retryAfter = _responseRetryAfter[key];
      if (value == null &&
          retryAfter != null &&
          DateTime.now().isBefore(retryAfter)) {
        return null;
      }
      if (identical(_responseCache[key], cached)) _responseCache.remove(key);
    }
    return _responseCache.putIfAbsent(
      key,
      () => _loadResponse(source, record, generation).then((value) {
        if (_isCurrentRun(generation)) {
          if (value == null) {
            _responseRetryAfter[key] = DateTime.now().add(
              const Duration(minutes: 1),
            );
          } else {
            _responseRetryAfter.remove(key);
          }
        }
        return value;
      }),
    );
  }

  Future<_ChannelResponse?> _loadResponse(
    String source,
    _MiniSeedRecord record,
    int generation,
  ) {
    final catalog = channelCatalog;
    if (catalog != null) {
      return catalog
          .find(
            source: source,
            network: record.network,
            station: record.station,
            location: record.location,
            channel: record.channel,
            time: record.startTime,
          )
          .then((result) {
            if (!_isCurrentRun(generation)) return null;
            _publishChannelStation(source, record, result);
            return result;
          });
    }
    final client = _httpClient;
    if (!_isCurrentRun(generation) || client == null) {
      return Future.value(null);
    }
    return _responseLoadLimiter.run(() async {
      if (!_isCurrentRun(generation) || !identical(_httpClient, client)) {
        return null;
      }
      final base = source == 'GEOFON'
          ? 'https://geofon.gfz-potsdam.de/fdsnws/station/1/query'
          : 'https://service.earthscope.org/fdsnws/station/1/query';
      final query = <String, String>{
        'network': record.network,
        'station': record.station,
        'channel': record.channel,
        'level': 'channel',
        'format': 'text',
        'location': record.location.isEmpty ? '--' : record.location,
        'starttime': record.startTime.toIso8601String(),
        'endtime': record.startTime.toIso8601String(),
        'nodata': '204',
      };

      Future<_ChannelResponse?> fetch(Uri endpoint) async {
        try {
          final response = await client
              .get(
                endpoint.replace(queryParameters: query),
                headers: const {
                  'Accept': 'text/plain,*/*',
                  'User-Agent': 'FlutterRhythmQuake/1.0',
                },
              )
              .timeout(const Duration(seconds: 12));
          if (!_isCurrentRun(generation) ||
              !identical(_httpClient, client) ||
              response.statusCode != 200) {
            return null;
          }
          return FdsnChannelSensitivity.parse(
            utf8.decode(response.bodyBytes),
            network: record.network,
            station: record.station,
            location: record.location,
            channel: record.channel,
            time: record.startTime,
          );
        } catch (e) {
          if (_isCurrentRun(generation)) {
            debugPrint('FDSN metadata ${record.network}.${record.station}: $e');
          }
          return null;
        }
      }

      var result = await fetch(Uri.parse(base));
      if (result == null && source == 'GEOFON' && _isCurrentRun(generation)) {
        final routes = await _metadataRouting.resolve(client, record.network);
        for (final route in routes) {
          if (!_isCurrentRun(generation)) return null;
          if (route.host == Uri.parse(base).host) continue;
          result = await fetch(route);
          if (result != null) break;
        }
      }
      if (!_isCurrentRun(generation)) return null;
      _publishChannelStation(source, record, result);
      return result;
    });
  }

  void _publishChannelStation(
    String source,
    _MiniSeedRecord record,
    _ChannelResponse? result,
  ) {
    if (result != null) {
      final lat = result.latitude;
      final lon = result.longitude;
      if (lat != null &&
          lon != null &&
          lat.isFinite &&
          lon.isFinite &&
          lat >= -90 &&
          lat <= 90 &&
          lon >= -180 &&
          lon <= 180) {
        final service = source == 'GEOFON'
            ? FdsnStationService.geofon
            : FdsnStationService.earthScope;
        service.acceptChannelStation(
          FdsnStation(
            network: record.network,
            station: record.station,
            location: record.location,
            coordinate: LatLng(lat, lon),
            source: source,
            elevation: result.elevation,
            startTime: result.start,
            endTime: result.end,
          ),
        );
      }
    }
  }

  _MotionMetrics _calculateMotionMetrics(
    _MiniSeedRecord record,
    _ChannelResponse response,
  ) {
    if (record.sampleRate <= 0 || record.samples.length < 2) {
      return const _MotionMetrics();
    }

    final centered = Float64List(record.samples.length);
    var sum = 0.0;
    for (var i = 0; i < centered.length; i++) {
      centered[i] = record.samples[i] / response.sensitivity;
      sum += centered[i];
    }
    final mean = sum / centered.length;
    for (var i = 0; i < centered.length; i++) {
      centered[i] -= mean;
    }
    final dt = 1.0 / record.sampleRate;

    double? pga;
    double? pgv;
    final unit = response.unit.replaceAll(' ', '');

    if (_isAccelerationUnit(unit)) {
      final accel = centered;
      pga = accel.map((v) => v.abs()).reduce(max) * 100.0;
      var velocity = 0.0;
      var maxVelocity = 0.0;
      for (final a in accel) {
        velocity += a * dt;
        maxVelocity = max(maxVelocity, velocity.abs());
      }
      pgv = maxVelocity * 100.0;
    } else if (_isVelocityUnit(unit)) {
      final velocity = centered;
      pgv = velocity.map((v) => v.abs()).reduce(max) * 100.0;
      var maxAccel = 0.0;
      for (var i = 1; i < velocity.length; i++) {
        maxAccel = max(maxAccel, ((velocity[i] - velocity[i - 1]) / dt).abs());
      }
      pga = maxAccel * 100.0;
    } else if (_isDisplacementUnit(unit)) {
      final displacement = centered;
      final velocity = <double>[];
      for (var i = 1; i < displacement.length; i++) {
        velocity.add((displacement[i] - displacement[i - 1]) / dt);
      }
      if (velocity.isNotEmpty) {
        pgv = velocity.map((v) => v.abs()).reduce(max) * 100.0;
      }
      if (velocity.length >= 2) {
        var maxAccel = 0.0;
        for (var i = 1; i < velocity.length; i++) {
          maxAccel = max(
            maxAccel,
            ((velocity[i] - velocity[i - 1]) / dt).abs(),
          );
        }
        pga = maxAccel * 100.0;
      }
    }

    if (pga != null && (!pga.isFinite || pga <= 0)) pga = null;
    if (pgv != null && (!pgv.isFinite || pgv <= 0)) pgv = null;

    final intensity = _instrumentalMmi(pgaGal: pga, pgvCms: pgv);
    return _MotionMetrics(pga: pga, pgv: pgv, intensity: intensity);
  }

  double? _instrumentalMmi({double? pgaGal, double? pgvCms}) {
    final pgaMmi = _mmiFromPgaGal(pgaGal);
    final pgvMmi = _mmiFromPgvCms(pgvCms);
    if (pgaMmi == null) return pgvMmi;
    if (pgvMmi == null) return pgaMmi;

    // PGA is usually more stable for weaker shaking; PGV carries stronger
    // shaking better. Around the transition, use the stronger estimate.
    final preferred = pgvMmi >= 5.0 ? pgvMmi : max(pgaMmi, pgvMmi);
    return preferred.clamp(1.0, 10.0).toDouble();
  }

  double? _mmiFromPgaGal(double? pgaGal) {
    if (pgaGal == null || pgaGal <= 0 || !pgaGal.isFinite) return null;
    final logPga = log(pgaGal) / ln10;
    final mmi = logPga <= 1.57 ? 1.78 + 1.55 * logPga : -1.60 + 3.70 * logPga;
    return mmi.isFinite ? mmi.clamp(1.0, 10.0).toDouble() : null;
  }

  double? _mmiFromPgvCms(double? pgvCms) {
    if (pgvCms == null || pgvCms <= 0 || !pgvCms.isFinite) return null;
    final logPgv = log(pgvCms) / ln10;
    final mmi = logPgv <= 0.53 ? 3.78 + 1.47 * logPgv : 2.89 + 3.16 * logPgv;
    return mmi.isFinite ? mmi.clamp(1.0, 10.0).toDouble() : null;
  }

  bool _isAccelerationUnit(String unit) =>
      unit.contains('M/S**2') ||
      unit.contains('M/S/S') ||
      unit.contains('M/SEC**2') ||
      unit.contains('M/SEC/SEC');

  bool _isVelocityUnit(String unit) =>
      unit == 'M/S' || unit == 'M/SEC' || unit.contains('M/S');

  bool _isDisplacementUnit(String unit) => unit == 'M' || unit == 'METER';

  void _handleClosed(
    Socket socket,
    int generation, {
    String reason = 'closed',
  }) {
    if (!identical(_socket, socket)) {
      socket.destroy();
      return;
    }
    _lastCloseReason = reason;
    // Detach first: destroy can synchronously deliver onDone on some transports.
    _socket = null;
    socket.destroy();
    _watchdog?.cancel();
    _watchdog = null;
    _buffer.clear();
    _pendingPackets.clear();
    _measurementRecords.clear();
    _measurementJobs.clear();
    _receivedStations.clear();
    // GQ's live reader re-subscribes from the current edge after a disconnect.
    if (!resumeAfterDisconnect) {
      _resumeSequences.clear();
      _resumeObservationTimes.clear();
    }
    _setConnected(false);
    if (_isCurrentRun(generation)) {
      _scheduleReconnect(++_runGeneration);
    }
  }

  void _scheduleReconnect(int generation) {
    if (!_isCurrentRun(generation) || _reconnectTimer != null) return;
    _reconnectTimer = Timer(reconnectDelay, () {
      _reconnectTimer = null;
      if (_isCurrentRun(generation)) _connect(generation);
    });
  }

  bool _isCurrentRun(int generation) =>
      _running && _runGeneration == generation;

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    onStatusChanged();
  }
}

@visibleForTesting
List<int>? decodeFdsnRecordForTest(Uint8List record) =>
    _MiniSeedRecord.tryParse(record)?.samples;

@visibleForTesting
Map<String, double?> fdsnMetricsForTest(
  List<int> samples,
  double sampleRate,
  double sensitivity,
  String unit,
) {
  final connection = _SeedLinkConnection(
    host: '',
    port: 0,
    streams: [],
    onSample: (_) {},
    onStatusChanged: () {},
  );
  final metrics = connection._calculateMotionMetrics(
    _MiniSeedRecord(
      network: 'XX',
      station: 'TEST',
      location: '',
      channel: 'HNZ',
      startTime: DateTime.utc(2026),
      sampleRate: sampleRate,
      samples: samples,
    ),
    FdsnChannelSensitivity(sensitivity, unit, DateTime.utc(2026), null),
  );
  return {'pga': metrics.pga, 'pgv': metrics.pgv, 'mmi': metrics.intensity};
}

class _MiniSeedRecord {
  final String network;
  final String station;
  final String location;
  final String channel;
  final DateTime startTime;
  final double sampleRate;
  final List<int> samples;

  const _MiniSeedRecord({
    required this.network,
    required this.station,
    required this.location,
    required this.channel,
    required this.startTime,
    required this.sampleRate,
    required this.samples,
  });

  static _MiniSeedRecord? tryParse(Uint8List record) {
    if (record.length < 48) return null;

    final station = _asciiField(record, 8, 5);
    final location = _asciiField(record, 13, 2);
    final channel = _asciiField(record, 15, 3);
    final network = _asciiField(record, 18, 2);
    if (station.isEmpty || channel.isEmpty || network.isEmpty) return null;

    final data = ByteData.sublistView(record);
    final bigEndian = _detectBigEndian(data);
    final endian = bigEndian ? Endian.big : Endian.little;
    final year = data.getUint16(20, endian);
    final dayOfYear = data.getUint16(22, endian);
    final hour = record[24];
    final minute = record[25];
    final second = record[26];
    final tenthMillis = data.getUint16(28, endian);
    final sampleCount = data.getUint16(30, endian);
    final sampleRateFactor = data.getInt16(32, endian);
    final sampleRateMultiplier = data.getInt16(34, endian);
    final dataOffset = data.getUint16(44, endian);
    final firstBlocketteOffset = data.getUint16(46, endian);

    final daysInYear = DateTime.utc(
      year + 1,
    ).difference(DateTime.utc(year)).inDays;
    if (year < 1900 ||
        year > 2200 ||
        dayOfYear < 1 ||
        dayOfYear > daysInYear ||
        hour > 23 ||
        minute > 59 ||
        second > 60 ||
        tenthMillis > 9999) {
      return null;
    }
    final startTime = DateTime.utc(year, 1, 1)
        .add(Duration(days: dayOfYear - 1))
        .add(
          Duration(
            hours: hour,
            minutes: minute,
            seconds: second,
            microseconds: tenthMillis * 100,
          ),
        );

    final blockette = _MiniSeedBlockette1000.tryParse(
      record,
      firstBlocketteOffset,
      endian,
    );
    if (blockette == null) return null;
    final dataEndian = blockette.bigEndian ? Endian.big : Endian.little;
    final payload = dataOffset > 0 && dataOffset < record.length
        ? Uint8List.sublistView(record, dataOffset)
        : Uint8List(0);
    final samples = _MiniSeedDecoder.decode(
      payload,
      encoding: blockette.encoding,
      endian: dataEndian,
      sampleCount: sampleCount,
    );
    if (samples.isEmpty) return null;

    return _MiniSeedRecord(
      network: network,
      station: station,
      location: location,
      channel: channel,
      startTime: startTime,
      sampleRate: _sampleRate(sampleRateFactor, sampleRateMultiplier),
      samples: samples,
    );
  }

  static bool _detectBigEndian(ByteData data) {
    final yearBig = data.getUint16(20, Endian.big);
    if (yearBig >= 1900 && yearBig <= 2200) return true;
    return false;
  }

  static String _asciiField(Uint8List bytes, int start, int length) {
    return ascii.decode(bytes.sublist(start, start + length)).trim();
  }

  static double _sampleRate(int factor, int multiplier) {
    if (factor == 0 || multiplier == 0) return 0;
    if (factor > 0 && multiplier > 0) return factor * multiplier.toDouble();
    if (factor > 0 && multiplier < 0) return factor / -multiplier;
    if (factor < 0 && multiplier > 0) return multiplier / -factor;
    return 1.0 / (factor.abs() * multiplier.abs());
  }
}

class _MiniSeedBlockette1000 {
  final int encoding;
  final bool bigEndian;

  const _MiniSeedBlockette1000({
    required this.encoding,
    required this.bigEndian,
  });

  static _MiniSeedBlockette1000? tryParse(
    Uint8List record,
    int offset,
    Endian endian,
  ) {
    var cursor = offset;
    final data = ByteData.sublistView(record);
    while (cursor >= 48 && cursor + 8 <= record.length) {
      final type = data.getUint16(cursor, endian);
      final next = data.getUint16(cursor + 2, endian);
      if (type == 1000) {
        return _MiniSeedBlockette1000(
          encoding: record[cursor + 4],
          bigEndian: record[cursor + 5] != 0,
        );
      }
      if (next == 0 || next <= cursor || next >= record.length) break;
      cursor = next;
    }
    return null;
  }
}

class _MiniSeedDecoder {
  static List<int> decode(
    Uint8List payload, {
    required int encoding,
    required Endian endian,
    required int sampleCount,
  }) {
    if (payload.isEmpty || sampleCount <= 0) return const [];
    switch (encoding) {
      case 1:
        return _decodeInt16(payload, endian, sampleCount);
      case 3:
        return _decodeInt32(payload, endian, sampleCount);
      case 10:
        return _decodeSteim1(payload, sampleCount, endian);
      case 11:
        return _decodeSteim2(payload, sampleCount, endian);
      default:
        return const [];
    }
  }

  static List<int> _decodeInt16(Uint8List payload, Endian endian, int count) {
    final data = ByteData.sublistView(payload);
    final out = <int>[];
    for (
      var offset = 0;
      offset + 2 <= payload.length && out.length < count;
      offset += 2
    ) {
      out.add(data.getInt16(offset, endian));
    }
    return out;
  }

  static List<int> _decodeInt32(Uint8List payload, Endian endian, int count) {
    final data = ByteData.sublistView(payload);
    final out = <int>[];
    for (
      var offset = 0;
      offset + 4 <= payload.length && out.length < count;
      offset += 4
    ) {
      out.add(data.getInt32(offset, endian));
    }
    return out;
  }

  static List<int> _decodeSteim1(
    Uint8List payload,
    int sampleCount,
    Endian endian,
  ) {
    final data = ByteData.sublistView(payload);
    final out = <int>[];
    int? previous;
    var skipFirstDifference = true;

    for (var frame = 0; frame + 64 <= payload.length; frame += 64) {
      final control = data.getUint32(frame, endian);
      for (var wordIndex = 1; wordIndex < 16; wordIndex++) {
        final wordOffset = frame + wordIndex * 4;
        final word = data.getUint32(wordOffset, endian);
        if (frame == 0 && wordIndex == 1) {
          previous = data.getInt32(wordOffset, endian);
          out.add(previous);
          if (out.length >= sampleCount) return out;
          continue;
        }
        if (frame == 0 && wordIndex == 2) continue;

        final seeded = previous;
        if (seeded == null) return out;
        var current = seeded;
        final code = (control >> (30 - 2 * wordIndex)) & 0x03;
        final diffs = switch (code) {
          1 => [for (var j = 0; j < 4; j++) data.getInt8(wordOffset + j)],
          2 => [
            data.getInt16(wordOffset, endian),
            data.getInt16(wordOffset + 2, endian),
          ],
          3 => [_signExtend(word, 32)],
          _ => const <int>[],
        };
        for (final diff in diffs) {
          // D0 links the previous record to X0; X0 is already in the output.
          if (skipFirstDifference) {
            skipFirstDifference = false;
            continue;
          }
          current = (current + diff).toSigned(32);
          previous = current;
          out.add(current);
          if (out.length >= sampleCount) return out;
        }
      }
    }
    return out;
  }

  static List<int> _decodeSteim2(
    Uint8List payload,
    int sampleCount,
    Endian endian,
  ) {
    final data = ByteData.sublistView(payload);
    final out = <int>[];
    int? previous;
    var skipFirstDifference = true;

    for (var frame = 0; frame + 64 <= payload.length; frame += 64) {
      final control = data.getUint32(frame, endian);
      for (var wordIndex = 1; wordIndex < 16; wordIndex++) {
        final wordOffset = frame + wordIndex * 4;
        final word = data.getUint32(wordOffset, endian);
        if (frame == 0 && wordIndex == 1) {
          previous = data.getInt32(wordOffset, endian);
          out.add(previous);
          if (out.length >= sampleCount) return out;
          continue;
        }
        if (frame == 0 && wordIndex == 2) continue;

        final seeded = previous;
        if (seeded == null) return out;
        var current = seeded;
        final code = (control >> (30 - 2 * wordIndex)) & 0x03;
        final diffs = code == 1
            ? [for (var j = 0; j < 4; j++) data.getInt8(wordOffset + j)]
            : _steim2Diffs(code, word);
        for (final diff in diffs) {
          if (skipFirstDifference) {
            skipFirstDifference = false;
            continue;
          }
          current = (current + diff).toSigned(32);
          previous = current;
          out.add(current);
          if (out.length >= sampleCount) return out;
        }
      }
    }
    return out;
  }

  static List<int> _steim2Diffs(int code, int word) {
    if (code == 0) return const [];
    if (code == 1) {
      return [
        _signExtend((word >> 24) & 0xff, 8),
        _signExtend((word >> 16) & 0xff, 8),
        _signExtend((word >> 8) & 0xff, 8),
        _signExtend(word & 0xff, 8),
      ];
    }

    final dnib = (word >> 30) & 0x03;
    if (code == 2) {
      return switch (dnib) {
        1 => [_signExtend(word & 0x3fffffff, 30)],
        2 => [
          _signExtend((word >> 15) & 0x7fff, 15),
          _signExtend(word & 0x7fff, 15),
        ],
        3 => [
          _signExtend((word >> 20) & 0x3ff, 10),
          _signExtend((word >> 10) & 0x3ff, 10),
          _signExtend(word & 0x3ff, 10),
        ],
        _ => const <int>[],
      };
    }

    return switch (dnib) {
      0 => [
        for (var shift = 24; shift >= 0; shift -= 6)
          _signExtend((word >> shift) & 0x3f, 6),
      ],
      1 => [
        for (var shift = 25; shift >= 0; shift -= 5)
          _signExtend((word >> shift) & 0x1f, 5),
      ],
      2 => [
        for (var shift = 24; shift >= 0; shift -= 4)
          _signExtend((word >> shift) & 0x0f, 4),
      ],
      _ => const <int>[],
    };
  }

  static int _signExtend(int value, int bits) {
    if (bits >= 32) return value.toSigned(32);
    final signBit = 1 << (bits - 1);
    final mask = (1 << bits) - 1;
    value &= mask;
    return (value & signBit) != 0 ? value - (1 << bits) : value;
  }
}
