import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image_lib;
import 'package:latlong2/latlong.dart';
import 'base_source.dart';
import '../../models/source_status.dart';
import '../debug/local_inject_decoder.dart';
import '../../models/weather_alarm.dart';
import 'nied_monitor.dart';
import '../../models/nied_calibration.dart';
import '../../core/source_estimation/kotoho7_js_receiver_bridge.dart';
import 'shake_detection_service.dart';
import 'jp_shindo_scale.dart';
import 'lmoni_image_service.dart';

/// 模拟输入服务
///
/// 该类提供手动注入地震数据的功能。
/// 用于测试和调试，支持多种数据格式的解析。
///
/// 主要功能：
/// - 解析JSON/JS格式的地震数据
/// - 支持Wolfx、P2P、FAN等多种数据格式
/// - 自动识别数据格式类型
/// - 提取嵌套的JSON数据块
///
/// 支持的数据格式：
/// - Wolfx格式: JMA/CENC/CWA等预警格式
/// - P2P格式: P2PQuake地震信息格式
/// - FAN格式: FanStudio聚合数据格式
class MockInputService extends BaseSourceService {
  final _weatherAlarms = StreamController<WeatherAlarm>.broadcast();
  Stream<WeatherAlarm> get onWeatherAlarm => _weatherAlarms.stream;

  @override
  void dispose() {
    _weatherAlarms.close();
    super.dispose();
  }

  bool _niedGifInjectionRunning = false;
  bool _niedGifInjectionCancelRequested = false;

  bool get isNiedGifInjectionRunning => _niedGifInjectionRunning;

  /// Request cooperative cancel of an in-flight [injectFromNiedGifPath].
  void stopNiedGifInjection() {
    if (!_niedGifInjectionRunning) return;
    _niedGifInjectionCancelRequested = true;
    debugPrint('[NIED GIF Inject] cancel requested');
  }

  @override
  String get name => localInjectApiName;

  @override
  bool get autoStart => false;

  @override
  void connect() {
    onStatusChanged?.call(SourceStatus.connected);
  }

  @override
  void disconnect() {
    onStatusChanged?.call(SourceStatus.disconnected);
  }

  /// 从原始字符串注入地震数据
  ///
  /// 支持多种输入格式：
  /// - 纯JSON字符串
  /// - JavaScript对象字面量
  /// - Markdown代码块包裹的JSON
  ///
  /// [raw] 原始输入字符串
  /// 返回成功解析的地震事件数量
  int injectFromJs(String raw, {String format = 'auto', String? source}) {
    final normalized = _extractJsonBlob(raw);
    if (normalized == null || normalized.trim().isEmpty) {
      throw FormatException('未识别到可解析的 JSON/JS 数据块');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(normalized);
    } catch (_) {
      final converted = _tryConvertJsObject(normalized);
      decoded = jsonDecode(converted);
    }

    return _publishDecoded(decoded, format: format, source: source);
  }

  int injectJson(String raw, {String format = 'auto', String? source}) =>
      _publishDecoded(jsonDecode(raw), format: format, source: source);

  int _publishDecoded(
    Object? decoded, {
    required String format,
    String? source,
  }) {
    final batch = LocalInjectDecoder.decode(
      decoded,
      format: format,
      source: source,
    );
    // Parse the complete batch before publishing anything.
    for (final event in batch.events) {
      emitUnified(event);
    }
    for (final event in batch.tsunamis) {
      emitTsunami(event);
    }
    for (final event in batch.weatherAlarms) {
      _weatherAlarms.add(event);
    }
    return batch.count;
  }

  String? _extractJsonBlob(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;

    text = text.replaceAllMapped(
      RegExp(r'^```[a-zA-Z0-9_-]*\s*|\s*```$'),
      (_) => '',
    );

    if ((text.startsWith('{') && text.endsWith('}')) ||
        (text.startsWith('[') && text.endsWith(']'))) {
      return text;
    }

    final startObj = text.indexOf('{');
    final startArr = text.indexOf('[');
    int start = -1;
    if (startObj >= 0 && startArr >= 0) {
      start = startObj < startArr ? startObj : startArr;
    } else if (startObj >= 0) {
      start = startObj;
    } else if (startArr >= 0) {
      start = startArr;
    }
    if (start < 0) return null;

    final open = text[start];
    final close = open == '{' ? '}' : ']';
    int depth = 0;
    bool inString = false;
    String quote = '"';
    bool escape = false;

    for (int i = start; i < text.length; i++) {
      final ch = text[i];
      if (inString) {
        if (escape) {
          escape = false;
          continue;
        }
        if (ch == r'\') {
          escape = true;
          continue;
        }
        if (ch == quote) {
          inString = false;
        }
        continue;
      }
      if (ch == '"' || ch == "'") {
        inString = true;
        quote = ch;
        continue;
      }
      if (ch == open) depth++;
      if (ch == close) {
        depth--;
        if (depth == 0) {
          return text.substring(start, i + 1);
        }
      }
    }
    return null;
  }

