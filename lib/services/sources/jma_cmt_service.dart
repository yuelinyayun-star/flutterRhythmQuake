import 'dart:async';

import 'package:http/http.dart' as http;

/// JMA CMT 解（精査後）サービス
///
/// 数据来源：気象庁 CMT 解リスト
/// （https://ds.data.jma.go.jp/svd/eqev/data/mech/cmt/top.html）
///
/// 该页面为 HTML 表格（非 REST API），本服务通过 HTTP 轮询 + 正则解析
/// 提取最新 10 个地震的 CMT 解。JMA CMT 仅人工复核（精査後），
/// 翌日以后发布。
///
/// 列序（参照 JMA 页面表头）：
///  0: 発生時刻(日本时间)  1: 緯度(度分)  2: 経度(度分)  3: 深さ(km)
///  4: M                   5: 震央地域名   6: Mw
///  7: 走向1   8: 傾斜1   9: すべり角1
/// 10: 走向2  11: 傾斜2  12: すべり角2
/// 13: 詳細リンク
///
/// 字段映射参见 [quake_event_adapter.dart] 的 `_jmaCmt` 方法。
class JmaCmtService {
  static final JmaCmtService _instance = JmaCmtService._internal();
  factory JmaCmtService() => _instance;
  JmaCmtService._internal();

  /// JMA CMT 解リスト（最新 10 个）
  static const String _url =
      'https://ds.data.jma.go.jp/svd/eqev/data/mech/cmt/top.html';

  /// 列表数据回调（全量字段 map 列表）
  void Function(List<Map<String, dynamic>>)? onListUpdated;
  void Function(bool connected)? onStatusChanged;

  Timer? _timer;
  bool _initialized = false;
  final Map<String, Map<String, dynamic>> _detailCache = {};

  /// 启动轮询（5 分钟一次）
  void start() {
    if (_timer?.isActive == true) return;
    _timer = Timer.periodic(const Duration(seconds: 300), (_) => fetch());
    fetch();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 标记是否已完成首次加载
  bool get initialized => _initialized;

  Future<void> fetch() async {
    try {
      final resp = await http
          .get(Uri.parse(_url))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        onStatusChanged?.call(false);
        print('JMA CMT HTTP ${resp.statusCode}');
        return;
      }
      final list = _parseHtml(resp.body);
      final currentDetailPaths = <String>{};
      for (final item in list) {
        final detailPath = item.remove('_detailPath')?.toString() ?? '';
        if (detailPath.isEmpty) continue;
        currentDetailPaths.add(detailPath);
        final cached = _detailCache[detailPath];
        if (cached != null) {
          item.addAll(cached);
          continue;
        }
        final detail = await _fetchDetail(detailPath);
        if (detail != null) {
          _detailCache[detailPath] = detail;
          item.addAll(detail);
        }
      }
      _detailCache.removeWhere((path, _) => !currentDetailPaths.contains(path));
      if (list.isNotEmpty) {
        onListUpdated?.call(list);
        _initialized = true;
      }
      onStatusChanged?.call(true);
    } catch (e) {
      print('JMA CMT fetch error: $e');
      onStatusChanged?.call(false);
    }
  }

