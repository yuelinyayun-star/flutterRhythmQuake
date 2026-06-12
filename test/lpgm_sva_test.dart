import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

// ── NoneType1 的 color2position 多项式 ──

double color2position(double h, double s, double v) {
  // h, s, v 都是 0-1 范围
  if (v <= 0.1 || s <= 0.75) return 0.0;
  double p;
  if (h > 0.1476) {
    p = 280.31 * math.pow(h, 6) -
        916.05 * math.pow(h, 5) +
        1142.6 * math.pow(h, 4) -
        709.95 * math.pow(h, 3) +
        234.65 * math.pow(h, 2) -
        40.27 * h +
        3.2217;
  } else if (h > 0.001) {
    p = 151.4 * math.pow(h, 4) -
        49.32 * math.pow(h, 3) +
        6.753 * math.pow(h, 2) -
        2.481 * h +
        0.9033;
  } else {
    p = -0.005171 * math.pow(v, 2) - 0.3282 * v + 1.2236;
  }
  if (p < 0) p = 0;
  return p;
}

// ── position → SVA 转换 ──

// 方案1: NoneType1 的简单对数刻度 PGV 公式
double svaFromPositionSimple(double p) {
  return math.pow(10.0, 5 * p - 3).toDouble();
}

// 方案2: 1-2-5 工程刻度对数线性插值
const List<double> _svaScaleValues = [
  0.001, 0.01, 0.1, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0,
  1000.0,
];
const List<double> _log10SvaScale = [
  -3.0, -2.0, -1.0, 0.0, 0.30103, 0.69897, 1.0, 1.30103, 1.69897, 2.0,
  2.30103, 2.69897, 3.0,
];
double svaFromPosition125(double p) {
  final clamped = p.clamp(0.0, 1.0);
  final n = _svaScaleValues.length;
  final idx = clamped * (n - 1);
  final i = idx.toInt();
  if (i >= n - 1) return _svaScaleValues.last;
  final t = idx - i;
  final logA = _log10SvaScale[i];
  final logB = _log10SvaScale[i + 1];
  final logSva = logA + (logB - logA) * t;
  return math.pow(10.0, logSva).toDouble();
}