  /// 尝试将JavaScript对象字面量转换为JSON
  ///
  /// 处理JS特有的语法：
  /// - 无引号的属性名
  /// - 单引号字符串
  /// - 尾随逗号
  String _tryConvertJsObject(String src) {
    var s = src.trim();
    s = s.replaceAll(RegExp(r'^\s*(const|let|var)\s+\w+\s*=\s*'), '');
    s = s.replaceAll(RegExp(r';\s*$'), '');
    s = s.replaceAllMapped(RegExp(r'([{\[,]\s*)([A-Za-z_]\w*)(\s*:)'), (m) {
      return '${m[1]}"${m[2]}"${m[3]}';
    });
    s = s.replaceAll("'", '"');
    s = s.replaceAllMapped(RegExp(r',\s*([}\]])'), (m) => m[1]!);
    return s;
  }

  /// 从 K-NET ASCII zip 文件注入测站数据
  ///
  /// 解析 zip 中的 .NS/.EW/.UD 文件，提取各站 PGA，
  /// 转换为 scratch level，灌入 ShakeDetectionService。
  ///
  /// [zipPath] K-NET ASCII zip 文件路径
  /// 返回注入的测站数量
  int injectFromKnetZip(String zipPath) {
    final file = File(zipPath);
    if (!file.existsSync()) {
      throw FormatException('文件不存在: $zipPath');
    }

    final bytes = file.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    final stations = <String, _KnetStationAcc>{};

    for (final entry in archive.files) {
      if (entry.isFile != true) continue;
      final name = entry.name;
      if (!name.endsWith('.NS') &&
          !name.endsWith('.EW') &&
          !name.endsWith('.UD')) {
        continue;
      }

      final comp = name.substring(name.length - 2);
      final fname = name.split('/').last;
      final codeIdx = fname.indexOf('2606');
      if (codeIdx < 0) continue;
      final code = fname.substring(0, codeIdx);

      final content = utf8.decode(entry.content as List<int>);
      final lines = content.split('\n');
      double? pga;
      double? lat;
      double? lng;

      for (final line in lines) {
        if (line.startsWith('Max. Acc. (gal)')) {
          final m = RegExp(r'([\d.]+)\s*$').firstMatch(line);
          if (m != null) pga = double.tryParse(m.group(1)!);
        } else if (line.startsWith('Station Lat.')) {
          final m = RegExp(r'([\d.]+)\s*$').firstMatch(line);
          if (m != null) lat = double.tryParse(m.group(1)!);
        } else if (line.startsWith('Station Long.')) {
          final m = RegExp(r'([\d.]+)\s*$').firstMatch(line);
          if (m != null) lng = double.tryParse(m.group(1)!);
        }
      }

      if (pga == null || lat == null || lng == null) continue;
      final l = lat;
      final ln = lng;
      stations.putIfAbsent(code, () => _KnetStationAcc(code, l, ln));
      final s = stations[code]!;
      if (pga > s.maxPga) s.maxPga = pga;
      s.comps[comp] = pga;
    }

    if (stations.isEmpty) {
      throw FormatException('未从 zip 中找到有效的 K-NET 测站数据');
    }

    // Convert to NiedStation list
    final niedStations = <NiedStation>[];
    double avgLat = 0, avgLng = 0;

    for (final ks in stations.values) {
      // PGA → shindo
      final pga = ks.maxPga;
      double shindo;
      if (pga > 0.001) {
        shindo = 2.68 + 1.72 * _log10(pga);
      } else {
        shindo = -3.0;
      }
      final level = JpShindoScale.kanameishiLevelFromShindo(shindo);
      if (level < 0) continue;

      final ns = NiedStation(
        id: ks.code.hashCode,
        code: ks.code,
        name: ks.code,
        coordinate: LatLng(ks.lat, ks.lng),
        network: 'K-NET',
        prefecture: _guessPref(ks.lat, ks.lng),
        expireSeconds: 5,
        level: level,
      );
      ns.recentLevel = List.filled(5, level);
      ns.lastUpdate = DateTime.now();
      ns.calibrationFactor =
          NiedCalibration.factors[ks.code] ?? NiedCalibration.defaultFactor;
      ns.thresholdCode =
          NiedCalibration.thresholdCodes[ks.code] ??
          NiedCalibration.defaultThresholdCode;
      niedStations.add(ns);
      avgLat += ks.lat;
      avgLng += ks.lng;
    }

    avgLat /= niedStations.length;
    avgLng /= niedStations.length;

    // Feed to ShakeDetectionService
    final detection = ShakeDetectionService();
    detection.setSensitivity(2);
    detection.setStations(niedStations);

    // Broadcast to map via LmoniImageService stream
    LmoniImageService().broadcastStations(niedStations);

    // Run multiple frames for detection
    for (int f = 0; f < 3; f++) {
      for (final s in niedStations) {
        s.lastUpdate = DateTime.now();
      }
      detection.processUpdate();
    }

    debugPrint(
      '[KNET] Injected ${niedStations.length} stations'
      ' (${stations.length} raw) from $zipPath'
      ', avg epicenter=(${avgLat.toStringAsFixed(3)}, ${avgLng.toStringAsFixed(3)})',
    );

    return niedStations.length;
  }

