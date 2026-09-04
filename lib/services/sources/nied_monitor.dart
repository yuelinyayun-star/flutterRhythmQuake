import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/nied_replay_logger.dart';
import '../ntp_service.dart';
import '../../core/source_estimation/kotoho7_js_receiver_bridge.dart';
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

  /// KA level in the -1..20 domain used by detection, display, and estimation.
  int level;
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
  int? abnormalUpdateCount;
  int? _detectState;
  String? _detectReason;
  int get detectState => _detectState ?? 0;
  set detectState(int value) => _detectState = value;
  String get detectReason => _detectReason ?? '';
  set detectReason(String value) => _detectReason = value;
  List<int> recentLevel;

  int expireSeconds;
  int defaultExpireSeconds;
  static const int kaExpireSeconds = 10;
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
  }) : defaultExpireSeconds = expireSeconds,
       gifObservations = <NiedGifLayer, NiedGifObservation>{},
       gifLayerQualityFlags = <NiedGifLayer, Set<String>>{},
       calibrationFactor = 1.0,
       thresholdCode = 320,
       ascend = 0,
       triggerStamp = 0,
       activity = 0.0,
       isActive = false,
       abnormalUpdateCount = null,
       _detectState = 0,
       _detectReason = '',
       recentLevel = [];

  double get continuousShindo => gifObservation?.shindo ?? 0.0;
  int get kaLevel => level;
  List<int> get recentKaLevel => recentLevel;

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

  void update(int newLevel, {bool render = true}) {
    final originLevel = newLevel.clamp(-1, 20).toInt();
    final effectiveLevel = _effectiveLevel(originLevel, recentLevel);

    level = effectiveLevel;

    // Push before detection, matching KA's unshift-before-calc order.
    recentLevel.insert(0, originLevel);
    if (recentLevel.length > maxExpireSeconds) {
      recentLevel = recentLevel.sublist(0, maxExpireSeconds);
    }

    var newAscend = 0;
    var newTriggerStamp = 0;
    if (_isAbnormalStation(recentKaLevel)) {
      abnormalUpdateCount = 0;
    } else if (abnormalUpdateCount != null) {
      final nextCount = abnormalUpdateCount! + 1;
      abnormalUpdateCount = nextCount >= 600 ? null : nextCount;
    } else {
      final ascendResult = _calcAscend(
        recentKaLevel,
        expireSeconds,
        currentLevel: kaLevel,
      );
      newAscend = ascendResult.$1;
      newTriggerStamp = ascendResult.$2;
    }
    ascend = newAscend;
    triggerStamp = newAscend > 0 ? newTriggerStamp : 0;
    activity = _calcActivity(kaLevel, ascend);
  }

  void updateFromContinuousShindo(
    double? newContinuousShindo, {
    bool render = true,
  }) {
    if (newContinuousShindo != null && newContinuousShindo.isFinite) {
      continuousShindo = newContinuousShindo;
    }
    final level = newContinuousShindo == null || !newContinuousShindo.isFinite
        ? -1
        : JpShindoScale.kanameishiLevelFromShindo(newContinuousShindo);
    update(level, render: render);
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

  /// Matches KA calcAscend: fills short -1 gaps, then scans backwards until
  /// the first level rebound to find the latest minimum.
  (int, int) _calcAscend(
    List<int> recentLevels,
    int expireSeconds, {
    required int currentLevel,
  }) {
    if (recentLevels.isEmpty) return (0, 0);

    // Fill short missing runs with the next valid value. Long or trailing
    // missing runs end the usable history, exactly as in KA.
    final arr = List<int>.from(recentLevels);
    var index = 0;
    while (index < arr.length) {
      if (arr[index] != -1) {
        index++;
        continue;
      }
      var missingCount = 1;
      var nextValidIndex = index + 1;
      while (nextValidIndex < arr.length && arr[nextValidIndex] == -1) {
        missingCount++;
        if (missingCount > expireSeconds) {
          arr.removeRange(index, arr.length);
          break;
        }
        nextValidIndex++;
      }
      if (index >= arr.length) break;
      if (nextValidIndex < arr.length) {
        arr[index] = arr[nextValidIndex];
        index++;
      } else {
        arr.removeRange(index, arr.length);
        break;
      }
    }
    if (arr.isEmpty) return (0, 0);

    var latestMinVal = arr[0];
    var latestMinIndex = 0;
    var identicalCount = 1;
    for (var i = 0; i < arr.length - 1; i++) {
      final current = arr[i];
      final next = arr[i + 1];
      if (next < current) {
        latestMinVal = next;
        latestMinIndex = i + 1;
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

    final ascend = currentLevel - latestMinVal;
    final triggerStamp = ascend > 0 && recentLevels[latestMinIndex] != -1
        ? (lastDataTime?.millisecondsSinceEpoch ??
                  lastUpdate?.millisecondsSinceEpoch ??
                  0) -
              latestMinIndex * 1000
        : 0;
    return (ascend, triggerStamp);
  }

  /// Equivalent to reference isAbnormalStation: detects 3+ peaks with
  /// amplitude >= 3 in KA level history.
  bool _isAbnormalStation(List<int> recentLevels) {
    final recentFilter = recentLevels.where((v) => v != -1).toList();
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
    // KA keeps an activated NIED station for 10.5 seconds so the hold spans
    // the boundary before the next one-second frame arrives.
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

  static const String _lmoniBaseUrl = 'https://www.lmoni.bosai.go.jp/img_svr';
  static const String _kmoniBaseUrl = 'http://www.kmoni.bosai.go.jp';
  static const Duration _metadataTimeout = Duration(seconds: 3);
  static const Duration _metadataRefreshInterval = Duration(seconds: 60);
  static const Duration _surfaceTimeout = Duration(seconds: 3);
  static const Duration _optionalLayerTimeout = Duration(milliseconds: 900);
  static const int _defaultRealtimeDelayMs = 0;
  static const int _maxRealtimeDelayMs = 5000;
  static const int _maxLiveCandidateAttemptsPerTick = 3;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  Timer? _timer;
  int _runGeneration = 0;
  int? _tickingGeneration;
  int? _physicalLayerGeneration;
  int? _timeSyncGeneration;
  String? _lastFetchedStampKey;
  DateTime? _lastFetchedFrameTime;
  DateTime? _liveFrameAnchorJst;
  final Stopwatch _liveFrameAnchorClock = Stopwatch();
  final Stopwatch _metadataRefreshClock = Stopwatch();
  int _realtimeDelayMs = _defaultRealtimeDelayMs;
  String _baseUrl = _lmoniBaseUrl;
  String _sourceName = 'lmoni';
  NiedReplayConfig _replayConfig = const NiedReplayConfig.disabled();
  DateTime? _replayCursorJst;
  bool _physicalLayersEnabled = false;
  HttpClient? _client;

  /// 回放当前帧时间（供 UI 显示用）
  final ValueNotifier<DateTime?> replayFrameTime = ValueNotifier(null);
  final ValueNotifier<DateTime?> dataFrameTime = ValueNotifier(null);

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _lastFetchedStampKey = null;
    _lastFetchedFrameTime = null;
    _realtimeDelayMs = _defaultRealtimeDelayMs;
    _resetLiveFrameAnchor();
    _runGeneration++;
    _client = _createHttpClient();
    unawaited(_tick());
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_tick()),
    );
  }

  void stop() {
    _isRunning = false;
    _physicalLayersEnabled = false;
    _runGeneration++;
    _timer?.cancel();
    _timer = null;
    _tickingGeneration = null;
    _physicalLayerGeneration = null;
    _client?.close(force: true);
    _client = null;
    dataFrameTime.value = null;
  }

  void configureEndpoint(String source) {
    final nextSource = source == 'kmoni' ? 'kmoni' : 'lmoni';
    final nextBaseUrl = _baseUrlForSource(nextSource);
    if (_sourceName == nextSource && _baseUrl == nextBaseUrl) return;

    _sourceName = nextSource;
    _baseUrl = nextBaseUrl;
    _lastFetchedStampKey = null;
    _lastFetchedFrameTime = null;
    dataFrameTime.value = null;
    _realtimeDelayMs = _defaultRealtimeDelayMs;
    _resetLiveFrameAnchor();
    _restartRunningRequests();
  }

  void configureReplay(NiedReplayConfig config) {
    _replayConfig = config;
    _replayCursorJst = config.enabled ? config.startJst : null;
    _lastFetchedStampKey = null;
    _lastFetchedFrameTime = null;
    dataFrameTime.value = null;
    _resetLiveFrameAnchor();
    _restartRunningRequests();
  }

  void setPhysicalLayersEnabled(bool enabled) {
    _physicalLayersEnabled = enabled;
  }

  Future<void> _tick() async {
    if (!_isRunning) return;
    final generation = _runGeneration;
    if (_tickingGeneration == generation) return;
    _tickingGeneration = generation;
    try {
      final candidates = await _calculateCandidateTimes(generation);
      if (!_isCurrentRun(generation)) return;
      final attemptCount = _replayConfig.enabled
          ? candidates.length
          : _liveCandidateAttemptCount(candidates.length);
      final forwardCatchUp =
          !_replayConfig.enabled &&
          _isForwardCatchUpCandidates(candidates, attemptCount);
      var attempted = false;
      var fetchedAny = false;
      List<Uint8List?>? prefetchedSurfaceBytes;
      if (forwardCatchUp) {
        attempted = attemptCount > 0;
        prefetchedSurfaceBytes = await Future.wait([
          for (var i = 0; i < attemptCount; i++)
            _fetchLayerSurfaceBytes(
              candidates[i],
              layer: NiedGifLayer.realtimeShindo,
              timeout: _surfaceTimeout,
              generation: generation,
            ),
        ]);
        if (!_isCurrentRun(generation)) return;
      }
      for (int i = 0; i < attemptCount; i++) {
        if (!_isCurrentRun(generation)) return;
        final stamp = candidates[i];
        final stampKey = _stampKey(stamp);
        if (stampKey == _lastFetchedStampKey) continue;

        attempted = true;
        final surfaceBytes = prefetchedSurfaceBytes == null
            ? await _fetchLayerSurfaceBytes(
                stamp,
                layer: NiedGifLayer.realtimeShindo,
                timeout: _surfaceTimeout,
                generation: generation,
              )
            : prefetchedSurfaceBytes[i];
        if (!_isCurrentRun(generation)) return;
        if (surfaceBytes == null) {
          if (_replayConfig.enabled) {
            NiedReplayLogger.instance.logFetchParse(
              jstTime: stamp,
              gifUrl: _buildLayerUrl(stamp, borehole: false),
              success: false,
            );
            return;
          }
          if (forwardCatchUp) {
            continue;
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
        if (!_isCurrentRun(generation)) return;
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
          if (surface == null) {
            continue;
          }
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
        fetchedAny = true;
        if (_replayConfig.enabled) {
          await _waitForReplaySourceBridgeBackpressure();
        }
        if (_physicalLayersEnabled &&
            (!forwardCatchUp || i == attemptCount - 1)) {
          unawaited(
            _processPhysicalLayers(
              stamp: stamp,
              receivedAt: frameReceivedAt,
              imageService: imageService,
              generation: generation,
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
        dataFrameTime.value = stamp;
        if (!_replayConfig.enabled && _timeSyncGeneration != generation) {
          _timeSyncGeneration = generation;
          unawaited(_resyncClockAfterConnection(generation));
        }
        if (!forwardCatchUp) return;
        // Broadcast streams are asynchronous and station objects are reused.
        // Let the detection/HYP listener consume this exact frame before the
        // next catch-up frame mutates the same station instances.
        await Future<void>.delayed(Duration.zero);
      }
      if (attempted && !fetchedAny) {
        _increaseRealtimeDelay();
      }
    } finally {
      if (_tickingGeneration == generation) {
        _tickingGeneration = null;
      }
    }
  }

  Future<void> _processPhysicalLayers({
    required DateTime stamp,
    required DateTime receivedAt,
    required LmoniImageService imageService,
    required int generation,
  }) async {
    if (!_isCurrentRun(generation) || _physicalLayerGeneration == generation) {
      return;
    }
    _physicalLayerGeneration = generation;
    try {
      final layerBundle = await _fetchPhysicalLayers(stamp, generation);
      if (!_isCurrentRun(generation)) return;
      for (final layer in const [
        NiedGifLayer.peakAcceleration,
        NiedGifLayer.peakVelocity,
        NiedGifLayer.peakDisplacement,
      ]) {
        final bytes = layerBundle[layer];
        final surface = bytes?.surface == null
            ? null
            : await _decodeBytes(bytes!.surface!);
        if (!_isCurrentRun(generation)) return;
        imageService.processPhysicalLayerPixels(
          layer: layer,
          dataTime: stamp,
          receivedAt: receivedAt,
          surfacePackedRgb: surface?.packedRgb,
        );
      }
      imageService.publishStations();
    } finally {
      if (_physicalLayerGeneration == generation) {
        _physicalLayerGeneration = null;
      }
    }
  }

  Future<void> _resyncClockAfterConnection(int generation) async {
    final connectedAt = DateTime.now();
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!_isCurrentRun(generation)) return;
      await NtpService().syncTime();
      if (!_isCurrentRun(generation)) return;
      final syncedAt = NtpService().lastSyncedAt;
      if (syncedAt != null && !syncedAt.isBefore(connectedAt)) return;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  Future<Uint8List?> _fetchBytes(
    String url, {
    required Duration timeout,
    required int generation,
  }) async {
    final client = _client;
    if (!_isCurrentRun(generation) || client == null) return null;
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      if (!_isCurrentRun(generation) || !identical(client, _client)) {
        request.abort();
        return null;
      }
      request.headers.set('Referer', _headers['Referer']!);
      request.headers.set('User-Agent', _headers['User-Agent']!);
      request.headers.set('Cache-Control', 'no-cache');
      request.headers.set('Pragma', 'no-cache');
      final httpResponse = await request.close().timeout(timeout);
      if (!_isCurrentRun(generation) || !identical(client, _client)) {
        return null;
      }
      if (httpResponse.statusCode != 200) {
        return null;
      }
      return await consolidateHttpClientResponseBytes(
        httpResponse,
      ).timeout(timeout);
    } catch (e) {
      return null;
    }
  }

  Future<Uint8List?> _fetchLayerSurfaceBytes(
    DateTime stamp, {
    required NiedGifLayer layer,
    required Duration timeout,
    required int generation,
  }) {
    return _fetchBytes(
      _buildLayerUrl(stamp, layer: layer, borehole: false),
      timeout: timeout,
      generation: generation,
    );
  }

  Future<Map<NiedGifLayer, _NiedLayerBytes>> _fetchPhysicalLayers(
    DateTime stamp,
    int generation,
  ) async {
    const layers = [
      NiedGifLayer.peakAcceleration,
      NiedGifLayer.peakVelocity,
      NiedGifLayer.peakDisplacement,
    ];
    final results = await Future.wait([
      for (final layer in layers) _fetchLayerBytes(stamp, layer, generation),
    ]);
    return {
      for (var index = 0; index < layers.length; index++)
        layers[index]: results[index],
    };
  }

  Future<_NiedLayerBytes> _fetchLayerBytes(
    DateTime stamp,
    NiedGifLayer layer,
    int generation,
  ) async {
    final surface = await _fetchLayerSurfaceBytes(
      stamp,
      layer: layer,
      timeout: _optionalLayerTimeout,
      generation: generation,
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

  Future<List<DateTime>> _calculateCandidateTimes(int generation) async {
    if (_replayConfig.enabled && _replayConfig.startJst != null) {
      final replayTime = _replayCursorJst ?? _replayConfig.startJst!;
      _replayCursorJst = replayTime.add(
        Duration(seconds: _replayConfig.stepSeconds.clamp(1, 60)),
      );
      return [replayTime];
    }

    final latest = await _latestFrameTimeForTick(generation);
    if (latest != null) {
      return _buildLiveCandidateTimes(
        latestTime: latest,
        projectedTime: _projectLiveFrameTime(),
        previousFrameTime: _lastFetchedFrameTime,
      );
    }

    final anchor = _liveFrameAnchorJst;
    if (anchor == null) {
      // Lmoni metadata is authoritative once reachable. Before the first
      // latest_time arrives, keep trying the real-time GIF path from the
      // locally corrected clock so a metadata outage cannot suppress all GIF
      // requests indefinitely.
      return _buildLocalFallbackCandidateTimes(
        correctedNow: NtpService().now,
        realtimeDelayMs: _realtimeDelayMs,
        previousFrameTime: _lastFetchedFrameTime,
      );
    }
    return _buildLiveCandidateTimes(
      latestTime: anchor,
      projectedTime: _projectLiveFrameTime(),
      previousFrameTime: _lastFetchedFrameTime,
    );
  }

  Future<DateTime?> _latestFrameTimeForTick(int generation) async {
    final anchor = _liveFrameAnchorJst;
    final refreshDue =
        anchor == null ||
        !_metadataRefreshClock.isRunning ||
        _metadataRefreshClock.elapsed >= _metadataRefreshInterval;
    if (!refreshDue) return anchor;

    _metadataRefreshClock
      ..reset()
      ..start();
    if (anchor == null) {
      await _refreshLiveFrameAnchor(generation);
      return _liveFrameAnchorJst;
    }

    // The official viewers keep the one-second image clock running while
    // their periodic server-time refresh is in flight. Do the same so a slow
    // metadata response cannot pause GIF updates.
    unawaited(_refreshLiveFrameAnchor(generation));
    return anchor;
  }

  Future<void> _refreshLiveFrameAnchor(int generation) async {
    final latest = await _fetchLatestFrameTime(generation);
    if (!_isCurrentRun(generation) || latest == null) return;
    _updateLiveFrameAnchor(latest);
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

  Future<DateTime?> _fetchLatestFrameTime(int generation) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final text = await _fetchText(
      _latestFrameMetadataUrlForSource(_sourceName, nowMs),
      generation,
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

  static String _latestFrameMetadataUrlForSource(String source, int nonce) =>
      '${_baseUrlForSource(source)}/webservice/server/pros/latest.json?_=$nonce';

  @visibleForTesting
  static String latestFrameMetadataUrlForTest({
    required String source,
    required int nonce,
  }) => _latestFrameMetadataUrlForSource(source, nonce);

  static int _liveCandidateAttemptCount(int candidateCount) =>
      candidateCount.clamp(0, _maxLiveCandidateAttemptsPerTick).toInt();

  @visibleForTesting
  static int liveCandidateAttemptCountForTest(int candidateCount) =>
      _liveCandidateAttemptCount(candidateCount);

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

  @visibleForTesting
  static List<DateTime> buildLocalFallbackCandidateTimesForTest({
    required DateTime correctedNow,
    int realtimeDelayMs = _defaultRealtimeDelayMs,
    DateTime? previousFrameTime,
  }) {
    return _buildLocalFallbackCandidateTimes(
      correctedNow: correctedNow,
      realtimeDelayMs: realtimeDelayMs,
      previousFrameTime: previousFrameTime,
    );
  }

  @visibleForTesting
  static String gifLayerUrlForTest({
    required String source,
    required DateTime jstTime,
    NiedGifLayer layer = NiedGifLayer.realtimeShindo,
    bool borehole = false,
  }) {
    final baseUrl = _baseUrlForSource(source);
    return layer
        .imageUri(jstTime, borehole: borehole, baseUrl: baseUrl)
        .toString();
  }

  static String _baseUrlForSource(String source) =>
      source == 'kmoni' ? _kmoniBaseUrl : _lmoniBaseUrl;

  static List<DateTime> _buildLocalFallbackCandidateTimes({
    required DateTime correctedNow,
    required int realtimeDelayMs,
    DateTime? previousFrameTime,
  }) {
    final utc = correctedNow.toUtc().add(const Duration(hours: 9));
    // The rest of the GIF path uses JST wall-clock DateTimes parsed from
    // latest_time, so retain the same representation for local fallback.
    final jstWallClock = DateTime(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      utc.second,
      utc.millisecond,
      utc.microsecond,
    );
    final delayed = jstWallClock.subtract(
      Duration(milliseconds: realtimeDelayMs.clamp(0, _maxRealtimeDelayMs)),
    );
    return _buildLiveCandidateTimes(
      latestTime: delayed,
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
      final catchUpTarget = latestTime.isAfter(previousFrameTime)
          ? latestTime
          : targetTime;
      if (catchUpTarget.isAfter(previousFrameTime)) {
        // Preserve the one-second station history used by triggerStamp and
        // HYP clustering. Metadata is only a periodic time anchor; projected
        // seconds between metadata refreshes must use the same ordered path.
        var next = previousFrameTime.add(const Duration(seconds: 1));
        for (var i = 0; i < 30 && !next.isAfter(catchUpTarget); i++) {
          add(next);
          next = next.add(const Duration(seconds: 1));
        }
      }
      return candidates;
    }

    add(latestTime);
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
    for (var i = 1; i < 30; i++) {
      add(latestTime.subtract(Duration(seconds: i)));
    }
    return candidates;
  }

  static bool _isForwardCatchUpCandidates(
    List<DateTime> candidates,
    int attemptCount,
  ) {
    if (attemptCount < 2) return false;
    for (var index = 1; index < attemptCount; index++) {
      if (!candidates[index].isAfter(candidates[index - 1])) return false;
    }
    return true;
  }

  void _updateLiveFrameAnchor(DateTime latest) {
    final current = _liveFrameAnchorJst;
    if (current != null && !latest.isAfter(current)) return;
    _liveFrameAnchorJst = latest;
    _liveFrameAnchorClock
      ..reset()
      ..start();
  }

  DateTime? _projectLiveFrameTime() {
    final anchor = _liveFrameAnchorJst;
    if (anchor == null) return null;
    final elapsedMs = _liveFrameAnchorClock.elapsedMilliseconds;
    final projectedMs = (elapsedMs - _realtimeDelayMs).clamp(0, elapsedMs);
    final projected = anchor.add(Duration(milliseconds: projectedMs));
    return DateTime(
      projected.year,
      projected.month,
      projected.day,
      projected.hour,
      projected.minute,
      projected.second,
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
    if (_realtimeDelayMs <= _defaultRealtimeDelayMs) {
      _realtimeDelayMs = _defaultRealtimeDelayMs;
      return;
    }
    _realtimeDelayMs = (_realtimeDelayMs - 100).clamp(
      _defaultRealtimeDelayMs,
      _maxRealtimeDelayMs,
    );
  }

  void _resetLiveFrameAnchor() {
    _liveFrameAnchorJst = null;
    _liveFrameAnchorClock
      ..stop()
      ..reset();
    _metadataRefreshClock
      ..stop()
      ..reset();
  }

  Future<String?> _fetchText(String url, int generation) async {
    final client = _client;
    if (!_isCurrentRun(generation) || client == null) return null;
    try {
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(_metadataTimeout);
      if (!_isCurrentRun(generation) || !identical(client, _client)) {
        request.abort();
        return null;
      }
      request.headers.set('Referer', _headers['Referer']!);
      request.headers.set('User-Agent', _headers['User-Agent']!);
      request.headers.set('Cache-Control', 'no-cache');
      request.headers.set('Pragma', 'no-cache');
      final response = await request.close().timeout(_metadataTimeout);
      if (!_isCurrentRun(generation) || !identical(client, _client)) {
        return null;
      }
      if (response.statusCode != 200) return null;
      return await utf8.decoder.bind(response).join().timeout(_metadataTimeout);
    } catch (_) {
      return null;
    }
  }

  HttpClient _createHttpClient() => HttpClient()
    ..badCertificateCallback = ((X509Certificate cert, String host, int port) =>
        true)
    ..connectionTimeout = const Duration(seconds: 8);

  bool _isCurrentRun(int generation) =>
      _isRunning && _runGeneration == generation;

  void _restartRunningRequests() {
    if (!_isRunning) return;
    final previousClient = _client;
    _runGeneration++;
    _tickingGeneration = null;
    _physicalLayerGeneration = null;
    _client = _createHttpClient();
    previousClient?.close(force: true);
    unawaited(_tick());
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
    final rgba = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final pixels = Uint32List(w * h);
    for (int i = 0; i < pixels.length; i++) {
      final int offset = i * 4;
      final int r = rgba[offset];
      final int g = rgba[offset + 1];
      final int b = rgba[offset + 2];
      pixels[i] = (r << 16) | (g << 8) | b;
    }
    return pixels;
  }

  Map<String, String> get _headers => {
    'Referer': _sourceName == 'kmoni'
        ? 'http://www.kmoni.bosai.go.jp/'
        : 'https://www.lmoni.bosai.go.jp/monitor/',
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
