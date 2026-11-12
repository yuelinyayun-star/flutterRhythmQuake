import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'native_weather_playback_catalog.dart';
import 'sources/source_http_client.dart';
import 'sources/web_source_proxy.dart';
import 'sources/fan_radar_service.dart';
import 'sources/jma_radar_service.dart';
import 'sources/jma_satellite_cloud_service.dart';
import 'sources/nsmc_satellite_cloud_service.dart';

class WeatherPlaybackFrame {
  const WeatherPlaybackFrame(this.source, this.time, this.data);
  final String source;
  final DateTime time;
  final Object data;
}

/// A display session only: no live service writes and no background subscriptions.
/// Retains at most three compressed images / 16 MiB; never caches decoded pixels.
class WeatherPlaybackController extends ChangeNotifier {
  WeatherPlaybackController({
    http.Client? client,
    this.interval = const Duration(milliseconds: 1000),
    this.autoPrepare = true,
  }) : _client = client ?? createSourceHttpClient();
  static const sources = <String, int>{
    'radarChinaLayer': 0,
    'precipitationChinaLayer': 1,
    'jmaRadarLayer': 2,
    'jmaSatelliteCloudLayer': 3,
    'nsmcSatelliteCloudLayer': 4,
  };
  static const _urls = [
    'https://d1.weather.com.cn/radar_channel/radar/json/radar_list.json?callback=readRadarList',
    'https://d1.weather.com.cn/radar_channel/prec1h/rainList.json?callback=getPreObs1h',
    JmaRadarService.targetTimesUrl,
    JmaSatelliteCloudService.targetTimesUrl,
    NsmcSatelliteCloudService.targetTimesUrl,
  ];
  final http.Client _client;
  final Duration interval;
  final bool autoPrepare;
  final frame = ValueNotifier<WeatherPlaybackFrame?>(null);
  final _images = <int, Uint8List>{};
  List<Map<String, dynamic>> entries = const [];
  String? source, error;
  int index = 0, _generation = 0, _request = 0;
  bool loading = false, playing = false, _disposed = false;
  bool _frameBusy = false;
  int? _queuedFrame;
  Completer<void>? _cloudReady;
  void _releaseCloudWait() {
    final ready = _cloudReady;
    _cloudReady = null;
    if (ready != null && !ready.isCompleted) ready.complete();
  }

  bool get isDisposed => _disposed;
  Timer? _timer;
  bool get supported => sources.containsKey(source);
  int get cachedBytes => _images.values.fold(0, (sum, b) => sum + b.length);
  DateTime timeAt(int value) => DateTime.fromMillisecondsSinceEpoch(
    entries[value]['epochMs'] as int,
    isUtc: true,
  );
  void selectSource(String? key) {
    if (_disposed || source == key) return;
    _releaseCloudWait();
    _queuedFrame = null;
    _generation++;
    _request++;
    pause(notify: false);
    source = key;
    entries = const [];
    _images.clear();
    index = 0;
    loading = false;
    error = null;
    frame.value = null;
    notifyListeners();
    if (autoPrepare && supported) unawaited(load());
  }