  /// 直接从 NIED GIF 文件或目录注入。
  ///
  /// 目录输入会优先选择 `*.jma_s.gif`，避免把井下/物理量图层当成实时震度图。
  /// 每张 GIF 对应一个秒级时刻，直接进入 `LmoniImageService.processPixels()`，后续测站更新、检测、
  /// 震源推算都走应用现有实时链路。
  Future<int> injectFromNiedGifPath(String path) async {
    if (_niedGifInjectionRunning) {
      throw StateError('NIED GIF 注入正在进行中');
    }
    final target = FileSystemEntity.typeSync(path);
    if (target == FileSystemEntityType.notFound) {
      throw FormatException('路径不存在: $path');
    }

    final files = target == FileSystemEntityType.directory
        ? _niedGifFilesInDirectory(Directory(path))
        : [File(path)];
    if (files.isEmpty) {
      throw FormatException('未找到可注入的 NIED GIF: $path');
    }

    _niedGifInjectionRunning = true;
    _niedGifInjectionCancelRequested = false;
    final imageService = LmoniImageService()..start();
    var injected = 0;
    DateTime? fallbackTime;
    DateTime? firstDataTime;
    final playbackClock = Stopwatch()..start();
    try {
      for (final file in files) {
        if (_niedGifInjectionCancelRequested) {
          debugPrint(
            '[NIED GIF Inject] cancelled after $injected / ${files.length}',
          );
          break;
        }
        final dataTime =
            _niedGifTimestampFromName(file) ??
            (fallbackTime = (fallbackTime ?? DateTime.now()).add(
              const Duration(seconds: 1),
            ));
        firstDataTime ??= dataTime;
        final targetElapsed = dataTime.difference(firstDataTime);
        if (targetElapsed > Duration.zero) {
          final remaining = targetElapsed - playbackClock.elapsed;
          if (remaining > Duration.zero) {
            await _delayUnlessNiedGifCancelled(remaining);
            if (_niedGifInjectionCancelRequested) {
              debugPrint(
                '[NIED GIF Inject] cancelled after $injected / ${files.length}',
              );
              break;
            }
          }
        }

        final bytes = await file.readAsBytes();
        // Decode off the UI isolate — 352x400 GIF decode on the main thread
        // stacks with wave/camera/station rebuilds and feels like hard jank.
        final packedRgb = await Isolate.run(
          () => _packedRgbFromGifBytes(bytes),
        );
        if (packedRgb == null) {
          debugPrint(
            '[NIED GIF Inject] skip ${file.path}: decode failed or bad size',
          );
          continue;
        }
        if (_niedGifInjectionCancelRequested) break;
        imageService.processPixels(
          packedRgb,
          surfaceGifBytes: bytes,
          dataTime: dataTime,
          receivedAt: DateTime.now(),
        );
        await _waitForNiedSourceBridgePlaybackBackpressure();
        injected++;
      }
    } finally {
      _niedGifInjectionRunning = false;
      _niedGifInjectionCancelRequested = false;
    }
    debugPrint('[NIED GIF Inject] Injected $injected GIF seconds from $path');
    return injected;
  }

