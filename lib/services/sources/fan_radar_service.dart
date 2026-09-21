import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

enum CmaImageProduct { radar, precipitation }

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

// Keep the legacy name and handoff kind for existing map/background consumers.
// The radar itself is fetched directly from China Weather, not FAN.
class FanRadarService {
  static final FanRadarService _instance = FanRadarService._internal(
    CmaImageProduct.radar,
  );
  static final FanRadarService _precipitation = FanRadarService._internal(
    CmaImageProduct.precipitation,
  );
  factory FanRadarService() => _instance;
  factory FanRadarService.precipitation() => _precipitation;
  FanRadarService._internal(this.product)
    : _client = http.Client(),
      _now = DateTime.now;

  @visibleForTesting
  FanRadarService.forTesting({
    required http.Client client,
    DateTime Function()? now,
    this.product = CmaImageProduct.radar,
  }) : _client = client,
       _now = now ?? DateTime.now;

  static const refreshInterval = Duration(minutes: 2);
  static const precipitationRefreshInterval = Duration(minutes: 10);
  final CmaImageProduct product;
  bool get _isPrecipitation => product == CmaImageProduct.precipitation;
  String get _callback => _isPrecipitation ? 'getPreObs1h' : 'readRadarList';
  String get _listUrl => _isPrecipitation
      ? 'https://d1.weather.com.cn/radar_channel/prec1h/rainList.json'
      : 'https://d1.weather.com.cn/radar_channel/radar/json/radar_list.json';
  String get _pictureBase => _isPrecipitation
      ? 'https://d1.weather.com.cn/radar_channel/prec1h/'
      : 'https://d1.weather.com.cn/radar_channel/radar/pic/';

  // Preserve the existing map registration: the direct PNG was byte-identical
  // to FAN's image. Do not substitute bounds taken from a Baidu-map overlay.
  LatLng get _southWest => _isPrecipitation
      ? const LatLng(18, 73)
      : const LatLng(12.316339, 69.64609);
  LatLng get _northEast => _isPrecipitation
      ? const LatLng(55, 136)
      : const LatLng(54.376029, 140.209411);

