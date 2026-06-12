import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../ntp_service.dart';
import '../../../core/nied_replay_logger.dart';
import 'lmoni_image_service.dart';
import 'jp_shindo_scale.dart';
import 'nied_gif_observation.dart';

class NiedReplayConfig {
  final bool enabled;
  final DateTime? startJst;
  final int stepSeconds;

  const NiedReplayConfig({
    required this.enabled,
    this.startJst,
    this.stepSeconds = 1,
  });

  const NiedReplayConfig.disabled()
    : enabled = false,
      startJst = null,
      stepSeconds = 1;
}

/// NIED 测站数据模型
class NiedStation {
  final int id;
  final String code;
  final String name;
  final LatLng coordinate;
  final String network;
  final String prefecture;
  int level;
  int detectLevel;
  NiedGifObservation? gifObservation;
  double calibrationFactor;
  int thresholdCode;
  int ascend;
  double activity;
  bool isActive;
  int? _detectState;
  String? _detectReason;
  int get detectState => _detectState ?? 0;
  set detectState(int value) => _detectState = value;
  String get detectReason => _detectReason ?? '';
  set detectReason(String value) => _detectReason = value;
  List<int> recentLevel;
  List<int> recentDetectLevel;
  int expireSeconds;
  int defaultExpireSeconds;
  static const int maxExpireSeconds = 30;
  DateTime? lastUpdate;
  DateTime? lastDataTime;
  DateTime? lastReceivedAt;
  int pixelX;
  int pixelY;
  final bool scanReliable;
  final String? pixelClusterId;
  Timer? activeTimer;

  NiedStation({
    required this.id,
    required this.code,
    required this.name,
    required this.coordinate,
    required this.network,
    required this.prefecture,
    required this.expireSeconds,
    this.pixelX = 0,
    this.pixelY = 0,
    this.scanReliable = true,
    this.pixelClusterId,
    this.level = -1,
    int? detectLevel,
  }) : defaultExpireSeconds = expireSeconds,
       detectLevel = detectLevel ?? -1,
       gifObservation = null,
       calibrationFactor = 1.0,
       thresholdCode = 320,
       ascend = 0,
       activity = 0.0,
       isActive = false,
       _detectState = 0,
       _detectReason = '',
       recentLevel = [],
       recentDetectLevel = [];

  double get continuousShindo => gifObservation?.shindo ?? 0.0;
  set continuousShindo(double value) {
    if (!value.isFinite) return;
    gifObservation = (gifObservation ?? const NiedGifObservation()).copyWith(
      shindo: value,
    );
  }

  void updateGifObservation(NiedGifObservation? observation) {
    if (observation == null) return;
    gifObservation = (gifObservation ?? const NiedGifObservation()).copyWith(
      colorPosition: observation.colorPosition,
      shindo: observation.shindo,
      pga: observation.pga,
      pgv: observation.pgv,
      pgd: observation.pgd,
    );
  }

  void update(int newRawLevel, {int? newDetectLevel, bool render = true}) {
    final originLevel = newRawLevel;
    final originDetectLevel =
        newDetectLevel ??
        JpShindoScale.kanameishiLevelFromDisplayLevel(newRawLevel);
    final effectiveLevel = _effectiveLevel(originLevel, recentLevel);
    final effectiveDetectLevel = _effectiveLevel(
      originDetectLevel,
      recentDetectLevel,
    );

    if (effectiveDetectLevel > detectLevel && detectLevel != -1) {
      expireSeconds = (expireSeconds + 2).clamp(
        defaultExpireSeconds,
        maxExpireSeconds,
      );
    } else if (effectiveDetectLevel < detectLevel ||
        effectiveDetectLevel == -1) {
      expireSeconds = defaultExpireSeconds;
    }

    if (effectiveLevel != level) {
      level = effectiveLevel;
    }
    detectLevel = effectiveDetectLevel;

    final recentFilter = recentDetectLevel
        .take(expireSeconds)
        .where((v) => v != -1)
        .toList();
    int newAscend = 0;
    if (recentFilter.isNotEmpty) {
      final minRecent = recentFilter.reduce((a, b) => a < b ? a : b);
      newAscend = effectiveDetectLevel - minRecent;
    }
    ascend = newAscend;
    activity = _calcActivity(effectiveDetectLevel, ascend);

    recentLevel.insert(0, originLevel);
    if (recentLevel.length > maxExpireSeconds) {
      recentLevel = recentLevel.sublist(0, maxExpireSeconds);
    }
    recentDetectLevel.insert(0, originDetectLevel);
    if (recentDetectLevel.length > maxExpireSeconds) {
      recentDetectLevel = recentDetectLevel.sublist(0, maxExpireSeconds);
    }

    if (expireSeconds > defaultExpireSeconds &&
        !isActive &&
        recentDetectLevel.length >= expireSeconds) {
      final checkFilter = recentDetectLevel
          .sublist(0, expireSeconds)
          .where((v) => v != -1)
          .toList();
      if (checkFilter.isNotEmpty &&
          checkFilter.every((v) => v == checkFilter.first)) {
        expireSeconds = defaultExpireSeconds;
      }
    }
  }

