import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class FanRadarFrame {
  const FanRadarFrame({
    required this.time,
    required this.southWest,
    required this.northEast,
    required this.width,
    required this.height,
    required this.imageBytes,
  });

  final DateTime time;
  final LatLng southWest;
  final LatLng northEast;
  final int width;
  final int height;
  final Uint8List imageBytes;
}

class FanRadarService {
  static final FanRadarService _instance = FanRadarService._internal();
  factory FanRadarService() => _instance;
  FanRadarService._internal();

  static const String _radarChinaUrl =
      'https://api.fanstudio.tech/we/img/radar_china.php';

  static const Map<String, String> _headers = {
    'User-Agent': 'flutterrhythmquake/1.0',
    'Accept': 'application/json',
  };

  final StreamController<FanRadarFrame?> _frameController =
      StreamController<FanRadarFrame?>.broadcast();

  Timer? _timer;
  bool _started = false;
  bool _fetching = false;
  FanRadarFrame? _latestFrame;

  Stream<FanRadarFrame?> get frameStream => _frameController.stream;
  FanRadarFrame? get latestFrame => _latestFrame;

  void start({Duration interval = const Duration(minutes: 10)}) {
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
          .get(Uri.parse(_radarChinaUrl), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        debugPrint('[FanRadar] HTTP ${response.statusCode}');
        return;
      }
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map) {
        debugPrint('[FanRadar] response is not an object');
        return;
      }
      final frame = _parseFrame(Map<String, dynamic>.from(json));
      if (frame == null) return;
      _latestFrame = frame;
      _frameController.add(frame);
      debugPrint(
        '[FanRadar] updated: ${frame.time} '
        '${frame.width}x${frame.height}',
      );
    } catch (e) {
      debugPrint('[FanRadar] fetch error: $e');
    } finally {
      _fetching = false;
    }
  }

  FanRadarFrame? _parseFrame(Map<String, dynamic> raw) {
    if ('${raw['status'] ?? ''}' != 'success') {
      debugPrint('[FanRadar] status=${raw['status']}');
      return null;
    }
    final time = _parseTime(raw['time']);
    final bounds = raw['bounds'];
    final size = raw['size'];
    final image = raw['image'];
    if (time == null ||
        bounds is! Map ||
        size is! Map ||
        image is! String ||
        image.isEmpty) {
      debugPrint('[FanRadar] missing fields');
      return null;
    }
    final southWest = _parseLatLng(bounds['sw']);
    final northEast = _parseLatLng(bounds['ne']);
    final width = _parseInt(size['width']);
    final height = _parseInt(size['height']);
    if (southWest == null ||
        northEast == null ||
        width == null ||
        height == null ||
        width <= 0 ||
        height <= 0) {
      debugPrint('[FanRadar] invalid bounds or size');
      return null;
    }
    final comma = image.indexOf(',');
    final payload = comma >= 0 ? image.substring(comma + 1) : image;
    try {
      final bytes = base64Decode(payload);
      if (bytes.isEmpty) {
        debugPrint('[FanRadar] empty image');
        return null;
      }
      return FanRadarFrame(
        time: time,
        southWest: southWest,
        northEast: northEast,
        width: width,
        height: height,
        imageBytes: bytes,
      );
    } catch (e) {
      debugPrint('[FanRadar] image decode error: $e');
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

  int? _parseInt(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