double positionFromSva125(double sva) {
  final logSva = math.log(sva) / math.ln10;
  for (int i = 0; i < _log10SvaScale.length - 1; i++) {
    if (logSva >= _log10SvaScale[i] && logSva <= _log10SvaScale[i + 1]) {
      final t = (logSva - _log10SvaScale[i]) /
          (_log10SvaScale[i + 1] - _log10SvaScale[i]);
      return (i + t) / (_svaScaleValues.length - 1);
    }
  }
  if (logSva <= _log10SvaScale.first) return 0.0;
  return 1.0;
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

void main() {
  test('LPGM vs NIED scale comparison', () async {
    final client = HttpClient();

    // 下载 LPGM 色标
    const lpgmUrl =
        'https://www.lmoni.bosai.go.jp/monitor/data/data/map_img/ScaleImg2/nied_abrspmx_s_w_scale.png';
    final req1 = await client.getUrl(Uri.parse(lpgmUrl));
    final resp1 = await req1.close();
    final builder1 = BytesBuilder();
    await for (final chunk in resp1) builder1.add(chunk);
    final lpgmBytes = builder1.toBytes();
    print('LPGM legend: ${lpgmBytes.length} bytes');

    // 下载 NIED 強震モニタ色标
    const niedUrl =
        'http://www.kmoni.bosai.go.jp/data/map_img/ScaleImg/nied_jma_s_w_scale.gif';
    final req2 = await client.getUrl(Uri.parse(niedUrl));
    final resp2 = await req2.close();
    final builder2 = BytesBuilder();
    await for (final chunk in resp2) builder2.add(chunk);
    final niedBytes = builder2.toBytes();
    print('NIED legend: ${niedBytes.length} bytes');
    client.close();

    // 解码 LPGM 色标
    final codec1 = await ui.instantiateImageCodec(lpgmBytes);
    final frame1 = await codec1.getNextFrame();
    final img1 = frame1.image;
    final w1 = img1.width, h1 = img1.height;
    final raw1 = (await img1.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    print('LPGM size: ${w1}x$h1');

    // 解码 NIED 色标
    final codec2 = await ui.instantiateImageCodec(niedBytes);
    final frame2 = await codec2.getNextFrame();
    final img2 = frame2.image;
    final w2 = img2.width, h2 = img2.height;
    final raw2 = (await img2.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    print('NIED size: ${w2}x$h2');

    // 找 LPGM 色标条
    int lpgmBarX = -1, lpgmBarCount = 0;
    for (int x = 200; x < w1; x++) {
      int c = 0;
      for (int y = 0; y < h1; y++) {
        final off = (y * w1 + x) * 4;
        if (raw1.getUint8(off) != 0 || raw1.getUint8(off+1) != 0 || raw1.getUint8(off+2) != 0) c++;
      }
      if (c > lpgmBarCount) { lpgmBarCount = c; lpgmBarX = x; }
    }
    int lpgmTop = h1, lpgmBottom = 0;
    for (int y = 0; y < h1; y++) {
      final off = (y * w1 + lpgmBarX) * 4;
      if (raw1.getUint8(off) != 0 || raw1.getUint8(off+1) != 0 || raw1.getUint8(off+2) != 0) {
        if (y < lpgmTop) lpgmTop = y;
        if (y > lpgmBottom) lpgmBottom = y;
      }
    }
    print('LPGM bar: x=$lpgmBarX, y=$lpgmTop~$lpgmBottom');

    // 找 NIED 色标条
    int niedBarX = -1, niedBarCount = 0;
    for (int x = 0; x < w2; x++) {
      int c = 0;
      for (int y = 0; y < h2; y++) {
        final off = (y * w2 + x) * 4;
        if (raw2.getUint8(off) != 0 || raw2.getUint8(off+1) != 0 || raw2.getUint8(off+2) != 0) c++;
      }
      if (c > niedBarCount) { niedBarCount = c; niedBarX = x; }
    }
    int niedTop = h2, niedBottom = 0;
    for (int y = 0; y < h2; y++) {
      final off = (y * w2 + niedBarX) * 4;
      if (raw2.getUint8(off) != 0 || raw2.getUint8(off+1) != 0 || raw2.getUint8(off+2) != 0) {
        if (y < niedTop) niedTop = y;
        if (y > niedBottom) niedBottom = y;
      }
    }
    print('NIED bar: x=$niedBarX, y=$niedTop~$niedBottom');

    // 采样两个色标条，取水平平均
    print('');
    print('═══════════════════════════════════════════════════════════════════════════');
    print('  两个色标条对比（position 0→1，每 0.05 采样）');
    print('═══════════════════════════════════════════════════════════════════════════');
    print(
      '${'pos'.padLeft(5)}  '
      '${'LPGM_R'.padLeft(7)} ${'LPGM_G'.padLeft(7)} ${'LPGM_B'.padLeft(7)}  '
      '${'LPGM_H°'.padLeft(7)}  '
      '${'NIED_R'.padLeft(7)} ${'NIED_G'.padLeft(7)} ${'NIED_B'.padLeft(7)}  '
      '${'NIED_H°'.padLeft(7)}  '
      '${'same?'.padLeft(5)}',
    );
    print('─' * 90);

    for (double p = 0.0; p <= 1.0; p += 0.05) {
      // LPGM
      final lpgmY = (lpgmBottom - p * (lpgmBottom - lpgmTop)).round().clamp(lpgmTop, lpgmBottom);
      int lSumR = 0, lSumG = 0, lSumB = 0, lCount = 0;
      for (int x = lpgmBarX - 5; x <= lpgmBarX + 5; x++) {
        if (x < 0 || x >= w1) continue;
        final off = (lpgmY * w1 + x) * 4;
        final r = raw1.getUint8(off), g = raw1.getUint8(off+1), b = raw1.getUint8(off+2);
        if (r == 0 && g == 0 && b == 0) continue;
        lSumR += r; lSumG += g; lSumB += b; lCount++;
      }
      final lr = lCount > 0 ? lSumR ~/ lCount : 0;
      final lg = lCount > 0 ? lSumG ~/ lCount : 0;
      final lb = lCount > 0 ? lSumB ~/ lCount : 0;
      final lHsv = _rgbToHsv(lr, lg, lb);

      // NIED
      final niedY = (niedBottom - p * (niedBottom - niedTop)).round().clamp(niedTop, niedBottom);
      int nSumR = 0, nSumG = 0, nSumB = 0, nCount = 0;
      for (int x = niedBarX - 5; x <= niedBarX + 5; x++) {
        if (x < 0 || x >= w2) continue;
        final off = (niedY * w2 + x) * 4;
        final r = raw2.getUint8(off), g = raw2.getUint8(off+1), b = raw2.getUint8(off+2);
        if (r == 0 && g == 0 && b == 0) continue;
        nSumR += r; nSumG += g; nSumB += b; nCount++;
      }
      final nr = nCount > 0 ? nSumR ~/ nCount : 0;
      final ng = nCount > 0 ? nSumG ~/ nCount : 0;
      final nb = nCount > 0 ? nSumB ~/ nCount : 0;
      final nHsv = _rgbToHsv(nr, ng, nb);

      final same = (lr == nr && lg == ng && lb == nb) ? 'YES' :
                   ((lr - nr).abs() <= 10 && (lg - ng).abs() <= 10 && (lb - nb).abs() <= 10) ? '~' : 'NO';

      print(
        '${p.toStringAsFixed(2).padLeft(5)}  '
        '${lr.toString().padLeft(7)} ${lg.toString().padLeft(7)} ${lb.toString().padLeft(7)}  '
        '${lHsv.$1.toStringAsFixed(0).padLeft(7)}  '
        '${nr.toString().padLeft(7)} ${ng.toString().padLeft(7)} ${nb.toString().padLeft(7)}  '
        '${nHsv.$1.toStringAsFixed(0).padLeft(7)}  '
        '${same.padLeft(5)}',
      );
    }

    // 用 NoneType1 多项式对两个色标条分别计算 position
    print('');
    print('═══════════════════════════════════════════════════════════════════════════');
    print('  NoneType1 多项式对两个色标条的 position 计算对比');
    print('═══════════════════════════════════════════════════════════════════════════');
    print(
      '${'actualPos'.padLeft(10)}  '
      '${'LPGM_calcPos'.padLeft(13)}  '
      '${'LPGM_err'.padLeft(9)}  '
      '${'NIED_calcPos'.padLeft(13)}  '
      '${'NIED_err'.padLeft(9)}',
    );
    print('─' * 70);

    for (double p = 0.0; p <= 1.0; p += 0.05) {
      // LPGM
      final lpgmY = (lpgmBottom - p * (lpgmBottom - lpgmTop)).round().clamp(lpgmTop, lpgmBottom);
      int lSumR = 0, lSumG = 0, lSumB = 0, lCount = 0;
      for (int x = lpgmBarX - 5; x <= lpgmBarX + 5; x++) {
        if (x < 0 || x >= w1) continue;
        final off = (lpgmY * w1 + x) * 4;
        final r = raw1.getUint8(off), g = raw1.getUint8(off+1), b = raw1.getUint8(off+2);
        if (r == 0 && g == 0 && b == 0) continue;
        lSumR += r; lSumG += g; lSumB += b; lCount++;
      }
      final lr = lCount > 0 ? lSumR ~/ lCount : 0;
      final lg = lCount > 0 ? lSumG ~/ lCount : 0;
      final lb = lCount > 0 ? lSumB ~/ lCount : 0;
      final lHsv = _rgbToHsv(lr, lg, lb);
      final lCalcPos = color2position(lHsv.$1 / 360.0, lHsv.$2, lHsv.$3);
      final lErr = (lCalcPos - p).abs();

      // NIED
      final niedY = (niedBottom - p * (niedBottom - niedTop)).round().clamp(niedTop, niedBottom);
      int nSumR = 0, nSumG = 0, nSumB = 0, nCount = 0;
      for (int x = niedBarX - 5; x <= niedBarX + 5; x++) {
        if (x < 0 || x >= w2) continue;
        final off = (niedY * w2 + x) * 4;
        final r = raw2.getUint8(off), g = raw2.getUint8(off+1), b = raw2.getUint8(off+2);
        if (r == 0 && g == 0 && b == 0) continue;
        nSumR += r; nSumG += g; nSumB += b; nCount++;
      }
      final nr = nCount > 0 ? nSumR ~/ nCount : 0;
      final ng = nCount > 0 ? nSumG ~/ nCount : 0;
      final nb = nCount > 0 ? nSumB ~/ nCount : 0;
      final nHsv = _rgbToHsv(nr, ng, nb);
      final nCalcPos = color2position(nHsv.$1 / 360.0, nHsv.$2, nHsv.$3);
      final nErr = (nCalcPos - p).abs();

      print(
        '${p.toStringAsFixed(2).padLeft(10)}  '
        '${lCalcPos.toStringAsFixed(4).padLeft(13)}  '
        '${lErr.toStringAsFixed(4).padLeft(9)}  '
        '${nCalcPos.toStringAsFixed(4).padLeft(13)}  '
        '${nErr.toStringAsFixed(4).padLeft(9)}',
      );
    }
  });
}
