import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:http/http.dart' as http;

class JmaSatelliteCloudFrame {
  const JmaSatelliteCloudFrame({
    required this.basetime,
    required this.validtime,
    required this.time,
  });

  final String basetime;
  final String validtime;
  final DateTime time;

  String get tileUrlTemplate =>
      'https://www.jma.go.jp/bosai/himawari/data/satimg/'
      '$basetime/fd/$validtime/B13/TBB/{z}/{x}/{y}.jpg';
}

class JmaSatelliteCloudService {
  static final JmaSatelliteCloudService _instance = JmaSatelliteCloudService._(
    http.Client(),
  );
  factory JmaSatelliteCloudService() => _instance;
  JmaSatelliteCloudService._(this._client);

  @visibleForTesting
  JmaSatelliteCloudService.forTest({required http.Client client})
    : _client = client;

  static const refreshInterval = Duration(minutes: 10);
  static const targetTimesUrl =
      'https://www.jma.go.jp/bosai/himawari/data/satimg/targetTimes_fd.json';

  final http.Client _client;
  final _frames = StreamController<JmaSatelliteCloudFrame?>.broadcast();
  Timer? _timer;
  bool _started = false;
  bool _fetching = false;
  bool _queued = false;
  int _session = 0;
  JmaSatelliteCloudFrame? _latestFrame;

  Stream<JmaSatelliteCloudFrame?> get frameStream => _frames.stream;
  JmaSatelliteCloudFrame? get latestFrame => _latestFrame;
  bool get isRunning => _started;

  void start({Duration interval = refreshInterval}) {
    if (_started) return;
    _started = true;
    if (_latestFrame != null) _frames.add(_latestFrame);
    _timer = Timer.periodic(interval, (_) => unawaited(fetchNow()));
    unawaited(fetchNow());
  }

  void stop({bool clear = false}) {
    _started = false;
    _session++;
    _queued = false;
    _timer?.cancel();
    _timer = null;
    if (clear && _latestFrame != null) {
      _latestFrame = null;
      _frames.add(null);
    }
  }

  Future<void> fetchNow() async {
    if (!_started) return;
    if (_fetching) {
      _queued = true;
      return;
    }
    _fetching = true;
    try {
      do {
        _queued = false;
        final session = _session;
        try {
          final response = await _client
              .get(Uri.parse(targetTimesUrl))
              .timeout(const Duration(seconds: 20));
          if (!_started || session != _session) continue;
          if (response.statusCode != 200) {
            debugPrint('[JmaSatellite] HTTP ${response.statusCode}');
            continue;
          }
          final frame = jmaSatelliteFrameFromTargetTimes(
            jsonDecode(utf8.decode(response.bodyBytes)),
          );
          if (frame == null) continue;
          final previous = _latestFrame;
          if (previous != null &&
              (frame.time.isBefore(previous.time) ||
                  (previous.basetime == frame.basetime &&
                      previous.validtime == frame.validtime))) {
            continue;
          }
          _latestFrame = frame;
          _frames.add(frame);
        } catch (error) {
          debugPrint('[JmaSatellite] fetch failed: ${error.runtimeType}');
        }
      } while (_queued && _started);
    } finally {
      _fetching = false;
    }
  }
}

DateTime? jmaSatelliteTimeFromStamp(Object? value) {
  if (value is! String || !RegExp(r'^\d{14}$').hasMatch(value)) {
    return null;
  }
  final parts = [
    int.parse(value.substring(0, 4)),
    for (var i = 4; i < 14; i += 2) int.parse(value.substring(i, i + 2)),
  ];
  final time = DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
  if (time.year != parts[0] ||
      time.month != parts[1] ||
      time.day != parts[2] ||
      time.hour != parts[3] ||
      time.minute != parts[4] ||
      time.second != parts[5]) {
    return null;
  }
  return time;
}

JmaSatelliteCloudFrame? jmaSatelliteFrameFromTargetTime(Map raw) {
  final base = jmaSatelliteTimeFromStamp(raw['basetime']);
  final valid = jmaSatelliteTimeFromStamp(raw['validtime']);
  if (base == null || valid == null) return null;
  return JmaSatelliteCloudFrame(
    basetime: raw['basetime'] as String,
    validtime: raw['validtime'] as String,
    time: valid,
  );
}

JmaSatelliteCloudFrame? jmaSatelliteFrameFromTargetTimes(Object? raw) {
  if (raw is! List) return null;
  JmaSatelliteCloudFrame? latest;
  for (final item in raw) {
    if (item is! Map) continue;
    final frame = jmaSatelliteFrameFromTargetTime(item);
    if (frame == null) continue;
    if (latest == null ||
        frame.time.isAfter(latest.time) ||
        (frame.time == latest.time &&
            frame.basetime.compareTo(latest.basetime) > 0)) {
      latest = frame;
    }
  }
  return latest;
}
