import 'dart:async';
import 'dart:io';

import 'package:euc/euc.dart';

/// F-net CMT（震源机制解）サービス
///
/// 数据来源：防災科学技術研究所 F-net 地震のメカニズム情報
///
/// F-net 站点要求先访问 joho.php 初始化 session cookie，随后才能正常请求
/// sret.php 与 tdmt.php。本服务使用 [HttpClient] 在两次请求之间复用 cookie。
///
/// 两步获取：
/// 1. 列表页 sret.php (LANG=en)：获取事件列表、基本参数、status_color
///    - status_color_2 = 自动解, status_color_1 = 正式（手动复核）
///    - 时间为 UT（UTC）
/// 2. 详细页 tdmt.php (LANG=ja)：获取断层面参数(Strike/Dip/Rake)和日文区域名
///    - 仅对新事件或 reviewType 发生变化的事件请求详细页
///
/// F-net 自动处理在震后约 10 分钟发布，工作日人工复核。
class FnetCmtService {
  static final FnetCmtService _instance = FnetCmtService._internal();
  factory FnetCmtService() => _instance;
  FnetCmtService._internal();

  static const String _baseUrl = 'https://www.fnet.bosai.go.jp';
  static const String _initUrl = '$_baseUrl/fnet/event/joho.php';
  static const String _listUrl = '$_baseUrl/event/sret.php';
  static const String _detailUrl = '$_baseUrl/event/tdmt.php';

  void Function(List<Map<String, dynamic>>)? onListUpdated;
  void Function(bool connected)? onStatusChanged;

  Timer? _timer;
  bool _initialized = false;
  bool _fetching = false;

