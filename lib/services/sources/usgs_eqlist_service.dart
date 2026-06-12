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
/// - 时间转换为UTC+8
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

  /// 启动轮询
  /// 
  /// [interval] 轮询间隔，默认60秒
  void start({Duration interval = const Duration(seconds: 60)}) {
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
      if (resp.statusCode != 200) return;

      final data = json.decode(resp.body);
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) return;

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
        final DateTime originTimeUtc =
            DateTime.fromMillisecondsSinceEpoch(timeMs, isUtc: true);
        final DateTime originTime = originTimeUtc.add(const Duration(hours: 8));

        final String eventId = f['id']?.toString() ??
            props['code']?.toString() ??
            'usgs_$timeMs';

        final String cnPlace = getFEName(latitude, longitude);

        final int maxIntensity =
            IntensityCalculator.calcCsisLevel(magnitude, depth, 0);

        final String status = props['status']?.toString() ?? '';
        final String reviewType = status.toLowerCase() == 'reviewed' 
            ? '正式测定' 
            : '自动测定';

        _latestList.add(QuakeMessage(
          source: QuakeSourceType.usgs,
          eventId: eventId,
          location: cnPlace.isNotEmpty ? cnPlace : place,
          magnitude: magnitude,
          latitude: latitude,
          longitude: longitude,
          depth: depth,
          originTime: originTime,
          isHistory: true,
          maxIntensity: maxIntensity,
          reviewType: reviewType,
          isInfoEvent: true,
        ));
      }

      onListUpdated?.call(_latestList);
    } catch (_) {}
  }
}