  Future<void> _delayUnlessNiedGifCancelled(Duration duration) async {
    const slice = Duration(milliseconds: 50);
    var remaining = duration;
    while (remaining > Duration.zero) {
      if (_niedGifInjectionCancelRequested) return;
      final step = remaining > slice ? slice : remaining;
      await Future<void>.delayed(step);
      remaining -= step;
    }
  }

  Future<void> _waitForNiedSourceBridgePlaybackBackpressure() async {
    // StreamController.add() delivers the map listener on a later microtask.
    // Yield once so the NIED source-estimation driver can enqueue the JS frame
    // before we inspect bridge pressure.
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
          '[NIED GIF Inject] wait JS bridge '
          'pending=${status.pendingFrameCount} '
          'inFlight=${status.inFlightSessionCount}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  List<File> _niedGifFilesInDirectory(Directory directory) {
    if (!directory.existsSync()) return const [];
    final allGifFiles = directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.gif'))
        .toList(growable: false);
    final surfaceGifFiles = allGifFiles
        .where((file) => file.path.toLowerCase().endsWith('.jma_s.gif'))
        .toList(growable: false);
    final selected = surfaceGifFiles.isNotEmpty ? surfaceGifFiles : allGifFiles;
    return selected.toList(growable: false)..sort(_compareNiedGifFiles);
  }

  int _compareNiedGifFiles(File left, File right) {
    final leftTime = _niedGifTimestampFromName(left);
    final rightTime = _niedGifTimestampFromName(right);
    if (leftTime != null && rightTime != null) {
      final timeCompare = leftTime.compareTo(rightTime);
      if (timeCompare != 0) return timeCompare;
    } else if (leftTime != null) {
      return -1;
    } else if (rightTime != null) {
      return 1;
    }
    return left.path.compareTo(right.path);
  }

  DateTime? _niedGifTimestampFromName(File file) {
    final name = file.uri.pathSegments.isEmpty
        ? file.path
        : file.uri.pathSegments.last;
    final match = RegExp(r'(20\d{12})').firstMatch(name);
    if (match == null) return null;
    final stamp = match.group(1)!;
    return DateTime(
      int.parse(stamp.substring(0, 4)),
      int.parse(stamp.substring(4, 6)),
      int.parse(stamp.substring(6, 8)),
      int.parse(stamp.substring(8, 10)),
      int.parse(stamp.substring(10, 12)),
      int.parse(stamp.substring(12, 14)),
    );
  }

  double _log10(double x) => x <= 0 ? 0 : (math.log(x) / 2.302585092994046);

  String _guessPref(double lat, double lng) {
    const prefs = [
      (35.0, 139.5, '東京都'),
      (34.7, 135.5, '大阪府'),
      (35.2, 136.9, '愛知県'),
      (38.3, 140.9, '宮城県'),
      (43.1, 141.4, '北海道'),
      (37.9, 139.0, '新潟県'),
      (34.4, 132.5, '広島県'),
      (33.6, 130.4, '福岡県'),
      (36.6, 136.7, '石川県'),
      (36.4, 139.0, '群馬県'),
      (35.6, 140.1, '千葉県'),
      (37.5, 138.1, '新潟県'),
    ];
    double best = double.infinity;
    String bestPref = '日本';
    for (final (pLat, pLng, name) in prefs) {
      final d = (lat - pLat) * (lat - pLat) + (lng - pLng) * (lng - pLng);
      if (d < best) {
        best = d;
        bestPref = name;
      }
    }
    return bestPref;
  }
}

/// Decode NIED surface GIF off the UI isolate (must be top-level for [Isolate.run]).
/// Returns compact [Uint32List] (not boxed [List<int>]) to cut Dart heap peak.
Uint32List? _packedRgbFromGifBytes(Uint8List bytes) {
  final decoded = image_lib.decodeImage(bytes);
  if (decoded == null) return null;
  if (decoded.width != 352 || decoded.height != 400) return null;
  final pixels = Uint32List(decoded.width * decoded.height);
  var index = 0;
  for (var y = 0; y < decoded.height; y++) {
    for (var x = 0; x < decoded.width; x++) {
      final pixel = decoded.getPixel(x, y);
      pixels[index++] =
          (pixel.r.toInt() << 16) | (pixel.g.toInt() << 8) | pixel.b.toInt();
    }
  }
  return pixels;
}

/// K-NET 测站累计 PGA 数据
class _KnetStationAcc {
  final String code;
  final double lat;
  final double lng;
  double maxPga = 0;
  final Map<String, double> comps = {};

  _KnetStationAcc(this.code, this.lat, this.lng);
}
