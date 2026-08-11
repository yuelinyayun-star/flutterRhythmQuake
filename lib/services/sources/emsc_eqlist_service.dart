import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/quake_message.dart';
import '../../utils/fe_regions.dart';
import '../../core/intensity_calculator.dart';

class EmscEqlistService {
  static final EmscEqlistService _instance = EmscEqlistService._internal();
  factory EmscEqlistService() => _instance;
  EmscEqlistService._internal();

  static const String _url =
      'https://www.seismicportal.eu/fdsnws/event/1/query?format=json&limit=50&orderby=time&minmag=3.0';

  Timer? _timer;
  final List<QuakeMessage> _latestList = [];
  List<QuakeMessage> get latestList => List.unmodifiable(_latestList);

  void Function(List<QuakeMessage>)? onListUpdated;

  /// 最新官方事件更新回调，字段格式与统一事件适配器的 EMSC 输入一致。
  void Function(Map<String, dynamic>)? onCurrentUpdated;

  void start({Duration interval = const Duration(seconds: 30)}) {
    _timer?.cancel();
    _fetch();
    _timer = Timer.periodic(interval, (_) => _fetch());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _fetch() async {
    try {
      final resp = await http
          .get(Uri.parse(_url))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return;

      final data = json.decode(resp.body);
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) return;

      final currentPayload = _normalizeFeatureForUnifiedUi(features.first);

      _latestList.clear();
      for (final f in features) {
        final props = f['properties'];
        if (props == null) continue;
        final geom = f['geometry'];
        if (geom == null) continue;

        final coords = geom['coordinates'] as List?;
        if (coords == null || coords.length < 2) continue;

        final double magnitude =
            double.tryParse(props['mag']?.toString() ?? '') ?? 0.0;
        final double longitude =
            double.tryParse(coords[0]?.toString() ?? '') ?? 0.0;
        final double latitude =
            double.tryParse(coords[1]?.toString() ?? '') ?? 0.0;
        final double depth =
            double.tryParse(props['depth']?.toString() ?? '') ?? 0.0;

        final String timeStr = props['time']?.toString() ?? '';
        final DateTime originTimeUtc =
            DateTime.tryParse(timeStr) ?? DateTime.now();
        final DateTime originTime = originTimeUtc.toUtc().add(
          const Duration(hours: 8),
        );

        final String eventId =
            props['unid']?.toString() ??
            f['id']?.toString() ??
            'emsc_${originTimeUtc.millisecondsSinceEpoch}';

        final String region =
            props['flynn_region']?.toString() ??
            props['region']?.toString() ??
            '';
        final String cnPlace = getFEName(latitude, longitude);
        final String location = cnPlace.isNotEmpty ? cnPlace : region;

        final int maxIntensity = IntensityCalculator.calcCsisLevel(
          magnitude,
          depth,
          0,
        );

        final String auth = props['auth']?.toString() ?? 'EMSC';

        _latestList.add(
          QuakeMessage(
            source: QuakeSourceType.emsc,
            eventId: eventId,
            location: location,
            magnitude: magnitude,
            latitude: latitude,
            longitude: longitude,
            depth: depth,
            originTime: originTime,
            isHistory: true,
            maxIntensity: maxIntensity,
            reviewType: '自动测定',
            infoTypeName: auth,
            isInfoEvent: true,
          ),
        );
      }

      if (currentPayload != null) onCurrentUpdated?.call(currentPayload);
      onListUpdated?.call(_latestList);
    } catch (_) {}
  }

  /// 将 EMSC feature 规范成统一 UI 已使用的 EMSC 字段。
  Map<String, dynamic>? _normalizeFeatureForUnifiedUi(Object? feature) {
    if (feature is! Map) return null;
    final featureMap = Map<String, dynamic>.from(feature);
    final propsRaw = featureMap['properties'];
    final geometryRaw = featureMap['geometry'];
    if (propsRaw is! Map || geometryRaw is! Map) return null;

    final props = Map<String, dynamic>.from(propsRaw);
    final geometry = Map<String, dynamic>.from(geometryRaw);
    final coords = geometry['coordinates'];
    if (coords is! List || coords.length < 2) return null;

    final magnitude = double.tryParse(props['mag']?.toString() ?? '');
    final longitude = double.tryParse(coords[0]?.toString() ?? '');
    final latitude = double.tryParse(coords[1]?.toString() ?? '');
    final depth = double.tryParse(props['depth']?.toString() ?? '');
    final originTime = _formatTimeAsUtc8(props['time']?.toString());
    final createTime = originTime;
    if (magnitude == null ||
        longitude == null ||
        latitude == null ||
        depth == null ||
        originTime == null ||
        createTime == null) {
      return null;
    }

    final eventId =
        props['unid']?.toString().trim() ??
        featureMap['id']?.toString().trim() ??
        '';
    if (eventId.isEmpty) return null;

    final region =
        props['flynn_region']?.toString() ?? props['region']?.toString() ?? '';
    final cnPlace = getFEName(latitude, longitude);
    final location = cnPlace.isNotEmpty ? cnPlace : region;

    return {
      'eventId': eventId,
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'depth': depth,
      'originTime': originTime,
      'shockTime': originTime,
      'createTime': createTime,
      'updateTime': createTime,
      'magnitude': magnitude,
      'maxIntensity': IntensityCalculator.calcCsisLevel(magnitude, depth, 0),
    };
  }

  String? _formatTimeAsUtc8(String? value) {
    if (value == null || value.isEmpty) return null;
    final dt = DateTime.tryParse(value);
    if (dt == null) return null;
    final utc8 = dt.toUtc().add(const Duration(hours: 8));
    String two(int part) => part.toString().padLeft(2, '0');
    return '${utc8.year.toString().padLeft(4, '0')}-'
        '${two(utc8.month)}-${two(utc8.day)} '
        '${two(utc8.hour)}:${two(utc8.minute)}:${two(utc8.second)}';
  }
}
