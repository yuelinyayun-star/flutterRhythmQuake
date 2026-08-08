import 'dart:async';

import 'package:euc/euc.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

/// Hi-net AQUA CMT（震源机制解）サービス
///
/// 数据来源：防災科学技術研究所 Hi-net AQUA 震源メカニズム解カタログ
/// URL: https://www.hinet.bosai.go.jp/AQUA/aqua_catalogue.php?LANG=ja&y=YYYY&m=MM
///
/// AQUA (Accurate and QUick Analysis System for Source Parameters) 是 NIED
/// 运行的自动震源参数解析系统。本服务通过 HTTP GET 按月轮询目录页，解析 HTML
/// 表格获取 CMT 事件。
///
/// 字段说明：
/// - 震源时：JST（日本标准时间），本服务转换为 UTC
/// - 震源地：日文区域名
/// - 緯度/経度：十进制度 N/E 格式
/// - 深さ：km（AQUA-CMT 时为矩心深度）
/// - Mw：矩震级
/// - 走向/傾斜角/すべり角：两组断层面参数，用 "/" 分隔
/// - 品質：VR%（方差缩减）
/// - 観測点数：参与反演的 Hi-net 台站数
/// - 種別：C = AQUA-CMT, M = AQUA-MT
class HinetAquaCmtService {
  static final HinetAquaCmtService _instance = HinetAquaCmtService._internal();
  factory HinetAquaCmtService() => _instance;
  HinetAquaCmtService._internal();

  static const String _baseUrl =
      'https://www.hinet.bosai.go.jp/AQUA/aqua_catalogue.php';

  void Function(List<Map<String, dynamic>>)? onListUpdated;

  Timer? _timer;
  bool _initialized = false;
  bool _fetching = false;

  void start() {
    if (_timer?.isActive == true) return;
    _timer = Timer.periodic(const Duration(seconds: 300), (_) => fetch());
    fetch();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  bool get initialized => _initialized;

  Future<void> fetch() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final now = DateTime.now().toUtc();
      // 轮询当前月和上个月（跨月边界也能拿到最近事件）
      final months = <DateTime>[
        DateTime.utc(now.year, now.month, 1),
        DateTime.utc(now.year, now.month - 1, 1),
      ];

      final allItems = <Map<String, dynamic>>[];
      for (final month in months) {
        final items = await _fetchMonth(month.year, month.month);
        allItems.addAll(items);
      }

      // 按发震时刻降序排列，取前 50 条
      allItems.sort((a, b) {
        final ta = a['originTime']?.toString() ?? '';
        final tb = b['originTime']?.toString() ?? '';
        return tb.compareTo(ta);
      });
      if (allItems.length > 50) allItems.removeRange(50, allItems.length);

      onListUpdated?.call(allItems);
      _initialized = true;
    } catch (e) {
      print('Hi-net AQUA CMT fetch error: $e');
    } finally {
      _fetching = false;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchMonth(int year, int month) async {
    final url =
        '$_baseUrl?LANG=ja&y=$year&m=${month.toString().padLeft(2, '0')}';
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) {
      print('Hi-net AQUA CMT list HTTP ${r.statusCode}');
      return [];
    }
    final body = EucJP().decode(r.bodyBytes);
    return _parseHtml(body);
  }

