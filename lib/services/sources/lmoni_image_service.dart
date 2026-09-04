import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../models/nied_station_db.dart';
import '../../models/nied_scan_positions.dart';
import '../../models/nied_calibration.dart';
import 'nied_gif_observation.dart';
import 'nied_gif_value_decoder.dart';
import 'nied_monitor.dart';
import 'nied_background_worker.dart';
import 'shindo_color_util.dart';

class NiedGifFrame {
  final DateTime dataTime;
  final Uint8List surfaceGifBytes;

  const NiedGifFrame({required this.dataTime, required this.surfaceGifBytes});
}

class LmoniImageService {
  static final LmoniImageService _instance = LmoniImageService._internal();
  factory LmoniImageService() => _instance;
  LmoniImageService._internal();

  static const int _imgW = 352;
  static const int _imgH = 400;

  bool _isRunning = false;
  DateTime? _lastFrameTime;
  DateTime? get lastFrameTime => _lastFrameTime;
  NiedGifFrame? _lastGifFrame;
  NiedGifFrame? get lastGifFrame => _lastGifFrame;

  final _stationController = StreamController<List<NiedStation>?>.broadcast();
  final _gifFrameController = StreamController<NiedGifFrame>.broadcast();
  final _statusController = StreamController<bool>.broadcast();

  static final Map<String, String> _scanClusterIds = _buildScanClusterIds();

  Stream<List<NiedStation>?> get stationStream => _stationController.stream;
  Stream<NiedGifFrame> get gifFrameStream => _gifFrameController.stream;
  Stream<bool> get statusStream => _statusController.stream;

  void Function(bool connected)? onStatusChanged;

  List<NiedStation>? _stations;
  List<NiedScanConfig> _backgroundScanConfigs = const [];
  String _backgroundScanConfigSignature = '';