  Future<Uint8List> _get(String url) async {
    final response = await _client
        .get(
          sourceUri(Uri.parse(url)),
          headers: sourceHeaders({
            'User-Agent': 'Mozilla/5.0',
            'Referer': url.contains('weather.com.cn')
                ? 'https://www.weather.com.cn/'
                : 'https://www.jma.go.jp/',
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200)
      throw StateError('HTTP ${response.statusCode}');
    if (response.bodyBytes.length > 16 * 1024 * 1024)
      throw const FormatException('Image is too large');
    return response.bodyBytes;
  }

  Future<void> load({bool preload = true}) async {
    if (_disposed || !supported || loading) return;
    pause(notify: false);
    final generation = ++_generation;
    _request++;
    _images.clear();
    entries = const [];
    frame.value = null;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final kind = sources[source]!;
      final bytes = await _get(_urls[kind]);
      if (_disposed || generation != _generation) return;
      entries = NativeWeatherPlaybackCatalog.parse(kind, bytes);
      index = entries.isEmpty ? 0 : entries.length - 1;
      if (entries.isEmpty) error = '上游暂未提供可播放的实况帧';
      // Preload original radar images without replacing the live display.
      // Cloud imagery is not prefetched while its source is being reviewed.
      if (preload && kind < 2) {
        for (var i = 0; i < entries.length && i < 2; i++) {
          await _warm(i, generation);
          if (_disposed || generation != _generation) return;
        }
      }
    } catch (e) {
      if (!_disposed && generation == _generation) error = '动画加载失败：$e';
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _warm(int value, int generation) async {
    if (_disposed ||
        generation != _generation ||
        value >= entries.length ||
        _images.containsKey(value))
      return;
    final url = entries[value]['url'];
    if (url is! String) return;
    final bytes = await _get(url);
    _validatePng(bytes);
    if (_disposed || generation != _generation) return;
    _images[value] = bytes;
    while (_images.length > 3 || cachedBytes > 16 * 1024 * 1024) {
      _images.remove(_images.keys.first);
    }
  }

  Future<void> show(int value) async {
    if (entries.isEmpty || _disposed) return;
    if (_frameBusy) {
      _releaseCloudWait();
      _queuedFrame = value;
      _request++;
      return;
    }
    _frameBusy = true;
    final generation = _generation, request = ++_request, key = source!;
    final next = value.clamp(0, entries.length - 1),
        entry = entries[next],
        time = timeAt(next);
    loading = true;
    error = null;
    notifyListeners();
    try {
      Object data;
      if (key == 'jmaRadarLayer') {
        data = JmaRadarFrame(
          basetime: entry['basetime'],
          validtime: entry['validtime'],
          time: time,
        );
      } else if (key == 'jmaSatelliteCloudLayer') {
        data = JmaSatelliteCloudFrame(
          basetime: entry['basetime'],
          validtime: entry['validtime'],
          time: time,
        );
      } else if (key == 'nsmcSatelliteCloudLayer') {
        final ready = Completer<void>();
        _cloudReady = ready;
        data = NsmcSatelliteCloudFrame.tiles(
          time: time,
          onVisibleReady: () {
            if (!ready.isCompleted) ready.complete();
          },
        );
      } else {
        var bytes = _images.remove(next);
        if (bytes == null) {
          bytes = await _get(entry['url'] as String);
          if (_disposed || generation != _generation || request != _request)
            return;
          _validatePng(bytes);
        }
        if (_disposed || generation != _generation || request != _request)
          return;
        _images[next] = bytes;
        while (_images.length > 3 || cachedBytes > 16 * 1024 * 1024) {
          _images.remove(_images.keys.first);
        }
        final radar = key == 'radarChinaLayer',
            header = ByteData.sublistView(bytes);
        data = FanRadarFrame(
          time: time,
          southWest: radar
              ? const LatLng(12.316339, 69.64609)
              : const LatLng(18, 73),
          northEast: radar
              ? const LatLng(54.376029, 140.209411)
              : const LatLng(55, 136),
          width: header.getUint32(16),
          height: header.getUint32(20),
          imageBytes: bytes,
        );
      }
      if (_disposed || generation != _generation || request != _request) return;
      index = next;
      frame.value = WeatherPlaybackFrame(key, time, data);
      if (key == 'nsmcSatelliteCloudLayer') {
        final ready = _cloudReady;
        if (ready != null)
          await ready.future.timeout(const Duration(seconds: 15));
      }
    } catch (e) {
      if (!_disposed && generation == _generation && request == _request) {
        error = '这一帧加载失败：$e';
        pause(notify: false);
      }
    } finally {
      _frameBusy = false;
      if (!_disposed && generation == _generation && request == _request) {
        loading = false;
        notifyListeners();
      }
      final queued = _queuedFrame;
      _queuedFrame = null;
      if (!_disposed && queued != null && entries.isNotEmpty)
        unawaited(show(queued));
    }
  }

  static void _validatePng(Uint8List b) {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (b.length < 33 || !listEquals(b.sublist(0, 8), signature))
      throw const FormatException('Invalid PNG');
    final h = ByteData.sublistView(b),
        w = h.getUint32(16),
        height = h.getUint32(20);
    if (w == 0 ||
        height == 0 ||
        w > 8192 ||
        height > 8192 ||
        w * height > 20000000)
      throw const FormatException('Invalid PNG dimensions');
  }

  Future<void> toggle() async {
    if (playing) {
      pause();
      return;
    }
    if (loading || !supported) return;
    if (entries.isEmpty) await load();
    if (_disposed || entries.length < 2 || error != null) return;
    playing = true;
    notifyListeners();
    await show(index >= entries.length - 1 ? 0 : index);
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (!playing || _disposed) return;
    _timer = Timer(interval, () async {
      await show((index + 1) % entries.length);
      _schedule();
    });
  }

  void pause({bool notify = true}) {
    if (playing) {
      _releaseCloudWait();
      _request++;
      loading = false;
    }
    playing = false;
    _timer?.cancel();
    _timer = null;
    if (notify && !_disposed) notifyListeners();
  }

  Future<void> seek(int value) async {
    pause();
    await show(value);
  }

  void live() {
    if (_disposed) return;
    _releaseCloudWait();
    _generation++;
    _request++;
    _queuedFrame = null;
    pause(notify: false);
    loading = false;
    error = null;
    frame.value = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _releaseCloudWait();
    _disposed = true;
    _generation++;
    _request++;
    pause(notify: false);
    _client.close();
    _images.clear();
    frame.dispose();
    super.dispose();
  }
}
