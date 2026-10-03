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
import 'fdsn_source_catalog.dart';
import 'fdsn_connection_health.dart';
import 'fdsn_source_status.dart';
import 'fdsn_network_io.dart';
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
      _responseClientFactory = createFdsnHttpClient,
      _network = FdsnNetwork.instance,
      _useChannelCatalog = true,
      _watchdogInterval = const Duration(seconds: 15),
      _networkTimeout = const Duration(minutes: 5),
      _heartbeatInterval = const Duration(minutes: 4),
      _healthFactory = FdsnConnectionHealth.new,
      _liveReconnectSources = const {'EarthScope'},
      _reconnectDelay = const Duration(seconds: 10);

  @visibleForTesting
  FdsnMotionService.forTesting({
    required List<FdsnSeedLinkStream> streams,
    http.Client Function()? responseClientFactory,
    FdsnNetwork? network,
    bool useChannelCatalog = false,
    Duration watchdogInterval = const Duration(seconds: 15),
    Duration networkTimeout = const Duration(minutes: 5),
    Duration heartbeatInterval = const Duration(minutes: 4),
    FdsnConnectionHealth Function()? healthFactory,
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
       _network = network ?? FdsnNetwork.instance,
       _useChannelCatalog = useChannelCatalog,
       _watchdogInterval = watchdogInterval,
       _networkTimeout = networkTimeout,
       _heartbeatInterval = heartbeatInterval,
       _healthFactory = healthFactory ?? FdsnConnectionHealth.new,
       _liveReconnectSources = Set.unmodifiable(liveReconnectSources),
       _reconnectDelay = reconnectDelay;

  final List<_SeedLinkSource> _sources;
  final List<FdsnSeedLinkStream> _defaults;
  final http.Client Function() _responseClientFactory;
  final FdsnNetwork _network;
  final bool _useChannelCatalog;
  final Duration _watchdogInterval;
  final Duration _networkTimeout;
  final Duration _heartbeatInterval;
  final FdsnConnectionHealth Function() _healthFactory;
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

  static final List<_SeedLinkSource> _seedLinkSources = [
    for (final source in FdsnSourceCatalog.sources)
      _SeedLinkSource(
        source: source.name,
        host: source.host,
        port: source.port,
        secure: source.secure,
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
  final sourceStatusesNotifier = ValueNotifier<List<FdsnSourceStatus>>(
    const [],
  );
  Timer? _sourceStatusTimer;
  bool? _lastConnectedStatus;

  final List<_SeedLinkConnection> _connections = [];
  final Set<Socket> _discoverySockets = {};
  Timer? _discoveryRetry;
  final Map<String, List<FdsnSeedLinkStream>> _discovered = {};
  final Map<String, DateTime> _discoveredAt = {};
  final Map<String, bool> _discoveryComplete = {};
  bool _running = false;
  bool _initialDiscoveryComplete = false;
  int _currentStationLimit = defaultStationLimit;
  Set<String> _currentEnabledSources = FdsnSourceCatalog.names;
  int _connectionGeneration = 0;

  void Function(bool connected)? onStatusChanged;

  @visibleForTesting
  List<FdsnSeedLinkStream> get selectedStreams => [
    for (final connection in _connections) ...connection.streams,
  ];

  @visibleForTesting
  Set<String> get regionalStationCodes => {
    for (final entry in _discovered.entries)
      if (entry.key != 'EarthScope')
        for (final stream in entry.value) '${stream.network}.${stream.station}',
  };

  @visibleForTesting
  List<Map<String, Object>> get connectionDiagnostics => [
    for (final c in _connections)
      {
        'host': c.host,
        'networkRoute': c._networkRoute,
        'source': c.streams.first.source,
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
        'heartbeatsSent': c._heartbeatsSent,
        'heartbeatReplies': c._heartbeatReplies,
        'liveRecoveries': c._health.recoveries,
        'nextLiveRecoveryAt': c._health.nextRecoveryAt?.toIso8601String() ?? '',
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
    _currentEnabledSources = _defaults.map((s) => s.source).toSet();
    _startSourceStatusTimer();
    _installStreams(_defaults);
  }

  void connect({
    int stationLimit = defaultStationLimit,
    Set<String> enabledSources = FdsnSourceCatalog.names,
  }) {
    final normalizedLimit = normalizeStationLimit(stationLimit);
    final normalizedSources = enabledSources
        .where((name) => _sources.any((source) => source.source == name))
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
    _startSourceStatusTimer();
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

    _initialDiscoveryComplete = true;
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
    _channelCatalog?.selectStations(
      streams.map((s) => (s.source, s.network, s.station)),
    );
    final groups = <String, List<FdsnSeedLinkStream>>{};
    for (final stream in streams) {
      groups.putIfAbsent('${stream.host}:${stream.port}', () => []).add(stream);
    }

    // A source can lose every station to a more direct provider after discovery.
    for (final old in _connections.toList()) {
      if (!groups.containsKey('${old.host}:${old.port}')) {
        _connections.remove(old);
        old.stop();
      }
    }
    for (final entry in groups.entries) {
      final first = entry.value.first;
      final previous = _connections
          .where((c) => c.host == first.host && c.port == first.port)
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
        network: _network,
        channelCatalog: _channelCatalog,
        watchdogInterval: _watchdogInterval,
        networkTimeout: _networkTimeout,
        heartbeatInterval: _heartbeatInterval,
        health: _healthFactory(),
        negotiateBatch:
            FdsnSourceCatalog.find(first.source)?.batchSubscribe ?? false,
        resumeAfterDisconnect: !_liveReconnectSources.contains(first.source),
        reconnectDelay: _reconnectDelay,
      );
      _connections.add(connection);
      for (final network
          in entry.value.map((stream) => stream.network).toSet()) {
        unawaited(_channelCatalog?.load(first.source, network));
      }
      connection.start();
    }
    _publishSourceStatuses();
  }

  void _startSourceStatusTimer() {
    _sourceStatusTimer?.cancel();
    _sourceStatusTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _publishSourceStatuses(),
    );
  }

  /// Bounded to the selected stations, with no scan or UI notification per packet.
  List<FdsnSourceStatus> collectSourceStatuses({DateTime? now}) {
    if (!_running) return const [];
    final capturedAt = now ?? DateTime.now();
    return [
      for (final source in _currentEnabledSources)
        _sourceStatus(source, capturedAt),
    ];
  }

  FdsnSourceStatus _sourceStatus(String source, DateTime now) {
    final connections = _connections
        .where((c) => c._stationSources.containsValue(source))
        .toList(growable: false);
    var state = FdsnSourceConnectionState.connecting;
    if (connections.isEmpty) {
      if (_discoveryComplete[source] == true) {
        state = FdsnSourceConnectionState.idle;
      } else if (_initialDiscoveryComplete) {
        state = FdsnSourceConnectionState.failed;
      }
    } else if (connections.any(
      (c) =>
          (c._socket == null && c._lastCloseReason.isNotEmpty) ||
          (!c._batchMode &&
              c._replyIndex >= c.streams.length * 3 &&
              c._acceptedStations.isEmpty),
    )) {
      state = FdsnSourceConnectionState.failed;
    } else if (connections.any((c) => c.isConnected)) {
      state = FdsnSourceConnectionState.streaming;
    }
    return FdsnSourceStatus.fromObservations(
      source: source,
      state: state,
      now: now,
      observations: [
        for (final c in connections)
          for (final entry in c._stationSources.entries)
            if (entry.value == source)
              c._socket == null ? null : c._health.observationFor(entry.key),
      ],
    );
  }

  void _publishSourceStatuses() {
    acceptSourceStatuses(collectSourceStatuses());
  }

  // Also used by the UI isolate when Android owns the sockets in the foreground service.
  void acceptSourceStatuses(List<FdsnSourceStatus> statuses) {
    if (!listEquals(sourceStatusesNotifier.value, statuses)) {
      sourceStatusesNotifier.value = List.unmodifiable(statuses);
    }
  }

  void disconnect({bool clearSourceStatuses = true}) {
    _running = false;
    _lastConnectedStatus = null;
    _sourceStatusTimer?.cancel();
    _sourceStatusTimer = null;
    if (clearSourceStatuses) acceptSourceStatuses(const []);
    _initialDiscoveryComplete = false;
    _connectionGeneration++;
    _discoveryRetry?.cancel();
    _discoveryRetry = null;
    _discovered.clear();
    _discoveredAt.clear();
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
    // Regional catalogues can start independently. Do not expand EarthScope
    // until all regional discovery attempts have completed.
    final pending = {...enabledSources};
    final lists = await Future.wait(
      _sources.where((source) => enabledSources.contains(source.source)).map((
        source,
      ) async {
        final loaded = await _loadSeedLinkStreams(
          source,
          generation,
          0x7fffffff,
        );
        if (!_isCurrentRun(generation)) return <FdsnSeedLinkStream>[];
        final lastDiscovery = _discoveredAt[source.source];
        if (lastDiscovery == null ||
            DateTime.now().difference(lastDiscovery) >
                FdsnSeedLinkInfo.maxDataAge) {
          _discovered.remove(source.source);
        }
        if (loaded.isNotEmpty || _discoveryComplete[source.source] == true) {
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
          _discoveredAt[source.source] = DateTime.now();
        }
        final available =
            _discovered[source.source] ?? const <FdsnSeedLinkStream>[];
        pending.remove(source.source);
        if (!_initialDiscoveryComplete) {
          final ready = enabledSources.where(
            (name) =>
                !pending.contains(name) &&
                (name != 'EarthScope' ||
                    !pending.any((name) => name != 'EarthScope')),
          );
          _installStreams(
            _selectStreams([
              for (final name in ready) _discovered[name] ?? const [],
            ], stationLimit),
          );
        }
        return available;
      }),
    );
    if (!_isCurrentRun(generation)) return const [];
    return _selectStreams(lists, stationLimit);
  }

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
    // Keep a channel selection stable within its chosen provider. A regional
    // provider discovered later must still take precedence over EarthScope.
    for (final connection in _connections) {
      for (final stream in connection.streams) {
        final candidate =
            available['${stream.source}:${stream.network}.${stream.station}:${stream.selector}'];
        if (candidate != null) {
          preferred['${stream.network}.${stream.station}'] = candidate;
        }
      }
    }
    final providers = <String, FdsnSeedLinkStream>{};
    for (final list in lists) {
      for (final stream in list) {
        final key = '${stream.network}.${stream.station}';
        final current = providers[key];
        if (current == null ||
            (FdsnSourceCatalog.find(stream.source)?.priority ?? 0) <
                (FdsnSourceCatalog.find(current.source)?.priority ?? 0)) {
          providers[key] = stream;
        }
      }
    }
    final seen = <String>{};
    final merged = <FdsnSeedLinkStream>[];

    void addStream(FdsnSeedLinkStream stream) {
      final key = '${stream.network}.${stream.station}';
      final provider = providers[key]!;
      if (provider.source != stream.source) return;
      if (!seen.add(key)) return;
      final previous = preferred[key];
      merged.add(previous?.source == stream.source ? previous! : stream);
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

  @visibleForTesting
  List<FdsnSeedLinkStream> selectStreamsForTesting(
    List<List<FdsnSeedLinkStream>> lists,
    int limit,
  ) => _selectStreams(lists, limit);

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
    var finishReason = 'socket-closed';
    var bytesReceived = 0;

    void complete() {
      if (!done.isCompleted) done.complete();
    }

    try {
      socket = (await _network.connect(
        source.host,
        source.port,
        secure: source.secure,
        timeout: const Duration(seconds: 12),
      )).socket;
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
    final connected = _connections.any((c) => c.isConnected);
    if (_lastConnectedStatus != connected) {
      _lastConnectedStatus = connected;
      onStatusChanged?.call(connected);
    }
    // Selection assigns each source/station to one connection. Sum the small
    // set of connection counts without copying thousands of station keys.
    var linkedStations = 0;
    for (final connection in _connections) {
      if (connection.isConnected) {
        linkedStations += connection._receivedStations.length;
      }
    }
    _setLinkedStationCount(linkedStations);
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
    sourceStatusesNotifier.dispose();
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
  final FdsnNetwork network;
  String _networkRoute = '';
  bool _checkingRoute = false;
  final Duration watchdogInterval;
  final Duration networkTimeout;
  final Duration heartbeatInterval;
  final FdsnConnectionHealth _health;
  final bool negotiateBatch;
  final bool resumeAfterDisconnect;
  final Duration reconnectDelay;

  Socket? _socket;
  Timer? _reconnectTimer;
  Timer? _watchdog;
  Timer? _packetDrainTimer;
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
  bool _awaitingBatch = false;
  bool _batchMode = false;
  bool _serialSelection = false;
  DateTime? _lastPacketAt;
  DateTime? _lastReceivedAt;
  DateTime? _lastHeartbeatAt;
  bool _heartbeatPending = false;
  int _heartbeatsSent = 0;
  int _heartbeatReplies = 0;
  int _packetCount = 0;
  int _connectAttempts = 0;
  int _consecutiveFailures = 0;
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
    FdsnNetwork? network,
    this.channelCatalog,
    this.secure = false,
    this.watchdogInterval = const Duration(seconds: 15),
    this.networkTimeout = const Duration(minutes: 5),
    this.heartbeatInterval = const Duration(minutes: 4),
    required FdsnConnectionHealth health,
    this.negotiateBatch = false,
    this.resumeAfterDisconnect = true,
    this.reconnectDelay = const Duration(seconds: 10),
  }) : _health = health,
       network = network ?? FdsnNetwork.instance;

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
    _packetDrainTimer?.cancel();
    _packetDrainTimer = null;
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
      final connected = await network.connect(
        host,
        port,
        secure: secure,
        timeout: const Duration(seconds: 12),
      );
      final socket = connected.socket;
      if (!_isCurrentRun(generation)) {
        socket.destroy();
        return;
      }
      _socket = socket;
      _networkRoute = connected.route.directive;
      _buffer.clear();
      _acceptedStations.clear();
      _replyIndex = 0;
      _selectionOk = true;
      _awaitingBatch = negotiateBatch;
      _batchMode = false;
      _serialSelection = false;
      _lastPacketAt = null;
      _lastReceivedAt = DateTime.now();
      _heartbeatPending = false;
      _health.connected(_lastReceivedAt!);
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
      if (_awaitingBatch) {
        _sendLine(socket, 'BATCH');
      } else {
        _sendSelections(socket);
      }
      _watchdog?.cancel();
      _watchdog = Timer.periodic(watchdogInterval, (_) {
        if (!_isCurrentRun(generation) || !identical(_socket, socket)) return;
        unawaited(_checkNetworkRoute(socket, generation));
        final now = DateTime.now();
        final before = _receivedStations.length;
        _receivedStations.removeWhere(
          (_, t) => now.difference(t) > FdsnSeedLinkInfo.maxDataAge,
        );
        if (_receivedStations.length != before) onStatusChanged();
        // INFO is a liveness reply, never an observation or a freshness reset.
        if (now.difference(_lastReceivedAt!) > networkTimeout) {
          debugPrint('SeedLink $host:$port: receive timeout, reconnecting');
          _resumeSequences.clear();
          _resumeObservationTimes.clear();
          _handleClosed(socket, generation, reason: 'network receive timeout');
          return;
        }
        if (_health.shouldRecover(now.toUtc())) {
          _resumeSequences.clear();
          _resumeObservationTimes.clear();
          _handleClosed(
            socket,
            generation,
            reason: 'sustained observation lag',
          );
          return;
        }
        if (_replyIndex >= streams.length * 3 &&
            !_heartbeatPending &&
            now.difference(_lastReceivedAt!) >= heartbeatInterval &&
            (_lastHeartbeatAt == null ||
                now.difference(_lastHeartbeatAt!) >= heartbeatInterval)) {
          _lastHeartbeatAt = now;
          _heartbeatPending = true;
          _heartbeatsSent++;
          _sendLine(socket, 'INFO ID');
        } else if (_heartbeatPending &&
            _lastHeartbeatAt != null &&
            now.difference(_lastHeartbeatAt!) >= heartbeatInterval &&
            _lastReceivedAt!.isAfter(_lastHeartbeatAt!)) {
          // Some servers disable INFO. Continuing waveforms prove liveness.
          _heartbeatPending = false;
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

  Future<void> _checkNetworkRoute(Socket socket, int generation) async {
    if (_checkingRoute) return;
    _checkingRoute = true;
    try {
      final route = await network.resolve(network.socketUri(host, port));
      if (!_isCurrentRun(generation) || !identical(_socket, socket)) return;
      if (route.directive == _networkRoute) return;
      _resumeSequences.clear();
      _resumeObservationTimes.clear();
      _consecutiveFailures = 0;
      _handleClosed(socket, generation, reason: 'system proxy route changed');
    } catch (e) {
      // A failed configuration read is not evidence that the proxy was disabled.
      debugPrint('SeedLink $host:$port proxy refresh failed: $e');
    } finally {
      _checkingRoute = false;
    }
  }

  void _sendSelections(Socket socket) {
    for (var index = 0; index < streams.length * 3; index++) {
      _sendLine(socket, _selectionCommand(index));
    }
    _sendLine(socket, 'END');
  }

  String _selectionCommand(int index) {
    final stream = streams[index ~/ 3];
    if (index % 3 == 0) return 'STATION ${stream.station} ${stream.network}';
    if (index % 3 == 1) return 'SELECT ${stream.selector}';
    final now = DateTime.now().toUtc();
    final key = '${stream.network}.${stream.station}';
    final observed = _resumeObservationTimes[key];
    if (observed == null ||
        now.difference(observed) > FdsnSeedLinkInfo.maxDataAge) {
      _resumeSequences.remove(key);
      _resumeObservationTimes.remove(key);
    }
    final sequence = _resumeSequences[key];
    return sequence == null
        ? 'DATA'
        : 'DATA ${((sequence + 1) & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  void _sendLine(Socket socket, String line) {
    socket.add(ascii.encode('$line\r\n'));
  }

  void _handleBytes(Uint8List bytes, int generation) {
    if (!_isCurrentRun(generation)) return;
    _buffer.addAll(bytes);
    if (_awaitingBatch) {
      final newline = _buffer.indexOf(10);
      if (newline < 0) return;
      final reply = ascii
          .decode(_buffer.sublist(0, newline), allowInvalid: true)
          .trim();
      _buffer.removeRange(0, newline + 1);
      _awaitingBatch = false;
      if (reply == 'OK') {
        _batchMode = true;
        _replyIndex = streams.length * 3;
        _sendSelections(_socket!);
      } else {
        _serialSelection = true;
        _sendLine(_socket!, _selectionCommand(0));
      }
    }
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
      if (_serialSelection && reply != 'OK') {
        // Do not issue DATA against the previous station after a rejected
        // STATION/SELECT modifier in the non-BATCH protocol.
        _replyIndex = ((_replyIndex + 2) ~/ 3) * 3;
      }
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
      if (_serialSelection) {
        _sendLine(
          _socket!,
          _replyIndex < streams.length * 3
              ? _selectionCommand(_replyIndex)
              : 'END',
        );
      }
    }
    if (_packetDrainTimer == null) _drainPacketBuffer(generation);
  }

  void _drainPacketBuffer(int generation) {
    _packetDrainTimer = null;
    if (!_isCurrentRun(generation)) return;
    var consumed = 0;
    var processed = 0;
    // Bound synchronous decoding per event-loop turn. Keep every raw packet
    // in order, while allowing frame and input callbacks between bursts.
    while (processed < 128) {
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
      processed++;
      if (packet[2] == 0x49) {
        if (packet[7] == 0x20 && _heartbeatPending) {
          _heartbeatPending = false;
          _heartbeatReplies++;
        }
      } else {
        _schedulePacket(packet, generation);
      }
    }
    // Compact once per socket chunk, instead of shifting all remaining packets
    // after each 520-byte record.
    if (consumed > 0) _buffer.removeRange(0, consumed);
    if (processed == 128 && _buffer.length >= _packetSize) {
      _packetDrainTimer = Timer(
        Duration.zero,
        () => _drainPacketBuffer(generation),
      );
    }
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
      if (data[i + 2] == 0x49 &&
          data[i + 3] == 0x4e &&
          data[i + 4] == 0x46 &&
          data[i + 5] == 0x4f &&
          data[i + 6] == 0x20 &&
          (data[i + 7] == 0x20 || data[i + 7] == 0x2a)) {
        return i;
      }
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
    // BATCH suppresses acknowledgements; count only stations actually received.
    if (_batchMode) _acceptedStations.add(stationCode);
    if (!_acceptedStations.contains(stationCode)) return;
    if (!_isCurrentRun(generation)) return;
    final now = DateTime.now().toUtc();
    _health.observe(stationCode, miniSeed.startTime, now);
    if (miniSeed.startTime.isAfter(now) ||
        now.difference(miniSeed.startTime) > FdsnSeedLinkInfo.maxDataAge) {
      _staleCount++;
      _setConnected(true);
      return;
    }
    _lastPacketAt = DateTime.now();
    _consecutiveFailures = 0;
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
      final config = FdsnSourceCatalog.find(source);
      if (config == null) return null;
      final base = config.stationUrl;
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
        final service = FdsnStationService.forSource(source);
        service?.acceptChannelStation(
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
      var maxAccel = 0.0;
      var velocity = 0.0;
      var maxVelocity = 0.0;
      for (var i = 0; i < accel.length; i++) {
        final a = accel[i];
        maxAccel = max(maxAccel, a.abs());
        velocity += a * dt;
        maxVelocity = max(maxVelocity, velocity.abs());
      }
      pga = maxAccel * 100.0;
      pgv = maxVelocity * 100.0;
    } else if (_isVelocityUnit(unit)) {
      final velocity = centered;
      var maxVelocity = velocity.first.abs();
      var maxAccel = 0.0;
      for (var i = 1; i < velocity.length; i++) {
        maxVelocity = max(maxVelocity, velocity[i].abs());
        maxAccel = max(maxAccel, ((velocity[i] - velocity[i - 1]) / dt).abs());
      }
      pgv = maxVelocity * 100.0;
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
    _packetDrainTimer?.cancel();
    _packetDrainTimer = null;
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
    final multiplier = (1 << _consecutiveFailures.clamp(0, 5)).clamp(1, 30);
    _consecutiveFailures++;
    _reconnectTimer = Timer(reconnectDelay * multiplier, () {
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
    health: FdsnConnectionHealth(),
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
    final out = Int32List(min(count, payload.length ~/ 2));
    for (var i = 0; i < out.length; i++) {
      out[i] = data.getInt16(i * 2, endian);
    }
    return out;
  }

  static List<int> _decodeInt32(Uint8List payload, Endian endian, int count) {
    final data = ByteData.sublistView(payload);
    final out = Int32List(min(count, payload.length ~/ 4));
    for (var i = 0; i < out.length; i++) {
      out[i] = data.getInt32(i * 4, endian);
    }
    return out;
  }

  static List<int> _decodeSteim1(
    Uint8List payload,
    int sampleCount,
    Endian endian,
  ) {
    final data = ByteData.sublistView(payload);
    final out = Int32List(min(sampleCount, payload.length * 2));
    var written = 0;
    int? previous;
    var skipFirstDifference = true;

    for (var frame = 0; frame + 64 <= payload.length; frame += 64) {
      final control = data.getUint32(frame, endian);
      for (var wordIndex = 1; wordIndex < 16; wordIndex++) {
        final wordOffset = frame + wordIndex * 4;
        final word = data.getUint32(wordOffset, endian);
        if (frame == 0 && wordIndex == 1) {
          previous = data.getInt32(wordOffset, endian);
          out[written++] = previous;
          if (written == out.length) return out;
          continue;
        }
        if (frame == 0 && wordIndex == 2) continue;

        final seeded = previous;
        if (seeded == null) return Int32List.sublistView(out, 0, written);
        var current = seeded;
        final code = (control >> (30 - 2 * wordIndex)) & 0x03;
        final count = switch (code) {
          1 => 4,
          2 => 2,
          3 => 1,
          _ => 0,
        };
        for (var j = 0; j < count; j++) {
          final diff = switch (code) {
            1 => data.getInt8(wordOffset + j),
            2 => data.getInt16(wordOffset + j * 2, endian),
            _ => _signExtend(word, 32),
          };
          // D0 links the previous record to X0; X0 is already in the output.
          if (skipFirstDifference) {
            skipFirstDifference = false;
            continue;
          }
          current = (current + diff).toSigned(32);
          previous = current;
          out[written++] = current;
          if (written == out.length) return out;
        }
      }
    }
    return Int32List.sublistView(out, 0, written);
  }

  static List<int> _decodeSteim2(
    Uint8List payload,
    int sampleCount,
    Endian endian,
  ) {
    final data = ByteData.sublistView(payload);
    final out = Int32List(min(sampleCount, payload.length * 2));
    var written = 0;
    int? previous;
    var skipFirstDifference = true;

    for (var frame = 0; frame + 64 <= payload.length; frame += 64) {
      final control = data.getUint32(frame, endian);
      for (var wordIndex = 1; wordIndex < 16; wordIndex++) {
        final wordOffset = frame + wordIndex * 4;
        final word = data.getUint32(wordOffset, endian);
        if (frame == 0 && wordIndex == 1) {
          previous = data.getInt32(wordOffset, endian);
          out[written++] = previous;
          if (written == out.length) return out;
          continue;
        }
        if (frame == 0 && wordIndex == 2) continue;

        final seeded = previous;
        if (seeded == null) return Int32List.sublistView(out, 0, written);
        var current = seeded;
        final code = (control >> (30 - 2 * wordIndex)) & 0x03;
        final dnib = (word >> 30) & 3;
        final (count, bits) = switch ((code, dnib)) {
          (1, _) => (4, 8),
          (2, 1) => (1, 30),
          (2, 2) => (2, 15),
          (2, 3) => (3, 10),
          (3, 0) => (5, 6),
          (3, 1) => (6, 5),
          (3, 2) => (7, 4),
          _ => (0, 0),
        };
        for (var j = 0; j < count; j++) {
          final diff = code == 1
              ? data.getInt8(wordOffset + j)
              : _signExtend(word >> ((count - 1 - j) * bits), bits);
          if (skipFirstDifference) {
            skipFirstDifference = false;
            continue;
          }
          current = (current + diff).toSigned(32);
          previous = current;
          out[written++] = current;
          if (written == out.length) return out;
        }
      }
    }
    return Int32List.sublistView(out, 0, written);
  }

  static int _signExtend(int value, int bits) {
    if (bits >= 32) return value.toSigned(32);
    final signBit = 1 << (bits - 1);
    final mask = (1 << bits) - 1;
    value &= mask;
    return (value & signBit) != 0 ? value - (1 << bits) : value;
  }
}
