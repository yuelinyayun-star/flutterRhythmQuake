import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show compute, debugPrint, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

class NsmcSatelliteCloudFrame {
  const NsmcSatelliteCloudFrame({required this.time, required this.imageBytes});
  final DateTime time;
  final Uint8List imageBytes;
}

class NsmcSatelliteCloudService {
  static final _instance = NsmcSatelliteCloudService._(http.Client());
  factory NsmcSatelliteCloudService() => _instance;
  NsmcSatelliteCloudService._(this._client);

  @visibleForTesting
  NsmcSatelliteCloudService.forTest({required http.Client client})
    : _client = client;

  static const refreshInterval = Duration(minutes: 30);
  static const targetTimesUrl =
      'https://data.nsmc.org.cn/nsmcapi/v1/nsmc/image/animation/datatime/mongodb'
      '?dataCode=GEO_MULT_GBAL_L2_GGM_IRX_GLL_YYYYMMDD_HHmm_4000M.PNG&hourRange=24';
  static const mercatorLatitude = 85.0511287798066;
  static const imageWidth = 2048;
  static const imageHeight = 1024;

  final http.Client _client;
  final _frames = StreamController<NsmcSatelliteCloudFrame?>.broadcast();
  Timer? _timer;
  bool _started = false;
  bool _fetching = false;
  bool _queued = false;
  int _session = 0;
  NsmcSatelliteCloudFrame? _latestFrame;

  Stream<NsmcSatelliteCloudFrame?> get frameStream => _frames.stream;
  NsmcSatelliteCloudFrame? get latestFrame => _latestFrame;
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
          if (response.statusCode != 200) continue;
          final time = nsmcSatelliteLatestTime(
            jsonDecode(utf8.decode(response.bodyBytes)),
          );
          if (time == null ||
              (_latestFrame != null && !time.isAfter(_latestFrame!.time))) {
            continue;
          }
          final responseImage = await _client
              .get(nsmcSatelliteImageUri(time))
              .timeout(const Duration(seconds: 30));
          if (!_started || session != _session) continue;
          if (responseImage.statusCode != 200) continue;
          final bytes = await compute(
            nsmcSatelliteToMercator,
            responseImage.bodyBytes,
          );
          if (!_started || session != _session) continue;
          _latestFrame = NsmcSatelliteCloudFrame(time: time, imageBytes: bytes);
          _frames.add(_latestFrame);
        } catch (error) {
          debugPrint('[NsmcSatellite] fetch failed: ${error.runtimeType}');
        }
      } while (_queued && _started);
    } finally {
      _fetching = false;
    }
  }
}

DateTime? nsmcSatelliteLatestTime(Object? raw) {
  if (raw is! Map || raw['returnCode'] != 0 || raw['ds'] is! List) return null;
  DateTime? latest;
  for (final item in raw['ds'] as List) {
    if (item is! Map) continue;
    final date = item['dataDate'];
    final clock = item['dataTime'];
    if (date is! String ||
        clock is! String ||
        !RegExp(r'^\d{8}$').hasMatch(date) ||
        !RegExp(r'^\d{6}$').hasMatch(clock)) {
      continue;
    }
    final time = DateTime.tryParse('${date}T${clock}Z');
    if (time == null) continue;
    final stamp = time
        .toIso8601String()
        .replaceAll(RegExp(r'[-:T]'), '')
        .substring(0, 14);
    if (stamp != '$date$clock') continue;
    if (latest == null || time.isAfter(latest)) latest = time;
  }
  return latest;
}

Uri nsmcSatelliteImageUri(DateTime time) {
  final stamp = time
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp(r'[-:T]'), '')
      .substring(0, 12);
  return Uri.https('data.nsmc.org.cn', '/NSMCAPI/v1/nsmc/image/wms/compose', {
    'layers': 'GEOS_IRX',
    'datetime': stamp,
    'request': 'GetMap',
    'bbox':
        '-180,-${NsmcSatelliteCloudService.mercatorLatitude},180,${NsmcSatelliteCloudService.mercatorLatitude}',
    'width': '${NsmcSatelliteCloudService.imageWidth}',
    'height': '${NsmcSatelliteCloudService.imageHeight}',
    'version': '1.1.0',
    'format': 'png',
  });
}

int nsmcSatelliteSourceRow(int y, int outputHeight, int sourceHeight) {
  final mercatorY = math.pi * (1 - 2 * (y + 0.5) / outputHeight);
  final latitude =
      (2 * math.atan(math.exp(mercatorY)) - math.pi / 2) * 180 / math.pi;
  return ((NsmcSatelliteCloudService.mercatorLatitude - latitude) /
          (2 * NsmcSatelliteCloudService.mercatorLatitude) *
          sourceHeight)
      .floor()
      .clamp(0, sourceHeight - 1);
}

// The WMS returns EPSG:4326. Reproject rows for the map's EPSG:3857 in an
// isolate; preserve source RGBA values, including cloud opacity, unchanged.
Uint8List nsmcSatelliteToMercator(Uint8List bytes) {
  final source = img.decodePng(bytes);
  if (source == null ||
      source.width != NsmcSatelliteCloudService.imageWidth ||
      source.height != NsmcSatelliteCloudService.imageHeight) {
    throw const FormatException(
      'Unexpected NSMC cloud image dimensions or format',
    );
  }
  final rgba = source
      .convert(numChannels: 4)
      .getBytes(order: img.ChannelOrder.rgba);
  var hasCloudPixels = false;
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] > 0) {
      hasCloudPixels = true;
      break;
    }
  }
  if (!hasCloudPixels) {
    throw const FormatException('Empty NSMC cloud image');
  }
  final width = source.width;
  final stride = width * 4;
  final output = Uint8List(width * stride);
  for (var y = 0; y < width; y++) {
    final row = nsmcSatelliteSourceRow(y, width, source.height);
    output.setRange(y * stride, (y + 1) * stride, rgba, row * stride);
  }
  return img.encodePng(
    img.Image.fromBytes(
      width: width,
      height: width,
      bytes: output.buffer,
      numChannels: 4,
    ),
  );
}
