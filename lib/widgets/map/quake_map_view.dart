// 地震地图视图组件
//
// 鏈粍浠舵槸搴旂敤鐨勬牳蹇冨湴鍥捐鍥撅紝闆嗘垚浜嗗绉嶅湴闇囩洃娴嬫暟鎹浘灞傘€?// 閲囩敤 FlutterMap 浣滀负搴曞眰鍦板浘寮曟搸锛屾敮鎸佸绉嶆暟鎹簮鍙犲姞鏄剧ず銆?//
// ## 涓昏鍔熻兘
//
// - **底图显示**: 使用 Petal 主题瓦片作为底图
// - **NIED 强震数据**: 显示日本 K-NET/KiK-net 测站实时震度
// - **KMA 娴嬬珯鏁版嵁**: 鏄剧ず闊╁浗姘旇薄鍘呮祴绔欏疄鏃堕渿搴?// - **S-net 娴峰簳鏁版嵁**: 鏄剧ず鏃ユ湰娴峰簳鍦伴渿瑙傛祴缃戞暟鎹?// - **CENC 浠櫒鐑堝害**: 鏄剧ず涓浗鍦伴渿鍙扮綉涓績浠櫒鐑堝害鍒嗗竷
// - **鍦伴渿娉㈠姩鐢?*: 鏄剧ず棰勮鍦伴渿娉紶鎾姩鐢?// - **鍘嗗彶鍦伴渿鏍囪**: 鏄剧ず閫変腑鐨勫巻鍙插湴闇囦綅缃?//
// ## 鏁版嵁娴?//
// 1. 鍚勭洃娴嬫湇鍔＄嫭绔嬭繍琛岋紝閫氳繃鍥炶皟鏇存柊鐘舵€?// 2. 鐘舵€佸彉鍖栬Е鍙?UI 閲嶇粯
// 3. 鏂伴璀︿簨浠惰Е鍙戝湴鍥捐嚜鍔ㄥ畾浣?//
// ## 图层叠加顺序
//
// 1. 搴曞浘鐡︾墖灞?// 2. NIED 闇囧害灞?// 3. KMA 闇囧害灞?// 4. S-net 娴峰簳灞?// 5. CENC 浠櫒鐑堝害灞?// 6. 鍦伴渿娉㈠姩鐢诲眰
// 7. 鍘嗗彶鍦伴渿鏍囪灞?
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wave_layer.dart';
import 'user_location_layer.dart';
import 'nied_intensity_layer.dart';
import 'kma_intensity_layer.dart';
import 'cwa_station_layer.dart';
import 'palert_station_layer.dart';
import 'cenc_ir_layer.dart';
import 'history_marker_layer.dart';
import 'snet_layer.dart';
import 'volcano_layer.dart';
import 'volcano_ashfall_layer.dart';
import 'volcano_info_focus.dart';
import '../../core/utils/volcano_icon_assets.dart';
import 'seisjs_layer.dart';
import 'fdsn_station_layer.dart';
import '../../core/fdsn_intensity.dart';
import 'fssn_cmt_layer.dart';
import 'intensity_fill_layer.dart';
import 'jma_lpgm_region_fill_layer.dart';
import 'station_dot_painter_layer.dart';
import 'tsunami_layer.dart';
import 'international_tsunami_layer.dart';
import 'nmefc_tsunami_layer.dart';
import 'typhoon_layer.dart';
import 'fan_radar_layer.dart';
import 'jma_radar_layer.dart';
import 'fan_satellite_cloud_layer.dart';
import 'weather_station_map_layer.dart';
import 'weather_alert_map_layer.dart';
import '../../models/weather_alert_map_item.dart';
import '../../services/sources/china_weather_alert_map_service.dart';
import 'eew_wave_camera_follow_gate.dart';
import 'cenc_ir_focus.dart';
import 'desktop_event_camera_focus.dart';
import 'station_detection_focus.dart';
import '../ui/ui_scale.dart';
import 'jma_info_focus.dart';
import 'finite_camera_constraint.dart';
import 'allow_any_cert_tile_provider.dart';
import 'map_config.dart';
import 'package:provider/provider.dart';
import '../../providers/quake_provider.dart';
import '../../providers/map_state_provider.dart';
import '../../services/background_service.dart';
import '../../services/obs_automation_input_service.dart';
import '../../services/sources/cma_local_weather_service.dart';
import '../../services/sources/lmoni_image_service.dart';
import '../../services/sources/lpgm_monitor_service.dart';
import '../../services/sources/nied_monitor.dart';
import '../../services/sources/nied_gif_observation.dart';
import '../../services/sources/nied_background_worker.dart';
import '../../services/sources/nied_source_estimation_worker.dart';
import '../../services/foreground_station_payload.dart';
import '../../services/sources/nied_yahoo_service.dart';
import '../../services/sources/jp_shindo_scale.dart';
import '../../services/sources/shindo_color_util.dart';
import '../../services/sources/jma_volcano_map_service.dart';
import '../../services/sources/fan_radar_service.dart';
import '../../services/sources/jma_radar_service.dart';
import '../../services/sources/fan_satellite_cloud_service.dart';
import '../../services/sources/shake_detection_service.dart';
import '../../services/sources/kma_monitor.dart';
import '../../services/sources/cwa_station_service.dart';
import '../../services/sources/palert_service.dart';
import '../../services/sources/palert_detection_grid.dart';
import '../../services/sources/palert_source_worker.dart';
import '../../services/sources/palert_source_state.dart';
import 'palert_source_visibility.dart';
import '../ui/ui_runtime_flags.dart';
import '../../services/sources/seisjs_service.dart';
import '../../services/sources/fdsn_station_service.dart';
import '../../services/sources/fdsn_motion_service.dart';
import '../../services/sources/snet_service.dart';
import '../../services/sources/whews_service.dart';
import '../../services/sources/whews_socket_client.dart';
import '../../services/sources/whews_station_service.dart';
import '../../services/sources/whews_nied_station_metadata.dart';
import 'china_fault_layer.dart';
import 'japan_fault_layer.dart';
import 'vector_basemap_layer.dart';
import '../../services/location_service.dart';
import '../../core/calculator.dart';
import '../../core/source_estimation/jma2001_travel_time_approximation.dart';
import '../../core/source_estimation/source_estimation_models.dart';
import '../../core/source_estimation/source_station_phase_classifier.dart';
import '../../core/source_estimation/station_event_tracker.dart';
import '../../core/source_estimation/kotoho7_js_receiver_bridge.dart';
import '../../core/event_animation_clock.dart';
import '../../services/sound_effect_service.dart';
import '../../models/source_status.dart';
import '../../models/quake_message.dart';
import '../../models/jma_volcano_site.dart';
import '../../models/snet_station.dart';
import '../../models/unified_quake_data.dart';
import '../../models/cenc_ir_data.dart';
import '../../models/tsunami_message.dart';
import '../ui/station_dashboard.dart';

