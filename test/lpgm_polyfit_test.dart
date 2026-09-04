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

void main() {
  test('Generate hardcoded legend samples for LPGM', () async {
    const legendUrl =
        'https://www.lmoni.bosai.go.jp/monitor/data/data/map_img/ScaleImg2/nied_abrspmx_s_w_scale.png';
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(legendUrl));
    final resp = await req.close();
    final builder = BytesBuilder();
    await for (final chunk in resp) builder.add(chunk);
    client.close();
    final imageBytes = builder.toBytes();
    print('Downloaded: ${imageBytes.length} bytes');

    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final bw = image.width;
    final bh = image.height;
    final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    print('Image: ${bw}x$bh');

    // Find bar position
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
    int barTop = bh, barBottom = 0;
    for (int y = 0; y < bh; y++) {
      final off = (y * bw + bestBarX) * 4;
      if (raw.getUint8(off) != 0 ||
          raw.getUint8(off + 1) != 0 ||
          raw.getUint8(off + 2) != 0) {
        if (y < barTop) barTop = y;
        if (y > barBottom) barBottom = y;
      }
    }
    print('Bar: x=$bestBarX, y=$barTop~$barBottom');

    // Sample with horizontal average, every row
    final samples = <(int, int, int, double)>[];
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
      samples.add((sumR ~/ count, sumG ~/ count, sumB ~/ count, position));
    }
    print('Total samples: ${samples.length}');

    // Print as Dart code
    print('');
    print('static const _legendSamples = <(int, int, int, double)>[');
    for (final (r, g, b, pos) in samples) {
      print('    ($r, $g, $b, ${pos.toStringAsFixed(4)}),');
    }
    print('  ];');

    // Test accuracy: RGB nearest-neighbor lookup
    print('');
    print('═══════════════════════════════════════════════════════════════');
    print('  13 calibration SVA points test');
    print('═══════════════════════════════════════════════════════════════');

    for (final expectedSva in _svaScaleValues) {
      final pos = _positionFromSva(expectedSva);
      final imageY = (barBottom - pos * (barBottom - barTop)).round().clamp(
        barTop,
        barBottom,
      );

      // Get average color at this Y
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
      if (count == 0) {
        print('  SVA=$expectedSva: no data at y=$imageY');
        continue;
      }
      final r = sumR ~/ count;
      final g = sumG ~/ count;
      final b = sumB ~/ count;

      // HSV weighted nearest-neighbor lookup
      final inputHsv = _rgbToHsv(r, g, b);
      double bestDist = double.infinity;
      double bestPos = 0.0;
      for (final (sr, sg, sb, sp) in samples) {
        final sHsv = _rgbToHsv(sr, sg, sb);
        double dh;
        if (sHsv.$1 < 1 && inputHsv.$1 < 1) {
          dh = 0;
        } else {
          dh = (sHsv.$1 - inputHsv.$1).abs();
          if (dh > 180) dh = 360 - dh;
          dh /= 180.0;
        }
        final ds = (sHsv.$2 - inputHsv.$2).abs();
        final dv = (sHsv.$3 - inputHsv.$3).abs();
        final dist = dh * dh + ds * ds * 16 + dv * dv * 16;
        if (dist < bestDist) {
          bestDist = dist;
          bestPos = sp;
        }
      }
      final actualSva = _svaFromPosition(bestPos);
      final err = (actualSva - expectedSva).abs() / expectedSva * 100;

      print(
        '  SVA=${expectedSva.toStringAsFixed(3).padLeft(8)}  '
        'RGB=(${r.toString().padLeft(3)},${g.toString().padLeft(3)},${b.toString().padLeft(3)})  '
        'pos=${pos.toStringAsFixed(4)}  '
        'lookupPos=${bestPos.toStringAsFixed(4)}  '
        'calcSVA=${actualSva.toStringAsFixed(2).padLeft(10)}  '
        'err=${err.toStringAsFixed(1).padLeft(6)}%',
      );
    }
  });
}
