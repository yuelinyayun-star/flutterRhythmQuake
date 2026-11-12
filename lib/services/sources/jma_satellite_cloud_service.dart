import 'source_http_client.dart';
import 'dart:async';
import 'dart:typed_data';
import 'api_json_decoder.dart';

import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;

import 'web_source_proxy.dart';
import 'native_jma_tile_owner.dart';

class JmaSatelliteCloudFrame {
  const JmaSatelliteCloudFrame({
    required this.basetime,
    required this.validtime,
    required this.time,
  });

  final String basetime;
  final String validtime;
  final DateTime time;

  String get tileUrlTemplate {
    final base = kIsWeb
        ? '${Uri.base.origin}/api/jma-bosai/himawari/data/satimg/'
        : 'https://www.jma.go.jp/bosai/himawari/data/satimg/';
    return '$base$basetime/fd/$validtime/B13/TBB/{z}/{x}/{y}.jpg';
  }
}

class JmaSatelliteCloudService {
  static final JmaSatelliteCloudService _instance =
      JmaSatelliteCloudService._();
  factory JmaSatelliteCloudService() => _instance;
  JmaSatelliteCloudService._()
    : _nativeMode = NativeJmaTileOwner.supported,
      _client = NativeJmaTileOwner.supported ? null : createSourceHttpClient(),
      _testEndpoint = null,
      _testTimeout = null;

  @visibleForTesting
  JmaSatelliteCloudService.forTest({required http.Client client})
    : _client = client,
      _nativeMode = false,
      _testEndpoint = null,
      _testTimeout = null;

  @visibleForTesting
  JmaSatelliteCloudService.forNativeTest({
    required Uri endpoint,
    Duration? timeout,
  }) : _client = null,
       _nativeMode = true,
       _testEndpoint = endpoint,
       _testTimeout = timeout;

  static const refreshInterval = Duration(minutes: 10);
  static const targetTimesUrl =
      'https://www.jma.go.jp/bosai/himawari/data/satimg/targetTimes_fd.json';

  final http.Client? _client;
  final bool _nativeMode;
  final Uri? _testEndpoint;
  final Duration? _testTimeout;
  NativeJmaTileOwner? _native;
  bool get usesNativeBackend => _nativeMode;
  Future<Uint8List?> loadNativeTile(Uri url, Future<void> cancel) =>
      _native?.tile(url.path, cancel) ?? Future.value(null);
  Future<Map<String, dynamic>> nativeDiagnostics() async =>
      await _native?.diagnostics() ?? {};
  void _bindNativeFrame(Map<String, dynamic>? value) {
    if (value == null) {
      if (_latestFrame != null) {
        _latestFrame = null;
        _frames.add(null);
      }
      return;
    }
    final frame = JmaSatelliteCloudFrame(
      basetime: value['basetime'] as String,
      validtime: value['validtime'] as String,
      time: DateTime.fromMillisecondsSinceEpoch(
        value['epochMs'] as int,
        isUtc: true,
      ),
    );
    _latestFrame = frame;
    _frames.add(frame);
  }

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
    if (_nativeMode) {
      (_native ??= NativeJmaTileOwner(
        satellite: true,
        onFrame: _bindNativeFrame,
      )).start(
        interval: interval,
        testEndpoint: _testEndpoint,
        testTimeout: _testTimeout,
      );
      return;
    }
    if (_latestFrame != null) _frames.add(_latestFrame);
    _timer = Timer.periodic(interval, (_) => unawaited(fetchNow()));
    unawaited(fetchNow());
  }

  void stop({bool clear = false}) {
    if (_nativeMode) {
      if (!_started && (!clear || (_native == null && _latestFrame == null)))
        return;
      _started = false;
      _native?.stop(clear: clear);
      if (clear) {
        _native?.dispose();
        _native = null;
      }
      if (clear && _latestFrame != null) {
        _latestFrame = null;
        _frames.add(null);
      }
      return;
    }
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
    if (_nativeMode) {
      if (_started) await _native?.fetch();
      return;
    }
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
          final response = await _client!
              .get(sourceUri(Uri.parse(targetTimesUrl)))
              .timeout(const Duration(seconds: 20));
          if (!_started || session != _session) continue;
          if (response.statusCode != 200) {
            debugPrint('[JmaSatellite] HTTP ${response.statusCode}');
            continue;
          }
          final frame = jmaSatelliteFrameFromTargetTimes(
            decodeApiJsonBytes(response.bodyBytes),
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

  Future<void> dispose() async {
    stop(clear: true);
    _native?.dispose();
    _native = null;
    _client?.close();
    await _frames.close();
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