  static const Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0',
    'Referer': 'https://www.weather.com.cn/',
  };

  final http.Client _client;
  final DateTime Function() _now;

  final StreamController<FanRadarFrame?> _frameController =
      StreamController<FanRadarFrame?>.broadcast();

  Timer? _timer;
  bool _started = false;
  bool _fetching = false;
  bool _fetchQueued = false;
  int _session = 0;
  FanRadarFrame? _latestFrame;
  String? _latestFilename;

  Stream<FanRadarFrame?> get frameStream => _frameController.stream;
  FanRadarFrame? get latestFrame => _latestFrame;
  bool get isRunning => _started;

  Future<void> start({
    Duration interval = refreshInterval,
    int startupAttempts = 3,
  }) {
    if (_started) {
      // Startup race: a previous start may still be fetching, or the first
      // attempt failed. Keep the overlay warm by requesting again when empty.
      if (_latestFrame == null) {
        return fetchNow(maxAttempts: startupAttempts);
      }
      return Future<void>.value();
    }
    _started = true;
    // A new Android subscriber needs the cached image even if the next list
    // request finds no newer frame.
    if (_latestFrame != null) _frameController.add(_latestFrame);
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(fetchNow()));
    return fetchNow(maxAttempts: startupAttempts);
  }

  void stop({bool clear = false}) {
    _session++;
    _timer?.cancel();
    _timer = null;
    _started = false;
    _fetchQueued = false;
    if (clear && _latestFrame != null) {
      _latestFrame = null;
      _latestFilename = null;
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
          if (!_started) return;
          if (session != _session) break;
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
      final uri = Uri.parse(_listUrl).replace(
        queryParameters: {
          'callback': _callback,
          '_': '${_now().millisecondsSinceEpoch}',
        },
      );
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (!_started || session != _session) return false;
      if (response.statusCode != 200) {
        debugPrint('[CmaRadar] list HTTP ${response.statusCode}');
        return false;
      }
      final entry = _latestEntry(utf8.decode(response.bodyBytes));
      final current = _latestFrame;
      if (current != null &&
          (entry.time.isBefore(current.time) ||
              (entry.time == current.time &&
                  entry.filename == _latestFilename))) {
        return true;
      }
      final image = await _client
          .get(Uri.parse('$_pictureBase${entry.filename}'), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (!_started || session != _session) return false;
      if (image.statusCode != 200) {
        debugPrint('[CmaRadar] image HTTP ${image.statusCode}');
        return false;
      }
      final frame = await _decodeFrame(entry.time, image.bodyBytes);
      if (!_started || session != _session) return false;
      _latestFrame = frame;
      _latestFilename = entry.filename;
      _frameController.add(frame);
      debugPrint(
        '[CmaRadar] updated: ${frame.time} '
        '${frame.width}x${frame.height}',
      );
      return true;
    } catch (e) {
      debugPrint('[CmaRadar] fetch error: $e');
      return false;
    }
  }

  ({DateTime time, String filename}) _latestEntry(String text) {
    final match = RegExp(
      '^\\s*${RegExp.escape(_callback)}\\s*\\(([\\s\\S]*)\\)\\s*;?\\s*\$',
    ).firstMatch(text);
    if (match == null) throw const FormatException('Invalid radar JSONP');
    final decoded = jsonDecode(match.group(1)!);
    if (decoded is! Map || decoded['datas'] is! List) {
      throw const FormatException('Missing radar list');
    }
    ({DateTime time, String filename})? latest;
    for (final item in decoded['datas'] as List) {
      if (item is! Map) continue;
      final dt = item['dt'];
      final filename = item[_isPrecipitation ? 'picPath' : 'fn'];
      if (dt is! String ||
          filename is! String ||
          !RegExp(_isPrecipitation ? r'^\d{10}$' : r'^\d{14}$').hasMatch(dt)) {
        continue;
      }
      final expectedFilename = _isPrecipitation
          ? 'prec_$dt.png'
          : 'ACHN_QREF_${dt.substring(0, 8)}_${dt.substring(8)}.png';
      if (filename != expectedFilename) {
        continue;
      }
      final timestamp = _isPrecipitation ? '${dt}0000' : dt;
      final parts = [
        int.parse(timestamp.substring(0, 4)),
        for (var i = 4; i < 14; i += 2)
          int.parse(timestamp.substring(i, i + 2)),
      ];
      final wall = DateTime.utc(
        parts[0],
        parts[1],
        parts[2],
        parts[3],
        parts[4],
        parts[5],
      );
      if (wall.year != parts[0] ||
          wall.month != parts[1] ||
          wall.day != parts[2] ||
          wall.hour != parts[3] ||
          wall.minute != parts[4] ||
          wall.second != parts[5]) {
        continue;
      }
      final time = wall.subtract(const Duration(hours: 8));
      if (latest == null || time.isAfter(latest.time)) {
        latest = (time: time, filename: filename);
      }
    }
    if (latest == null) throw const FormatException('No valid radar frame');
    return latest;
  }

  Future<FanRadarFrame> _decodeFrame(DateTime time, Uint8List bytes) async {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < 33 || bytes.length > 16 * 1024 * 1024) {
      throw const FormatException('Invalid radar image length');
    }
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) {
        throw const FormatException('Radar response is not PNG');
      }
    }
    final header = ByteData.sublistView(bytes);
    final width = header.getUint32(16);
    final height = header.getUint32(20);
    if (width == 0 ||
        height == 0 ||
        width > 8192 ||
        height > 8192 ||
        width * height > 20000000) {
      throw const FormatException('Invalid radar dimensions');
    }
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final decoded = await codec.getNextFrame();
      decoded.image.dispose();
    } finally {
      codec.dispose();
    }
    return FanRadarFrame(
      time: time,
      southWest: _southWest,
      northEast: _northEast,
      width: width,
      height: height,
      imageBytes: bytes,
    );
  }
}
