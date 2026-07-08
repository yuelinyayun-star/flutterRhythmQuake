import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sources/shake_detection_service.dart';

/// NIED 回放日志记录器
///
/// 开启后在 Debug 页会自动记录全链路日志到文件，
/// 供离线分析：GIF URL → 解析 → 检测 → 推算震中
class NiedReplayLogger {
  static const autoSaveOnSourceTriggerPreferenceKey =
      'nied_replay_logger_auto_save_on_source_trigger';

  static final NiedReplayLogger instance = NiedReplayLogger._();
  NiedReplayLogger._();

  bool _enabled = false;
  bool _autoSaveOnSourceTrigger = false;
  bool _writeToDisk = true;
  final List<Map<String, dynamic>> _frames = [];
  final List<_PendingGifCapture> _pendingGifCaptures = [];
  final List<Map<String, Object?>> _capturedGifs = [];
  final Set<String> _capturedGifKeys = {};
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  String? _logPath;
  String? _captureDirPath;
  DateTime? _sessionStart;

  bool get isEnabled => _enabled;
  bool get autoSaveOnSourceTrigger => _autoSaveOnSourceTrigger;

  void loadPreferencesFrom(SharedPreferences prefs) {
    final next = prefs.getBool(autoSaveOnSourceTriggerPreferenceKey) ?? false;
    if (next == _autoSaveOnSourceTrigger) return;
    _autoSaveOnSourceTrigger = next;
    _notifyChanged();
  }

