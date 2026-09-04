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

  /// HTTP 轮询状态回调
  void Function(bool connected)? onStatusChanged;

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
      if (resp.statusCode != 200) {
        onStatusChanged?.call(false);
        return;
      }

      final data = json.decode(resp.body);
      final features = data['features'] as List?;
      onStatusChanged?.call(true);
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
            DateTime.tryParse(timeStr)?.toUtc() ?? DateTime.now().toUtc();
        final DateTime originTime = originTimeUtc.toLocal();

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
            timeZone: _systemTimeZoneHours,
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
    } catch (_) {
      onStatusChanged?.call(false);
    }
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
    // Preserve the absolute EMSC ISO instant for the adapter. It localizes
    // direct-source events to the device timezone instead of forcing UTC+8.
    final originTime = DateTime.tryParse(
      props['time']?.toString() ?? '',
    )?.toUtc().toIso8601String();
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

  int get _systemTimeZoneHours => DateTime.now().timeZoneOffset.inMinutes ~/ 60;
}