({double pRadiusKm, double sRadiusKm}) niedWaveRadiiFromEstimate(
  SourceEstimate estimate, {
  double? algorithmElapsedSeconds,
}) {
  double? value(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  final bestSource = estimate.diagnostics['best_source'];
  final bestSourceMap = bestSource is Map ? bestSource : null;
  final frozen = (
    pRadiusKm:
        value(estimate.diagnostics['best_source_p_radius_km']) ??
        value(bestSourceMap?['pRadiusKm']) ??
        0,
    sRadiusKm:
        value(estimate.diagnostics['best_source_s_radius_km']) ??
        value(bestSourceMap?['sRadiusKm']) ??
        0,
  );
  final depthKm = estimate.depthKm;
  final radiusCapKm = value(estimate.diagnostics['wave_radius_cap_km']);
  if (estimate.method != 'nied_dart_hyp_v1' ||
      algorithmElapsedSeconds == null ||
      depthKm == null ||
      radiusCapKm == null) {
    return frozen;
  }
  const hiddenRadius = 999999.0;
  final elapsedSeconds = math.max(0.0, algorithmElapsedSeconds);
  if (elapsedSeconds >= 300.0) {
    return (pRadiusKm: hiddenRadius, sRadiusKm: hiddenRadius);
  }
  return (
    pRadiusKm: math.min(
      Jma2001TravelTimeApproximation.epicentralRadiusKm(
        elapsedSeconds: elapsedSeconds,
        depthKm: depthKm,
        pWave: true,
      ),
      radiusCapKm,
    ),
    sRadiusKm: math.min(
      Jma2001TravelTimeApproximation.epicentralRadiusKm(
        elapsedSeconds: elapsedSeconds,
        depthKm: depthKm,
        pWave: false,
      ),
      radiusCapKm,
    ),
  );
}

String unifiedMapLayerKey({
  required QuakeSourceType source,
  required String? eventId,
  required bool isEew,
  required int index,
}) {
  final id = eventId == null || eventId.isEmpty ? 'noid_$index' : eventId;
  final eventType = isEew ? 'eew' : 'info';
  // 同一事件的连续报必须复用图层 State，因此不将报号放入 Key。
  // EEW 与其后续地震情报可能共享来源和事件 ID，必须按事件类别区分。
  return '${source.name}_${eventType}_$id';
}

/// 地震地图视图组件
///
/// 搴旂敤鐨勬牳蹇冨湴鍥捐鍥撅紝璐熻矗闆嗘垚鍜屾樉绀烘墍鏈夊湴闇囩洃娴嬫暟鎹浘灞傘€?
class QuakeMapView extends StatefulWidget {
  /// 鍦板浘鎺у埗鍣?  ///
  /// 鐢ㄤ簬鎺у埗鍦板浘鐨勭Щ鍔ㄣ€佺缉鏀剧瓑鎿嶄綔銆?  /// 鐢辩埗缁勪欢浼犲叆锛屾敮鎸佸閮ㄦ帶鍒躲€?
  final MapController mapController;

  final void Function(StationSummaryData)? onStationDataChanged;
  final bool weatherOnly;

  /// NIED 鏁版嵁婧愬垏鎹㈤€氱煡鍣?

  static final ValueNotifier<String> niedSourceNotifier = ValueNotifier(
    'lmoni',
  );

  /// Bumped after NIED GIF inject ends so the map clears inject residue and
  /// restarts the previously selected live NIED/GIF source.
  static final ValueNotifier<int> niedLiveRestoreNotifier = ValueNotifier<int>(
    0,
  );

  /// Clear inject residue and restart live NIED (lmoni/kmoni/yahoo/…).
  static void restoreNiedLiveSource([String? source]) {
    if (source != null && source.trim().isNotEmpty) {
      niedSourceNotifier.value = source.trim();
    }
    niedLiveRestoreNotifier.value++;
  }

  static const String kmaDataSourcePreferenceKey = 'kma_data_source';
  static const String snetDataSourcePreferenceKey = 'snet_data_source';
  static final ValueNotifier<String> kmaSourceNotifier = ValueNotifier('pews');
  static final ValueNotifier<String> snetSourceNotifier = ValueNotifier('msil');
  static final ValueNotifier<NiedReplayConfig> niedReplayNotifier =
      ValueNotifier(const NiedReplayConfig.disabled());
  static final ValueNotifier<int> shakeSensitivityNotifier = ValueNotifier<int>(
    2,
  );
  static final ValueNotifier<int> fdsnStationLimitNotifier = ValueNotifier<int>(
    FdsnMotionService.defaultStationLimit,
  );
  static const String tremStationEnabledPreferenceKey = 'trem_station_enabled';
  static const String displayShindo0PreferenceKey = 'station_display_shindo0';
  static const String kmaIntensityHoldPreferenceKey =
      'kma_intensity_hold_frames';
  static final ValueNotifier<bool> tremStationEnabledNotifier =
      ValueNotifier<bool>(true);
  static final ValueNotifier<bool> displayShindo0Notifier = ValueNotifier<bool>(
    false,
  );
  static final ValueNotifier<int> kmaIntensityHoldNotifier = ValueNotifier<int>(
    1,
  );
  static const String fanEnabledPreferenceKey = 'api_source_fan_enabled';
  static const String wolfxEnabledPreferenceKey = 'api_source_wolfx_enabled';
  static const String wolfxSeisJsEnabledPreferenceKey =
      'api_source_wolfx_seisjs_enabled';
  static const String p2pquakeEnabledPreferenceKey =
      'api_source_p2pquake_enabled';
  static const String kmaPewsEnabledPreferenceKey =
      'api_source_kma_pews_enabled';
  static const String pAlertEnabledPreferenceKey = 'api_source_palert_enabled';
  static const String niedMonitorEnabledPreferenceKey =
      'api_source_nied_monitor_enabled';
  static const String niedLpgmEnabledPreferenceKey =
      'api_source_nied_lpgm_enabled';
  static const String snetEnabledPreferenceKey = 'api_source_snet_enabled';
  static const String fdsnSeedLinkEnabledPreferenceKey =
      'api_source_fdsn_seedlink_enabled';
  static const String whewsNiedEnabledPreferenceKey =
      WhewsStationService.niedEnabledPreferenceKey;
  static const String whewsSnetEnabledPreferenceKey =
      WhewsStationService.snetEnabledPreferenceKey;
  static const String whewsKmaEnabledPreferenceKey =
      WhewsStationService.kmaEnabledPreferenceKey;
  static final ValueNotifier<bool> kmaPewsEnabledNotifier = ValueNotifier<bool>(
    true,
  );
  static final ValueNotifier<bool> pAlertEnabledNotifier = ValueNotifier<bool>(
    true,
  );
  static final ValueNotifier<bool> wolfxSeisJsEnabledNotifier =
      ValueNotifier<bool>(true);
  static final ValueNotifier<bool> niedMonitorEnabledNotifier =
      ValueNotifier<bool>(true);
  static final ValueNotifier<bool> niedLpgmEnabledNotifier =
      ValueNotifier<bool>(true);
  static final ValueNotifier<bool> snetEnabledNotifier = ValueNotifier<bool>(
    true,
  );
  static final ValueNotifier<bool> fdsnSeedLinkEnabledNotifier =
      ValueNotifier<bool>(false);
  static final ValueNotifier<bool> whewsNiedEnabledNotifier =
      ValueNotifier<bool>(false);
  static final ValueNotifier<bool> whewsSnetEnabledNotifier =
      ValueNotifier<bool>(false);
  static final ValueNotifier<bool> whewsKmaEnabledNotifier =
      ValueNotifier<bool>(false);
  static final ValueNotifier<String> whewsApiTokenNotifier =
      ValueNotifier<String>('');

  const QuakeMapView({
    super.key,
    required this.mapController,
    this.onStationDataChanged,
    this.weatherOnly = false,
  });

  @override
  State<QuakeMapView> createState() => _QuakeMapViewState();
}

/// 鍦伴渿鍦板浘瑙嗗浘鐘舵€佺被
///
/// 绠＄悊鍚勭洃娴嬫湇鍔＄殑鐢熷懡鍛ㄦ湡鍜屾暟鎹闃呫€?
class _QuakeMapViewState extends State<QuakeMapView> {
  static const double _splitUnifiedFocusDistanceKm = 2500.0;
  static const Set<String> _liveWeatherTileKeys = {
    'cloudLayer',
    'windLayer',
    'rainLayer',
  };

  ({String tileKey, String tileUrl}) _baseTileState(MapStateProvider mapState) {
    return (tileKey: mapState.tileKey, tileUrl: mapState.tileUrl);
  }

  ({bool cloudLayer, bool windLayer, bool rainLayer, bool cnContour})
  _weatherOverlayState(MapStateProvider mapState) {
    return (
      cloudLayer: mapState.isOverlayEnabled('cloudLayer'),
      windLayer: mapState.isOverlayEnabled('windLayer'),
      rainLayer: mapState.isOverlayEnabled('rainLayer'),
      cnContour: mapState.isOverlayEnabled('cnContour'),
    );
  }

  /// NIED 强震监测服务实例 (lmoni 图片解析算法)
  final LmoniImageService _lmoniService = LmoniImageService();

  /// NIED Yahoo CDN 鏈嶅姟瀹炰緥 (JSON 鏁版嵁婧?

  final NiedYahooService _yahooService = NiedYahooService();

  /// 鎽囨檭妫€娴嬫湇鍔″疄渚?

  final ShakeDetectionService _shakeDetection = ShakeDetectionService();
  final ObsAutomationInputService _obsAutomationInputs =
      ObsAutomationInputService();
  final NiedSourceEstimationWorker _niedSourceEstimationDriver =
      NiedSourceEstimationWorker();

  /// 鏄惁浣跨敤 Yahoo CDN 鏁版嵁婧?

  bool _useYahooSource = false;
  String _niedSource = 'lmoni';
  String _kmaSource = 'pews';
  String _snetSource = 'msil';

  /// 当前地图上选中的气象预警条目（驱动 WeatherAlertMapLayer 弹窗）
  WeatherAlertMapItem? _selectedWeatherAlert;
  DateTime? _popupClosedAt;

  /// KMA 监测服务实例

  final KmaMonitorService _kmaService = KmaMonitorService();

  /// S-net 海底观测服务实例

  final SnetService _snetService = SnetService();
  final WhewsStationService _whewsNiedService = WhewsStationService(
    kind: WhewsStationKind.nied,
    apiToken: '',
  );
  final WhewsStationService _whewsSnetService = WhewsStationService(
    kind: WhewsStationKind.snet,
    apiToken: '',
  );
  final WhewsStationService _whewsKmaService = WhewsStationService(
    kind: WhewsStationKind.kma,
    apiToken: '',
  );
  final LpgmMonitorService _lpgmService = LpgmMonitorService();

  /// KMA 图层是否可见

  final bool _kmaVisible = true;

  /// S-net 图层是否可见

  final bool _snetVisible = true;

  /// KMA 测站数据订阅
  StreamSubscription? _kmaStationSubscription;
  StreamSubscription? _whewsNiedSubscription;
  StreamSubscription? _whewsSnetSubscription;
  StreamSubscription? _whewsKmaSubscription;
  StreamSubscription<Map<String, dynamic>>? _foregroundStationSubscription;

  /// NIED lmoni 测站数据订阅
  StreamSubscription? _lmoniStationSub;
  StreamSubscription? _yahooStationSub;

  /// NIED 娴嬬珯鍒楄〃 (浠?lmoni 鍥剧墖瑙ｆ瀽)

  List<NiedStation> _niedStations = [];
  final List<LatLng> _niedGridCellCenters = []; // kanameishi: 宸茬敾鏍煎瓙涓績鐐?
  final List<LatLng> _kmaGridCellCenters = []; // kanameishi: KMA 宸茬敾鏍煎瓙涓績鐐?
  /// KMA 测站列表
  List<KmaStation> _kmaStations = [];
  List<NiedStation> _whewsNiedStations = [];
  DateTime? _lastWhewsNiedDataTime;
  int _whewsNiedFrameSerial = 0;
  List<SnetStation> _whewsSnetStations = [];

  /// CWA 测站服务实例

  final CwaStationService _cwaService = CwaStationService();
  final PAlertService _pAlertService = PAlertService();
  final PAlertSourceWorker _pAlertSourceWorker = PAlertSourceWorker();
  Timer? _pAlertSourceExpiry;
  int _pAlertSourceGeneration = 0;

  /// CWA 测站数据订阅
  StreamSubscription? _cwaStationSubscription;
  StreamSubscription? _pAlertStationSubscription;

  /// CWA 测站列表

  List<CwaStation> _cwaStations = [];
  List<PAlertStation> _pAlertStations = [];
  final PAlertDetectionGrid _pAlertDetectionGrid = PAlertDetectionGrid();
  bool _wolfxSeisJsEnabled = true;
  bool _kmaPewsEnabled = true;
  bool _pAlertEnabled = true;
  bool _tremStationEnabled = true;
  bool _displayShindo0 = false;
  int _kmaIntensityHoldFrames = 1;
  bool _niedMonitorEnabled = true;
  bool _niedLpgmEnabled = true;
  bool _snetEnabled = true;
  bool _fdsnSeedLinkEnabled = false;
  bool _whewsNiedEnabled = false;
  bool _whewsSnetEnabled = false;
  bool _whewsKmaEnabled = false;

  bool get _usesWhewsNied => _whewsNiedEnabled && _niedSource == 'whews';
  bool get _usesWhewsSnet => _whewsSnetEnabled && _snetSource == 'whews';
  bool get _usesWhewsKma => _whewsKmaEnabled && _kmaSource == 'whews';

  /// CWA 图层是否可见

  final bool _cwaVisible = true;

  /// SeisJS 测站服务实例

  final SeisJsService _seisjsService = SeisJsService();

  /// SeisJS 测站数据订阅
  StreamSubscription? _seisjsSubscription;
  StreamSubscription? _lpgmSnapshotSubscription;

  /// SeisJS 测站列表

  List<SeisJsStation> _seisjsStations = [];

  /// SeisJS 图层是否可见

  final bool _seisjsVisible = true;

  final FdsnStationService _earthScopeStationService =
      FdsnStationService.earthScope;
  final FdsnStationService _geofonStationService = FdsnStationService.geofon;
  StreamSubscription? _earthScopeStationSubscription;
  StreamSubscription? _geofonStationSubscription;
  final FdsnMotionService _fdsnMotionService = FdsnMotionService();
  StreamSubscription? _fdsnMotionSubscription;
  List<FdsnStation> _earthScopeStations = [];
  List<FdsnStation> _geofonStations = [];
  final ValueNotifier<int> _niedLayerRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> _kmaLayerRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> _cwaLayerRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> _pAlertLayerRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> _seisJsLayerRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> _snetLayerRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> _earthScopeLayerRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> _geofonLayerRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> _liveWeatherTileRevision = ValueNotifier<int>(0);
  final ValueNotifier<bool> _blinkNotifier = ValueNotifier<bool>(true);
  Map<String, int> _earthScopeStationIndex = const {};
  Map<String, int> _geofonStationIndex = const {};
  bool _fdsnServicesActive = false;
  String _lastForegroundFdsnConfig = '';
  final Map<String, FdsnMotionSample> _pendingFdsnMotionSamples = {};
  final Map<String, FdsnMotionSample> _latestFdsnMotionSamples = {};
  final Map<String, DateTime> _latestFdsnMotionReceivedAt = {};
  final Map<String, DateTime> _lastFdsnUiUpdateAt = {};
  Timer? _fdsnMotionFlushTimer;
  Timer? _fdsnMotionRestartTimer;
  Timer? _liveWeatherTileRefreshTimer;
  String _liveWeatherTileOverlaySignature = '';
  Duration? _liveWeatherTileRefreshInterval;
  int _liveWeatherTileVersion = DateTime.now().millisecondsSinceEpoch;

  /// NIED 图层是否可见

  final bool _niedLayerVisible = true;

  /// EEW 鏃舵槸鍚﹂殣钘忚娴嬬綉鏍?

  bool _hideGridOnEew = false;

  /// EEW 鏍囪闂儊鐘舵€?

  bool get _blinkOn => _blinkNotifier.value;
  EventAnimationLease? _blinkClockLease;
  EventAnimationLease? _waveAutoZoomClockLease;
  LatLng? _preferredViewCenter;
  double? _preferredDefaultZoom;

  /// 涓婃棰勮浜嬩欢鏁伴噺 (鐢ㄤ簬妫€娴嬫柊浜嬩欢)

  /// 涓婃淇℃伅浜嬩欢鏁伴噺 (鐢ㄤ簬妫€娴嬫柊浜嬩欢)

  LpgmSnapshot? _latestLpgmSnapshot;
  final JmaVolcanoMapService _volcanoMapService = JmaVolcanoMapService();
  List<JmaVolcanoSite> _volcanoSites = [];
  final FanRadarService _fanRadarService = FanRadarService();
  final FanRadarService _precipitationService = FanRadarService.precipitation();
  StreamSubscription<FanRadarFrame?>? _precipitationSubscription;
  FanRadarFrame? _latestPrecipitationFrame;
  final ValueNotifier<int> _precipitationLayerRevision = ValueNotifier<int>(0);
  StreamSubscription<FanRadarFrame?>? _fanRadarSubscription;
  FanRadarFrame? _latestFanRadarFrame;
  final ValueNotifier<int> _fanRadarLayerRevision = ValueNotifier<int>(0);
  final JmaRadarService _jmaRadarService = JmaRadarService();
  StreamSubscription<JmaRadarFrame?>? _jmaRadarSubscription;
  JmaRadarFrame? _latestJmaRadarFrame;
  final ValueNotifier<int> _jmaRadarLayerRevision = ValueNotifier<int>(0);
  final FanSatelliteCloudService _fanSatelliteCloudService =
      FanSatelliteCloudService();
  StreamSubscription<FanSatelliteCloudFrame?>? _fanSatelliteCloudSubscription;
  FanSatelliteCloudFrame? _latestFanSatelliteCloudFrame;
  final ValueNotifier<int> _fanSatelliteCloudLayerRevision = ValueNotifier<int>(
    0,
  );

  /// Android 前台服务当前托管的低频图层连接。
  ///
  /// 这些图层仍由主 isolate 绘制，但请求和刷新由前台服务负责；集合用于
  /// 防止地图开关变化时重复启动前台服务重载。
  final Set<String> _foregroundHostedOverlayKeys = <String>{};
  int _lastTyphoonUpdateRevision = 0;
  ShakeDetectionSnapshot _latestDetectSnapshot = const ShakeDetectionSnapshot(
    stage: ShakeDetectStage.idle,
    weakCount: 0,
    detectedCount: 0,
    strongCount: 0,
    maxShindo: -1,
  );
  SeismicActiveEvent? _latestNiedSourceEvent;
  String? _lastNiedStationFocusSignature;
  DateTime? _lastNiedStationFocusAt;
  LatLng? _niedDetectEpicenter;
  String? _niedSourceWaveEventId;
  String _lastNiedSourceEstimateSignature = 'none';
  EventAnimationLease? _niedWaveClockLease;
  double? _niedWaveElapsedAnchorSeconds;
  final Stopwatch _niedWaveElapsedClock = Stopwatch();
  final ValueNotifier<int> _waveTick = ValueNotifier<int>(0);
  final SourceStationPhaseClassifier _sourceStationPhaseClassifier =
      const SourceStationPhaseClassifier();
  LatLng? _lastEpicenterFocus;
  String? _lastEpicenterSourceEventId;
  String? _lastKmaStationFocusSignature;
  DateTime? _lastKmaStationFocusAt;
  String? _lastTremStationFocusSignature;
  DateTime? _lastTremStationFocusAt;
  String? _lastPAlertStationFocusSignature;
  DateTime? _lastPAlertStationFocusAt;
  String _lastNiedLayerSignature = '';
  String _lastKmaLayerSignature = '';
  String _lastCwaLayerSignature = '';
  String _lastPAlertLayerSignature = '';
  String _lastSeisJsLayerSignature = '';
  String _lastSnetLayerSignature = '';
  String? _lastEventPointFocusSignature;
  String _lastCameraDatasetKey = '';
  bool _cameraPolicyQueued = false;
  bool _cameraPolicyForce = false;
  QuakeMessage? _preferredEventFocus;
  UnifiedQuakeData? _preferredUnifiedInfoFocus;
  int? _lastCameraCarouselIndex;
  final _desktopEventCameraFocus = DesktopEventCameraFocus();
  final _desktopEewCameraGates = <String, EewWaveCameraFollowGate>{};
  List<LatLng> _preferredEventFocusPoints = const [];
  DateTime? _preferredEventFocusUntil;
  String? _preferredEventFocusSignature;
  Timer? _preferredEventFocusTimer;
  final EewWaveCameraFollowGate _eewWaveCameraFollowGate =
      EewWaveCameraFollowGate();
  String _lastEewTakeoverSignature = '';
  String? _lastSelectedHistoryCameraKey;
  bool _pendingNiedStationFocus = false;
  bool _pendingKmaStationFocus = false;
  bool _pendingTremStationFocus = false;
  bool _pendingPAlertStationFocus = false;
  QuakeProvider? _quakeProvider;
  MapStateProvider? _mapStateProvider;
  bool _providerCallbacksBound = false;
  bool _mapDataServicesStarted = false;
  // 初始设为 true，保证第一次 _resumeMapDataServices 会真正启动数据源。
  // 进入后台时 _pauseMapDataServices 会将其置回 true，回到前台再恢复。
  bool _backgroundPaused = true;
  bool _initialCameraPolicyApplied = false;
  bool _lastCanAutoFollow = true;
  final AllowAnyCertTileProvider _tileProvider = AllowAnyCertTileProvider();
  final StreamController<void> _tileResetController =
      StreamController<void>.broadcast();

  void _handleTileLoadError(
    TileImage tile,
    Object error,
    StackTrace? stackTrace,
  ) {
    // 瓦片底层 RetryClient 已在 HTTP 层面进行 3 次重试。
    // 避免在此处调用全局 _tileResetController.add(null) 导致全图重置风暴（销毁所有已加载瓦片）。
    debugPrint('[MapTile] tile load error (${tile.coordinates}): $error');
  }

  bool get _showNiedEstimatedEpicenter =>
      _mapStateProvider?.showEstimatedEpicenter ?? false;

  SourceEstimate? get _latestNiedSourceEstimate =>
      _latestNiedSourceEvent?.estimate;

  bool get _hasNiedSourceEstimate =>
      _latestNiedSourceEstimate != null ||
      (_latestNiedSourceEvent != null &&
          _niedPublishedSourceEstimates(_latestNiedSourceEvent!).isNotEmpty);

  /// 涓存椂淇℃伅浜嬩欢瀹氫綅璁℃椂鍣?

  /// 鍒濆鍖栫姸鎬?  ///
  /// 鍚姩鎵€鏈夌洃娴嬫湇鍔″苟璁㈤槄鏁版嵁娴併€?  @override
  @override
  void initState() {
    super.initState();
    _loadCameraDefaults();
    _volcanoSites = _volcanoMapService.sites;
    _volcanoMapService.onSitesUpdated = (items) {
      if (!mounted) return;
      setState(() => _volcanoSites = items);
    };
    _latestFanRadarFrame = _fanRadarService.latestFrame;
    _latestPrecipitationFrame = _precipitationService.latestFrame;
    _precipitationSubscription = _precipitationService.frameStream.listen((frame) {
      if (!mounted) return;
      _latestPrecipitationFrame = frame;
      _notifyLayer(_precipitationLayerRevision);
    });
    _fanRadarSubscription = _fanRadarService.frameStream.listen((frame) {
      if (!mounted) return;
      _latestFanRadarFrame = frame;
      _notifyLayer(_fanRadarLayerRevision);
    });
    _latestJmaRadarFrame = _jmaRadarService.latestFrame;
    _jmaRadarSubscription = _jmaRadarService.frameStream.listen((frame) {
      if (!mounted) return;
      _latestJmaRadarFrame = frame;
      _notifyLayer(_jmaRadarLayerRevision);
    });
    _latestFanSatelliteCloudFrame = _fanSatelliteCloudService.latestFrame;
    _fanSatelliteCloudSubscription = _fanSatelliteCloudService.frameStream
        .listen((frame) {
          if (!mounted) return;
          _latestFanSatelliteCloudFrame = frame;
          _notifyLayer(_fanSatelliteCloudLayerRevision);
        });
    QuakeMapView.fdsnStationLimitNotifier.addListener(
      _onFdsnStationLimitChanged,
    );
    QuakeMapView.tremStationEnabledNotifier.addListener(
      _onTremStationEnabledChanged,
    );
    QuakeMapView.displayShindo0Notifier.addListener(_onDisplayShindo0Changed);
    QuakeMapView.kmaIntensityHoldNotifier.addListener(
      _onKmaIntensityHoldChanged,
    );
    QuakeMapView.wolfxSeisJsEnabledNotifier.addListener(
      _onWolfxSeisJsEnabledChanged,
    );
    QuakeMapView.kmaPewsEnabledNotifier.addListener(_onKmaPewsEnabledChanged);
    QuakeMapView.kmaSourceNotifier.addListener(_onKmaSourceChanged);
    QuakeMapView.pAlertEnabledNotifier.addListener(_onPAlertEnabledChanged);
    UiRuntimeFlags.hideGridOnEewNotifier.addListener(_onHideGridOnEewChanged);
    QuakeMapView.niedMonitorEnabledNotifier.addListener(
      _onNiedMonitorEnabledChanged,
    );
    QuakeMapView.niedLpgmEnabledNotifier.addListener(_onNiedLpgmEnabledChanged);
    QuakeMapView.snetEnabledNotifier.addListener(_onSnetEnabledChanged);
    QuakeMapView.snetSourceNotifier.addListener(_onSnetSourceChanged);
    QuakeMapView.fdsnSeedLinkEnabledNotifier.addListener(
      _onFdsnSeedLinkEnabledChanged,
    );
    QuakeMapView.whewsNiedEnabledNotifier.addListener(
      _onWhewsNiedEnabledChanged,
    );
    QuakeMapView.whewsSnetEnabledNotifier.addListener(
      _onWhewsSnetEnabledChanged,
    );
    QuakeMapView.whewsKmaEnabledNotifier.addListener(_onWhewsKmaEnabledChanged);
    QuakeMapView.whewsApiTokenNotifier.addListener(_onWhewsApiTokenChanged);
    LocationService().positionListenable.addListener(_onUserLocationChanged);
    _latestNiedSourceEvent =
        StationEventTracker.instance.currentNiedEvent.value;
    StationEventTracker.instance.currentNiedEvent.addListener(
      _onNiedSourceEventChanged,
    );
    _kmaStationSubscription = _kmaService.stationStream.listen((stations) {
      if (!mounted) return;
      _ingestKmaAutomationStations(stations);
      final signature = _kmaLayerSignature(stations);
      if (signature != _lastKmaLayerSignature) {
        _lastKmaLayerSignature = signature;
        _kmaStations = stations;
        _notifyLayer(_kmaLayerRevision);
      } else {
        _kmaStations = stations;
      }
      if (_pendingKmaStationFocus) {
        _pendingKmaStationFocus = false;
        _requestKmaStationFocus(force: true);
      }
      _syncActivityTimers();
      _emitStationSummary();
    });
    _whewsNiedSubscription = _whewsNiedService.frameStream.listen(
      _onWhewsNiedFrame,
    );
    _whewsSnetSubscription = _whewsSnetService.frameStream.listen(
      _onWhewsSnetFrame,
    );
    _whewsKmaSubscription = _whewsKmaService.frameStream.listen(
      _onWhewsKmaFrame,
    );
    _whewsNiedService.stateNotifier.addListener(_onWhewsNiedStateChanged);
    _whewsSnetService.stateNotifier.addListener(_onWhewsSnetStateChanged);
    _whewsKmaService.stateNotifier.addListener(_onWhewsKmaStateChanged);
    _foregroundStationSubscription = BackgroundService().onForegroundStationData
        .listen(_onForegroundStationData);
    _cwaStationSubscription = _cwaService.stationStream.listen((stations) {
      if (!mounted) return;
      _ingestTremAutomationStations(stations);
      final signature = _cwaLayerSignature(stations);
      if (signature != _lastCwaLayerSignature) {
        _lastCwaLayerSignature = signature;
        _cwaStations = stations;
        _notifyLayer(_cwaLayerRevision);
      } else {
        _cwaStations = stations;
      }
      if (_pendingTremStationFocus) {
        _pendingTremStationFocus = false;
        _requestTremStationFocus(force: true);
      }
      _syncActivityTimers();
      _emitStationSummary();
    });
    _pAlertStationSubscription = _pAlertService.stationStream.listen((
      stations,
    ) {
      if (!mounted) return;
      _processPAlertSourceEstimation(stations, {
        for (final entry in _pAlertService.detectionSnapshot.detectedStations)
          entry.code,
      });
      _ingestPAlertAutomationStations(stations);
      final signature = _pAlertLayerSignature(stations);
      if (signature != _lastPAlertLayerSignature) {
        _lastPAlertLayerSignature = signature;
        _pAlertStations = stations;
        _notifyLayer(_pAlertLayerRevision);
      } else {
        _pAlertStations = stations;
      }
      _emitStationSummary();
    });
    _seisjsSubscription = _seisjsService.stationStream.listen((stations) {
      if (!mounted) return;
      _ingestSeisJsAutomationStations(stations);
      final signature = _seisJsLayerSignature(stations);
      if (signature != _lastSeisJsLayerSignature) {
        _lastSeisJsLayerSignature = signature;
        _seisjsStations = stations;
        _notifyLayer(_seisJsLayerRevision);
      } else {
        _seisjsStations = stations;
      }
      _emitStationSummary();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startMapDataServices();
    });
    if (BackgroundService().isBackgroundHandlingEnabled) {
      BackgroundService().addStateListener(_onBackgroundStateChanged);
    }
    BackgroundService().connectionHostingNotifier.addListener(
      _onConnectionHostingChanged,
    );
  }

  void _onConnectionHostingChanged() {
    if (!mounted) return;
    if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
      _pauseMapDataServices();
    } else {
      _resumeMapDataServices();
    }
  }

  void _onForegroundStationData(Map<String, dynamic> payload) {
    if (!mounted ||
        !BackgroundService().isAndroidConnectionHostedByForegroundService) {
      return;
    }
    final kind = payload['kind']?.toString();
    if (kind == 'signal') {
      _handleForegroundStationSignal(payload);
      return;
    }
    final rawStations = payload['stations'];
    switch (kind) {
      case 'nied':
        if (!_niedMonitorEnabled || _usesWhewsNied || _niedSource == 'whews') {
          return;
        }
        final source = payload['source']?.toString();
        if (source != null && source != _niedSource) return;
        final stations = ForegroundStationPayload.decodeNied(rawStations);
        DateTime? frameTime;
        for (final station in stations) {
          final stamp = station.lastDataTime;
          if (stamp != null &&
              (frameTime == null || stamp.isAfter(frameTime))) {
            frameTime = stamp;
          }
        }
        if (_useYahooSource) {
          _yahooService.dataFrameTime.value = frameTime;
        } else {
          NiedMonitorService().dataFrameTime.value = frameTime;
        }
        _acceptNiedStations(stations);
      case 'kma':
        if (_usesWhewsKma || !_kmaPewsEnabled) return;
        _kmaService.dataTimeNotifier.value = ForegroundStationPayload.frameTime(
          payload,
        );
        final stations = ForegroundStationPayload.decodeKma(rawStations);
        _kmaStations = stations;
        _ingestKmaAutomationStations(stations);
        final signature = _kmaLayerSignature(stations);
        if (signature != _lastKmaLayerSignature) {
          _lastKmaLayerSignature = signature;
          _notifyLayer(_kmaLayerRevision);
        }
        _requestKmaStationFocus(force: true);
        _syncActivityTimers();
        _emitStationSummary();
      case 'cwa':
        if (!_tremStationEnabled) return;
        _cwaService.dataTimeNotifier.value = ForegroundStationPayload.frameTime(
          payload,
        );
        final stations = ForegroundStationPayload.decodeCwa(rawStations);
        _cwaStations = stations;
        _ingestTremAutomationStations(stations);
        final signature = _cwaLayerSignature(stations);
        if (signature != _lastCwaLayerSignature) {
          _lastCwaLayerSignature = signature;
          _notifyLayer(_cwaLayerRevision);
        }
        _requestTremStationFocus(force: true);
        _syncActivityTimers();
        _emitStationSummary();
      case 'snet':
        if (_usesWhewsSnet || !_snetEnabled) return;
        final stations = ForegroundStationPayload.decodeSnet(rawStations);
        _snetService.ingestExternalStations(stations);
        _lastSnetLayerSignature = _snetLayerSignature(stations);
        _notifyLayer(_snetLayerRevision);
        _emitStationSummary();
      case 'seisjs':
        if (!_wolfxSeisJsEnabled) return;
        _seisjsService.dataTimeNotifier.value =
            ForegroundStationPayload.frameTime(payload);
        final stations = ForegroundStationPayload.decodeSeisJs(rawStations);
        _seisjsStations = stations;
        _ingestSeisJsAutomationStations(stations);
        final signature = _seisJsLayerSignature(stations);
        if (signature != _lastSeisJsLayerSignature) {
          _lastSeisJsLayerSignature = signature;
          _notifyLayer(_seisJsLayerRevision);
        }
        _emitStationSummary();
      case 'palert':
        if (!_pAlertEnabled) return;
        _pAlertService.dataTimeNotifier.value =
            ForegroundStationPayload.frameTime(payload);
        _pAlertService.receivedTimeNotifier.value = DateTime.tryParse(
          payload['receivedTime']?.toString() ?? '',
        );
        final stations = ForegroundStationPayload.decodePAlert(rawStations);
        _processPAlertSourceEstimation(stations,
          ForegroundStationPayload.decodePAlertDetectedStationIds(
            payload, now: DateTime.now(),
          ));
        _pAlertStations = stations;
        _ingestPAlertAutomationStations(stations);
        _updatePAlertDetectionGrid(
          ForegroundStationPayload.decodePAlertDetection(
            payload, now: DateTime.now(),
          ),
        );
        final signature = _pAlertLayerSignature(stations);
        if (signature != _lastPAlertLayerSignature) {
          _lastPAlertLayerSignature = signature;
          _notifyLayer(_pAlertLayerRevision);
        }
        _emitStationSummary();
      case 'lpgm':
        if (!_niedLpgmEnabled) return;
        final snapshot = ForegroundStationPayload.decodeLpgm(payload);
        if (snapshot == null) return;
        _latestLpgmSnapshot = snapshot;
        _emitStationSummary();
      case 'fdsnStations':
        final source = payload['source']?.toString();
        final stations = ForegroundStationPayload.decodeFdsnStations(
          rawStations,
        );
        if (source == 'EarthScope') {
          _earthScopeStations = _applyLatestFdsnMotionToStations(stations);
          _earthScopeStationIndex = _buildFdsnStationIndex(_earthScopeStations);
          _notifyLayer(_earthScopeLayerRevision);
        } else if (source == 'GEOFON') {
          _geofonStations = _applyLatestFdsnMotionToStations(stations);
          _geofonStationIndex = _buildFdsnStationIndex(_geofonStations);
          _notifyLayer(_geofonLayerRevision);
        }
      case 'fdsnMotion':
        final sample = ForegroundStationPayload.decodeFdsnMotion(payload);
        if (sample != null) _handleFdsnMotionSample(sample);
      case 'volcanoSites':
        _volcanoMapService.acceptSitesSnapshot(
          ForegroundStationPayload.decodeVolcanoSites(payload['sites']),
        );
      case 'fanRadar':
        final frame = ForegroundStationPayload.decodeFanRadar(payload);
        if (frame != null) {
          _latestFanRadarFrame = frame;
          _notifyLayer(_fanRadarLayerRevision);
        }
      case 'jmaRadar':
        final frame = ForegroundStationPayload.decodeJmaRadar(payload);
        if (frame != null) {
          _latestJmaRadarFrame = frame;
          _notifyLayer(_jmaRadarLayerRevision);
        }
      case 'cmaPrecipitation':
        if (_mapStateProvider?.isOverlayEnabled('precipitationChinaLayer') != true) return;
        final frame = ForegroundStationPayload.decodeFanRadar(payload);
        if (frame != null) {
          _latestPrecipitationFrame = frame;
          _notifyLayer(_precipitationLayerRevision);
        }
      case 'fanSatellite':
        final frame = ForegroundStationPayload.decodeFanSatellite(payload);
        if (frame != null) {
          _latestFanSatelliteCloudFrame = frame;
          _notifyLayer(_fanSatelliteCloudLayerRevision);
        }
      case 'whewsNied':
        if (!_usesWhewsNied || !_niedMonitorEnabled) return;
        final frame = _decodeForegroundWhewsFrame(payload);
        if (frame != null) _onWhewsNiedFrame(frame);
      case 'whewsSnet':
        if (!_usesWhewsSnet || !_snetEnabled) return;
        final frame = _decodeForegroundWhewsFrame(payload);
        if (frame != null) _onWhewsSnetFrame(frame);
      case 'whewsKma':
        if (!_usesWhewsKma || !_kmaPewsEnabled) return;
        final frame = _decodeForegroundWhewsFrame(payload);
        if (frame != null) _onWhewsKmaFrame(frame);
    }
  }

  WhewsStationFrame? _decodeForegroundWhewsFrame(Map<String, dynamic> payload) {
    final dataTime = DateTime.tryParse(payload['dataTime']?.toString() ?? '');
    final rawCoordinates = payload['coordinates'];
    final rawValues = payload['values'];
    if (dataTime == null || rawCoordinates is! List || rawValues is! List) {
      return null;
    }
    final coordinates = <LatLng>[];
    for (final raw in rawCoordinates.whereType<Map>()) {
      final lat = _foregroundNumber(raw['lat']);
      final lng = _foregroundNumber(raw['lng']);
      if (lat == null || lng == null) return null;
      coordinates.add(LatLng(lat, lng));
    }
    final values = rawValues
        .map(_foregroundNumber)
        .whereType<double>()
        .toList();
    if (coordinates.length != values.length) return null;
    final pga = _foregroundNumbers(payload['pga']);
    final pgv = _foregroundNumbers(payload['pgv']);
    return WhewsStationFrame(
      kind: WhewsStationKind.nied,
      dataTime: dataTime,
      coordinates: coordinates,
      values: values,
      pga: pga,
      pgv: pgv,
    );
  }

  void _handleForegroundStationSignal(Map<String, dynamic> payload) {
    final source = payload['source']?.toString();
    final action = payload['action']?.toString();
    final value = _foregroundNumber(payload['value']);
    final detectedAt = DateTime.tryParse(payload['detectedAt']?.toString() ?? '');
    if (source == 'kma') {
      if (action == 'detected' && value != null) {
        final intensity = value.round();
        _obsAutomationInputs.ingestLegacyNetworkDetection(
          network: 'kma',
          maxIntensity: intensity,
          observedAt: DateTime.now(),
        );
        _onKmaShakeDetected(intensity, detectedAt: detectedAt);
      } else if (action == 'expired') {
        _obsAutomationInputs.endLegacyNetworkDetection(
          network: 'kma',
          observedAt: DateTime.now(),
        );
        _onKmaShakeExpired();
      }
    } else if (source == 'trem') {
      if (action == 'detected' && value != null) {
        final intensity = value.round();
        _obsAutomationInputs.ingestLegacyNetworkDetection(
          network: 'trem',
          maxIntensity: intensity,
          observedAt: DateTime.now(),
        );
        _onTremShakeDetected(intensity, detectedAt: detectedAt);
      } else if (action == 'expired') {
        _obsAutomationInputs.endLegacyNetworkDetection(
          network: 'trem',
          observedAt: DateTime.now(),
        );
        _onTremShakeExpired();
      }
    } else if (source == 'palert') {
      if (action == 'detected' && value != null) {
        final intensity = value.round();
        _obsAutomationInputs.ingestLegacyNetworkDetection(
          network: 'palert',
          maxIntensity: intensity,
          observedAt: DateTime.now(),
        );
        _onPAlertShakeDetected(intensity, detectedAt: detectedAt);
      } else if (action == 'expired') {
        _obsAutomationInputs.endLegacyNetworkDetection(
          network: 'palert',
          observedAt: DateTime.now(),
        );
        _onPAlertShakeExpired();
      }
    }
  }

  static double? _foregroundNumber(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static List<double> _foregroundNumbers(dynamic value) {
    if (value is! List) return const [];
    return value.map(_foregroundNumber).whereType<double>().toList();
  }

  Future<void> _startMapDataServices() async {
    if (!mounted || _mapDataServicesStarted) return;
    _mapDataServicesStarted = true;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _tremStationEnabled =
        prefs.getBool(QuakeMapView.tremStationEnabledPreferenceKey) ?? true;
    _displayShindo0 =
        prefs.getBool(QuakeMapView.displayShindo0PreferenceKey) ?? false;
    _kmaIntensityHoldFrames =
        prefs.getInt(QuakeMapView.kmaIntensityHoldPreferenceKey) ?? 1;
    _wolfxSeisJsEnabled =
        prefs.getBool(QuakeMapView.wolfxSeisJsEnabledPreferenceKey) ?? true;
    _kmaPewsEnabled =
        prefs.getBool(QuakeMapView.kmaPewsEnabledPreferenceKey) ?? true;
    final savedKmaSource = prefs.getString(
      QuakeMapView.kmaDataSourcePreferenceKey,
    );
    _kmaSource = switch (savedKmaSource) {
      'fan' => 'fan',
      'whews' => 'whews',
      _ => 'pews',
    };
    _pAlertEnabled =
        prefs.getBool(QuakeMapView.pAlertEnabledPreferenceKey) ?? true;
    _niedMonitorEnabled =
        prefs.getBool(QuakeMapView.niedMonitorEnabledPreferenceKey) ?? true;
    _niedLpgmEnabled =
        prefs.getBool(QuakeMapView.niedLpgmEnabledPreferenceKey) ?? true;
    _snetEnabled = prefs.getBool(QuakeMapView.snetEnabledPreferenceKey) ?? true;
    _snetSource =
        prefs.getString(QuakeMapView.snetDataSourcePreferenceKey) == 'whews'
        ? 'whews'
        : 'msil';
    _fdsnSeedLinkEnabled =
        prefs.getBool(QuakeMapView.fdsnSeedLinkEnabledPreferenceKey) ?? false;
    FdsnIntensity.scale.value = FdsnIntensity.parseScale(
      prefs.getString(FdsnIntensity.preferenceKey),
    );
    final whewsToken = QuakeMapView.whewsApiTokenNotifier.value;
    final whewsAuthorized =
        (prefs.getBool(WhewsService.apiAuthorizedPreferenceKey) ?? false) &&
        whewsToken.trim().isNotEmpty;
    _whewsNiedEnabled =
        whewsAuthorized &&
        (prefs.getBool(QuakeMapView.whewsNiedEnabledPreferenceKey) ?? false);
    _whewsSnetEnabled =
        whewsAuthorized &&
        (prefs.getBool(QuakeMapView.whewsSnetEnabledPreferenceKey) ?? false);
    _whewsKmaEnabled =
        whewsAuthorized &&
        (prefs.getBool(QuakeMapView.whewsKmaEnabledPreferenceKey) ?? false);
    if (_kmaSource == 'whews' && !_whewsKmaEnabled) {
      _kmaSource = 'pews';
      unawaited(
        prefs.setString(QuakeMapView.kmaDataSourcePreferenceKey, _kmaSource),
      );
    }
    if (_snetSource == 'whews' && !_whewsSnetEnabled) {
      _snetSource = 'msil';
      unawaited(
        prefs.setString(QuakeMapView.snetDataSourcePreferenceKey, _snetSource),
      );
    }
    _whewsNiedService.setApiToken(whewsToken);
    _whewsSnetService.setApiToken(whewsToken);
    _whewsKmaService.setApiToken(whewsToken);
    QuakeMapView.whewsApiTokenNotifier.value = whewsToken;
    QuakeMapView.tremStationEnabledNotifier.value = _tremStationEnabled;
    QuakeMapView.displayShindo0Notifier.value = _displayShindo0;
    QuakeMapView.kmaIntensityHoldNotifier.value = _kmaIntensityHoldFrames;
    _kmaService.setIntensityHoldFrames(_kmaIntensityHoldFrames);
    QuakeMapView.wolfxSeisJsEnabledNotifier.value = _wolfxSeisJsEnabled;
    QuakeMapView.kmaPewsEnabledNotifier.value = _kmaPewsEnabled;
    QuakeMapView.kmaSourceNotifier.value = _kmaSource;
    QuakeMapView.pAlertEnabledNotifier.value = _pAlertEnabled;
    QuakeMapView.niedMonitorEnabledNotifier.value = _niedMonitorEnabled;
    QuakeMapView.niedLpgmEnabledNotifier.value = _niedLpgmEnabled;
    QuakeMapView.snetEnabledNotifier.value = _snetEnabled;
    QuakeMapView.snetSourceNotifier.value = _snetSource;
    QuakeMapView.fdsnSeedLinkEnabledNotifier.value = _fdsnSeedLinkEnabled;
    QuakeMapView.whewsNiedEnabledNotifier.value = _whewsNiedEnabled;
    QuakeMapView.whewsSnetEnabledNotifier.value = _whewsSnetEnabled;
    QuakeMapView.whewsKmaEnabledNotifier.value = _whewsKmaEnabled;
    // 托管连接也需要源选择和检知监听，不能依赖可被取消的网络启动定时器。
    await _initNiedBindings();
    if (!mounted) return;
    _resumeMapDataServices();
  }

  Timer? _staggeredStartupTimerT1;
  Timer? _staggeredStartupTimerT2;

  void _cancelStaggeredStartupTimers() {
    _staggeredStartupTimerT1?.cancel();
    _staggeredStartupTimerT1 = null;
    _staggeredStartupTimerT2?.cancel();
    _staggeredStartupTimerT2 = null;
  }

  /// 后台状态变化回调
  void _onBackgroundStateChanged(AppLifecycleStateExt state) {
    if (!mounted) return;
    if (state == AppLifecycleStateExt.background) {
      _pauseMapDataServices();
    } else {
      _resumeMapDataServices();
    }
  }

  /// 进入后台时暂停地图/测站等高功耗数据源
  void _pauseMapDataServices() {
    _cancelStaggeredStartupTimers();
    if (_backgroundPaused) return;
    _backgroundPaused = true;
    _kmaService.disconnect();
    _seisjsService.disconnect();
    _pAlertService.stop();
    _lmoniService.stop();
    _yahooService.stop();
    NiedMonitorService().stop();
    NiedBackgroundWorker.instance.stop();
    _lpgmService.stop();
    _snetService.stopMonitoring();
    _cwaService.stop();
    _fdsnMotionService.disconnect();
    _volcanoMapService.stop();
    _fanRadarService.stop();
    _precipitationService.stop();
    _jmaRadarService.stop();
    _fanSatelliteCloudService.stop();
    _whewsNiedService.stop();
    _whewsSnetService.stop();
    _whewsKmaService.stop();
  }

  /// 回到前台或启动时根据当前设置阶梯化恢复地图/测站数据源（Staggered Loading，彻底消除启动峰值）
  void _resumeMapDataServices() {
    if (!_backgroundPaused) return;
    _backgroundPaused = false;
    if (!mounted) return;
    _cancelStaggeredStartupTimers();

    // 【T0 首屏：0ms】立即接入核心活跃地震测站（NIED, S-net, KMA, CWA），无卡顿
    _syncNiedMonitorService();
    _syncSnetService();
    _syncKmaPewsService();
    _syncTremStationService();

    // 【T1 核心测站网络接入：700ms】在首屏完全稳定就绪后，接入 NIED 图像切片解析与次级测站
    _staggeredStartupTimerT1 = Timer(const Duration(milliseconds: 700), () {
      if (!mounted || _backgroundPaused) return;
      _syncLpgmMonitorService();
      _syncPAlertService();
      _syncWolfxSeisJsService();
    });

    // 【T2 重型气象与辅助环境数据：1800ms】平滑接入雷达、云图、火山与天气切片
    _staggeredStartupTimerT2 = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted || _backgroundPaused) return;
      _syncVolcanoMapServiceWithOverlay();
      _syncFanRadarServiceWithOverlay();
      _syncPrecipitationServiceWithOverlay();
      _syncJmaRadarServiceWithOverlay();
      _syncFanSatelliteCloudServiceWithOverlay();
      _syncLiveWeatherTileRefresh();
      _syncFdsnServicesWithOverlay();
    });
  }

  void _onTremStationEnabledChanged() {
    if (!mounted) return;
    final enabled = QuakeMapView.tremStationEnabledNotifier.value;
    if (_tremStationEnabled == enabled) return;
    _tremStationEnabled = enabled;
    _syncTremStationService();
  }

  void _onDisplayShindo0Changed() {
    if (!mounted) return;
    final enabled = QuakeMapView.displayShindo0Notifier.value;
    if (_displayShindo0 == enabled) return;
    _displayShindo0 = enabled;
    _notifyLayer(_niedLayerRevision);
    _notifyLayer(_kmaLayerRevision);
    _notifyLayer(_cwaLayerRevision);
    _notifyLayer(_pAlertLayerRevision);
  }

  void _onKmaIntensityHoldChanged() {
    final frames = QuakeMapView.kmaIntensityHoldNotifier.value.clamp(1, 60);
    if (_kmaIntensityHoldFrames == frames) return;
    _kmaIntensityHoldFrames = frames;
    _kmaService.setIntensityHoldFrames(frames);
  }

  void _onWolfxSeisJsEnabledChanged() {
    if (!mounted) return;
    final enabled = QuakeMapView.wolfxSeisJsEnabledNotifier.value;
    if (_wolfxSeisJsEnabled == enabled) return;
    _wolfxSeisJsEnabled = enabled;
    _syncWolfxSeisJsService();
  }

  void _onKmaPewsEnabledChanged() {
    if (!mounted) return;
    final enabled = QuakeMapView.kmaPewsEnabledNotifier.value;
    if (_kmaPewsEnabled == enabled) return;
    _kmaPewsEnabled = enabled;
    _syncKmaPewsService();
  }

  void _onKmaSourceChanged() {
    if (!mounted) return;
    var source = QuakeMapView.kmaSourceNotifier.value;
    if (source == 'whews' && !_whewsKmaEnabled) {
      source = 'pews';
      QuakeMapView.kmaSourceNotifier.value = source;
    }
    if (_kmaSource == source) return;
    _kmaSource = source;
    _kmaService.disconnect();
    _whewsKmaService.stop();
    _kmaService.setConnectionSource(source);
    _kmaService.setExternalInputEnabled(source == 'whews');
    _clearKmaDisplayState();
    _syncKmaPewsService();
  }

  void _onPAlertEnabledChanged() {
    if (!mounted) return;
    final enabled = QuakeMapView.pAlertEnabledNotifier.value;
    if (_pAlertEnabled == enabled) return;
    _pAlertEnabled = enabled;
    _syncPAlertService();
  }

  void _onNiedMonitorEnabledChanged() {
    if (!mounted) return;
    final enabled = QuakeMapView.niedMonitorEnabledNotifier.value;
    if (_niedMonitorEnabled == enabled) return;
    _niedMonitorEnabled = enabled;
    _syncNiedMonitorService();
  }

  void _onNiedLpgmEnabledChanged() {
    if (!mounted) return;
    final enabled = QuakeMapView.niedLpgmEnabledNotifier.value;
    if (_niedLpgmEnabled == enabled) return;
    _niedLpgmEnabled = enabled;
    _syncLpgmMonitorService();
  }

  void _onSnetEnabledChanged() {
    if (!mounted) return;
    final enabled = QuakeMapView.snetEnabledNotifier.value;
    if (_snetEnabled == enabled) return;
    _snetEnabled = enabled;
    _syncSnetService();
  }

  void _onSnetSourceChanged() {
    if (!mounted) return;
    var source = QuakeMapView.snetSourceNotifier.value;
    if (source == 'whews' && !_whewsSnetEnabled) {
      source = 'msil';
      QuakeMapView.snetSourceNotifier.value = source;
    }
    if (_snetSource == source) return;
    _snetSource = source;
    _obsAutomationInputs.clearStationNetwork('snet');
    _snetService.stopMonitoring();
    _whewsSnetService.stop();
    _whewsSnetStations = [];
    _lastSnetLayerSignature = '';
    _syncSnetService();
    _notifyLayer(_snetLayerRevision);
    _emitStationSummary();
  }

  void _onFdsnSeedLinkEnabledChanged() {
    if (!mounted) return;
    final enabled = QuakeMapView.fdsnSeedLinkEnabledNotifier.value;
    if (_fdsnSeedLinkEnabled == enabled) return;
    _fdsnSeedLinkEnabled = enabled;
    _syncFdsnServicesWithOverlay();
  }

  void _onWhewsNiedEnabledChanged() {
    if (!mounted) return;
    _whewsNiedEnabled = QuakeMapView.whewsNiedEnabledNotifier.value;
    _syncNiedMonitorService();
  }

  void _onWhewsSnetEnabledChanged() {
    if (!mounted) return;
    _whewsSnetEnabled = QuakeMapView.whewsSnetEnabledNotifier.value;
    _syncSnetService();
  }

  void _onWhewsKmaEnabledChanged() {
    if (!mounted) return;
    _whewsKmaEnabled = QuakeMapView.whewsKmaEnabledNotifier.value;
    _syncKmaPewsService();
  }

  void _onWhewsApiTokenChanged() {
    final token = QuakeMapView.whewsApiTokenNotifier.value;
    _whewsNiedService.setApiToken(token);
    _whewsSnetService.setApiToken(token);
    _whewsKmaService.setApiToken(token);
  }

  void _onWhewsNiedStateChanged() {
    if (!_usesWhewsNied) return;
    _updateWhewsStationStatus('NIED', _whewsNiedService.stateNotifier.value);
  }

  void _onWhewsSnetStateChanged() {
    if (!_usesWhewsSnet) return;
    _updateWhewsStationStatus('S-net', _whewsSnetService.stateNotifier.value);
  }

  void _onWhewsKmaStateChanged() {
    if (!_usesWhewsKma) return;
    _updateWhewsStationStatus('KMA', _whewsKmaService.stateNotifier.value);
  }

  void _updateWhewsStationStatus(String source, WhewsSocketState state) {
    final status = switch (state) {
      WhewsSocketState.connected => SourceStatus.connected,
      WhewsSocketState.connecting => SourceStatus.connecting,
      WhewsSocketState.disconnected => SourceStatus.disconnected,
      WhewsSocketState.unauthorized ||
      WhewsSocketState.error => SourceStatus.error,
    };
    _quakeProvider?.updateSourceStatus(source, status);
  }

  void _syncKmaPewsService() {
    if (!_kmaPewsEnabled) {
      _kmaService.disconnect();
      _whewsKmaService.stop();
      _kmaService.resetRealtimeState();
      _clearKmaDisplayState();
      _quakeProvider?.updateSourceStatus('KMA', SourceStatus.disconnected);
      if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
        unawaited(BackgroundService().requestSourceReload());
      }
      return;
    }

    if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
      _kmaService.disconnect();
      _whewsKmaService.stop();
      _kmaService.setExternalInputEnabled(_usesWhewsKma);
      unawaited(BackgroundService().requestSourceReload());
      return;
    }

    if (_usesWhewsKma) {
      _kmaService.disconnect();
      _kmaService.setExternalInputEnabled(true);
      _whewsKmaService.start();
      return;
    }

    _whewsKmaService.stop();
    _kmaService.setConnectionSource(_kmaSource);
    _kmaService.setExternalInputEnabled(false);
    _kmaService.connect();
  }

  void _clearKmaDisplayState() {
    _obsAutomationInputs.clearStationNetwork('kma');
    _kmaStations = const [];
    _kmaGridCellCenters.clear();
    _lastKmaLayerSignature = '';
    _lastKmaStationFocusSignature = null;
    _lastKmaStationFocusAt = null;
    _pendingKmaStationFocus = false;
    _notifyLayer(_kmaLayerRevision);
    _emitStationSummary();
  }

  void _syncWolfxSeisJsService() {
    if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
      _seisjsService.disconnect();
      if (_wolfxSeisJsEnabled) {
        unawaited(BackgroundService().requestSourceReload());
      } else {
        _obsAutomationInputs.clearStationNetwork('seisjs');
        _seisjsStations = const [];
        _notifyLayer(_seisJsLayerRevision);
        _emitStationSummary();
      }
      return;
    }
    if (_wolfxSeisJsEnabled) {
      _seisjsService.connect();
      return;
    }
    _seisjsService.disconnect();
    _obsAutomationInputs.clearStationNetwork('seisjs');
    _seisjsStations = const [];
    _lastSeisJsLayerSignature = '';
    _notifyLayer(_seisJsLayerRevision);
    _quakeProvider?.updateSourceStatus('SeisJS', SourceStatus.disconnected);
    _emitStationSummary();
  }

  void _syncPAlertService() {
    if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
      _pAlertService.stop();
      if (_pAlertEnabled) {
        unawaited(BackgroundService().requestSourceReload());
      } else {
        _obsAutomationInputs.clearStationNetwork('palert');
        _pAlertStations = const [];
        _clearPAlertStationFocus();
        _notifyLayer(_pAlertLayerRevision);
        _emitStationSummary();
      }
      return;
    }
    if (_pAlertEnabled) {
      _quakeProvider?.updateSourceStatus('P-Alert', SourceStatus.connecting);
      _pAlertService.start();
      return;
    }
    _pAlertService.stop();
    _obsAutomationInputs.clearStationNetwork('palert');
    _pAlertStations = const [];
    _lastPAlertLayerSignature = '';
    _clearPAlertStationFocus();
    _notifyLayer(_pAlertLayerRevision);
    _quakeProvider?.updateSourceStatus('P-Alert', SourceStatus.disconnected);
    _emitStationSummary();
  }

  void _syncNiedMonitorService() {
    _whewsNiedFrameSerial++;
    if (!_niedMonitorEnabled) {
      NiedMonitorService().setPhysicalLayersEnabled(false);
      _lmoniService.stop();
      _yahooService.stop();
      NiedMonitorService().stop();
      _whewsNiedService.stop();
      _lastWhewsNiedDataTime = null;
      _clearNiedMonitorState();
      if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
        unawaited(BackgroundService().requestSourceReload());
      }
      return;
    }

    if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
      NiedMonitorService().stop();
      _lmoniService.stop();
      _yahooService.stop();
      _whewsNiedService.stop();
      _lastWhewsNiedDataTime = null;
      unawaited(BackgroundService().requestSourceReload());
      return;
    }

    if (_usesWhewsNied) {
      NiedMonitorService().setPhysicalLayersEnabled(false);
      _lmoniService.stop();
      _yahooService.stop();
      NiedMonitorService().stop();
      _lastWhewsNiedDataTime = null;
      _whewsNiedService.start();
      return;
    }

    _whewsNiedService.stop();
    _whewsNiedStations = [];
    _lastWhewsNiedDataTime = null;
    if (_useYahooSource) {
      NiedMonitorService().setPhysicalLayersEnabled(false);
      _lmoniService.stop();
      NiedMonitorService().stop();
      _yahooService.start();
    } else {
      _yahooService.stop();
      _lmoniService.start();
      NiedMonitorService().start();
    }
  }

  void _clearNiedMonitorState() {
    _niedStations = const [];
    _whewsNiedStations = [];
    _lastWhewsNiedDataTime = null;
    _niedGridCellCenters.clear();
    _lastNiedLayerSignature = '';
    _resetNiedDetectionState(detachStations: true);
    NiedBackgroundWorker.instance.stop();
    _notifyLayer(_niedLayerRevision);
    _quakeProvider?.updateSourceStatus('NIED', SourceStatus.disconnected);
    _emitStationSummary();
  }

  void _syncLpgmMonitorService() {
    if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
      _lpgmService.stop();
      _lpgmSnapshotSubscription?.cancel();
      _lpgmSnapshotSubscription = null;
      _latestLpgmSnapshot = null;
      _emitStationSummary();
      if (_niedLpgmEnabled) {
        unawaited(BackgroundService().requestSourceReload());
      }
      return;
    }
    if (_niedLpgmEnabled) {
      unawaited(_initLpgmMonitor());
      return;
    }
    _lpgmSnapshotSubscription?.cancel();
    _lpgmSnapshotSubscription = null;
    _lpgmService.stop();
    _latestLpgmSnapshot = null;
    _emitStationSummary();
  }

  void _syncSnetService() {
    if (!_snetEnabled) {
      _obsAutomationInputs.clearStationNetwork('snet');
      _snetService.stopMonitoring();
      _whewsSnetService.stop();
      _whewsSnetStations = [];
      _snetService.clearStations();
      _lastSnetLayerSignature = '';
      _notifyLayer(_snetLayerRevision);
      _quakeProvider?.updateSourceStatus('S-net', SourceStatus.disconnected);
      _emitStationSummary();
      if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
        unawaited(BackgroundService().requestSourceReload());
      }
      return;
    }

    if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
      _snetService.stopMonitoring();
      _whewsSnetService.stop();
      _whewsSnetStations = [];
      unawaited(BackgroundService().requestSourceReload());
      return;
    }

    if (_usesWhewsSnet) {
      _snetService.stopMonitoring();
      _whewsSnetService.start();
      return;
    }

    _whewsSnetService.stop();
    _whewsSnetStations = [];
    unawaited(_initSnet());
  }

  void _syncTremStationService() {
    if (!mounted) return;
    final provider = context.read<QuakeProvider>();
    if (!_tremStationEnabled) {
      _cwaService.stop();
      _obsAutomationInputs.clearStationNetwork('trem');
      _cwaStations = const [];
      _lastCwaLayerSignature = '';
      _lastTremStationFocusSignature = null;
      _lastTremStationFocusAt = null;
      _pendingTremStationFocus = false;
      _notifyLayer(_cwaLayerRevision);
      _emitStationSummary();
      provider.updateSourceStatus('TREM', SourceStatus.disconnected);
      if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
        unawaited(BackgroundService().requestSourceReload());
      }
      return;
    }
    if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
      _cwaService.stop();
      unawaited(BackgroundService().requestSourceReload());
      return;
    }
    if (!_cwaService.isRunning) {
      _cwaService.start();
    }
  }

  void _refreshNiedLayerIfNeeded(List<NiedStation>? stations) {
    if (!mounted) return;
    final signature = _niedLayerSignature(stations ?? _niedStations);
    if (signature == _lastNiedLayerSignature) return;
    _lastNiedLayerSignature = signature;
    _notifyLayer(_niedLayerRevision);
  }

  void _acceptNiedStations(List<NiedStation>? stations) {
    if (stations != null) {
      if (stations.isEmpty) {
        _niedStations = const [];
        _resetNiedDetectionState(detachStations: true);
      } else {
        _niedStations = stations;
        _shakeDetection.setStations(stations, background: true);
        _shakeDetection.processUpdate(background: true);
        _ingestNiedAutomationStations(stations);
        unawaited(_processNiedSourceEstimation(stations));
        _requestNiedStationFocus();
      }
    }
    _refreshNiedLayerIfNeeded(stations);
    _emitStationSummary();
  }

  void _ingestNiedAutomationStations(List<NiedStation> stations) {
    if (!_obsAutomationInputs.hasListeners) return;
    _obsAutomationInputs.ingestStationSnapshot(
      'nied',
      stations.where((station) => station.isActive).map((station) {
        final level = JpShindoScale.jmaIndexFromKanameishiLevel(
          station.kaLevel,
        );
        return ObsStationInputSample(
          stationId: station.code,
          stationName: station.name,
          active: true,
          intensityLevel: level,
          intensity: JpShindoScale.rawShindoFromKanameishiLevel(
            station.kaLevel,
          ),
          latitude: station.coordinate.latitude,
          longitude: station.coordinate.longitude,
          observedAt:
              station.lastDataTime ?? station.lastUpdate ?? DateTime.now(),
          rising: station.detectState == 1,
          strong: station.detectState >= 6,
        );
      }),
    );
  }

  void _ingestKmaAutomationStations(List<KmaStation> stations) {
    if (!_obsAutomationInputs.hasListeners) return;
    _obsAutomationInputs.ingestStationSnapshot(
      'kma',
      stations.where((station) => station.isActive).map((station) {
        final intensityLevel = KmaMonitorService.shindoFromLevel(
          station.holdLevel,
        );
        return ObsStationInputSample(
          stationId: station.id.toString(),
          stationName: station.id.toString(),
          active: true,
          intensityLevel: intensityLevel,
          intensity: station.heldIntensity.toDouble(),
          latitude: station.coordinate.latitude,
          longitude: station.coordinate.longitude,
          observedAt: station.lastUpdate ?? DateTime.now(),
          strong: intensityLevel >= 4,
        );
      }),
    );
  }

  void _ingestTremAutomationStations(List<CwaStation> stations) {
    if (!_obsAutomationInputs.hasListeners) return;
    _obsAutomationInputs.ingestStationSnapshot(
      'trem',
      stations.where((station) => station.hasAlert).map((station) {
        final rawLevel = CwaStationService.gridLevelFromInstShindo(
          station.currentIntensity,
        );
        final intensityLevel = JpShindoScale.jmaIndexFromKanameishiLevel(
          rawLevel,
        );
        return ObsStationInputSample(
          stationId: station.id,
          stationName: station.code.toString(),
          active: true,
          intensityLevel: intensityLevel,
          intensity: station.currentIntensity,
          latitude: station.coordinate.latitude,
          longitude: station.coordinate.longitude,
          observedAt: station.lastUpdate ?? DateTime.now(),
          strong: intensityLevel >= 4,
        );
      }),
    );
  }

  void _ingestSnetAutomationStations(List<SnetStation> stations) {
    if (!_obsAutomationInputs.hasListeners) return;
    _obsAutomationInputs.ingestStationSnapshot(
      'snet',
      stations.where((station) => station.isActive).map((station) {
        final intensityLevel = JpShindoScale.jmaIndexFromKanameishiLevel(
          station.level,
        );
        return ObsStationInputSample(
          stationId: station.code,
          stationName: station.name,
          active: true,
          intensityLevel: intensityLevel,
          intensity: station.shindo,
          latitude: station.coordinate.latitude,
          longitude: station.coordinate.longitude,
          observedAt: station.lastUpdate ?? DateTime.now(),
          strong: intensityLevel >= 4,
        );
      }),
    );
  }

  void _ingestPAlertAutomationStations(List<PAlertStation> stations) {
    if (!_obsAutomationInputs.hasListeners) return;
    _obsAutomationInputs.ingestStationSnapshot(
      'palert',
      stations.where((station) => station.hasRealtime).map((station) {
        final intensityLevel = station.displayCwaIntensityIndex ?? -1;
        return ObsStationInputSample(
          stationId: station.id,
          stationName: station.name,
          active: true,
          intensityLevel: intensityLevel,
          intensity: intensityLevel >= 0 ? intensityLevel.toDouble() : null,
          latitude: station.coordinate.latitude,
          longitude: station.coordinate.longitude,
          observedAt: station.dataTime ?? DateTime.now(),
          strong: intensityLevel >= 4,
        );
      }),
    );
  }

  void _ingestSeisJsAutomationStations(List<SeisJsStation> stations) {
    if (!_obsAutomationInputs.hasListeners) return;
    _obsAutomationInputs.ingestStationSnapshot(
      'seisjs',
      stations.map((station) {
        final intensityLevel = station.shindo;
        return ObsStationInputSample(
          stationId: station.id,
          stationName: station.region,
          active: true,
          intensityLevel: intensityLevel,
          intensity: station.intensity,
          latitude: station.coordinate.latitude,
          longitude: station.coordinate.longitude,
          observedAt: station.lastUpdate ?? DateTime.now(),
          strong: intensityLevel >= 4,
        );
      }),
    );
  }

  void _notifyLayer(ValueNotifier<int> notifier) {
    notifier.value = notifier.value + 1;
  }

  void _onNiedSourceEventChanged() {
    _refreshNiedSourceEventFromTracker();
  }

  void _refreshNiedSourceEventFromTracker() {
    if (!mounted) return;
    if (!_showNiedEstimatedEpicenter) {
      _clearNiedSourceEstimationState();
      return;
    }
    final previousEventId = _latestNiedSourceEvent?.eventId;
    final previousEstimateSignature = _lastNiedSourceEstimateSignature;
    _latestNiedSourceEvent =
        StationEventTracker.instance.currentNiedEvent.value;
    final changed = _syncNiedSourceEstimateState(
      previousEventId: previousEventId,
      previousEstimateSignature: previousEstimateSignature,
    );
    _syncActivityTimers();
    if (changed) {
      _queueCameraPolicyRefresh(
        force: previousEventId != _latestNiedSourceEvent?.eventId,
      );
      setState(() {});
    }
  }

  void _clearNiedSourceEstimationState() {
    _niedSourceEstimationDriver.reset();
    if (StationEventTracker.instance.currentNiedEvent.value != null ||
        StationEventTracker.instance.niedEventHistory.value.isNotEmpty) {
      StationEventTracker.instance.resetNied();
    }
    _clearNiedSourceDisplayState();
  }

  void _clearNiedSourceDisplayState() {
    final hadState =
        _latestNiedSourceEvent != null ||
        _niedDetectEpicenter != null ||
        _niedSourceWaveEventId != null ||
        _lastNiedSourceEstimateSignature != 'none';
    _latestNiedSourceEvent = null;
    _niedDetectEpicenter = null;
    _niedSourceWaveEventId = null;
    _lastNiedSourceEstimateSignature = 'none';
    _clearNiedWaveElapsedAnchor();
    _lastEpicenterFocus = null;
    _lastEpicenterSourceEventId = null;
    _stopNiedWaveClock();
    if (hadState && mounted) {
      setState(() {});
      _queueCameraPolicyRefresh(force: true);
    }
  }

  Future<void> _processNiedSourceEstimation(List<NiedStation> stations) async {
    if (!_showNiedEstimatedEpicenter) {
      NiedMonitorService().setPhysicalLayersEnabled(false);
      _clearNiedSourceEstimationState();
      return;
    }
    NiedSourceEstimationResult? result;
    try {
      result = await _niedSourceEstimationDriver.processStations(stations);
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'NIED source estimation',
          context: ErrorDescription(
            'while processing a station frame off the UI isolate',
          ),
        ),
      );
      return;
    }
    if (!mounted || !_showNiedEstimatedEpicenter || result == null) return;
    final detection = result.detection;
    // The realtime shindo frame remains the priority. Physical GIF layers are
    // fetched only while the detector has an actual candidate or source event.
    if ((_niedSource == 'lmoni' || _niedSource == 'kmoni') &&
        _niedMonitorEnabled) {
      NiedMonitorService().setPhysicalLayersEnabled(detection.hasActiveEvent);
    }
    // Publishing notifies the existing map/card listeners once per result.
    result.publish();
  }

  bool _syncNiedSourceEstimateState({
    required String? previousEventId,
    required String previousEstimateSignature,
  }) {
    final event = _latestNiedSourceEvent;
    final estimate = event?.estimate;
    if (estimate == null) {
      final hadEstimateState =
          _niedDetectEpicenter != null || _niedSourceWaveEventId != null;
      _niedDetectEpicenter = null;
      _niedSourceWaveEventId = null;
      _lastNiedSourceEstimateSignature = 'none';
      _clearNiedWaveElapsedAnchor();
      _stopNiedWaveClock();
      return hadEstimateState || previousEstimateSignature != 'none';
    }

    final estimateSignature = _estimateSignature(estimate, event);
    final point = LatLng(estimate.latitude, estimate.longitude);
    if (!QuakeCalculator.isUsableMapCoordinate(
      point.latitude,
      point.longitude,
    )) {
      final hadEstimateState =
          _niedDetectEpicenter != null || _niedSourceWaveEventId != null;
      _niedDetectEpicenter = null;
      _niedSourceWaveEventId = null;
      _lastNiedSourceEstimateSignature = 'none';
      _clearNiedWaveElapsedAnchor();
      _stopNiedWaveClock();
      return hadEstimateState || previousEstimateSignature != 'none';
    }
    final eventId = event?.eventId;
    final firstEstimate = eventId != _niedSourceWaveEventId;
    if (firstEstimate) {
      _niedSourceWaveEventId = eventId;
      _startNiedWaveClock();
    }
    if (firstEstimate || previousEstimateSignature != estimateSignature) {
      _anchorNiedWaveElapsed(estimate);
    }

    final needsDistanceUpdate =
        firstEstimate ||
        _niedDetectEpicenter == null ||
        _haversine(point, _niedDetectEpicenter!) > 10.0;
    if (needsDistanceUpdate) {
      _niedDetectEpicenter = point;
    }
    _lastNiedSourceEstimateSignature = estimateSignature;

    return firstEstimate ||
        needsDistanceUpdate ||
        previousEventId != eventId ||
        previousEstimateSignature != estimateSignature;
  }

  String _estimateSignature(
    SourceEstimate? estimate,
    SeismicActiveEvent? event,
  ) {
    if (estimate == null) return 'none';
    if (estimate.method == 'nied_gif_kotoho7_js_receiver_v1') {
      final error = _metadataDouble(estimate.diagnostics['best_source_error']);
      final frame = estimate.diagnostics['best_source_frame'];
      final pRadius = _metadataDouble(
        estimate.diagnostics['best_source_p_radius_km'],
      );
      final sRadius = _metadataDouble(
        estimate.diagnostics['best_source_s_radius_km'],
      );
      return '${estimate.latitude.toStringAsFixed(4)},'
          '${estimate.longitude.toStringAsFixed(4)},'
          '${(estimate.depthKm ?? -1).toStringAsFixed(1)},'
          '${error?.toStringAsFixed(3) ?? 'null'},'
          '${pRadius?.toStringAsFixed(1) ?? 'null'},'
          '${sRadius?.toStringAsFixed(1) ?? 'null'},'
          '$frame,'
          '${event?.updatedAt.millisecondsSinceEpoch ?? 0}';
    }
    final sourceSignature = event == null
        ? ''
        : _niedPublishedSourceEstimates(event)
              .map(
                (source) =>
                    '${source.diagnostics['selected_detection_id']}:'
                    '${source.latitude.toStringAsFixed(3)}:'
                    '${source.longitude.toStringAsFixed(3)}:'
                    '${(source.depthKm ?? -1).toStringAsFixed(0)}',
              )
              .join('|');
    return '${estimate.latitude.toStringAsFixed(4)},'
        '${estimate.longitude.toStringAsFixed(4)},'
        '${(estimate.depthKm ?? -1).toStringAsFixed(1)},'
        '${estimate.confidence.toStringAsFixed(2)},'
        '${estimate.method},'
        '$sourceSignature,'
        '${event?.updatedAt.millisecondsSinceEpoch ?? 0}';
  }

  List<SourceEstimate> _niedPublishedSourceEstimates(SeismicActiveEvent event) {
    final primary = event.estimate;
    final rawSources = event.metadata['nied_dart_hyp_sources'];
    if (rawSources is! Iterable) {
      return primary == null ? const [] : [primary];
    }
    final sources = <SourceEstimate>[];
    var includedPrimary = false;
    for (final rawSource in rawSources) {
      if (rawSource is! Map) continue;
      final selected = rawSource['selected'] == true;
      if (selected && primary != null) {
        sources.add(primary);
        includedPrimary = true;
        continue;
      }
      final latitude = _metadataDouble(rawSource['latitude']);
      final longitude = _metadataDouble(rawSource['longitude']);
      final confidence = _metadataDouble(rawSource['confidence']);
      if (latitude == null || longitude == null || confidence == null) {
        continue;
      }
      final rawDiagnostics = rawSource['diagnostics'];
      final diagnostics = <String, Object?>{
        if (rawDiagnostics is Map)
          for (final entry in rawDiagnostics.entries)
            entry.key.toString(): entry.value,
        'nied_dart_hyp_selected': selected,
      };
      sources.add(
        SourceEstimate(
          latitude: latitude,
          longitude: longitude,
          depthKm: _metadataDouble(rawSource['depth_km']),
          magnitude: _metadataDouble(rawSource['magnitude']),
          originTime: DateTime.tryParse(
            rawSource['origin_time']?.toString() ?? '',
          ),
          confidence: confidence,
          method: rawSource['method']?.toString() ?? 'nied_dart_hyp_v1',
          supportingStationCount:
              (rawSource['supporting_station_count'] as num?)?.toInt() ?? 0,
          diagnostics: diagnostics,
        ),
      );
    }
    if (!includedPrimary && primary != null) sources.insert(0, primary);
    return List<SourceEstimate>.unmodifiable(sources);
  }

  String _niedLayerSignature(List<NiedStation> stations) {
    final buffer = StringBuffer();
    buffer.write(stations.length);
    buffer.write('|');
    buffer.write(_niedDetectionLayerSignature());
    for (final station in stations) {
      buffer
        ..write('|')
        ..write(station.id)
        ..write(':')
        ..write(station.level)
        ..write(':')
        ..write(station.detectState);
    }
    return buffer.toString();
  }

  String _niedDetectionLayerSignature() {
    final snapshot = _latestDetectSnapshot;
    final cells = snapshot.gridCells.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final buffer = StringBuffer()
      ..write(snapshot.stage.name)
      ..write(':')
      ..write(snapshot.weakCount)
      ..write(':')
      ..write(snapshot.detectedCount)
      ..write(':')
      ..write(snapshot.strongCount)
      ..write(':')
      ..write(snapshot.maxShindo);
    for (final cell in cells) {
      buffer
        ..write(':')
        ..write(cell.key)
        ..write('=')
        ..write(cell.value.level);
    }
    return buffer.toString();
  }

  String _kmaLayerSignature(List<KmaStation> stations) {
    final buffer = StringBuffer()..write(stations.length);
    for (final station in stations) {
      buffer
        ..write('|')
        ..write(station.id)
        ..write(':')
        ..write(station.intensity)
        ..write(':')
        ..write(station.activityLevel)
        ..write(':')
        ..write(station.holdLevel)
        ..write(':')
        ..write(station.ascend)
        ..write(':')
        ..write(station.isActive ? 1 : 0);
    }
    return buffer.toString();
  }

  String _cwaLayerSignature(List<CwaStation> stations) {
    final buffer = StringBuffer()..write(stations.length);
    for (final station in stations) {
      buffer
        ..write('|')
        ..write(station.id)
        ..write(':')
        ..write(station.currentIntensity)
        ..write(':')
        ..write(station.alertIntensity)
        ..write(':')
        ..write(station.intensity)
        ..write(':')
        ..write(station.hasAlert ? 1 : 0)
        ..write(':')
        ..write(station.work ? 1 : 0);
    }
    return buffer.toString();
  }

  String _pAlertLayerSignature(List<PAlertStation> stations) {
    final buffer = StringBuffer()..write(stations.length);
    for (final station in stations) {
      buffer
        ..write('|')
        ..write(station.id)
        ..write(':')
        ..write(station.gridLevel)
        ..write(':')
        ..write(station.pgaGal?.toStringAsFixed(3) ?? '-')
        ..write(':')
        ..write(station.pgvCms?.toStringAsFixed(3) ?? '-')
        ..write(':')
        ..write(station.dataTime?.millisecondsSinceEpoch ?? 0);
    }
    return buffer.toString();
  }

  String _seisJsLayerSignature(List<SeisJsStation> stations) {
    final buffer = StringBuffer()..write(stations.length);
    for (final station in stations) {
      buffer
        ..write('|')
        ..write(station.id)
        ..write(':')
        ..write(station.intensity.toStringAsFixed(3));
    }
    return buffer.toString();
  }

  String _snetLayerSignature(List<SnetStation> stations) {
    final buffer = StringBuffer()..write(stations.length);
    for (final station in stations) {
      buffer
        ..write('|')
        ..write(station.code)
        ..write(':')
        ..write(station.level)
        ..write(':')
        ..write(station.shindo.toStringAsFixed(3))
        ..write(':')
        ..write(station.isActive ? 1 : 0);
    }
    return buffer.toString();
  }

  int _unifiedMapUiSignature(QuakeProvider provider) {
    final unifiedEvents = provider.unifiedEvents;
    final mapEvents = provider.unifiedMapEvents;
    return Object.hash(
      provider.unifiedMapRevision,
      identityHashCode(provider.cencIrData),
      Object.hashAll(unifiedEvents.map((event) => event.hashCode)),
      Object.hashAll(mapEvents.map(_quakeMessageVisualSignature)),
    );
  }

  int _quakeMessageVisualSignature(QuakeMessage event) {
    return Object.hash(
      event.source,
      event.eventId,
      event.reportNumber,
      event.magnitude,
      event.depth,
      event.latitude,
      event.longitude,
      event.originTime,
      event.maxIntensity,
      event.isWarn,
      event.isCanceled,
    );
  }

  bool _hasEewSource(QuakeProvider provider, String source) {
    return _hideGridOnEew &&
        provider.unifiedEvents.any(
          (event) => event.source == source && event.isEew,
        );
  }

  Widget _buildWeatherStationLayer() {
    return Selector<MapStateProvider, (bool, String)>(
      selector: (context, mapState) => (
        mapState.isOverlayEnabled('weatherStationLayer'),
        mapState.weatherStationMode,
      ),
      builder: (context, tuple, child) {
        final (enabled, modeKey) = tuple;
        if (!enabled) return const SizedBox.shrink();
        if (CmaLocalWeatherService.stationDirectoryNotifier.value.isEmpty) {
          unawaited(CmaLocalWeatherService.ensureStationDirectoryLoaded());
        }
        return ValueListenableBuilder<List<CmaStationSummary>>(
          valueListenable: CmaLocalWeatherService.stationDirectoryNotifier,
          builder: (context, stations, child) {
            if (stations.isEmpty) return const SizedBox.shrink();
            return WeatherStationMapLayer(
              stations: stations,
              mode: WeatherStationDisplayMode.fromKey(modeKey),
            );
          },
        );
      },
    );
  }

  Widget _buildWeatherAlertMapLayer() {
    return Selector<MapStateProvider, bool>(
      selector: (context, mapState) =>
          mapState.isOverlayEnabled('weatherAlertLayer'),
      builder: (context, enabled, child) {
        if (!enabled) {
          // 图层关闭时清除选中状态
          ChinaWeatherAlertMapService().stop();
          if (_selectedWeatherAlert != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _selectedWeatherAlert = null);
            });
          }
          return const SizedBox.shrink();
        }
        if (!ChinaWeatherAlertMapService().isRunning) {
          ChinaWeatherAlertMapService().start();
        }
        return ValueListenableBuilder<List<WeatherAlertMapItem>>(
          valueListenable: ChinaWeatherAlertMapService.alertItemsNotifier,
          builder: (context, alerts, child) {
            if (alerts.isEmpty) return const SizedBox.shrink();
            return WeatherAlertMapLayer(
              alerts: alerts,
              selectedAlert: _selectedWeatherAlert,
              onDismiss: () {
                _popupClosedAt = DateTime.now();
                setState(() => _selectedWeatherAlert = null);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildNiedStationLayer() {
    return ValueListenableBuilder<int>(
      valueListenable: _niedLayerRevision,
      builder: (context, revision, child) {
        return Selector<QuakeProvider, bool>(
          selector: (context, provider) => _hasEewSource(provider, 'jmaEew'),
          builder: (context, hideGrid, child) {
            return ValueListenableBuilder<bool>(
              valueListenable: _blinkNotifier,
              builder: (context, blinkOn, child) {
                if (!_niedLayerVisible) return const SizedBox.shrink();
                return NiedIntensityLayer(
                  stations: _niedStations,
                  hideGrid: hideGrid,
                  blinkOn: blinkOn,
                  displayShindo0: _displayShindo0,
                  detectionGridCells: _latestDetectSnapshot.gridCells,
                  onGridCellsChanged: (centers) {
                    _niedGridCellCenters
                      ..clear()
                      ..addAll(centers);
                    _queueCameraPolicyRefresh();
                    if (_pendingNiedStationFocus) {
                      _pendingNiedStationFocus = false;
                      _requestNiedStationFocus(force: true);
                    } else {
                      _requestNiedStationFocus();
                    }
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildKmaStationLayer() {
    return ValueListenableBuilder<int>(
      valueListenable: _kmaLayerRevision,
      builder: (context, revision, child) {
        return Selector<QuakeProvider, bool>(
          selector: (context, provider) => _hasEewSource(provider, 'kmaEew'),
          builder: (context, hideGrid, child) {
            return ValueListenableBuilder<bool>(
              valueListenable: _blinkNotifier,
              builder: (context, blinkOn, child) {
                if (!_kmaVisible || _kmaStations.isEmpty) {
                  return const SizedBox.shrink();
                }
                return KmaIntensityLayer(
                  stations: _kmaStations,
                  hideGrid: hideGrid,
                  blinkOn: blinkOn,
                  displayShindo0: _displayShindo0,
                  onGridCellsChanged: (centers) {
                    _kmaGridCellCenters
                      ..clear()
                      ..addAll(centers);
                    _queueCameraPolicyRefresh();
                    if (_pendingKmaStationFocus) {
                      _pendingKmaStationFocus = false;
                      _requestKmaStationFocus(force: true);
                    } else {
                      _requestKmaStationFocus();
                    }
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildCwaStationLayer() {
    return ValueListenableBuilder<int>(
      valueListenable: _cwaLayerRevision,
      builder: (context, revision, child) {
        return Selector<QuakeProvider, bool>(
          selector: (context, provider) => _hasEewSource(provider, 'cwaEew'),
          builder: (context, hideGrid, child) {
            return ValueListenableBuilder<bool>(
              valueListenable: _blinkNotifier,
              builder: (context, blinkOn, child) {
                if (!_cwaVisible || _cwaStations.isEmpty) {
                  return const SizedBox.shrink();
                }
                return CwaStationLayer(
                  stations: _cwaStations,
                  hideGrid: hideGrid,
                  blinkOn: blinkOn,
                  displayShindo0: _displayShindo0,
                  onGridCellsChanged: (_) {
                    _queueCameraPolicyRefresh();
                    if (_pendingTremStationFocus) {
                      _pendingTremStationFocus = false;
                      _requestTremStationFocus(force: true);
                    } else {
                      _requestTremStationFocus();
                    }
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildPAlertStationLayer() {
    return ValueListenableBuilder<int>(
      valueListenable: _pAlertLayerRevision,
      builder: (context, revision, child) {
        if (!_pAlertEnabled || _pAlertStations.isEmpty) {
          return const SizedBox.shrink();
        }
        return Selector<QuakeProvider, bool>(
          selector: (context, provider) => _hasEewSource(provider, 'cwaEew'),
          builder: (context, hideGrid, child) => ValueListenableBuilder<bool>(
            valueListenable: _blinkNotifier,
            builder: (context, blinkOn, child) => PAlertStationLayer(
              stations: _pAlertStations,
              displayShindo0: _displayShindo0,
              detectionGridCells: _pAlertDetectionGrid.cells,
              hideGrid: hideGrid,
              blinkOn: blinkOn,
            ),
          ),
        );
      },
    );
  }

  Widget _buildUnifiedIntensityLayerStack() {
    return Selector<QuakeProvider, int>(
      selector: (context, provider) => _unifiedMapUiSignature(provider),
      builder: (context, signature, child) {
        final provider = context.read<QuakeProvider>();
        final layers = _buildUnifiedIntensityLayers(provider);
        if (layers.isEmpty) return const SizedBox.shrink();
        return Stack(children: layers);
      },
    );
  }

  List<Widget> _buildUnifiedIntensityLayers(QuakeProvider provider) {
    final unifiedEvents = provider.unifiedEvents;
    if (unifiedEvents.isEmpty) return const [];

    final mapEvents = provider.unifiedMapEvents;
    final lpgm = provider.unifiedEvents
        .where(
          (event) =>
              event.isJmaLpgm && event.jmaLpgmBulletin?.isActive() == true,
        )
        .map((event) => event.jmaLpgmBulletin!)
        .firstOrNull;
    final hasActiveLpgm = lpgm != null;
    final hasEew = unifiedEvents.any((e) => e.isEew);
    final activeInfoFocusSignature = _activePreferredInfoFocusSignature();
    final layers = <Widget>[];
    if (lpgm != null) {
      layers.add(
        JmaLpgmRegionFillLayer(
          key: ValueKey('jma_lpgm_regions_${lpgm.signature}'),
          bulletin: lpgm,
        ),
      );
    }
    final combinedJmaIntensity = _combinedJmaIntensityLayerData(
      unifiedEvents,
      mapEvents,
      hasEew,
      activeInfoFocusSignature,
    );
    if (!hasActiveLpgm && combinedJmaIntensity != null) {
      final event = combinedJmaIntensity.event;
      layers.add(
        IntensityFillLayer(
          key: ValueKey('intensity_jma_combined_${combinedJmaIntensity.key}'),
          magnitude: event.magnitude,
          depth: event.depth,
          hypoLat: event.latitude,
          hypoLng: event.longitude,
          source: 'jp',
          mode: IntensityFillMode.jma,
          minIntensity: 1.0,
          opacity: 0.55,
          enabled: true,
          warnAreaJson: combinedJmaIntensity.warnAreaJson,
        ),
      );
    }

    final layerCount = math.min(unifiedEvents.length, mapEvents.length);
    for (int i = 0; i < layerCount; i++) {
      final u = unifiedEvents[i];
      if (u.isVolcanoEvent) continue;
      final qm = mapEvents[i];
      final layerKey = unifiedMapLayerKey(
        source: qm.source,
        eventId: u.eventId,
        isEew: u.isEew,
        index: i,
      );

      final source = qm.source;
      String regionSource;
      bool useJma;

      switch (source) {
        case QuakeSourceType.wolfx:
        case QuakeSourceType.jma_fan:
        case QuakeSourceType.p2p:
          regionSource = 'jp';
          useJma = true;
          break;
        case QuakeSourceType.kma_eew_fan:
        case QuakeSourceType.kma_eq:
          regionSource = 'kr';
          useJma = true;
          break;
        case QuakeSourceType.cwa_eew:
        case QuakeSourceType.cwa:
          regionSource = 'tw';
          useJma = false;
          break;
        case QuakeSourceType.cea:
        case QuakeSourceType.cea_pr:
        case QuakeSourceType.sc_eew:
        case QuakeSourceType.fj_eew:
        case QuakeSourceType.cq_eew:
        case QuakeSourceType.cenc:
          regionSource = 'cn';
          useJma = false;
          break;
        default:
          regionSource = '';
          useJma = false;
      }

      final drawIntensity =
          !_isJmaIntensityMapEvent(qm) &&
          _shouldDrawIntensityForEvent(u, hasEew, activeInfoFocusSignature);

      if (!hasActiveLpgm &&
          drawIntensity &&
          provider.shouldDrawUnifiedIntensityFill(u) &&
          regionSource.isNotEmpty &&
          qm.magnitude > 0) {
        layers.add(
          IntensityFillLayer(
            key: ValueKey('intensity_$layerKey'),
            magnitude: qm.magnitude,
            depth: qm.depth,
            hypoLat: qm.latitude,
            hypoLng: qm.longitude,
            source: regionSource,
            mode: useJma ? IntensityFillMode.jma : IntensityFillMode.csis,
            minIntensity: 1.0,
            opacity: 0.55,
            enabled: true,
            warnAreaJson: u.warnArea,
          ),
        );
      }
    }

    return layers;
  }

  Widget _buildSeisJsStationLayer() {
    return ValueListenableBuilder<int>(
      valueListenable: _seisJsLayerRevision,
      builder: (context, revision, child) {
        if (!_seisjsVisible || _seisjsStations.isEmpty) {
          return const SizedBox.shrink();
        }
        return SeisJsLayer(stations: _seisjsStations);
      },
    );
  }

  Widget _buildSnetStationLayer() {
    return ValueListenableBuilder<int>(
      valueListenable: _snetLayerRevision,
      builder: (context, revision, child) {
        if (!_snetVisible) return const SizedBox.shrink();
        final stations = _usesWhewsSnet
            ? _whewsSnetStations
            : _snetService.stations;
        return SnetLayer(stations: stations);
      },
    );
  }

  Widget _buildFdsnStationLayer({
    required String overlayKey,
    required ValueNotifier<int> revision,
    required List<FdsnStation> Function() stations,
  }) {
    return Selector<MapStateProvider, bool>(
      selector: (context, mapState) => mapState.isOverlayEnabled(overlayKey),
      builder: (context, enabled, child) {
        if (!enabled) return const SizedBox.shrink();
        return ValueListenableBuilder<int>(
          valueListenable: revision,
          builder: (context, revision, child) {
            final currentStations = stations();
            if (currentStations.isEmpty) return const SizedBox.shrink();
            return FdsnStationLayer(stations: currentStations);
          },
        );
      },
    );
  }

  void _tickBlinkState() {
    if (!mounted) return;
    if (!_needsBlinkRepaint) {
      _syncBlinkTimer();
      return;
    }
    _blinkNotifier.value = !_blinkNotifier.value;
  }

  void _syncActivityTimers() {
    if (!mounted) return;
    _syncBlinkTimer();
    _syncWaveAutoZoomTimer();
  }

  void _syncBlinkTimer() {
    final shouldRun = _needsBlinkRepaint;
    if (shouldRun) {
      if (_blinkClockLease == null) {
        EventAnimationClock.instance.blink2Fps.addListener(_tickBlinkState);
        _blinkClockLease = EventAnimationClock.instance.acquire();
      }
      return;
    }
    if (_blinkClockLease != null) {
      EventAnimationClock.instance.blink2Fps.removeListener(_tickBlinkState);
      _blinkClockLease?.dispose();
      _blinkClockLease = null;
    }
    if (!_blinkOn) {
      _blinkNotifier.value = true;
    }
  }

  void _syncWaveAutoZoomTimer() {
    final shouldRun =
        (_mapStateProvider?.isSeismicViewportVisible ?? true) &&
        _hasActiveCameraPolicyWork &&
        (_mapStateProvider?.canAutoFollow ?? false);
    if (shouldRun) {
      if (_waveAutoZoomClockLease == null) {
        EventAnimationClock.instance.second1Fps.addListener(_syncWaveAutoZoom);
        _waveAutoZoomClockLease = EventAnimationClock.instance.acquire();
      }
      return;
    }
    if (_waveAutoZoomClockLease != null) {
      EventAnimationClock.instance.second1Fps.removeListener(_syncWaveAutoZoom);
      _waveAutoZoomClockLease?.dispose();
      _waveAutoZoomClockLease = null;
    }
  }

  void _startNiedWaveClock() {
    if (_niedWaveClockLease != null) return;
    EventAnimationClock.instance.blink2Fps.addListener(_tickNiedWave);
    _niedWaveClockLease = EventAnimationClock.instance.acquire();
  }

  void _stopNiedWaveClock() {
    if (_niedWaveClockLease == null) return;
    EventAnimationClock.instance.blink2Fps.removeListener(_tickNiedWave);
    _niedWaveClockLease?.dispose();
    _niedWaveClockLease = null;
  }

  void _tickNiedWave() {
    if (mounted) _waveTick.value++;
  }

  void _anchorNiedWaveElapsed(SourceEstimate estimate) {
    final elapsedSeconds = _metadataDouble(
      estimate.diagnostics['wave_elapsed_s'],
    );
    if (elapsedSeconds == null) {
      _clearNiedWaveElapsedAnchor();
      return;
    }
    _niedWaveElapsedAnchorSeconds = elapsedSeconds;
    _niedWaveElapsedClock
      ..reset()
      ..start();
  }

  void _clearNiedWaveElapsedAnchor() {
    _niedWaveElapsedAnchorSeconds = null;
    _niedWaveElapsedClock
      ..stop()
      ..reset();
  }

  double? get _displayNiedWaveElapsedSeconds {
    if (QuakeMapView.niedReplayNotifier.value.enabled) return null;
    final anchor = _niedWaveElapsedAnchorSeconds;
    if (anchor == null) return null;
    return anchor + _niedWaveElapsedClock.elapsedMilliseconds / 1000.0;
  }

  void _onQuakeProviderChanged() {
    _syncActivityTimers();
    _syncVolcanoMapServiceWithOverlay();
    if (PAlertSourceState.events.value.isNotEmpty) {
      _queueCameraPolicyRefresh();
    }
    final provider = _quakeProvider;
    if (provider != null &&
        (provider.mobileEewCarousel || !UiScale.isPhone(context)) &&
        _lastCameraCarouselIndex != provider.currentUnifiedIndex) {
      _lastCameraCarouselIndex = provider.currentUnifiedIndex;
      _queueCameraPolicyRefresh();
    }
  }

  void _onTyphoonListenableChanged() {
    final typhoonRevision = _quakeProvider?.typhoonUpdateRevision ?? 0;
    if (typhoonRevision != _lastTyphoonUpdateRevision) {
      _lastTyphoonUpdateRevision = typhoonRevision;
      _refreshFanSatelliteCloudOnTyphoonUpdate();
    }
  }

  bool get _needsBlinkRepaint {
    final provider = _quakeProvider;
    if (provider?.unifiedEvents.any((e) => e.isEew) == true) return true;
    if (provider?.jmaTsunami?.isActive == true) return true;
    if (provider?.nmefcTsunami?.isActive == true) return true;
    if (provider?.ptwcTsunami?.isActive == true) return true;
    if (provider?.ntwcTsunami?.isActive == true) return true;
    if (provider?.incoisTsunami?.isActive == true) return true;
    if (_latestDetectSnapshot.stage != ShakeDetectStage.idle) return true;
    if (_pAlertDetectionGrid.cells.isNotEmpty) return true;
    if (_kmaStations.any((s) => s.isActive || s.intensity >= 0)) return true;
    if (_cwaStations.any((s) => s.hasAlert || s.currentIntensity >= 0)) {
      return true;
    }
    return false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _quakeProvider = context.read<QuakeProvider>();
    final mapState = context.read<MapStateProvider>();
    if (_mapStateProvider != mapState) {
      _mapStateProvider?.removeListener(_onMapStateChanged);
      _mapStateProvider = mapState;
      mapState.addListener(_onMapStateChanged);
    }
    if (!_providerCallbacksBound) {
      _quakeProvider?.addListener(_onQuakeProviderChanged);
      _quakeProvider?.typhoonListenable.addListener(
        _onTyphoonListenableChanged,
      );
      _lastTyphoonUpdateRevision = _quakeProvider?.typhoonUpdateRevision ?? 0;
      _wireStatusCallbacks();
      _bindAllEventsExpiredCallback();
      _providerCallbacksBound = true;
    }
    _syncActivityTimers();
    _syncVolcanoMapServiceWithOverlay();
    _syncFdsnServicesWithOverlay();
    _syncLiveWeatherTileRefresh();
    _syncTyphoonLayerServiceWithOverlay();
    _syncFanRadarServiceWithOverlay();
    _syncPrecipitationServiceWithOverlay();
    _syncJmaRadarServiceWithOverlay();
    _syncFanSatelliteCloudServiceWithOverlay();
  }

  void _handleFdsnMotionSample(FdsnMotionSample sample) {
    if (!mounted) return;
    if (!sample.hasMeasurement && !sample.active) return;
    _fdsnMotionService.recordDataTime(sample.timestamp);
    final key = '${sample.source}:${sample.code}';
    final previous = _latestFdsnMotionSamples[key];
    if (previous != null && sample.timestamp.isBefore(previous.timestamp)) return;
    if (!sample.hasMeasurement && previous?.hasMeasurement == true) return;
    _pendingFdsnMotionSamples[key] = sample;
    _latestFdsnMotionSamples[key] = sample;
    _latestFdsnMotionReceivedAt[key] = DateTime.now();
    _fdsnMotionFlushTimer ??= Timer(
      const Duration(seconds: 1),
      _flushFdsnMotionSamples,
    );
  }

  void _flushFdsnMotionSamples() {
    _fdsnMotionFlushTimer = null;
    if (!mounted || _pendingFdsnMotionSamples.isEmpty) return;
    final samples = Map<String, FdsnMotionSample>.from(
      _pendingFdsnMotionSamples,
    );
    final receivedAt = _latestFdsnMotionReceivedAt;
    _pendingFdsnMotionSamples.clear();
    if (_obsAutomationInputs.hasListeners) {
      for (final sample in samples.values) {
        final intensityLevel = sample.intensity?.floor() ?? -1;
        _obsAutomationInputs.ingestStationSample(
          'fdsn',
          ObsStationInputSample(
            stationId: sample.code,
            stationName: sample.code,
            active: sample.active,
            intensityLevel: intensityLevel,
            intensity: sample.intensity,
            observedAt: sample.timestamp,
            strong: intensityLevel >= 5,
          ),
        );
      }
    }

    List<FdsnStation> updateStations(
      List<FdsnStation> stations,
      Map<String, int> index,
    ) {
      List<FdsnStation>? updated;
      for (final entry in samples.entries) {
        final stationIndex = index[entry.key];
        if (stationIndex == null || stationIndex >= stations.length) continue;
        final station = stations[stationIndex];
        final sample = entry.value;
        final now = receivedAt[entry.key]!;
        final sameValues =
            station.pga == sample.pga &&
            station.pgv == sample.pgv &&
            station.intensity == sample.intensity;
        final lastUiUpdate = _lastFdsnUiUpdateAt[entry.key];
        if (sameValues &&
            station.lastMotionUpdate != null &&
            lastUiUpdate != null &&
            now.difference(lastUiUpdate) < const Duration(seconds: 10)) {
          continue;
        }
        updated ??= List<FdsnStation>.of(stations, growable: false);
        _lastFdsnUiUpdateAt[entry.key] = now;
        updated[stationIndex] = station.copyWith(
          pga: sample.pga,
          pgv: sample.pgv,
          intensity: sample.intensity,
          lastMotionUpdate: sample.timestamp,
        );
      }
      return updated ?? stations;
    }

    final nextEarthScopeStations = updateStations(
      _earthScopeStations,
      _earthScopeStationIndex,
    );
    final nextGeofonStations = updateStations(
      _geofonStations,
      _geofonStationIndex,
    );
    if (identical(nextEarthScopeStations, _earthScopeStations) &&
        identical(nextGeofonStations, _geofonStations)) {
      return;
    }

    if (!identical(nextEarthScopeStations, _earthScopeStations)) {
      _earthScopeStations = nextEarthScopeStations;
      _notifyLayer(_earthScopeLayerRevision);
    }
    if (!identical(nextGeofonStations, _geofonStations)) {
      _geofonStations = nextGeofonStations;
      _notifyLayer(_geofonLayerRevision);
    }
  }

  Map<String, int> _buildFdsnStationIndex(List<FdsnStation> stations) {
    final index = <String, int>{};
    for (var i = 0; i < stations.length; i++) {
      index['${stations[i].source}:${stations[i].code}'] = i;
    }
    return index;
  }

  List<FdsnStation> _applyLatestFdsnMotionToStations(
    List<FdsnStation> stations,
  ) {
    if (_latestFdsnMotionSamples.isEmpty) return stations;
    var changed = false;
    final updated = stations
        .map((station) {
          final key = '${station.source}:${station.code}';
          final sample = _latestFdsnMotionSamples[key];
          if (sample == null) return station;
          changed = true;
          return station.copyWith(
            pga: sample.pga,
            pgv: sample.pgv,
            intensity: sample.intensity,
            lastMotionUpdate: sample.timestamp,
          );
        })
        .toList(growable: false);
    return changed ? updated : stations;
  }

  void _onMapStateChanged() {
    final mapState = _mapStateProvider;
    final canAutoFollow = mapState?.canAutoFollow ?? false;
    final selectedHistoryCameraKey = _historyCameraKey(
      mapState?.selectedHistoryEvent,
    );
    _syncFdsnServicesWithOverlay();
    _syncLiveWeatherTileRefresh();
    _syncTyphoonLayerServiceWithOverlay();
    _syncVolcanoMapServiceWithOverlay();
    _syncFanRadarServiceWithOverlay();
    _syncPrecipitationServiceWithOverlay();
    _syncJmaRadarServiceWithOverlay();
    _syncFanSatelliteCloudServiceWithOverlay();
    _syncWaveAutoZoomTimer();
    if (!_showNiedEstimatedEpicenter) {
      _clearNiedSourceDisplayState();
      _clearPAlertSourceEstimation();
    }
    if (!_lastCanAutoFollow && canAutoFollow) {
      _queueCameraPolicyRefresh(force: false);
    }
    _lastCanAutoFollow = canAutoFollow;
    if (mapState != null &&
        !mapState.isGestureAutoFollowPaused &&
        _cameraPolicyForce) {
      _queueCameraPolicyRefresh(force: true);
    }
    if (_lastSelectedHistoryCameraKey != selectedHistoryCameraKey) {
      _lastSelectedHistoryCameraKey = selectedHistoryCameraKey;
      _queueCameraPolicyRefresh(force: false);
    }
    if (!_initialCameraPolicyApplied && mapState?.mapController != null) {
      _initialCameraPolicyApplied = true;
      _queueCameraPolicyRefresh(force: false);
    }
  }

  void _handleMapEvent(MapEvent event) {
    final manual = _isManualCameraEvent(event);
    if (!manual) return;
    context.read<MapStateProvider>().pauseAutoZoomForGesture();
  }

  bool _isManualCameraEvent(MapEvent event) {
    return switch (event.source) {
      MapEventSource.dragStart ||
      MapEventSource.onDrag ||
      MapEventSource.dragEnd ||
      MapEventSource.multiFingerGestureStart ||
      MapEventSource.onMultiFinger ||
      MapEventSource.multiFingerEnd ||
      MapEventSource.scrollWheel ||
      MapEventSource.doubleTap ||
      MapEventSource.doubleTapHold ||
      MapEventSource.keyboard => true,
      _ => false,
    };
  }

  void _onFdsnStationLimitChanged() {
    if (!_fdsnServicesActive) return;
    _fdsnMotionRestartTimer?.cancel();
    _fdsnMotionRestartTimer = Timer(
      const Duration(milliseconds: 350),
      _restartFdsnMotionService,
    );
  }

  void _syncFdsnServicesWithOverlay() {
    if (!_fdsnSeedLinkEnabled) {
      _stopFdsnServices(clearStations: true);
      _lastForegroundFdsnConfig = '';
      return;
    }
    final mapState = _mapStateProvider;
    final enabledSources = <String>{
      if (mapState?.isOverlayEnabled('fdsnEarthScope') == true) 'EarthScope',
      if (mapState?.isOverlayEnabled('fdsnGeofon') == true) 'GEOFON',
    };
    if (enabledSources.isNotEmpty) {
      if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
        _stopFdsnServices(clearStations: false);
        final config = enabledSources.toList()..sort();
        final signature = config.join('|');
        if (_lastForegroundFdsnConfig != signature) {
          _lastForegroundFdsnConfig = signature;
          unawaited(BackgroundService().requestSourceReload());
        }
        return;
      }
      _lastForegroundFdsnConfig = '';
      _startFdsnServices(enabledSources);
    } else {
      _stopFdsnServices(clearStations: true);
      if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
        _lastForegroundFdsnConfig = 'none';
        unawaited(BackgroundService().requestSourceReload());
      }
    }
  }

  void _syncVolcanoMapServiceWithOverlay() {
    if (_backgroundPaused) {
      _volcanoMapService.stop();
      return;
    }
    final mapState = _mapStateProvider;
    final overlayEnabled =
        mapState != null && mapState.isOverlayEnabled('volcanoLayer');
    final hasVolcanoEvent =
        _quakeProvider?.unifiedEvents.any((event) => event.isVolcanoEvent) == true;
    if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
      if (overlayEnabled && !_foregroundHostedOverlayKeys.contains('volcano')) {
        _foregroundHostedOverlayKeys.add('volcano');
        unawaited(BackgroundService().requestSourceReload());
      } else if (!overlayEnabled) {
        _foregroundHostedOverlayKeys.remove('volcano');
      }
      // The host supplies overlay snapshots; hidden-layer event badges still
      // need standing warnings, without restarting all background sources.
      if (hasVolcanoEvent && !overlayEnabled) {
        _volcanoMapService.start();
      } else {
        _volcanoMapService.stop();
      }
      return;
    }
    if (overlayEnabled || hasVolcanoEvent) {
      _volcanoMapService.start();
    } else {
      _volcanoMapService.stop();
    }
  }

  List<JmaVolcanoSite> _volcanoSitesForEvents(List<UnifiedQuakeData> events) {
    final officialByCode = <String, JmaVolcanoSite>{
      for (final site in _volcanoSites) site.code: site,
    };
    final latestByLocation = <String, UnifiedQuakeData>{};
    for (final event in events) {
      final volcano = event.volcanoEvent;
      if (volcano == null) continue;
      final code = volcano.volcanoCode.trim();
      final key = code.isEmpty ? 'event:${event.eventId}' : 'code:$code';
      final existing = latestByLocation[key];
      final eventTime = event.reportTime ?? event.arrivedAt;
      final existingTime = existing?.reportTime ?? existing?.arrivedAt;
      if (existing == null ||
          (eventTime != null &&
              (existingTime == null || eventTime.isAfter(existingTime)))) {
        latestByLocation[key] = event;
      }
    }

    final sites = <JmaVolcanoSite>[];
    for (final event in latestByLocation.values) {
      final volcano = event.volcanoEvent!;
      final official = officialByCode[volcano.volcanoCode.trim()];
      if (official != null) {
        var site = official;
        if (volcano.isProvisionalCommentary) {
          site = site.copyWith(hasProvisionalInfo: true);
        }
        site = site.copyWith(
          alertLevel: VolcanoIconAssets.levelForVolcanoEvent(
            volcano,
            officialSite: official,
          ),
        );
        sites.add(site);
        continue;
      }
      if (!volcano.hasMapLocation) continue;
      sites.add(
        JmaVolcanoSite(
          code: volcano.volcanoCode.trim().isEmpty
              ? event.eventId
              : volcano.volcanoCode.trim(),
          nameJp: volcano.volcanoName,
          nameEn: '',
          latitude: volcano.latitude!,
          longitude: volcano.longitude!,
          levelOperation: false,
          alertLevel: VolcanoIconAssets.levelForVolcanoEvent(volcano),
          hasWarning: false,
          hasRecentInfo: volcano.isCommentaryInfo,
          hasRecentEruption: false,
          hasProvisionalInfo: volcano.isProvisionalCommentary,
        ),
      );
    }
    return sites;
  }

  void _syncTyphoonLayerServiceWithOverlay() {
    final mapState = _mapStateProvider;
    if (mapState == null) return;
    _quakeProvider?.setTyphoonLayerEnabled(
      mapState.isOverlayEnabled('typhoonLayer'),
    );
  }

  void _syncLiveWeatherTileRefresh() {
    final mapState = _mapStateProvider;
    final cloud = mapState?.isOverlayEnabled('cloudLayer') == true;
    final wind = mapState?.isOverlayEnabled('windLayer') == true;
    final rain = mapState?.isOverlayEnabled('rainLayer') == true;
    final signature = '$cloud|$wind|$rain';
    final anyLiveLayer = cloud || wind || rain;
    if (!anyLiveLayer) {
      _liveWeatherTileRefreshTimer?.cancel();
      _liveWeatherTileRefreshTimer = null;
      _liveWeatherTileOverlaySignature = signature;
      _liveWeatherTileRefreshInterval = null;
      return;
    }

    final interval = (cloud || rain)
        ? const Duration(minutes: 10)
        : const Duration(minutes: 30);
    final signatureChanged = signature != _liveWeatherTileOverlaySignature;
    final intervalChanged = interval != _liveWeatherTileRefreshInterval;
    _liveWeatherTileOverlaySignature = signature;
    _liveWeatherTileRefreshInterval = interval;

    if (signatureChanged) {
      _refreshLiveWeatherTiles();
    }
    if (signatureChanged ||
        intervalChanged ||
        _liveWeatherTileRefreshTimer == null) {
      _liveWeatherTileRefreshTimer?.cancel();
      _liveWeatherTileRefreshTimer = Timer.periodic(
        interval,
        (_) => _refreshLiveWeatherTiles(),
      );
    }
  }

  void _refreshLiveWeatherTiles() {
    _liveWeatherTileVersion = DateTime.now().millisecondsSinceEpoch;
    // Versioned overlay URLs refresh weather without evicting base-map images.
    _notifyLayer(_liveWeatherTileRevision);
  }

  void _syncFanRadarServiceWithOverlay() {
    final mapState = _mapStateProvider;
    final shouldRun =
        mapState != null && mapState.isOverlayEnabled('radarChinaLayer');
    if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
      _fanRadarService.stop(clear: false);
      if (shouldRun && !_foregroundHostedOverlayKeys.contains('fanRadar')) {
        _foregroundHostedOverlayKeys.add('fanRadar');
        unawaited(BackgroundService().requestSourceReload());
      } else if (!shouldRun) {
        _foregroundHostedOverlayKeys.remove('fanRadar');
        _latestFanRadarFrame = null;
        _notifyLayer(_fanRadarLayerRevision);
      }
      return;
    }
    if (shouldRun) {
      _fanRadarService.start(interval: FanRadarService.refreshInterval);
    } else {
      _fanRadarService.stop(clear: true);
    }
  }

  void _syncPrecipitationServiceWithOverlay() {
    final shouldRun =
        _mapStateProvider?.isOverlayEnabled('precipitationChinaLayer') == true;
    if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
      _precipitationService.stop(clear: false);
      if (shouldRun && !_foregroundHostedOverlayKeys.contains('cmaPrecipitation')) {
        _foregroundHostedOverlayKeys.add('cmaPrecipitation');
        unawaited(BackgroundService().requestSourceReload());
      } else if (!shouldRun) {
        _foregroundHostedOverlayKeys.remove('cmaPrecipitation');
        _latestPrecipitationFrame = null;
        _notifyLayer(_precipitationLayerRevision);
      }
      return;
    }
    if (shouldRun) {
      _precipitationService.start(
        interval: FanRadarService.precipitationRefreshInterval,
      );
    } else {
      _precipitationService.stop(clear: true);
    }
  }

  void _syncJmaRadarServiceWithOverlay() {
    final mapState = _mapStateProvider;
    final shouldRun =
        mapState != null && mapState.isOverlayEnabled('jmaRadarLayer');
    if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
      _jmaRadarService.stop(clear: false);
      if (shouldRun && !_foregroundHostedOverlayKeys.contains('jmaRadar')) {
        _foregroundHostedOverlayKeys.add('jmaRadar');
        unawaited(BackgroundService().requestSourceReload());
      } else if (!shouldRun) {
        _foregroundHostedOverlayKeys.remove('jmaRadar');
        _latestJmaRadarFrame = null;
        _notifyLayer(_jmaRadarLayerRevision);
      }
      return;
    }
    if (shouldRun) {
      _jmaRadarService.start(interval: JmaRadarService.refreshInterval);
    } else {
      _jmaRadarService.stop(clear: true);
    }
  }

  void _syncFanSatelliteCloudServiceWithOverlay() {
    final mapState = _mapStateProvider;
    final shouldRun =
        mapState != null && mapState.isOverlayEnabled('satelliteCloudLayer');
    if (BackgroundService().isAndroidConnectionHostedByForegroundService) {
      _fanSatelliteCloudService.stop(clear: false);
      if (shouldRun && !_foregroundHostedOverlayKeys.contains('fanSatellite')) {
        _foregroundHostedOverlayKeys.add('fanSatellite');
        unawaited(BackgroundService().requestSourceReload());
      } else if (!shouldRun) {
        _foregroundHostedOverlayKeys.remove('fanSatellite');
        _latestFanSatelliteCloudFrame = null;
        _notifyLayer(_fanSatelliteCloudLayerRevision);
      }
      return;
    }
    if (shouldRun) {
      _fanSatelliteCloudService.start(interval: const Duration(minutes: 30));
    } else {
      _fanSatelliteCloudService.stop(clear: true);
    }
  }

  void _refreshFanSatelliteCloudOnTyphoonUpdate() {
    final mapState = _mapStateProvider;
    if (mapState?.isOverlayEnabled('satelliteCloudLayer') != true) return;
    if (!_fanSatelliteCloudService.isRunning) {
      _fanSatelliteCloudService.start(interval: const Duration(minutes: 30));
      return;
    }
    unawaited(_fanSatelliteCloudService.fetchNow());
  }

  void _startFdsnServices(Set<String> enabledSources) {
    if (_fdsnServicesActive) {
      _syncFdsnStationSources(enabledSources);
      _fdsnMotionService.connect(
        stationLimit: QuakeMapView.fdsnStationLimitNotifier.value,
        enabledSources: enabledSources,
      );
      return;
    }
    _fdsnServicesActive = true;
    _syncFdsnStationSources(enabledSources);
    _fdsnMotionService.connect(
      stationLimit: QuakeMapView.fdsnStationLimitNotifier.value,
      enabledSources: enabledSources,
    );
    _fdsnMotionSubscription = _fdsnMotionService.sampleStream.listen(
      _handleFdsnMotionSample,
    );
  }

  void _syncFdsnStationSources(Set<String> enabledSources) {
    if (enabledSources.contains('EarthScope')) {
      if (_earthScopeStationSubscription == null) {
        unawaited(_earthScopeStationService.start());
        _earthScopeStationSubscription = _earthScopeStationService.stationStream
            .listen((stations) {
              if (mounted) {
                final updated = _applyLatestFdsnMotionToStations(stations);
                _earthScopeStations = updated;
                _earthScopeStationIndex = _buildFdsnStationIndex(updated);
                _notifyLayer(_earthScopeLayerRevision);
              }
            });
      }
    } else {
      _earthScopeStationSubscription?.cancel();
      _earthScopeStationSubscription = null;
      _earthScopeStationService.stop();
      _earthScopeStationIndex = const {};
      if (_earthScopeStations.isNotEmpty) {
        _earthScopeStations = [];
        _notifyLayer(_earthScopeLayerRevision);
      }
    }

    if (enabledSources.contains('GEOFON')) {
      if (_geofonStationSubscription == null) {
        unawaited(_geofonStationService.start());
        _geofonStationSubscription = _geofonStationService.stationStream.listen(
          (stations) {
            if (mounted) {
              final updated = _applyLatestFdsnMotionToStations(stations);
              _geofonStations = updated;
              _geofonStationIndex = _buildFdsnStationIndex(updated);
              _notifyLayer(_geofonLayerRevision);
            }
          },
        );
      }
    } else {
      _geofonStationSubscription?.cancel();
      _geofonStationSubscription = null;
      _geofonStationService.stop();
      _geofonStationIndex = const {};
      if (_geofonStations.isNotEmpty) {
        _geofonStations = [];
        _notifyLayer(_geofonLayerRevision);
      }
    }
  }

  void _restartFdsnMotionService() {
    _fdsnMotionRestartTimer = null;
    if (!_fdsnServicesActive || !_fdsnSeedLinkEnabled) return;
    final enabledSources = <String>{
      if (_mapStateProvider?.isOverlayEnabled('fdsnEarthScope') == true)
        'EarthScope',
      if (_mapStateProvider?.isOverlayEnabled('fdsnGeofon') == true) 'GEOFON',
    };
    if (enabledSources.isEmpty) {
      _stopFdsnServices(clearStations: true);
      return;
    }
    _fdsnMotionSubscription?.cancel();
    _fdsnMotionSubscription = null;
    _fdsnMotionFlushTimer?.cancel();
    _fdsnMotionFlushTimer = null;
    _pendingFdsnMotionSamples.clear();
    _fdsnMotionService.disconnect();
    _fdsnMotionService.connect(
      stationLimit: QuakeMapView.fdsnStationLimitNotifier.value,
      enabledSources: enabledSources,
    );
    _fdsnMotionSubscription = _fdsnMotionService.sampleStream.listen(
      _handleFdsnMotionSample,
    );
  }

  void _stopFdsnServices({bool clearStations = false}) {
    _fdsnServicesActive = false;
    _obsAutomationInputs.clearStationNetwork('fdsn');
    _earthScopeStationSubscription?.cancel();
    _earthScopeStationSubscription = null;
    _geofonStationSubscription?.cancel();
    _geofonStationSubscription = null;
    _fdsnMotionSubscription?.cancel();
    _fdsnMotionSubscription = null;
    _fdsnMotionRestartTimer?.cancel();
    _fdsnMotionRestartTimer = null;
    _fdsnMotionFlushTimer?.cancel();
    _fdsnMotionFlushTimer = null;
    _pendingFdsnMotionSamples.clear();
    if (clearStations) {
      _latestFdsnMotionSamples.clear();
      _latestFdsnMotionReceivedAt.clear();
      _lastFdsnUiUpdateAt.clear();
    }
    _fdsnMotionService.disconnect();
    _earthScopeStationService.stop();
    _geofonStationService.stop();

    if (clearStations &&
        mounted &&
        (_earthScopeStations.isNotEmpty || _geofonStations.isNotEmpty)) {
      if (_earthScopeStations.isNotEmpty) {
        _earthScopeStations = [];
        _notifyLayer(_earthScopeLayerRevision);
      }
      if (_geofonStations.isNotEmpty) {
        _geofonStations = [];
        _notifyLayer(_geofonLayerRevision);
      }
      _earthScopeStationIndex = const {};
      _geofonStationIndex = const {};
    }
  }

  /// 缁戝畾鎵€鏈変簨浠惰繃鏈熷洖璋?

  void _bindAllEventsExpiredCallback() {
    final provider = _quakeProvider;
    if (provider == null) return;
    provider.onAllEventsExpired = () {
      if (!mounted) return;
      // Align with kanameishi: expire triggers a normal auto-policy refresh.
      // It is not a forced default reset; manual lock still wins.
      _queueCameraPolicyRefresh(force: false);
    };
  }

  /// 澶勭悊鏂伴璀︿簨浠?  ///
  /// 单预警：定位到震中，zoom=6.0
  /// Desktop events retain individual framing rather than a combined extent.
  void _syncWaveAutoZoom() {
    if (!mounted) return;
    if (!_hasActiveCameraPolicyWork) {
      _syncWaveAutoZoomTimer();
      return;
    }
    final mapState = _mapStateProvider;
    if (mapState == null) return;
    if (!mapState.canAutoFollow) {
      _syncWaveAutoZoomTimer();
      return;
    }
    _queueCameraPolicyRefresh();
  }

  bool get _hasActiveCameraPolicyWork {
    final provider = _quakeProvider;
    if (provider == null) return false;
    if (provider.unifiedEvents.isNotEmpty) return true;
    if (_stationDetectionFocus().points.isNotEmpty) return true;
    if (_preferredEventFocus != null &&
        _preferredEventFocusUntil != null &&
        DateTime.now().isBefore(_preferredEventFocusUntil!)) {
      return true;
    }
    return _hasNiedSourceEstimate;
  }

  Future<void> _loadCameraDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble('map_view_lat');
    final lng = prefs.getDouble('map_view_lng');
    final zoom = prefs.getDouble('map_default_zoom');
    if (lat != null && lng != null) {
      _preferredViewCenter = LatLng(lat, lng);
    }
    if (zoom != null && zoom >= 3.0 && zoom <= 12.0) {
      _preferredDefaultZoom = zoom;
    }
    if (mounted) {
      _queueCameraPolicyRefresh(force: false);
    }
  }

  void _onUserLocationChanged() {
    final pos = LocationService().currentPosition;
    if (pos != null) {
      _preferredViewCenter = LatLng(pos.latitude, pos.longitude);
    }
    if (mounted) {
      _queueCameraPolicyRefresh(force: true);
    }
  }

  List<QuakeMessage> _unifiedEewMapEvents(QuakeProvider provider) {
    final unifiedEvents = provider.unifiedEvents;
    final mapEvents = provider.unifiedMapEvents;
    final waveEvents = <QuakeMessage>[];
    for (int i = 0; i < unifiedEvents.length && i < mapEvents.length; i++) {
      if (unifiedEvents[i].isEew) {
        waveEvents.add(mapEvents[i]);
      }
    }
    return waveEvents;
  }

  /// 临时显示信息事件位置
  ///
  /// 褰撴湁棰勮鏃舵敹鍒颁俊鎭簨浠讹紝璺宠浆鍒颁俊鎭簨浠朵綅缃?绉掑悗鍥炲埌棰勮浣嶇疆
  bool _shouldSplitDistantUnifiedFocus(List<QuakeMessage> events) {
    if (events.length < 2) return false;
    var maxDistanceKm = 0.0;
    for (var i = 0; i < events.length; i++) {
      final a = events[i];
      if (!QuakeCalculator.isUsableMapCoordinate(a.latitude, a.longitude)) {
        continue;
      }
      for (var j = i + 1; j < events.length; j++) {
        final b = events[j];
        if (!QuakeCalculator.isUsableMapCoordinate(b.latitude, b.longitude)) {
          continue;
        }
        final distance = QuakeCalculator.haversineDistance(
          a.latitude,
          a.longitude,
          b.latitude,
          b.longitude,
        );
        if (distance > maxDistanceKm) {
          maxDistanceKm = distance;
        }
      }
    }
    return maxDistanceKm > _splitUnifiedFocusDistanceKm;
  }

  QuakeMessage? _currentEewFocusEvent(
    QuakeProvider provider,
    List<QuakeMessage> eewEvents,
  ) {
    if (eewEvents.isEmpty) return null;
    final index = provider.currentUnifiedIndex;
    final unifiedEvents = provider.unifiedEvents;
    final mapEvents = provider.unifiedMapEvents;
    if (index >= 0 &&
        index < unifiedEvents.length &&
        index < mapEvents.length &&
        unifiedEvents[index].isEew) {
      return mapEvents[index];
    }
    return eewEvents[index % eewEvents.length];
  }

  QuakeMessage? _currentInfoFocusEvent(
    QuakeProvider provider,
    List<QuakeMessage> infoEvents,
  ) {
    if (infoEvents.isEmpty) return null;
    final index = provider.currentUnifiedIndex;
    final unifiedEvents = provider.unifiedEvents;
    final mapEvents = infoEvents;
    if (index >= 0 &&
        index < unifiedEvents.length &&
        index < mapEvents.length &&
        !unifiedEvents[index].isEew) {
      return mapEvents[index];
    }
    return infoEvents[index % infoEvents.length];
  }

  String _cameraEventTag(QuakeMessage event) {
    final id = event.eventId.isEmpty ? 'noid' : event.eventId;
    final report = event.reportNumber?.toString() ?? 'r0';
    return '${event.source.name}:$id:$report';
  }

  DesktopCameraCandidate? _selectDesktopCameraFocus(
    QuakeProvider provider,
    MapStateProvider mapState, {
    required bool isEew,
  }) {
    final events = provider.unifiedEvents;
    final mapEvents = provider.unifiedMapEvents;
    final candidates = <DesktopCameraCandidate>[];
    for (var i = 0; i < events.length && i < mapEvents.length; i++) {
      final event = events[i];
      if (event.isEew != isEew) continue;
      final mapEvent = mapEvents[i];
      final points = isEew
          ? const <LatLng>[]
          : _unifiedInfoFocusPoints(provider, event, mapEvent);
      final candidate = DesktopCameraCandidate.fromEvent(
        event,
        index: i,
        focusPoints: points,
      );
      if (candidate != null) candidates.add(candidate);
    }
    final padding = cencIrViewportPadding(context)!;
    return _desktopEventCameraFocus.select(
      candidates: candidates,
      requestedIndex: provider.currentUnifiedIndex,
      isVisible: (point) => mapState.isPointInEventViewport(
        point,
        padding: padding,
      ),
    );
  }

  bool _applyDesktopInfoFocusPolicy(
    QuakeProvider provider,
    MapStateProvider mapState,
    bool force,
  ) {
    final target = _selectDesktopCameraFocus(provider, mapState, isEew: false);
    if (target == null) return false;
    final event = provider.unifiedEvents[target.index];
    final mapEvent = provider.unifiedMapEvents[target.index];
    final points = _unifiedInfoFocusPoints(provider, event, mapEvent);
    final padding = cencIrViewportPadding(context)!;
    final stationFit = event.source == 'nowQuakeCencIr' && points.length > 1;
    final areaFit = stationFit || (event.isVolcanoEvent && points.length > 1);
    final screenOffset = Offset(
      (padding.left - padding.right) / 2,
      (padding.top - padding.bottom) / 2,
    );
    provider.setMobileCameraInfoFocus(null);
    if (points.isNotEmpty) {
      mapState.smartMoveToPoints(
        points,
        padding: 0.8,
        minZoom: 3,
        maxZoom: stationFit ? 12 : 8,
        viewportPadding: areaFit ? padding : null,
        focusAnchor: event.source == 'nowQuakeCencIr'
            ? LatLng(mapEvent.latitude, mapEvent.longitude)
            : null,
        screenOffset: areaFit ? Offset.zero : screenOffset,
        sourceTag: 'policy-desktop-info-area-${target.key}',
        force: force,
        minInterval: const Duration(milliseconds: 1200),
      );
    } else {
      mapState.smartMoveToEvents(
        [mapEvent],
        padding: 1,
        minZoom: 3,
        screenOffset: screenOffset,
        sourceTag: 'policy-desktop-info-${target.key}',
        force: force,
        minInterval: const Duration(milliseconds: 1200),
      );
    }
    return true;
  }

  String _eewWaveCameraEventKey(QuakeMessage event) {
    final eventId = event.eventId.isEmpty
        ? '${event.latitude.toStringAsFixed(4)},${event.longitude.toStringAsFixed(4)}'
        : event.eventId;
    return '${event.source.name}:$eventId';
  }

  int _latestUnifiedInfoIndex(List<UnifiedQuakeData> events) {
    var bestIndex = -1;
    DateTime? bestTime;
    for (var i = 0; i < events.length; i++) {
      final event = events[i];
      if (event.isEew || event.isVolcanoEvent) continue;
      final time = event.arrivedAt ?? event.reportTime ?? event.originTime;
      if (bestIndex < 0 ||
          (time != null && (bestTime == null || time.isAfter(bestTime)))) {
        bestIndex = i;
        bestTime = time;
      }
    }
    return bestIndex;
  }

  String _unifiedInfoFocusSignature(
    UnifiedQuakeData event, {
    CencIrData? cencIrData,
  }) {
    final time =
        event.reportTime ?? event.originTime ?? event.arrivedAt ?? DateTime(0);
    return [
      'eew-info',
      event.source,
      event.eventId,
      event.titleText,
      event.reportNumText,
      event.maxIntensity,
      event.warnArea.hashCode,
      if (event.source == 'nowQuakeCencIr') identityHashCode(cencIrData),
      time.millisecondsSinceEpoch,
    ].join(':');
  }

  void _onNiedShakeDetected(int shindo) {
    if (!mounted) return;
    SoundEffectService().playShindo(shindo, source: 'nied');
    if (shindo < 1) return;
    if (!_requestNiedStationFocus(force: true)) {
      _pendingNiedStationFocus = true;
    }
  }

  void _onNiedShakeExpired() {
    if (!mounted) return;
    _lastNiedStationFocusSignature = null;
    _lastNiedStationFocusAt = null;
    _pendingNiedStationFocus = false;
    _niedGridCellCenters.clear();
    _latestDetectSnapshot = ShakeDetectionService.idleSnapshot;
    _emitStationSummary();
    _queueCameraPolicyRefresh(force: true);
  }

  void _resetNiedDetectionState({
    bool detachStations = false,
    bool clearStationValues = true,
  }) {
    _obsAutomationInputs.clearStationNetwork('nied');
    _shakeDetection.reset(
      clearStationState: true,
      clearStationValues: clearStationValues,
      detachStations: detachStations,
      emitSnapshot: false,
    );
    _latestDetectSnapshot = ShakeDetectionService.idleSnapshot;
    _niedGridCellCenters.clear();
    _lastNiedStationFocusSignature = null;
    _lastNiedStationFocusAt = null;
    _pendingNiedStationFocus = false;
    _lastNiedLayerSignature = '';
    _clearNiedSourceEstimationState();
    _emitStationSummary();
    _syncActivityTimers();
    _notifyLayer(_niedLayerRevision);
  }

  void _onKmaShakeExpired() {
    if (!mounted) return;
    _lastKmaStationFocusSignature = null;
    _lastKmaStationFocusAt = null;
    _pendingKmaStationFocus = false;
    _onShakeExpired();
  }

  void _onTremShakeExpired() {
    if (!mounted) return;
    _lastTremStationFocusSignature = null;
    _lastTremStationFocusAt = null;
    _pendingTremStationFocus = false;
    _onShakeExpired();
  }

  void _onHideGridOnEewChanged() {
    _hideGridOnEew = UiRuntimeFlags.hideGridOnEewNotifier.value;
    if (mounted) {
      setState(() {});
      _queueCameraPolicyRefresh();
    }
  }

  List<SeismicActiveEvent> _visiblePAlertSources() {
    if (!_showNiedEstimatedEpicenter || !_pAlertEnabled) return const [];
    return PAlertSourceState.events.value.where((event) =>
      event.estimate != null && shouldShowPAlertSource(
        event.estimate!, _quakeProvider?.unifiedEvents ?? const [],
        hideOnMatchingEew: _hideGridOnEew,
      )).toList(growable: false);
  }

  void _clearPAlertSourceEstimation() {
    _pAlertSourceGeneration++;
    _pAlertSourceExpiry?.cancel();
    _pAlertSourceExpiry = null;
    _pAlertSourceWorker.reset();
    if (PAlertSourceState.events.value.isNotEmpty) {
      PAlertSourceState.events.value = const [];
      _queueCameraPolicyRefresh();
    }
  }

  Future<void> _processPAlertSourceEstimation(
    List<PAlertStation> stations, Set<String> confirmedIds,
  ) async {
    if (!mounted || !_pAlertEnabled || !_showNiedEstimatedEpicenter) return;
    final received = stations.map((s) => s.receivedAt).whereType<DateTime>()
        .fold<DateTime?>(null, (last, time) =>
          last == null || time.isAfter(last) ? time : last);
    if (received == null || PAlertService.isFrameStale(received, DateTime.now())) {
      _clearPAlertSourceEstimation();
      return;
    }
    _pAlertSourceExpiry?.cancel();
    _pAlertSourceExpiry = Timer(
      received.add(PAlertService.frameStaleAfter).difference(DateTime.now()),
      _clearPAlertSourceEstimation,
    );
    final generation = _pAlertSourceGeneration;
    try {
      final events = await _pAlertSourceWorker.process(stations, confirmedIds);
      if (!mounted || generation != _pAlertSourceGeneration || events == null ||
          !_pAlertEnabled || !_showNiedEstimatedEpicenter ||
          PAlertService.isFrameStale(received, DateTime.now())) {
        return;
      }
      if (events.isEmpty && PAlertSourceState.events.value.isEmpty) return;
      PAlertSourceState.events.value = events;
      _queueCameraPolicyRefresh();
    } catch (error, stack) {
      debugPrint('P-Alert source estimation failed: $error\n$stack');
      if (mounted && generation == _pAlertSourceGeneration) {
        _clearPAlertSourceEstimation();
      }
    }
  }

  void _onPAlertShakeExpired() {
    if (!mounted) return;
    _clearPAlertStationFocus();
    _onShakeExpired();
  }

  void _clearPAlertStationFocus() {
    _clearPAlertSourceEstimation();
    _pAlertDetectionGrid.clear();
    _lastPAlertStationFocusSignature = null;
    _lastPAlertStationFocusAt = null;
    _pendingPAlertStationFocus = false;
    _syncActivityTimers();
    _notifyLayer(_pAlertLayerRevision);
  }

  void _requestEventPointFocus(
    QuakeMessage event,
    String signature, {
    bool force = false,
    Duration hold = const Duration(seconds: 4),
    List<LatLng> focusPoints = const [],
    UnifiedQuakeData? unifiedInfo,
  }) {
    if (!mounted) return;
    if (!UiScale.isPhone(context) &&
        focusPoints.isEmpty &&
        QuakeCalculator.isUsableMapCoordinate(event.latitude, event.longitude) &&
        (_mapStateProvider?.isPointInEventViewport(
          LatLng(event.latitude, event.longitude),
          padding: cencIrViewportPadding(context)!,
        ) ?? false)) {
      return;
    }
    if (!force && signature == _lastEventPointFocusSignature) return;
    _lastEventPointFocusSignature = signature;
    _preferredEventFocus = event;
    _preferredUnifiedInfoFocus = unifiedInfo;
    _preferredEventFocusPoints = List.unmodifiable(focusPoints);
    final until = DateTime.now().add(hold);
    _preferredEventFocusUntil = until;
    _preferredEventFocusSignature = signature;
    _preferredEventFocusTimer?.cancel();
    _preferredEventFocusTimer = Timer(hold, () {
      _preferredEventFocusTimer = null;
      if (!mounted) return;
      if (_preferredEventFocusSignature != signature ||
          _preferredEventFocusUntil != until) {
        return;
      }
      _clearPreferredEventFocus();
      _quakeProvider?.setMobileCameraInfoFocus(null);
      _queueCameraPolicyRefresh(force: true);
      setState(() {});
    });
    _queueCameraPolicyRefresh(force: force);
  }

  void _clearPreferredEventFocus() {
    _preferredEventFocusTimer?.cancel();
    _preferredEventFocusTimer = null;
    _preferredEventFocus = null;
    _preferredUnifiedInfoFocus = null;
    _preferredEventFocusPoints = const [];
    _preferredEventFocusUntil = null;
    _preferredEventFocusSignature = null;
  }

  String? _activePreferredInfoFocusSignature() {
    final until = _preferredEventFocusUntil;
    final signature = _preferredEventFocusSignature;
    if (until == null || signature == null) return null;
    if (!DateTime.now().isBefore(until)) return null;
    return signature;
  }

  String _eewTakeoverSignature(List<UnifiedQuakeData> events) {
    final ids =
        events
            .where((event) => event.isEew)
            .map((event) => '${event.source}:${event.eventId}')
            .toList()
          ..sort();
    return ids.join('|');
  }

  bool _shouldDrawIntensityForEvent(
    UnifiedQuakeData event,
    bool hasEew,
    String? activeInfoFocusSignature,
  ) {
    if (!hasEew) return true;
    if (activeInfoFocusSignature != null) {
      return !event.isEew &&
          _unifiedInfoFocusSignature(event) == activeInfoFocusSignature;
    }
    return event.isEew;
  }

  bool _isJmaIntensityMapEvent(QuakeMessage event) {
    return event.source == QuakeSourceType.wolfx ||
        event.source == QuakeSourceType.jma_fan ||
        event.source == QuakeSourceType.p2p;
  }

  List<LatLng> _p2pJmaInfoFocusPoints(
    UnifiedQuakeData event,
    QuakeMessage mapEvent,
  ) {
    final isP2p =
        !event.isEew &&
        ((event.source == 'jmaEqlist' && event.origin == 2) ||
            event.source == 'p2pJmaEqlist');
    if (!isP2p) return const [];
    return jmaInfoFocusPoints(
      warnAreaJson: event.warnArea,
      epicenterLatitude: mapEvent.latitude,
      epicenterLongitude: mapEvent.longitude,
    );
  }

  List<LatLng> _cencIrInfoFocusPoints(
    QuakeProvider provider,
    UnifiedQuakeData event,
    QuakeMessage mapEvent,
  ) {
    if (event.isEew || event.source != 'nowQuakeCencIr') return const [];
    final data = provider.realtimeCencIrData;
    if (data == null) return const [];
    return cencIrFocusPoints(
      data: data,
      eventId: event.eventId,
      epicenterLatitude: mapEvent.latitude,
      epicenterLongitude: mapEvent.longitude,
    );
  }

  List<LatLng> _unifiedInfoFocusPoints(
    QuakeProvider provider,
    UnifiedQuakeData event,
    QuakeMessage mapEvent,
  ) {
    final volcano = event.volcanoEvent;
    if (volcano != null) return volcanoInfoFocusPoints(volcano);
    final jmaPoints = _p2pJmaInfoFocusPoints(event, mapEvent);
    if (jmaPoints.isNotEmpty) return jmaPoints;
    return _cencIrInfoFocusPoints(provider, event, mapEvent);
  }

  ({QuakeMessage event, String warnAreaJson, String key})?
  _combinedJmaIntensityLayerData(
    List<UnifiedQuakeData> unifiedEvents,
    List<QuakeMessage> mapEvents,
    bool hasEew,
    String? activeInfoFocusSignature,
  ) {
    final warnAreaItems = <dynamic>[];
    final keyParts = <String>[];
    QuakeMessage? representative;
    final count = math.min(unifiedEvents.length, mapEvents.length);

    for (var i = 0; i < count; i++) {
      final unified = unifiedEvents[i];
      final mapEvent = mapEvents[i];
      if (!_isJmaIntensityMapEvent(mapEvent)) continue;
      if (!_shouldDrawIntensityForEvent(
        unified,
        hasEew,
        activeInfoFocusSignature,
      )) {
        continue;
      }

      representative ??= mapEvent;
      keyParts.add('${unified.source}:${unified.eventId}');

      final warnArea = unified.warnArea.trim();
      if (warnArea.isEmpty) continue;
      try {
        final decoded = json.decode(warnArea);
        if (decoded is List) {
          warnAreaItems.addAll(decoded);
        }
      } catch (_) {}
    }

    final event = representative;
    if (event == null) return null;
    if (warnAreaItems.isEmpty && event.magnitude <= 0) return null;
    return (
      event: event,
      warnAreaJson: warnAreaItems.isEmpty ? '' : json.encode(warnAreaItems),
      key: keyParts.join('|'),
    );
  }

  void _onKmaShakeDetected(int maxShindo, {DateTime? detectedAt}) {
    if (!mounted) return;
    SoundEffectService().playShindo(
      maxShindo, source: 'kma', detectedAt: detectedAt,
    );
    if (!_requestKmaStationFocus(force: true)) {
      _pendingKmaStationFocus = true;
    }
  }

  void _onTremShakeDetected(int maxShindo, {DateTime? detectedAt}) {
    if (!mounted) return;
    SoundEffectService().playShindo(
      maxShindo, source: 'trem', detectedAt: detectedAt,
    );
    if (!_requestTremStationFocus(force: true)) {
      _pendingTremStationFocus = true;
    }
  }

  void _onPAlertShakeDetected(int maxShindo, {DateTime? detectedAt}) {
    if (!mounted) return;
    SoundEffectService().playShindo(
      maxShindo, source: 'palert', detectedAt: detectedAt,
    );
    if (!_requestPAlertStationFocus(force: true)) {
      _pendingPAlertStationFocus = true;
    }
  }

  bool _requestNiedStationFocus({bool force = false}) {
    if (!mounted) return false;
    final provider = context.read<QuakeProvider>();
    if (provider.unifiedEvents.any((e) => e.isEew)) return false;

    final focusPoints = _niedFocusPoints();
    if (focusPoints.isEmpty) {
      _lastNiedStationFocusSignature = null;
      _lastNiedStationFocusAt = null;
      return false;
    }

    final signature = _niedGridFocusSignature(focusPoints);
    final now = DateTime.now();
    final lastAt = _lastNiedStationFocusAt;
    if (!force) {
      if (signature == _lastNiedStationFocusSignature) return false;
      if (lastAt != null &&
          now.difference(lastAt) < const Duration(seconds: 5)) {
        return false;
      }
    }

    _lastNiedStationFocusSignature = signature;
    _lastNiedStationFocusAt = now;
    _queueCameraPolicyRefresh(force: force);
    return true;
  }

  void _queueCameraPolicyRefresh({bool force = false}) {
    if (!mounted) return;
    _syncWaveAutoZoomTimer();
    _cameraPolicyForce = _cameraPolicyForce || force;
    if (!(_mapStateProvider?.isSeismicViewportVisible ?? true)) return;
    if (_cameraPolicyQueued) return;
    _cameraPolicyQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cameraPolicyQueued = false;
      if (!mounted) return;
      final useForce = _cameraPolicyForce;
      _cameraPolicyForce = false;
      _applyCameraPolicy(force: useForce);
    });
  }

  void _applyCameraPolicy({bool force = false}) {
    if (!mounted) return;
    final mapState = _mapStateProvider;
    if (mapState == null || !mapState.isSeismicViewportVisible) return;
    final info = _preferredUnifiedInfoFocus;
    final infoStillActive =
        info != null &&
        (_quakeProvider?.unifiedEvents.any(
              (event) =>
                  event.source == info.source && event.eventId == info.eventId,
            ) ??
            false);
    if (_quakeProvider?.mobileEewCarousel == true &&
        info != null &&
        !infoStillActive) {
      _clearPreferredEventFocus();
    }
    if (mapState.isGestureAutoFollowPaused) {
      _cameraPolicyForce = _cameraPolicyForce || force;
      return;
    }
    if (force && mapState.isHistoryEventSelected) {
      mapState.clearSelectedHistoryEvent();
    }
    if (!force && !mapState.canAutoFollow) return;
    if (force && !mapState.canAutoFollow) {
      mapState.resumeAutoZoom();
    }
    final provider = _quakeProvider;
    if (provider == null) return;
    final now = DateTime.now();

    final mapEvents = provider.unifiedMapEvents;
    final eewEvents = _unifiedEewMapEvents(provider);
    final desktop = !UiScale.isPhone(context);
    final activeEewKeys = eewEvents.map(_eewWaveCameraEventKey).toSet();
    _desktopEewCameraGates.removeWhere((key, _) => !activeEewKeys.contains(key));

    final selectedHistory = mapState.selectedHistoryEvent;
    if (selectedHistory != null &&
        QuakeCalculator.isUsableMapCoordinate(
          selectedHistory.latitude,
          selectedHistory.longitude,
        )) {
      provider.setMobileCameraInfoFocus(null);
      mapState.smartMoveToCenter(
        LatLng(selectedHistory.latitude, selectedHistory.longitude),
        zoom: 7.0,
        sourceTag: 'policy-history-${_cameraEventTag(selectedHistory)}',
        force: true,
        minInterval: Duration.zero,
      );
      return;
    }

    if (eewEvents.isNotEmpty) {
      if (_preferredEventFocus != null &&
          _preferredEventFocusUntil != null &&
          now.isBefore(_preferredEventFocusUntil!)) {
        final focus = _preferredEventFocus!;
        provider.setMobileCameraInfoFocus(_preferredUnifiedInfoFocus);
        if (_preferredEventFocusPoints.isNotEmpty) {
          final isCencIrFocus =
              _preferredUnifiedInfoFocus?.source == 'nowQuakeCencIr';
          final viewportPadding =
              isCencIrFocus &&
                      _preferredEventFocusPoints.length > 1
                  ? cencIrViewportPadding(context)
                  : null;
          mapState.smartMoveToPoints(
            _preferredEventFocusPoints,
            padding: 0.8,
            minZoom: isCencIrFocus ? 3.0 : 4.5,
            maxZoom: isCencIrFocus ? 12.0 : 7.5,
            viewportPadding: viewportPadding,
            focusAnchor: isCencIrFocus
                ? LatLng(focus.latitude, focus.longitude)
                : null,
            screenOffset: _eventFocusOffset(),
            sourceTag: 'policy-event-area-focus',
            force: force,
            minInterval: const Duration(milliseconds: 1200),
          );
          return;
        }
        mapState.smartMoveToEvents(
          [focus],
          padding: 0.8,
          minZoom: 4.5,
          maxZoom: 7.5,
          screenOffset: _eventFocusOffset(),
          sourceTag: 'policy-event-focus',
          force: force,
          minInterval: const Duration(milliseconds: 1200),
        );
        return;
      }

      _clearPreferredEventFocus();

      provider.setMobileCameraInfoFocus(null);

      final desktopFocus = desktop
          ? _selectDesktopCameraFocus(provider, mapState, isEew: true)
          : null;
      final splitDistantEewFocus = desktop
          ? desktopFocus != null
          : _shouldSplitDistantUnifiedFocus(eewEvents);
      final currentEewFocus = desktopFocus != null
          ? mapEvents[desktopFocus.index]
          : splitDistantEewFocus
              ? _currentEewFocusEvent(provider, eewEvents)
              : null;
      final focusedEewEvents = eewCameraFocusEvents(
        events: eewEvents,
        splitDistant: splitDistantEewFocus,
        currentEvent: currentEewFocus,
      );
      final waveGate = desktop && currentEewFocus != null
          ? _desktopEewCameraGates.putIfAbsent(
              _eewWaveCameraEventKey(currentEewFocus),
              EewWaveCameraFollowGate.new,
            )
          : _eewWaveCameraFollowGate;
      final eewWaveCameraReleased = waveGate.syncEvents(
        (desktop ? focusedEewEvents : eewEvents).map(_eewWaveCameraEventKey),
        now,
      );

      if (eewWaveCameraReleased) {
        mapState.smartMoveToEvents(
          focusedEewEvents,
          padding: 0.0,
          minZoom: 4.5,
          maxZoom: 8.0,
          screenOffset: _eventFocusOffset(),
          sourceTag: splitDistantEewFocus && currentEewFocus != null
              ? 'policy-unified-eew-split-epicenter-${_cameraEventTag(currentEewFocus)}'
              : 'policy-unified-eew-epicenters',
          force: force,
          minInterval: const Duration(milliseconds: 1500),
        );
        return;
      }

      if (splitDistantEewFocus && currentEewFocus != null) {
        final focusedEvents = focusedEewEvents;
        final targetZoom = mapState.smartMoveToEvents(
          focusedEvents,
          waveEvents: focusedEvents,
          padding: 0.8,
          minZoom: 4.5,
          maxZoom: desktop ? 8.0 : 7.0,
          screenOffset: _eventFocusOffset(),
          sourceTag:
              'policy-unified-eew-split-${_cameraEventTag(currentEewFocus)}',
          force: force,
          minInterval: const Duration(milliseconds: 900),
          continuousFollow: true,
        );
        waveGate.noteTargetZoom(
          targetZoom: targetZoom ?? double.infinity,
          minimumZoom: 4.5,
          now: now,
        );
        return;
      }

      final targetZoom = mapState.smartMoveToEvents(
        eewEvents,
        waveEvents: eewEvents,
        padding: 0.8,
        minZoom: 4.5,
        screenOffset: _eventFocusOffset(),
        sourceTag: 'policy-unified-eew',
        force: force,
        minInterval: const Duration(milliseconds: 900),
        continuousFollow: true,
      );
      waveGate.noteTargetZoom(
        targetZoom: targetZoom ?? double.infinity,
        minimumZoom: 4.5,
        now: now,
      );
      return;
    }

    _clearPreferredEventFocus();

    _eewWaveCameraFollowGate.syncEvents(const [], now);
    // Multiple networks share one extent, including when NIED has an estimate.
    final stationFocus = _stationDetectionFocus();
    if (stationFocus.isCombined &&
        _applyStationFocusPolicy(mapState, force: force, focus: stationFocus)) {
      _lastEpicenterFocus = null;
      _lastEpicenterSourceEventId = null;
      provider.setMobileCameraInfoFocus(null);
      return;
    }
    if (_applyNiedSourceFocusPolicy(mapState, force: force)) {
      provider.setMobileCameraInfoFocus(null);
      return;
    }

    if (_applyStationFocusPolicy(mapState, force: force, focus: stationFocus)) {
      provider.setMobileCameraInfoFocus(null);
      return;
    }

    if (desktop && _applyDesktopInfoFocusPolicy(provider, mapState, force)) {
      return;
    }

    final selectedInfo = provider.currentUnifiedEvent;
    final hasVolcanoInfo = provider.unifiedEvents.any((event) => event.isVolcanoEvent);
    final latestInfoIndex = !desktop && hasVolcanoInfo &&
            selectedInfo != null && !selectedInfo.isEew
        ? provider.currentUnifiedIndex
        : _latestUnifiedInfoIndex(provider.unifiedEvents);
    if (latestInfoIndex >= 0 && latestInfoIndex < mapEvents.length) {
      final infoFocusPoints = _unifiedInfoFocusPoints(
        provider,
        provider.unifiedEvents[latestInfoIndex],
        mapEvents[latestInfoIndex],
      );
      if (infoFocusPoints.isNotEmpty) {
        final isCencIrFocus =
            provider.unifiedEvents[latestInfoIndex].source == 'nowQuakeCencIr';
        final viewportPadding =
            isCencIrFocus &&
                    infoFocusPoints.length > 1
                ? cencIrViewportPadding(context)
                : null;
        provider.setMobileCameraInfoFocus(
          provider.unifiedEvents[latestInfoIndex],
        );
        mapState.smartMoveToPoints(
          infoFocusPoints,
          padding: 0.8,
          minZoom: 3.0,
          maxZoom: isCencIrFocus ? 12.0 : 8.0,
          viewportPadding: viewportPadding,
          focusAnchor: isCencIrFocus
              ? LatLng(
                  mapEvents[latestInfoIndex].latitude,
                  mapEvents[latestInfoIndex].longitude,
                )
              : null,
          screenOffset: _eventFocusOffset(),
          sourceTag: 'policy-info-area-${_cameraEventTag(mapEvents[latestInfoIndex])}',
          force: force,
          minInterval: const Duration(milliseconds: 1200),
        );
        return;
      }
    }

    if (mapEvents.isNotEmpty) {
      if (hasVolcanoInfo || _shouldSplitDistantUnifiedFocus(mapEvents)) {
        final focusInfo = _currentInfoFocusEvent(provider, mapEvents);
        if (focusInfo != null) {
          final focusIndex = mapEvents.indexOf(focusInfo);
          provider.setMobileCameraInfoFocus(provider.unifiedEvents[focusIndex]);
          mapState.smartMoveToEvents(
            [focusInfo],
            padding: 1.0,
            minZoom: 3.0,
            screenOffset: _eventFocusOffset(),
            sourceTag:
                'policy-unified-info-split-${_cameraEventTag(focusInfo)}',
            force: force,
            minInterval: const Duration(milliseconds: 1500),
          );
          return;
        }
      }

      provider.setMobileCameraInfoFocus(null);
      mapState.smartMoveToEvents(
        mapEvents,
        padding: 1.0,
        minZoom: 3.0,
        screenOffset: _eventFocusOffset(),
        sourceTag: 'policy-unified',
        force: force,
        minInterval: const Duration(milliseconds: 1500),
      );
      return;
    }

    provider.setMobileCameraInfoFocus(null);
    _lastEpicenterFocus = null;
    _lastEpicenterSourceEventId = null;

    final fallback = _defaultFallbackCenter();
    mapState.smartMoveToCenter(
      fallback,
      zoom: _defaultFallbackZoom(),
      sourceTag: 'policy-default',
      force: false,
      minInterval: const Duration(milliseconds: 1200),
    );
  }

  bool _applyNiedSourceFocusPolicy(
    MapStateProvider mapState, {
    required bool force,
  }) {
    if (!_showNiedEstimatedEpicenter) return false;
    final event = _latestNiedSourceEvent;
    final estimate = event?.estimate;
    if (event == null || estimate == null) return false;

    final epicenter = LatLng(estimate.latitude, estimate.longitude);
    if (!QuakeCalculator.isUsableMapCoordinate(
      epicenter.latitude,
      epicenter.longitude,
    )) {
      return false;
    }
    final sameEvent = event.eventId == _lastEpicenterSourceEventId;
    final movedFar =
        _lastEpicenterFocus == null ||
        _haversine(epicenter, _lastEpicenterFocus!) > 50;
    if (!force && sameEvent && !movedFar) return true;

    _lastEpicenterFocus = epicenter;
    _lastEpicenterSourceEventId = event.eventId;

    final supportPoints = _sourceFocusPoints(event, epicenter);
    if (supportPoints.isEmpty) return false;
    if (supportPoints.length >= 2) {
      mapState.smartMoveToPoints(
        supportPoints,
        padding: 0.75,
        minZoom: 4.5,
        maxZoom: 7.2,
        screenOffset: _eventFocusOffset(),
        sourceTag: 'policy-nied-source-${event.eventId}',
        force: force,
        minInterval: const Duration(milliseconds: 1500),
      );
    } else {
      mapState.smartMoveToCenter(
        epicenter,
        zoom: 6.5,
        screenOffset: _eventFocusOffset(),
        sourceTag: 'policy-nied-source-${event.eventId}',
        force: force,
        minInterval: const Duration(milliseconds: 1500),
      );
    }
    return true;
  }

  List<LatLng> _sourceFocusPoints(SeismicActiveEvent event, LatLng epicenter) {
    final points = <LatLng>[];
    if (QuakeCalculator.isUsableMapCoordinate(
      epicenter.latitude,
      epicenter.longitude,
    )) {
      points.add(epicenter);
    }
    for (final estimate in _niedPublishedSourceEstimates(event)) {
      if (!QuakeCalculator.isUsableMapCoordinate(
        estimate.latitude,
        estimate.longitude,
      )) {
        continue;
      }
      final point = LatLng(estimate.latitude, estimate.longitude);
      if (points.any((existing) => _haversine(existing, point) < 1.0)) {
        continue;
      }
      points.add(point);
    }
    final phases = _sourceStationPhaseClassifier.classify(event);
    final ordered = phases.stations.toList(growable: false)
      ..sort((a, b) {
        final ar = a.residualSeconds ?? double.infinity;
        final br = b.residualSeconds ?? double.infinity;
        final residualCmp = ar.compareTo(br);
        if (residualCmp != 0) return residualCmp;
        return a.stationCode.compareTo(b.stationCode);
      });
    for (final item in ordered.take(18)) {
      final coordinate = item.coordinate;
      if (!QuakeCalculator.isUsableMapCoordinate(
        coordinate.latitude,
        coordinate.longitude,
      )) {
        continue;
      }
      if (QuakeCalculator.isLikelyUninitializedCoordinate(
        coordinate.latitude,
        coordinate.longitude,
      )) {
        continue;
      }
      points.add(coordinate);
    }
    return points;
  }

  StationDetectionFocus _stationDetectionFocus() {
    return StationDetectionFocus({
      if (_niedLayerVisible) 'nied': _niedFocusPoints(),
      if (_kmaVisible) 'kma': _kmaFocusPoints(),
      if (_cwaVisible)
        'trem': _tremFocusStations().map((s) => s.coordinate).toList(),
      if (_pAlertEnabled) 'palert': [
        ..._pAlertDetectionGrid.centers,
        for (final event in _visiblePAlertSources())
          LatLng(event.estimate!.latitude, event.estimate!.longitude),
      ],
    });
  }

  bool _applyStationFocusPolicy(
    MapStateProvider mapState, {
    required bool force,
    required StationDetectionFocus focus,
  }) {
    if (focus.points.isEmpty) return false;
    mapState.smartMoveToPoints(
      focus.points,
      minZoom: focus.minZoom,
      maxZoom: 8.5,
      padding: _stationFocusPadding(focus.points.length),
      viewportPadding: focus.isCombined
          ? cencIrViewportPadding(context) ?? const EdgeInsets.all(50)
          : null,
      screenOffset: focus.isCombined ? Offset.zero : _stationFocusOffset(),
      sourceTag: focus.sourceTag,
      force: force,
      minInterval: const Duration(milliseconds: 2000),
    );
    return true;
  }

  String _cameraDatasetKey(QuakeProvider provider) {
    final unified = provider.unifiedEvents
        .map((e) => '${e.eventId}:${e.reportNumText}:${e.isEew ? 1 : 0}')
        .join('|');
    final niedSig = _lastNiedStationFocusSignature ?? '';
    final kmaSig = _lastKmaStationFocusSignature ?? '';
    final tremSig = _lastTremStationFocusSignature ?? '';
    final pAlertSig = _lastPAlertStationFocusSignature ?? '';
    final stationFocus = _stationDetectionFocus().signature;
    return 'u[$unified]-n[$niedSig]-k[$kmaSig]-c[$tremSig]-p[$pAlertSig]-s[$stationFocus]';
  }

  String? _historyCameraKey(QuakeMessage? event) {
    if (event == null) return null;
    return '${event.source.name}:${event.eventId}:'
        '${event.latitude.toStringAsFixed(5)}:'
        '${event.longitude.toStringAsFixed(5)}';
  }

  // ignore: unused_element
  List<NiedStation> _niedFocusStations() {
    // kanameishi: 鐩存帴鏌ュ凡鐢绘牸瀛? 鏍煎瓙涓績鐐瑰綋浣滆仛鐒︾洰鏍?
    if (_niedGridCellCenters.isEmpty) return const [];
    // 浠庢牸瀛愪腑蹇冪偣鎵惧埌鏈€杩戠殑鍘熺珯 (鐢ㄤ簬闇囧害璇勭骇鎺掑簭)
    final gridSet = _niedGridCellCenters.toSet();
    return _niedStations.where((s) => gridSet.contains(s.coordinate)).toList()
      ..sort((a, b) => b.level.compareTo(a.level));
  }

  // ignore: unused_element
  String _niedFocusGridSignature(List<NiedStation> stations) {
    final keys =
        stations
            .map((s) {
              final lat = s.coordinate.latitude.floor();
              final lng = s.coordinate.longitude.floor();
              final jma = JpShindoScale.jmaIndexFromKanameishiLevel(s.level);
              return '$lat,$lng:$jma';
            })
            .toSet()
            .toList()
          ..sort();
    return keys.join('|');
  }

  List<LatLng> _niedFocusPoints() {
    if (_niedGridCellCenters.isEmpty) return const [];
    final deduped = _niedGridCellCenters.toSet().toList()
      ..sort((a, b) {
        final latCompare = a.latitude.compareTo(b.latitude);
        if (latCompare != 0) return latCompare;
        return a.longitude.compareTo(b.longitude);
      });
    return deduped;
  }

  String _niedGridFocusSignature(List<LatLng> points) {
    final snapshotKeys =
        _latestDetectSnapshot.gridCells.entries
            .map((entry) => '${entry.key}:${entry.value.level}')
            .toList()
          ..sort();
    if (snapshotKeys.isNotEmpty) {
      return snapshotKeys.join('|');
    }
    final keys =
        points
            .map(
              (p) =>
                  '${p.latitude.toStringAsFixed(3)},${p.longitude.toStringAsFixed(3)}',
            )
            .toList()
          ..sort();
    return keys.join('|');
  }

  bool _requestKmaStationFocus({bool force = false}) {
    if (!mounted) return false;
    final provider = context.read<QuakeProvider>();
    if (provider.unifiedEvents.any((e) => e.isEew)) return false;

    final focusPoints = _kmaFocusPoints();
    if (focusPoints.isEmpty) {
      _lastKmaStationFocusSignature = null;
      _lastKmaStationFocusAt = null;
      return false;
    }

    final signature = _kmaGridFocusSignature(focusPoints);
    final now = DateTime.now();
    final lastAt = _lastKmaStationFocusAt;
    if (!force) {
      if (signature == _lastKmaStationFocusSignature) return false;
      if (lastAt != null &&
          now.difference(lastAt) < const Duration(seconds: 5)) {
        return false;
      }
    }

    _lastKmaStationFocusSignature = signature;
    _lastKmaStationFocusAt = now;
    _queueCameraPolicyRefresh(force: force);
    return true;
  }

  List<LatLng> _kmaFocusPoints() {
    // kanameishi: 鐩存帴鏌ュ凡鐢绘牸瀛?
    if (_kmaGridCellCenters.isEmpty) return const [];
    final deduped = _kmaGridCellCenters.toSet().toList()
      ..sort((a, b) {
        final latCompare = a.latitude.compareTo(b.latitude);
        if (latCompare != 0) return latCompare;
        return a.longitude.compareTo(b.longitude);
      });
    return deduped;
  }

  String _kmaGridFocusSignature(List<LatLng> points) {
    final keys =
        points
            .map(
              (p) =>
                  '${p.latitude.toStringAsFixed(3)},${p.longitude.toStringAsFixed(3)}',
            )
            .toSet()
            .toList()
          ..sort();
    return keys.join('|');
  }

  bool _requestTremStationFocus({bool force = false}) {
    if (!mounted) return false;
    final provider = context.read<QuakeProvider>();
    if (provider.unifiedEvents.any((e) => e.isEew)) return false;

    final focusStations = _tremFocusStations();
    if (focusStations.isEmpty) {
      _lastTremStationFocusSignature = null;
      _lastTremStationFocusAt = null;
      return false;
    }

    final signature = _tremFocusGridSignature(focusStations);
    final now = DateTime.now();
    final lastAt = _lastTremStationFocusAt;
    if (!force) {
      if (signature == _lastTremStationFocusSignature) return false;
      if (lastAt != null &&
          now.difference(lastAt) < const Duration(seconds: 5)) {
        return false;
      }
    }

    _lastTremStationFocusSignature = signature;
    _lastTremStationFocusAt = now;
    _queueCameraPolicyRefresh(force: force);
    return true;
  }

  List<CwaStation> _tremFocusStations() {
    final active = _cwaStations.where((s) => s.hasAlert).toList();
    if (active.isEmpty) return const [];

    final positive = active.where((s) => s.alertIntensity >= 1).toList();
    final candidates = positive.isNotEmpty ? positive : active;
    final maxIntensity = candidates
        .map((s) => s.alertIntensity)
        .reduce((a, b) => a > b ? a : b);

    final threshold = _stationFocusThreshold(maxIntensity.toDouble());
    final focused =
        candidates.where((s) => s.alertIntensity >= threshold).toList()
          ..sort((a, b) => b.alertIntensity.compareTo(a.alertIntensity));

    if (focused.length <= 1) return focused;
    return _localStationCluster(
      focused,
      (s) => s.coordinate,
      (s) => s.alertIntensity.toDouble(),
    );
  }

  String _tremFocusGridSignature(List<CwaStation> stations) {
    final keys =
        stations
            .map((s) {
              final lat = s.coordinate.latitude.floor();
              final lng = s.coordinate.longitude.floor();
              return '$lat,$lng:${_stationFocusLevel(s.alertIntensity.toDouble())}';
            })
            .toSet()
            .toList()
          ..sort();
    return keys.join('|');
  }

  bool _requestPAlertStationFocus({bool force = false}) {
    if (!mounted) return false;
    final provider = context.read<QuakeProvider>();
    if (provider.unifiedEvents.any((event) => event.isEew)) return false;

    if (_pAlertDetectionGrid.cells.isEmpty) {
      _lastPAlertStationFocusSignature = null;
      _lastPAlertStationFocusAt = null;
      return false;
    }

    final signature = _pAlertDetectionGrid.signature;
    final now = DateTime.now();
    final lastAt = _lastPAlertStationFocusAt;
    if (!force) {
      if (signature == _lastPAlertStationFocusSignature) return false;
      if (lastAt != null &&
          now.difference(lastAt) < const Duration(seconds: 5)) {
        return false;
      }
    }

    _lastPAlertStationFocusSignature = signature;
    _lastPAlertStationFocusAt = now;
    _queueCameraPolicyRefresh(force: force);
    return true;
  }

  void _updatePAlertDetectionGrid(Iterable<PAlertDetectionGridCell> cells) {
    final hadGrid = _pAlertDetectionGrid.cells.isNotEmpty;
    final previousSignature = _pAlertDetectionGrid.signature;
    _pAlertDetectionGrid.update(cells);
    if (previousSignature != _pAlertDetectionGrid.signature) {
      _notifyLayer(_pAlertLayerRevision);
    }
    if (_pAlertDetectionGrid.cells.isEmpty) {
      if (hadGrid) _onPAlertShakeExpired();
    } else {
      final force = _pendingPAlertStationFocus || !hadGrid;
      if (_requestPAlertStationFocus(force: force)) {
        _pendingPAlertStationFocus = false;
      }
    }
    _syncActivityTimers();
  }

  /// 閫氱敤娴嬬珯鍦扮悊鑱氱被锛屼笌 [_localNiedFocusCluster] 鍚岄€昏緫

  List<T> _localStationCluster<T>(
    List<T> stations,
    LatLng Function(T) coordOf,
    double Function(T) valueOf,
  ) {
    if (stations.length <= 1) return stations;
    final anchor = stations.first;
    final anchorVal = valueOf(anchor);
    final radiusKm = _stationFocusClusterRadiusKm(anchorVal);
    final cluster =
        stations
            .where((s) => _distanceKm(coordOf(anchor), coordOf(s)) <= radiusKm)
            .toList()
          ..sort((a, b) => valueOf(b).compareTo(valueOf(a)));

    if (cluster.length >= 2 || stations.length <= 2) return cluster;
    return stations.take(2).toList();
  }

  double _stationFocusThreshold(double maxValue) {
    if (maxValue >= 1.5) return maxValue - 1.5;
    if (maxValue >= 0) return 0.0;
    return maxValue - 0.6;
  }

  int _stationFocusLevel(double value) {
    if (value < 0) return -1;
    return value.floor();
  }

  double _stationFocusClusterRadiusKm(double anchorValue) {
    if (anchorValue >= 3.5) return 160.0;
    if (anchorValue >= 1.0) return 130.0;
    return 90.0;
  }

  double _stationFocusPadding(int count) {
    if (count <= 1) return 0.45;
    if (count <= 3) return 0.65;
    return 0.9;
  }

  double _distanceKm(LatLng a, LatLng b) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRadians(b.latitude - a.latitude);
    final dLng = _toRadians(b.longitude - a.longitude);
    final lat1 = _toRadians(a.latitude);
    final lat2 = _toRadians(b.latitude);
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  double _toRadians(double degree) => degree * math.pi / 180.0;

  Offset _stationFocusOffset() {
    final size = MediaQuery.sizeOf(context);
    return Offset(
      (size.width * 0.13).clamp(100.0, 240.0),
      -(size.height * 0.06).clamp(24.0, 70.0),
    );
  }

  Offset _eventFocusOffset() {
    return Offset.zero;
  }

  LatLng _defaultFallbackCenter() {
    final mapState = _mapStateProvider;
    if (mapState != null && mapState.preferredViewMode != null) {
      return mapState.defaultCenter;
    }
    if (_preferredViewCenter != null) return _preferredViewCenter!;
    final pos = LocationService().currentPosition;
    if (pos != null) {
      return LatLng(pos.latitude, pos.longitude);
    }
    return MapStateProvider.fallbackCenter;
  }

  double _defaultFallbackZoom() {
    final mapState = _mapStateProvider;
    if (mapState != null && mapState.preferredViewMode != null) {
      return mapState.defaultZoom;
    }
    return _preferredDefaultZoom ?? MapStateProvider.fallbackZoom;
  }

  void _onShakeExpired() {
    if (!mounted) return;
    // Shake end should never force a default-view reset.
    // The center button owns explicit default-view navigation.
    _queueCameraPolicyRefresh(force: false);
  }

  /// 杩炴帴鐘舵€佸洖璋冪粦瀹?  ///
  /// 灏嗗悇鐩戞祴鏈嶅姟鐨勭姸鎬佸彉鍖栧洖璋冪粦瀹氬埌 QuakeProvider銆?  /// 褰撴湇鍔¤繛鎺ユ垨鏂紑鏃讹紝鏇存柊鍏ㄥ眬鐘舵€併€?
  void _wireStatusCallbacks() {
    final provider = _quakeProvider;
    if (provider == null) return;
    void updateNiedStatus(bool connected) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        provider.updateSourceStatus(
          'NIED',
          connected ? SourceStatus.connected : SourceStatus.error,
        );
      });
    }

    _lmoniService.onStatusChanged = (connected) {
      if (_usesWhewsNied || _useYahooSource) return;
      updateNiedStatus(connected);
    };
    _yahooService.onStatusChanged = (connected) {
      if (_usesWhewsNied || !_useYahooSource) return;
      updateNiedStatus(connected);
    };
    _kmaService.onStatusChanged = (connected) {
      if (_usesWhewsKma) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          provider.updateSourceStatus(
            'KMA',
            connected ? SourceStatus.connected : SourceStatus.error,
          );
        }
      });
    };
    _cwaService.onStatusChanged = (connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          provider.updateSourceStatus(
            'TREM',
            connected ? SourceStatus.connected : SourceStatus.error,
          );
        }
      });
    };
    _seisjsService.onStatusChanged = (connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          provider.updateSourceStatus(
            'SeisJS',
            connected ? SourceStatus.connected : SourceStatus.error,
          );
        }
      });
    };
    _snetService.onStatusChanged = (connected) {
      if (_usesWhewsSnet) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          provider.updateSourceStatus(
            'S-net',
            connected ? SourceStatus.connected : SourceStatus.error,
          );
        }
      });
    };
    _pAlertService.onStatusChanged = (connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          provider.updateSourceStatus(
            'P-Alert',
            connected
                ? SourceStatus.connected
                : (_pAlertEnabled
                      ? SourceStatus.error
                      : SourceStatus.disconnected),
          );
        }
      });
    };
  }

  void _emitStationSummary() {
    if (widget.onStationDataChanged == null || !mounted) return;
    final summary = StationSummaryData();

    for (final s in _seisjsStations) {
      if (s.region.contains('六分街') || s.region.contains('新艾利都')) {
        summary.seisJsStation = s;
        break;
      }
    }
    summary.seisJsMaxStation = selectSeisJsCurrentMaxStation(_seisjsStations);

    double niedMax = -1;
    for (final s in _niedStations) {
      if (s.level >= 0 && s.level > niedMax) {
        niedMax = s.level.toDouble();
        summary.niedMaxStation = s;
      }
    }

    double treaMax = -1;
    for (final s in _cwaStations) {
      final intensity = s.currentIntensity;
      if (intensity > treaMax) {
        treaMax = intensity;
        summary.treaMaxStation = s;
      }
    }

    int kmaMaxLevel = -1;
    for (final s in _kmaStations) {
      if (s.holdLevel > kmaMaxLevel) {
        kmaMaxLevel = s.holdLevel;
        summary.kmaMaxStation = s;
      }
    }

    var pAlertMax = -1;
    for (final station in _pAlertStations) {
      final level = station.gridLevel;
      if (level > pAlertMax) {
        pAlertMax = level;
        summary.pAlertMaxStation = station;
      }
    }

    final snetStations = _usesWhewsSnet
        ? _whewsSnetStations
        : _snetService.stations;
    final snetTopStations = selectSnetSidebarTopStations(snetStations);
    if (snetTopStations.isNotEmpty) {
      summary.snetWindowEnd = DateTime.now();
      summary.snetWindowStart = summary.snetWindowEnd!.subtract(
        const Duration(minutes: 10),
      );
      summary.snetTopStations = snetTopStations;
    } else {
      summary.snetTopStations = const [];
      summary.snetWindowStart = null;
      summary.snetWindowEnd = null;
    }

    summary.niedDetect = NiedDetectSummary(
      stage: _latestDetectSnapshot.stage.name,
      weakCount: _latestDetectSnapshot.weakCount,
      detectedCount: _latestDetectSnapshot.detectedCount,
      strongCount: _latestDetectSnapshot.strongCount,
      maxShindo: _latestDetectSnapshot.maxShindo,
      visualGridCount: _latestDetectSnapshot.gridCells.length,
      detectedStations: _latestDetectSnapshot.detectedStations,
      visualAreas: _niedDetectVisualAreas(),
    );

    final lpgm = _latestLpgmSnapshot;
    if (lpgm != null) {
      summary.lpgmTime = lpgm.dataTime;
      summary.lpgmMaxSva = lpgm.maxSva;
      summary.lpgmMaxClass = lpgm.maxClass;
      summary.lpgmTopStations = lpgm.topStations
          .map(
            (s) => LpgmTopStation(
              code: s.code,
              sva: s.sva,
              lpgmClass: s.lpgmClass,
            ),
          )
          .toList(growable: false);
    } else {
      summary.lpgmTopStations = const [];
      summary.lpgmMaxSva = null;
      summary.lpgmMaxClass = null;
      summary.lpgmTime = null;
    }

    widget.onStationDataChanged!(summary);
  }

  List<NiedDetectVisualArea> _niedDetectVisualAreas() {
    final cells = _latestDetectSnapshot.gridCells;
    if (cells.isEmpty) return const [];

    final prefMax = <String, int>{};
    final activeStations = _niedStations
        .where((s) => s.isActive && s.level >= 0)
        .toList(growable: false);

    void updatePref(String pref, int jmaShindo) {
      final name = pref.trim();
      if (name.isEmpty) return;
      final current = prefMax[name] ?? -1;
      if (jmaShindo > current) prefMax[name] = jmaShindo;
    }

    for (final cell in cells.values) {
      final jmaShindo = JpShindoScale.jmaNumberFromKanameishiLevel(cell.level);
      final prefs = <String>{};
      for (final station in activeStations) {
        if (_stationInNiedVisualCell(station, cell.center)) {
          prefs.add(
            station.prefecture.trim().isNotEmpty
                ? station.prefecture
                : station.code,
          );
        }
      }
      if (prefs.isEmpty) {
        final nearest = _nearestNiedStationTo(cell.center);
        if (nearest != null) {
          prefs.add(
            nearest.prefecture.trim().isNotEmpty
                ? nearest.prefecture
                : nearest.code,
          );
        }
      }
      for (final pref in prefs) {
        updatePref(pref, jmaShindo);
      }
    }

    final areas =
        prefMax.entries
            .map(
              (entry) =>
                  NiedDetectVisualArea(name: entry.key, jmaShindo: entry.value),
            )
            .toList(growable: false)
          ..sort((a, b) {
            final shindoCompare = b.jmaShindo.compareTo(a.jmaShindo);
            if (shindoCompare != 0) return shindoCompare;
            return a.name.compareTo(b.name);
          });
    return areas;
  }

  bool _stationInNiedVisualCell(NiedStation station, LatLng center) {
    const halfCell = 0.500001;
    return (station.coordinate.latitude - center.latitude).abs() <= halfCell &&
        (station.coordinate.longitude - center.longitude).abs() <= halfCell;
  }

  NiedStation? _nearestNiedStationTo(LatLng point) {
    NiedStation? nearest;
    var nearestDistance = double.infinity;
    for (final station in _niedStations) {
      final distance = _haversine(point, station.coordinate);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = station;
      }
    }
    return nearest;
  }

  /// 鍒濆鍖?NIED 鏈嶅姟 (鍥剧墖鐩存帴鑾峰彇 鈫?瑙ｆ瀽 鈫?鍥惧眰)

  bool _niedBindingsInitialized = false;

  Future<void> _initNiedBindings() async {
    if (_niedBindingsInitialized) return;
    _niedBindingsInitialized = true;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    var niedSource = prefs.getString('nied_data_source') ?? 'lmoni';
    if (niedSource == 'whews' && !_whewsNiedEnabled) {
      niedSource = 'lmoni';
      unawaited(prefs.setString('nied_data_source', niedSource));
    }
    _niedSource = niedSource;
    _useYahooSource = niedSource == 'yahoo';
    QuakeMapView.niedSourceNotifier.value = niedSource;
    if (niedSource == 'lmoni' || niedSource == 'kmoni') {
      NiedMonitorService().configureEndpoint(niedSource);
    }
    final replayConfig = _niedReplayConfigFromPrefs(prefs);
    QuakeMapView.niedReplayNotifier.value = replayConfig;
    NiedMonitorService().configureReplay(replayConfig);
    _yahooService.configureReplay(replayConfig);
    final sensitivity = prefs.getInt('shake_sensitivity') ?? 2;
    QuakeMapView.shakeSensitivityNotifier.value = sensitivity;
    _shakeDetection.setSensitivity(sensitivity);
    _niedSourceEstimationDriver.setSensitivity(sensitivity);
    _kmaService.setSensitivity(sensitivity);
    _pAlertService.setSensitivity(sensitivity);
    _hideGridOnEew = prefs.getBool('hide_grid_on_eew') ?? false;
    UiRuntimeFlags.hideGridOnEewNotifier.value = _hideGridOnEew;

    QuakeMapView.niedSourceNotifier.addListener(_onNiedSourceChanged);
    QuakeMapView.niedLiveRestoreNotifier.addListener(
      _onNiedLiveRestoreRequested,
    );
    QuakeMapView.niedReplayNotifier.addListener(_onNiedReplayChanged);
    QuakeMapView.shakeSensitivityNotifier.addListener(
      _onShakeSensitivityChanged,
    );

    _lmoniStationSub = _lmoniService.stationStream.listen((stations) {
      if (!mounted || _useYahooSource || _usesWhewsNied) return;
      _acceptNiedStations(stations);
    });

    _yahooStationSub = _yahooService.stationStream.listen((stations) {
      if (!mounted || !_useYahooSource || _usesWhewsNied) return;
      _acceptNiedStations(stations);
    });

    _shakeDetection.onNotification = (title, body) {
      debugPrint('ShakeDetection: $title - $body');
    };
    _shakeDetection.onFocusWindow = () {
      debugPrint('ShakeDetection: focus window requested');
    };
    _shakeDetection.onShakeDetected = (shindo) {
      debugPrint('ShakeDetection: shindo $shindo detected');
      _onNiedShakeDetected(shindo);
    };
    _shakeDetection.onShakeExpired = () {
      debugPrint('ShakeDetection: shake expired');
      _onNiedShakeExpired();
    };
    _shakeDetection.onDetectionSnapshotChanged = (snapshot) {
      final oldStage = _latestDetectSnapshot.stage;
      _latestDetectSnapshot = snapshot;
      _syncActivityTimers();
      _emitStationSummary();
      _refreshNiedLayerIfNeeded(_niedStations);

      if (oldStage != snapshot.stage) {
        debugPrint(
          'NIED Detect: ${snapshot.stage.name} weak=${snapshot.weakCount} detected=${snapshot.detectedCount} strong=${snapshot.strongCount} max=${snapshot.maxShindo}',
        );
      }
      if (_showNiedEstimatedEpicenter) {
        setState(() {}); // trigger map redraw for epicenter marker
      }
    };
    _shakeDetection.onEventDetectionChanged = (detection) {
      _obsAutomationInputs.ingestEventDetection('nied', detection);
    };

    _kmaService.onShakeDetected = (maxShindo) {
      debugPrint('KMA ShakeDetection: shindo $maxShindo detected');
      _obsAutomationInputs.ingestLegacyNetworkDetection(
        network: 'kma',
        maxIntensity: maxShindo,
        observedAt: _kmaService.dataTimeNotifier.value ?? DateTime.now(),
      );
      _onKmaShakeDetected(maxShindo);
    };
    _kmaService.onShakeExpired = () {
      debugPrint('KMA ShakeDetection: shake expired');
      _obsAutomationInputs.endLegacyNetworkDetection(
        network: 'kma',
        observedAt: _kmaService.dataTimeNotifier.value ?? DateTime.now(),
      );
      _onKmaShakeExpired();
    };

    _cwaService.onShakeDetected = (maxShindo) {
      debugPrint('TREM ShakeDetection: shindo $maxShindo detected');
      _obsAutomationInputs.ingestLegacyNetworkDetection(
        network: 'trem',
        maxIntensity: maxShindo,
        observedAt: _cwaService.dataTimeNotifier.value ?? DateTime.now(),
      );
      _onTremShakeDetected(maxShindo);
    };
    _cwaService.onShakeExpired = () {
      debugPrint('TREM ShakeDetection: shake expired');
      _obsAutomationInputs.endLegacyNetworkDetection(
        network: 'trem',
        observedAt: _cwaService.dataTimeNotifier.value ?? DateTime.now(),
      );
      _onTremShakeExpired();
    };

    _pAlertService.onDetectionChanged = (snapshot) {
      if (!mounted || !_pAlertEnabled ||
          BackgroundService().isAndroidConnectionHostedByForegroundService) {
        return;
      }
      _updatePAlertDetectionGrid(
        snapshot.gridCells.values.map(PAlertDetectionGridCell.fromDetection),
      );
      _processPAlertSourceEstimation(_pAlertService.stations, {
        for (final entry in snapshot.detectedStations) entry.code,
      });
    };
    _pAlertService.onShakeDetected = (maxShindo) {
      debugPrint('P-Alert ShakeDetection: shindo $maxShindo detected');
      _obsAutomationInputs.ingestLegacyNetworkDetection(
        network: 'palert',
        maxIntensity: maxShindo,
        observedAt: _pAlertService.dataTimeNotifier.value ?? DateTime.now(),
      );
      _onPAlertShakeDetected(maxShindo);
    };
    _pAlertService.onShakeExpired = () {
      debugPrint('P-Alert ShakeDetection: shake expired');
      _obsAutomationInputs.endLegacyNetworkDetection(
        network: 'palert',
        observedAt: _pAlertService.dataTimeNotifier.value ?? DateTime.now(),
      );
      _onPAlertShakeExpired();
    };
  }

  void _onNiedSourceChanged() {
    var newSource = QuakeMapView.niedSourceNotifier.value;
    if (newSource == 'whews' && !_whewsNiedEnabled) {
      newSource = 'lmoni';
      QuakeMapView.niedSourceNotifier.value = newSource;
    }
    final useYahoo = newSource == 'yahoo';
    if (newSource == _niedSource) return;

    _resetNiedDetectionState(detachStations: true);
    NiedMonitorService().setPhysicalLayersEnabled(false);
    _lmoniService.stop();
    NiedMonitorService().stop();
    _yahooService.stop();
    _whewsNiedService.stop();
    _lastWhewsNiedDataTime = null;
    if (newSource == 'lmoni' || newSource == 'kmoni') {
      NiedMonitorService().configureEndpoint(newSource);
    }

    _niedSource = newSource;
    _useYahooSource = useYahoo;
    _niedStations = [];
    _whewsNiedStations = [];
    _lastWhewsNiedDataTime = null;
    _lastNiedLayerSignature = '';
    _syncNiedMonitorService();
    _notifyLayer(_niedLayerRevision);
    _emitStationSummary();
    debugPrint('NIED 数据源切换为: ${_niedSourceLabel(newSource)}');
  }

  void _onNiedLiveRestoreRequested() {
    if (!mounted) return;
    var source = QuakeMapView.niedSourceNotifier.value;
    if (source == 'whews' && !_whewsNiedEnabled) {
      source = 'lmoni';
      QuakeMapView.niedSourceNotifier.value = source;
    }

    _resetNiedDetectionState(detachStations: true);
    NiedMonitorService().setPhysicalLayersEnabled(false);
    NiedBackgroundWorker.instance.stop();
    _lmoniService.stop();
    NiedMonitorService().stop();
    _yahooService.stop();
    _whewsNiedService.stop();
    _lastWhewsNiedDataTime = null;
    _niedGridCellCenters.clear();
    _niedStations = const [];
    _whewsNiedStations = [];
    _lastNiedLayerSignature = '';
    Kotoho7JsReceiverBridge.clearSessions();
    unawaited(Kotoho7JsReceiverBridge.disposePersistentRuntime());
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.clear();
    imageCache.clearLiveImages();
    if (source == 'lmoni' || source == 'kmoni') {
      NiedMonitorService().configureEndpoint(source);
    }
    _niedSource = source;
    _useYahooSource = source == 'yahoo';
    _syncNiedMonitorService();
    _notifyLayer(_niedLayerRevision);
    _emitStationSummary();
    debugPrint(
      '[NIED] live source restored after GIF inject: ${_niedSourceLabel(source)}',
    );
  }

  String _niedSourceLabel(String source) {
    switch (source) {
      case 'yahoo':
        return 'Yahoo CDN JSON';
      case 'kmoni':
        return 'KMONI GIF';
      case 'whews':
        return 'WHEWS API';
      default:
        return 'Lmoni GIF';
    }
  }

  void _onNiedReplayChanged() {
    final config = QuakeMapView.niedReplayNotifier.value;
    NiedMonitorService().configureReplay(config);
    _yahooService.configureReplay(config);
    if (_niedSource == 'lmoni' || _niedSource == 'kmoni') {
      _lmoniService.stop();
      _lmoniService.start();
    }
    _resetNiedDetectionState(detachStations: false);
  }

  void _onShakeSensitivityChanged() {
    final sensitivity = QuakeMapView.shakeSensitivityNotifier.value;
    _shakeDetection.setSensitivity(sensitivity);
    _niedSourceEstimationDriver.setSensitivity(sensitivity);
    _kmaService.setSensitivity(sensitivity);
    _pAlertService.setSensitivity(sensitivity);
    BackgroundService().updatePAlertDetectionSensitivity(sensitivity);
  }

  NiedReplayConfig _niedReplayConfigFromPrefs(SharedPreferences prefs) {
    final enabled = prefs.getBool('nied_replay_enabled') ?? false;
    final startText = prefs.getString('nied_replay_start_jst') ?? '';
    final startJst = _parseNiedReplayTime(startText);
    final stepSeconds = prefs.getInt('nied_replay_step_seconds') ?? 1;
    if (!enabled || startJst == null) {
      return const NiedReplayConfig.disabled();
    }
    return NiedReplayConfig(
      enabled: true,
      startJst: startJst,
      stepSeconds: stepSeconds,
    );
  }

  DateTime? _parseNiedReplayTime(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final normalized = trimmed.replaceAll('/', '-').replaceFirst(' ', 'T');
    try {
      return DateTime.parse(normalized);
    } catch (_) {
      return null;
    }
  }

  /// 鍒濆鍖?S-net 鏈嶅姟
  ///
  /// 璁剧疆鏁版嵁鏇存柊鍥炶皟骞跺惎鍔ㄥ畾鏈熺洃娴嬨€?
  Future<void> _onWhewsNiedFrame(WhewsStationFrame frame) async {
    if (!mounted || !_usesWhewsNied || !_niedMonitorEnabled) return;
    final serial = ++_whewsNiedFrameSerial;
    final now = DateTime.now();
    if (!_matchesNiedCoordinates(_whewsNiedStations, frame.coordinates)) {
      if (frame.coordinates.isNotEmpty) {
        try {
          await loadWhewsNiedPrefectures();
        } catch (error) {
          debugPrint('WHEWS NIED prefecture map unavailable: ${error.runtimeType}');
        }
        if (!mounted || !_usesWhewsNied || !_niedMonitorEnabled ||
            serial != _whewsNiedFrameSerial) {
          return;
        }
      }
      _resetNiedDetectionState(detachStations: true);
      _lastWhewsNiedDataTime = null;
      _whewsNiedStations = buildWhewsNiedStations(frame.coordinates);
    }
    _applyWhewsNiedFrameGap(frame.dataTime);

    for (var index = 0; index < _whewsNiedStations.length; index++) {
      final raw = frame.values[index];
      final station = _whewsNiedStations[index];
      station
        ..lastUpdate = frame.dataTime
        ..lastDataTime = frame.dataTime
        ..lastReceivedAt = now;
      if (whewsNiedSnetValueIsValid(raw)) {
        station.updateFromContinuousShindo(raw);
      } else {
        station.updateFromContinuousShindo(null);
      }
      if (frame.pga.length == _whewsNiedStations.length) {
        station.updateGifObservation(
          NiedGifObservation(
            layer: NiedGifLayer.peakAcceleration,
            pga: frame.pga[index],
          ),
        );
      } else {
        station.clearGifObservation(
          NiedGifLayer.peakAcceleration,
          qualityFlag: 'whews_missing_or_invalid',
        );
      }
      if (frame.pgv.length == _whewsNiedStations.length) {
        station.updateGifObservation(
          NiedGifObservation(
            layer: NiedGifLayer.peakVelocity,
            pgv: frame.pgv[index],
          ),
        );
      } else {
        station.clearGifObservation(
          NiedGifLayer.peakVelocity,
          qualityFlag: 'whews_missing_or_invalid',
        );
      }
    }
    _acceptNiedStations(_whewsNiedStations);
  }

  void _applyWhewsNiedFrameGap(DateTime dataTime) {
    final previous = _lastWhewsNiedDataTime;
    _lastWhewsNiedDataTime = dataTime;
    if (previous == null) return;

    final diffMs = dataTime.difference(previous).inMilliseconds;
    if (diffMs <= 1000) return;

    var missingFrames = (diffMs / 1000).round() - 1;
    if (missingFrames <= 0) return;
    if (missingFrames > NiedStation.maxExpireSeconds) {
      missingFrames = NiedStation.maxExpireSeconds;
    }

    final noData = List<int>.filled(missingFrames, -1);
    final stale = diffMs > 10000;
    for (final station in _whewsNiedStations) {
      station.recentLevel.insertAll(0, noData);
      if (station.recentLevel.length > NiedStation.maxExpireSeconds) {
        station.recentLevel = station.recentLevel.sublist(
          0,
          NiedStation.maxExpireSeconds,
        );
      }
      if (stale) station.isActive = false;
    }
  }

  void _onWhewsSnetFrame(WhewsStationFrame frame) {
    if (!mounted || !_usesWhewsSnet || !_snetEnabled) return;
    if (!_matchesSnetCoordinates(_whewsSnetStations, frame.coordinates)) {
      _whewsSnetStations = List.generate(frame.coordinates.length, (index) {
        return SnetStation(
          code: 'WHEWS-SNET-${index + 1}',
          name: 'WHEWS-SNET-${index + 1}',
          coordinate: frame.coordinates[index],
          depth: 0,
          network: 'WHEWS',
          type: 'velocity',
        );
      });
    }
    for (var index = 0; index < _whewsSnetStations.length; index++) {
      final raw = frame.values[index];
      final valid = whewsNiedSnetValueIsValid(raw);
      final station = _whewsSnetStations[index];
      station
        ..shindo = valid ? raw : -3.0
        ..intensity = valid ? raw : null
        ..level = valid ? ShindoColorUtil.shindoToRawLevel(raw) : -1
        ..isActive = valid
        ..lastUpdate = frame.dataTime;
    }
    _ingestSnetAutomationStations(_whewsSnetStations);
    final signature = _snetLayerSignature(_whewsSnetStations);
    if (signature != _lastSnetLayerSignature) {
      _lastSnetLayerSignature = signature;
      _notifyLayer(_snetLayerRevision);
    }
    _emitStationSummary();
  }

  void _onWhewsKmaFrame(WhewsStationFrame frame) {
    if (!mounted || !_usesWhewsKma || !_kmaPewsEnabled) return;
    _kmaService.ingestExternalFrame(
      timestamp: frame.dataTime,
      coordinates: frame.coordinates,
      values: frame.values,
    );
  }

  bool _matchesNiedCoordinates(
    List<NiedStation> stations,
    List<LatLng> coordinates,
  ) {
    if (stations.length != coordinates.length) return false;
    for (var i = 0; i < stations.length; i++) {
      if (stations[i].coordinate != coordinates[i]) return false;
    }
    return true;
  }

  bool _matchesSnetCoordinates(
    List<SnetStation> stations,
    List<LatLng> coordinates,
  ) {
    if (stations.length != coordinates.length) return false;
    for (var i = 0; i < stations.length; i++) {
      if (stations[i].coordinate != coordinates[i]) return false;
    }
    return true;
  }

  Future<void> _initSnet() async {
    if (!_snetEnabled || _usesWhewsSnet) return;
    _snetService.onDataUpdated = (stations) {
      if (!mounted || !_snetEnabled || _usesWhewsSnet) return;
      _ingestSnetAutomationStations(stations);
      final signature = _snetLayerSignature(stations);
      if (signature == _lastSnetLayerSignature) return;
      _lastSnetLayerSignature = signature;
      _notifyLayer(_snetLayerRevision);
    };
    await _snetService.fetchLatestData();
    if (!mounted || !_snetEnabled || _usesWhewsSnet) {
      _snetService.stopMonitoring();
      return;
    }
    if (mounted) {
      final signature = _snetLayerSignature(_snetService.stations);
      if (signature != _lastSnetLayerSignature) {
        _lastSnetLayerSignature = signature;
        _notifyLayer(_snetLayerRevision);
      }
    }
    _startSnetMonitoring();
  }

  Future<void> _initLpgmMonitor() async {
    await _lpgmService.start(interval: _lpgmPollingInterval);
    // The service is stopped and restarted across app background transitions,
    // but its broadcast stream subscription should remain singleton-owned by
    // this map widget. Reusing the existing subscription prevents duplicate
    // station-summary emissions after repeated foreground/background cycles.
    if (!mounted || !_niedLpgmEnabled || _lpgmSnapshotSubscription != null) {
      return;
    }
    _lpgmSnapshotSubscription = _lpgmService.snapshotStream.listen((snapshot) {
      _latestLpgmSnapshot = snapshot;
      _emitStationSummary();
      if (snapshot.maxClass >= 1) {
        debugPrint(
          '[LPGM] maxClass=${snapshot.maxClass} maxSva=${snapshot.maxSva.toStringAsFixed(3)} top=${snapshot.topStations.map((e) => '${e.code}:${e.sva.toStringAsFixed(3)}').join(', ')}',
        );
      }
    });
  }

  Duration get _lpgmPollingInterval {
    if (kIsWeb) return const Duration(seconds: 1);
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS => const Duration(seconds: 15),
      _ => const Duration(seconds: 1),
    };
  }

  /// 启动 S-net 定期监测
  ///
  /// 姣?15 绉掕幏鍙栦竴娆℃渶鏂版暟鎹€?
  void _startSnetMonitoring() {
    _snetService.startMonitoring(intervalSeconds: 15);
  }

  /// 閲婃斁璧勬簮
  ///
  /// 鍙栨秷璁㈤槄骞跺仠姝㈡墍鏈夌洃娴嬫湇鍔°€?  @override
  @override
  void dispose() {
    EventAnimationClock.instance.blink2Fps.removeListener(_tickBlinkState);
    _blinkClockLease?.dispose();
    EventAnimationClock.instance.second1Fps.removeListener(_syncWaveAutoZoom);
    _waveAutoZoomClockLease?.dispose();
    _stopNiedWaveClock();
    _waveTick.dispose();
    _kmaStationSubscription?.cancel();
    _whewsNiedSubscription?.cancel();
    _whewsSnetSubscription?.cancel();
    _whewsKmaSubscription?.cancel();
    _foregroundStationSubscription?.cancel();
    _whewsNiedService.stateNotifier.removeListener(_onWhewsNiedStateChanged);
    _whewsSnetService.stateNotifier.removeListener(_onWhewsSnetStateChanged);
    _whewsKmaService.stateNotifier.removeListener(_onWhewsKmaStateChanged);
    _cwaStationSubscription?.cancel();
    _lmoniStationSub?.cancel();
    _yahooStationSub?.cancel();
    QuakeMapView.niedSourceNotifier.removeListener(_onNiedSourceChanged);
    QuakeMapView.niedLiveRestoreNotifier.removeListener(
      _onNiedLiveRestoreRequested,
    );
    QuakeMapView.niedReplayNotifier.removeListener(_onNiedReplayChanged);
    QuakeMapView.shakeSensitivityNotifier.removeListener(
      _onShakeSensitivityChanged,
    );
    QuakeMapView.fdsnStationLimitNotifier.removeListener(
      _onFdsnStationLimitChanged,
    );
    QuakeMapView.tremStationEnabledNotifier.removeListener(
      _onTremStationEnabledChanged,
    );
    QuakeMapView.displayShindo0Notifier.removeListener(
      _onDisplayShindo0Changed,
    );
    QuakeMapView.kmaIntensityHoldNotifier.removeListener(
      _onKmaIntensityHoldChanged,
    );
    QuakeMapView.wolfxSeisJsEnabledNotifier.removeListener(
      _onWolfxSeisJsEnabledChanged,
    );
    QuakeMapView.kmaPewsEnabledNotifier.removeListener(
      _onKmaPewsEnabledChanged,
    );
    QuakeMapView.kmaSourceNotifier.removeListener(_onKmaSourceChanged);
    QuakeMapView.pAlertEnabledNotifier.removeListener(_onPAlertEnabledChanged);
    QuakeMapView.niedMonitorEnabledNotifier.removeListener(
      _onNiedMonitorEnabledChanged,
    );
    QuakeMapView.niedLpgmEnabledNotifier.removeListener(
      _onNiedLpgmEnabledChanged,
    );
    QuakeMapView.snetEnabledNotifier.removeListener(_onSnetEnabledChanged);
    QuakeMapView.snetSourceNotifier.removeListener(_onSnetSourceChanged);
    QuakeMapView.fdsnSeedLinkEnabledNotifier.removeListener(
      _onFdsnSeedLinkEnabledChanged,
    );
    QuakeMapView.whewsNiedEnabledNotifier.removeListener(
      _onWhewsNiedEnabledChanged,
    );
    QuakeMapView.whewsSnetEnabledNotifier.removeListener(
      _onWhewsSnetEnabledChanged,
    );
    QuakeMapView.whewsKmaEnabledNotifier.removeListener(
      _onWhewsKmaEnabledChanged,
    );
    QuakeMapView.whewsApiTokenNotifier.removeListener(_onWhewsApiTokenChanged);
    LocationService().positionListenable.removeListener(_onUserLocationChanged);
    StationEventTracker.instance.currentNiedEvent.removeListener(
      _onNiedSourceEventChanged,
    );
    _niedSourceEstimationDriver.dispose();
    _pAlertSourceExpiry?.cancel();
    _pAlertSourceGeneration++;
    _pAlertSourceWorker.dispose();
    PAlertSourceState.events.value = const [];
    UiRuntimeFlags.hideGridOnEewNotifier.removeListener(_onHideGridOnEewChanged);
    _kmaService.disconnect();
    _cwaService.stop();
    _pAlertStationSubscription?.cancel();
    _pAlertService.stop();
    _seisjsSubscription?.cancel();
    _lpgmSnapshotSubscription?.cancel();
    _seisjsService.disconnect();
    _quakeProvider?.removeListener(_onQuakeProviderChanged);
    _quakeProvider?.typhoonListenable.removeListener(
      _onTyphoonListenableChanged,
    );
    _mapStateProvider?.removeListener(_onMapStateChanged);
    _preferredEventFocusTimer?.cancel();
    _preferredEventFocusTimer = null;
    _liveWeatherTileRefreshTimer?.cancel();
    _liveWeatherTileRefreshTimer = null;
    _stopFdsnServices();
    _fanRadarSubscription?.cancel();
    _precipitationSubscription?.cancel();
    _precipitationService.stop(clear: false);
    _fanRadarService.stop(clear: false);
    _jmaRadarSubscription?.cancel();
    _jmaRadarService.stop(clear: false);
    _fanSatelliteCloudSubscription?.cancel();
    _fanSatelliteCloudService.stop(clear: false);
    _shakeDetection.onEventDetectionChanged = null;
    _shakeDetection.reset(
      clearStationState: true,
      clearStationValues: true,
      detachStations: true,
      emitSnapshot: false,
    );
    _lmoniService.stop();
    NiedMonitorService().stop();
    _yahooService.stop();
    _snetService.dispose();
    _whewsNiedService.dispose();
    _whewsSnetService.dispose();
    _whewsKmaService.dispose();
    _lpgmService.stop();
    NiedBackgroundWorker.instance.stop();
    _volcanoMapService.onSitesUpdated = null;
    _volcanoMapService.stop();
    _niedLayerRevision.dispose();
    _kmaLayerRevision.dispose();
    _cwaLayerRevision.dispose();
    _pAlertLayerRevision.dispose();
    _seisJsLayerRevision.dispose();
    _snetLayerRevision.dispose();
    _earthScopeLayerRevision.dispose();
    _geofonLayerRevision.dispose();
    _liveWeatherTileRevision.dispose();
    _fanRadarLayerRevision.dispose();
    _precipitationLayerRevision.dispose();
    _jmaRadarLayerRevision.dispose();
    _fanSatelliteCloudLayerRevision.dispose();
    _blinkNotifier.dispose();
    _cancelStaggeredStartupTimers();
    _tileResetController.close();
    if (BackgroundService().isBackgroundHandlingEnabled) {
      BackgroundService().removeStateListener(_onBackgroundStateChanged);
    }
    BackgroundService().connectionHostingNotifier.removeListener(
      _onConnectionHostingChanged,
    );
    super.dispose();
  }

  /// 构建地图视图
  ///
  /// 鎸夊浘灞傞『搴忓彔鍔犳樉绀哄悇鏁版嵁灞傘€?  @override
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          color: const Color(0xFF152238),
          child: Selector<MapStateProvider, ({String tileKey, String tileUrl})>(
            selector: (context, mapState) => _baseTileState(mapState),
            builder: (context, tileState, child) {
              final mapboxBase =
                  tileState.tileKey == MapConfig.mapboxEewceDarkKey &&
                  MapConfig.hasMapboxAccessToken;
              return Stack(
                fit: StackFit.expand,
                children: [
                  ExcludeSemantics(
                    child: FlutterMap(
                      mapController: widget.mapController,
                      options: MapOptions(
                        backgroundColor: const Color(0xFF152238),
                        initialCenter: context
                            .read<MapStateProvider>()
                            .defaultCenter,
                        initialZoom: context
                            .read<MapStateProvider>()
                            .defaultZoom,
                        initialRotation: 0,
                        maxZoom: 18.0,
                        minZoom: 3.0,
                        // 某些 Android 设备在快速双指缩放时会产生包含 NaN
                        // 坐标的瞬时相机更新。约束会在 flutter_map 提交更新前
                        // 丢弃该帧，保留上一帧有效相机，避免瓦片投影异常。
                        cameraConstraint: const FiniteCameraConstraint(),
                        interactionOptions: InteractionOptions(
                          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                          cursorKeyboardRotationOptions:
                              CursorKeyboardRotationOptions.disabled(),
                          keyboardOptions: const KeyboardOptions(
                            enableQERotating: false,
                          ),
                        ),
                        onMapEvent: _handleMapEvent,
                        onTap: (tapPosition, latLng) {
                          // 0. 关闭防穿透：刚点击关闭按钮 350ms 内忽略地图穿透事件
                          if (_popupClosedAt != null &&
                              DateTime.now()
                                      .difference(_popupClosedAt!)
                                      .inMilliseconds <
                                  350) {
                            return;
                          }

                          // 气象预警图层点击命中测试
                          // 必须从 MapOptions.onTap 处理，避免 FlutterMap 手势竞技场抢占
                          final mapState = context.read<MapStateProvider>();
                          if (!mapState.isOverlayEnabled('weatherAlertLayer'))
                            return;
                          final alerts = ChinaWeatherAlertMapService
                              .alertItemsNotifier
                              .value;
                          if (alerts.isEmpty) return;
                          final camera = widget.mapController.camera;
                          final offset = tapPosition.relative ?? Offset.zero;

                          // 检查是否点击在当前打开的弹窗卡片矩形区域内
                          final cardRect =
                              WeatherAlertMapLayer.getPopupCardRect(
                                _selectedWeatherAlert,
                                camera,
                              );
                          if (cardRect != null &&
                              cardRect.inflate(4.0).contains(offset)) {
                            return; // 弹窗卡片内点击直接拦截
                          }

                          final hit = WeatherAlertMapLayer.hitTest(
                            alerts,
                            camera,
                            offset,
                            selectedAlert: _selectedWeatherAlert,
                          );
                          if (hit != null) {
                            if (hit.id != _selectedWeatherAlert?.id) {
                              setState(() => _selectedWeatherAlert = hit);
                            }
                          } else if (_selectedWeatherAlert != null) {
                            setState(() => _selectedWeatherAlert = null);
                          }
                        },
                      ),

                      children: [
                        if (tileState.tileKey == MapConfig.vectorBasemapKey)
                          const VectorBasemapLayer()
                        else
                          TileLayer(
                            key: ValueKey(tileState.tileKey),
                            urlTemplate: tileState.tileUrl,
                            subdomains: MapConfig.subdomainsByKey(
                              tileState.tileKey,
                            ),
                            userAgentPackageName: 'flutterrhythmquake/1.0',
                            tileProvider: _tileProvider,
                            tileDimension: mapboxBase ? 512 : 256,
                            zoomOffset: mapboxBase ? -1 : 0,
                            tms: MapConfig.isTmsTileKey(tileState.tileKey),
                            panBuffer: 1,
                            keepBuffer: 4,
                            evictErrorTileStrategy:
                                EvictErrorTileStrategy.dispose,
                            reset: _tileResetController.stream,
                            errorTileCallback: _handleTileLoadError,
                            tileDisplay: const TileDisplay.instantaneous(),
                          ),
                        if (tileState.tileKey == MapConfig.vectorBasemapKey)
                          const VectorBasemapLabels()
                        else
                          const SizedBox.shrink(),
                        Selector<
                          MapStateProvider,
                          ({
                            bool cloudLayer,
                            bool windLayer,
                            bool rainLayer,
                            bool cnContour,
                          })
                        >(
                          selector: (context, mapState) =>
                              _weatherOverlayState(mapState),
                          builder: (context, overlays, child) {
                            return ValueListenableBuilder<int>(
                              valueListenable: _liveWeatherTileRevision,
                              builder: (context, revision, child) {
                                return Stack(
                                  children: _buildOptionalOverlayLayers(
                                    overlays,
                                  ),
                                );
                              },
                            );
                          },
                        ),
                        Selector<MapStateProvider, bool>(
                          selector: (context, mapState) =>
                              mapState.isOverlayEnabled('jmaRadarLayer'),
                          builder: (context, visible, child) {
                            if (!visible) return const SizedBox.shrink();
                            return ValueListenableBuilder<int>(
                              valueListenable: _jmaRadarLayerRevision,
                              builder: (context, revision, child) {
                                return JmaRadarLayer(
                                  frame: _latestJmaRadarFrame,
                                  tileProvider: _tileProvider,
                                  reset: _tileResetController.stream,
                                  errorTileCallback: _handleTileLoadError,
                                );
                              },
                            );
                          },
                        ),
                        Selector<MapStateProvider, bool>(
                          selector: (context, mapState) =>
                              mapState.isOverlayEnabled('radarChinaLayer'),
                          builder: (context, visible, child) {
                            if (!visible) return const SizedBox.shrink();
                            return ValueListenableBuilder<int>(
                              valueListenable: _fanRadarLayerRevision,
                              builder: (context, revision, child) {
                                return FanRadarLayer(
                                  frame: _latestFanRadarFrame,
                                );
                              },
                            );
                          },
                        ),
                        Selector<MapStateProvider, bool>(
                          selector: (context, mapState) =>
                              mapState.isOverlayEnabled('precipitationChinaLayer'),
                          builder: (context, visible, child) {
                            if (!visible) return const SizedBox.shrink();
                            return ValueListenableBuilder<int>(
                              valueListenable: _precipitationLayerRevision,
                              builder: (context, revision, child) {
                                return FanRadarLayer(
                                  frame: _latestPrecipitationFrame,
                                );
                              },
                            );
                          },
                        ),
                        Selector<MapStateProvider, bool>(
                          selector: (context, mapState) =>
                              mapState.isOverlayEnabled('satelliteCloudLayer'),
                          builder: (context, visible, child) {
                            if (!visible) return const SizedBox.shrink();
                            return ValueListenableBuilder<int>(
                              valueListenable: _fanSatelliteCloudLayerRevision,
                              builder: (context, revision, child) {
                                return FanSatelliteCloudLayer(
                                  frame: _latestFanSatelliteCloudFrame,
                                );
                              },
                            );
                          },
                        ),
                        Selector<MapStateProvider, bool>(
                          selector: (context, mapState) =>
                              mapState.isOverlayEnabled('typhoonLayer'),
                          builder: (context, visible, child) {
                            if (!visible) return const SizedBox.shrink();
                            final provider = context.read<QuakeProvider>();
                            return ValueListenableBuilder<int>(
                              valueListenable: provider.typhoonListenable,
                              builder: (context, _, child) {
                                return TyphoonLayer(
                                  typhoons: provider.activeTyphoons,
                                );
                              },
                            );
                          },
                        ),
                        _buildWeatherStationLayer(),
                        if (widget.weatherOnly) const UserLocationLayer(),
                        if (!widget.weatherOnly) ...[
                          _buildUnifiedIntensityLayerStack(),
                          Selector<MapStateProvider, bool>(
                            selector: (context, mapState) =>
                                mapState.isOverlayEnabled('cnFault'),
                            builder: (context, visible, child) => visible
                                ? const ChinaFaultLayer()
                                : const SizedBox.shrink(),
                          ),
                          Selector<MapStateProvider, bool>(
                            selector: (context, mapState) =>
                                mapState.isOverlayEnabled('jpFault'),
                            builder: (context, visible, child) => visible
                                ? const JapanFaultLayer()
                                : const SizedBox.shrink(),
                          ),
                          _buildNiedStationLayer(),
                          _buildKmaStationLayer(),
                          _buildCwaStationLayer(),
                          _buildPAlertStationLayer(),
                          _buildSeisJsStationLayer(),
                          _buildSnetStationLayer(),
                          _buildFdsnStationLayer(
                            overlayKey: 'fdsnEarthScope',
                            revision: _earthScopeLayerRevision,
                            stations: () => _earthScopeStations,
                          ),
                          _buildFdsnStationLayer(
                            overlayKey: 'fdsnGeofon',
                            revision: _geofonLayerRevision,
                            stations: () => _geofonStations,
                          ),
                          Selector<QuakeProvider, CencIrData?>(
                            selector: (context, provider) =>
                                provider.cencIrData,
                            builder: (context, irData, child) {
                              if (irData == null)
                                return const SizedBox.shrink();
                              return CencIrLayer(data: irData);
                            },
                          ),
                          const UserLocationLayer(),
                          ListenableBuilder(
                            listenable: Listenable.merge([
                              PAlertSourceState.events,
                              UiRuntimeFlags.hideGridOnEewNotifier,
                              context.read<MapStateProvider>(),
                              context.read<QuakeProvider>(),
                            ]),
                            builder: (context, child) => MarkerLayer(markers: [
                              for (final event in _visiblePAlertSources())
                                Marker(
                                  width: 220, height: 56,
                                  point: LatLng(event.estimate!.latitude,
                                    event.estimate!.longitude),
                                  alignment: Alignment.center,
                                  child: _NiedHypMapCandidateMarkerVisual(
                                    label: event.estimate!.diagnostics['nied_dart_hyp_selected'] == true
                                        ? '当前' : '震源 ${event.estimate!.diagnostics['selected_detection_id'] ?? ''}',
                                    depthText: _niedHypMapSourceDetail(event.estimate!),
                                    color: const Color(0xFFFFA000),
                                    temporary: false,
                                    selected: event.estimate!.diagnostics['nied_dart_hyp_selected'] == true,
                                  ),
                                ),
                            ]),
                          ),
                          Selector<MapStateProvider, bool>(
                            selector: (context, mapState) =>
                                mapState.showEstimatedEpicenter,
                            builder: (context, visible, child) {
                              if (!visible) return const SizedBox.shrink();
                              return ValueListenableBuilder<
                                SeismicActiveEvent?
                              >(
                                valueListenable: StationEventTracker
                                    .instance
                                    .currentNiedEvent,
                                builder: (context, sourceEvent, child) {
                                  if (sourceEvent == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return Stack(
                                    children: [
                                      _buildSourceCandidateRegionLayer(
                                        sourceEvent,
                                      ),
                                      _buildNiedHypAlgorithmCandidateLayer(
                                        sourceEvent,
                                      ),
                                      _buildEstimatedEpicenterMarkers(
                                        sourceEvent,
                                      ),
                                      _buildSourceTriggerStationLayer(
                                        sourceEvent,
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                          Selector<QuakeProvider, List<UnifiedQuakeData>>(
                            selector: (context, provider) => provider
                                .unifiedEvents
                                .where((event) => event.isVolcanoEvent)
                                .toList(growable: false),
                            builder: (context, volcanoEvents, child) {
                              // API-pushed volcano events (WHEWS etc.) are not
                              // tied to the JMA volcano-site overlay switch.
                              if (volcanoEvents.isNotEmpty) {
                                return Stack(
                                  children: [
                                    VolcanoAshfallLayer(events: volcanoEvents),
                                    VolcanoLayer(
                                      sites: _volcanoSitesForEvents(
                                        volcanoEvents,
                                      ),
                                    ),
                                  ],
                                );
                              }
                              return Selector<MapStateProvider, bool>(
                                selector: (context, mapState) =>
                                    mapState.isOverlayEnabled('volcanoLayer'),
                                builder: (context, visible, child) {
                                  if (!visible) {
                                    return const SizedBox.shrink();
                                  }
                                  return VolcanoLayer(sites: _volcanoSites);
                                },
                              );
                            },
                          ),
                          ValueListenableBuilder<bool>(
                            valueListenable: _blinkNotifier,
                            builder: (context, blinkOn, child) {
                              return Selector<QuakeProvider, int>(
                                selector: (context, provider) =>
                                    _unifiedMapUiSignature(provider),
                                builder: (context, signature, child) {
                                  final provider = context
                                      .read<QuakeProvider>();
                                  final unifiedEvents = provider.unifiedEvents;
                                  final hasUnified = unifiedEvents.isNotEmpty;
                                  final cameraDatasetKey = _cameraDatasetKey(
                                    provider,
                                  );
                                  if (cameraDatasetKey !=
                                      _lastCameraDatasetKey) {
                                    _lastCameraDatasetKey = cameraDatasetKey;
                                    _queueCameraPolicyRefresh();
                                  }

                                  if (!hasUnified) {
                                    _lastEventPointFocusSignature = null;
                                    _lastEewTakeoverSignature = '';
                                    return const SizedBox.shrink();
                                  }

                                  final hasEew = unifiedEvents.any(
                                    (e) => e.isEew,
                                  );
                                  final eewTakeoverSignature =
                                      _eewTakeoverSignature(unifiedEvents);
                                  if (eewTakeoverSignature !=
                                      _lastEewTakeoverSignature) {
                                    final previousEewIds =
                                        _lastEewTakeoverSignature.isEmpty
                                        ? const <String>{}
                                        : _lastEewTakeoverSignature
                                              .split('|')
                                              .toSet();
                                    final hasNewEew = eewTakeoverSignature
                                        .split('|')
                                        .where((id) => id.isNotEmpty)
                                        .any(
                                          (id) => !previousEewIds.contains(id),
                                        );
                                    _lastEewTakeoverSignature =
                                        eewTakeoverSignature;
                                    if (hasNewEew) {
                                      _clearPreferredEventFocus();
                                      _queueCameraPolicyRefresh(force: true);
                                    }
                                  }
                                  final latestInfoIndex =
                                      _latestUnifiedInfoIndex(unifiedEvents);
                                  if (latestInfoIndex >= 0) {
                                    final latestInfo =
                                        unifiedEvents[latestInfoIndex];
                                    final signature =
                                        _unifiedInfoFocusSignature(
                                          latestInfo,
                                          cencIrData: provider.cencIrData,
                                        );
                                    if (signature !=
                                        _lastEventPointFocusSignature) {
                                      final mapEvents =
                                          provider.unifiedMapEvents;
                                      _lastEventPointFocusSignature = signature;
                                      if (hasEew &&
                                          latestInfoIndex < mapEvents.length) {
                                        final mapEv =
                                            mapEvents[latestInfoIndex];
                                        final areaFocusPoints =
                                            _unifiedInfoFocusPoints(
                                              provider,
                                              latestInfo,
                                              mapEv,
                                            );
                                        if (areaFocusPoints.isNotEmpty) {
                                          _requestEventPointFocus(
                                            mapEv,
                                            signature,
                                            unifiedInfo: latestInfo,
                                            force: true,
                                            hold: const Duration(
                                              milliseconds: 6500,
                                            ),
                                            focusPoints: areaFocusPoints,
                                          );
                                        } else if (QuakeCalculator.isUsableMapCoordinate(
                                          mapEv.latitude,
                                          mapEv.longitude,
                                        )) {
                                          _requestEventPointFocus(
                                            mapEv,
                                            signature,
                                            unifiedInfo: latestInfo,
                                            force: true,
                                            hold: const Duration(
                                              milliseconds: 6500,
                                            ),
                                          );
                                        } else {
                                          _queueCameraPolicyRefresh(
                                            force: true,
                                          );
                                        }
                                      } else if (latestInfoIndex <
                                          mapEvents.length) {
                                        final areaFocusPoints =
                                            _unifiedInfoFocusPoints(
                                              provider,
                                              latestInfo,
                                              mapEvents[latestInfoIndex],
                                            );
                                        if (areaFocusPoints.isNotEmpty) {
                                          _queueCameraPolicyRefresh(
                                            force: true,
                                          );
                                        }
                                      }
                                    }
                                  }

                                  final allLayers = <Widget>[];
                                  final userPos =
                                      LocationService().currentPosition;
                                  final userLatLng = userPos != null
                                      ? LatLng(
                                          userPos.latitude,
                                          userPos.longitude,
                                        )
                                      : null;
                                  if (hasUnified) {
                                    final mapEvents = provider.unifiedMapEvents;
                                    final layerCount = math.min(
                                      unifiedEvents.length,
                                      mapEvents.length,
                                    );
                                    for (int i = 0; i < layerCount; i++) {
                                      final u = unifiedEvents[i];
                                      if (u.isVolcanoEvent) continue;
                                      final qm = mapEvents[i];
                                      // CMT 事件由 FssnCmtLayer 绘制 beachball，跳过 QuakeWaveLayer
                                      if (qm.source ==
                                              QuakeSourceType.fssnCmt ||
                                          qm.source ==
                                              QuakeSourceType.cencCmt ||
                                          qm.source ==
                                              QuakeSourceType.usgsCmt ||
                                          qm.source == QuakeSourceType.jmaCmt ||
                                          qm.source ==
                                              QuakeSourceType.fnetCmt ||
                                          qm.source ==
                                              QuakeSourceType.hinetAquaCmt) {
                                        continue;
                                      }
                                      final layerKey = unifiedMapLayerKey(
                                        source: qm.source,
                                        eventId: u.eventId,
                                        isEew: u.isEew,
                                        index: i,
                                      );

                                      allLayers.add(
                                        QuakeWaveLayer(
                                          key: ValueKey('unified_$layerKey'),
                                          event: qm,
                                          showWaves: u.isEew,
                                          userPosition: userLatLng,
                                          colorMode: SWaveColorMode.intensity,
                                          blinkOn: u.isEew ? blinkOn : true,
                                          sWaveColor: _unifiedWaveColor(
                                            u.className,
                                          ),
                                        ),
                                      );
                                    }
                                  }

                                  // P/S wave circles now drawn at estimated epicenter

                                  return Stack(children: allLayers);
                                },
                              );
                            },
                          ),
                          Selector<QuakeProvider, int>(
                            selector: (context, provider) =>
                                _unifiedMapUiSignature(provider),
                            builder: (context, signature, child) {
                              final provider = context.read<QuakeProvider>();
                              final cmts = provider.unifiedMapEvents
                                  .where(
                                    (e) =>
                                        e.source == QuakeSourceType.fssnCmt ||
                                        e.source == QuakeSourceType.cencCmt ||
                                        e.source == QuakeSourceType.usgsCmt ||
                                        e.source == QuakeSourceType.jmaCmt ||
                                        e.source == QuakeSourceType.fnetCmt ||
                                        e.source ==
                                            QuakeSourceType.hinetAquaCmt,
                                  )
                                  .map(FssnCmtMarker.fromQuakeMessage)
                                  .toList();
                              return FssnCmtLayer(markers: cmts);
                            },
                          ),
                          Selector<MapStateProvider, QuakeMessage?>(
                            selector: (context, mapProvider) =>
                                mapProvider.selectedHistoryEvent,
                            builder: (context, selected, child) {
                              return HistoryMarkerLayer(event: selected);
                            },
                          ),
                          Selector<
                            QuakeProvider,
                            ({
                              TsunamiMessage? jma,
                              TsunamiMessage? nmefc,
                              TsunamiMessage? ptwc,
                              TsunamiMessage? ntwc,
                              TsunamiMessage? incois,
                            })
                          >(
                            selector: (context, provider) => (
                              jma: provider.jmaTsunami,
                              nmefc: provider.nmefcTsunami,
                              ptwc: provider.ptwcTsunami,
                              ntwc: provider.ntwcTsunami,
                              incois: provider.incoisTsunami,
                            ),
                            builder: (context, tsunamiData, child) {
                              final jma = tsunamiData.jma;
                              final nmefc = tsunamiData.nmefc;
                              final ptwc = tsunamiData.ptwc;
                              final ntwc = tsunamiData.ntwc;
                              final incois = tsunamiData.incois;
                              if (jma == null &&
                                  nmefc == null &&
                                  ptwc == null &&
                                  ntwc == null &&
                                  incois == null) {
                                return const SizedBox.shrink();
                              }
                              return Stack(
                                children: [
                                  if (jma != null)
                                    TsunamiLayer(
                                      key: const ValueKey('tsunami_jma'),
                                      tsunami: jma,
                                      source: 'jp',
                                    ),
                                  if (nmefc != null)
                                    NmefcTsunamiLayer(
                                      key: const ValueKey('tsunami_nmefc'),
                                      tsunami: nmefc,
                                    ),
                                  if (ptwc != null)
                                    InternationalTsunamiLayer(
                                      key: const ValueKey('tsunami_ptwc'),
                                      tsunami: ptwc,
                                    ),
                                  if (ntwc != null)
                                    InternationalTsunamiLayer(
                                      key: const ValueKey('tsunami_ntwc'),
                                      tsunami: ntwc,
                                    ),
                                  if (incois != null)
                                    InternationalTsunamiLayer(
                                      key: const ValueKey('tsunami_incois'),
                                      tsunami: incois,
                                    ),
                                ],
                              );
                            },
                          ),
                        ],
                        _buildWeatherAlertMapLayer(),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // NIED 鍥炴斁鐘舵€佸彔鍔犲眰
        if (!widget.weatherOnly) _buildReplayOverlay(),
      ],
    );
  }

  /// NIED 鍥炴斁鐘舵€佸彔鍔犲眰锛堝彸涓嬭灏忓瓧锛?

  Widget _buildReplayOverlay() {
    final config = QuakeMapView.niedReplayNotifier.value;
    if (!config.enabled) return const SizedBox.shrink();

    return Positioned(
      bottom: 6,
      right: 6,
      child: ValueListenableBuilder<DateTime?>(
        valueListenable: NiedMonitorService().replayFrameTime,
        builder: (context, frameTime, _) {
          final stepText = '${config.stepSeconds}s/步';
          final timeText = frameTime != null
              ? '${frameTime.year}-${_pad2(frameTime.month)}-${_pad2(frameTime.day)} '
                    '${_pad2(frameTime.hour)}:${_pad2(frameTime.minute)}:${_pad2(frameTime.second)}'
              : '加载中...';

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '回放  $timeText  $stepText',
              style: const TextStyle(
                color: Color(0xCC66C8FF),
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        },
      ),
    );
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  Widget _buildNiedHypAlgorithmCandidateLayer(SeismicActiveEvent event) {
    final estimates = _niedPublishedSourceEstimates(event)
        .where((estimate) => estimate.method == 'nied_dart_hyp_v1')
        .where(
          (estimate) => QuakeCalculator.isUsableMapCoordinate(
            estimate.latitude,
            estimate.longitude,
          ),
        )
        .toList(growable: false);
    if (estimates.isEmpty) {
      return const SizedBox.shrink();
    }
    return RepaintBoundary(
      child: Semantics(
        label: '震源算法有效震源',
        child: MarkerLayer(
          markers: [
            for (final estimate in estimates)
              Marker(
                width: 220,
                height: 56,
                point: LatLng(estimate.latitude, estimate.longitude),
                alignment: Alignment.center,
                child: _NiedHypMapCandidateMarkerVisual(
                  label: estimate.diagnostics['nied_dart_hyp_selected'] == true
                      ? '当前'
                      : '震源 ${estimate.diagnostics['selected_detection_id'] ?? ''}',
                  depthText: _niedHypMapSourceDetail(estimate),
                  color: const Color(0xFFFFA000),
                  temporary: false,
                  selected:
                      estimate.diagnostics['nied_dart_hyp_selected'] == true,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _niedHypMapSourceDetail(SourceEstimate estimate) {
    final currentErrorLevel = _metadataDouble(
      estimate.diagnostics['error_level'],
    );
    var detail = estimate.depthKm == null
        ? '--'
        : '${estimate.depthKm!.round()}km';
    if (currentErrorLevel != null) {
      detail += ' 误差${currentErrorLevel.toStringAsFixed(2)}';
    }
    return detail;
  }

  /// 推算震中标记：实时 P/S 波圈与中心点。

  Widget _buildEstimatedEpicenterMarkers(SeismicActiveEvent event) {
    final estimates = _niedPublishedSourceEstimates(event);
    if (estimates.isEmpty) return const SizedBox.shrink();
    return Stack(
      children: [
        for (final estimate in estimates)
          _buildEstimatedEpicenterMarker(event, estimate),
      ],
    );
  }

  Widget _buildEstimatedEpicenterMarker(
    SeismicActiveEvent event,
    SourceEstimate estimate,
  ) {
    if (!QuakeCalculator.isUsableMapCoordinate(
      estimate.latitude,
      estimate.longitude,
    )) {
      return const SizedBox.shrink();
    }
    final point = LatLng(estimate.latitude, estimate.longitude);
    return Builder(
      builder: (context) {
        final maxShindo = _sourceEstimateDisplayMaxShindo(event, estimate);
        final accent = _estimateAccentColor(maxShindo);
        final waveColor = _niedDetectionThresholdColor(maxShindo);

        return ValueListenableBuilder<int>(
          valueListenable: _waveTick,
          builder: (context, tick, child) {
            final circles = <CircleMarker<Object>>[];
            final radii = niedWaveRadiiFromEstimate(
              estimate,
              algorithmElapsedSeconds: _displayNiedWaveElapsedForEstimate(
                estimate,
              ),
            );
            var pRadiusKm = radii.pRadiusKm;
            var sRadiusKm = radii.sRadiusKm;

            if (pRadiusKm >= 999000) pRadiusKm = 0;
            if (sRadiusKm >= 999000) sRadiusKm = 0;

            final pRadiusM = pRadiusKm > 0 ? pRadiusKm * 1000 : 0.0;
            final sRadiusM = sRadiusKm > 0 ? sRadiusKm * 1000 : 0.0;

            if (pRadiusM > 0) {
              circles.add(
                CircleMarker(
                  point: point,
                  radius: pRadiusM,
                  useRadiusInMeter: true,
                  color: Colors.transparent,
                  borderColor: waveColor.withValues(alpha: 0.58),
                  borderStrokeWidth: 1.6,
                ),
              );
            }
            if (sRadiusM > 0) {
              circles.add(
                CircleMarker(
                  point: point,
                  radius: sRadiusM,
                  useRadiusInMeter: true,
                  color: Colors.transparent,
                  borderColor: waveColor.withValues(alpha: 0.92),
                  borderStrokeWidth: 2.2,
                ),
              );
            }

            return Stack(
              children: [
                CircleLayer(circles: circles),
                MarkerLayer(
                  markers: [
                    Marker(
                      width: 156,
                      height: 28,
                      point: point,
                      alignment: Alignment.center,
                      child: _EstimatedEpicenterMarkerVisual(
                        color: accent,
                        maxShindo: maxShindo,
                        depthKm: estimate.depthKm,
                        sourceError: _metadataDouble(
                          estimate.diagnostics['best_source_error'],
                        ),
                        visible: estimate.method != 'nied_dart_hyp_v1',
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  double? _displayNiedWaveElapsedForEstimate(SourceEstimate estimate) {
    if (QuakeMapView.niedReplayNotifier.value.enabled) return null;
    if (identical(estimate, _latestNiedSourceEstimate)) {
      return _displayNiedWaveElapsedSeconds;
    }
    final elapsed = _metadataDouble(estimate.diagnostics['wave_elapsed_s']);
    if (elapsed == null) return null;
    return elapsed + _niedWaveElapsedClock.elapsedMilliseconds / 1000.0;
  }

  static Color _estimateAccentColor(int maxShindo) {
    return _niedDetectionThresholdColor(maxShindo);
  }

  static int _sourceEstimateDisplayMaxShindo(
    SeismicActiveEvent event,
    SourceEstimate estimate,
  ) {
    if (estimate.method == 'nied_gif_kotoho7_js_receiver_v1') {
      return _metadataDouble(
            estimate.diagnostics['js_map_max_shindo_class'],
          )?.floor() ??
          -1;
    }
    return event.maxShindo;
  }

  static Color _niedDetectionThresholdColor(int maxShindo) {
    if (maxShindo >= 6) return const Color(0xFFFF0000);
    if (maxShindo >= 4) return const Color(0xFFFFFF00);
    return const Color(0xFF39F29A);
  }

  static Color _unifiedWaveColor(String className) {
    switch (className) {
      case 'purple':
        return const Color(0xFFAF00AF);
      case 'dark-red':
      case 'red':
        return const Color(0xFFFF0000);
      case 'dark-orange':
      case 'orange':
        return const Color(0xFFFFA500);
      case 'yellow':
        return const Color(0xFFFFFF1F);
      case 'green':
        return const Color(0xFF4FF77F);
      case 'blue':
      case 'sky-blue':
        return const Color(0xFF1F8FFF);
      case 'dark-gray':
      case 'gray':
      default:
        return const Color(0xFFB7B7B7);
    }
  }

  Widget _buildSourceCandidateRegionLayer(SeismicActiveEvent? event) {
    final candidateRegion = event?.metadata['candidate_region'];
    if (candidateRegion is! Map) return const SizedBox.shrink();
    if (candidateRegion['production_coordinate_switch_allowed'] == true) {
      return const SizedBox.shrink();
    }
    final latitude = _metadataDouble(candidateRegion['latitude']);
    final longitude = _metadataDouble(candidateRegion['longitude']);
    if (latitude == null || longitude == null) {
      return const SizedBox.shrink();
    }
    if (!QuakeCalculator.isUsableMapCoordinate(latitude, longitude)) {
      return const SizedBox.shrink();
    }

    final status = candidateRegion['status']?.toString() ?? 'pending';
    final color = _candidateRegionColor(status);
    final point = LatLng(latitude, longitude);
    final radiusKm = math.max(
      30.0,
      _metadataDouble(candidateRegion['cluster_distance_km']) ?? 0.0,
    );

    return Stack(
      children: [
        CircleLayer(
          circles: [
            CircleMarker(
              point: point,
              radius: radiusKm * 1000,
              useRadiusInMeter: true,
              color: color.withValues(alpha: 0.10),
              borderColor: color.withValues(alpha: 0.75),
              borderStrokeWidth: 2.0,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              width: 108,
              height: 32,
              point: point,
              alignment: Alignment.topCenter,
              child: IgnorePointer(
                child: Transform.translate(
                  offset: const Offset(0, -30),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xCC111820),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: color.withValues(alpha: 0.70),
                        width: 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        _candidateRegionMapLabel(status),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static Color _candidateRegionColor(String status) => switch (status) {
    'confirmedDelayed' || 'confirmedImmediate' => const Color(0xFF72F5B2),
    'expired' => const Color(0xFF9AA4B2),
    _ => const Color(0xFFFFC857),
  };

  static String _candidateRegionMapLabel(String status) => switch (status) {
    'confirmedDelayed' => '\u5019\u9009\u5ef6\u8fdf\u786e\u8ba4',
    'confirmedImmediate' => '\u5019\u9009\u5df2\u786e\u8ba4',
    'expired' => '\u5019\u9009\u5df2\u8fc7\u671f',
    _ => '\u5019\u9009\u533a\u57df',
  };

  static double? _metadataDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  double _haversine(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final sinDLat = math.sin(dLat / 2);
    final sinDLng = math.sin(dLng / 2);
    final h =
        sinDLat * sinDLat +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            sinDLng *
            sinDLng;
    return 2 * r * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  Widget _buildSourceTriggerStationLayer(SeismicActiveEvent event) {
    final phases = _sourceStationPhaseClassifier.classify(event);
    if (phases.stations.isEmpty) return const SizedBox.shrink();

    final radius = _sourcePhaseStationRadius(context);
    final borderWidth = _sourcePhaseStationBorderWidth(context);
    return Semantics(
      label:
          '推算触发 ${phases.stations.length}站 '
          'P ${phases.count(EstimatedStationPhase.p)} '
          'S ${phases.count(EstimatedStationPhase.s)} '
          'O ${phases.count(EstimatedStationPhase.other)}',
      child: StationDotPainterLayer(
        dots: [
          for (final item in phases.stations)
            StationDot(
              coordinate: item.coordinate,
              color: _sourcePhaseColor(item.phase),
              radius: radius,
              fillOpacity: 0.08,
              borderOpacity: 0.92,
              borderWidth: borderWidth,
            ),
        ],
      ),
    );
  }

  static double _sourcePhaseStationRadius(BuildContext context) {
    final zoom = MapCamera.maybeOf(context)?.zoom ?? 4.0;
    final dotSize = (0.9 + (zoom - 3) * 0.95).clamp(0.9, 7.5).toDouble();
    return dotSize / 2;
  }

  static double _sourcePhaseStationBorderWidth(BuildContext context) {
    final zoom = MapCamera.maybeOf(context)?.zoom ?? 4.0;
    final overview = ((zoom - 3.2) / 3.8).clamp(0.0, 1.0).toDouble();
    return (0.45 + overview * 0.70).clamp(0.45, 1.15).toDouble();
  }

  static Color _sourcePhaseColor(EstimatedStationPhase phase) =>
      switch (phase) {
        EstimatedStationPhase.p => const Color(0xFF35B8FF),
        EstimatedStationPhase.s => const Color(0xFF39F29A),
        EstimatedStationPhase.other => const Color(0xFFFFC857),
      };

  List<Widget> _buildOptionalOverlayLayers(
    ({bool cloudLayer, bool windLayer, bool rainLayer, bool cnContour})
    overlays,
  ) {
    final layers = <Widget>[];
    void addOverlay(String key, bool enabled) {
      if (!enabled) return;
      layers.add(
        TileLayer(
          key: ValueKey(_overlayTileLayerKey(key)),
          urlTemplate: _overlayTileUrlTemplate(key),
          userAgentPackageName: 'flutterrhythmquake/1.0',
          tileProvider: _tileProvider,
          panBuffer: 1,
          keepBuffer: 3,
          evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
          reset: _tileResetController.stream,
          errorTileCallback: _handleTileLoadError,
          tileDisplay: const TileDisplay.instantaneous(),
        ),
      );
    }

    addOverlay('cloudLayer', overlays.cloudLayer);
    addOverlay('windLayer', overlays.windLayer);
    addOverlay('rainLayer', overlays.rainLayer);
    addOverlay('cnContour', overlays.cnContour);
    return layers;
  }

  String _overlayTileUrlTemplate(String key) {
    final template = MapConfig.overlayUrlByKey(key);
    if (!_liveWeatherTileKeys.contains(key)) return template;
    final separator = template.contains('?') ? '&' : '?';
    return '$template${separator}rq_live=$_liveWeatherTileVersion';
  }

  String _overlayTileLayerKey(String key) {
    if (!_liveWeatherTileKeys.contains(key)) return key;
    return '$key:$_liveWeatherTileVersion';
  }
}

class _NiedHypMapCandidateMarkerVisual extends StatelessWidget {
  const _NiedHypMapCandidateMarkerVisual({
    required this.label,
    required this.depthText,
    required this.color,
    required this.temporary,
    required this.selected,
  });

  final String label;
  final String depthText;
  final Color color;
  final bool temporary;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final zoom = MapCamera.maybeOf(context)?.zoom ?? 4.0;
    final diameter = (5.0 + (zoom - 3.0) * 1.2).clamp(6.0, 13.0).toDouble();
    final cross = Icon(
      Icons.close,
      size: selected || temporary ? diameter + 8 : diameter + 5,
      color: color,
      shadows: const [
        Shadow(color: Colors.black, blurRadius: 4),
        Shadow(color: Colors.black, blurRadius: 2),
      ],
    );
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (selected || temporary)
            Container(
              width: diameter + 13,
              height: diameter + 13,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 1.4),
              ),
            ),
          cross,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Text(
              '$label $depthText',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.visible,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                height: 1,
                shadows: const [
                  Shadow(color: Colors.black, blurRadius: 4),
                  Shadow(color: Colors.black, blurRadius: 2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EstimatedEpicenterMarkerVisual extends StatelessWidget {
  final Color color;
  final int maxShindo;
  final double? depthKm;
  final double? sourceError;
  final bool visible;

  const _EstimatedEpicenterMarkerVisual({
    required this.color,
    required this.maxShindo,
    required this.depthKm,
    required this.sourceError,
    this.visible = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final zoom = MapCamera.maybeOf(context)?.zoom ?? 4.0;
    final dotDiameter = (1.8 + (zoom - 3) * 1.35).clamp(3.0, 10.0).toDouble();
    const markerWidth = 156.0;
    final textLeft = markerWidth / 2 + dotDiameter / 2 + 4.0;
    final errorText = sourceError == null
        ? 'JS误差--'
        : 'JS误差${sourceError!.toStringAsFixed(2)}';
    final depthText = depthKm == null ? '--' : '${depthKm!.round()}km';
    final shindoText = maxShindo < 0 ? '--' : '$maxShindo';

    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: dotDiameter,
            height: dotDiameter,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          Positioned(
            left: textLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  shindoText,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    height: 1,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.95),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '$depthText  $errorText',
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.95),
                        blurRadius: 4,
                      ),
                      Shadow(
                        color: color.withValues(alpha: 0.65),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
