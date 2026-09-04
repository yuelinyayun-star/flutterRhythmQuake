import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

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

const _svaScaleValues = [
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
const _log10SvaScale = [
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

double _svaFromPosition(double p) {
  final clamped = p.clamp(0.0, 1.0);
  final n = 13;
  final idx = clamped * (n - 1);
  final i = idx.toInt();
  if (i >= n - 1) return 1000.0;
  final t = idx - i;
  final logSva =
      _log10SvaScale[i] + (_log10SvaScale[i + 1] - _log10SvaScale[i]) * t;
  return math.pow(10.0, logSva).toDouble();
}

double _positionFromSva(double sva) {
  final logSva = math.log(sva) / math.ln10;
  for (int i = 0; i < _log10SvaScale.length - 1; i++) {
    if (logSva >= _log10SvaScale[i] && logSva <= _log10SvaScale[i + 1]) {
      final t =
          (logSva - _log10SvaScale[i]) /
          (_log10SvaScale[i + 1] - _log10SvaScale[i]);
      return (i + t) / 12;
    }
  }
  if (logSva <= _log10SvaScale.first) return 0.0;
  return 1.0;
}

/// Normalize H: wrap H > 350° to H - 360 (so red colors are near 0°, not 360°)
double _normalizeH(double h) {
  if (h > 350) return h - 360;
  return h;
}

/// Least squares polynomial fitting
List<double> _polyFit(List<double> xs, List<double> ys, int degree) {
  final n = xs.length;
  final m = degree + 1;
  final ata = List.generate(m, (_) => List.filled(m, 0.0));
  final aty = List.filled(m, 0.0);
  for (int i = 0; i < n; i++) {
    final xp = List.filled(m, 0.0);
    xp[0] = 1.0;
    for (int j = 1; j < m; j++) {
      xp[j] = xp[j - 1] * xs[i];
    }
    for (int j = 0; j < m; j++) {
      aty[j] += xp[j] * ys[i];
      for (int k = 0; k < m; k++) {
        ata[j][k] += xp[j] * xp[k];
      }
    }
  }
  final aug = List.generate(m, (j) => [...ata[j], aty[j]]);
  for (int col = 0; col < m; col++) {
    int maxRow = col;
    double maxVal = aug[col][col].abs();
    for (int row = col + 1; row < m; row++) {
      if (aug[row][col].abs() > maxVal) {
        maxVal = aug[row][col].abs();
        maxRow = row;
      }
    }
    if (maxRow != col) {
      final tmp = aug[col];
      aug[col] = aug[maxRow];
      aug[maxRow] = tmp;
    }
    for (int row = col + 1; row < m; row++) {
      final factor = aug[row][col] / aug[col][col];
      for (int k = col; k <= m; k++) {
        aug[row][k] -= factor * aug[col][k];
      }
    }
  }
  final coeffs = List.filled(m, 0.0);
  for (int i = m - 1; i >= 0; i--) {
    double sum = aug[i][m];
    for (int j = i + 1; j < m; j++) {
      sum -= aug[i][j] * coeffs[j];
    }
    coeffs[i] = sum / aug[i][i];
  }
  return coeffs;
}

double _polyEval(List<double> coeffs, double x) {
  double result = 0;
  for (int i = coeffs.length - 1; i >= 0; i--) {
    result = result * x + coeffs[i];
  }
  return result;
}

void main() {
  test('Hybrid polynomial fit for LPGM color scale', () async {
    // 1. Download LPGM color scale image
    const legendUrl =
        'https://www.lmoni.bosai.go.jp/monitor/data/data/map_img/ScaleImg2/nied_abrspmx_s_w_scale.png';
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(legendUrl));
    final resp = await req.close();
    final builder = BytesBuilder();
    await for (final chunk in resp) builder.add(chunk);
    client.close();
    final imageBytes = builder.toBytes();

    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final bw = image.width;
    final bh = image.height;
    final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;

    // 2. Find the color bar position
    // First find the column with the most non-black pixels (the color bar center)
    int bestBarX = -1, bestBarCount = 0;
    for (int x = 200; x < bw; x++) {
      int c = 0;
      for (int y = 0; y < bh; y++) {
        final off = (y * bw + x) * 4;
        if (raw.getUint8(off) != 0 ||
            raw.getUint8(off + 1) != 0 ||
            raw.getUint8(off + 2) != 0)
          c++;
      }
      if (c > bestBarCount) {
        bestBarCount = c;
        bestBarX = x;
      }
    }

    // Find the gradient range by detecting the black border lines
    // The color bar has 1px black border lines at top and bottom
    // Scan at bestBarX to find the actual gradient area
    int firstNonBlack = bh, lastNonBlack = 0;
    for (int y = 0; y < bh; y++) {
      final off = (y * bw + bestBarX) * 4;
      final r = raw.getUint8(off),
          g = raw.getUint8(off + 1),
          b = raw.getUint8(off + 2);
      if (r != 0 || g != 0 || b != 0) {
        if (y < firstNonBlack) firstNonBlack = y;
        if (y > lastNonBlack) lastNonBlack = y;
      }
    }

    // Now refine: exclude low-saturation rows at top and bottom (border/background)
    // The actual gradient has saturated colors (S > 0.15) or high brightness
    int barTop = firstNonBlack, barBottom = lastNonBlack;
    // Trim top: skip rows with S <= 0.15 (gray background above the gradient)
    for (int y = firstNonBlack; y <= lastNonBlack; y++) {
      int sumR = 0, sumG = 0, sumB = 0, count = 0;
      for (int x = bestBarX - 3; x <= bestBarX + 3; x++) {
        if (x < 0 || x >= bw) continue;
        final off = (y * bw + x) * 4;
        final r = raw.getUint8(off),
            g = raw.getUint8(off + 1),
            b = raw.getUint8(off + 2);
        if (r == 0 && g == 0 && b == 0) continue;
        sumR += r;
        sumG += g;
        sumB += b;
        count++;
      }
      if (count == 0) continue;
      final avgR = sumR / count, avgG = sumG / count, avgB = sumB / count;
      final cMax = [avgR, avgG, avgB].reduce(math.max) / 255.0;
      final cMin = [avgR, avgG, avgB].reduce(math.min) / 255.0;
      final sat = cMax == 0 ? 0.0 : (cMax - cMin) / cMax;
      // The actual gradient has S > 0.15 (even the bottom purple has S ≈ 0.17)
      // Gray background has S ≈ 0.12
      if (sat > 0.15) {
        barTop = y;
        break;
      }
    }
    // Trim bottom: skip rows with S <= 0.15 (gray background below the gradient)
    for (int y = lastNonBlack; y >= firstNonBlack; y--) {
      int sumR = 0, sumG = 0, sumB = 0, count = 0;
      for (int x = bestBarX - 3; x <= bestBarX + 3; x++) {
        if (x < 0 || x >= bw) continue;
        final off = (y * bw + x) * 4;
        final r = raw.getUint8(off),
            g = raw.getUint8(off + 1),
            b = raw.getUint8(off + 2);
        if (r == 0 && g == 0 && b == 0) continue;
        sumR += r;
        sumG += g;
        sumB += b;
        count++;
      }
      if (count == 0) continue;
      final avgR = sumR / count, avgG = sumG / count, avgB = sumB / count;
      final cMax = [avgR, avgG, avgB].reduce(math.max) / 255.0;
      final cMin = [avgR, avgG, avgB].reduce(math.min) / 255.0;
      final sat = cMax == 0 ? 0.0 : (cMax - cMin) / cMax;
      if (sat > 0.15) {
        barBottom = y;
        break;
      }
    }
    print('Color bar center: x=$bestBarX');
    print(
      'Gradient range: y=$barTop ~ $barBottom (${barBottom - barTop + 1} rows)',
    );

    // 3. Sample every row with horizontal averaging
    // Note: Use single-row sampling (not multi-row avg) because actual map pixels
    // are single pixels, not averaged. Multi-row avg distorts the polynomial fit.
    final samples =
        <
          (double, double, double, double, double)
        >[]; // (H_norm, S, V, G_norm, position)
    for (int y = barBottom; y >= barTop; y--) {
      final position = (barBottom - y) / (barBottom - barTop);
      int sumR = 0, sumG = 0, sumB = 0, count = 0;
      for (int x = bestBarX - 5; x <= bestBarX + 5; x++) {
        if (x < 0 || x >= bw) continue;
        final off = (y * bw + x) * 4;
        final r = raw.getUint8(off),
            g = raw.getUint8(off + 1),
            b = raw.getUint8(off + 2);
        if (r == 0 && g == 0 && b == 0) continue;
        sumR += r;
        sumG += g;
        sumB += b;
        count++;
      }
      if (count == 0) continue;
      final r = sumR ~/ count;
      final g = sumG ~/ count;
      final b = sumB ~/ count;
      final hsv = _rgbToHsv(r, g, b);
      final hNorm = _normalizeH(hsv.$1);
      samples.add((hNorm, hsv.$2, hsv.$3, g / 255.0, position));
    }
    print('Total samples: ${samples.length}');

    // Helper: sample RGB at a given row (single-row, same as actual map pixels)
    (int, int, int)? sampleAtRow(int imageY) {
      int sumR = 0, sumG = 0, sumB = 0, count = 0;
      for (int x = bestBarX - 5; x <= bestBarX + 5; x++) {
        if (x < 0 || x >= bw) continue;
        final off = (imageY * bw + x) * 4;
        final r = raw.getUint8(off),
            g = raw.getUint8(off + 1),
            b = raw.getUint8(off + 2);
        if (r == 0 && g == 0 && b == 0) continue;
        sumR += r;
        sumG += g;
        sumB += b;
        count++;
      }
      if (count == 0) return null;
      return (sumR ~/ count, sumG ~/ count, sumB ~/ count);
    }

    // 4. Print H vs position (normalized) + detailed row data
    print('\n═══════════════════════════════════════════════════════════════');
    print('  H_norm vs position (H > 350° wrapped to H - 360°)');
    print('═══════════════════════════════════════════════════════════════');
    // Also print row index for debugging
    for (int i = 0; i < samples.length; i += 5) {
      final (h, s, v, gNorm, pos) = samples[i];
      final rowIdx = (barBottom - pos * (barBottom - barTop)).round();
      print(
        '  pos=${pos.toStringAsFixed(4)}  '
        'row=$rowIdx  '
        'H=${h.toStringAsFixed(1).padLeft(6)}  '
        'S=${s.toStringAsFixed(3)}  '
        'V=${v.toStringAsFixed(3)}  '
        'G=${gNorm.toStringAsFixed(3)}',
      );
    }

    // 4b. Print the 13 calibration point rows for debugging
    print('\n═══════════════════════════════════════════════════════════════');
    print('  13 calibration point rows (single-row sampling)');
    print('═══════════════════════════════════════════════════════════════');
    for (final expectedSva in _svaScaleValues) {
      final pos = _positionFromSva(expectedSva);
      final imageY = (barBottom - pos * (barBottom - barTop)).round().clamp(
        barTop,
        barBottom,
      );
      final rgb = sampleAtRow(imageY);
      if (rgb == null) {
        print('  SVA=$expectedSva row=$imageY → all black');
        continue;
      }
      final (r, g, b) = rgb;
      final hsv = _rgbToHsv(r, g, b);
      final hNorm = _normalizeH(hsv.$1);
      print(
        '  SVA=${expectedSva.toStringAsFixed(3).padLeft(8)}  '
        'pos=${pos.toStringAsFixed(4)}  '
        'row=$imageY  '
        'H=${hNorm.toStringAsFixed(1).padLeft(6)}  '
        'V=${hsv.$3.toStringAsFixed(3)}  '
        'S=${hsv.$2.toStringAsFixed(3)}',
      );
    }

    // 5. Split into segments with fixed H wrap-around
    // Non-red: H_norm > 10° (H from 300° down to 10°)
    //   - High-H (H > 65°): H→position works well
    //   - Plateau (10° < H ≤ 65°): H barely changes, use G→position instead
    // Red: H_norm ≤ 10° (includes H near 0° and H near 360°)
    final nonRedH = <double>[], nonRedPos = <double>[];
    final plateauG = <double>[], plateauPos = <double>[];
    final redV = <double>[], redPos = <double>[];

    for (final (h, s, v, gNorm, pos) in samples) {
      if (s <= 0.15 && v <= 0.25) continue;
      if (v <= 0.05) continue;

      if (h > 10) {
        nonRedH.add(h);
        nonRedPos.add(pos);
        if (h <= 65) {
          plateauG.add(gNorm);
          plateauPos.add(pos);
        }
      } else {
        redV.add(v);
        redPos.add(pos);
      }
    }

    print('\nSegment sizes (fixed H wrap-around):');
    print(
      '  Non-red (H_norm > 10°): ${nonRedH.length} samples, '
      'H=${nonRedH.first.toStringAsFixed(1)}~${nonRedH.last.toStringAsFixed(1)}, '
      'pos=${nonRedPos.first.toStringAsFixed(4)}~${nonRedPos.last.toStringAsFixed(4)}',
    );
    print(
      '  Plateau (10° < H ≤ 65°): ${plateauG.length} samples, '
      'G=${plateauG.first.toStringAsFixed(3)}~${plateauG.last.toStringAsFixed(3)}, '
      'pos=${plateauPos.first.toStringAsFixed(4)}~${plateauPos.last.toStringAsFixed(4)}',
    );
    print(
      '  Red (H_norm ≤ 10°): ${redV.length} samples, '
      'V=${redV.first.toStringAsFixed(3)}~${redV.last.toStringAsFixed(3)}, '
      'pos=${redPos.first.toStringAsFixed(4)}~${redPos.last.toStringAsFixed(4)}',
    );

    // ═══════════════════════════════════════════════════════════════
    // Approach A: Direct H→position for non-red, inverted position→V for red
    // ═══════════════════════════════════════════════════════════════

    print('\n═══════════════════════════════════════════════════════════════');
    print('  Approach A: Direct H→position (non-red) + Inverted pos→V (red)');
    print('═══════════════════════════════════════════════════════════════');

    // Fit H→position for non-red region
    // Normalize H to [0, 1] by dividing by 360
    final nonRedHnorm = nonRedH.map((h) => h / 360.0).toList();

    List<double>? bestNonRedCoeffs;
    double bestNonRedRmse = double.infinity;
    int bestNonRedDeg = 0;

    print('\nNon-red H→position polynomial:');
    for (int deg = 4; deg <= 10; deg++) {
      if (nonRedHnorm.length <= deg) continue;
      final coeffs = _polyFit(nonRedHnorm, nonRedPos, deg);
      double ss = 0;
      for (int i = 0; i < nonRedHnorm.length; i++) {
        final pred = _polyEval(coeffs, nonRedHnorm[i]);
        ss += (pred - nonRedPos[i]) * (pred - nonRedPos[i]);
      }
      final rmse = math.sqrt(ss / nonRedHnorm.length);
      print('  deg=$deg RMSE=${rmse.toStringAsFixed(6)}');
      if (rmse < bestNonRedRmse) {
        bestNonRedRmse = rmse;
        bestNonRedCoeffs = coeffs;
        bestNonRedDeg = deg;
      }
    }
    print(
      '  Best: deg=$bestNonRedDeg RMSE=${bestNonRedRmse.toStringAsFixed(6)}',
    );

    // Fit position→V for red region (inverted approach)
    List<double>? bestRedPosToVCoeffs;
    double bestRedPosToVRmse = double.infinity;
    int bestRedPosToVDeg = 0;

    print('\nRed position→V polynomial (for inversion):');
    for (int deg = 2; deg <= 6; deg++) {
      if (redPos.length <= deg) continue;
      final coeffs = _polyFit(redPos, redV, deg);
      double ss = 0;
      for (int i = 0; i < redPos.length; i++) {
        final pred = _polyEval(coeffs, redPos[i]);
        ss += (pred - redV[i]) * (pred - redV[i]);
      }
      final rmse = math.sqrt(ss / redPos.length);
      print('  deg=$deg RMSE=${rmse.toStringAsFixed(6)}');
      if (rmse < bestRedPosToVRmse) {
        bestRedPosToVRmse = rmse;
        bestRedPosToVCoeffs = coeffs;
        bestRedPosToVDeg = deg;
      }
    }
    print(
      '  Best: deg=$bestRedPosToVDeg RMSE=${bestRedPosToVRmse.toStringAsFixed(6)}',
    );

    // Pre-compute 13 calibration point HSV values (using multi-row avg)
    final calPoints = <(double, double, double, double, double)>[];
    // (expectedSva, pos, hNorm, V, S)
    for (final expectedSva in _svaScaleValues) {
      final pos = _positionFromSva(expectedSva);
      final imageY = (barBottom - pos * (barBottom - barTop)).round().clamp(
        barTop,
        barBottom,
      );
      final rgb = sampleAtRow(imageY);
      if (rgb == null) continue;
      final (r, g, b) = rgb;
      final hsv = _rgbToHsv(r, g, b);
      final hNorm = _normalizeH(hsv.$1);
      calPoints.add((expectedSva, pos, hNorm, hsv.$3, hsv.$2));
    }

    // Test Approach A on 13 calibration points
    print('\n  13 calibration points (Approach A):');
    double totalErrA = 0;
    int errCountA = 0;
    for (final (expectedSva, pos, hNorm, v, s) in calPoints) {
      double calcPos;
      if (hNorm > 10) {
        // Non-red: direct H→position
        calcPos = _polyEval(bestNonRedCoeffs!, hNorm / 360.0).clamp(0.0, 1.0);
      } else {
        // Red: inverted position→V with binary search
        final targetV = v;
        double lo = redPos.first, hi = redPos.last;
        for (int iter = 0; iter < 50; iter++) {
          final mid = (lo + hi) / 2;
          final predV = _polyEval(bestRedPosToVCoeffs!, mid);
          if (predV > targetV) {
            lo = mid; // higher position → lower V
          } else {
            hi = mid;
          }
        }
        calcPos = ((lo + hi) / 2).clamp(0.0, 1.0);
      }

      final actualSva = _svaFromPosition(calcPos);
      final err = (actualSva - expectedSva).abs() / expectedSva * 100;
      totalErrA += err;
      errCountA++;

      print(
        '  SVA=${expectedSva.toStringAsFixed(3).padLeft(8)}  '
        'H=${hNorm.toStringAsFixed(1).padLeft(6)}  '
        'V=${v.toStringAsFixed(3)}  '
        'pos=${pos.toStringAsFixed(4)}  '
        'calcPos=${calcPos.toStringAsFixed(4)}  '
        'calcSVA=${actualSva.toStringAsFixed(2).padLeft(10)}  '
        'err=${err.toStringAsFixed(1).padLeft(6)}%',
      );
    }
    print('\n  Average error: ${(totalErrA / errCountA).toStringAsFixed(1)}%');

    // ═══════════════════════════════════════════════════════════════
    // Approach B: Split non-red into 2 sub-segments + inverted for red
    // ═══════════════════════════════════════════════════════════════

    print('\n═══════════════════════════════════════════════════════════════');
    print('  Approach B: Split non-red (H>65° / 10°<H≤65°) + Inverted red');
    print('═══════════════════════════════════════════════════════════════');

    final seg1H = <double>[], seg1Pos = <double>[]; // H > 65°
    final seg2H = <double>[], seg2Pos = <double>[]; // 10° < H ≤ 65°

    for (int i = 0; i < nonRedH.length; i++) {
      final h = nonRedH[i];
      final p = nonRedPos[i];
      if (h > 65) {
        seg1H.add(h / 360.0);
        seg1Pos.add(p);
      } else {
        seg2H.add(h / 360.0);
        seg2Pos.add(p);
      }
    }

    print('  Seg1 (H > 65°): ${seg1H.length} samples');
    print('  Seg2 (10° < H ≤ 65°): ${seg2H.length} samples');

    // Fit Seg1
    List<double>? bestSeg1Coeffs;
    double bestSeg1Rmse = double.infinity;
    int bestSeg1Deg = 0;
    for (int deg = 4; deg <= 8; deg++) {
      if (seg1H.length <= deg) continue;
      final coeffs = _polyFit(seg1H, seg1Pos, deg);
      double ss = 0;
      for (int i = 0; i < seg1H.length; i++) {
        final pred = _polyEval(coeffs, seg1H[i]);
        ss += (pred - seg1Pos[i]) * (pred - seg1Pos[i]);
      }
      final rmse = math.sqrt(ss / seg1H.length);
      if (rmse < bestSeg1Rmse) {
        bestSeg1Rmse = rmse;
        bestSeg1Coeffs = coeffs;
        bestSeg1Deg = deg;
      }
    }
    print(
      '  Seg1 best: deg=$bestSeg1Deg RMSE=${bestSeg1Rmse.toStringAsFixed(6)}',
    );

    // Fit Seg2
    List<double>? bestSeg2Coeffs;
    double bestSeg2Rmse = double.infinity;
    int bestSeg2Deg = 0;
    for (int deg = 3; deg <= 8; deg++) {
      if (seg2H.length <= deg) continue;
      final coeffs = _polyFit(seg2H, seg2Pos, deg);
      double ss = 0;
      for (int i = 0; i < seg2H.length; i++) {
        final pred = _polyEval(coeffs, seg2H[i]);
        ss += (pred - seg2Pos[i]) * (pred - seg2Pos[i]);
      }
      final rmse = math.sqrt(ss / seg2H.length);
      if (rmse < bestSeg2Rmse) {
        bestSeg2Rmse = rmse;
        bestSeg2Coeffs = coeffs;
        bestSeg2Deg = deg;
      }
    }
    print(
      '  Seg2 best: deg=$bestSeg2Deg RMSE=${bestSeg2Rmse.toStringAsFixed(6)}',
    );

    // Test Approach B
    print('\n  13 calibration points (Approach B):');
    double totalErrB = 0;
    int errCountB = 0;
    for (final (expectedSva, pos, hNorm, v, s) in calPoints) {
      double calcPos;
      if (hNorm > 65) {
        calcPos = _polyEval(bestSeg1Coeffs!, hNorm / 360.0).clamp(0.0, 1.0);
      } else if (hNorm > 10) {
        calcPos = _polyEval(bestSeg2Coeffs!, hNorm / 360.0).clamp(0.0, 1.0);
      } else {
        // Red: inverted position→V with binary search
        final targetV = v;
        double lo = redPos.first, hi = redPos.last;
        for (int iter = 0; iter < 50; iter++) {
          final mid = (lo + hi) / 2;
          final predV = _polyEval(bestRedPosToVCoeffs!, mid);
          if (predV > targetV) {
            lo = mid;
          } else {
            hi = mid;
          }
        }
        calcPos = ((lo + hi) / 2).clamp(0.0, 1.0);
      }

      final actualSva = _svaFromPosition(calcPos);
      final err = (actualSva - expectedSva).abs() / expectedSva * 100;
      totalErrB += err;
      errCountB++;

      print(
        '  SVA=${expectedSva.toStringAsFixed(3).padLeft(8)}  '
        'H=${hNorm.toStringAsFixed(1).padLeft(6)}  '
        'V=${v.toStringAsFixed(3)}  '
        'pos=${pos.toStringAsFixed(4)}  '
        'calcPos=${calcPos.toStringAsFixed(4)}  '
        'calcSVA=${actualSva.toStringAsFixed(2).padLeft(10)}  '
        'err=${err.toStringAsFixed(1).padLeft(6)}%',
      );
    }
    print('\n  Average error: ${(totalErrB / errCountB).toStringAsFixed(1)}%');

    // ═══════════════════════════════════════════════════════════════
    // Approach C: Fully inverted - position→H for non-red, position→V for red
    // With split sub-segments for non-red
    // ═══════════════════════════════════════════════════════════════

    print('\n═══════════════════════════════════════════════════════════════');
    print('  Approach C: Inverted pos→H (split) + pos→V (red)');
    print('════════════════════════════════════════════════════════════════');

    // Split non-red into sub-segments by position
    final sub1Pos = <double>[], sub1H = <double>[]; // pos 0.0 ~ 0.28
    final sub2Pos = <double>[], sub2H = <double>[]; // pos 0.28 ~ 0.50
    final sub3Pos = <double>[], sub3H = <double>[]; // pos 0.50 ~ 0.75

    for (int i = 0; i < nonRedPos.length; i++) {
      final p = nonRedPos[i];
      final h = nonRedH[i] / 360.0;
      if (p <= 0.28) {
        sub1Pos.add(p);
        sub1H.add(h);
      } else if (p <= 0.50) {
        sub2Pos.add(p);
        sub2H.add(h);
      } else {
        sub3Pos.add(p);
        sub3H.add(h);
      }
    }

    print('  Sub1 (pos 0~0.28): ${sub1Pos.length} samples');
    print('  Sub2 (pos 0.28~0.50): ${sub2Pos.length} samples');
    print('  Sub3 (pos 0.50~0.75): ${sub3Pos.length} samples');

    // Fit position→H for each sub-segment
    List<double>? bestSub1Coeffs, bestSub2Coeffs, bestSub3Coeffs;
    double bestSub1Rmse = double.infinity,
        bestSub2Rmse = double.infinity,
        bestSub3Rmse = double.infinity;
    int bestSub1Deg = 0, bestSub2Deg = 0, bestSub3Deg = 0;

    for (int deg = 3; deg <= 7; deg++) {
      if (sub1Pos.length > deg) {
        final coeffs = _polyFit(sub1Pos, sub1H, deg);
        double ss = 0;
        for (int i = 0; i < sub1Pos.length; i++) {
          ss +=
              (_polyEval(coeffs, sub1Pos[i]) - sub1H[i]) *
              (_polyEval(coeffs, sub1Pos[i]) - sub1H[i]);
        }
        final rmse = math.sqrt(ss / sub1Pos.length);
        if (rmse < bestSub1Rmse) {
          bestSub1Rmse = rmse;
          bestSub1Coeffs = coeffs;
          bestSub1Deg = deg;
        }
      }
      if (sub2Pos.length > deg) {
        final coeffs = _polyFit(sub2Pos, sub2H, deg);
        double ss = 0;
        for (int i = 0; i < sub2Pos.length; i++) {
          ss +=
              (_polyEval(coeffs, sub2Pos[i]) - sub2H[i]) *
              (_polyEval(coeffs, sub2Pos[i]) - sub2H[i]);
        }
        final rmse = math.sqrt(ss / sub2Pos.length);
        if (rmse < bestSub2Rmse) {
          bestSub2Rmse = rmse;
          bestSub2Coeffs = coeffs;
          bestSub2Deg = deg;
        }
      }
      if (sub3Pos.length > deg) {
        final coeffs = _polyFit(sub3Pos, sub3H, deg);
        double ss = 0;
        for (int i = 0; i < sub3Pos.length; i++) {
          ss +=
              (_polyEval(coeffs, sub3Pos[i]) - sub3H[i]) *
              (_polyEval(coeffs, sub3Pos[i]) - sub3H[i]);
        }
        final rmse = math.sqrt(ss / sub3Pos.length);
        if (rmse < bestSub3Rmse) {
          bestSub3Rmse = rmse;
          bestSub3Coeffs = coeffs;
          bestSub3Deg = deg;
        }
      }
    }
    print(
      '  Sub1 best: deg=$bestSub1Deg RMSE=${bestSub1Rmse.toStringAsFixed(6)}',
    );
    print(
      '  Sub2 best: deg=$bestSub2Deg RMSE=${bestSub2Rmse.toStringAsFixed(6)}',
    );
    print(
      '  Sub3 best: deg=$bestSub3Deg RMSE=${bestSub3Rmse.toStringAsFixed(6)}',
    );

    // Inverted approach: given H, find position via binary search in each sub-segment
    double positionFromHInverted(double hNorm) {
      final targetH = hNorm / 360.0;
      double bestPos = -1;
      double bestDist = double.infinity;

      // Try each sub-segment
      final segs = [
        (bestSub1Coeffs, 0.0, 0.28),
        (bestSub2Coeffs, 0.28, 0.50),
        (bestSub3Coeffs, 0.50, 0.75),
      ];

      for (final (coeffs, lo0, hi0) in segs) {
        if (coeffs == null) continue;
        double lo = lo0, hi = hi0;
        for (int iter = 0; iter < 50; iter++) {
          final mid = (lo + hi) / 2;
          final predH = _polyEval(coeffs, mid);
          if (predH > targetH) {
            lo = mid;
          } else {
            hi = mid;
          }
        }
        final mid = (lo + hi) / 2;
        final predH = _polyEval(coeffs!, mid);
        final dist = (predH - targetH).abs();
        if (dist < bestDist) {
          bestDist = dist;
          bestPos = mid;
        }
      }
      return bestPos.clamp(0.0, 1.0);
    }

    // Test Approach C
    print('\n  13 calibration points (Approach C):');
    double totalErrC = 0;
    int errCountC = 0;
    for (final (expectedSva, pos, hNorm, v, s) in calPoints) {
      double calcPos;
      if (hNorm > 10) {
        calcPos = positionFromHInverted(hNorm);
      } else {
        // Red: inverted position→V with binary search
        final targetV = v;
        double lo = redPos.first, hi = redPos.last;
        for (int iter = 0; iter < 50; iter++) {
          final mid = (lo + hi) / 2;
          final predV = _polyEval(bestRedPosToVCoeffs!, mid);
          if (predV > targetV) {
            lo = mid;
          } else {
            hi = mid;
          }
        }
        calcPos = ((lo + hi) / 2).clamp(0.0, 1.0);
      }

      final actualSva = _svaFromPosition(calcPos);
      final err = (actualSva - expectedSva).abs() / expectedSva * 100;
      totalErrC += err;
      errCountC++;

      print(
        '  SVA=${expectedSva.toStringAsFixed(3).padLeft(8)}  '
        'H=${hNorm.toStringAsFixed(1).padLeft(6)}  '
        'V=${v.toStringAsFixed(3)}  '
        'pos=${pos.toStringAsFixed(4)}  '
        'calcPos=${calcPos.toStringAsFixed(4)}  '
        'calcSVA=${actualSva.toStringAsFixed(2).padLeft(10)}  '
        'err=${err.toStringAsFixed(1).padLeft(6)}%',
      );
    }
    print('\n  Average error: ${(totalErrC / errCountC).toStringAsFixed(1)}%');

    // ═══════════════════════════════════════════════════════════════
    // Approach D: H→position (H>65°) + G→position (plateau) + pos→V (red)
    // ═══════════════════════════════════════════════════════════════

    print('\n═══════════════════════════════════════════════════════════════');
    print('  Approach D: H→pos (H>65°) + G→pos (plateau) + pos→V (red)');
    print('═══════════════════════════════════════════════════════════════');

    // Fit H→position for high-H region (H > 65°)
    final highHH = <double>[], highHPos = <double>[];
    for (int i = 0; i < nonRedH.length; i++) {
      if (nonRedH[i] > 65) {
        highHH.add(nonRedH[i] / 360.0);
        highHPos.add(nonRedPos[i]);
      }
    }

    List<double>? bestHighHCoeffs;
    double bestHighHRmse = double.infinity;
    int bestHighHDeg = 0;
    for (int deg = 4; deg <= 10; deg++) {
      if (highHH.length <= deg) continue;
      final coeffs = _polyFit(highHH, highHPos, deg);
      double ss = 0;
      for (int i = 0; i < highHH.length; i++) {
        final pred = _polyEval(coeffs, highHH[i]);
        ss += (pred - highHPos[i]) * (pred - highHPos[i]);
      }
      final rmse = math.sqrt(ss / highHH.length);
      if (rmse < bestHighHRmse) {
        bestHighHRmse = rmse;
        bestHighHCoeffs = coeffs;
        bestHighHDeg = deg;
      }
    }
    print(
      '  High-H (H>65°) H→position: deg=$bestHighHDeg RMSE=${bestHighHRmse.toStringAsFixed(6)}',
    );

    // Fit G→position for plateau region (10° < H ≤ 65°)
    List<double>? bestPlateauGCoeffs;
    double bestPlateauGRmse = double.infinity;
    int bestPlateauGDeg = 0;
    for (int deg = 3; deg <= 8; deg++) {
      if (plateauG.length <= deg) continue;
      final coeffs = _polyFit(plateauG, plateauPos, deg);
      double ss = 0;
      for (int i = 0; i < plateauG.length; i++) {
        final pred = _polyEval(coeffs, plateauG[i]);
        ss += (pred - plateauPos[i]) * (pred - plateauPos[i]);
      }
      final rmse = math.sqrt(ss / plateauG.length);
      if (rmse < bestPlateauGRmse) {
        bestPlateauGRmse = rmse;
        bestPlateauGCoeffs = coeffs;
        bestPlateauGDeg = deg;
      }
    }
    print(
      '  Plateau (10°<H≤65°) G→position: deg=$bestPlateauGDeg RMSE=${bestPlateauGRmse.toStringAsFixed(6)}',
    );

    // Test Approach D on 13 calibration points
    print('\n  13 calibration points (Approach D):');
    double totalErrD = 0;
    int errCountD = 0;
    for (final expectedSva in _svaScaleValues) {
      final pos = _positionFromSva(expectedSva);
      final imageY = (barBottom - pos * (barBottom - barTop)).round().clamp(
        barTop,
        barBottom,
      );

      final rgb = sampleAtRow(imageY);
      if (rgb == null) continue;
      final (r, g, b) = rgb;
      final hsv = _rgbToHsv(r, g, b);
      final hNorm = _normalizeH(hsv.$1);

      double calcPos;
      if (hNorm > 65) {
        // High-H region: H→position
        calcPos = _polyEval(bestHighHCoeffs!, hNorm / 360.0).clamp(0.0, 1.0);
      } else if (hNorm > 10) {
        // Plateau region: G→position
        calcPos = _polyEval(bestPlateauGCoeffs!, g / 255.0).clamp(0.0, 1.0);
      } else {
        // Red region: inverted position→V with binary search
        final targetV = hsv.$3;
        double lo = redPos.first, hi = redPos.last;
        for (int iter = 0; iter < 50; iter++) {
          final mid = (lo + hi) / 2;
          final predV = _polyEval(bestRedPosToVCoeffs!, mid);
          if (predV > targetV) {
            lo = mid;
          } else {
            hi = mid;
          }
        }
        calcPos = ((lo + hi) / 2).clamp(0.0, 1.0);
      }

      final actualSva = _svaFromPosition(calcPos);
      final err = (actualSva - expectedSva).abs() / expectedSva * 100;
      totalErrD += err;
      errCountD++;

      print(
        '  SVA=${expectedSva.toStringAsFixed(3).padLeft(8)}  '
        'H=${hNorm.toStringAsFixed(1).padLeft(6)}  '
        'G=${(g / 255.0).toStringAsFixed(3)}  '
        'V=${hsv.$3.toStringAsFixed(3)}  '
        'pos=${pos.toStringAsFixed(4)}  '
        'calcPos=${calcPos.toStringAsFixed(4)}  '
        'calcSVA=${actualSva.toStringAsFixed(2).padLeft(10)}  '
        'err=${err.toStringAsFixed(1).padLeft(6)}%',
      );
    }
    print('\n  Average error: ${(totalErrD / errCountD).toStringAsFixed(1)}%');

    // ═══════════════════════════════════════════════════════════════
    // Approach E: H→pos (H>65°) + V→pos (plateau 10°<H≤65°) + pos→V (red)
    // Key insight: In the plateau region, H barely changes (≈55-65°) but V
    // decreases monotonically from ~0.765 to ~0.349, making V a much better
    // input feature for position estimation.
    // ═══════════════════════════════════════════════════════════════

    print('\n═══════════════════════════════════════════════════════════════');
    print('  Approach E: H→pos (H>65°) + V→pos (plateau) + pos→V (red)');
    print('═══════════════════════════════════════════════════════════════');

    // Collect plateau V data
    final plateauV = <double>[], plateauVPos = <double>[];
    for (final (h, s, v, gNorm, pos) in samples) {
      if (s <= 0.15 && v <= 0.25) continue;
      if (v <= 0.05) continue;
      if (h > 10 && h <= 65) {
        plateauV.add(v);
        plateauVPos.add(pos);
      }
    }
    print(
      '  Plateau (10°<H≤65°) V→position: ${plateauV.length} samples, '
      'V=${plateauV.first.toStringAsFixed(3)}~${plateauV.last.toStringAsFixed(3)}, '
      'pos=${plateauVPos.first.toStringAsFixed(4)}~${plateauVPos.last.toStringAsFixed(4)}',
    );

    // Check V monotonicity in plateau region
    bool vMonotonic = true;
    for (int i = 1; i < plateauV.length; i++) {
      if (plateauV[i] >= plateauV[i - 1]) {
        vMonotonic = false;
        break;
      }
    }
    print('  V monotonic (decreasing) in plateau: $vMonotonic');

    // Fit V→position for plateau region
    List<double>? bestPlateauVCoeffs;
    double bestPlateauVRmse = double.infinity;
    int bestPlateauVDeg = 0;
    for (int deg = 3; deg <= 8; deg++) {
      if (plateauV.length <= deg) continue;
      final coeffs = _polyFit(plateauV, plateauVPos, deg);
      double ss = 0;
      for (int i = 0; i < plateauV.length; i++) {
        final pred = _polyEval(coeffs, plateauV[i]);
        ss += (pred - plateauVPos[i]) * (pred - plateauVPos[i]);
      }
      final rmse = math.sqrt(ss / plateauV.length);
      print('    deg=$deg RMSE=${rmse.toStringAsFixed(6)}');
      if (rmse < bestPlateauVRmse) {
        bestPlateauVRmse = rmse;
        bestPlateauVCoeffs = coeffs;
        bestPlateauVDeg = deg;
      }
    }
    print(
      '  Plateau V→position best: deg=$bestPlateauVDeg RMSE=${bestPlateauVRmse.toStringAsFixed(6)}',
    );

    // Test Approach E on 13 calibration points
    print('\n  13 calibration points (Approach E):');
    double totalErrE = 0;
    int errCountE = 0;
    for (final (expectedSva, pos, hNorm, v, s) in calPoints) {
      double calcPos;
      if (hNorm > 65) {
        // High-H region: H→position
        calcPos = _polyEval(bestHighHCoeffs!, hNorm / 360.0).clamp(0.0, 1.0);
      } else if (hNorm > 10) {
        // Plateau region: V→position
        calcPos = _polyEval(bestPlateauVCoeffs!, v).clamp(0.0, 1.0);
      } else {
        // Red region: inverted position→V with binary search
        final targetV = v;
        double lo = redPos.first, hi = redPos.last;
        for (int iter = 0; iter < 50; iter++) {
          final mid = (lo + hi) / 2;
          final predV = _polyEval(bestRedPosToVCoeffs!, mid);
          if (predV > targetV) {
            lo = mid;
          } else {
            hi = mid;
          }
        }
        calcPos = ((lo + hi) / 2).clamp(0.0, 1.0);
      }

      final actualSva = _svaFromPosition(calcPos);
      final err = (actualSva - expectedSva).abs() / expectedSva * 100;
      totalErrE += err;
      errCountE++;

      print(
        '  SVA=${expectedSva.toStringAsFixed(3).padLeft(8)}  '
        'H=${hNorm.toStringAsFixed(1).padLeft(6)}  '
        'V=${v.toStringAsFixed(3)}  '
        'pos=${pos.toStringAsFixed(4)}  '
        'calcPos=${calcPos.toStringAsFixed(4)}  '
        'calcSVA=${actualSva.toStringAsFixed(2).padLeft(10)}  '
        'err=${err.toStringAsFixed(1).padLeft(6)}%',
      );
    }
    print('\n  Average error: ${(totalErrE / errCountE).toStringAsFixed(1)}%');

    // ═══════════════════════════════════════════════════════════════
    // Approach F: Full-range forward fit pos→H + pos→V, then binary
    // search on position to match input (H, V).
    // This avoids the plateau problem entirely because we search over
    // position space where both H and V are well-defined functions.
    // ═══════════════════════════════════════════════════════════════

    print('\n═══════════════════════════════════════════════════════════════');
    print('  Approach F: Forward pos→H + pos→V, binary search on pos');
    print('═══════════════════════════════════════════════════════════════');

    // Collect all valid samples for forward fitting
    final allPos = <double>[], allH = <double>[], allV = <double>[];
    for (final (h, s, v, gNorm, pos) in samples) {
      if (s <= 0.15 && v <= 0.25) continue;
      if (v <= 0.05) continue;
      allPos.add(pos);
      allH.add(h / 360.0); // normalized
      allV.add(v);
    }
    print('  Total valid samples for forward fit: ${allPos.length}');

    // Fit position→H (full range, split into segments for better accuracy)
    // Split at position boundaries where H behavior changes
    final fwdSeg1Pos = <double>[], fwdSeg1H = <double>[], fwdSeg1V = <double>[];
    final fwdSeg2Pos = <double>[], fwdSeg2H = <double>[], fwdSeg2V = <double>[];
    final fwdSeg3Pos = <double>[], fwdSeg3H = <double>[], fwdSeg3V = <double>[];

    for (int i = 0; i < allPos.length; i++) {
      final p = allPos[i];
      if (p <= 0.30) {
        fwdSeg1Pos.add(p);
        fwdSeg1H.add(allH[i]);
        fwdSeg1V.add(allV[i]);
      } else if (p <= 0.80) {
        fwdSeg2Pos.add(p);
        fwdSeg2H.add(allH[i]);
        fwdSeg2V.add(allV[i]);
      } else {
        fwdSeg3Pos.add(p);
        fwdSeg3H.add(allH[i]);
        fwdSeg3V.add(allV[i]);
      }
    }
    print('  Fwd Seg1 (pos 0~0.30): ${fwdSeg1Pos.length} samples');
    print('  Fwd Seg2 (pos 0.30~0.80): ${fwdSeg2Pos.length} samples');
    print('  Fwd Seg3 (pos 0.80~1.00): ${fwdSeg3Pos.length} samples');

    // Fit position→H for each segment
    List<double>? fwdSeg1HCoeffs, fwdSeg2HCoeffs, fwdSeg3HCoeffs;
    double fwdSeg1HRmse = double.infinity,
        fwdSeg2HRmse = double.infinity,
        fwdSeg3HRmse = double.infinity;
    int fwdSeg1HDeg = 0, fwdSeg2HDeg = 0, fwdSeg3HDeg = 0;

    for (int deg = 3; deg <= 8; deg++) {
      if (fwdSeg1Pos.length > deg) {
        final coeffs = _polyFit(fwdSeg1Pos, fwdSeg1H, deg);
        double ss = 0;
        for (int i = 0; i < fwdSeg1Pos.length; i++) {
          ss +=
              (_polyEval(coeffs, fwdSeg1Pos[i]) - fwdSeg1H[i]) *
              (_polyEval(coeffs, fwdSeg1Pos[i]) - fwdSeg1H[i]);
        }
        final rmse = math.sqrt(ss / fwdSeg1Pos.length);
        if (rmse < fwdSeg1HRmse) {
          fwdSeg1HRmse = rmse;
          fwdSeg1HCoeffs = coeffs;
          fwdSeg1HDeg = deg;
        }
      }
      if (fwdSeg2Pos.length > deg) {
        final coeffs = _polyFit(fwdSeg2Pos, fwdSeg2H, deg);
        double ss = 0;
        for (int i = 0; i < fwdSeg2Pos.length; i++) {
          ss +=
              (_polyEval(coeffs, fwdSeg2Pos[i]) - fwdSeg2H[i]) *
              (_polyEval(coeffs, fwdSeg2Pos[i]) - fwdSeg2H[i]);
        }
        final rmse = math.sqrt(ss / fwdSeg2Pos.length);
        if (rmse < fwdSeg2HRmse) {
          fwdSeg2HRmse = rmse;
          fwdSeg2HCoeffs = coeffs;
          fwdSeg2HDeg = deg;
        }
      }
      if (fwdSeg3Pos.length > deg) {
        final coeffs = _polyFit(fwdSeg3Pos, fwdSeg3H, deg);
        double ss = 0;
        for (int i = 0; i < fwdSeg3Pos.length; i++) {
          ss +=
              (_polyEval(coeffs, fwdSeg3Pos[i]) - fwdSeg3H[i]) *
              (_polyEval(coeffs, fwdSeg3Pos[i]) - fwdSeg3H[i]);
        }
        final rmse = math.sqrt(ss / fwdSeg3Pos.length);
        if (rmse < fwdSeg3HRmse) {
          fwdSeg3HRmse = rmse;
          fwdSeg3HCoeffs = coeffs;
          fwdSeg3HDeg = deg;
        }
      }
    }
    print(
      '  Fwd Seg1 pos→H: deg=$fwdSeg1HDeg RMSE=${fwdSeg1HRmse.toStringAsFixed(6)}',
    );
    print(
      '  Fwd Seg2 pos→H: deg=$fwdSeg2HDeg RMSE=${fwdSeg2HRmse.toStringAsFixed(6)}',
    );
    print(
      '  Fwd Seg3 pos→H: deg=$fwdSeg3HDeg RMSE=${fwdSeg3HRmse.toStringAsFixed(6)}',
    );

    // Fit position→V for each segment
    List<double>? fwdSeg1VCoeffs, fwdSeg2VCoeffs, fwdSeg3VCoeffs;
    double fwdSeg1VRmse = double.infinity,
        fwdSeg2VRmse = double.infinity,
        fwdSeg3VRmse = double.infinity;
    int fwdSeg1VDeg = 0, fwdSeg2VDeg = 0, fwdSeg3VDeg = 0;

    for (int deg = 2; deg <= 6; deg++) {
      if (fwdSeg1Pos.length > deg) {
        final coeffs = _polyFit(fwdSeg1Pos, fwdSeg1V, deg);
        double ss = 0;
        for (int i = 0; i < fwdSeg1Pos.length; i++) {
          ss +=
              (_polyEval(coeffs, fwdSeg1Pos[i]) - fwdSeg1V[i]) *
              (_polyEval(coeffs, fwdSeg1Pos[i]) - fwdSeg1V[i]);
        }
        final rmse = math.sqrt(ss / fwdSeg1Pos.length);
        if (rmse < fwdSeg1VRmse) {
          fwdSeg1VRmse = rmse;
          fwdSeg1VCoeffs = coeffs;
          fwdSeg1VDeg = deg;
        }
      }
      if (fwdSeg2Pos.length > deg) {
        final coeffs = _polyFit(fwdSeg2Pos, fwdSeg2V, deg);
        double ss = 0;
        for (int i = 0; i < fwdSeg2Pos.length; i++) {
          ss +=
              (_polyEval(coeffs, fwdSeg2Pos[i]) - fwdSeg2V[i]) *
              (_polyEval(coeffs, fwdSeg2Pos[i]) - fwdSeg2V[i]);
        }
        final rmse = math.sqrt(ss / fwdSeg2Pos.length);
        if (rmse < fwdSeg2VRmse) {
          fwdSeg2VRmse = rmse;
          fwdSeg2VCoeffs = coeffs;
          fwdSeg2VDeg = deg;
        }
      }
      if (fwdSeg3Pos.length > deg) {
        final coeffs = _polyFit(fwdSeg3Pos, fwdSeg3V, deg);
        double ss = 0;
        for (int i = 0; i < fwdSeg3Pos.length; i++) {
          ss +=
              (_polyEval(coeffs, fwdSeg3Pos[i]) - fwdSeg3V[i]) *
              (_polyEval(coeffs, fwdSeg3Pos[i]) - fwdSeg3V[i]);
        }
        final rmse = math.sqrt(ss / fwdSeg3Pos.length);
        if (rmse < fwdSeg3VRmse) {
          fwdSeg3VRmse = rmse;
          fwdSeg3VCoeffs = coeffs;
          fwdSeg3VDeg = deg;
        }
      }
    }
    print(
      '  Fwd Seg1 pos→V: deg=$fwdSeg1VDeg RMSE=${fwdSeg1VRmse.toStringAsFixed(6)}',
    );
    print(
      '  Fwd Seg2 pos→V: deg=$fwdSeg2VDeg RMSE=${fwdSeg2VRmse.toStringAsFixed(6)}',
    );
    print(
      '  Fwd Seg3 pos→V: deg=$fwdSeg3VDeg RMSE=${fwdSeg3VRmse.toStringAsFixed(6)}',
    );

    // Binary search: find position that minimizes distance in (H_norm, V) space
    double positionFromHV(double hNorm, double v) {
      final targetH = hNorm / 360.0;
      final targetV = v;

      // Weight: H is more important in non-plateau, V is more important in plateau
      // Use equal weight for now, normalized to similar scale
      double distAt(double pos) {
        // Determine which segment
        List<double> hCoeffs, vCoeffs;
        if (pos <= 0.30) {
          hCoeffs = fwdSeg1HCoeffs!;
          vCoeffs = fwdSeg1VCoeffs!;
        } else if (pos <= 0.80) {
          hCoeffs = fwdSeg2HCoeffs!;
          vCoeffs = fwdSeg2VCoeffs!;
        } else {
          hCoeffs = fwdSeg3HCoeffs!;
          vCoeffs = fwdSeg3VCoeffs!;
        }
        final predH = _polyEval(hCoeffs, pos);
        final predV = _polyEval(vCoeffs, pos);
        // H is in [0,1] range (normalized by 360), V is in [0,1] range
        // Weight H more since it carries more information
        final dh = (predH - targetH) * 3.0; // weight H 3x
        final dv = predV - targetV;
        return dh * dh + dv * dv;
      }

      // Grid search for initial estimate, then refine with golden section
      double bestPos = 0.0;
      double bestDist = double.infinity;
      const gridN = 200;
      for (int i = 0; i <= gridN; i++) {
        final p = i / gridN;
        final d = distAt(p);
        if (d < bestDist) {
          bestDist = d;
          bestPos = p;
        }
      }

      // Refine with golden section search around bestPos
      double lo = (bestPos - 0.02).clamp(0.0, 1.0);
      double hi = (bestPos + 0.02).clamp(0.0, 1.0);
      const phi = 0.618033988749895;
      double a = lo, b = hi;
      double c = b - phi * (b - a);
      double d = a + phi * (b - a);
      for (int iter = 0; iter < 50; iter++) {
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
      return ((a + b) / 2).clamp(0.0, 1.0);
    }

    // Test Approach F on 13 calibration points
    print('\n  13 calibration points (Approach F):');
    double totalErrF = 0;
    int errCountF = 0;
    for (final (expectedSva, pos, hNorm, v, s) in calPoints) {
      final calcPos = positionFromHV(hNorm, v);

      final actualSva = _svaFromPosition(calcPos);
      final err = (actualSva - expectedSva).abs() / expectedSva * 100;
      totalErrF += err;
      errCountF++;

      print(
        '  SVA=${expectedSva.toStringAsFixed(3).padLeft(8)}  '
        'H=${hNorm.toStringAsFixed(1).padLeft(6)}  '
        'V=${v.toStringAsFixed(3)}  '
        'pos=${pos.toStringAsFixed(4)}  '
        'calcPos=${calcPos.toStringAsFixed(4)}  '
        'calcSVA=${actualSva.toStringAsFixed(2).padLeft(10)}  '
        'err=${err.toStringAsFixed(1).padLeft(6)}%',
      );
    }
    print('\n  Average error: ${(totalErrF / errCountF).toStringAsFixed(1)}%');

    // ═══════════════════════════════════════════════════════════════
    // Approach G: B's non-red (split H→pos) + F's red (forward min-dist)
    // Best of both worlds: H→position for non-red (B's approach) and
    // forward pos→H + pos→V with minimum distance search for red (F's approach)
    // ═══════════════════════════════════════════════════════════════

    print('\n═══════════════════════════════════════════════════════════════');
    print('  Approach G: B non-red + F red (split H→pos + forward min-dist)');
    print('═══════════════════════════════════════════════════════════════');

    // For red region, use forward pos→H + pos→V with minimum distance search
    double positionFromHVRed(double hNorm, double v) {
      final targetH = hNorm / 360.0;
      final targetV = v;

      double distAt(double pos) {
        final predH = _polyEval(fwdSeg3HCoeffs!, pos);
        final predV = _polyEval(fwdSeg3VCoeffs!, pos);
        final dh = (predH - targetH) * 3.0;
        final dv = predV - targetV;
        return dh * dh + dv * dv;
      }

      // Grid search for initial estimate
      double bestPos = 0.80;
      double bestDist = double.infinity;
      const gridN = 200;
      for (int i = (gridN * 0.80).round(); i <= gridN; i++) {
        final p = i / gridN;
        final d = distAt(p);
        if (d < bestDist) {
          bestDist = d;
          bestPos = p;
        }
      }

      // Refine with golden section search
      double lo = (bestPos - 0.02).clamp(0.80, 1.0);
      double hi = (bestPos + 0.02).clamp(0.80, 1.0);
      const phi = 0.618033988749895;
      double a = lo, b = hi;
      double c = b - phi * (b - a);
      double d = a + phi * (b - a);
      for (int iter = 0; iter < 50; iter++) {
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

    // Test Approach G on 13 calibration points
    print('\n  13 calibration points (Approach G):');
    double totalErrG = 0;
    int errCountG = 0;
    for (final (expectedSva, pos, hNorm, v, s) in calPoints) {
      double calcPos;
      if (hNorm > 65) {
        // High-H: Seg1 H→position (from Approach B)
        calcPos = _polyEval(bestSeg1Coeffs!, hNorm / 360.0).clamp(0.0, 1.0);
      } else if (hNorm > 10) {
        // Plateau: Seg2 H→position (from Approach B)
        calcPos = _polyEval(bestSeg2Coeffs!, hNorm / 360.0).clamp(0.0, 1.0);
      } else {
        // Red: forward min-distance search (from Approach F)
        calcPos = positionFromHVRed(hNorm, v);
      }

      final actualSva = _svaFromPosition(calcPos);
      final err = (actualSva - expectedSva).abs() / expectedSva * 100;
      totalErrG += err;
      errCountG++;

      print(
        '  SVA=${expectedSva.toStringAsFixed(3).padLeft(8)}  '
        'H=${hNorm.toStringAsFixed(1).padLeft(6)}  '
        'V=${v.toStringAsFixed(3)}  '
        'pos=${pos.toStringAsFixed(4)}  '
        'calcPos=${calcPos.toStringAsFixed(4)}  '
        'calcSVA=${actualSva.toStringAsFixed(2).padLeft(10)}  '
        'err=${err.toStringAsFixed(1).padLeft(6)}%',
      );
    }
    print('\n  Average error: ${(totalErrG / errCountG).toStringAsFixed(1)}%');

    // ═══════════════════════════════════════════════════════════════
    // Approach H: Seg1 H→pos (high-H) + forward min-dist for plateau + forward min-dist for red
    // Key improvement: plateau region uses (H,V) min-distance search
    // so V can disambiguate when H is nearly constant (e.g. SVA=2 vs 5)
    // ═══════════════════════════════════════════════════════════════

    print('\n═══════════════════════════════════════════════════════════════');
    print(
      '  Approach H: Seg1 H→pos + forward min-dist plateau + forward min-dist red',
    );
    print('═══════════════════════════════════════════════════════════════');

    // For plateau region, use forward pos→H + pos→V with minimum distance search
    // (same technique as red region, but for pos 0.30~0.80 range)
    double positionFromHVPlateau(double hNorm, double v) {
      final targetH = hNorm / 360.0;
      final targetV = v;

      double distAt(double pos) {
        final predH = _polyEval(fwdSeg2HCoeffs!, pos);
        final predV = _polyEval(fwdSeg2VCoeffs!, pos);
        final dh = (predH - targetH) * 3.0;
        final dv = predV - targetV;
        return dh * dh + dv * dv;
      }

      // Grid search for initial estimate
      double bestPos = 0.30;
      double bestDist = double.infinity;
      const gridN = 200;
      for (int i = (gridN * 0.30).round(); i <= (gridN * 0.80).round(); i++) {
        final p = i / gridN;
        final d = distAt(p);
        if (d < bestDist) {
          bestDist = d;
          bestPos = p;
        }
      }

      // Refine with golden section search
      double lo = (bestPos - 0.05).clamp(0.30, 0.80);
      double hi = (bestPos + 0.05).clamp(0.30, 0.80);
      const phi = 0.618033988749895;
      double a = lo, b = hi;
      double c = b - phi * (b - a);
      double d = a + phi * (b - a);
      for (int iter = 0; iter < 50; iter++) {
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
      return ((a + b) / 2).clamp(0.30, 0.80);
    }

    // Test Approach H on 13 calibration points
    print('\n  13 calibration points (Approach H):');
    double totalErrH = 0;
    int errCountH = 0;
    for (final (expectedSva, pos, hNorm, v, s) in calPoints) {
      double calcPos;
      if (hNorm > 65) {
        // High-H: Seg1 H→position (from Approach B)
        calcPos = _polyEval(bestSeg1Coeffs!, hNorm / 360.0).clamp(0.0, 1.0);
      } else if (hNorm > 10) {
        // Plateau: forward min-distance search using (H,V)
        calcPos = positionFromHVPlateau(hNorm, v);
      } else {
        // Red: forward min-distance search (from Approach F)
        calcPos = positionFromHVRed(hNorm, v);
      }

      final actualSva = _svaFromPosition(calcPos);
      final err = (actualSva - expectedSva).abs() / expectedSva * 100;
      totalErrH += err;
      errCountH++;

      print(
        '  SVA=${expectedSva.toStringAsFixed(3).padLeft(8)}  '
        'H=${hNorm.toStringAsFixed(1).padLeft(6)}  '
        'V=${v.toStringAsFixed(3)}  '
        'pos=${pos.toStringAsFixed(4)}  '
        'calcPos=${calcPos.toStringAsFixed(4)}  '
        'calcSVA=${actualSva.toStringAsFixed(2).padLeft(10)}  '
        'err=${err.toStringAsFixed(1).padLeft(6)}%',
      );
    }
    print('\n  Average error: ${(totalErrH / errCountH).toStringAsFixed(1)}%');

    // ═══════════════════════════════════════════════════════════════
    // Print the best approach's coefficients for Dart code
    // ═══════════════════════════════════════════════════════════════

    print('\n═══════════════════════════════════════════════════════════════');
    print(
      '  Summary: A avg=${(totalErrA / errCountA).toStringAsFixed(1)}%, '
      'B avg=${(totalErrB / errCountB).toStringAsFixed(1)}%, '
      'C avg=${(totalErrC / errCountC).toStringAsFixed(1)}%, '
      'D avg=${(totalErrD / errCountD).toStringAsFixed(1)}%, '
      'E avg=${(totalErrE / errCountE).toStringAsFixed(1)}%, '
      'F avg=${(totalErrF / errCountF).toStringAsFixed(1)}%, '
      'G avg=${(totalErrG / errCountG).toStringAsFixed(1)}%, '
      'H avg=${(totalErrH / errCountH).toStringAsFixed(1)}%',
    );
    print('═══════════════════════════════════════════════════════════════');

    // Print coefficients for best approach
    final approaches = [
      ('A', totalErrA / errCountA),
      ('B', totalErrB / errCountB),
      ('C', totalErrC / errCountC),
      ('D', totalErrD / errCountD),
      ('E', totalErrE / errCountE),
      ('F', totalErrF / errCountF),
      ('G', totalErrG / errCountG),
      ('H', totalErrH / errCountH),
    ];
    approaches.sort((a, b) => a.$2.compareTo(b.$2));
    final bestApproach = approaches.first.$1;
    print(
      '\n  Best approach: $bestApproach (avg=${approaches.first.$2.toStringAsFixed(1)}%)',
    );

    // Always print Approach G coefficients (our chosen approach for service code)
    print('\n// ═══ Approach G coefficients (for service code) ═══');
    print('// Seg1 (H>65°): H_norm/360 → position, deg=$bestSeg1Deg');
    print('static const _seg1HCoeffs = [');
    for (final c in bestSeg1Coeffs!) {
      print('  ${c.toStringAsFixed(15)},');
    }
    print('];');
    print('\n// Seg2 (10°<H≤65°): H_norm/360 → position, deg=$bestSeg2Deg');
    print('static const _seg2HCoeffs = [');
    for (final c in bestSeg2Coeffs!) {
      print('  ${c.toStringAsFixed(15)},');
    }
    print('];');
    print('\n// Fwd Seg3 (pos 0.80~1.00): pos→H, deg=$fwdSeg3HDeg');
    print('static const _fwdSeg3HCoeffs = [');
    for (final c in fwdSeg3HCoeffs!) {
      print('  ${c.toStringAsFixed(15)},');
    }
    print('];');
    print('\n// Fwd Seg3 (pos 0.80~1.00): pos→V, deg=$fwdSeg3VDeg');
    print('static const _fwdSeg3VCoeffs = [');
    for (final c in fwdSeg3VCoeffs!) {
      print('  ${c.toStringAsFixed(15)},');
    }
    print('];');

    if (bestApproach == 'G') {
      print('\n// ═══ Approach G coefficients ═══');
      print('// Seg1 (H>65°): H_norm/360 → position, deg=$bestSeg1Deg');
      print('static const _seg1HCoeffs = [');
      for (final c in bestSeg1Coeffs!) {
        print('  ${c.toStringAsFixed(15)},');
      }
      print('];');
      print('\n// Seg2 (10°<H≤65°): H_norm/360 → position, deg=$bestSeg2Deg');
      print('static const _seg2HCoeffs = [');
      for (final c in bestSeg2Coeffs!) {
        print('  ${c.toStringAsFixed(15)},');
      }
      print('];');
      print('\n// Fwd Seg3 (pos 0.80~1.00): pos→H, deg=$fwdSeg3HDeg');
      print('static const _fwdSeg3HCoeffs = [');
      for (final c in fwdSeg3HCoeffs!) {
        print('  ${c.toStringAsFixed(15)},');
      }
      print('];');
      print('\n// Fwd Seg3 (pos 0.80~1.00): pos→V, deg=$fwdSeg3VDeg');
      print('static const _fwdSeg3VCoeffs = [');
      for (final c in fwdSeg3VCoeffs!) {
        print('  ${c.toStringAsFixed(15)},');
      }
      print('];');
    } else if (bestApproach == 'F') {
      print('\n// ═══ Approach F coefficients ═══');
      print('// Fwd Seg1 (pos 0~0.30): pos→H, deg=$fwdSeg1HDeg');
      print('static const _fwdSeg1HCoeffs = [');
      for (final c in fwdSeg1HCoeffs!) {
        print('  ${c.toStringAsFixed(15)},');
      }
      print('];');
      print('\n// Fwd Seg2 (pos 0.30~0.80): pos→H, deg=$fwdSeg2HDeg');
      print('static const _fwdSeg2HCoeffs = [');
      for (final c in fwdSeg2HCoeffs!) {
        print('  ${c.toStringAsFixed(15)},');
      }
      print('];');
      print('\n// Fwd Seg3 (pos 0.80~1.00): pos→H, deg=$fwdSeg3HDeg');
      print('static const _fwdSeg3HCoeffs = [');
      for (final c in fwdSeg3HCoeffs!) {
        print('  ${c.toStringAsFixed(15)},');
      }
      print('];');
      print('\n// Fwd Seg1 (pos 0~0.30): pos→V, deg=$fwdSeg1VDeg');
      print('static const _fwdSeg1VCoeffs = [');
      for (final c in fwdSeg1VCoeffs!) {
        print('  ${c.toStringAsFixed(15)},');
      }
      print('];');
      print('\n// Fwd Seg2 (pos 0.30~0.80): pos→V, deg=$fwdSeg2VDeg');
      print('static const _fwdSeg2VCoeffs = [');
      for (final c in fwdSeg2VCoeffs!) {
        print('  ${c.toStringAsFixed(15)},');
      }
      print('];');
      print('\n// Fwd Seg3 (pos 0.80~1.00): pos→V, deg=$fwdSeg3VDeg');
      print('static const _fwdSeg3VCoeffs = [');
      for (final c in fwdSeg3VCoeffs!) {
        print('  ${c.toStringAsFixed(15)},');
      }
      print('];');
    } else if (bestApproach == 'A') {
      print('\n// ═══ Approach A coefficients ═══');
      print('// Non-red: H_norm/360 → position, deg=$bestNonRedDeg');
      print('static const _nonRedHCoeffs = [');
      for (final c in bestNonRedCoeffs!) {
        print('  ${c.toStringAsFixed(15)},');
      }
      print('];');
      print('\n// Red: position → V (for inversion), deg=$bestRedPosToVDeg');
      print('static const _redPosToVCoeffs = [');
      for (final c in bestRedPosToVCoeffs!) {
        print('  ${c.toStringAsFixed(15)},');
      }
      print('];');
      print(
        '// Red region position range: ${redPos.first.toStringAsFixed(4)} ~ ${redPos.last.toStringAsFixed(4)}',
      );
    }
  });

  // ═══════════════════════════════════════════════════════════════
  // Integration test: verify the polynomial method matches service code
  // ═══════════════════════════════════════════════════════════════
  test('Integration: polynomial method vs service code', () async {
    // Same coefficients as in lpgm_monitor_service.dart (Approach G)
    const seg1HCoeffs = [
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
    const seg2HCoeffs = [
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
    const fwdRedHCoeffs = [
      -317.606418568731158,
      1529.274225936303537,
      -2546.891986670196729,
      1120.213918891942285,
      1467.996471615477503,
      -1919.134431419236307,
      735.142609758312915,
      -68.988896493292302,
    ];
    const fwdRedVCoeffs = [
      7624.402922573011892,
      -35905.804882620301214,
      58259.456480197964993,
      -25087.462649548655463,
      -29685.464062582039332,
      35384.701423115729995,
      -10589.307931537665354,
    ];

    double polyEval(List<double> coeffs, double x) {
      double result = 0;
      for (int i = coeffs.length - 1; i >= 0; i--) {
        result = result * x + coeffs[i];
      }
      return result;
    }

    double positionFromHVRed(double hNorm, double v) {
      final targetH = hNorm / 360.0;
      final targetV = v;
      double distAt(double pos) {
        final predH = polyEval(fwdRedHCoeffs, pos);
        final predV = polyEval(fwdRedVCoeffs, pos);
        final dh = (predH - targetH) * 3.0;
        final dv = predV - targetV;
        return dh * dh + dv * dv;
      }

      double bestPos = 0.80;
      double bestDist = double.infinity;
      const gridN = 40;
      for (int i = (gridN * 0.80).round(); i <= gridN; i++) {
        final p = i / gridN;
        final d = distAt(p);
        if (d < bestDist) {
          bestDist = d;
          bestPos = p;
        }
      }
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

    double? rgbToSva(int r, int g, int b) {
      final rn = r / 255.0, gn = g / 255.0, bn = b / 255.0;
      final cMax = math.max(rn, math.max(gn, bn));
      final cMin = math.min(rn, math.min(gn, bn));
      final delta = cMax - cMin;
      double h = 0.0;
      if (delta != 0) {
        if (cMax == rn)
          h = 60 * (((gn - bn) / delta) % 6);
        else if (cMax == gn)
          h = 60 * (((bn - rn) / delta) + 2);
        else
          h = 60 * (((rn - gn) / delta) + 4);
      }
      if (h < 0) h += 360;
      final s = cMax == 0 ? 0.0 : delta / cMax;
      final v = cMax;
      if (s <= 0.15 && v <= 0.25) {
        if (v > 0.05) return 1000.0;
        return null;
      }
      if (v <= 0.05) return null;
      final hNorm = h > 350 ? h - 360 : h;
      double calcPos;
      if (hNorm > 65) {
        calcPos = polyEval(seg1HCoeffs, hNorm / 360.0).clamp(0.0, 1.0);
      } else if (hNorm > 10) {
        calcPos = polyEval(seg2HCoeffs, hNorm / 360.0).clamp(0.0, 1.0);
      } else {
        calcPos = positionFromHVRed(hNorm, v);
      }
      return _svaFromPosition(calcPos);
    }

    // Download LPGM color scale image and test on 13 calibration points
    const legendUrl =
        'https://www.lmoni.bosai.go.jp/monitor/data/data/map_img/ScaleImg2/nied_abrspmx_s_w_scale.png';
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(legendUrl));
    final resp = await req.close();
    final builder = BytesBuilder();
    await for (final chunk in resp) builder.add(chunk);
    client.close();
    final imageBytes = builder.toBytes();

    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final bw = image.width;
    final bh = image.height;
    final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;

    int bestBarX = -1, bestBarCount = 0;
    for (int x = 200; x < bw; x++) {
      int c = 0;
      for (int y = 0; y < bh; y++) {
        final off = (y * bw + x) * 4;
        if (raw.getUint8(off) != 0 ||
            raw.getUint8(off + 1) != 0 ||
            raw.getUint8(off + 2) != 0)
          c++;
      }
      if (c > bestBarCount) {
        bestBarCount = c;
        bestBarX = x;
      }
    }
    // Find gradient range (exclude border and gray background)
    int firstNonBlack = bh, lastNonBlack = 0;
    for (int y = 0; y < bh; y++) {
      final off = (y * bw + bestBarX) * 4;
      final r = raw.getUint8(off),
          g = raw.getUint8(off + 1),
          b = raw.getUint8(off + 2);
      if (r != 0 || g != 0 || b != 0) {
        if (y < firstNonBlack) firstNonBlack = y;
        if (y > lastNonBlack) lastNonBlack = y;
      }
    }
    int barTop = firstNonBlack, barBottom = lastNonBlack;
    for (int y = firstNonBlack; y <= lastNonBlack; y++) {
      int sumR = 0, sumG = 0, sumB = 0, count = 0;
      for (int x = bestBarX - 3; x <= bestBarX + 3; x++) {
        if (x < 0 || x >= bw) continue;
        final off = (y * bw + x) * 4;
        final r = raw.getUint8(off),
            g = raw.getUint8(off + 1),
            b = raw.getUint8(off + 2);
        if (r == 0 && g == 0 && b == 0) continue;
        sumR += r;
        sumG += g;
        sumB += b;
        count++;
      }
      if (count == 0) continue;
      final avgR = sumR / count, avgG = sumG / count, avgB = sumB / count;
      final cMax = [avgR, avgG, avgB].reduce(math.max) / 255.0;
      final cMin = [avgR, avgG, avgB].reduce(math.min) / 255.0;
      final sat = cMax == 0 ? 0.0 : (cMax - cMin) / cMax;
      if (sat > 0.15) {
        barTop = y;
        break;
      }
    }
    for (int y = lastNonBlack; y >= firstNonBlack; y--) {
      int sumR = 0, sumG = 0, sumB = 0, count = 0;
      for (int x = bestBarX - 3; x <= bestBarX + 3; x++) {
        if (x < 0 || x >= bw) continue;
        final off = (y * bw + x) * 4;
        final r = raw.getUint8(off),
            g = raw.getUint8(off + 1),
            b = raw.getUint8(off + 2);
        if (r == 0 && g == 0 && b == 0) continue;
        sumR += r;
        sumG += g;
        sumB += b;
        count++;
      }
      if (count == 0) continue;
      final avgR = sumR / count, avgG = sumG / count, avgB = sumB / count;
      final cMax = [avgR, avgG, avgB].reduce(math.max) / 255.0;
      final cMin = [avgR, avgG, avgB].reduce(math.min) / 255.0;
      final sat = cMax == 0 ? 0.0 : (cMax - cMin) / cMax;
      if (sat > 0.15) {
        barBottom = y;
        break;
      }
    }

    print('\n═══════════════════════════════════════════════════════════════');
    print(
      '  Integration test: Service polynomial method on 13 calibration points',
    );
    print('═══════════════════════════════════════════════════════════════');

    double totalErr = 0;
    int errCount = 0;
    for (final expectedSva in _svaScaleValues) {
      final pos = _positionFromSva(expectedSva);
      final imageY = (barBottom - pos * (barBottom - barTop)).round().clamp(
        barTop,
        barBottom,
      );

      int sumR = 0, sumG = 0, sumB = 0, count = 0;
      for (int x = bestBarX - 5; x <= bestBarX + 5; x++) {
        if (x < 0 || x >= bw) continue;
        final off = (imageY * bw + x) * 4;
        final r = raw.getUint8(off),
            g = raw.getUint8(off + 1),
            b = raw.getUint8(off + 2);
        if (r == 0 && g == 0 && b == 0) continue;
        sumR += r;
        sumG += g;
        sumB += b;
        count++;
      }
      if (count == 0) continue;
      final r = sumR ~/ count, g = sumG ~/ count, b = sumB ~/ count;

      final actualSva = rgbToSva(r, g, b);
      if (actualSva == null) {
        print(
          '  SVA=${expectedSva.toStringAsFixed(3).padLeft(8)}  RGB=($r,$g,$b)  → null (unexpected)',
        );
        continue;
      }
      final err = (actualSva - expectedSva).abs() / expectedSva * 100;
      totalErr += err;
      errCount++;

      // Debug: print HSV and calcPos
      final rn2 = r / 255.0, gn2 = g / 255.0, bn2 = b / 255.0;
      final cMax2 = math.max(rn2, math.max(gn2, bn2));
      final cMin2 = math.min(rn2, math.min(gn2, bn2));
      final delta2 = cMax2 - cMin2;
      double h2 = 0.0;
      if (delta2 != 0) {
        if (cMax2 == rn2)
          h2 = 60 * (((gn2 - bn2) / delta2) % 6);
        else if (cMax2 == gn2)
          h2 = 60 * (((bn2 - rn2) / delta2) + 2);
        else
          h2 = 60 * (((rn2 - gn2) / delta2) + 4);
      }
      if (h2 < 0) h2 += 360;
      final hNorm2 = h2 > 350 ? h2 - 360 : h2;
      final s2 = cMax2 == 0 ? 0.0 : delta2 / cMax2;

      print(
        '  SVA=${expectedSva.toStringAsFixed(3).padLeft(8)}  '
        'RGB=($r,$g,$b)  '
        'H=${hNorm2.toStringAsFixed(1)}  '
        'S=${s2.toStringAsFixed(3)}  '
        'V=${cMax2.toStringAsFixed(3)}  '
        'calcSVA=${actualSva.toStringAsFixed(2).padLeft(10)}  '
        'err=${err.toStringAsFixed(1).padLeft(6)}%',
      );
    }
    final avgErr = totalErr / errCount;
    print('\n  Average error: ${avgErr.toStringAsFixed(1)}%');
    print('  (Excluding SVA=1000 gray area which is handled by S/V threshold)');

    // Single-row sampling average error ~32.8% due to GIF dithering in H plateau region
    // (SVA=2.0 and 5.0 have nearly identical H≈55.6° but different V)
    expect(avgErr, lessThan(35.0));
  });
}
