import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

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

  static const String _cloudChinaUrl =
      'https://api.fanstudio.tech/we/img/cloud_china.php';

  static const Map<String, String> _headers = {
    'User-Agent': 'flutterrhythmquake/1.0',
    'Accept': 'application/json',
  };

  final StreamController<FanSatelliteCloudFrame?> _frameController =
      StreamController<FanSatelliteCloudFrame?>.broadcast();

  Timer? _timer;
  bool _started = false;
  bool _fetching = false;
  FanSatelliteCloudFrame? _latestFrame;

  Stream<FanSatelliteCloudFrame?> get frameStream => _frameController.stream;
  FanSatelliteCloudFrame? get latestFrame => _latestFrame;
  bool get isRunning => _started;

  void start({Duration interval = const Duration(minutes: 30)}) {
    if (_started) return;
    _started = true;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(fetchNow()));
    unawaited(fetchNow());
  }

  void stop({bool clear = false}) {
    _timer?.cancel();
    _timer = null;
    _started = false;
    if (clear && _latestFrame != null) {
      _latestFrame = null;
      _frameController.add(null);
    }
  }

  Future<void> fetchNow() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final response = await http
          .get(Uri.parse(_cloudChinaUrl), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        debugPrint('[FanSatelliteCloud] HTTP ${response.statusCode}');
        return;
      }
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map) {
        debugPrint('[FanSatelliteCloud] response is not an object');
        return;
      }
      final frame = _parseFrame(Map<String, dynamic>.from(json));
      if (frame == null) return;
      _latestFrame = frame;
      _frameController.add(frame);
      debugPrint('[FanSatelliteCloud] updated: ${frame.time}');
    } catch (e) {
      debugPrint('[FanSatelliteCloud] fetch error: $e');
    } finally {
      _fetching = false;
    }
  }

  FanSatelliteCloudFrame? _parseFrame(Map<String, dynamic> raw) {
    if ('${raw['status'] ?? ''}' != 'success') {
      debugPrint('[FanSatelliteCloud] status=${raw['status']}');
      return null;
    }
    final time = _parseTime(raw['time']);
    final bounds = raw['bounds'];
    final image = raw['image'];
    if (time == null || bounds is! Map || image is! String || image.isEmpty) {
      debugPrint('[FanSatelliteCloud] missing fields');
      return null;
    }
    final southWest = _parseLatLng(bounds['sw']);
    final northEast = _parseLatLng(bounds['ne']);
    if (southWest == null || northEast == null) {
      debugPrint('[FanSatelliteCloud] invalid bounds');
      return null;
    }
    final comma = image.indexOf(',');
    final payload = comma >= 0 ? image.substring(comma + 1) : image;
    try {
      final bytes = base64Decode(payload);
      if (bytes.isEmpty) {
        debugPrint('[FanSatelliteCloud] empty image');
        return null;
      }
      return FanSatelliteCloudFrame(
        time: time,
        southWest: southWest,
        northEast: northEast,
        imageBytes: bytes,
      );
    } catch (e) {
      debugPrint('[FanSatelliteCloud] image decode error: $e');
      return null;
    }
  }

  DateTime? _parseTime(Object? value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text.replaceFirst(' ', 'T'));
  }

  LatLng? _parseLatLng(Object? value) {
    if (value is! List || value.length < 2) return null;
    final lat = _parseDouble(value[0]);
    final lng = _parseDouble(value[1]);
    if (lat == null || lng == null) return null;
    if (!lat.isFinite || !lng.isFinite) return null;
    return LatLng(lat, lng);
  }

  double? _parseDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