  void updateFromContinuousShindo(
    int newRawLevel,
    double? newContinuousShindo, {
    bool render = true,
  }) {
    if (newContinuousShindo != null && newContinuousShindo.isFinite) {
      continuousShindo = newContinuousShindo;
    }
    // kanameishi only treats NIED shindo-0 as displayable from level 6
    // (roughly -0.5) upward.  Lower negative GIF colors are normal background
    // noise and should not drive the chain detector.
    final detectLevel =
        newContinuousShindo == null ||
            !newContinuousShindo.isFinite ||
            newContinuousShindo < -0.5
        ? -1
        : JpShindoScale.kanameishiLevelFromShindo(newContinuousShindo);
    update(newRawLevel, newDetectLevel: detectLevel, render: render);
  }

  int _effectiveLevel(int originLevel, List<int> recentLevels) {
    if (originLevel != -1) return originLevel;
    if (recentLevels.isEmpty) return -1;
    final sublist = recentLevels.sublist(
      0,
      recentLevels.length < 4 ? recentLevels.length : 4,
    );
    return sublist.firstWhere((v) => v != -1, orElse: () => -1);
  }

  double _calcActivity(int level, int ascend) {
    double levelActivity;
    if (ascend > 0 || isActive) {
      if (level <= 5) {
        levelActivity = 0;
      } else if (level <= 7) {
        levelActivity = isActive ? 0.5 * (level - 5) : 0.25 * (level - 5);
      } else if (level <= 11) {
        levelActivity = 2.0 * (level - 7);
      } else {
        levelActivity = 6.0 * (level - 10);
      }
    } else {
      levelActivity = 0;
    }

    double ascendActivity;
    if (ascend <= 0) {
      ascendActivity = 0;
    } else if (ascend <= 1) {
      ascendActivity = isActive ? 0.5 : 0.25;
    } else if (ascend <= 6) {
      ascendActivity = 2.0 * (ascend - 2) + 1;
    } else {
      ascendActivity = 6.0 * (ascend - 5);
    }

    return levelActivity + ascendActivity;
  }

  void setActive([void Function()? onExpired]) {
    isActive = true;
    activeTimer?.cancel();
    // Align with SREV-style hold window (~10.5s) to reduce lingering false positives.
    activeTimer = Timer(const Duration(milliseconds: 10500), () {
      isActive = false;
      onExpired?.call();
    });
  }

  void terminate() {
    activeTimer?.cancel();
  }
}

/// NIED 强震监测服务 (图片获取与解析版)
class NiedMonitorService extends ChangeNotifier {
  static final NiedMonitorService _instance = NiedMonitorService._internal();
  factory NiedMonitorService() => _instance;
  NiedMonitorService._internal();

  static const String _lmoniBaseUrl = 'https://smi.lmoniexp.bosai.go.jp';
  static const String _kmoniBaseUrl = 'http://www.kmoni.bosai.go.jp';

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  Timer? _timer;
  String? _lastFetchedStampKey;
  String _baseUrl = _lmoniBaseUrl;
  String _sourceName = 'lmoni';
  NiedReplayConfig _replayConfig = const NiedReplayConfig.disabled();
  DateTime? _replayCursorJst;

