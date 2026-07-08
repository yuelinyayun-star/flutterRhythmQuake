import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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

  const FdsnSeedLinkStream({
    required this.source,
    required this.host,
    required this.port,
    required this.network,
    required this.station,
    required this.selector,
  });
}

class _SeedLinkSource {
  final String source;
  final String host;
  final int port;
  final Set<String> allowedNetworks;

  const _SeedLinkSource({
    required this.source,
    required this.host,
    required this.port,
    required this.allowedNetworks,
  });
}

class FdsnMotionService {
  static final FdsnMotionService _instance = FdsnMotionService._();
  factory FdsnMotionService() => _instance;
  FdsnMotionService._();

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
      port: 18000,
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
      port: 18000,
      network: 'IU',
      station: 'ANMO',
      selector: 'BH?',
    ),
    FdsnSeedLinkStream(
      source: 'EarthScope',
      host: 'rtserve.earthscope.org',
      port: 18000,
      network: 'IU',
      station: 'COLA',
      selector: 'BH?',
    ),
    FdsnSeedLinkStream(
      source: 'EarthScope',
      host: 'rtserve.earthscope.org',
      port: 18000,
      network: 'II',
      station: 'PFO',
      selector: 'BH?',
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

  final List<_SeedLinkConnection> _connections = [];
  bool _running = false;
  int _currentStationLimit = defaultStationLimit;
  Set<String> _currentEnabledSources = const {'EarthScope', 'GEOFON'};
  int _connectionGeneration = 0;

  void Function(bool connected)? onStatusChanged;

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
    final generation = ++_connectionGeneration;
    _currentStationLimit = normalizedLimit;
    _currentEnabledSources = normalizedSources;
    if (targetStationLimitNotifier.value != normalizedLimit) {
      targetStationLimitNotifier.value = normalizedLimit;
    }
    _setLinkedStationCount(0);
    unawaited(
      _startConnections(normalizedLimit, normalizedSources, generation),
    );
  }

  Future<void> _startConnections(
    int stationLimit,
    Set<String> enabledSources,
    int generation,
  ) async {
    final streams = await _streamsForLimit(stationLimit, enabledSources);
    if (!_running ||
        _currentStationLimit != stationLimit ||
        !setEquals(_currentEnabledSources, enabledSources) ||
        _connectionGeneration != generation) {
      return;
    }

    final groups = <String, List<FdsnSeedLinkStream>>{};
    for (final stream in streams) {
      groups.putIfAbsent('${stream.host}:${stream.port}', () => []).add(stream);
    }

    for (final entry in groups.entries) {
      final first = entry.value.first;
      final connection = _SeedLinkConnection(
        host: first.host,
        port: first.port,
        streams: entry.value,
        onSample: _controller.add,
        onStatusChanged: _emitStatus,
      );
      _connections.add(connection);
      connection.start();
    }
  }

  void disconnect() {
    _running = false;
    _connectionGeneration++;
    for (final connection in _connections) {
      connection.stop();
    }
    _connections.clear();
    _setLinkedStationCount(0);
    onStatusChanged?.call(false);
  }

  Future<List<FdsnSeedLinkStream>> _streamsForLimit(
    int stationLimit,
    Set<String> enabledSources,
  ) async {
    final defaultForSources = defaultStreams
        .where((stream) => enabledSources.contains(stream.source))
        .toList(growable: false);
    if (stationLimit <= defaultForSources.length) {
      return defaultForSources.take(stationLimit).toList(growable: false);
    }

    final discovered = await _discoverSeedLinkStreams(
      stationLimit,
      enabledSources,
    );
    if (discovered.isEmpty) return defaultForSources;
    return discovered.take(stationLimit).toList(growable: false);
  }

  Future<List<FdsnSeedLinkStream>> _discoverSeedLinkStreams(
    int stationLimit,
    Set<String> enabledSources,
  ) async {
    final lists = await Future.wait(
      _seedLinkSources
          .where((source) => enabledSources.contains(source.source))
          .map((source) => _loadSeedLinkStreams(source)),
    );
    final seen = <String>{};
    final merged = <FdsnSeedLinkStream>[];

    void addStream(FdsnSeedLinkStream stream) {
      final key =
          '${stream.source}:${stream.host}:${stream.network}.${stream.station}:${stream.selector}';
      if (!seen.add(key)) return;
      merged.add(stream);
    }

    for (final stream in defaultStreams.where(
      (stream) => enabledSources.contains(stream.source),
    )) {
      addStream(stream);
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
  ) async {
    Socket? socket;
    Timer? timeoutTimer;
    final bytes = <int>[];
    final done = Completer<void>();

    void complete() {
      if (!done.isCompleted) done.complete();
    }

    try {
      socket = await Socket.connect(
        source.host,
        source.port,
        timeout: const Duration(seconds: 12),
      );
      timeoutTimer = Timer(const Duration(seconds: 10), complete);
      socket.listen(
        (chunk) {
          bytes.addAll(chunk);
          if (bytes.length >= 10 * 1024 * 1024 ||
              _containsAscii(bytes, '</seedlink>')) {
            complete();
          }
        },
        onDone: complete,
        onError: (_) => complete(),
        cancelOnError: true,
      );
      socket.add(ascii.encode('INFO STREAMS\r'));
      await done.future;
    } catch (e) {
      debugPrint('SeedLink ${source.host}:${source.port} INFO failed: $e');
      return const [];
    } finally {
      timeoutTimer?.cancel();
      socket?.destroy();
    }

    final text = _extractSeedLinkInfoText(Uint8List.fromList(bytes));
    final streams = _parseSeedLinkStreams(source, text);
    debugPrint('SeedLink ${source.source}: ${streams.length} stations found');
    return streams;
  }

  bool _containsAscii(List<int> bytes, String needle) {
    final pattern = ascii.encode(needle.toLowerCase());
    if (bytes.length < pattern.length) return false;
    for (var i = 0; i <= bytes.length - pattern.length; i++) {
      var matched = true;
      for (var j = 0; j < pattern.length; j++) {
        final b = bytes[i + j];
        final lower = b >= 0x41 && b <= 0x5A ? b + 0x20 : b;
        if (lower != pattern[j]) {
          matched = false;
          break;
        }
      }
      if (matched) return true;
    }
    return false;
  }

  String _extractSeedLinkInfoText(Uint8List bytes) {
    const packetSize = 520;
    const infoXmlOffset = 72;
    final buffer = StringBuffer();

    for (var i = 0; i + packetSize <= bytes.length; i++) {
      if (bytes[i] != 0x53 ||
          bytes[i + 1] != 0x4C ||
          bytes[i + 2] != 0x49 ||
          bytes[i + 3] != 0x4E ||
          bytes[i + 4] != 0x46 ||
          bytes[i + 5] != 0x4F) {
        continue;
      }
      buffer.write(
        latin1.decode(bytes.sublist(i + infoXmlOffset, i + packetSize)),
      );
      i += packetSize - 1;
    }

    final text = buffer.isEmpty ? latin1.decode(bytes) : buffer.toString();
    return text.replaceAll('\x00', '');
  }

  List<FdsnSeedLinkStream> _parseSeedLinkStreams(
    _SeedLinkSource source,
    String text,
  ) {
    final stations = <FdsnSeedLinkStream>[];
    final stationRegex = RegExp(
      r'<station\b([^>]*)>([\s\S]*?)</station>',
      caseSensitive: false,
    );
    final streamRegex = RegExp(
      r'<stream\b[^>]*\bseedname="([^"]+)"',
      caseSensitive: false,
    );

    for (final match in stationRegex.allMatches(text)) {
      final attrs = match.group(1) ?? '';
      final network = _xmlAttribute(attrs, 'network')?.toUpperCase();
      final station = _xmlAttribute(attrs, 'name')?.toUpperCase();
      final body = match.group(2) ?? '';
      if (network == null ||
          station == null ||
          network.isEmpty ||
          station.isEmpty ||
          (source.allowedNetworks.isNotEmpty &&
              !source.allowedNetworks.contains(network))) {
        continue;
      }

      final channels = streamRegex
          .allMatches(body)
          .map((m) => m.group(1)?.trim().toUpperCase() ?? '')
          .where((channel) => channel.length >= 2)
          .toSet();
      final selector = _preferredSelector(channels);
      if (selector == null) continue;

      stations.add(
        FdsnSeedLinkStream(
          source: source.source,
          host: source.host,
          port: source.port,
          network: network,
          station: station,
          selector: selector,
        ),
      );
    }

    return stations;
  }

  String? _xmlAttribute(String attrs, String name) {
    final match = RegExp(
      '$name="([^"]*)"',
      caseSensitive: false,
    ).firstMatch(attrs);
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? _preferredSelector(Set<String> channels) {
    const families = ['HN', 'HL', 'HH', 'BH'];
    for (final family in families) {
      final hasFamily = channels.any((channel) => channel.startsWith(family));
      if (hasFamily) return '$family?';
    }
    return null;
  }

  void _emitStatus() {
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
    _controller.close();
  }
}

class _ChannelResponse {
  final double sensitivity;
  final String unit;

  const _ChannelResponse({required this.sensitivity, required this.unit});
}

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
  static const int _packetSize = 520;
  static final _responseLoadLimiter = _AsyncLimiter(8);

  final String host;
  final int port;
  final List<FdsnSeedLinkStream> streams;
  final void Function(FdsnMotionSample sample) onSample;
  final VoidCallback onStatusChanged;

  Socket? _socket;
  Timer? _reconnectTimer;
  bool _running = false;
  bool _connected = false;
  int _activePacketJobs = 0;
  final List<int> _buffer = [];
  final Map<String, Future<_ChannelResponse?>> _responseCache = {};

  _SeedLinkConnection({
    required this.host,
    required this.port,
    required this.streams,
    required this.onSample,
    required this.onStatusChanged,
  });

  bool get isConnected => _connected;
  Set<String> get stationCodes =>
      streams.map((stream) => '${stream.network}.${stream.station}').toSet();

  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  void stop() {
    _running = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _socket?.destroy();
    _socket = null;
    _setConnected(false);
  }

  Future<void> _connect() async {
    if (!_running || _socket != null) return;
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 12),
      );
      _socket = socket;
      _setConnected(true);
      _sendSelections(socket);
      socket.listen(
        _handleBytes,
        onDone: _handleClosed,
        onError: (error) {
          debugPrint('SeedLink $host:$port error: $error');
          _handleClosed();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('SeedLink $host:$port connect failed: $e');
      _handleClosed();
    }
  }

  void _sendSelections(Socket socket) {
    for (final stream in streams) {
      _sendLine(socket, 'STATION ${stream.station} ${stream.network}');
      _sendLine(socket, 'SELECT ${stream.selector}');
    }
    _sendLine(socket, 'END');
  }

  void _sendLine(Socket socket, String line) {
    socket.add(ascii.encode('$line\r'));
  }

  void _handleBytes(Uint8List bytes) {
    _buffer.addAll(bytes);

    while (true) {
      final start = _findSeedLinkHeader(_buffer);
      if (start < 0) {
        if (_buffer.length > _packetSize) {
          _buffer.removeRange(0, _buffer.length - 8);
        }
        return;
      }
      if (start > 0) {
        _buffer.removeRange(0, start);
      }
      if (_buffer.length < _packetSize) return;

      final packet = Uint8List.fromList(_buffer.sublist(0, _packetSize));
      _buffer.removeRange(0, _packetSize);
      _schedulePacket(packet);
    }
  }

  void _schedulePacket(Uint8List packet) {
    if (_activePacketJobs >= 200) return;
    _activePacketJobs++;
    unawaited(
      _handlePacket(packet).whenComplete(() {
        _activePacketJobs--;
      }),
    );
  }

  int _findSeedLinkHeader(List<int> data) {
    for (var i = 0; i <= data.length - 8; i++) {
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

  Future<void> _handlePacket(Uint8List packet) async {
    final record = packet.sublist(8);
    final miniSeed = _MiniSeedRecord.tryParse(record);
    if (miniSeed == null || miniSeed.samples.isEmpty) return;

    var source = '';
    for (final stream in streams) {
      if (stream.network == miniSeed.network &&
          stream.station == miniSeed.station) {
        source = stream.source;
        break;
      }
    }
    if (source.isEmpty) return;

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

    final response = await _responseFor(source, miniSeed);
    if (response == null) return;

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

  Future<_ChannelResponse?> _responseFor(
    String source,
    _MiniSeedRecord record,
  ) {
    final key =
        '$source:${record.network}.${record.station}.${record.location}.${record.channel}';
    return _responseCache.putIfAbsent(key, () => _loadResponse(source, record));
  }

  Future<_ChannelResponse?> _loadResponse(
    String source,
    _MiniSeedRecord record,
  ) => _responseLoadLimiter.run(() async {
    final base = source == 'GEOFON'
        ? 'https://geofon.gfz-potsdam.de/fdsnws/station/1/query'
        : 'https://service.earthscope.org/fdsnws/station/1/query';
    final query = <String, String>{
      'network': record.network,
      'station': record.station,
      'channel': record.channel,
      'level': 'response',
      'format': 'xml',
      'nodata': '204',
    };
    if (record.location.isNotEmpty) {
      query['location'] = record.location;
    }

    try {
      final response = await http
          .get(
            Uri.parse(base).replace(queryParameters: query),
            headers: const {
              'Accept': 'application/xml,text/xml,*/*',
              'User-Agent': 'FlutterRhythmQuake/1.0',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      return _parseResponseXml(response.body);
    } catch (e) {
      debugPrint(
        'FDSN response load failed ${record.network}.${record.station}.${record.channel}: $e',
      );
      return null;
    }
  });

  _ChannelResponse? _parseResponseXml(String xml) {
    final sensitivityMatch = RegExp(
      r'<(?:\w+:)?InstrumentSensitivity\b[^>]*>[\s\S]*?<(?:\w+:)?Value>([^<]+)</(?:\w+:)?Value>[\s\S]*?<(?:\w+:)?InputUnits\b[^>]*>[\s\S]*?<(?:\w+:)?Name>([^<]+)</(?:\w+:)?Name>',
      caseSensitive: false,
    ).firstMatch(xml);
    if (sensitivityMatch == null) return null;

    final sensitivity = double.tryParse(sensitivityMatch.group(1)!.trim());
    final unit = sensitivityMatch.group(2)!.trim().toUpperCase();
    if (sensitivity == null || sensitivity == 0 || !sensitivity.isFinite) {
      return null;
    }
    return _ChannelResponse(sensitivity: sensitivity.abs(), unit: unit);
  }

  _MotionMetrics _calculateMotionMetrics(
    _MiniSeedRecord record,
    _ChannelResponse response,
  ) {
    if (record.sampleRate <= 0 || record.samples.length < 2) {
      return const _MotionMetrics();
    }

    final values = record.samples
        .map((sample) => sample / response.sensitivity)
        .toList(growable: false);
    final mean = values.reduce((a, b) => a + b) / values.length;
    final centered = values.map((v) => v - mean).toList(growable: false);
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

  void _handleClosed() {
    _socket?.destroy();
    _socket = null;
    _setConnected(false);
    if (!_running || _reconnectTimer != null) return;
    _reconnectTimer = Timer(const Duration(seconds: 10), () {
      _reconnectTimer = null;
      _connect();
    });
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    onStatusChanged();
  }
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

    DateTime startTime;
    try {
      startTime = DateTime.utc(year, 1, 1)
          .add(Duration(days: dayOfYear - 1))
          .add(
            Duration(
              hours: hour,
              minutes: minute,
              seconds: second,
              microseconds: tenthMillis * 100,
            ),
          );
    } catch (_) {
      startTime = DateTime.now().toUtc();
    }

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
        return _decodeSteim1(payload, sampleCount);
      case 11:
        return _decodeSteim2(payload, sampleCount);
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

  static List<int> _decodeSteim1(Uint8List payload, int sampleCount) {
    final data = ByteData.sublistView(payload);
    final out = <int>[];
    int? previous;

    for (var frame = 0; frame + 64 <= payload.length; frame += 64) {
      final control = data.getUint32(frame, Endian.big);
      for (var wordIndex = 1; wordIndex < 16; wordIndex++) {
        final wordOffset = frame + wordIndex * 4;
        final word = data.getUint32(wordOffset, Endian.big);
        if (frame == 0 && wordIndex == 1) {
          previous = data.getInt32(wordOffset, Endian.big);
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
          1 => [
            _signExtend((word >> 24) & 0xff, 8),
            _signExtend((word >> 16) & 0xff, 8),
            _signExtend((word >> 8) & 0xff, 8),
            _signExtend(word & 0xff, 8),
          ],
          2 => [
            _signExtend((word >> 16) & 0xffff, 16),
            _signExtend(word & 0xffff, 16),
          ],
          3 => [_signExtend(word, 32)],
          _ => const <int>[],
        };
        for (final diff in diffs) {
          current += diff;
          previous = current;
          out.add(current);
          if (out.length >= sampleCount) return out;
        }
      }
    }
    return out;
  }

  static List<int> _decodeSteim2(Uint8List payload, int sampleCount) {
    final data = ByteData.sublistView(payload);
    final out = <int>[];
    int? previous;

    for (var frame = 0; frame + 64 <= payload.length; frame += 64) {
      final control = data.getUint32(frame, Endian.big);
      for (var wordIndex = 1; wordIndex < 16; wordIndex++) {
        final wordOffset = frame + wordIndex * 4;
        final word = data.getUint32(wordOffset, Endian.big);
        if (frame == 0 && wordIndex == 1) {
          previous = data.getInt32(wordOffset, Endian.big);
          out.add(previous);
          if (out.length >= sampleCount) return out;
          continue;
        }
        if (frame == 0 && wordIndex == 2) continue;

        final seeded = previous;
        if (seeded == null) return out;
        var current = seeded;
        final code = (control >> (30 - 2 * wordIndex)) & 0x03;
        final diffs = _steim2Diffs(code, word);
        for (final diff in diffs) {
          current += diff;
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
