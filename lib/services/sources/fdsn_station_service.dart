import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class FdsnStation {
  static const motionRetention = Duration(minutes: 3);

  final String network;
  final String station;
  final String location;
  final LatLng coordinate;
  final double? elevation;
  final String siteName;
  final DateTime? startTime;
  final DateTime? endTime;
  final String source;
  final double? pga;
  final double? pgv;
  final double? intensity;
  final DateTime? lastMotionUpdate;

  const FdsnStation({
    required this.network,
    required this.station,
    required this.location,
    required this.coordinate,
    required this.source,
    this.elevation,
    this.siteName = '',
    this.startTime,
    this.endTime,
    this.pga,
    this.pgv,
    this.intensity,
    this.lastMotionUpdate,
  });

  String get code => '$network.$station';
  bool get isMotionActive =>
      lastMotionUpdate != null &&
      DateTime.now().difference(lastMotionUpdate!) <= motionRetention;
  bool get hasMotionMeasurement =>
      lastMotionUpdate != null ||
      pga != null ||
      pgv != null ||
      intensity != null;
  bool get hasActiveMotionMeasurement => isMotionActive && hasMotionMeasurement;

  FdsnStation copyWith({
    double? pga,
    double? pgv,
    double? intensity,
    DateTime? lastMotionUpdate,
  }) {
    return FdsnStation(
      network: network,
      station: station,
      location: location,
      coordinate: coordinate,
      source: source,
      elevation: elevation,
      siteName: siteName,
      startTime: startTime,
      endTime: endTime,
      pga: pga ?? this.pga,
      pgv: pgv ?? this.pgv,
      intensity: intensity ?? this.intensity,
      lastMotionUpdate: lastMotionUpdate ?? this.lastMotionUpdate,
    );
  }
}

class FdsnStationEndpoint {
  final String name;
  final String stationUrl;
  final Map<String, String> query;

  const FdsnStationEndpoint({
    required this.name,
    required this.stationUrl,
    this.query = const {},
  });
}

class FdsnStationService {
  FdsnStationService({required this.endpoint});

  static final earthScope = FdsnStationService(
    endpoint: const FdsnStationEndpoint(
      name: 'EarthScope',
      stationUrl: 'https://service.earthscope.org/fdsnws/station/1/query',
    ),
  );

  static final geofon = FdsnStationService(
    endpoint: const FdsnStationEndpoint(
      name: 'GEOFON',
      stationUrl: 'https://geofon.gfz-potsdam.de/fdsnws/station/1/query',
    ),
  );

  final FdsnStationEndpoint endpoint;
  final _controller = StreamController<List<FdsnStation>>.broadcast();

  Stream<List<FdsnStation>> get stationStream => _controller.stream;

  List<FdsnStation> _stations = const [];
  List<FdsnStation> get stations => _stations;

  bool _running = false;
  int _runGeneration = 0;
  int? _loadingGeneration;
  http.Client? _client;
  Timer? _refreshTimer;

  void Function(bool connected)? onStatusChanged;

  Future<void> start({
    Duration refreshInterval = const Duration(hours: 12),
  }) async {
    if (_running) return;
    _running = true;
    final generation = ++_runGeneration;
    _client = http.Client();
    await _refresh(generation);
    if (!_isCurrentRun(generation)) return;
    _refreshTimer = Timer.periodic(
      refreshInterval,
      (_) => unawaited(refresh()),
    );
  }

  Future<void> refresh() => _refresh(_runGeneration);

  Future<void> _refresh(int generation) async {
    final client = _client;
    if (!_isCurrentRun(generation) || client == null) return;
    if (_loadingGeneration == generation) return;
    _loadingGeneration = generation;
    onStatusChanged?.call(false);
    try {
      final uri = _buildUri();
      final response = await client
          .get(
            uri,
            headers: const {
              'Accept': 'text/plain,*/*',
              'User-Agent': 'FlutterRhythmQuake/1.0',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (!_isCurrentRun(generation) || !identical(client, _client)) return;

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      _stations = _parseStationText(utf8.decode(response.bodyBytes));
      _controller.add(_stations);
      onStatusChanged?.call(true);
      debugPrint('FDSN ${endpoint.name}: ${_stations.length} stations loaded');
    } catch (e) {
      if (!_isCurrentRun(generation) || !identical(client, _client)) return;
      debugPrint('FDSN ${endpoint.name}: station load failed: $e');
      onStatusChanged?.call(false);
    } finally {
      if (_loadingGeneration == generation) {
        _loadingGeneration = null;
      }
    }
  }

  void stop() {
    _running = false;
    _runGeneration++;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _loadingGeneration = null;
    _client?.close();
    _client = null;
    onStatusChanged?.call(false);
  }

  bool _isCurrentRun(int generation) =>
      _running && _runGeneration == generation;

  void dispose() {
    stop();
    _controller.close();
  }

  Uri _buildUri() {
    final base = Uri.parse(endpoint.stationUrl);
    final query = <String, String>{
      'level': 'station',
      'format': 'text',
      'nodata': '204',
      ...endpoint.query,
    };
    return base.replace(queryParameters: {...base.queryParameters, ...query});
  }

  List<FdsnStation> _parseStationText(String text) {
    final stations = <String, FdsnStation>{};

    for (final rawLine in const LineSplitter().convert(text)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final cols = line.split('|');
      if (cols.length < 4) continue;

      final network = cols[0].trim();
      final station = cols[1].trim();
      final lat = double.tryParse(cols[2].trim());
      final lon = double.tryParse(cols[3].trim());
      if (network.isEmpty || station.isEmpty || lat == null || lon == null) {
        continue;
      }
      if (lat < -90 || lat > 90 || lon < -180 || lon > 180) continue;

      final parsed = FdsnStation(
        network: network,
        station: station,
        location: '',
        coordinate: LatLng(lat, lon),
        elevation: cols.length > 4 ? double.tryParse(cols[4].trim()) : null,
        siteName: cols.length > 5 ? cols[5].trim() : '',
        startTime: cols.length > 6 ? DateTime.tryParse(cols[6].trim()) : null,
        endTime: cols.length > 7 ? DateTime.tryParse(cols[7].trim()) : null,
        source: endpoint.name,
      );
      final existing = stations[parsed.code];
      if (existing == null || _isPreferredStation(parsed, existing)) {
        stations[parsed.code] = parsed;
      }
    }

    return stations.values.toList(growable: false);
  }

  bool _isPreferredStation(FdsnStation candidate, FdsnStation current) {
    final now = DateTime.now().toUtc();
    final candidateActive =
        candidate.endTime == null || candidate.endTime!.toUtc().isAfter(now);
    final currentActive =
        current.endTime == null || current.endTime!.toUtc().isAfter(now);
    if (candidateActive != currentActive) return candidateActive;

    final candidateStart = candidate.startTime;
    final currentStart = current.startTime;
    if (candidateStart == null) return false;
    if (currentStart == null) return true;
    return candidateStart.isAfter(currentStart);
  }
}