  /// 解析 JMA CMT HTML 表格
  List<Map<String, dynamic>> _parseHtml(String html) {
    final result = <Map<String, dynamic>>[];
    try {
      final rowRegex = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true);
      final cellRegex = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true);
      final rows = rowRegex.allMatches(html);
      for (final rowMatch in rows) {
        final rowHtml = rowMatch.group(1) ?? '';
        final cells = cellRegex
            .allMatches(rowHtml)
            .map((m) => _stripTags(m.group(1) ?? '').trim())
            .toList();
        // 跳过表头行（单元格数不足或首列非日期）
        if (cells.length < 13) continue;
        if (!_looksLikeDateTime(cells[0])) continue;
        final item = _buildItem(cells, detailPath: _detailPathFromRow(rowHtml));
        if (item != null) result.add(item);
      }
    } catch (e) {
      print('JMA CMT parse error: $e');
    }
    return result;
  }

  /// 将单元格列表构造为事件字段 map
  Map<String, dynamic>? _buildItem(
    List<String> cells, {
    required String? detailPath,
  }) {
    try {
      final originTime = _parseJapanTime(cells[0]);
      final lat = _parseDms(cells[1]);
      final lng = _parseDms(cells[2]);
      final depth = _parseDepth(cells[3]);
      final quickMag = double.tryParse(cells[4]);
      final location = cells[5];
      final mwMag = double.tryParse(cells[6]);
      if (originTime == null || lat == null || lng == null) return null;
      // Mw 优先，fallback M
      final magnitude = mwMag ?? quickMag ?? -1;
      final eventId =
          'jma_cmt_${originTime.toIso8601String()}_${lat.toStringAsFixed(3)}_${lng.toStringAsFixed(3)}';
      return {
        'eventId': eventId,
        'originTime': originTime.toIso8601String(),
        'latitude': lat,
        'longitude': lng,
        'depth': depth ?? -1,
        'magnitude': magnitude,
        'centroidDepth': null,
        'nodalPlane1':
            '${cells[7].trim()}/${cells[8].trim()}/${cells[9].trim()}',
        'nodalPlane2':
            '${cells[10].trim()}/${cells[11].trim()}/${cells[12].trim()}',
        'reviewType': 'reviewed',
        'location': location,
        if (detailPath != null) '_detailPath': detailPath,
      };
    } catch (_) {
      return null;
    }
  }

  String? _detailPathFromRow(String rowHtml) {
    final match = RegExp(
      r'''<a\s+[^>]*href=["']([^"']*\.html)["']''',
      caseSensitive: false,
    ).firstMatch(rowHtml);
    final href = match?.group(1)?.trim() ?? '';
    if (!href.startsWith('./fig/cmt') || !href.endsWith('.html')) return null;
    return href;
  }

  Future<Map<String, dynamic>?> _fetchDetail(String detailPath) async {
    try {
      final uri = Uri.parse(_url).resolve(detailPath);
      final resp = await http.get(uri).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;

      final tables = RegExp(
        r'<table\s+class="mech mtx data">(.*?)</table>',
        dotAll: true,
      ).allMatches(resp.body).toList();
      // The third data table is JMA's moment-tensor table.
      if (tables.length < 3) return null;
      List<String> tableCells(int index) =>
          RegExp(
            r'<t[hd][^>]*>(.*?)</t[hd]>',
            dotAll: true,
          ).allMatches(tables[index].group(1) ?? '').map((match) {
            return _stripTags(match.group(1) ?? '').trim();
          }).toList();

      final centroidCells = tableCells(1);
      final tensorCells = tableCells(2);
      final qualityCells = tables.length > 4 ? tableCells(4) : const <String>[];
      if (tensorCells.length < 20 || centroidCells.length < 10) return null;

      final values = <String, dynamic>{
        'mrr': tensorCells[11],
        'mtt': tensorCells[12],
        'mff': tensorCells[13],
        'mrt': tensorCells[14],
        'mrf': tensorCells[15],
        'mtf': tensorCells[16],
      };
      if (values.values.any(
        (value) => double.tryParse(value.toString()) == null,
      )) {
        return null;
      }
      final centroidLatitude = _parseDms(centroidCells[6]);
      final centroidLongitude = _parseDms(centroidCells[7]);
      final centroidDepth = _parseDepth(centroidCells[8]);
      final stationCount = qualityCells.length >= 2
          ? int.tryParse(
              RegExp(r'\d+').firstMatch(qualityCells[1])?.group(0) ?? '',
            )
          : null;
      final varianceReduction = qualityCells.length >= 4
          ? double.tryParse(
              RegExp(r'\d+(?:\.\d+)?').firstMatch(qualityCells[3])?.group(0) ??
                  '',
            )
          : null;
      return {
        'centroidDepth': centroidDepth,
        'momentTensor': values,
        'momentTensorConvention': 'rtp',
        'cmtMetadata': {
          'centroidTime': centroidCells[5],
          'centroidLatitude': centroidLatitude,
          'centroidLongitude': centroidLongitude,
          'scalarMoment': tensorCells[10],
          'scalarMomentExponent': int.tryParse(tensorCells[17]),
          'scalarMomentUnit': tensorCells[18],
          'nonDoubleCoupleRatio': double.tryParse(tensorCells[19]),
          'stationCount': stationCount,
          'varianceReduction': varianceReduction,
        },
      };
    } catch (e) {
      print('JMA CMT detail fetch error: $e');
      return null;
    }
  }

  /// 解析日本时间字符串（如 "2026-07-28 23:01:57.2"）为 UTC DateTime
  ///
  /// JMA 页面时间为日本时间（UTC+9），此方法转 UTC 后返回。
  DateTime? _parseJapanTime(String text) {
    try {
      final decoded = _decodeEntities(text).replaceAll('/', '-');
      final match = RegExp(
        r'(\d{4})-(\d{1,2})-(\d{1,2})[ T](\d{1,2}):(\d{1,2}):(\d{1,2})',
      ).firstMatch(decoded);
      if (match == null) return null;
      final y = int.parse(match.group(1)!);
      final mo = int.parse(match.group(2)!);
      final d = int.parse(match.group(3)!);
      final h = int.parse(match.group(4)!);
      final mi = int.parse(match.group(5)!);
      final s = int.parse(match.group(6)!);
      // 输入是日本时间(UTC+9)，先按 UTC 构造再减 9 小时得到真正 UTC
      final japanUtc = DateTime.utc(y, mo, d, h, mi, s);
      return japanUtc.subtract(const Duration(hours: 9));
    } catch (_) {
      return null;
    }
  }

  /// 解析度分格式（如 "32度29.8分N" / "130度34.7分E"）为十进制度
  double? _parseDms(String text) {
    try {
      final match = RegExp(r'(\d+)度(\d+\.?\d*)分([NSEW])').firstMatch(text);
      if (match == null) {
        // 某些事件可能无度分格式，尝试纯数字
        return double.tryParse(text);
      }
      final deg = double.parse(match.group(1)!);
      final min = double.parse(match.group(2)!);
      final hemi = match.group(3)!;
      var value = deg + min / 60.0;
      if (hemi == 'S' || hemi == 'W') value = -value;
      return value;
    } catch (_) {
      return null;
    }
  }

  /// 解析深度（如 "14km"）为 double
  double? _parseDepth(String text) {
    try {
      final match = RegExp(r'(\d+\.?\d*)').firstMatch(text);
      if (match == null) return null;
      return double.parse(match.group(1)!);
    } catch (_) {
      return null;
    }
  }

  bool _looksLikeDateTime(String text) {
    return RegExp(r'\d{4}-\d{1,2}-\d{1,2}').hasMatch(text);
  }

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
        .replaceAll('&#39;', "'");
  }
}
