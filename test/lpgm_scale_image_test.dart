import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart';

/// 将 RGB 转为 HSV（各分量 0~1）
(double, double, double) rgbToHsv(int r, int g, int b) {
  final rf = r / 255.0, gf = g / 255.0, bf = b / 255.0;
  final maxV = [rf, gf, bf].reduce(math.max);
  final minV = [rf, gf, bf].reduce(math.min);
  final delta = maxV - minV;

  double h = 0;
  if (delta > 0) {
    if (maxV == rf) {
      h = ((gf - bf) / delta) % 6;
    } else if (maxV == gf) {
      h = (bf - rf) / delta + 2;
    } else {
      h = (rf - gf) / delta + 4;
    }
    h /= 6.0;
    if (h < 0) h += 1.0;
  }
  final s = maxV == 0 ? 0.0 : delta / maxV;
  final v = maxV;
  return (h, s, v);
}

void main() {
  test('分析 LPGM 色标图片结构', () async {
    // 1. 下载图片
    const url =
        'https://www.lmoni.bosai.go.jp/monitor/data/data/map_img/ScaleImg2/nied_abrspmx_s_w_scale.png';
    print('正在下载图片: $url');
    final response = await http.get(Uri.parse(url));
    expect(response.statusCode, equals(200), reason: '下载失败');

    final imageBytes = response.bodyBytes;
    print('图片大小: ${imageBytes.length} bytes');

    // 2. 解码图片
    final image = decodePng(imageBytes)!;
    final width = image.width;
    final height = image.height;
    print('图片尺寸: ${width}x$height');

    // 3. 打印整张图片的概览（每隔一定行/列采样）
    print('\n========== 图片概览 ==========');
    print('逐行扫描，找到色标条区域:');
    print('');

    // 扫描每一行，统计非白色/非透明像素的范围
    int colorBarTop = -1;
    int colorBarBottom = -1;
    int colorBarLeft = width;
    int colorBarRight = 0;

    for (int y = 0; y < height; y++) {
      int rowMinX = -1;
      int rowMaxX = -1;
      for (int x = 0; x < width; x++) {
        final p = image.getPixel(x, y);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        final a = p.a.toInt();
        // 非白色且非完全透明
        if (a > 10 && !(r > 240 && g > 240 && b > 240)) {
          if (rowMinX == -1) rowMinX = x;
          rowMaxX = x;
        }
      }
      if (rowMinX != -1) {
        if (colorBarTop == -1) colorBarTop = y;
        colorBarBottom = y;
        if (rowMinX < colorBarLeft) colorBarLeft = rowMinX;
        if (rowMaxX > colorBarRight) colorBarRight = rowMaxX;
      }
    }

    print('非白色/非透明像素包围盒: left=$colorBarLeft, top=$colorBarTop, '
        'right=$colorBarRight, bottom=$colorBarBottom');

    // 4. 更精细地找色标条——色标条通常是连续的彩色渐变
    // 扫描每列，找到颜色变化最丰富的列区间
    print('\n========== 逐列分析（找色标条水平范围）==========');
    // 对每列，统计不同颜色的数量（简化：统计R通道值种类数）
    final colColorVariety = <int, int>{};
    for (int x = 0; x < width; x++) {
      final rValues = <int>{};
      for (int y = colorBarTop; y <= colorBarBottom; y++) {
        final p = image.getPixel(x, y);
        rValues.add(p.r.toInt());
      }
      colColorVariety[x] = rValues.length;
    }

    // 找到颜色变化最丰富的连续区间
    int barLeft = -1;
    int barRight = -1;
    int maxVariety = 0;
    for (int x = 0; x < width; x++) {
      if (colColorVariety[x]! > 5) {
        if (barLeft == -1) barLeft = x;
        barRight = x;
      }
    }
    print('色标条水平范围: left=$barLeft, right=$barRight');
    print('色标条宽度: ${barRight - barLeft + 1}');

    // 5. 找色标条的垂直范围——从色标条中心列采样
    final barCenterX = (barLeft + barRight) ~/ 2;
    print('\n========== 色标条中心列(x=$barCenterX)逐行颜色 ==========');
    print('y\tR\tG\tB\tA\tH\tS\tV');

    int gradientTop = -1;
    int gradientBottom = -1;

    for (int y = 0; y < height; y++) {
      final p = image.getPixel(barCenterX, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      final a = p.a.toInt();
      final (h, s, v) = rgbToHsv(r, g, b);

      // 跳过白色/透明行
      if (a < 10 || (r > 245 && g > 245 && b > 245)) continue;

      // 找到渐变开始和结束
      if (s > 0.05 || v < 0.9) {
        if (gradientTop == -1) gradientTop = y;
        gradientBottom = y;
      }

      // 只打印关键行
      if (y <= 5 ||
          y >= height - 5 ||
          (y >= gradientTop - 2 && y <= gradientTop + 5) ||
          (y >= gradientBottom - 5 && y <= gradientBottom + 2) ||
          y % 20 == 0) {
        print('$y\t$r\t$g\t$b\t$a\t${h.toStringAsFixed(3)}\t${s.toStringAsFixed(3)}\t${v.toStringAsFixed(3)}');
      }
    }

    print('\n渐变色标条垂直范围: top=$gradientTop, bottom=$gradientBottom');
    print('渐变色标条高度: ${gradientBottom - gradientTop + 1}');

    // 6. 在色标条的13个标定点位置采样颜色
    print('\n========== 13个标定点颜色采样 ==========');
    print('position\tSVA\tR\tG\tB\tH\tS\tV');

    final barHeight = gradientBottom - gradientTop + 1;
    for (int i = 0; i <= 12; i++) {
      final pos = i / 12.0;
      // position=0 对应底部(SVA=0), position=1 对应顶部(SVA=1000)
      // 在图片中，顶部是y小的位置
      final y = gradientBottom - (pos * (barHeight - 1)).round();
      final p = image.getPixel(barCenterX, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      final a = p.a.toInt();
      final (h, s, v) = rgbToHsv(r, g, b);
      final sva = (pos * 1000).round();
      print('${pos.toStringAsFixed(4)}\t$sva\t$r\t$g\t$b\t$a\t${h.toStringAsFixed(3)}\t${s.toStringAsFixed(3)}\t${v.toStringAsFixed(3)}');
    }

    // 7. 特别关注顶部区域（position 0.9~1.0），逐行打印颜色
    print('\n========== 顶部区域逐行分析 (position 0.9~1.0) ==========');
    print('y\tpos\tR\tG\tB\tH\tS\tV\t描述');

    final topStart = gradientBottom - ((0.9 * (barHeight - 1)).round());
    for (int y = topStart; y >= gradientTop; y--) {
      final pos = (gradientBottom - y) / (barHeight - 1);
      final p = image.getPixel(barCenterX, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      final (h, s, v) = rgbToHsv(r, g, b);

      String desc = '';
      if (s < 0.1 && v < 0.3) {
        desc = '深灰/黑';
      } else if (s < 0.1 && v >= 0.3 && v < 0.7) {
        desc = '灰色';
      } else if (s < 0.1 && v >= 0.7) {
        desc = '浅灰/白';
      } else if (h > 0.95 || h < 0.05) {
        desc = '红色';
      } else if (h >= 0.05 && h < 0.1) {
        desc = '橙红';
      } else if (h >= 0.1 && h < 0.2) {
        desc = '橙/黄';
      } else if (h >= 0.2 && h < 0.4) {
        desc = '绿';
      } else if (h >= 0.4 && h < 0.7) {
        desc = '蓝/青';
      } else {
        desc = '紫/品红';
      }

      print('$y\t${pos.toStringAsFixed(4)}\t$r\t$g\t$b\t${h.toStringAsFixed(3)}\t${s.toStringAsFixed(3)}\t${v.toStringAsFixed(3)}\t$desc');
    }

    // 8. 检查色标条旁边是否有刻度线
    print('\n========== 检查刻度线 ==========');
    // 刻度线通常在色标条的左侧或右侧，是黑色/深色细线
    // 扫描色标条左右各10像素的区域

    // 右侧刻度线检测
    print('--- 色标条右侧区域 (x=${barRight + 1}~${barRight + 15}) ---');
    for (int x = barRight + 1; x < math.min(barRight + 16, width); x++) {
      int darkPixels = 0;
      final darkYPositions = <int>[];
      for (int y = gradientTop; y <= gradientBottom; y++) {
        final p = image.getPixel(x, y);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        if (r < 80 && g < 80 && b < 80) {
          darkPixels++;
          darkYPositions.add(y);
        }
      }
      if (darkPixels > 0) {
        print('  x=$x: $darkPixels 个暗色像素, y范围=${darkYPositions.first}~${darkYPositions.last}');
        // 打印刻度线的y位置（连续暗色像素的起始位置）
        final tickYPositions = <int>[];
        int? prevY;
        for (final y in darkYPositions) {
          if (prevY == null || y - prevY > 2) {
            tickYPositions.add(y);
          }
          prevY = y;
        }
        print('    刻度线y位置: $tickYPositions');
      }
    }

    // 左侧刻度线检测
    print('--- 色标条左侧区域 (x=${barLeft - 15}~${barLeft - 1}) ---');
    for (int x = math.max(0, barLeft - 15); x < barLeft; x++) {
      int darkPixels = 0;
      final darkYPositions = <int>[];
      for (int y = gradientTop; y <= gradientBottom; y++) {
        final p = image.getPixel(x, y);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        if (r < 80 && g < 80 && b < 80) {
          darkPixels++;
          darkYPositions.add(y);
        }
      }
      if (darkPixels > 0) {
        print('  x=$x: $darkPixels 个暗色像素, y范围=${darkYPositions.first}~${darkYPositions.last}');
        final tickYPositions = <int>[];
        int? prevY;
        for (final y in darkYPositions) {
          if (prevY == null || y - prevY > 2) {
            tickYPositions.add(y);
          }
          prevY = y;
        }
        print('    刻度线y位置: $tickYPositions');
      }
    }

    // 9. 保存图片到本地以便参考
    final file = File('test/lpgm_scale.png');
    await file.writeAsBytes(imageBytes);
    print('\n图片已保存到: ${file.absolute.path}');

    // 10. 综合分析色标条上方是否有边框/背景
    print('\n========== 色标条上方区域分析 ==========');
    for (int y = math.max(0, gradientTop - 10); y <= gradientTop + 2; y++) {
      final colors = <String>[];
      for (int x = barLeft; x <= barRight; x += 3) {
        final p = image.getPixel(x, y);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        colors.add('($r,$g,$b)');
      }
      print('y=$y: ${colors.join(' ')}');
    }

    // 11. 综合分析色标条下方区域
    print('\n========== 色标条下方区域分析 ==========');
    for (int y = gradientBottom - 2; y <= math.min(height - 1, gradientBottom + 10); y++) {
      final colors = <String>[];
      for (int x = barLeft; x <= barRight; x += 3) {
        final p = image.getPixel(x, y);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        colors.add('($r,$g,$b)');
      }
      print('y=$y: ${colors.join(' ')}');
    }

    // 12. 完整逐行打印色标条中心列颜色（用于精确分析）
    print('\n========== 色标条完整逐行颜色 (x=$barCenterX) ==========');
    print('y\tpos\tR\tG\tB\tH\tS\tV');
    for (int y = gradientTop; y <= gradientBottom; y++) {
      final pos = (gradientBottom - y) / (barHeight - 1);
      final p = image.getPixel(barCenterX, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      final (h, s, v) = rgbToHsv(r, g, b);
      print('$y\t${pos.toStringAsFixed(4)}\t$r\t$g\t$b\t${h.toStringAsFixed(3)}\t${s.toStringAsFixed(3)}\t${v.toStringAsFixed(3)}');
    }
  });
}
