import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../utils/fe_regions.dart';

/// USGS 矩心矩张量解（CMT）服务
///
/// 数据来源：USGS FDSN API 的 moment-tensor 产品
/// （https://earthquake.usgs.gov/fdsnws/event/1/query）
///
/// 获取方式（两步）：
/// 1. FDSN query + producttype=moment-tensor 获取含 CMT 的事件列表
/// 2. 对每个事件用 eventid=xxx 获取详情，提取 products.moment-tensor
///
/// FDSN query 返回的 GeoJSON 不含 products 对象，只有 types 字段标识
/// 事件有哪些产品。必须逐事件获取详情才能拿到 CMT 字段。
///
/// 轮询周期 5 分钟（CMT 非速报，与 CENC CMT 一致）。每次轮询产出
/// `List<Map<String, dynamic>>`，由 [QuakeProvider] 调用
/// [QuakeEventAdapter.convert]（source='usgsCmt'）转为 [UnifiedQuakeData]。
///
/// 字段映射参见 [quake_event_adapter.dart] 的 `_usgsCmt` 方法。
class UsgsCmtService {
  static final UsgsCmtService _instance = UsgsCmtService._internal();
  factory UsgsCmtService() => _instance;
  UsgsCmtService._internal();

  /// FDSN query：获取含 moment-tensor 产品的近期事件
  static const String _queryUrl =
      'https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson'
      '&producttype=moment-tensor&minmagnitude=5.5&orderby=time&limit=20';

  /// FDSN detail：按 eventid 获取含 products 的单事件详情
  static const String _detailUrl =
      'https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&eventid=';

  /// 列表数据回调
  void Function(List<Map<String, dynamic>>)? onListUpdated;

  Timer? _timer;
  bool _initialized = false;
  bool _fetching = false;

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

  /// 拉取含 moment-tensor 的事件列表并逐个获取详情
  Future<void> fetch() async {
    if (_fetching) return;
    _fetching = true;
    try {
      // Step 1: FDSN query 获取含 CMT 的事件列表
      final resp = await http
          .get(Uri.parse(_queryUrl))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        print('USGS CMT query HTTP ${resp.statusCode}');
        return;
      }
      final data = json.decode(resp.body);
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) return;

      // Step 2: 逐事件获取详情，提取 moment-tensor 产品
      final items = <Map<String, dynamic>>[];
      for (final feature in features) {
        final item = await _fetchDetail(feature);
        if (item != null) items.add(item);
      }