  List<Map<String, dynamic>> _parseHtml(String html) {
    final result = <Map<String, dynamic>>[];
    try {
      // 每行数据：<tr id="lst20260804000079" ...><td>...</td>...</tr>
      final rowRegex = RegExp(
        r'<tr\s+id="lst(\d+)"[^>]*>(.*?)</tr>',
        dotAll: true,
      );
      final cellRegex = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true);

      for (final rowMatch in rowRegex.allMatches(html)) {
        final rawId = rowMatch.group(1) ?? '';
        final rowHtml = rowMatch.group(2) ?? '';
        final cells = cellRegex
            .allMatches(rowHtml)
            .map((m) => _stripTags(m.group(1) ?? '').trim())
            .toList();
        if (cells.length < 12) continue;

        final item = _buildItem(rawId, cells);
        if (item != null) result.add(item);
      }
    } catch (e) {
      print('Hi-net AQUA CMT parse error: $e');
    }
    return result;
  }

  Map<String, dynamic>? _buildItem(String rawId, List<String> cells) {
    try {
      // 只接入 AQUA-CMT（C 类型），跳过 AQUA-MT（M 类型）
      final aquaType = cells.length > 11 ? cells[11].trim() : '';
      if (aquaType != 'C') return null;

      final originTime = _parseJstTime(cells[0]);
      final lat = _parseCoordinate(cells[2], isLat: true);
      final lng = _parseCoordinate(cells[3], isLat: false);
      if (originTime == null || lat == null || lng == null) return null;

      final depth = _parseDepth(cells[4]);
      final mw = double.tryParse(cells[5]);
      final quality = double.tryParse(cells[9]);
      // VR% 低于 50 的解视为低质量，跳过
      if (quality != null && quality < 50) return null;

      final nodalPlane1 = _parseNodalPlane(cells[6], cells[7], cells[8], 0);
      final nodalPlane2 = _parseNodalPlane(cells[6], cells[7], cells[8], 1);

      return {
        'eventId': 'hinet_aqua_cmt_$rawId',
        'originTime': originTime.toIso8601String(),
        'latitude': lat,
        'longitude': lng,
        'depth': depth ?? -1,
        'magnitude': mw ?? -1,
        'centroidDepth': depth,
        'location': cells[1],
        'nodalPlane1': nodalPlane1,
        'nodalPlane2': nodalPlane2,
        'quality': quality ?? 0,
        'stationCount': int.tryParse(cells[10]) ?? 0,
        'cmtMetadata': {
          'varianceReduction': quality,
          'stationCount': int.tryParse(cells[10]),
        },
        'aquaType': cells[11],
        'reviewType': 'auto',
      };
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseJstTime(String text) {
    try {
      final match = RegExp(
        r'(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})',
      ).firstMatch(text.trim());
      if (match == null) return null;
      final y = int.parse(match.group(1)!);
      final mo = int.parse(match.group(2)!);
      final d = int.parse(match.group(3)!);
      final h = int.parse(match.group(4)!);
      final mi = int.parse(match.group(5)!);
      final s = int.parse(match.group(6)!);
      // 输入是日本时间(UTC+9)，先按 UTC 构造名义上的 JST 分量，
      // 再减去 9 小时得到真正 UTC。与 JMA CMT 的 _parseJapanTime 保持一致。
      final jstUtc = DateTime.utc(y, mo, d, h, mi, s);
      return jstUtc.subtract(const Duration(hours: 9));
    } catch (_) {
      return null;
    }
  }

  double? _parseCoordinate(String text, {required bool isLat}) {
    try {
      final t = text.trim();
      final suffix = isLat ? r'[NS]' : r'[EW]';
      final match = RegExp(r'(\d+\.?\d*)\s*' + suffix).firstMatch(t);
      if (match == null) return null;
      final value = double.parse(match.group(1)!);
      final negative = isLat ? t.contains('S') : t.contains('W');
      return negative ? -value : value;
    } catch (_) {
      return null;
    }
  }

  double? _parseDepth(String text) {
    try {
      final match = RegExp(r'(\d+\.?\d*)\s*km').firstMatch(text.trim());
      return match != null ? double.parse(match.group(1)!) : null;
    } catch (_) {
      return null;
    }
  }

  /// 从 "134.2°/277.4°", "3.9°/86.9°", "-53.3°/-92.3°" 中提取第 index 组
  String _parseNodalPlane(
    String strikeStr,
    String dipStr,
    String rakeStr,
    int index,
  ) {
    try {
      final strikes = _splitAngle(strikeStr);
      final dips = _splitAngle(dipStr);
      final rakes = _splitAngle(rakeStr);
      if (index < strikes.length &&
          index < dips.length &&
          index < rakes.length) {
        return '${strikes[index]}/${dips[index]}/${rakes[index]}';
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  List<String> _splitAngle(String text) {
    return text
        // Keep the numeric characters in the HTML entity intact. A character
        // class containing "&#730;" also matches and removes 7, 3, and 0.
        .replaceAll(RegExp(r'(?:°|˚|&#730;)'), '')
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  @visibleForTesting
  List<String> splitAngleForTest(String text) => _splitAngle(text);

  String _stripTags(String html) {
    return _decodeEntities(html.replaceAll(RegExp(r'<[^>]*>'), ''));
  }

  String _decodeEntities(String text) {
    return text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#730;', '°');
  }
}
