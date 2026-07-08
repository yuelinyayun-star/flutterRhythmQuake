import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/nied_replay_logger.dart';
import '../../core/source_estimation/kotoho7_js_receiver_bridge.dart';
import '../../services/ntp_service.dart';
import 'lmoni_image_service.dart';
import 'jp_shindo_scale.dart';
import 'nied_gif_observation.dart';
import 'nied_background_worker.dart';

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
  final Map<NiedGifLayer, NiedGifObservation> gifObservations;
  final Map<NiedGifLayer, Set<String>> gifLayerQualityFlags;
  NiedGifObservation? get gifObservation =>
      gifObservations[NiedGifLayer.realtimeShindo];
  NiedGifObservation? get pgaObservation =>
      gifObservations[NiedGifLayer.peakAcceleration];
  NiedGifObservation? get pgvObservation =>
      gifObservations[NiedGifLayer.peakVelocity];
  NiedGifObservation? get pgdObservation =>
      gifObservations[NiedGifLayer.peakDisplacement];
  double calibrationFactor;
  int thresholdCode;
  int ascend;
  int triggerStamp;
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
  static const int maxExpireSeconds = 60;
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
       gifObservations = <NiedGifLayer, NiedGifObservation>{},
       gifLayerQualityFlags = <NiedGifLayer, Set<String>>{},
       calibrationFactor = 1.0,
       thresholdCode = 320,
       ascend = 0,
       triggerStamp = 0,
       activity = 0.0,
       isActive = false,
       _detectState = 0,
       _detectReason = '',
       recentLevel = [],
       recentDetectLevel = [];

  double get continuousShindo => gifObservation?.shindo ?? 0.0;
  set continuousShindo(double value) {
    if (!value.isFinite) return;
    final current =
        gifObservation ??
        const NiedGifObservation(layer: NiedGifLayer.realtimeShindo);
    gifObservations[NiedGifLayer.realtimeShindo] = current.copyWith(
      layer: NiedGifLayer.realtimeShindo,
      shindo: value,
    );
  }

  void updateGifObservation(NiedGifObservation? observation) {
    if (observation == null) return;
    gifObservations[observation.layer] = observation;
    gifLayerQualityFlags.remove(observation.layer);
  }

  void clearGifObservation(NiedGifLayer layer, {required String qualityFlag}) {
    gifObservations.remove(layer);
    gifLayerQualityFlags[layer] = {qualityFlag};
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

    // Push to recentLevel BEFORE calcAscend (matches reference order: unshift then calcAscend)
    recentLevel.insert(0, originLevel);
    if (recentLevel.length > maxExpireSeconds) {
      recentLevel = recentLevel.sublist(0, maxExpireSeconds);
    }
    recentDetectLevel.insert(0, originDetectLevel);
    if (recentDetectLevel.length > maxExpireSeconds) {
      recentDetectLevel = recentDetectLevel.sublist(0, maxExpireSeconds);
    }

    // calcAscend uses recentLevel and level (display level), matching reference
    final ascendResult = _calcAscend(recentLevel, expireSeconds);
    var newAscend = ascendResult.$1;
    var newTriggerStamp = ascendResult.$2;
    // isAbnormalStation check: if abnormal, skip ascend/triggerStamp
    if (_isAbnormalStation()) {
      newAscend = 0;
      newTriggerStamp = 0;
    }
    ascend = newAscend;
    triggerStamp = newAscend > 0 ? newTriggerStamp : 0;
    activity = _calcActivity(level, ascend);

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
    final detectLevel =
        newContinuousShindo == null || !newContinuousShindo.isFinite
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

/// Equivalent to reference calcAscend: fills -1 gaps, finds latest minimum
  /// where trend reverses, returns (ascend, triggerStamp).
  /// triggerStamp = updateStamp - latestMinIndex * 1000 (only if original
  /// recentLevel at latestMinIndex is not -1).
  (int, int) _calcAscend(List<int> recentLevels, int expireSeconds) {
    if (recentLevels.isEmpty) return (0, 0);

    // Copy and fill -1 gaps with next valid value, stop if gap > expireSeconds
    final arr = List<int>.from(recentLevels);
    var i = 0;
    while (i < arr.length) {
      if (arr[i] == -1) {
        var nanCount = 1;
        var nextValidIndex = i + 1;
        while (nextValidIndex < arr.length && arr[nextValidIndex] == -1) {
          nanCount++;
          if (nanCount > expireSeconds) {
            arr.removeRange(i, arr.length);
            break;
          }
          nextValidIndex++;
        }
        if (nextValidIndex < arr.length && i < arr.length) {
          arr[i] = arr[nextValidIndex];
          i++;
        } else if (i < arr.length) {
          arr.removeRange(i, arr.length);
          break;
        }
      } else {
        i++;
      }
    }
    if (arr.isEmpty) return (0, 0);

    // Find latest minimum: scan until trend reverses or identical stretch exceeds expireSeconds
    var latestMinVal = arr[0];
    var latestMinIndex = 0;
    var identicalCount = 1;
    for (var j = 0; j < arr.length - 1; j++) {
      final current = arr[j];
      final next = arr[j + 1];
      if (next < current) {
        latestMinVal = next;
        latestMinIndex = j + 1;
        identicalCount = 1;
      } else if (next > current) {
        break;
      } else {
        identicalCount++;
        if (identicalCount > expireSeconds) {
          break;
        }
      }
    }

    final ascend = level - latestMinVal;
    final triggerStamp = ascend > 0 && recentLevels[latestMinIndex] != -1
        ? (lastDataTime?.millisecondsSinceEpoch ??
            lastUpdate?.millisecondsSinceEpoch ??
            0) - latestMinIndex * 1000
        : 0;
    return (ascend, triggerStamp);
  }

  /// Equivalent to reference isAbnormalStation: detects 3+ peaks with
  /// amplitude >= 3 in recentLevel.
  bool _isAbnormalStation() {
    final recentFilter = recentLevel.where((v) => v != -1).toList();
    if (recentFilter.length < 3) return false;

    var peakCount = 0;
    var i = 1;
    final n = recentFilter.length;
    while (i < n) {
      while (i < n && recentFilter[i] <= recentFilter[i - 1]) {
        i++;
      }
      if (i >= n) break;
      var leftBottom = recentFilter[i - 1];
      var top = recentFilter[i];
      while (i < n && recentFilter[i] >= recentFilter[i - 1]) {
        top = recentFilter[i];
        i++;
      }
      if (i >= n) break;
      var rightBottom = recentFilter[i];
      while (i < n && recentFilter[i] <= recentFilter[i - 1]) {
        rightBottom = recentFilter[i];
        i++;
      }
      if (top - leftBottom >= 3 && top - rightBottom >= 3) {
        peakCount++;
      }
    }
    return peakCount >= 3;
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
  static const Duration _metadataTimeout = Duration(seconds: 3);
  static const Duration _surfaceTimeout = Duration(seconds: 3);
  static const Duration _optionalLayerTimeout = Duration(milliseconds: 900);
  static const int _defaultRealtimeDelayMs = 1200;
  static const int _maxRealtimeDelayMs = 5000;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  Timer? _timer;
  bool _isTicking = false;
  bool _isPhysicalLayerTicking = false;
  String? _lastFetchedStampKey;
  DateTime? _lastFetchedFrameTime;
  DateTime? _lastDelayDecayAt;
  int _realtimeDelayMs = _defaultRealtimeDelayMs;
  String _baseUrl = _lmoniBaseUrl;
  String _sourceName = 'lmoni';
  NiedReplayConfig _replayConfig = const NiedReplayConfig.disabled();
  DateTime? _replayCursorJst;
  bool _physicalLayersEnabled = false;
  final HttpClient _client = HttpClient()
    ..badCertificateCallback = ((X509Certificate cert, String host, int port) =>
        true)
    ..connectionTimeout = const Duration(seconds: 8);

  /// 回放当前帧时间（供 UI 显示用）
  final ValueNotifier<DateTime?> replayFrameTime = ValueNotifier(null);

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _lastFetchedStampKey = null;
    _lastFetchedFrameTime = null;
    _lastDelayDecayAt = null;
    _realtimeDelayMs = _defaultRealtimeDelayMs;
    _resetLiveFrameAnchor();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isTicking = false;
    _isRunning = false;
  }

  void configureEndpoint(String source) {
    final nextSource = source == 'kmoni' ? 'kmoni' : 'lmoni';
    final nextBaseUrl = nextSource == 'kmoni' ? _kmoniBaseUrl : _lmoniBaseUrl;
    if (_sourceName == nextSource && _baseUrl == nextBaseUrl) return;

    _sourceName = nextSource;
    _baseUrl = nextBaseUrl;
    _lastFetchedStampKey = null;
    _lastFetchedFrameTime = null;
    _lastDelayDecayAt = null;
    _realtimeDelayMs = _defaultRealtimeDelayMs;
    _resetLiveFrameAnchor();
  }

  void configureReplay(NiedReplayConfig config) {
    _replayConfig = config;
    _replayCursorJst = config.enabled ? config.startJst : null;
    _lastFetchedStampKey = null;
    _lastFetchedFrameTime = null;
    _resetLiveFrameAnchor();
  }

  void setPhysicalLayersEnabled(bool enabled) {
    _physicalLayersEnabled = enabled;
  }

  Future<void> _tick() async {
    if (_isTicking) return;
    _isTicking = true;
    try {
      final candidates = await _calculateCandidateTimes();
      var attempted = false;
      for (int i = 0; i < candidates.length; i++) {
        final stamp = candidates[i];
        final stampKey = _stampKey(stamp);
        if (stampKey == _lastFetchedStampKey) continue;

        attempted = true;
        final surfaceBytes = await _fetchLayerSurfaceBytes(
          stamp,
          layer: NiedGifLayer.realtimeShindo,
          timeout: _surfaceTimeout,
        );
        if (surfaceBytes == null) {
          if (_replayConfig.enabled) {
            NiedReplayLogger.instance.logFetchParse(
              jstTime: stamp,
              gifUrl: _buildLayerUrl(stamp, borehole: false),
              success: false,
            );
            return;
          }
          continue;
        }
        _decayRealtimeDelayIfNeeded();

        final imageService = LmoniImageService();
        final frameReceivedAt = DateTime.now();
        final backgroundFrame = await NiedBackgroundWorker.instance
            .scanFrame(
              surfaceBytes: surfaceBytes,
              configs: imageService.backgroundScanConfigs,
              configSignature: imageService.backgroundScanConfigSignature,
            )
            .timeout(_optionalLayerTimeout, onTimeout: () => null);
        int surfaceWidth;
        int surfaceHeight;
        if (backgroundFrame != null) {
          imageService.processSampledFrame(
            backgroundFrame,
            surfaceGifBytes: surfaceBytes,
            dataTime: stamp,
            receivedAt: frameReceivedAt,
            publish: false,
          );
          surfaceWidth = backgroundFrame.width;
          surfaceHeight = backgroundFrame.height;
        } else {
          final surface = await _decodeBytes(surfaceBytes);
          if (surface == null) continue;
          imageService.processPixels(
            surface.packedRgb,
            surfaceGifBytes: surfaceBytes,
            dataTime: stamp,
            receivedAt: frameReceivedAt,
            publish: false,
          );
          surfaceWidth = surface.width;
          surfaceHeight = surface.height;
        }
        imageService.publishStations();
        if (_replayConfig.enabled) {
          await _waitForReplaySourceBridgeBackpressure();
        }
        if (_physicalLayersEnabled) {
          unawaited(
            _processPhysicalLayers(
              stamp: stamp,
              receivedAt: frameReceivedAt,
              imageService: imageService,
            ),
          );
        }
        if (_replayConfig.enabled) {
          replayFrameTime.value = stamp;
        }
        NiedReplayLogger.instance.recordGifBytes(
          jstTime: stamp,
          gifUrl: _buildLayerUrl(stamp, borehole: false),
          bytes: surfaceBytes,
          layerKey: NiedGifLayer.realtimeShindo.imageKey(borehole: false),
        );
        NiedReplayLogger.instance.logFetchParse(
          jstTime: stamp,
          gifUrl: _buildLayerUrl(stamp, borehole: false),
          success: true,
          surfaceW: surfaceWidth,
          surfaceH: surfaceHeight,
        );

        _lastFetchedStampKey = stampKey;
        _lastFetchedFrameTime = stamp;
        return;
      }
      if (attempted) {
        _increaseRealtimeDelay();
      }
    } finally {
      _isTicking = false;
    }
  }

  Future<void> _processPhysicalLayers({
    required DateTime stamp,
    required DateTime receivedAt,
    required LmoniImageService imageService,
  }) async {
    if (_isPhysicalLayerTicking) return;
    _isPhysicalLayerTicking = true;
    try {
      final layerBundle = await _fetchPhysicalLayers(stamp);
      for (final layer in const [
        NiedGifLayer.peakAcceleration,
        NiedGifLayer.peakVelocity,
        NiedGifLayer.peakDisplacement,
      ]) {
        final bytes = layerBundle[layer];
        final surface = bytes?.surface == null
            ? null
            : await _decodeBytes(bytes!.surface!);
        imageService.processPhysicalLayerPixels(
          layer: layer,
          dataTime: stamp,
          receivedAt: receivedAt,
          surfacePackedRgb: surface?.packedRgb,
        );
      }
      imageService.publishStations();
    } finally {
      _isPhysicalLayerTicking = false;
    }
  }

  Future<Uint8List?> _fetchBytes(
    String url, {
    required Duration timeout,
  }) async {
    try {
      final request = await _client.getUrl(Uri.parse(url)).timeout(timeout);
      request.headers.set('Referer', _headers['Referer']!);
      request.headers.set('User-Agent', _headers['User-Agent']!);
      request.headers.set('Cache-Control', 'no-cache');
      request.headers.set('Pragma', 'no-cache');
      final httpResponse = await request.close().timeout(timeout);
      if (httpResponse.statusCode != 200) {
        return null;
      }
      return Uint8List.fromList(
        await consolidateHttpClientResponseBytes(httpResponse).timeout(timeout),
      );
    } catch (e) {
      return null;
    }
  }

  Future<Uint8List?> _fetchLayerSurfaceBytes(
    DateTime stamp, {
    required NiedGifLayer layer,
    required Duration timeout,
  }) {
    return _fetchBytes(
      _buildLayerUrl(stamp, layer: layer, borehole: false),
      timeout: timeout,
    );
  }

  Future<Map<NiedGifLayer, _NiedLayerBytes>> _fetchPhysicalLayers(
    DateTime stamp,
  ) async {
    const layers = [
      NiedGifLayer.peakAcceleration,
      NiedGifLayer.peakVelocity,
      NiedGifLayer.peakDisplacement,
    ];
    final results = await Future.wait([
      for (final layer in layers) _fetchLayerBytes(stamp, layer),
    ]);
    return {
      for (var index = 0; index < layers.length; index++)
        layers[index]: results[index],
    };
  }

  Future<_NiedLayerBytes> _fetchLayerBytes(
    DateTime stamp,
    NiedGifLayer layer,
  ) async {
    final surface = await _fetchLayerSurfaceBytes(
      stamp,
      layer: layer,
      timeout: _optionalLayerTimeout,
    );
    return _NiedLayerBytes(surface: surface);
  }

  Future<_DecodedGifFrame?> _decodeBytes(Uint8List bytes) async {
    try {
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
      final width = image.width;
      final height = image.height;
      image.dispose();
      codec.dispose();
      return _DecodedGifFrame(
        packedRgb: packedRgb,
        gifBytes: bytes,
        width: width,
        height: height,
      );
    } catch (e) {
      return null;
    }
  }

  Future<List<DateTime>> _calculateCandidateTimes() async {
    if (_replayConfig.enabled && _replayConfig.startJst != null) {
      final replayTime = _replayCursorJst ?? _replayConfig.startJst!;
      _replayCursorJst = replayTime.add(
        Duration(seconds: _replayConfig.stepSeconds.clamp(1, 60)),
      );
      return [replayTime];
    }

    final projected = _targetLiveFrameTime();
    final latest = await _fetchLatestFrameTime();
    if (latest != null) {
      return _buildLiveCandidateTimes(
        latestTime: latest,
        projectedTime: projected,
        previousFrameTime: _lastFetchedFrameTime,
      );
    }

    return _buildLiveCandidateTimes(
      latestTime: projected,
      projectedTime: projected,
      previousFrameTime: _lastFetchedFrameTime,
    );
  }

  Future<void> _waitForReplaySourceBridgeBackpressure() async {
    await Future<void>.delayed(Duration.zero);
    const maxWait = Duration(milliseconds: 1200);
    final stopwatch = Stopwatch()..start();
    var lastLogged = '';
    while (stopwatch.elapsed < maxWait) {
      final status = Kotoho7JsReceiverBridge.queueStatus();
      if (!status.hasWork) return;
      final signature =
          '${status.pendingFrameCount}/${status.inFlightSessionCount}';
      if (kDebugMode && signature != lastLogged) {
        lastLogged = signature;
        debugPrint(
          '[NIED Replay] wait JS bridge '
          'pending=${status.pendingFrameCount} '
          'inFlight=${status.inFlightSessionCount}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  Future<DateTime?> _fetchLatestFrameTime() async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final text = await _fetchText(
      '$_baseUrl/webservice/server/pros/latest.json?_=$nowMs',
    );
    if (text == null) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return null;
      final latest = decoded['latest_time'];
      if (latest is! String) return null;
      return _parseJstStampText(latest);
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static List<DateTime> buildLiveCandidateTimesForTest({
    required DateTime latestTime,
    DateTime? projectedTime,
    DateTime? previousFrameTime,
  }) {
    return _buildLiveCandidateTimes(
      latestTime: latestTime,
      projectedTime: projectedTime,
      previousFrameTime: previousFrameTime,
    );
  }

  static List<DateTime> _buildLiveCandidateTimes({
    required DateTime latestTime,
    DateTime? projectedTime,
    DateTime? previousFrameTime,
  }) {
    final candidates = <DateTime>[];
    final seen = <String>{};

    void add(DateTime time) {
      final key =
          "${time.year}${time.month.toString().padLeft(2, '0')}${time.day.toString().padLeft(2, '0')}${time.hour.toString().padLeft(2, '0')}${time.minute.toString().padLeft(2, '0')}${time.second.toString().padLeft(2, '0')}";
      if (seen.add(key)) candidates.add(time);
    }

    var targetTime = latestTime;
    if (projectedTime != null && projectedTime.isAfter(targetTime)) {
      targetTime = projectedTime;
    }

    if (previousFrameTime != null) {
      if (targetTime.isAfter(previousFrameTime)) {
        final gapSeconds = targetTime.difference(previousFrameTime).inSeconds;
        if (gapSeconds > 10) {
          add(targetTime);
          if (latestTime.isAfter(previousFrameTime)) add(latestTime);
          return candidates;
        } else {
          final catchUpCount = gapSeconds.clamp(1, 5).toInt();
          for (var i = 1; i <= catchUpCount; i++) {
            add(previousFrameTime.add(Duration(seconds: i)));
          }
        }
      }
      for (var i = 0; i < 30; i++) {
        final fallback = latestTime.subtract(Duration(seconds: i));
        if (!fallback.isAfter(previousFrameTime)) break;
        add(fallback);
      }
      return candidates;
    }

    if (targetTime.isAfter(latestTime)) {
      final aheadSeconds = targetTime
          .difference(latestTime)
          .inSeconds
          .clamp(0, 12)
          .toInt();
      for (var i = aheadSeconds; i >= 1; i--) {
        add(latestTime.add(Duration(seconds: i)));
      }
    }
    for (var i = 0; i < 30; i++) {
      add(latestTime.subtract(Duration(seconds: i)));
    }
    return candidates;
  }

  DateTime _targetLiveFrameTime() {
    final jstNow = NtpService().now.toUtc().add(const Duration(hours: 9));
    final target = jstNow.subtract(Duration(milliseconds: _realtimeDelayMs));
    return DateTime(
      target.year,
      target.month,
      target.day,
      target.hour,
      target.minute,
      target.second,
    );
  }

  void _increaseRealtimeDelay() {
    if (_replayConfig.enabled) return;
    if (_realtimeDelayMs <= _maxRealtimeDelayMs - 100) {
      _realtimeDelayMs += 100;
    }
  }

  void _decayRealtimeDelayIfNeeded() {
    if (_replayConfig.enabled) return;
    final now = DateTime.now();
    final lastDecay = _lastDelayDecayAt;
    if (lastDecay != null &&
        now.difference(lastDecay) < const Duration(seconds: 10)) {
      return;
    }
    _lastDelayDecayAt = now;
    if (_realtimeDelayMs <= _defaultRealtimeDelayMs) {
      _realtimeDelayMs = _defaultRealtimeDelayMs;
      return;
    }
    final step = _realtimeDelayMs <= (_maxRealtimeDelayMs * 2 ~/ 3) ? 20 : 100;
    _realtimeDelayMs = (_realtimeDelayMs - step).clamp(
      _defaultRealtimeDelayMs,
      _maxRealtimeDelayMs,
    );
  }

  void _resetLiveFrameAnchor() {}

  Future<String?> _fetchText(String url) async {
    try {
      final request = await _client
          .getUrl(Uri.parse(url))
          .timeout(_metadataTimeout);
      request.headers.set('Referer', _headers['Referer']!);
      request.headers.set('User-Agent', _headers['User-Agent']!);
      request.headers.set('Cache-Control', 'no-cache');
      request.headers.set('Pragma', 'no-cache');
      final response = await request.close().timeout(_metadataTimeout);
      if (response.statusCode != 200) return null;
      return await utf8.decoder.bind(response).join().timeout(_metadataTimeout);
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseJstStampText(String text) {
    final match = RegExp(
      r'^(\d{4})/(\d{2})/(\d{2}) (\d{2}):(\d{2}):(\d{2})$',
    ).firstMatch(text.trim());
    if (match == null) return null;
    try {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
    } catch (_) {
      return null;
    }
  }

  String _buildLayerUrl(
    DateTime jstTime, {
    NiedGifLayer layer = NiedGifLayer.realtimeShindo,
    required bool borehole,
  }) =>
      layer.imageUri(jstTime, borehole: borehole, baseUrl: _baseUrl).toString();

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

class _NiedLayerBytes {
  const _NiedLayerBytes({required this.surface});

  final Uint8List? surface;
}