  List<NiedScanConfig> get backgroundScanConfigs => _backgroundScanConfigs;
  String get backgroundScanConfigSignature => _backgroundScanConfigSignature;

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _buildStationsFromDb();
  }

  void stop() {
    _isRunning = false;
    for (final station in _stations ?? const <NiedStation>[]) {
      station.terminate();
    }
    _lastFrameTime = null;
    _lastGifFrame = null;
    _stations = null;
    _backgroundScanConfigs = const [];
    _backgroundScanConfigSignature = '';
  }

  void dispose() {
    stop();
    _stationController.close();
    _gifFrameController.close();
    _statusController.close();
  }

  void _buildStationsFromDb() {
    if (_stations != null && _stations!.isNotEmpty) return;
    final db = NiedStationDb.stations;
    final list = <NiedStation>[];

    for (int i = 0; i < db.length; i++) {
      final s = db[i];
      final code = s['code'] as String;
      final lat = (s['lat'] as num).toDouble();
      final lng = (s['lng'] as num).toDouble();
      final pos = NiedScanPositions.positions[code];
      if (pos == null) continue;
      final px = pos[0];
      final py = pos[1];
      final station = NiedStation(
        id: i,
        code: code,
        name: s['name'] as String,
        coordinate: LatLng(lat, lng),
        network: (s['network'] as String?) ?? 'K-NET',
        prefecture: (s['pref'] as String?) ?? '',
        expireSeconds: NiedStation.kaExpireSeconds,
        pixelX: px,
        pixelY: py,
        scanReliable: true,
        pixelClusterId: _scanClusterIds[code],
      );
      station.calibrationFactor =
          NiedCalibration.factors[code] ?? NiedCalibration.defaultFactor;
      station.thresholdCode =
          NiedCalibration.thresholdCodes[code] ??
          NiedCalibration.defaultThresholdCode;
      list.add(station);
    }

    _stations = list;
    _backgroundScanConfigs = List<NiedScanConfig>.unmodifiable([
      for (final station in list)
        NiedScanConfig(pixelX: station.pixelX, pixelY: station.pixelY),
    ]);
    _backgroundScanConfigSignature = list
        .map(
          (station) =>
              '${station.code}:${station.pixelX}:${station.pixelY}:'
              's',
        )
        .join('|');
    // debugPrint('Lmoni: ${list.length} stations (scan-position mapped only)');
  }

  void processPixels(
    List<int> packedRgb, {
    List<int>? boreholePackedRgb,
    Uint8List? surfaceGifBytes,
    Uint8List? boreholeGifBytes,
    DateTime? dataTime,
    DateTime? receivedAt,
    bool publish = true,
  }) {
    if (!_isRunning || _stations == null || _stations!.isEmpty) return;
    if (packedRgb.length != _imgW * _imgH) return;

    final stamp = dataTime ?? DateTime.now();
    final frameReceivedAt = receivedAt ?? DateTime.now();
    _applyFrameGap(stamp);

    for (int i = 0; i < _stations!.length; i++) {
      final s = _stations![i];
      s
        ..lastUpdate = stamp
        ..lastDataTime = stamp
        ..lastReceivedAt = frameReceivedAt;

      final shindo = _sampleRealtimeShindo(packedRgb, s);
      if (shindo == null) {
        s.updateFromContinuousShindo(null);
        continue;
      }

      s.updateFromContinuousShindo(shindo);
    }

    if (surfaceGifBytes != null) {
      final gifFrame = NiedGifFrame(
        dataTime: stamp,
        surfaceGifBytes: surfaceGifBytes,
      );
      _lastGifFrame = gifFrame;
      _gifFrameController.add(gifFrame);
    }

    if (publish) publishStations();
  }

  void processSampledFrame(
    NiedFrameScanResult frame, {
    required Uint8List surfaceGifBytes,
    DateTime? dataTime,
    DateTime? receivedAt,
    bool publish = true,
  }) {
    if (!_isRunning || _stations == null || _stations!.isEmpty) return;
    if (frame.width != _imgW ||
        frame.height != _imgH ||
        frame.samples.length != _stations!.length) {
      return;
    }

    final stamp = dataTime ?? DateTime.now();
    final frameReceivedAt = receivedAt ?? DateTime.now();
    _applyFrameGap(stamp);

    for (var i = 0; i < _stations!.length; i++) {
      final station = _stations![i];
      final sample = frame.samples[i];
      final position = sample.surfacePosition;
      station
        ..lastUpdate = stamp
        ..lastDataTime = stamp
        ..lastReceivedAt = frameReceivedAt;

      if (position == null) {
        station.clearGifObservation(
          NiedGifLayer.realtimeShindo,
          qualityFlag: 'pixel_undecodable',
        );
        station.updateFromContinuousShindo(null);
      } else {
        final observation = NiedGifValueDecoder.decodeObservationFromPosition(
          position,
          layer: NiedGifLayer.realtimeShindo,
        );
        station.updateGifObservation(observation);
        station.updateFromContinuousShindo(observation.shindo);
      }
    }

    final gifFrame = NiedGifFrame(
      dataTime: stamp,
      surfaceGifBytes: Uint8List.fromList(surfaceGifBytes),
    );
    _lastGifFrame = gifFrame;
    _gifFrameController.add(gifFrame);
    if (publish) publishStations();
  }

  void processPhysicalLayerPixels({
    required NiedGifLayer layer,
    required DateTime dataTime,
    required DateTime receivedAt,
    List<int>? surfacePackedRgb,
  }) {
    if (!_isRunning || _stations == null || _stations!.isEmpty) return;
    if (layer == NiedGifLayer.realtimeShindo) {
      throw ArgumentError.value(
        layer,
        'layer',
        'Use the realtime shindo path.',
      );
    }
    if (surfacePackedRgb != null && surfacePackedRgb.length != _imgW * _imgH) {
      surfacePackedRgb = null;
    }

    for (final station in _stations!) {
      final currentDataTime = station.lastDataTime;
      if (currentDataTime != null && dataTime.isBefore(currentDataTime)) {
        continue;
      }
      final selectedPixels = surfacePackedRgb;
      if (selectedPixels == null) {
        station.clearGifObservation(layer, qualityFlag: 'layer_missing');
        continue;
      }
      final position = _sampleColorPosition(selectedPixels, station);
      if (position == null) {
        station.clearGifObservation(layer, qualityFlag: 'pixel_undecodable');
        continue;
      }
      station.updateGifObservation(
        NiedGifValueDecoder.decodeObservationFromPosition(
          position,
          layer: layer,
        ),
      );
      station
        ..lastDataTime = dataTime
        ..lastReceivedAt = receivedAt;
    }
  }

  void publishStations() {
    if (!_isRunning || _stations == null) return;
    _stationController.add(List.unmodifiable(_stations!));
    _statusController.add(true);
    onStatusChanged?.call(true);
  }

  /// 广播外部注入的测站数据（如 K-NET ASCII 导入）
  void broadcastStations(List<NiedStation> stations) {
    _stations = stations;
    _stationController.add(List.unmodifiable(stations));
    _statusController.add(true);
    onStatusChanged?.call(true);
  }

  double? _sampleRealtimeShindo(List<int> sourcePixels, NiedStation station) {
    final x = station.pixelX;
    final y = station.pixelY;
    if (x < 0 || x >= _imgW || y < 0 || y >= _imgH) return null;

    final rgb = sourcePixels[y * _imgW + x];
    final r = (rgb >> 16) & 0xFF;
    final g = (rgb >> 8) & 0xFF;
    final b = rgb & 0xFF;
    final shindo = ShindoColorUtil.rgbaToShindo(r, g, b);
    if (shindo == null) {
      station.clearGifObservation(
        NiedGifLayer.realtimeShindo,
        qualityFlag: 'pixel_undecodable',
      );
      return null;
    }
    final position = ShindoColorUtil.rgbaToPosition(r, g, b);
    if (position != null && position.isFinite) {
      final observation = NiedGifValueDecoder.decodeObservationFromPosition(
        position,
        layer: NiedGifLayer.realtimeShindo,
      );
      station.updateGifObservation(observation);
      return observation.shindo;
    } else {
      station.updateGifObservation(NiedGifObservation(shindo: shindo));
      return shindo;
    }
  }

  double? _sampleColorPosition(List<int> sourcePixels, NiedStation station) {
    final x = station.pixelX;
    final y = station.pixelY;
    if (x < 0 || x >= _imgW || y < 0 || y >= _imgH) return null;
    final rgb = sourcePixels[y * _imgW + x];
    final position = ShindoColorUtil.rgbaToPosition(
      (rgb >> 16) & 0xFF,
      (rgb >> 8) & 0xFF,
      rgb & 0xFF,
    );
    return position != null && position.isFinite ? position : null;
  }

  @visibleForTesting
  void applyFrameGapForTest(DateTime stamp) => _applyFrameGap(stamp);

  void _applyFrameGap(DateTime stamp) {
    final previous = _lastFrameTime;
    if (previous == null) {
      _lastFrameTime = stamp;
      return;
    }

    final diffMs = stamp.difference(previous).inMilliseconds;
    if (diffMs < 0) {
      // 回放模式：时间倒流，重置时间基准并清空测站缓冲
      _lastFrameTime = stamp;
      for (final station in _stations!) {
        station.recentLevel.clear();
        station.expireSeconds = station.defaultExpireSeconds;
        station.isActive = false;
        station.activeTimer?.cancel();
        station.ascend = 0;
        station.activity = 0;
        station.level = -1;
      }
      return;
    }

    _lastFrameTime = stamp;
    if (diffMs <= 1500) return;

    var missingFrames = (diffMs / 1000).round() - 1;
    if (missingFrames <= 0) return;
    if (missingFrames > NiedStation.maxExpireSeconds) {
      missingFrames = NiedStation.maxExpireSeconds;
    }

    final noData = List<int>.filled(missingFrames, -1);
    // SREV-like behavior: if frame gap exceeds ~10s, quickly invalidate active state.
    final stale = diffMs > 10000;
    for (final station in _stations!) {
      station.recentLevel.insertAll(0, noData);
      if (station.recentLevel.length > NiedStation.maxExpireSeconds) {
        station.recentLevel = station.recentLevel.sublist(
          0,
          NiedStation.maxExpireSeconds,
        );
      }
      if (stale) {
        station.isActive = false;
      }
    }
  }

  static Map<String, String> _buildScanClusterIds() {
    final entries = NiedScanPositions.positions.entries.toList(growable: false);
    final parents = <String, String>{};
    final coords = <String, List<int>>{};
    for (final entry in entries) {
      parents[entry.key] = entry.key;
      coords[entry.key] = entry.value;
    }

    String find(String code) {
      var current = code;
      while (parents[current] != current) {
        parents[current] = parents[parents[current]!]!;
        current = parents[current]!;
      }
      return current;
    }

    void union(String a, String b) {
      final rootA = find(a);
      final rootB = find(b);
      if (rootA != rootB) {
        parents[rootB] = rootA;
      }
    }

    for (var i = 0; i < entries.length; i++) {
      final a = entries[i];
      final ax = a.value[0];
      final ay = a.value[1];
      for (var j = i + 1; j < entries.length; j++) {
        final b = entries[j];
        final bx = b.value[0];
        final by = b.value[1];
        if ((ax - bx).abs() <= 1 && (ay - by).abs() <= 1) {
          union(a.key, b.key);
        }
      }
    }

    final byRoot = <String, List<String>>{};
    for (final code in parents.keys) {
      final root = find(code);
      (byRoot[root] ??= <String>[]).add(code);
    }

    final clusterIds = <String, String>{};
    var clusterSeq = 0;
    for (final codes in byRoot.values) {
      if (codes.length <= 1) continue;
      codes.sort();
      final clusterId = 'gif-px-${clusterSeq++}';
      for (final code in codes) {
        clusterIds[code] = clusterId;
      }
    }
    return clusterIds;
  }
}