  Future<void> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    loadPreferencesFrom(prefs);
  }

  Future<void> setAutoSaveOnSourceTrigger(bool enabled) async {
    if (enabled == _autoSaveOnSourceTrigger) return;
    _autoSaveOnSourceTrigger = enabled;
    _notifyChanged();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(autoSaveOnSourceTriggerPreferenceKey, enabled);
  }

  void setEnabled(bool v) {
    if (v == _enabled) return;
    _enabled = v;
    if (v) {
      _frames.clear();
      _capturedGifs.clear();
      _capturedGifKeys.clear();
      _sessionStart = DateTime.now();
      _logPath = null;
      _captureDirPath = null;
      _lastAutoSaveCount = 0;
      _lastAutoSaveAt = null;
      _flushPendingGifCaptures();
      debugPrint('[ReplayLogger] ENABLED — session started');
    } else {
      _flush();
      debugPrint('[ReplayLogger] DISABLED — saved to $_logPath');
    }
    _notifyChanged();
  }

  /// 自动保存开关启用后，生产推算真正触发时从这里启动记录。
  void startForSourceTrigger({
    required String? eventId,
    required DateTime observedAt,
    required String stageName,
    Map<String, Object?> metadata = const {},
  }) {
    if (!_autoSaveOnSourceTrigger) return;
    if (!_enabled) {
      setEnabled(true);
    }
    _frames.add({
      'type': 'source_trigger',
      'event_id': eventId,
      'observed_at': observedAt.toIso8601String(),
      'stage': stageName,
      'metadata': metadata,
    });
    _flushPendingGifCaptures();
    _autoSave();
  }

  /// 缓存/保存实时抓取的 GIF 原始字节。
  ///
  /// logger 未启用时只保留最近少量帧；source trigger 自动开启后会立即落盘，
  /// 避免漏掉触发帧前后的 GIF。
  void recordGifBytes({
    required DateTime jstTime,
    required String gifUrl,
    required Uint8List bytes,
    String layerKey = 'jma_s',
  }) {
    final pending = _PendingGifCapture(
      jstTime: jstTime,
      gifUrl: gifUrl,
      bytes: Uint8List.fromList(bytes),
      layerKey: layerKey,
    );
    _pendingGifCaptures.add(pending);
    while (_pendingGifCaptures.length > 30) {
      _pendingGifCaptures.removeAt(0);
    }
    if (_enabled) {
      _writeGifCaptureSync(pending);
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
      'station_levels': ?stationLevels,
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
          .map(
            (s) => {
              'code': s.code,
              'pref': s.prefecture,
              'level': s.level,
              'shindo': s.jmaShindo,
              'state': s.detectState,
              'reason': s.detectReason,
            },
          )
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
  DateTime? _lastAutoSaveAt;
  void _autoSave() {
    if (!_enabled || !_writeToDisk) return;
    final now = DateTime.now();
    final enoughRecords = _frames.length - _lastAutoSaveCount >= 80;
    final enoughTime =
        _lastAutoSaveAt == null ||
        now.difference(_lastAutoSaveAt!) >= const Duration(seconds: 15);
    if (!enoughRecords || !enoughTime) return;
    _lastAutoSaveCount = _frames.length;
    _lastAutoSaveAt = now;
    _writeSync();
  }

  /// 立即同步保存当前会话。
  void saveSync() {
    _writeSync();
    _notifyChanged();
  }

  /// 同步写入 (可从任何上下文调用)
  void _writeSync() {
    if (!_enabled || _frames.isEmpty) return;
    if (!_writeToDisk) return;
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
        'detection_count': _frames
            .where((f) => f['type'] == 'detection')
            .length,
        'epicenter_count': _frames
            .where((f) => f['type'] == 'epicenter')
            .length,
        'gif_capture_count': _capturedGifs.length,
        'capture_directory': _captureDirPath,
        'captured_gifs': _capturedGifs,
        'frames': _frames,
      };
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(payload),
      );
      _logPath = file.path;
      _writeCapturePackageMetadataSync(payload);
      _notifyChanged();
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
  String? get captureDirPath => _captureDirPath;

  void _flushPendingGifCaptures() {
    if (!_enabled) return;
    for (final pending in _pendingGifCaptures) {
      _writeGifCaptureSync(pending);
    }
  }

  void _writeGifCaptureSync(_PendingGifCapture capture) {
    if (!_writeToDisk) return;
    final captureDir = _ensureCaptureDirSync();
    if (captureDir == null) return;
    final fileName = _gifFileName(capture);
    final relativePath = 'raw/${capture.layerKey}/$fileName';
    final key = '${capture.layerKey}/$fileName';
    if (_capturedGifKeys.contains(key)) return;
    try {
      final layerDir = Directory('${captureDir.path}/raw/${capture.layerKey}');
      if (!layerDir.existsSync()) layerDir.createSync(recursive: true);
      final file = File('${layerDir.path}/$fileName');
      file.writeAsBytesSync(capture.bytes, flush: false);
      _capturedGifKeys.add(key);
      _capturedGifs.add({
        'jst': capture.jstTime.toIso8601String(),
        'layer': capture.layerKey,
        'url': capture.gifUrl,
        'path': relativePath,
        'bytes': capture.bytes.length,
      });
    } catch (_) {
      // Keep the realtime path quiet; replay JSON still records the URL.
    }
  }

  Directory? _ensureCaptureDirSync() {
    if (_captureDirPath != null) return Directory(_captureDirPath!);
    final sessionStart = _sessionStart;
    if (sessionStart == null) return null;
    final home = Platform.environment['USERPROFILE'] ?? '.';
    final ts = _sessionTimestamp(sessionStart);
    final dir = Directory('$home/Desktop/nied_capture_$ts');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _captureDirPath = dir.path;
    return dir;
  }

  String _gifFileName(_PendingGifCapture capture) {
    final fromUrl = Uri.tryParse(capture.gifUrl)?.pathSegments.last;
    if (fromUrl != null && fromUrl.toLowerCase().endsWith('.gif')) {
      return fromUrl;
    }
    final stamp = _compactTimestamp(capture.jstTime);
    return '$stamp.${capture.layerKey}.gif';
  }

  void _writeCapturePackageMetadataSync(Map<String, Object?> replayPayload) {
    final captureDirPath = _captureDirPath;
    if (captureDirPath == null) return;
    try {
      File('$captureDirPath/nied_replay.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(replayPayload),
      );
      File('$captureDirPath/capture_manifest.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'schemaVersion': 'nied_capture_v1',
          'createdAt': DateTime.now().toIso8601String(),
          'sessionStart': _sessionStart?.toIso8601String(),
          'sourceReplayPath': _logPath,
          'gifCount': _capturedGifs.length,
          'frames': _capturedGifs,
        }),
      );
    } catch (_) {
      // best-effort capture package metadata
    }
  }

  String _sessionTimestamp(DateTime value) =>
      '${_compactDate(value)}_'
      '${value.hour.toString().padLeft(2, '0')}'
      '${value.minute.toString().padLeft(2, '0')}'
      '${value.second.toString().padLeft(2, '0')}';

  String _compactTimestamp(DateTime value) =>
      '${_compactDate(value)}'
      '${value.hour.toString().padLeft(2, '0')}'
      '${value.minute.toString().padLeft(2, '0')}'
      '${value.second.toString().padLeft(2, '0')}';

  String _compactDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}';

  void _notifyChanged() {
    revision.value++;
  }

  @visibleForTesting
  void resetForTest({
    bool autoSaveOnSourceTrigger = false,
    bool writeToDisk = false,
  }) {
    _enabled = false;
    _autoSaveOnSourceTrigger = autoSaveOnSourceTrigger;
    _writeToDisk = writeToDisk;
    _frames.clear();
    _pendingGifCaptures.clear();
    _capturedGifs.clear();
    _capturedGifKeys.clear();
    _logPath = null;
    _captureDirPath = null;
    _sessionStart = null;
    _lastAutoSaveCount = 0;
    _notifyChanged();
  }

  @visibleForTesting
  List<Map<String, dynamic>> get debugRecords => List.unmodifiable(_frames);
}

class _PendingGifCapture {
  final DateTime jstTime;
  final String gifUrl;
  final Uint8List bytes;
  final String layerKey;

  const _PendingGifCapture({
    required this.jstTime,
    required this.gifUrl,
    required this.bytes,
    required this.layerKey,
  });
}
