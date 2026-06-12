import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../services/sources/shake_detection_service.dart';

/// NIED 回放日志记录器
///
/// 开启后在 Debug 页会自动记录全链路日志到文件，
/// 供离线分析：GIF URL → 解析 → 检测 → 推算震中
class NiedReplayLogger {
  static final NiedReplayLogger instance = NiedReplayLogger._();
  NiedReplayLogger._();

  bool _enabled = false;
  final List<Map<String, dynamic>> _frames = [];
  String? _logPath;
  DateTime? _sessionStart;

  bool get isEnabled => _enabled;

  void setEnabled(bool v) {
    if (v == _enabled) return;
    _enabled = v;
    if (v) {
      _frames.clear();
      _sessionStart = DateTime.now();
      _logPath = null;
      debugPrint('[ReplayLogger] ENABLED — session started');
    } else {
      _flush();
      debugPrint('[ReplayLogger] DISABLED — saved to $_logPath');
    }
  }

  /// 记录每帧: GIF 抓取 + 解析结果
  void logFetchParse({
    required DateTime jstTime,
    required String gifUrl,
    required bool success,
    int surfaceW = 0,
    int surfaceH = 0,
    int parsedCount = 0,
    int maxRawLevel = -1,
    Map<String, int>? stationLevels,
  }) {
    if (!_enabled) return;
    _frames.add({
      'type': 'frame',
      'jst': jstTime.toIso8601String(),
      'gif_url': gifUrl,
      'success': success,
      'img_w': surfaceW,
      'img_h': surfaceH,
      'parsed_stations': parsedCount,
      'max_raw_level': maxRawLevel,
      if (stationLevels != null) 'station_levels': stationLevels,
    });
    _autoSave();
  }

  /// 记录检测结果
  void logDetection(ShakeDetectionSnapshot snapshot) {
    if (!_enabled) return;
    _frames.add({
      'type': 'detection',
      'stage': snapshot.stage.name,
      'weak': snapshot.weakCount,
      'detected': snapshot.detectedCount,
      'strong': snapshot.strongCount,
      'max_shindo': snapshot.maxShindo,
      'stations': snapshot.detectedStations
          .map((s) => {
                'code': s.code,
                'pref': s.prefecture,
                'level': s.level,
                'shindo': s.jmaShindo,
                'state': s.detectState,
                'reason': s.detectReason,
              })
          .toList(),
    });
    _autoSave();
  }

  /// 记录震中推算
  void logEpicenter({
    double? lat,
    double? lng,
    double? confidence,
    int activeStationCount = 0,
  }) {
    if (!_enabled) return;
    _frames.add({
      'type': 'epicenter',
      'lat': lat,
      'lng': lng,
      'confidence': confidence,
      'active_count': activeStationCount,
    });
    _autoSave();
  }

  int _lastAutoSaveCount = 0;
  void _autoSave() {
    // 每 10 条记录自动写一次文件
    if (_frames.length - _lastAutoSaveCount >= 10) {
      _lastAutoSaveCount = _frames.length;
      _writeSync();
    }
  }

  /// 同步写入 (可从任何上下文调用)
  void _writeSync() {
    if (!_enabled || _frames.isEmpty) return;
    try {
      final home = Platform.environment['USERPROFILE'] ?? '.';
      final ts = _sessionStart != null
          ? '${_sessionStart!.year}${_sessionStart!.month.toString().padLeft(2, '0')}${_sessionStart!.day.toString().padLeft(2, '0')}_${_sessionStart!.hour.toString().padLeft(2, '0')}${_sessionStart!.minute.toString().padLeft(2, '0')}${_sessionStart!.second.toString().padLeft(2, '0')}'
          : 'unknown';
      final outDir = Directory('$home/Desktop');
      if (!outDir.existsSync()) outDir.createSync(recursive: true);
      final file = File('${outDir.path}/nied_replay_$ts.json');
      final payload = {
        'session_start': _sessionStart?.toIso8601String(),
        'written_at': DateTime.now().toIso8601String(),
        'frame_count': _frames.where((f) => f['type'] == 'frame').length,
        'detection_count': _frames.where((f) => f['type'] == 'detection').length,
        'epicenter_count': _frames.where((f) => f['type'] == 'epicenter').length,
        'frames': _frames,
      };
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(payload),
      );
      _logPath = file.path;
    } catch (e) {
      // silent — avoid flooding console
    }
  }

  /// 写入文件到桌面 (async, 用于关闭时保存)
  Future<void> _flush() async {
    _writeSync();
  }

  /// 手动触发保存
  Future<void> save() => _flush();

  /// 上次保存路径
  String? get lastLogPath => _logPath;
}
