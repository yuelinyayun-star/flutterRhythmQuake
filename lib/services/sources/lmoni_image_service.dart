import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../models/nied_station_db.dart';
import '../../models/nied_scan_positions.dart';
import '../../models/nied_calibration.dart';
import 'nied_gif_observation.dart';
import 'nied_gif_value_decoder.dart';
import 'nied_monitor.dart';
import 'shindo_color_util.dart';

class NiedGifFrame {
  final DateTime dataTime;
  final Uint8List surfaceGifBytes;
  final Uint8List? boreholeGifBytes;

  const NiedGifFrame({
    required this.dataTime,
    required this.surfaceGifBytes,
    this.boreholeGifBytes,
  });
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

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _buildStationsFromDb();
  }

  void stop() {
    _isRunning = false;
    _lastFrameTime = null;
    _stations = null;
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
        expireSeconds: 30,
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
    // debugPrint('Lmoni: ${list.length} stations (scan-position mapped only)');
  }

  void processPixels(
    List<int> packedRgb, {
    List<int>? boreholePackedRgb,
    Uint8List? surfaceGifBytes,
    Uint8List? boreholeGifBytes,
    DateTime? dataTime,
  }) {
    if (!_isRunning || _stations == null || _stations!.isEmpty) return;
    if (packedRgb.length != _imgW * _imgH) return;
    if (boreholePackedRgb != null &&
        boreholePackedRgb.length != _imgW * _imgH) {
      boreholePackedRgb = null;
    }

    final stamp = dataTime ?? DateTime.now();
    final receivedAt = DateTime.now();
    _applyFrameGap(stamp);

    for (int i = 0; i < _stations!.length; i++) {
      final s = _stations![i];
      final isKik = s.network.toLowerCase().contains('kik');
      final useBoreholePrimary = isKik && boreholePackedRgb != null;

      int rawLevel = useBoreholePrimary
          ? _sampleRawLevel(boreholePackedRgb, s)
          : _sampleRawLevel(packedRgb, s);
      final boreholeLooksEmpty =
          useBoreholePrimary && rawLevel == 0 && s.continuousShindo <= -2.99;
      if ((rawLevel == -1 || boreholeLooksEmpty) && useBoreholePrimary) {
        rawLevel = _sampleRawLevel(packedRgb, s);
      }
      if (rawLevel == -1) {
        s.updateFromContinuousShindo(-1, null);
        s
          ..lastUpdate = stamp
          ..lastDataTime = stamp
          ..lastReceivedAt = receivedAt;
        continue;
      }

      // GIF path: keep the true continuous shindo value, then derive the
      // 21-step kanameishi detection level from that continuous range only.
      s.updateFromContinuousShindo(rawLevel, s.continuousShindo);
      s
        ..lastUpdate = stamp
        ..lastDataTime = stamp
        ..lastReceivedAt = receivedAt;
    }

    if (surfaceGifBytes != null) {
      final gifFrame = NiedGifFrame(
        dataTime: stamp,
        surfaceGifBytes: Uint8List.fromList(surfaceGifBytes),
        boreholeGifBytes: boreholeGifBytes == null
            ? null
            : Uint8List.fromList(boreholeGifBytes),
      );
      _lastGifFrame = gifFrame;
      _gifFrameController.add(gifFrame);
    }

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

  int _sampleRawLevel(List<int> sourcePixels, NiedStation station) {
    final x = station.pixelX;
    final y = station.pixelY;
    if (x < 0 || x >= _imgW || y < 0 || y >= _imgH) return -1;

    final rgb = sourcePixels[y * _imgW + x];
    final r = (rgb >> 16) & 0xFF;
    final g = (rgb >> 8) & 0xFF;
    final b = rgb & 0xFF;
    final shindo = ShindoColorUtil.rgbaToShindo(r, g, b);
    if (shindo == null) return -1;
    final position = ShindoColorUtil.rgbaToPosition(r, g, b);
    if (position != null && position.isFinite && position > 0) {
      station.updateGifObservation(
        NiedGifValueDecoder.decodeObservationFromPosition(position),
      );
    } else {
      station.updateGifObservation(NiedGifObservation(shindo: shindo));
    }
    final rawLevel = ShindoColorUtil.shindoToRawLevel(shindo);
    if (rawLevel >= 0) {
      // Keep rendered intensity and detection intensity on the same GIF-derived
      // shindo track; otherwise the detector can outrun what the map is showing.
      station.continuousShindo = shindo;
      return rawLevel;
    }
    return -1;
  }

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
        station.recentDetectLevel.clear();
        station.expireSeconds = station.defaultExpireSeconds;
        station.isActive = false;
        station.activeTimer?.cancel();
        station.ascend = 0;
        station.activity = 0;
        station.detectLevel = -1;
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
      station.recentDetectLevel.insertAll(0, noData);
      if (station.recentDetectLevel.length > NiedStation.maxExpireSeconds) {
        station.recentDetectLevel = station.recentDetectLevel.sublist(
          0,
          NiedStation.maxExpireSeconds,
        );
      }

      if (station.expireSeconds > station.defaultExpireSeconds) {
        final nextExpire = station.expireSeconds - missingFrames;
        station.expireSeconds = nextExpire < station.defaultExpireSeconds
            ? station.defaultExpireSeconds
            : nextExpire;
      }

      if (stale) {
        station.isActive = false;
        station.activeTimer?.cancel();
        station.ascend = 0;
        station.activity = 0;
        station.detectLevel = -1;
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
