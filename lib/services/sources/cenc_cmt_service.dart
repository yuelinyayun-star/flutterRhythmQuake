import 'dart:async';

import 'package:http/http.dart' as http;

import '../../utils/fe_regions.dart';

/// CENC 大震震源机制 CMT 产品服务
///
/// 数据来源：data.earthquake.cn 大震震源机制 CMT 产品
/// （https://data.earthquake.cn/datashare/report.shtml?PAGEID=earthquake_dzzyjz）
///
/// 该页面为 HTML 表单查询（非 REST API），本服务通过 HTTP 轮询 + 正则解析
/// 提取表格中的事件行。CENC 提供两套目录：
/// - 自动产出（cmtype=auto）：震后 5~35 分钟产出，时效优先
/// - 人工复核（cmtype=review）：地震学家复核，可靠性优先，参数会修正
///
/// 合并策略：人工复核覆盖自动产出（按 eventId）。每次轮询产出合并后的
/// `List<Map<String, dynamic>>`，由 [QuakeProvider] 调用
/// [QuakeEventAdapter.convert]（source='cencCmt'）转为 [UnifiedQuakeData]。
///
/// 字段映射参见 [quake_event_adapter.dart] 的 `_cencCmt` 方法。
class CencCmtService {
  static final CencCmtService _instance = CencCmtService._internal();
  factory CencCmtService() => _instance;
  CencCmtService._internal();

  /// CENC CMT 产品页面（HTML 表单查询）
  static const String _baseUrl =
      'https://data.earthquake.cn/datashare/report.shtml';

  /// 列表数据回调（合并后的全量字段 map 列表）
  void Function(List<Map<String, dynamic>>)? onListUpdated;

  /// HTTP 轮询状态回调
  void Function(bool connected)? onStatusChanged;

  Timer? _timer;
  bool _initialized = false;

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

  /// 标记是否已完成首次加载（首次只填充 eqlist 桶，不推送主 UI）
  bool get initialized => _initialized;

  /// 拉取并合并自动产出与人工复核两套目录
  Future<void> fetch() async {
    try {
      final results = await Future.wait([
        _fetchCatalog('auto', 'automatic'),
        _fetchCatalog('review', 'reviewed'),
      ]);
      final autoList = results[0];
      final reviewList = results[1];

      // 合并：人工复核覆盖自动产出（按 eventId）
      final merged = <String, Map<String, dynamic>>{};
      for (final item in autoList) {
        final id = item['eventId']?.toString() ?? '';
        if (id.isNotEmpty) merged[id] = item;
      }
      for (final item in reviewList) {
        final id = item['eventId']?.toString() ?? '';
        if (id.isNotEmpty) merged[id] = item;
      }

      final list = merged.values.toList();
      if (list.isNotEmpty) {
        onListUpdated?.call(list);
        // 仅在有数据时标记已初始化，避免首次 fetch 为空时下次
        // 有数据走增量推送（应走首次填充 eqlist 桶逻辑）
        _initialized = true;
      }
      onStatusChanged?.call(true);
    } catch (e) {
      print('CENC CMT fetch error: $e');
      onStatusChanged?.call(false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchCatalog(
    String cmtype,
    String reviewType,
  ) async {
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl?PAGEID=earthquake_dzzyjz&cmtype=$cmtype'))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        print('CENC CMT HTTP ${resp.statusCode} ($cmtype)');
        return [];
      }
      return _parseHtml(resp.body, reviewType);
    } catch (e) {
      print('CENC CMT $cmtype fetch error: $e');
      return [];
    }
  }

  /// 解析 CENC CMT HTML 表格
  ///
  /// 提取 <tr> 行中的 <td> 单元格，按列序映射到字段。
  /// 列序（参照 CENC 页面表头，若页面结构变化需调整）：
  ///  0: 发震时刻(北京时间)   1: 震中纬度    2: 震中经度    3: 震源深度(km)
  ///  4: 速报震级              5: Mw震级      6: 矩心深度(km)
  ///  7: 断层面1走向           8: 断层面1倾角  9: 断层面1滑动角
  /// 10: 断层面2走向          11: 断层面2倾角 12: 断层面2滑动角
  List<Map<String, dynamic>> _parseHtml(String html, String reviewType) {
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
        final item = _buildItem(cells, reviewType);
        if (item != null) result.add(item);
      }
    } catch (e) {
      print('CENC CMT parse error ($reviewType): $e');
    }
    return result;
  }

  /// 将单元格列表构造为事件字段 map
  Map<String, dynamic>? _buildItem(List<String> cells, String reviewType) {
    try {
      final originTime = _parseBeijingTime(cells[0]);
      final lat = double.tryParse(cells[1]);
      final lng = double.tryParse(cells[2]);
      final depth = double.tryParse(cells[3]);
      final quickMag = double.tryParse(cells[4]);
      final mwMag = double.tryParse(cells[5]);
      final centroidDepth = double.tryParse(cells[6]);
      if (originTime == null || lat == null || lng == null) return null;
      // Mw 优先，fallback 速报震级
      final magnitude = mwMag ?? quickMag ?? -1;
      // CENC 的自动/正式解可能修订坐标；用官方发震时刻保持为同一个事件。
      final eventId = 'cenc_cmt_${originTime.toIso8601String()}';
      // 优先使用已加载的国内地名索引，未命中时保留既有全球区域回退。
      final location = getFEName(lat, lng);
      return {
        'eventId': eventId,
        'originTime': originTime.toIso8601String(),
        'latitude': lat,
        'longitude': lng,
        'depth': depth ?? -1,
        'magnitude': magnitude,
        'centroidDepth': centroidDepth,
        'nodalPlane1': '${cells[7]}/${cells[8]}/${cells[9]}',
        'nodalPlane2': '${cells[10]}/${cells[11]}/${cells[12]}',
        'reviewType': reviewType,
        'location': location,
      };
    } catch (_) {
      return null;
    }
  }

  /// 解析北京时间字符串（如 "2023-12-18 23:59:30"）为 UTC DateTime
  ///
  /// CENC 页面时间为北京时间（UTC+8），此方法转 UTC 后返回。
  /// 输出用于 [DateTime.toIso8601String]（带 Z 后缀），确保 adapter 端
  /// [_parseTime] 解析为 UTC。
  DateTime? _parseBeijingTime(String text) {
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
      // 输入是北京时间(UTC+8)，先按 UTC 构造再减 8 小时得到真正 UTC
      final beijingUtc = DateTime.utc(y, mo, d, h, mi, s);
      return beijingUtc.subtract(const Duration(hours: 8));
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
