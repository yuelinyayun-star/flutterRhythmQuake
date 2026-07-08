import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../models/nied_scan_positions.dart';
import '../../models/nied_station_db.dart';

class LpgmStationReading {
  final String code;
  final String name;
  final LatLng coordinate;
  final double sva;
  final int lpgmClass;

  const LpgmStationReading({
    required this.code,
    required this.name,
    required this.coordinate,
    required this.sva,
    required this.lpgmClass,
  });
}

class LpgmSnapshot {
  final DateTime dataTime;
  final double maxSva;
  final int maxClass;
  final List<LpgmStationReading> topStations;

  /// Original RGB color at the max-SVA station position on the GIF image
  final int? maxRawRgb;

  const LpgmSnapshot({
    required this.dataTime,
    required this.maxSva,
    required this.maxClass,
    required this.topStations,
    this.maxRawRgb,
  });
}

class LpgmInputFrame {
  final DateTime dataTime;
  final Uint8List imageBytes;

  const LpgmInputFrame({required this.dataTime, required this.imageBytes});
}

class LpgmMonitorService {
  static final LpgmMonitorService _instance = LpgmMonitorService._internal();
  factory LpgmMonitorService() => _instance;
  LpgmMonitorService._internal();

  static const int _imgW = 352;
  static const int _imgH = 400;
  static const String _latestUrl =
      'https://smi.lmoniexp.bosai.go.jp/webservice/server/pros/latest.json';
  static const String legendImageUrl =
      'https://www.lmoni.bosai.go.jp/monitor/data/data/map_img/ScaleImg2/nied_abrspmx_s_w_scale.png';

  static const List<(int, int)> _sampleOffsets = [
    (0, 0),
    (-1, -1),
    (0, -1),
    (1, -1),
    (-1, 0),
    (1, 0),
    (-1, 1),
    (0, 1),
    (1, 1),
  ];

  bool _running = false;
  bool get isRunning => _running;
  bool _isTicking = false;

  Timer? _timer;
  String? _lastStamp;
  LpgmSnapshot? _latestSnapshot;
  LpgmInputFrame? _latestInputFrame;
  List<_LpgmPoint> _points = const [];
  final HttpClient _client = HttpClient()
    ..badCertificateCallback = ((X509Certificate cert, String host, int port) =>
        true)
    ..connectionTimeout = const Duration(seconds: 8);

  /// 多项式拟合系数（Approach G: 分段 H→pos + 正向最小距离红色区）
  /// 从 LPGM 色标图片采样后用最小二乘法拟合

  /// 非红色区 Seg1（H_norm > 65°）：H_norm/360 → position，deg=8
  static const _seg1HCoeffs = [
    -13.756892493387474,
    328.958029890138221,
    -3190.918598515499980,
    16806.689547560992651,
    -52826.731377120268007,
    101797.755763668290456,
    -117842.866795022258884,
    75168.634575526608387,
    -20285.598918820709514,
  ];

  /// 非红色区 Seg2（10° < H_norm ≤ 65°）：H_norm/360 → position，deg=8
  static const _seg2HCoeffs = [
    -0.810940738606774,
    175.473819552740480,
    -7693.684764532855297,
    178704.675070021330612,
    -2459875.003526113461703,
    20664799.061271760612726,
    -103876591.255096301436424,
    286634236.782177150249481,
    -333609828.117548406124115,
  ];

  /// 红色区正向 pos→H（pos 0.80~1.00），deg=7
  static const _fwdRedHCoeffs = [
    -317.606418568731158,
    1529.274225936303537,
    -2546.891986670196729,
    1120.213918891942285,
    1467.996471615477503,
    -1919.134431419236307,
    735.142609758312915,
    -68.988896493292302,
  ];

  /// 红色区正向 pos→V（pos 0.80~1.00），deg=6
  static const _fwdRedVCoeffs = [
    7624.402922573011892,
    -35905.804882620301214,
    58259.456480197964993,
    -25087.462649548655463,
    -29685.464062582039332,
    35384.701423115729995,
    -10589.307931537665354,
  ];

