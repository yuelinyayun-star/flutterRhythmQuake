import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:http/http.dart' as http;

class JmaRadarFrame {
  const JmaRadarFrame({
    required this.basetime,
    required this.validtime,
    required this.time,
  });

  final String basetime;
  final String validtime;
  final DateTime time;

  String get tileUrlTemplate => jmaRadarTileUrlTemplate(basetime, validtime);
}

class JmaRadarService {
  static final JmaRadarService _instance = JmaRadarService._(http.Client());
  factory JmaRadarService() => _instance;

  @visibleForTesting
  JmaRadarService.forTest({http.Client? client})
    : _client = client ?? http.Client();

  JmaRadarService._(this._client);

  static const Duration refreshInterval = Duration(minutes: 5);
  static const String targetTimesUrl =
      'https://www.jma.go.jp/bosai/jmatile/data/nowc/targetTimes_N1.json';

  static const Map<String, String> _headers = {
    'Accept': 'application/json, text/plain, */*',
    'Referer': 'https://www.jma.go.jp/bosai/nowc/',
    'User-Agent': 'flutterrhythmquake/1.0',
  };

  final http.Client _client;
  final StreamController<JmaRadarFrame?> _frameController =
      StreamController<JmaRadarFrame?>.broadcast();

  Timer? _timer;
  bool _started = false;
  bool _fetching = false;
  bool _fetchQueued = false;
  int _session = 0;
  JmaRadarFrame? _latestFrame;

  Stream<JmaRadarFrame?> get frameStream => _frameController.stream;
  JmaRadarFrame? get latestFrame => _latestFrame;
  bool get isRunning => _started;

  void start({Duration interval = refreshInterval, int startupAttempts = 3}) {
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
      final response = await _client
          .get(Uri.parse(targetTimesUrl), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (!_started || session != _session) return false;
      if (response.statusCode != 200) {
        debugPrint('[JmaRadar] HTTP ${response.statusCode}');
        return false;
      }
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      final frame = jmaRadarFrameFromTargetTimes(json);
      if (frame == null) {
        debugPrint('[JmaRadar] no usable target time');
        return false;
      }
      if (!_started || session != _session) return false;
      final unchanged =
          _latestFrame != null &&
          _latestFrame!.basetime == frame.basetime &&
          _latestFrame!.validtime == frame.validtime;
      _latestFrame = frame;
      if (!unchanged) {
        _frameController.add(frame);
      }
      debugPrint('[JmaRadar] updated: ${frame.validtime}');
      return true;
    } catch (e) {
      debugPrint('[JmaRadar] fetch error: $e');
      return false;
    }
  }
}

@visibleForTesting
String jmaRadarTileUrlTemplate(String basetime, String validtime) {
  return 'https://www.jma.go.jp/bosai/jmatile/data/nowc/'
      '$basetime/none/$validtime/surf/hrpns/{z}/{x}/{y}.png';
}

/// JMA `hrpns` tiles only contain real precipitation at even zooms 4/6/8/10.
/// Odd zooms and z>10 return a 200 empty transparent PNG, which looks like
/// the overlay vanished.
int jmaRadarNativeZoom(double zoom) {
  const minNative = 4;
  const maxNative = 10;
  final clamped = zoom.round().clamp(minNative, maxNative);
  return clamped - (clamped % 2);
}

@visibleForTesting
JmaRadarFrame? jmaRadarFrameFromTargetTimes(Object? json) {
  if (json is! List || json.isEmpty) return null;
  JmaRadarFrame? latest;
  for (final item in json) {
    if (item is! Map) continue;
    final frame = jmaRadarFrameFromTargetTime(Map<String, dynamic>.from(item));
    if (frame == null) continue;
    if (latest == null ||
        frame.time.isAfter(latest.time) ||
        (frame.time == latest.time &&
            frame.validtime.compareTo(latest.validtime) > 0)) {
      latest = frame;
    }
  }
  return latest;
}

@visibleForTesting
JmaRadarFrame? jmaRadarFrameFromTargetTime(Map<String, dynamic> raw) {
  final basetime = '${raw['basetime'] ?? ''}'.trim();
  final validtime = '${raw['validtime'] ?? ''}'.trim();
  if (basetime.isEmpty || validtime.isEmpty) return null;
  final elements = raw['elements'];
  if (elements is List && !elements.map((item) => '$item').contains('hrpns')) {
    return null;
  }
  final time =
      jmaRadarTimeFromStamp(validtime) ?? jmaRadarTimeFromStamp(basetime);
  if (time == null) return null;
  return JmaRadarFrame(basetime: basetime, validtime: validtime, time: time);
}

@visibleForTesting
DateTime? jmaRadarTimeFromStamp(String stamp) {
  final text = stamp.trim();
  if (text.length < 12 || !RegExp(r'^\d+$').hasMatch(text)) return null;
  final year = int.tryParse(text.substring(0, 4));
  final month = int.tryParse(text.substring(4, 6));
  final day = int.tryParse(text.substring(6, 8));
  final hour = int.tryParse(text.substring(8, 10));
  final minute = int.tryParse(text.substring(10, 12));
  final second = text.length >= 14 ? int.tryParse(text.substring(12, 14)) : 0;
  if (year == null ||
      month == null ||
      day == null ||
      hour == null ||
      minute == null ||
      second == null) {
    return null;
  }
  return DateTime(year, month, day, hour, minute, second);
}
