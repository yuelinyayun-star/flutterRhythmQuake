import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/quake_message.dart';
import '../../utils/fe_regions.dart';
import '../../core/intensity_calculator.dart';

/// USGS地震列表服务
///
/// 该类提供美国地质调查局(USGS)地震数据获取功能。
/// 通过HTTP轮询获取全球地震列表。
///
/// 主要功能：
/// - 定时轮询USGS GeoJSON API
/// - 解析地震数据
/// - 计算中国地震烈度(CSIS)
/// - 转换地名显示
/// - epoch 时间保留为绝对时间，并按设备时区显示
///
/// 数据源：
/// - USGS 2.5级以上一周内地震
/// - URL: https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_week.geojson
class UsgsEqlistService {
  static final UsgsEqlistService _instance = UsgsEqlistService._internal();
  factory UsgsEqlistService() => _instance;
  UsgsEqlistService._internal();

  /// USGS GeoJSON API地址
  ///
  /// 获取最近一周2.5级以上的地震
  static const String _url =
      'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_week.geojson';

  /// 定时器
  Timer? _timer;

  /// 最新地震列表
  final List<QuakeMessage> _latestList = [];

  /// 获取最新列表（只读）
  List<QuakeMessage> get latestList => List.unmodifiable(_latestList);

  /// 列表更新回调
  void Function(List<QuakeMessage>)? onListUpdated;

  /// 最新官方事件更新回调，字段格式与统一事件适配器的 USGS 输入一致。
  void Function(Map<String, dynamic>)? onCurrentUpdated;

  /// HTTP 轮询状态回调
  void Function(bool connected)? onStatusChanged;

  /// 启动轮询
  ///
  /// [interval] 轮询间隔，默认30秒（信息事件列表，无需 10s）
  void start({Duration interval = const Duration(seconds: 30)}) {
    _timer?.cancel();
    _fetch();
    _timer = Timer.periodic(interval, (_) => _fetch());
  }

  /// 停止轮询
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 获取地震数据
  Future<void> _fetch() async {
    try {
      final resp = await http
          .get(Uri.parse(_url))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        onStatusChanged?.call(false);
        return;
      }

      final data = json.decode(resp.body);
      final features = data['features'] as List?;
      onStatusChanged?.call(true);
      if (features == null || features.isEmpty) return;

      final currentPayload = normalizeFeatureForUnifiedUi(features.first);

      _latestList.clear();
      for (final f in features) {
        final props = f['properties'];
        if (props == null) continue;
        final geom = f['geometry'];
        if (geom == null) continue;

        final coords = geom['coordinates'] as List?;
        if (coords == null || coords.length < 3) continue;

        final double magnitude =
            double.tryParse(props['mag']?.toString() ?? '') ?? 0.0;
        final String place = props['place']?.toString() ?? 'Unknown';
        final double longitude =
            double.tryParse(coords[0]?.toString() ?? '') ?? 0.0;
        final double latitude =
            double.tryParse(coords[1]?.toString() ?? '') ?? 0.0;
        final double depth =
            double.tryParse(coords[2]?.toString() ?? '') ?? 0.0;

        final int timeMs = props['time'] ?? 0;
        final DateTime originTimeUtc = DateTime.fromMillisecondsSinceEpoch(
          timeMs,
          isUtc: true,
        );
        final DateTime originTime = originTimeUtc.toLocal();

        final String eventId =
            f['id']?.toString() ?? props['code']?.toString() ?? 'usgs_$timeMs';

        final String cnPlace = getFEName(latitude, longitude);

        final int maxIntensity = IntensityCalculator.calcCsisLevel(
          magnitude,
          depth,
          0,
        );

        final String status = props['status']?.toString() ?? '';
        final String reviewType = status.toLowerCase() == 'reviewed'
            ? '正式测定'
            : '自动测定';

        _latestList.add(
          QuakeMessage(
            source: QuakeSourceType.usgs,
            eventId: eventId,
            location: cnPlace.isNotEmpty ? cnPlace : place,
            magnitude: magnitude,
            latitude: latitude,
            longitude: longitude,
            depth: depth,
            originTime: originTime,
            timeZone: _systemTimeZoneHours,
            isHistory: true,
            maxIntensity: maxIntensity,
            reviewType: reviewType,
            isInfoEvent: true,
          ),
        );
      }

      if (currentPayload != null) onCurrentUpdated?.call(currentPayload);
      // 当前事件会同步进入统一列表桶；随后用官方完整列表覆盖，避免重复条目。
      onListUpdated?.call(_latestList);
    } catch (_) {
      onStatusChanged?.call(false);
    }
  }

  /// 将 USGS GeoJSON feature 规范成统一 UI 已使用的 USGS 字段。
  ///
  /// 当前事件 ID 优先使用 `properties.code`，与 FAN 的 USGS `id` 对齐。
  Map<String, dynamic>? normalizeFeatureForUnifiedUi(Object? feature) {
    if (feature is! Map) return null;
    final featureMap = Map<String, dynamic>.from(feature);
    final propsRaw = featureMap['properties'];
    final geometryRaw = featureMap['geometry'];
    if (propsRaw is! Map || geometryRaw is! Map) return null;

    final props = Map<String, dynamic>.from(propsRaw);
    final geometry = Map<String, dynamic>.from(geometryRaw);
    final coords = geometry['coordinates'];
    if (coords is! List || coords.length < 3) return null;

    final magnitude = double.tryParse(props['mag']?.toString() ?? '');
    final longitude = double.tryParse(coords[0]?.toString() ?? '');
    final latitude = double.tryParse(coords[1]?.toString() ?? '');
    final depth = double.tryParse(coords[2]?.toString() ?? '');
    // USGS supplies epoch milliseconds. Keep them as ISO UTC instants; the
    // direct-source adapter converts them to the device timezone.
    final originTime = _formatEpochAsIso(props['time']);
    final updateTime = _formatEpochAsIso(props['updated']);
    if (magnitude == null ||
        longitude == null ||
        latitude == null ||
        depth == null ||
        originTime == null ||
        updateTime == null) {
      return null;
    }

    final code = props['code']?.toString().trim() ?? '';
    final featureId = featureMap['id']?.toString().trim() ?? '';
    final eventId = code.isNotEmpty ? code : featureId;
    if (eventId.isEmpty) return null;

    final place = props['place']?.toString() ?? 'Unknown';
    final cnPlace = getFEName(latitude, longitude);
    final status = props['status']?.toString() ?? '';
    return {
      'eventId': eventId,
      'reviewType': status.toLowerCase() == 'reviewed'
          ? 'reviewed'
          : 'automatic',
      'location': cnPlace.isNotEmpty ? cnPlace : place,
      'latitude': latitude,
      'longitude': longitude,
      'depth': depth,
      'originTime': originTime,
      'shockTime': originTime,
      'updateTime': updateTime,
      'magnitude': magnitude,
      'maxIntensity': IntensityCalculator.calcCsisLevel(magnitude, depth, 0),
    };
  }

  String? _formatEpochAsIso(Object? value) {
    final milliseconds = value is int
        ? value
        : int.tryParse(value?.toString() ?? '');
    if (milliseconds == null || milliseconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      milliseconds,
      isUtc: true,
    ).toIso8601String();
  }

  int get _systemTimeZoneHours => DateTime.now().timeZoneOffset.inMinutes ~/ 60;
}
