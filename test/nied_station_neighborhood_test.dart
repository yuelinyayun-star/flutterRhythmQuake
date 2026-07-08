// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutterrhythmquake/models/nied_scan_positions.dart';
import 'package:flutterrhythmquake/services/sources/shindo_color_util.dart';

import 'support/nied_replay_fixture.dart';

({int r, int g, int b, double? shindo}) _sample(
  List<int> packedRgb,
  int x,
  int y,
) {
  final rgb = packedRgb[y * 352 + x];
  final r = (rgb >> 16) & 0xFF;
  final g = (rgb >> 8) & 0xFF;
  final b = rgb & 0xFF;
  return (r: r, g: g, b: b, shindo: ShindoColorUtil.rgbaToShindo(r, g, b));
}

String _cellText(int dx, int dy, ({int r, int g, int b, double? shindo}) v) {
  final s = v.shindo == null ? 'null' : v.shindo!.toStringAsFixed(2);
  return '[${dx >= 0 ? '+' : ''}$dx,${dy >= 0 ? '+' : ''}$dy]'
      ' RGB(${v.r},${v.g},${v.b}) sh=$s';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('inspect 5x5 neighborhood around CHB015 and IBRH21', () async {
    final dir = Directory('.dart_tool\\nied_compare_recent\\202606091851');
    if (!dir.existsSync()) {
      markTestSkipped('Missing offline replay directory: ${dir.path}');
      return;
    }

    final surface = await decodeNiedGifFile(
      File('${dir.path}\\20260609185200.jma_s.gif'),
    );
    final borehole = await decodeNiedGifFile(
      File('${dir.path}\\20260609185200.jma_b.gif'),
    );
    if (surface == null || borehole == null) {
      markTestSkipped('Missing GIF frame 20260609185200');
      return;
    }

    for (final code in const ['CHB015', 'IBRH21']) {
      final pos = NiedScanPositions.positions[code]!;
      final cx = pos[0];
      final cy = pos[1];
      print('');
      print('=== $code center=($cx,$cy) surface ===');
      for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
          print(
            _cellText(dx, dy, _sample(surface.packedRgb, cx + dx, cy + dy)),
          );
        }
      }
      print('=== $code center=($cx,$cy) borehole ===');
      for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
          print(
            _cellText(dx, dy, _sample(borehole.packedRgb, cx + dx, cy + dy)),
          );
        }
      }
    }
  });
}
