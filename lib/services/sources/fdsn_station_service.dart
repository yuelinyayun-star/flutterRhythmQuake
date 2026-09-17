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
  FdsnStationService({
    required this.endpoint,
    this.retryInterval = const Duration(seconds: 30),
  });

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
  final Duration retryInterval;
  final _controller = StreamController<List<FdsnStation>>.broadcast();

  Stream<List<FdsnStation>> get stationStream => _controller.stream;

  List<FdsnStation> _stations = const [];
  final _supplementalStations = <String, FdsnStation>{};
  final _pendingSupplementalStations = <FdsnStation>[];
  Timer? _supplementalPublishTimer;
  Set<String> _stationCodes = {};
  List<FdsnStation> get stations => _stations;

  // Coordinates come from the matched channel epoch at the official metadata
  // owner. The displayed source remains the SeedLink relay selected by the user.
  void acceptChannelStation(FdsnStation station) {
    if (!_running ||
        station.source != endpoint.name ||
        _stationCodes.contains(station.code)) {
      return;
    }
    _supplementalStations[station.code] = station;
    _stationCodes.add(station.code);
    _pendingSupplementalStations.add(station);
    // Metadata arrives in bursts. Publish one immutable snapshot for the map
    // and Android bridge, rather than copying/serializing the catalogue per station.
    _supplementalPublishTimer ??= Timer(
      const Duration(milliseconds: 100),
      _publishSupplementalStations,
    );
  }

  void _publishSupplementalStations({bool notify = true}) {
    _supplementalPublishTimer?.cancel();
    _supplementalPublishTimer = null;
    if (_pendingSupplementalStations.isEmpty) return;
    _stations = [..._stations, ..._pendingSupplementalStations];
    _pendingSupplementalStations.clear();
    if (notify && _running) _controller.add(_stations);
  }

  bool _running = false;
  int _runGeneration = 0;
  int? _loadingGeneration;
  http.Client? _client;
  Timer? _refreshTimer;
  Timer? _retryTimer;

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

      final stations = await compute(_parseStationText, (
        utf8.decode(response.bodyBytes),
        endpoint.name,
      ));
      if (!_isCurrentRun(generation) || !identical(client, _client)) return;
      if (stations.isEmpty) {
        throw const FormatException('Empty station catalogue');
      }
      _stationCodes = stations.map((s) => s.code).toSet();
      _stations = [
        ...stations,
        ..._supplementalStations.values.where(
          (s) => !_stationCodes.contains(s.code),
        ),
      ];
      _stationCodes.addAll(_supplementalStations.keys);
      _supplementalPublishTimer?.cancel();
      _supplementalPublishTimer = null;
      _pendingSupplementalStations.clear();
      _retryTimer?.cancel();
      _retryTimer = null;
      _controller.add(_stations);
      onStatusChanged?.call(true);
      debugPrint('FDSN ${endpoint.name}: ${_stations.length} stations loaded');
    } catch (e) {
      if (!_isCurrentRun(generation) || !identical(client, _client)) return;
      debugPrint('FDSN ${endpoint.name}: station load failed: $e');
      onStatusChanged?.call(false);
      _retryTimer?.cancel();
      _retryTimer = Timer(retryInterval, () {
        _retryTimer = null;
        if (_isCurrentRun(generation)) unawaited(_refresh(generation));
      });
    } finally {
      if (_loadingGeneration == generation) {
        _loadingGeneration = null;
      }
    }
  }

  void stop() {
    _publishSupplementalStations(notify: false);
    _running = false;
    _runGeneration++;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
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
      'endafter': DateTime.now().toUtc().toIso8601String(),
      ...endpoint.query,
    };
    return base.replace(queryParameters: {...base.queryParameters, ...query});
  }

  static List<FdsnStation> _parseStationText((String, String) input) {
    final (text, source) = input;
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
        startTime: cols.length > 6 ? _parseUtc(cols[6].trim()) : null,
        endTime: cols.length > 7 ? _parseUtc(cols[7].trim()) : null,
        source: source,
      );
      final existing = stations[parsed.code];
      if (existing == null || _isPreferredStation(parsed, existing)) {
        stations[parsed.code] = parsed;
      }
    }

    return stations.values.toList(growable: false);
  }

  static bool _isPreferredStation(FdsnStation candidate, FdsnStation current) {
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

  static DateTime? _parseUtc(String text) => text.isEmpty
      ? null
      : DateTime.tryParse(text.endsWith('Z') ? text : '${text}Z');
}