  /// 已获取详细数据的事件缓存。每次列表刷新都回填真实节面，避免后续
  /// 轮询把已有 CMT 球退化成无参数状态。
  final Map<String, ({String reviewType, Map<String, dynamic> fields})>
  _detailCache = {};

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
    final client = HttpClient();
    try {
      // 1. 初始化 session：F-net 要求先访问 joho.php 才能请求 sret.php
      await _initSession(client);

      // 2. 请求列表页
      final list = await _fetchList(client);
      if (list.isEmpty) return;

      // 3. 对新事件或 reviewType 变化的事件获取详细数据
      final currentIds = <String>{};
      for (final item in list) {
        final eventId = item['eventId']?.toString() ?? '';
        final reviewType = item['reviewType']?.toString() ?? 'auto';
        if (eventId.isEmpty) continue;
        currentIds.add(eventId);

        final cached = _detailCache[eventId];
        if (cached != null && cached.reviewType == reviewType) {
          item.addAll(cached.fields);
          continue;
        }

        final detail = await _fetchDetail(client, eventId);
        if (detail != null) {
          item.addAll(detail);
          _detailCache[eventId] = (
            reviewType: reviewType,
            fields: Map<String, dynamic>.from(detail),
          );
        }
      }
      // 清理不在当前列表中的旧 ID，避免缓存无限增长
      _detailCache.removeWhere((id, _) => !currentIds.contains(id));

      onListUpdated?.call(list);
      _initialized = true;
      onStatusChanged?.call(true);
    } catch (e) {
      print('F-net CMT fetch error: $e');
      onStatusChanged?.call(false);
    } finally {
      client.close();
      _fetching = false;
    }
  }

  /// 访问 joho.php 初始化 session cookie
  Future<void> _initSession(HttpClient client) async {
    final req = await client.getUrl(Uri.parse('$_initUrl?LANG=en'));
    _setHeaders(req);
    final resp = await req.close();
    await resp.drain();
    if (resp.statusCode != 200) {
      throw Exception('F-net CMT init session HTTP ${resp.statusCode}');
    }
  }

  /// 请求列表页 sret.php
  Future<List<Map<String, dynamic>>> _fetchList(HttpClient client) async {
    final now = DateTime.now().toUtc();
    final req = await client.postUrl(Uri.parse('$_listUrl?LANG=en'));
    _setHeaders(
      req,
      referer: '$_initUrl?LANG=en',
      contentType: 'application/x-www-form-urlencoded; charset=UTF-8',
    );

    final postData = [
      'init=1',
      'page=1',
      'one_page_view=50',
      'sy=${now.year}',
      'sm=${now.month.toString().padLeft(2, '0')}',
      'sd=01',
      'sh=00',
      'si=00',
      'ey=${now.year}',
      'em=${now.month.toString().padLeft(2, '0')}',
      'ed=31',
      'eh=23',
      'ei=59',
      'time_sort=desc',
      'smag=',
      'emag=',
      'sdep=',
      'edep=',
      'slat=',
      'elat=',
      'slng=',
      'elng=',
      'status[]=1',
      'status[]=2',
    ].join('&');
    req.write(postData);

    final resp = await req.close();
    final bodyBytes = await resp.fold<List<int>>([], (a, b) => a..addAll(b));
    if (resp.statusCode != 200) {
      print('F-net CMT list HTTP ${resp.statusCode}');
      return [];
    }
    final body = EucJP().decode(bodyBytes);
    return _parseList(body);
  }

  /// 获取详细页面数据（断层面参数 + 日文区域名）
  Future<Map<String, dynamic>?> _fetchDetail(
    HttpClient client,
    String rawId,
  ) async {
    try {
      // rawId 格式为 "fnet_cmt_20260803143900"，提取数字部分
      final id = rawId.replaceAll(RegExp(r'^fnet_cmt_'), '');
      final req = await client.getUrl(
        Uri.parse('$_detailUrl?_id=$id&_upd=&LANG=ja'),
      );
      _setHeaders(req, referer: '$_initUrl?LANG=ja');
      final resp = await req.close();
      final bodyBytes = await resp.fold<List<int>>([], (a, b) => a..addAll(b));
      if (resp.statusCode != 200) return null;

      // 用 EucJP 解码日文页面
      final body = EucJP().decode(bodyBytes);

      // 解析断层面参数（<td class="deci">）
      final deciRegex = RegExp(r'<td class="deci">([^<]*)</td>');
      final deciCells = deciRegex
          .allMatches(body)
          .map((m) => m.group(1)!.trim())
          .toList();

      Map<String, dynamic>? result;
      // deciCells 结构（每组 13 个）：
      // [0] lat, [1] lng, [2] depth, [3] Mj, [4] MTlat, [5] MTlng,
      // [6] centroidDepth, [7] strike, [8] dip, [9] rake, [10] Mo, [11] Mw, [12] VR
      // 当存在手动复核时，页面有两组（自动 + 手动），共约 26 个单元格
      // 优先取手动解（第二组），否则取自动解（第一组）
      final hasManual = body.contains('手動メカニズム');
      final manualOffset = hasManual && deciCells.length >= 26 ? 13 : 0;
      if (deciCells.length >= manualOffset + 13) {
        final strikeStr = deciCells[manualOffset + 7];
        final dipStr = deciCells[manualOffset + 8];
        final rakeStr = deciCells[manualOffset + 9];
        final parts = _parseNodalPlanes(strikeStr, dipStr, rakeStr);
        result ??= {};
        result['nodalPlane1'] = parts[0];
        result['nodalPlane2'] = parts[1];
        result['centroidDepth'] = _parseDepth(deciCells[manualOffset + 6]);
        result['cmtMetadata'] = {
          'centroidLatitude': double.tryParse(deciCells[manualOffset + 4]),
          'centroidLongitude': double.tryParse(deciCells[manualOffset + 5]),
          'scalarMoment': deciCells[manualOffset + 10],
          'varianceReduction': double.tryParse(deciCells[manualOffset + 12]),
        };
      }

      // 解析日文区域名（<td class="nodeci region">根室半島南東沖</td>）
      final regionRegex = RegExp(
        r'<td[^>]*class="[^"]*\bregion\b[^"]*"[^>]*>([^<]*)</td>',
      );
      final regionMatch = regionRegex.firstMatch(body);
      if (regionMatch != null) {
        final region = regionMatch.group(1)!.trim();
        if (region.isNotEmpty) {
          result ??= {};
          result['location'] = region;
        }
      }

      // reviewType 由列表页 status_color 决定，详细页不再重复设置
      return result;
    } catch (e) {
      print('F-net CMT detail fetch error: $e');
      return null;
    }
  }

  void _setHeaders(
    HttpClientRequest req, {
    String? referer,
    String? contentType,
  }) {
    req.headers.set(
      'User-Agent',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    );
    if (referer != null) {
      req.headers.set('Referer', referer);
    }
    req.headers.set('X-Requested-With', 'XMLHttpRequest');
    if (contentType != null) {
      req.headers.set('Content-Type', contentType);
    }
  }

  /// 将 "147 ; 40", "29 ; 81", "19 ; 118" 解析为两个 nodalPlane
  ///
  /// 返回 ["147/29/19", "40/81/118"]
  List<String> _parseNodalPlanes(
    String strikeStr,
    String dipStr,
    String rakeStr,
  ) {
    try {
      final strikes = strikeStr.split(';');
      final dips = dipStr.split(';');
      final rakes = rakeStr.split(';');
      if (strikes.length >= 2 && dips.length >= 2 && rakes.length >= 2) {
        final s1 = strikes[0].trim();
        final s2 = strikes[1].trim();
        final d1 = dips[0].trim();
        final d2 = dips[1].trim();
        final r1 = rakes[0].trim();
        final r2 = rakes[1].trim();
        return ['$s1/$d1/$r1', '$s2/$d2/$r2'];
      }
      // fallback: 只有一个值
      final s = strikeStr.trim();
      final d = dipStr.trim();
      final r = rakeStr.trim();
      return ['$s/$d/$r', ''];
    } catch (_) {
      return ['', ''];
    }
  }

  /// 解析列表页 HTML 表格
  List<Map<String, dynamic>> _parseList(String html) {
    final result = <Map<String, dynamic>>[];
    try {
      final rowRegex = RegExp(
        r'<tr\s+id="(\d{14})"[^>]*>(.*?)</tr>',
        dotAll: true,
      );
      final cellRegex = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true);
      final statusRegex = RegExp(r'status_color_(\d+)');

      for (final rowMatch in rowRegex.allMatches(html)) {
        final rawId = rowMatch.group(1) ?? '';
        final rowHtml = rowMatch.group(2) ?? '';
        final cells = cellRegex
            .allMatches(rowHtml)
            .map((m) => _stripTags(m.group(1) ?? '').trim())
            .toList();
        if (cells.length < 10) continue;

        final statusMatch = statusRegex.firstMatch(rowHtml);
        final statusColor = statusMatch?.group(1) ?? '2';
        final isAuto = statusColor == '2';

        final item = _buildListItem(rawId, cells, isAuto);
        if (item != null) result.add(item);
      }
    } catch (e) {
      print('F-net CMT parse error: $e');
    }
    return result;
  }

  /// 构造列表项
  Map<String, dynamic>? _buildListItem(
    String rawId,
    List<String> cells,
    bool isAuto,
  ) {
    try {
      final originTime = _parseUtTime(cells[1]);
      final lat = double.tryParse(cells[2]);
      final lng = double.tryParse(cells[3]);
      if (originTime == null || lat == null || lng == null) return null;
      final location = cells[4]; // 英文区域名（fallback）
      final jmaDepth = _parseDepth(cells[5]);
      final mj = double.tryParse(cells[6]);
      final centroidDepth = _parseDepth(cells[7]);
      final mw = double.tryParse(cells[8]);
      final quality = double.tryParse(cells[9]);
      if (quality != null && quality < 50) return null;
      final magnitude = mw ?? mj ?? -1;
      return {
        'eventId': 'fnet_cmt_$rawId',
        'originTime': originTime.toIso8601String(),
        'latitude': lat,
        'longitude': lng,
        'depth': jmaDepth ?? -1,
        'magnitude': magnitude,
        'centroidDepth': centroidDepth,
        'location': location,
        'quality': quality ?? 0,
        'reviewType': isAuto ? 'auto' : 'reviewed',
      };
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseUtTime(String text) {
    try {
      final decoded = _decodeEntities(text).trim();
      final match = RegExp(
        r'(\d{4})/(\d{1,2})/(\d{1,2})[ ,]+(\d{1,2}):(\d{1,2})',
      ).firstMatch(decoded);
      if (match == null) return null;
      return DateTime.utc(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
      );
    } catch (_) {
      return null;
    }
  }

  double? _parseDepth(String text) {
    try {
      final trimmed = text.trim();
      if (trimmed.toLowerCase().contains('shallow')) return 0;
      final match = RegExp(r'(\d+\.?\d*)').firstMatch(trimmed);
      if (match == null) return null;
      return double.parse(match.group(1)!);
    } catch (_) {
      return null;
    }
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