  final _snapshotController = StreamController<LpgmSnapshot>.broadcast();
  final _frameController = StreamController<LpgmInputFrame>.broadcast();
  Duration _interval = const Duration(seconds: 1);
  Stream<LpgmSnapshot> get snapshotStream => _snapshotController.stream;
  Stream<LpgmInputFrame> get inputFrameStream => _frameController.stream;
  LpgmSnapshot? get latestSnapshot => _latestSnapshot;
  LpgmInputFrame? get latestInputFrame => _latestInputFrame;

  Future<void> start({Duration interval = const Duration(seconds: 1)}) async {
    if (_running && _interval == interval) return;
    if (_running) {
      stop();
    }
    _interval = interval;
    _running = true;
    _buildPoints();
    _timer = Timer.periodic(_interval, (_) => _tick());
    unawaited(_tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    _isTicking = false;
    _lastStamp = null;
  }

  void dispose() {
    stop();
    _snapshotController.close();
    _frameController.close();
  }

  Future<void> refreshDebugFrame() async {
    if (!_frameController.hasListener) return;
    try {
      final stamp = await _fetchLatestStamp();
      if (stamp == null) return;
      final time = _parseStamp(stamp);
      if (time == null) return;
      final frame = await _fetchGif(_buildRtImageUrl(stamp));
      if (frame == null) return;
      _latestInputFrame = LpgmInputFrame(
        dataTime: time,
        imageBytes: frame.gifBytes,
      );
      _frameController.add(_latestInputFrame!);
    } catch (_) {
      // Debug-only frame refresh failure should not affect monitoring.
    }
  }

  Future<void> _tick() async {
    if (!_running || _isTicking) return;
    _isTicking = true;
    try {
      final stamp = await _fetchLatestStamp();
      if (stamp == null || stamp == _lastStamp) return;
      final time = _parseStamp(stamp);
      if (time == null) return;
      final frame = await _fetchGif(_buildRtImageUrl(stamp));
      if (frame == null) return;
      _lastStamp = stamp;
      if (_frameController.hasListener) {
        _latestInputFrame = LpgmInputFrame(
          dataTime: time,
          imageBytes: frame.gifBytes,
        );
        _frameController.add(_latestInputFrame!);
      } else {
        _latestInputFrame = null;
      }
      _parseFrame(frame.packedRgb, time);
    } catch (_) {
      // keep silent for now; caller can observe stream gaps.
    } finally {
      _isTicking = false;
    }
  }

  Future<String?> _fetchLatestStamp() async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final url = '$_latestUrl?_=$nowMs';
    final text = await _fetchText(url);
    if (text == null) return null;
    String latest;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return null;
      final value = decoded['latest_time'];
      if (value is! String) return null;
      latest = value.trim();
    } catch (_) {
      return null;
    }
    return latest.replaceAll('/', '').replaceAll(' ', '').replaceAll(':', '');
  }

  void _parseFrame(List<int> packedRgb, DateTime dataTime) {
    if (_points.isEmpty) return;

    final readings = <LpgmStationReading>[];
    double maxSva = 0.0;
    int? maxRawRgb;

    for (final p in _points) {
      final sva = _sampleSvaAt(packedRgb, p.x, p.y);
      if (sva == null || sva <= 0) continue;
      final lpClass = lpgmClassFromSva(sva);
      readings.add(
        LpgmStationReading(
          code: p.code,
          name: p.name,
          coordinate: p.coordinate,
          sva: sva,
          lpgmClass: lpClass,
        ),
      );
      if (sva > maxSva) {
        maxSva = sva;
        // Record the raw RGB at the center pixel of the max-SVA station
        if (p.x >= 0 && p.x < _imgW && p.y >= 0 && p.y < _imgH) {
          maxRawRgb = packedRgb[p.y * _imgW + p.x];
        }
      }
    }

    if (readings.isEmpty) return;
    readings.sort((a, b) => b.sva.compareTo(a.sva));
    final maxClass = lpgmClassFromSva(maxSva);
    final top = readings.take(5).toList(growable: false);
    _snapshotController.add(
      _latestSnapshot = LpgmSnapshot(
        dataTime: dataTime,
        maxSva: maxSva,
        maxClass: maxClass,
        topStations: top,
        maxRawRgb: maxRawRgb,
      ),
    );
  }

  double? _sampleSvaAt(List<int> packedRgb, int x, int y) {
    if (x < 0 || x >= _imgW || y < 0 || y >= _imgH) return null;

    // 先对 3x3 区域取平均 RGB（GIF 也是调色板量化+抖动的）
    int sumR = 0, sumG = 0, sumB = 0, count = 0;
    for (final (dx, dy) in _sampleOffsets) {
      final px = x + dx;
      final py = y + dy;
      if (px < 0 || px >= _imgW || py < 0 || py >= _imgH) continue;
      final rgb = packedRgb[py * _imgW + px];
      final r = (rgb >> 16) & 0xFF;
      final g = (rgb >> 8) & 0xFF;
      final b = rgb & 0xFF;
      sumR += r;
      sumG += g;
      sumB += b;
      count++;
    }
    if (count == 0) return null;
    final avgR = sumR ~/ count;
    final avgG = sumG ~/ count;
    final avgB = sumB ~/ count;

    return _rgbToSva(avgR, avgG, avgB);
  }

  double? _rgbToSva(int r, int g, int b) {
    // 使用分段多项式拟合（Approach G）
    final hsv = _rgbToHsv(r, g, b);
    final s = hsv.$2;
    final v = hsv.$3;

    // 暗色区域（低饱和度+低亮度）→ 超量程或无数据
    if (s <= 0.15 && v <= 0.25) {
      // 灰色区域对应色标顶部（SVA 超量程）
      if (v > 0.05) return 1000.0;
      return null;
    }
    // 极低亮度 → 无数据
    if (v <= 0.05) return null;

    final hDeg = hsv.$1;
    // 归一化 H：将 H > 350° 映射到 H - 360°，使红色区域 H 在 0° 附近
    final hNorm = hDeg > 350 ? hDeg - 360 : hDeg;

    double calcPos;
    if (hNorm > 65) {
      // 非红色区 Seg1（H > 65°）：H→position 多项式
      calcPos = _polyEval(_seg1HCoeffs, hNorm / 360.0).clamp(0.0, 1.0);
    } else if (hNorm > 10) {
      // 非红色区 Seg2（10° < H ≤ 65°）：H→position 多项式
      calcPos = _polyEval(_seg2HCoeffs, hNorm / 360.0).clamp(0.0, 1.0);
    } else {
      // 红色区（H ≤ 10°）：正向 pos→H + pos→V 最小距离搜索
      calcPos = _positionFromHVRed(hNorm, v);
    }

    return _svaFromPosition(calcPos);
  }

  /// 红色区：用正向 pos→H + pos→V 多项式做最小距离搜索
  /// 在 position 空间 [0.80, 1.00] 中找到最接近输入 (hNorm, v) 的位置
  static double _positionFromHVRed(double hNorm, double v) {
    final targetH = hNorm / 360.0;
    final targetV = v;

    double distAt(double pos) {
      final predH = _polyEval(_fwdRedHCoeffs, pos);
      final predV = _polyEval(_fwdRedVCoeffs, pos);
      final dh = (predH - targetH) * 3.0; // H 权重 3x
      final dv = predV - targetV;
      return dh * dh + dv * dv;
    }

    // 网格搜索初始估计
    double bestPos = 0.80;
    double bestDist = double.infinity;
    const gridN = 40; // 精度足够，减少计算量
    for (int i = (gridN * 0.80).round(); i <= gridN; i++) {
      final p = i / gridN;
      final d = distAt(p);
      if (d < bestDist) {
        bestDist = d;
        bestPos = p;
      }
    }

    // 黄金分割搜索精化
    double lo = (bestPos - 0.05).clamp(0.80, 1.0);
    double hi = (bestPos + 0.05).clamp(0.80, 1.0);
    const phi = 0.618033988749895;
    double a = lo, b = hi;
    double c = b - phi * (b - a);
    double d = a + phi * (b - a);
    for (int iter = 0; iter < 30; iter++) {
      if (distAt(c) < distAt(d)) {
        b = d;
        d = c;
        c = b - phi * (b - a);
      } else {
        a = c;
        c = d;
        d = a + phi * (b - a);
      }
    }
    return ((a + b) / 2).clamp(0.80, 1.0);
  }

  /// 多项式求值：y = c[0] + c[1]*x + c[2]*x^2 + ...
  static double _polyEval(List<double> coeffs, double x) {
    double result = 0;
    for (int i = coeffs.length - 1; i >= 0; i--) {
      result = result * x + coeffs[i];
    }
    return result;
  }

  /// 从 position (0~1) 计算 SVA
  ///
  /// LPGM 色标使用 1-2-5 工程刻度，13个标定点等距排列，
  /// 但数值增长不是对数均匀的，所以不能用简单的 10^(6p-3) 公式。
  /// 在相邻标定点之间做对数线性插值。
  static double _svaFromPosition(double p) {
    final clamped = p.clamp(0.0, 1.0);
    final n = _svaScaleValues.length; // 13
    final idx = clamped * (n - 1);
    final i = idx.toInt();
    if (i >= n - 1) return _svaScaleValues.last;
    final t = idx - i;
    // 对数线性插值
    final logA = _log10SvaScale[i];
    final logB = _log10SvaScale[i + 1];
    final logSva = logA + (logB - logA) * t;
    return math.pow(10.0, logSva).toDouble();
  }

  (double, double, double) _rgbToHsv(int r, int g, int b) {
    final rn = r / 255.0;
    final gn = g / 255.0;
    final bn = b / 255.0;
    final cMax = math.max(rn, math.max(gn, bn));
    final cMin = math.min(rn, math.min(gn, bn));
    final delta = cMax - cMin;
    double h = 0.0;
    if (delta != 0) {
      if (cMax == rn) {
        h = 60 * (((gn - bn) / delta) % 6);
      } else if (cMax == gn) {
        h = 60 * (((bn - rn) / delta) + 2);
      } else {
        h = 60 * (((rn - gn) / delta) + 4);
      }
    }
    if (h < 0) h += 360;
    final s = cMax == 0 ? 0.0 : delta / cMax;
    return (h, s, cMax);
  }

  DateTime? _parseStamp(String stamp) {
    if (stamp.length != 14) return null;
    try {
      final y = int.parse(stamp.substring(0, 4));
      final m = int.parse(stamp.substring(4, 6));
      final d = int.parse(stamp.substring(6, 8));
      final hh = int.parse(stamp.substring(8, 10));
      final mm = int.parse(stamp.substring(10, 12));
      final ss = int.parse(stamp.substring(12, 14));
      return DateTime(y, m, d, hh, mm, ss);
    } catch (_) {
      return null;
    }
  }

  String _buildRtImageUrl(String stamp) {
    final ymd = stamp.substring(0, 8);
    return 'https://www.lmoni.bosai.go.jp/monitor/data/data/map_img/RealTimeImg/abrspmx_s/$ymd/$stamp.abrspmx_s.gif';
  }

  static String rtImageUrlFromTime(DateTime dataTime) {
    String two(int v) => v.toString().padLeft(2, '0');
    final y = dataTime.year.toString().padLeft(4, '0');
    final mo = two(dataTime.month);
    final d = two(dataTime.day);
    final h = two(dataTime.hour);
    final mi = two(dataTime.minute);
    final s = two(dataTime.second);
    final ymd = '$y$mo$d';
    final stamp = '$y$mo$d$h$mi$s';
    return 'https://www.lmoni.bosai.go.jp/monitor/data/data/map_img/RealTimeImg/abrspmx_s/$ymd/$stamp.abrspmx_s.gif';
  }

  Future<String?> _fetchText(String url) async {
    try {
      final req = await _client.getUrl(Uri.parse(url));
      req.headers.set('Referer', 'https://www.lmoni.bosai.go.jp/monitor/');
      req.headers.set('User-Agent', _ua);
      req.headers.set('Cache-Control', 'no-cache');
      req.headers.set('Pragma', 'no-cache');
      final res = await req.close();
      if (res.statusCode != 200) return null;
      return await utf8.decoder.bind(res).join();
    } catch (_) {
      return null;
    }
  }

  Future<_LpgmDecodedFrame?> _fetchGif(String url) async {
    final decoded = await _fetchGifOrPng(url);
    if (decoded == null) return null;
    return _LpgmDecodedFrame(packedRgb: decoded.$1, gifBytes: decoded.$4);
  }

  Future<(List<int>, int, int, Uint8List)?> _fetchGifOrPng(String url) async {
    try {
      final req = await _client.getUrl(Uri.parse(url));
      req.headers.set('Referer', 'https://www.lmoni.bosai.go.jp/monitor/');
      req.headers.set('User-Agent', _ua);
      req.headers.set('Cache-Control', 'no-cache');
      req.headers.set('Pragma', 'no-cache');
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final bytes = await consolidateHttpClientResponseBytes(res);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        img.dispose();
        codec.dispose();
        return null;
      }
      final out = List<int>.filled(img.width * img.height, 0);
      for (int i = 0; i < out.length; i++) {
        final off = i * 4;
        final r = byteData.getUint8(off);
        final g = byteData.getUint8(off + 1);
        final b = byteData.getUint8(off + 2);
        out[i] = (r << 16) | (g << 8) | b;
      }
      final w = img.width;
      final h = img.height;
      img.dispose();
      codec.dispose();
      return (out, w, h, Uint8List.fromList(bytes));
    } catch (_) {
      return null;
    }
  }

  void _buildPoints() {
    final db = NiedStationDb.stations;
    final out = <_LpgmPoint>[];
    for (final s in db) {
      final code = (s['code'] as String?) ?? '';
      if (code.isEmpty) continue;
      final pos = NiedScanPositions.positions[code];
      if (pos == null) continue;
      final lat = (s['lat'] as num).toDouble();
      final lng = (s['lng'] as num).toDouble();
      out.add(
        _LpgmPoint(
          code: code,
          name: (s['name'] as String?) ?? code,
          coordinate: LatLng(lat, lng),
          x: pos[0],
          y: pos[1],
        ),
      );
    }
    _points = out;
  }

  static int lpgmClassFromSva(double sva) {
    if (sva >= 100.0) return 4;
    if (sva >= 50.0) return 3;
    if (sva >= 15.0) return 2;
    if (sva >= 5.0) return 1;
    return 0;
  }

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
}

/// LPGM 色标 SVA 值（从下到上，等距排列的 1-2-5 工程刻度）
const List<double> _svaScaleValues = [
  0.001,
  0.01,
  0.1,
  1.0,
  2.0,
  5.0,
  10.0,
  20.0,
  50.0,
  100.0,
  200.0,
  500.0,
  1000.0,
];

/// 预计算的 log10(SVA) 值，用于对数线性插值
const List<double> _log10SvaScale = [
  -3.0,
  -2.0,
  -1.0,
  0.0,
  0.30103,
  0.69897,
  1.0,
  1.30103,
  1.69897,
  2.0,
  2.30103,
  2.69897,
  3.0,
];

class _LpgmPoint {
  final String code;
  final String name;
  final LatLng coordinate;
  final int x;
  final int y;
  const _LpgmPoint({
    required this.code,
    required this.name,
    required this.coordinate,
    required this.x,
    required this.y,
  });
}

class _LpgmDecodedFrame {
  final List<int> packedRgb;
  final Uint8List gifBytes;
  const _LpgmDecodedFrame({required this.packedRgb, required this.gifBytes});
}
