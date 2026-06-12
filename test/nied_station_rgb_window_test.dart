import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:flutterrhythmquake/models/nied_scan_positions.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';
import 'package:flutterrhythmquake/services/sources/shindo_color_util.dart';

class _DecodedGifFrame {
  final List<int> packedRgb;
  const _DecodedGifFrame({required this.packedRgb});
}

Future<_DecodedGifFrame?> _decodeGifFile(File file) async {
  if (!file.existsSync()) return null;
  final bytes = await file.readAsBytes();
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (byteData == null) {
    image.dispose();
    codec.dispose();
    return null;
  }

  final pixels = List<int>.filled(image.width * image.height, 0);
  for (var i = 0; i < pixels.length; i++) {
    final offset = i * 4;
    final r = byteData.getUint8(offset);
    final g = byteData.getUint8(offset + 1);
    final b = byteData.getUint8(offset + 2);
    pixels[i] = (r << 16) | (g << 8) | b;
  }

  image.dispose();
  codec.dispose();
  return _DecodedGifFrame(packedRgb: pixels);
}

String _formatTimeKey(DateTime jst) {
  final ymd =
      '${jst.year}${jst.month.toString().padLeft(2, '0')}${jst.day.toString().padLeft(2, '0')}';
  final hms =
      '${jst.hour.toString().padLeft(2, '0')}${jst.minute.toString().padLeft(2, '0')}${jst.second.toString().padLeft(2, '0')}';
  return '$ymd$hms';
}

({int r, int g, int b}) _rgbAt(List<int> packedRgb, int x, int y) {
  final rgb = packedRgb[y * 352 + x];
  return (r: (rgb >> 16) & 0xFF, g: (rgb >> 8) & 0xFF, b: rgb & 0xFF);
}

String _fmtLine(
  String source,
  String code,
  String network,
  int x,
  int y,
  ({int r, int g, int b}) rgb,
) {
  final shindo = ShindoColorUtil.rgbaToShindo(rgb.r, rgb.g, rgb.b);
  final shText = shindo == null ? 'null' : shindo.toStringAsFixed(3);
  return '$source $code($network) xy=($x,$y) RGB(${rgb.r},${rgb.g},${rgb.b}) shindo=$shText';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('print raw RGB for key stations around 2026-06-09 18:52 JST', () async {
    final dir = Directory('.dart_tool\\nied_compare_recent\\202606091851');
    if (!dir.existsSync()) {
      markTestSkipped('Missing offline replay directory: ${dir.path}');
      return;
    }

    const watchCodes = ['OSK006', 'CHB015', 'IBRH21'];
    final watchMeta = <String, Map<String, dynamic>>{};
    for (final s in NiedStationDb.stations) {
      final code = s['code'] as String;
      if (watchCodes.contains(code)) {
        watchMeta[code] = s;
      }
    }

    final start = DateTime(2026, 6, 9, 18, 52, 0);
    const seconds = 4;
    print('');
    print('=== Raw RGB compare 2026-06-09 18:52 JST ===');
    for (var i = 0; i < seconds; i++) {
      final jst = start.add(Duration(seconds: i));
      final stamp = _formatTimeKey(jst);
      final surface = await _decodeGifFile(File('${dir.path}\\$stamp.jma_s.gif'));
      final borehole = await _decodeGifFile(File('${dir.path}\\$stamp.jma_b.gif'));
      if (surface == null) continue;
      print(stamp);
      for (final code in watchCodes) {
        final pos = NiedScanPositions.positions[code]!;
        final meta = watchMeta[code]!;
        final network = meta['network'] as String? ?? 'K-NET';
        final x = pos[0];
        final y = pos[1];
        final sRgb = _rgbAt(surface.packedRgb, x, y);
        print(_fmtLine('surface ', code, network, x, y, sRgb));
        if (borehole != null) {
          final bRgb = _rgbAt(borehole.packedRgb, x, y);
          print(_fmtLine('borehole', code, network, x, y, bRgb));
        }
      }
      print('---');
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
