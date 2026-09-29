import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'web_source_proxy.dart';

class FanSatelliteCloudFrame {
  const FanSatelliteCloudFrame({
    required this.time,
    required this.southWest,
    required this.northEast,
    required this.imageBytes,
  });

  final DateTime time;
  final LatLng southWest;
  final LatLng northEast;
  final Uint8List imageBytes;
}

class FanSatelliteCloudService {
  static final FanSatelliteCloudService _instance =
      FanSatelliteCloudService._internal();
  factory FanSatelliteCloudService() => _instance;
  FanSatelliteCloudService._internal();

  // Keep the legacy type name for the existing foreground/background payload.
  static const String _zhejiangCloudUrl =
      'https://typhoon.slt.zj.gov.cn/Api/LeastCloud/?type=30';

  static const Map<String, String> _headers = {
    'User-Agent': 'flutterrhythmquake/1.0',
    'Accept': 'application/json',
    'Referer': 'https://typhoon.slt.zj.gov.cn/',
  };

  final StreamController<FanSatelliteCloudFrame?> _frameController =
      StreamController<FanSatelliteCloudFrame?>.broadcast();

  Timer? _timer;
  bool _started = false;
  bool _fetching = false;
  bool _fetchQueued = false;
  int _session = 0;
  FanSatelliteCloudFrame? _latestFrame;

  Stream<FanSatelliteCloudFrame?> get frameStream => _frameController.stream;
  FanSatelliteCloudFrame? get latestFrame => _latestFrame;
  bool get isRunning => _started;

  void start({
    Duration interval = const Duration(minutes: 30),
    int startupAttempts = 3,
  }) {
    if (_started) {
      if (_latestFrame == null) {
        unawaited(fetchNow(maxAttempts: startupAttempts));
      }
      return;
    }
    _started = true;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(fetchNow()));
    unawaited(fetchNow(maxAttempts: startupAttempts));
  }

  void stop({bool clear = false}) {
    _session++;
    _timer?.cancel();
    _timer = null;
    _started = false;
    _fetchQueued = false;
    if (clear && _latestFrame != null) {
      _latestFrame = null;
      _frameController.add(null);
    }
  }

  Future<void> fetchNow({int maxAttempts = 1}) async {
    final attempts = maxAttempts < 1 ? 1 : maxAttempts;
    if (_fetching) {
      _fetchQueued = true;
      return;
    }
    _fetching = true;
    try {
      do {
        _fetchQueued = false;
        final session = _session;
        for (var attempt = 1; attempt <= attempts; attempt++) {
          if (!_started || session != _session) return;
          final ok = await _fetchOnce(session);
          if (ok || !_started || session != _session) break;
          if (attempt < attempts) {
            await Future<void>.delayed(Duration(seconds: attempt * 2));
          }
        }
      } while (_fetchQueued && _started);
    } finally {
      _fetching = false;
    }
  }

  Future<bool> _fetchOnce(int session) async {
    try {
      final response = await http
          .get(
            sourceUri(Uri.parse(_zhejiangCloudUrl)),
            headers: sourceHeaders(_headers),
          )
          .timeout(const Duration(seconds: 20));
      if (!_started || session != _session) return false;
      if (response.statusCode != 200) {
        debugPrint('[ZhejiangSatelliteCloud] HTTP ${response.statusCode}');
        return false;
      }
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map) {
        debugPrint('[ZhejiangSatelliteCloud] response is not an object');
        return false;
      }
      final frame = parseZhejiangFrame(Map<String, dynamic>.from(json));
      if (frame == null) return false;
      if (!_started || session != _session) return false;
      _latestFrame = frame;
      _frameController.add(frame);
      debugPrint('[ZhejiangSatelliteCloud] updated: ${frame.time}');
      return true;
    } catch (e) {
      debugPrint('[ZhejiangSatelliteCloud] fetch error: $e');
      return false;
    }
  }

  static FanSatelliteCloudFrame? parseZhejiangFrame(Map<String, dynamic> raw) {
    final diffTime = _parseDouble(raw['diffTime']);
    if (diffTime == null || diffTime < 0 || diffTime >= 30000) {
      debugPrint('[ZhejiangSatelliteCloud] stale or missing cloud frame');
      return null;
    }
    final time = _parseTime(raw['timeStr']);
    final south = _parseDouble(raw['minLat']);
    final north = _parseDouble(raw['maxLat']);
    final west = _parseDouble(raw['minLng']);
    final east = _parseDouble(raw['maxLng']);
    final image = raw['cloudname'];
    if (time == null ||
        south == null ||
        north == null ||
        west == null ||
        east == null ||
        south < -90 ||
        north > 90 ||
        south >= north ||
        west < -180 ||
        east > 180 ||
        west >= east ||
        image is! String ||
        !image.startsWith('data:image/png;base64,')) {
      debugPrint('[ZhejiangSatelliteCloud] invalid cloud frame metadata');
      return null;
    }
    try {
      final bytes = base64Decode(
        image.substring('data:image/png;base64,'.length),
      );
      if (bytes.length < 24 ||
          bytes[0] != 0x89 ||
          bytes[1] != 0x50 ||
          bytes[2] != 0x4e ||
          bytes[3] != 0x47) {
        debugPrint('[ZhejiangSatelliteCloud] invalid PNG image');
        return null;
      }
      return FanSatelliteCloudFrame(
        time: time,
        southWest: LatLng(south, west),
        northEast: LatLng(north, east),
        imageBytes: bytes,
      );
    } catch (e) {
      debugPrint('[ZhejiangSatelliteCloud] image decode error: $e');
      return null;
    }
  }

  static DateTime? _parseTime(Object? value) {
    final text = '${value ?? ''}'.trim();
    final match = RegExp(
      r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})\.png$',
    ).firstMatch(text);
    if (match == null) return null;
    final parts = [
      for (var index = 1; index <= 5; index++) int.parse(match[index]!),
    ];
    final time = DateTime(parts[0], parts[1], parts[2], parts[3], parts[4]);
    if (time.year != parts[0] ||
        time.month != parts[1] ||
        time.day != parts[2] ||
        time.hour != parts[3] ||
        time.minute != parts[4]) {
      return null;
    }
    return time;
  }

  static double? _parseDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