      if (items.isNotEmpty) {
        onListUpdated?.call(items);
        // 仅在有数据时标记已初始化，避免首次 fetch 为空时下次
        // 有数据走增量推送（应走首次填充 eqlist 桶逻辑）
        _initialized = true;
      }
    } catch (e) {
      print('USGS CMT fetch error: $e');
    } finally {
      _fetching = false;
    }
  }

  /// 获取单事件详情并提取 preferredWeight 最高的 moment-tensor 产品
  Future<Map<String, dynamic>?> _fetchDetail(dynamic feature) async {
    try {
      final featureMap = feature as Map<String, dynamic>;
      final eventId = featureMap['id']?.toString() ?? '';
      if (eventId.isEmpty) return null;

      final resp = await http
          .get(Uri.parse('$_detailUrl$eventId'))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;

      final data = json.decode(resp.body);
      final props = data['properties'] as Map<String, dynamic>?;
      if (props == null) return null;

      final products = props['products'] as Map<String, dynamic>?;
      if (products == null) return null;

      final mtList = products['moment-tensor'] as List?;
      if (mtList == null || mtList.isEmpty) return null;

      // 取 preferredWeight 最高的 moment-tensor 产品
      final mt =
          mtList.reduce((a, b) {
                final aw = (a['preferredWeight'] ?? 0) as num;
                final bw = (b['preferredWeight'] ?? 0) as num;
                return aw >= bw ? a : b;
              })
              as Map<String, dynamic>;

      final mtProps = mt['properties'] as Map<String, dynamic>?;
      if (mtProps == null) return null;

      return _buildItem(featureMap, mtProps);
    } catch (e) {
      print('USGS CMT detail error: $e');
      return null;
    }
  }

  /// 将 GeoJSON feature + moment-tensor 产品属性构造为事件字段 map
  ///
  /// 字段映射：
  /// - eventId: feature.id（如 us7000t37a）
  /// - originTime: mtProps.eventtime（UTC ISO → UTC+8 字符串）
  /// - latitude/longitude: feature.geometry.coordinates（震中坐标）
  /// - depth: feature.geometry.coordinates[2]（震源深度，km）
  /// - magnitude: mtProps.derived-magnitude（矩震级 Mw，fallback 速报震级）
  /// - centroidDepth: mtProps.derived-depth（矩心深度，km）
  /// - nodalPlane1/2: mtProps.nodal-plane-N-strike/dip/rake
  /// - reviewType: mtProps.review-status / evaluation-status
  Map<String, dynamic>? _buildItem(
    Map<String, dynamic> feature,
    Map<String, dynamic> mtProps,
  ) {
    try {
      final eventId = feature['id']?.toString() ?? '';
      final geom = feature['geometry']?['coordinates'] as List?;
      final lat = geom != null && geom.length >= 2
          ? double.tryParse(geom[1]?.toString() ?? '')
          : null;
      final lng = geom != null && geom.length >= 2
          ? double.tryParse(geom[0]?.toString() ?? '')
          : null;
      final depth = geom != null && geom.length >= 3
          ? double.tryParse(geom[2]?.toString() ?? '')
          : null;
      if (eventId.isEmpty || lat == null || lng == null) return null;

      // eventtime 格式: 2026-07-24T21:37:55.7Z (UTC)
      final eventTime = mtProps['eventtime']?.toString() ?? '';
      final originTime = _parseUtcIso(eventTime);
      if (originTime == null) return null;

      // Mw 矩震级优先，fallback 速报震级
      final mw = double.tryParse(
        mtProps['derived-magnitude']?.toString() ?? '',
      );
      final magnitude =
          mw ??
          double.tryParse(feature['properties']?['mag']?.toString() ?? '') ??
          -1;

      // 矩心深度（derived-depth）
      final centroidDepth = double.tryParse(
        mtProps['derived-depth']?.toString() ?? '',
      );

      // 断层面参数
      final strike1 = mtProps['nodal-plane-1-strike']?.toString() ?? '';
      final dip1 = mtProps['nodal-plane-1-dip']?.toString() ?? '';
      final rake1 = mtProps['nodal-plane-1-rake']?.toString() ?? '';
      final strike2 = mtProps['nodal-plane-2-strike']?.toString() ?? '';
      final dip2 = mtProps['nodal-plane-2-dip']?.toString() ?? '';
      final rake2 = mtProps['nodal-plane-2-rake']?.toString() ?? '';

      // 审核状态：review-status 或 evaluation-status
      final reviewStatus = mtProps['review-status']?.toString() ?? '';
      final evaluationStatus = mtProps['evaluation-status']?.toString() ?? '';
      final reviewType =
          (reviewStatus.toLowerCase() == 'reviewed' ||
              evaluationStatus.toLowerCase() == 'reviewed' ||
              evaluationStatus.toLowerCase() == 'confirmed')
          ? 'reviewed'
          : 'automatic';

      // 地名：优先 FE 中文名，fallback USGS place
      final place = feature['properties']?['place']?.toString() ?? '';
      final cnPlace = getFEName(lat, lng);

      // originTime 转 UTC+8 字符串（与 usgs_eqlist_service._formatEpochAsUtc8 一致）
      final originTimeUtc8 = originTime.add(const Duration(hours: 8));
      String two(int p) => p.toString().padLeft(2, '0');
      final originTimeStr =
          '${originTimeUtc8.year.toString().padLeft(4, '0')}-'
          '${two(originTimeUtc8.month)}-${two(originTimeUtc8.day)} '
          '${two(originTimeUtc8.hour)}:${two(originTimeUtc8.minute)}:'
          '${two(originTimeUtc8.second)}';

      return {
        'eventId': eventId,
        'originTime': originTimeStr,
        'latitude': lat,
        'longitude': lng,
        'depth': depth ?? -1,
        'magnitude': magnitude,
        'centroidDepth': centroidDepth,
        'nodalPlane1': '$strike1/$dip1/$rake1',
        'nodalPlane2': '$strike2/$dip2/$rake2',
        'momentTensor': {
          'mrr': mtProps['tensor-mrr'],
          'mtt': mtProps['tensor-mtt'],
          'mpp': mtProps['tensor-mpp'],
          'mrt': mtProps['tensor-mrt'],
          'mrp': mtProps['tensor-mrp'],
          'mtp': mtProps['tensor-mtp'],
        },
        'momentTensorConvention': 'rtp',
        'cmtMetadata': {
          // Keep USGS product values as supplied; they are not recomputed here.
          'centroidTime': mtProps['derived-eventtime'],
          'centroidLatitude': mtProps['derived-latitude'],
          'centroidLongitude': mtProps['derived-longitude'],
          'scalarMoment': mtProps['scalar-moment'],
          'doubleCoupleRatio': mtProps['percent-double-couple'],
        },
        'reviewType': reviewType,
        'location': cnPlace.isNotEmpty ? cnPlace : place,
      };
    } catch (_) {
      return null;
    }
  }

  /// 解析 UTC ISO 时间字符串（如 2026-07-24T21:37:55.7Z）为 UTC DateTime
  DateTime? _parseUtcIso(String text) {
    try {
      return DateTime.parse(text);
    } catch (_) {
      return null;
    }
  }
}