  /// 回放当前帧时间（供 UI 显示用）
  final ValueNotifier<DateTime?> replayFrameTime = ValueNotifier(null);

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _lastFetchedStampKey = null;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _isRunning = false;
  }

  void configureEndpoint(String source) {
    final nextSource = source == 'kmoni' ? 'kmoni' : 'lmoni';
    final nextBaseUrl = nextSource == 'kmoni' ? _kmoniBaseUrl : _lmoniBaseUrl;
    if (_sourceName == nextSource && _baseUrl == nextBaseUrl) return;

    _sourceName = nextSource;
    _baseUrl = nextBaseUrl;
    _lastFetchedStampKey = null;
  }

  void configureReplay(NiedReplayConfig config) {
    _replayConfig = config;
    _replayCursorJst = config.enabled ? config.startJst : null;
    _lastFetchedStampKey = null;
  }

  Future<void> _tick() async {
    final candidates = _calculateCandidateTimes();
    for (int i = 0; i < candidates.length; i++) {
      final stamp = candidates[i];
      final stampKey = _stampKey(stamp);
      if (stampKey == _lastFetchedStampKey) continue;

      final surface = await _fetchAndDecode(_buildLayerUrl(stamp, 's'));
      if (surface == null) {
        if (_replayConfig.enabled) {
          NiedReplayLogger.instance.logFetchParse(
            jstTime: stamp,
            gifUrl: _buildLayerUrl(stamp, 's'),
            success: false,
          );
          return;
        }
        continue;
      }

      final borehole = await _fetchAndDecode(_buildLayerUrl(stamp, 'b'));

      LmoniImageService().processPixels(
        surface.packedRgb,
        boreholePackedRgb: borehole?.packedRgb,
        surfaceGifBytes: surface.gifBytes,
        boreholeGifBytes: borehole?.gifBytes,
        dataTime: stamp,
      );
      if (_replayConfig.enabled) {
        replayFrameTime.value = stamp;
      }
      NiedReplayLogger.instance.logFetchParse(
        jstTime: stamp,
        gifUrl: _buildLayerUrl(stamp, 's'),
        success: true,
        surfaceW: surface.width,
        surfaceH: surface.height,
      );

      _lastFetchedStampKey = stampKey;
      return;
    }
  }

  Future<_DecodedGifFrame?> _fetchAndDecode(String url) async {
    try {
      final client = HttpClient()
        ..badCertificateCallback =
            ((X509Certificate cert, String host, int port) => true);
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('Referer', _headers['Referer']!);
      request.headers.set('User-Agent', _headers['User-Agent']!);
      final httpResponse = await request.close();
      if (httpResponse.statusCode != 200) {
        client.close();
        return null;
      }
      final bytes = await consolidateHttpClientResponseBytes(httpResponse);
      client.close();
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ui.Image image = frame.image;

      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) {
        image.dispose();
        codec.dispose();
        return null;
      }

      final packedRgb = _convertToPackedRgb(
        byteData,
        image.width,
        image.height,
      );
      image.dispose();
      codec.dispose();
      return _DecodedGifFrame(
        packedRgb: packedRgb,
        gifBytes: Uint8List.fromList(bytes),
        width: image.width,
        height: image.height,
      );
    } catch (e) {
      return null;
    }
  }

  List<DateTime> _calculateCandidateTimes() {
    if (_replayConfig.enabled && _replayConfig.startJst != null) {
      final replayTime = _replayCursorJst ?? _replayConfig.startJst!;
      _replayCursorJst = replayTime.add(
        Duration(seconds: _replayConfig.stepSeconds.clamp(1, 60)),
      );
      return [replayTime];
    }

    final jstNow = NtpService().now.toUtc().add(const Duration(hours: 9));
    return List.generate(90, (i) => jstNow.subtract(Duration(seconds: i + 2)));
  }

  String _buildLayerUrl(DateTime jstTime, String layerSuffix) {
    final ymd =
        "${jstTime.year}${jstTime.month.toString().padLeft(2, '0')}${jstTime.day.toString().padLeft(2, '0')}";
    final hms =
        "${jstTime.hour.toString().padLeft(2, '0')}${jstTime.minute.toString().padLeft(2, '0')}${jstTime.second.toString().padLeft(2, '0')}";
    final layer = 'jma_$layerSuffix';
    return "$_baseUrl/data/map_img/RealTimeImg/$layer/$ymd/$ymd$hms.$layer.gif";
  }

  String _stampKey(DateTime stamp) {
    return "${stamp.year}${stamp.month.toString().padLeft(2, '0')}${stamp.day.toString().padLeft(2, '0')}${stamp.hour.toString().padLeft(2, '0')}${stamp.minute.toString().padLeft(2, '0')}${stamp.second.toString().padLeft(2, '0')}";
  }

  List<int> _convertToPackedRgb(ByteData data, int w, int h) {
    final List<int> pixels = List.filled(w * h, 0);
    for (int i = 0; i < pixels.length; i++) {
      final int offset = i * 4;
      final int r = data.getUint8(offset);
      final int g = data.getUint8(offset + 1);
      final int b = data.getUint8(offset + 2);
      pixels[i] = (r << 16) | (g << 8) | b;
    }
    return pixels;
  }

  Map<String, String> get _headers => {
    'Referer': '$_baseUrl/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };
}

class _DecodedGifFrame {
  final List<int> packedRgb;
  final Uint8List gifBytes;
  final int width;
  final int height;

  const _DecodedGifFrame({
    required this.packedRgb,
    required this.gifBytes,
    required this.width,
    required this.height,
  });
}
