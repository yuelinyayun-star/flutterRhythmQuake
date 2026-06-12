// 鍦伴渿鍦板浘瑙嗗浘缁勪欢
//
// 鏈粍浠舵槸搴旂敤鐨勬牳蹇冨湴鍥捐鍥撅紝闆嗘垚浜嗗绉嶅湴闇囩洃娴嬫暟鎹浘灞傘€?// 閲囩敤 FlutterMap 浣滀负搴曞眰鍦板浘寮曟搸锛屾敮鎸佸绉嶆暟鎹簮鍙犲姞鏄剧ず銆?//
// ## 涓昏鍔熻兘
//
// - **搴曞浘鏄剧ず**: 浣跨敤 Petal 涓婚鐡︾墖浣滀负搴曞浘
// - **NIED 寮洪渿鏁版嵁**: 鏄剧ず鏃ユ湰 K-NET/KiK-net 娴嬬珯瀹炴椂闇囧害
// - **KMA 娴嬬珯鏁版嵁**: 鏄剧ず闊╁浗姘旇薄鍘呮祴绔欏疄鏃堕渿搴?// - **S-net 娴峰簳鏁版嵁**: 鏄剧ず鏃ユ湰娴峰簳鍦伴渿瑙傛祴缃戞暟鎹?// - **CENC 浠櫒鐑堝害**: 鏄剧ず涓浗鍦伴渿鍙扮綉涓績浠櫒鐑堝害鍒嗗竷
// - **鍦伴渿娉㈠姩鐢?*: 鏄剧ず棰勮鍦伴渿娉紶鎾姩鐢?// - **鍘嗗彶鍦伴渿鏍囪**: 鏄剧ず閫変腑鐨勫巻鍙插湴闇囦綅缃?//
// ## 鏁版嵁娴?//
// 1. 鍚勭洃娴嬫湇鍔＄嫭绔嬭繍琛岋紝閫氳繃鍥炶皟鏇存柊鐘舵€?// 2. 鐘舵€佸彉鍖栬Е鍙?UI 閲嶇粯
// 3. 鏂伴璀︿簨浠惰Е鍙戝湴鍥捐嚜鍔ㄥ畾浣?//
// ## 鍥惧眰鍙犲姞椤哄簭
//
// 1. 搴曞浘鐡︾墖灞?// 2. NIED 闇囧害灞?// 3. KMA 闇囧害灞?// 4. S-net 娴峰簳灞?// 5. CENC 浠櫒鐑堝害灞?// 6. 鍦伴渿娉㈠姩鐢诲眰
// 7. 鍘嗗彶鍦伴渿鏍囪灞?
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wave_layer.dart';
import 'user_location_layer.dart';
import 'nied_intensity_layer.dart';
import 'kma_intensity_layer.dart';
import 'cwa_station_layer.dart';
import 'cenc_ir_layer.dart';
import 'history_marker_layer.dart';
import 'snet_layer.dart';
import 'volcano_layer.dart';
import 'seisjs_layer.dart';
import 'fdsn_station_layer.dart';
import 'fssn_cmt_layer.dart';
import 'intensity_fill_layer.dart';
import 'tsunami_layer.dart';
import 'nmefc_tsunami_layer.dart';
import 'allow_any_cert_tile_provider.dart';
import 'map_config.dart';
import 'package:provider/provider.dart';
import '../../providers/quake_provider.dart';
import '../../providers/map_state_provider.dart';
import '../../services/sources/lmoni_image_service.dart';
import '../../services/sources/lpgm_monitor_service.dart';
import '../../services/sources/nied_monitor.dart';
import '../../services/sources/nied_yahoo_service.dart';
import '../../services/sources/jp_shindo_scale.dart';
import '../../services/sources/jma_volcano_map_service.dart';
import '../../services/sources/shake_detection_service.dart';
import '../../services/sources/kma_monitor.dart';
import '../../services/sources/cwa_station_service.dart';
import '../../services/sources/seisjs_service.dart';
import '../../services/sources/fdsn_station_service.dart';
import '../../services/sources/fdsn_motion_service.dart';
import '../../services/sources/snet_service.dart';
import '../../services/location_service.dart';
import '../../core/calculator.dart';
import '../../core/travel_time_service.dart';
import '../../services/sound_effect_service.dart';
import '../../models/source_status.dart';
import '../../models/quake_message.dart';
import '../../models/jma_volcano_site.dart';
import '../ui/station_dashboard.dart';

/// 鍦伴渿鍦板浘瑙嗗浘缁勪欢
///
/// 搴旂敤鐨勬牳蹇冨湴鍥捐鍥撅紝璐熻矗闆嗘垚鍜屾樉绀烘墍鏈夊湴闇囩洃娴嬫暟鎹浘灞傘€?
class QuakeMapView extends StatefulWidget {
  /// 鍦板浘鎺у埗鍣?  ///
  /// 鐢ㄤ簬鎺у埗鍦板浘鐨勭Щ鍔ㄣ€佺缉鏀剧瓑鎿嶄綔銆?  /// 鐢辩埗缁勪欢浼犲叆锛屾敮鎸佸閮ㄦ帶鍒躲€?
  final MapController mapController;

  final void Function(StationSummaryData)? onStationDataChanged;

  /// NIED 鏁版嵁婧愬垏鎹㈤€氱煡鍣?

  static final ValueNotifier<String> niedSourceNotifier = ValueNotifier(
    'lmoni',
  );
  static final ValueNotifier<NiedReplayConfig> niedReplayNotifier =
      ValueNotifier(const NiedReplayConfig.disabled());

  const QuakeMapView({
    super.key,
    required this.mapController,
    this.onStationDataChanged,
  });

  @override
  State<QuakeMapView> createState() => _QuakeMapViewState();
}

/// 鍦伴渿鍦板浘瑙嗗浘鐘舵€佺被
///
/// 绠＄悊鍚勭洃娴嬫湇鍔＄殑鐢熷懡鍛ㄦ湡鍜屾暟鎹闃呫€?
class _QuakeMapViewState extends State<QuakeMapView> {
  /// NIED 寮洪渿鐩戞祴鏈嶅姟瀹炰緥 (lmoni 鍥剧墖瑙ｆ瀽绠楁硶)
  final LmoniImageService _lmoniService = LmoniImageService();

  /// NIED Yahoo CDN 鏈嶅姟瀹炰緥 (JSON 鏁版嵁婧?

  final NiedYahooService _yahooService = NiedYahooService();

  /// 鎽囨檭妫€娴嬫湇鍔″疄渚?

  final ShakeDetectionService _shakeDetection = ShakeDetectionService();

  /// 鏄惁浣跨敤 Yahoo CDN 鏁版嵁婧?

  bool _useYahooSource = false;
  String _niedSource = 'lmoni';

  /// KMA 鐩戞祴鏈嶅姟瀹炰緥

  final KmaMonitorService _kmaService = KmaMonitorService();

  /// S-net 娴峰簳瑙傛祴鏈嶅姟瀹炰緥

  final SnetService _snetService = SnetService();
  final LpgmMonitorService _lpgmService = LpgmMonitorService();

  /// KMA 鍥惧眰鏄惁鍙

  final bool _kmaVisible = true;

  /// S-net 鍥惧眰鏄惁鍙

  final bool _snetVisible = true;

  /// KMA 娴嬬珯鏁版嵁璁㈤槄
  StreamSubscription? _kmaStationSubscription;

  /// NIED lmoni 娴嬬珯鏁版嵁璁㈤槄
  StreamSubscription? _lmoniStationSub;
  StreamSubscription? _yahooStationSub;

  /// NIED 娴嬬珯鍒楄〃 (浠?lmoni 鍥剧墖瑙ｆ瀽)

  List<NiedStation> _niedStations = [];
  final List<LatLng> _niedGridCellCenters = []; // kanameishi: 宸茬敾鏍煎瓙涓績鐐?
  final List<LatLng> _kmaGridCellCenters = []; // kanameishi: KMA 宸茬敾鏍煎瓙涓績鐐?
  /// KMA 娴嬬珯鍒楄〃
  List<KmaStation> _kmaStations = [];

  /// CWA 娴嬬珯鏈嶅姟瀹炰緥

  final CwaStationService _cwaService = CwaStationService();

  /// CWA 娴嬬珯鏁版嵁璁㈤槄
  StreamSubscription? _cwaStationSubscription;

  /// CWA 娴嬬珯鍒楄〃

  List<CwaStation> _cwaStations = [];

  /// CWA 鍥惧眰鏄惁鍙

  final bool _cwaVisible = true;

  /// SeisJS 娴嬬珯鏈嶅姟瀹炰緥

  final SeisJsService _seisjsService = SeisJsService();

  /// SeisJS 娴嬬珯鏁版嵁璁㈤槄
  StreamSubscription? _seisjsSubscription;
  StreamSubscription? _lpgmSnapshotSubscription;

  /// SeisJS 娴嬬珯鍒楄〃

  List<SeisJsStation> _seisjsStations = [];

  /// SeisJS 鍥惧眰鏄惁鍙

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

  /// NIED 鍥惧眰鏄惁鍙

  final bool _niedLayerVisible = true;

  /// EEW 鏃舵槸鍚﹂殣钘忚娴嬬綉鏍?

  bool _hideGridOnEew = false;

  /// EEW 鏍囪闂儊鐘舵€?

  bool _blinkOn = true;
  Timer? _blinkTimer;
  Timer? _waveAutoZoomTimer;
  LatLng? _preferredViewCenter;
  double? _preferredDefaultZoom;

  /// 涓婃棰勮浜嬩欢鏁伴噺 (鐢ㄤ簬妫€娴嬫柊浜嬩欢)
  int _lastWarningCount = 0;

  /// 涓婃淇℃伅浜嬩欢鏁伴噺 (鐢ㄤ簬妫€娴嬫柊浜嬩欢)
  int _lastInfoEventCount = 0;

  /// 涓婃缁熶竴浜嬩欢鍒楄〃绗竴涓殑 eventId (鐢ㄤ簬妫€娴?first 鍙樺寲)
  String? _lastFirstEventId;
  LpgmSnapshot? _latestLpgmSnapshot;
  final JmaVolcanoMapService _volcanoMapService = JmaVolcanoMapService();
  List<JmaVolcanoSite> _volcanoSites = [];
  ShakeDetectionSnapshot _latestDetectSnapshot = const ShakeDetectionSnapshot(
    stage: ShakeDetectStage.idle,
    weakCount: 0,
    detectedCount: 0,
    strongCount: 0,
    maxShindo: -1,
  );
  String? _lastNiedStationFocusSignature;
  DateTime? _lastNiedStationFocusAt;
  DateTime? _niedDetectFirstAt;
  LatLng? _niedDetectEpicenter;
  Timer? _niedWaveTimer;
  final ValueNotifier<int> _waveTick = ValueNotifier<int>(0);
  final Map<String, double> _niedStationDistances =
      {}; // stationCode -> distance_km from epicenter
  LatLng? _nearestStationToHypo;
  LatLng? _lastEpicenterFocus;
  ShakeDetectStage _lastEpicenterStage = ShakeDetectStage.idle;
  String? _lastKmaStationFocusSignature;
  DateTime? _lastKmaStationFocusAt;
  String? _lastTremStationFocusSignature;
  DateTime? _lastTremStationFocusAt;
  String? _lastEventPointFocusSignature;
  String _lastCameraDatasetKey = '';
  bool _cameraPolicyQueued = false;
  bool _cameraPolicyForce = false;
  QuakeMessage? _preferredEventFocus;
  DateTime? _preferredEventFocusUntil;
  String? _preferredStationFocusSource;
  List<LatLng>? _preferredStationFocusPoints;
  bool _pendingNiedStationFocus = false;
  bool _pendingKmaStationFocus = false;
  bool _pendingTremStationFocus = false;

  bool get _showNiedEstimatedEpicenter =>
      context.read<MapStateProvider>().showEstimatedEpicenter;

  /// 涓存椂淇℃伅浜嬩欢瀹氫綅璁℃椂鍣?

  Timer? _tempInfoLocationTimer;

  /// 鍒濆鍖栫姸鎬?  ///
  /// 鍚姩鎵€鏈夌洃娴嬫湇鍔″苟璁㈤槄鏁版嵁娴併€?  @override
  void initState() {
    super.initState();
    _wireStatusCallbacks();
    _loadCameraDefaults();
    _initNiedFromImage();
    _initSnet();
    _initLpgmMonitor();
    _volcanoSites = _volcanoMapService.sites;
    _volcanoMapService.onSitesUpdated = (items) {
      if (!mounted) return;
      setState(() => _volcanoSites = items);
    };
    _volcanoMapService.start();
    _kmaService.connect();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _blinkOn = !_blinkOn);
    });
    _waveAutoZoomTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _syncWaveAutoZoom();
    });
    _kmaStationSubscription = _kmaService.stationStream.listen((stations) {
      if (mounted) setState(() => _kmaStations = stations);
      if (_pendingKmaStationFocus) {
        _pendingKmaStationFocus = false;
        _requestKmaStationFocus(force: true);
      }
      _emitStationSummary();
    });
    _cwaService.start();
    _cwaStationSubscription = _cwaService.stationStream.listen((stations) {
      if (mounted) setState(() => _cwaStations = stations);
      if (_pendingTremStationFocus) {
        _pendingTremStationFocus = false;
        _requestTremStationFocus(force: true);
      }
      _emitStationSummary();
    });
    _seisjsService.connect();
    _seisjsSubscription = _seisjsService.stationStream.listen((stations) {
      if (mounted) setState(() => _seisjsStations = stations);
      _emitStationSummary();
    });
    _earthScopeStationService.start();
    _earthScopeStationSubscription = _earthScopeStationService.stationStream
        .listen((stations) {
          if (mounted) setState(() => _earthScopeStations = stations);
        });
    _geofonStationService.start();
    _geofonStationSubscription = _geofonStationService.stationStream.listen((
      stations,
    ) {
      if (mounted) setState(() => _geofonStations = stations);
    });
    _fdsnMotionService.connect();
    _fdsnMotionSubscription = _fdsnMotionService.sampleStream.listen(
      _handleFdsnMotionSample,
    );
    _bindAllEventsExpiredCallback();
  }

  void _handleFdsnMotionSample(FdsnMotionSample sample) {
    if (!mounted) return;

    List<FdsnStation> updateStations(List<FdsnStation> stations) {
      var changed = false;
      final updated = stations
          .map((station) {
            if (station.code != sample.code) return station;
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

    setState(() {
      _earthScopeStations = updateStations(_earthScopeStations);
      _geofonStations = updateStations(_geofonStations);
    });
  }

  /// 缁戝畾鎵€鏈変簨浠惰繃鏈熷洖璋?

  void _bindAllEventsExpiredCallback() {
    final provider = context.read<QuakeProvider>();
    provider.onAllEventsExpired = () {
      if (!mounted) return;
      // Align with kanameishi: expire triggers a normal auto-policy refresh.
      // It is not a forced default reset; manual lock still wins.
      _queueCameraPolicyRefresh(force: false);
    };
  }

  /// 澶勭悊鏂伴璀︿簨浠?  ///
  /// 鍗曢璀︼細瀹氫綅鍒伴渿涓紝zoom=6.0
  /// 澶氶璀︼細璁＄畻杈圭晫妗嗭紝鑷姩缂╂斁鏄剧ず鍏ㄩ儴
  void _handleNewWarnings(List<ActiveWarning> warnings) {
    if (warnings.isEmpty) return;
    _queueCameraPolicyRefresh(force: true);
  }

  void _syncWaveAutoZoom() {
    if (!mounted) return;
    final mapState = context.read<MapStateProvider>();
    if (!mapState.canAutoFollow) return;
    _queueCameraPolicyRefresh();
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

  String _mapLayerKey(QuakeMessage event, String? eventId, int index) {
    final id = eventId == null || eventId.isEmpty ? 'noid' : eventId;
    final report = event.reportNumber?.toString() ?? 'r0';
    return '${id}_${event.source.name}_${report}_$index';
  }

  /// kanameishi: 鏍规嵁浜嬩欢鏉ユ簮鑾峰彇瀵瑰簲鐨勮娴嬬綉缃戞牸鐐?  /// JMA EEW 鈫?NIED 缃戞牸, KMA EEW 鈫?KMA 缃戞牸
  /// 瑙傛祴缃戞縺娲绘椂鐢ㄧ綉鏍肩偣浠ｆ浛 S 娉㈠～鍏呮墿灞曡鍙?
  List<LatLng> _cameraGridPoints(List<QuakeMessage> eewEvents) {
    final points = <LatLng>[];
    for (final e in eewEvents) {
      final source = e.source;
      if (source == QuakeSourceType.jma_fan) {
        if (_niedGridCellCenters.isNotEmpty) {
          points.addAll(_niedGridCellCenters);
        }
      } else if (source == QuakeSourceType.kma_eew_fan) {
        if (_kmaGridCellCenters.isNotEmpty) {
          points.addAll(_kmaGridCellCenters);
        }
      }
    }
    return points;
  }

  /// 涓存椂鏄剧ず淇℃伅浜嬩欢浣嶇疆
  ///
  /// 褰撴湁棰勮鏃舵敹鍒颁俊鎭簨浠讹紝璺宠浆鍒颁俊鎭簨浠朵綅缃?绉掑悗鍥炲埌棰勮浣嶇疆
  void _showTempInfoLocation(QuakeMessage event) {
    _tempInfoLocationTimer?.cancel();
    _requestEventPointFocus(
      event,
      'temp-info:${event.eventId}',
      force: true,
      hold: const Duration(seconds: 7),
    );

    _tempInfoLocationTimer = Timer(const Duration(seconds: 7), () {
      if (!mounted) return;
      _preferredEventFocus = null;
      _preferredEventFocusUntil = null;
      final provider = context.read<QuakeProvider>();
      if (provider.activeWarnings.isNotEmpty) {
        _handleNewWarnings(provider.activeWarnings);
      } else {
        _queueCameraPolicyRefresh(force: true);
      }
    });
  }

  void _onNiedShakeDetected(int shindo) {
    if (!mounted) return;
    SoundEffectService().playShindo(shindo);
    if (!_requestNiedStationFocus(force: true)) {
      _pendingNiedStationFocus = true;
    }
  }

  void _onNiedShakeExpired() {
    if (!mounted) return;
    _lastNiedStationFocusSignature = null;
    _lastNiedStationFocusAt = null;
    _pendingNiedStationFocus = false;
    if (_preferredStationFocusSource == 'nied') {
      _preferredStationFocusSource = null;
      _preferredStationFocusPoints = null;
    }
    // 寮哄埗鎺ㄩ€?idle 蹇収 鈫?渚ф爮娓呴浂 + 闇囦腑鏍囪娑堝け
    _latestDetectSnapshot = const ShakeDetectionSnapshot(
      stage: ShakeDetectStage.idle,
      weakCount: 0,
      detectedCount: 0,
      strongCount: 0,
      maxShindo: -1,
    );
    _emitStationSummary();
    _onShakeExpired();
  }

  void _onKmaShakeExpired() {
    if (!mounted) return;
    _lastKmaStationFocusSignature = null;
    _lastKmaStationFocusAt = null;
    _pendingKmaStationFocus = false;
    if (_preferredStationFocusSource == 'kma') {
      _preferredStationFocusSource = null;
      _preferredStationFocusPoints = null;
    }
    _onShakeExpired();
  }

  void _onTremShakeExpired() {
    if (!mounted) return;
    _lastTremStationFocusSignature = null;
    _lastTremStationFocusAt = null;
    _pendingTremStationFocus = false;
    if (_preferredStationFocusSource == 'trem') {
      _preferredStationFocusSource = null;
      _preferredStationFocusPoints = null;
    }
    _onShakeExpired();
  }

  void _requestEventPointFocus(
    QuakeMessage event,
    String signature, {
    bool force = false,
    Duration hold = const Duration(seconds: 4),
  }) {
    if (!mounted) return;
    if (!force && signature == _lastEventPointFocusSignature) return;
    _lastEventPointFocusSignature = signature;
    _preferredEventFocus = event;
    _preferredEventFocusUntil = DateTime.now().add(hold);
    _queueCameraPolicyRefresh(force: force);
  }

  void _onKmaShakeDetected(int maxMmi) {
    if (!mounted) return;
    SoundEffectService().playShindo(maxMmi);
    if (!_requestKmaStationFocus(force: true)) {
      _pendingKmaStationFocus = true;
    }
  }

  void _onTremShakeDetected(int alertIntensity) {
    if (!mounted) return;
    SoundEffectService().playShindo(alertIntensity);
    if (!_requestTremStationFocus(force: true)) {
      _pendingTremStationFocus = true;
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
    _preferStationFocusSource('nied', force, focusPoints);
    _queueCameraPolicyRefresh(force: force);
    return true;
  }

  void _queueCameraPolicyRefresh({bool force = false}) {
    if (!mounted) return;
    _cameraPolicyForce = _cameraPolicyForce || force;
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

  void _preferStationFocusSource(
    String source,
    bool force,
    List<LatLng> points,
  ) {
    if (!force) return;
    _preferredStationFocusSource = source;
    _preferredStationFocusPoints = List<LatLng>.unmodifiable(points);
  }

  void _applyCameraPolicy({bool force = false}) {
    if (!mounted) return;
    final mapState = context.read<MapStateProvider>();
    if (!mapState.canAutoFollow) return;
    final provider = context.read<QuakeProvider>();
    final now = DateTime.now();

    if (provider.unifiedEvents.isNotEmpty) {
      final mapEvents = provider.unifiedMapEvents;
      final eewEvents = _unifiedEewMapEvents(provider);
      final focusEvents = eewEvents.isNotEmpty ? eewEvents : mapEvents;
      final gridPoints = _cameraGridPoints(eewEvents);
      mapState.smartMoveToEvents(
        focusEvents,
        waveEvents: eewEvents,
        gridPoints: gridPoints,
        padding: eewEvents.isNotEmpty ? 0.8 : 1.0,
        minZoom: eewEvents.isNotEmpty ? 4.5 : 3.0,
        screenOffset: _eventFocusOffset(),
        sourceTag: eewEvents.isNotEmpty
            ? 'policy-unified-eew'
            : 'policy-unified',
        force: force,
        minInterval: const Duration(milliseconds: 1500),
      );
      return;
    }

    if (_applyStationFocusPolicy(mapState, force: force)) {
      return;
    }

    if (_preferredEventFocus != null &&
        _preferredEventFocusUntil != null &&
        now.isBefore(_preferredEventFocusUntil!)) {
      final focus = _preferredEventFocus!;
      final focusPt = LatLng(focus.latitude, focus.longitude);
      final eewEvents = _unifiedEewMapEvents(provider);
      if (eewEvents.isNotEmpty) {
        final allPoints = <LatLng>[focusPt];
        final gridPoints = _cameraGridPoints(eewEvents);
        if (gridPoints.isNotEmpty) {
          allPoints.addAll(gridPoints);
          mapState.smartMoveToPoints(
            allPoints,
            padding: 0.8,
            minZoom: 4.5,
            screenOffset: _eventFocusOffset(),
            sourceTag: 'policy-event-focus',
            force: true,
            minInterval: const Duration(milliseconds: 1200),
          );
        } else {
          mapState.smartMoveToEvents(
            [focus],
            waveEvents: eewEvents,
            padding: 0.8,
            minZoom: 4.5,
            screenOffset: _eventFocusOffset(),
            sourceTag: 'policy-event-focus',
            force: true,
            minInterval: const Duration(milliseconds: 1200),
          );
        }
      } else {
        mapState.smartMoveToPoints(
          [focusPt],
          padding: 1.2,
          maxZoom: 7.0,
          screenOffset: _eventFocusOffset(),
          sourceTag: 'policy-event-focus',
          force: true,
          minInterval: const Duration(milliseconds: 1200),
        );
      }
      return;
    }

    _preferredEventFocus = null;
    _preferredEventFocusUntil = null;

    final epi = _latestDetectSnapshot;
    if (_showNiedEstimatedEpicenter &&
        epi.hypoLat != null &&
        epi.hypoLng != null &&
        epi.stage != ShakeDetectStage.idle) {
      final epiPt = LatLng(epi.hypoLat!, epi.hypoLng!);
      if (_lastEpicenterFocus == null ||
          _haversine(epiPt, _lastEpicenterFocus!) > 50 ||
          epi.stage != _lastEpicenterStage) {
        _lastEpicenterFocus = epiPt;
        _lastEpicenterStage = epi.stage;
        mapState.smartMoveToCenter(
          epiPt,
          zoom: 6.5,
          sourceTag: 'policy-epi-focus',
          force: true,
          minInterval: const Duration(milliseconds: 3000),
        );
        return;
      }
    } else {
      _lastEpicenterFocus = null;
    }

    final fallback = _defaultFallbackCenter();
    mapState.smartMoveToCenter(
      fallback,
      zoom: _defaultFallbackZoom(),
      sourceTag: 'policy-default',
      force: false,
      minInterval: const Duration(milliseconds: 1200),
    );
  }

  bool _applyStationFocusPolicy(
    MapStateProvider mapState, {
    required bool force,
  }) {
    var preferred = _preferredStationFocusSource;
    final currentPreferredPoints = switch (preferred) {
      'kma' => _kmaFocusStations().map((s) => s.coordinate).toList(),
      'trem' => _tremFocusStations().map((s) => s.coordinate).toList(),
      'nied' => _niedFocusPoints(),
      _ => const <LatLng>[],
    };
    if (preferred != null && currentPreferredPoints.isEmpty) {
      _preferredStationFocusSource = null;
      _preferredStationFocusPoints = null;
      preferred = null;
    }

    final preferredPoints =
        _preferredStationFocusPoints != null &&
            _preferredStationFocusPoints!.isNotEmpty
        ? _preferredStationFocusPoints!
        : currentPreferredPoints;

    final stationPoints = <String, List<LatLng>>{
      'nied': _niedFocusPoints(),
      'kma': _kmaFocusStations().map((s) => s.coordinate).toList(),
      'trem': _tremFocusStations().map((s) => s.coordinate).toList(),
      if (preferred != null && preferredPoints.isNotEmpty)
        preferred: preferredPoints,
    };
    final preferredHasPoints =
        preferred != null && (stationPoints[preferred]?.isNotEmpty ?? false);

    final order = <String>[
      if (preferredHasPoints) preferred,
      for (final source in const ['nied', 'kma', 'trem'])
        if (source != preferred) source,
    ];

    for (final source in order) {
      final points = stationPoints[source] ?? const <LatLng>[];
      if (points.isEmpty) continue;

      mapState.smartMoveToPoints(
        points,
        minZoom: 4.5,
        maxZoom: 8.5,
        padding: _stationFocusPadding(points.length),
        screenOffset: _stationFocusOffset(),
        sourceTag: 'policy-$source-station',
        force: force,
        minInterval: const Duration(milliseconds: 2000),
      );
      return true;
    }

    return false;
  }

  String _cameraDatasetKey(QuakeProvider provider) {
    final unified = provider.unifiedEvents
        .map((e) => '${e.eventId}:${e.reportNumText}:${e.isEew ? 1 : 0}')
        .join('|');
    final niedSig = _lastNiedStationFocusSignature ?? '';
    final kmaSig = _lastKmaStationFocusSignature ?? '';
    final tremSig = _lastTremStationFocusSignature ?? '';
    final stationPref = _preferredStationFocusSource ?? '';
    return 'u[$unified]-n[$niedSig]-k[$kmaSig]-c[$tremSig]-sp[$stationPref]';
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
              final jma = JpShindoScale.jmaIndexFromLevel(s.level);
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

    final focusStations = _kmaFocusStations();
    if (focusStations.isEmpty) {
      _lastKmaStationFocusSignature = null;
      _lastKmaStationFocusAt = null;
      return false;
    }

    final signature = _kmaFocusGridSignature(focusStations);
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
    _preferStationFocusSource(
      'kma',
      force,
      focusStations.map((s) => s.coordinate).toList(),
    );
    _queueCameraPolicyRefresh(force: force);
    return true;
  }

  List<KmaStation> _kmaFocusStations() {
    // kanameishi: 鐩存帴鏌ュ凡鐢绘牸瀛?
    if (_kmaGridCellCenters.isEmpty) return const [];
    final gridSet = _kmaGridCellCenters.toSet();
    return _kmaStations.where((s) => gridSet.contains(s.coordinate)).toList()
      ..sort((a, b) => b.intensity.compareTo(a.intensity));
  }

  String _kmaFocusGridSignature(List<KmaStation> stations) {
    final keys =
        stations
            .map((s) {
              final lat = s.coordinate.latitude.floor();
              final lng = s.coordinate.longitude.floor();
              return '$lat,$lng:${_stationFocusLevel(s.intensity.toDouble())}';
            })
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
    _preferStationFocusSource(
      'trem',
      force,
      focusStations.map((s) => s.coordinate).toList(),
    );
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
    if (_preferredViewCenter != null) return _preferredViewCenter!;
    final pos = LocationService().currentPosition;
    if (pos != null) {
      return LatLng(pos.latitude, pos.longitude);
    }
    return MapStateProvider.defaultCenter;
  }

  double _defaultFallbackZoom() =>
      _preferredDefaultZoom ?? MapStateProvider.defaultZoom;

  void _onShakeExpired() {
    if (!mounted) return;
    // Shake end should never force a default-view reset.
    // The center button owns explicit default-view navigation.
    _queueCameraPolicyRefresh(force: false);
  }

  /// 杩炴帴鐘舵€佸洖璋冪粦瀹?  ///
  /// 灏嗗悇鐩戞祴鏈嶅姟鐨勭姸鎬佸彉鍖栧洖璋冪粦瀹氬埌 QuakeProvider銆?  /// 褰撴湇鍔¤繛鎺ユ垨鏂紑鏃讹紝鏇存柊鍏ㄥ眬鐘舵€併€?
  void _wireStatusCallbacks() {
    final provider = context.read<QuakeProvider>();
    void updateNiedStatus(bool connected) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        provider.updateSourceStatus(
          'NIED',
          connected ? SourceStatus.connected : SourceStatus.error,
        );
        setState(() {});
      });
    }

    _lmoniService.onStatusChanged = updateNiedStatus;
    _yahooService.onStatusChanged = updateNiedStatus;
    _kmaService.onStatusChanged = (connected) {
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          provider.updateSourceStatus(
            'S-net',
            connected ? SourceStatus.connected : SourceStatus.error,
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

    double niedMax = -1;
    for (final s in _niedStations) {
      if (s.level >= 0 && s.level > niedMax) {
        niedMax = s.level.toDouble();
        summary.niedMaxStation = s;
      }
    }

    int treaMax = -1;
    for (final s in _cwaStations) {
      if (s.alertIntensity > treaMax) {
        treaMax = s.alertIntensity;
        summary.treaMaxStation = s;
      }
    }

    int kmaMax = -1;
    for (final s in _kmaStations) {
      if (s.intensity > kmaMax) {
        kmaMax = s.intensity;
        summary.kmaMaxStation = s;
      }
    }

    final snetCandidates =
        _snetService.stations.where((s) => s.shindo >= 1.0).toList()
          ..sort((a, b) => b.shindo.compareTo(a.shindo));
    if (snetCandidates.isNotEmpty) {
      summary.snetWindowEnd = DateTime.now();
      summary.snetWindowStart = summary.snetWindowEnd!.subtract(
        const Duration(minutes: 10),
      );
      summary.snetTopStations = snetCandidates
          .take(5)
          .map(
            (s) => SnetTopStation(
              code: s.code,
              shindo: s.shindo,
              jmaIndex: JpShindoScale.jmaIndexFromShindo(s.shindo),
            ),
          )
          .toList(growable: false);
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
      detectedStations: _latestDetectSnapshot.detectedStations,
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

  /// 鍒濆鍖?NIED 鏈嶅姟 (鍥剧墖鐩存帴鑾峰彇 鈫?瑙ｆ瀽 鈫?鍥惧眰)

  void _initNiedFromImage() async {
    final prefs = await SharedPreferences.getInstance();
    final niedSource = prefs.getString('nied_data_source') ?? 'lmoni';
    _niedSource = niedSource;
    _useYahooSource = niedSource == 'yahoo';
    QuakeMapView.niedSourceNotifier.value = niedSource;
    if (!_useYahooSource) {
      NiedMonitorService().configureEndpoint(niedSource);
    }
    final replayConfig = _niedReplayConfigFromPrefs(prefs);
    QuakeMapView.niedReplayNotifier.value = replayConfig;
    NiedMonitorService().configureReplay(replayConfig);
    _yahooService.configureReplay(replayConfig);
    final sensitivity = prefs.getInt('shake_sensitivity') ?? 2;
    _shakeDetection.setSensitivity(sensitivity);
    _kmaService.setSensitivity(sensitivity);
    _hideGridOnEew = prefs.getBool('hide_grid_on_eew') ?? false;

    if (_useYahooSource) {
      _yahooService.start();
    } else {
      _lmoniService.start();
      NiedMonitorService().start();
    }

    QuakeMapView.niedSourceNotifier.addListener(_onNiedSourceChanged);
    QuakeMapView.niedReplayNotifier.addListener(_onNiedReplayChanged);

    _lmoniStationSub = _lmoniService.stationStream.listen((stations) {
      if (!mounted || _useYahooSource) return;
      if (stations != null) {
        _niedStations = stations;
        _shakeDetection.setStations(stations);
        _shakeDetection.processUpdate();
        _requestNiedStationFocus();
      }
      setState(() {});
      _emitStationSummary();
    });

    _yahooStationSub = _yahooService.stationStream.listen((stations) {
      if (!mounted || !_useYahooSource) return;
      if (stations != null) {
        _niedStations = stations;
        _shakeDetection.setStations(stations);
        _shakeDetection.processUpdate();
        _requestNiedStationFocus();
      }
      setState(() {});
      _emitStationSummary();
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
      _latestDetectSnapshot = snapshot;
      _emitStationSummary();

      // NIED estimated epicenter/P-S display is disabled while detection follows kanameishi.

      if (_showNiedEstimatedEpicenter &&
          snapshot.stage != ShakeDetectStage.idle &&
          snapshot.hypoLat != null &&
          snapshot.hypoLng != null) {
        final epiPt = LatLng(snapshot.hypoLat!, snapshot.hypoLng!);
        final firstDetect =
            _niedDetectFirstAt == null || snapshot.stage != _lastEpicenterStage;
        if (firstDetect) {
          _niedDetectFirstAt = DateTime.now();
          _niedWaveTimer?.cancel();
          _niedWaveTimer = Timer.periodic(const Duration(milliseconds: 100), (
            _,
          ) {
            if (mounted) {
              _waveTick.value++;
            }
          });
        }
        // Update epicenter when it shifts >10km, recompute station distances
        final needsUpdate =
            firstDetect ||
            _niedDetectEpicenter == null ||
            _haversine(epiPt, _niedDetectEpicenter!) > 10.0;
        if (needsUpdate) {
          _niedDetectEpicenter = epiPt;
          _niedStationDistances.clear();
          for (final s in _niedStations) {
            _niedStationDistances[s.code] = _haversine(epiPt, s.coordinate);
          }
        }
      }
      if (snapshot.stage == ShakeDetectStage.idle) {
        _niedDetectFirstAt = null;
        _niedDetectEpicenter = null;
        _niedWaveTimer?.cancel();
        _niedWaveTimer = null;
        _niedStationDistances.clear();
      }

      // Scratch: 鏈€鐭偣琛ㄧず 鈥?nearest station to hypocenter

      if (_showNiedEstimatedEpicenter &&
          snapshot.hypoLat != null &&
          snapshot.hypoLng != null) {
        _updateNearestStationToHypo(snapshot.hypoLat!, snapshot.hypoLng!);
      } else {
        _nearestStationToHypo = null;
      }

      debugPrint(
        'NIED Detect: ${snapshot.stage.name} weak=${snapshot.weakCount} detected=${snapshot.detectedCount} strong=${snapshot.strongCount} max=${snapshot.maxShindo}',
      );
      setState(() {}); // trigger map redraw for epicenter marker
    };

    _kmaService.onShakeDetected = (maxMmi) {
      debugPrint('KMA ShakeDetection: mmi $maxMmi detected');
      _onKmaShakeDetected(maxMmi);
    };
    _kmaService.onShakeExpired = () {
      debugPrint('KMA ShakeDetection: shake expired');
      _onKmaShakeExpired();
    };

    _cwaService.onShakeDetected = (alertIntensity) {
      debugPrint('TREM ShakeDetection: alert $alertIntensity detected');
      _onTremShakeDetected(alertIntensity);
    };
    _cwaService.onShakeExpired = () {
      debugPrint('TREM ShakeDetection: shake expired');
      _onTremShakeExpired();
    };
  }

  void _onNiedSourceChanged() {
    final newSource = QuakeMapView.niedSourceNotifier.value;
    final useYahoo = newSource == 'yahoo';
    if (newSource == _niedSource) return;

    if (useYahoo) {
      _lmoniService.stop();
      NiedMonitorService().stop();
      _yahooService.start();
    } else {
      NiedMonitorService().configureEndpoint(newSource);
      if (_useYahooSource) {
        _yahooService.stop();
        _lmoniService.start();
        NiedMonitorService().start();
      }
    }

    _niedSource = newSource;
    _useYahooSource = useYahoo;
    _niedStations = [];
    _lastNiedStationFocusSignature = null;
    _lastNiedStationFocusAt = null;
    setState(() {});
    debugPrint('NIED 鏁版嵁婧愬垏鎹负: ${_niedSourceLabel(newSource)}');
  }

  String _niedSourceLabel(String source) {
    switch (source) {
      case 'yahoo':
        return 'Yahoo CDN JSON';
      case 'kmoni':
        return 'KMONI GIF';
      default:
        return 'KMONI GIF';
    }
  }

  void _onNiedReplayChanged() {
    final config = QuakeMapView.niedReplayNotifier.value;
    NiedMonitorService().configureReplay(config);
    _yahooService.configureReplay(config);
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
  Future<void> _initSnet() async {
    _snetService.onDataUpdated = (stations) {
      if (mounted) setState(() {});
    };
    await _snetService.fetchLatestData();
    if (mounted) setState(() {});
    _startSnetMonitoring();
  }

  Future<void> _initLpgmMonitor() async {
    await _lpgmService.start();
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

  /// 鍚姩 S-net 瀹氭湡鐩戞祴
  ///
  /// 姣?15 绉掕幏鍙栦竴娆℃渶鏂版暟鎹€?
  void _startSnetMonitoring() {
    _snetService.startMonitoring(intervalSeconds: 15);
  }

  /// 閲婃斁璧勬簮
  ///
  /// 鍙栨秷璁㈤槄骞跺仠姝㈡墍鏈夌洃娴嬫湇鍔°€?  @override
  void dispose() {
    _tempInfoLocationTimer?.cancel();
    _blinkTimer?.cancel();
    _niedWaveTimer?.cancel();
    _waveTick.dispose();
    _waveAutoZoomTimer?.cancel();
    _kmaStationSubscription?.cancel();
    _cwaStationSubscription?.cancel();
    _lmoniStationSub?.cancel();
    _yahooStationSub?.cancel();
    QuakeMapView.niedSourceNotifier.removeListener(_onNiedSourceChanged);
    QuakeMapView.niedReplayNotifier.removeListener(_onNiedReplayChanged);
    _kmaService.disconnect();
    _cwaService.stop();
    _seisjsSubscription?.cancel();
    _earthScopeStationSubscription?.cancel();
    _geofonStationSubscription?.cancel();
    _fdsnMotionSubscription?.cancel();
    _lpgmSnapshotSubscription?.cancel();
    _seisjsService.disconnect();
    _fdsnMotionService.disconnect();
    _earthScopeStationService.stop();
    _geofonStationService.stop();
    _lmoniService.stop();
    NiedMonitorService().stop();
    _yahooService.stop();
    _snetService.dispose();
    _lpgmService.stop();
    _volcanoMapService.onSitesUpdated = null;
    super.dispose();
  }

  /// 鏋勫缓鍦板浘瑙嗗浘
  ///
  /// 鎸夊浘灞傞『搴忓彔鍔犳樉绀哄悇鏁版嵁灞傘€?  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          color: const Color(0xFF152238),
          child: Consumer<MapStateProvider>(
            builder: (context, mapState, child) {
              return ExcludeSemantics(
                child: FlutterMap(
                  key: ValueKey(mapState.tileKey),
                  mapController: widget.mapController,
                  options: MapOptions(
                    backgroundColor: const Color(0xFF152238),
                    initialCenter: MapStateProvider.defaultCenter,
                    initialZoom: MapStateProvider.defaultZoom,
                    maxZoom: 18.0,
                    minZoom: 3.0,
                    onPositionChanged: (position, hasGesture) {
                      if (hasGesture) {
                        context.read<MapStateProvider>().pauseAutoZoom();
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: mapState.tileUrl,
                      userAgentPackageName: 'flutterrhythmquake/1.0',
                      tileProvider: AllowAnyCertTileProvider(),
                    ),
                    ..._buildOptionalOverlayLayers(mapState),
                    Consumer<MapStateProvider>(
                      builder: (context, mapState, child) {
                        if (!mapState.isOverlayEnabled('volcanoLayer')) {
                          return const SizedBox.shrink();
                        }
                        return VolcanoLayer(
                          sites: _volcanoSites,
                          showHoverTargets: false,
                        );
                      },
                    ),
                    Consumer<QuakeProvider>(
                      builder: (context, provider, child) {
                        final hasJmaEew =
                            _hideGridOnEew &&
                            provider.unifiedEvents.any(
                              (e) => e.source == 'jmaEew' && e.isEew,
                            );
                        final hasCwaEew =
                            _hideGridOnEew &&
                            provider.unifiedEvents.any(
                              (e) => e.source == 'cwaEew' && e.isEew,
                            );
                        final hasKmaEew =
                            _hideGridOnEew &&
                            provider.unifiedEvents.any(
                              (e) => e.source == 'kmaEew' && e.isEew,
                            );
                        return Stack(
                          children: [
                            if (_niedLayerVisible)
                              NiedIntensityLayer(
                                stations: _niedStations,
                                hideGrid: hasJmaEew,
                                blinkOn: _blinkOn,
                                detectionGridCells:
                                    _latestDetectSnapshot.gridCells,
                                onGridCellsChanged: (centers) {
                                  _niedGridCellCenters
                                    ..clear()
                                    ..addAll(centers);
                                  if (_pendingNiedStationFocus) {
                                    _pendingNiedStationFocus = false;
                                    _requestNiedStationFocus(force: true);
                                  } else if (_preferredStationFocusSource ==
                                      'nied') {
                                    _requestNiedStationFocus();
                                  }
                                },
                              ),
                            if (_kmaVisible && _kmaStations.isNotEmpty)
                              KmaIntensityLayer(
                                stations: _kmaStations,
                                hideGrid: hasKmaEew,
                                blinkOn: _blinkOn,
                                onGridCellsChanged: (centers) {
                                  _kmaGridCellCenters
                                    ..clear()
                                    ..addAll(centers);
                                  if (_pendingKmaStationFocus) {
                                    _pendingKmaStationFocus = false;
                                    _requestKmaStationFocus(force: true);
                                  } else if (_preferredStationFocusSource ==
                                      'kma') {
                                    _requestKmaStationFocus();
                                  }
                                },
                              ),
                            if (_cwaVisible && _cwaStations.isNotEmpty)
                              CwaStationLayer(
                                stations: _cwaStations,
                                hideGrid: hasCwaEew,
                                blinkOn: _blinkOn,
                                onGridCellsChanged: (_) {
                                  if (_pendingTremStationFocus) {
                                    _pendingTremStationFocus = false;
                                    _requestTremStationFocus(force: true);
                                  } else if (_preferredStationFocusSource ==
                                      'trem') {
                                    _requestTremStationFocus();
                                  }
                                },
                              ),
                          ],
                        );
                      },
                    ),
                    if (_seisjsVisible && _seisjsStations.isNotEmpty)
                      SeisJsLayer(stations: _seisjsStations),
                    if (_snetVisible)
                      SnetLayer(stations: _snetService.stations),
                    Consumer<MapStateProvider>(
                      builder: (context, mapState, child) {
                        if (!mapState.isOverlayEnabled('fdsnEarthScope') ||
                            _earthScopeStations.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return FdsnStationLayer(stations: _earthScopeStations);
                      },
                    ),
                    Consumer<MapStateProvider>(
                      builder: (context, mapState, child) {
                        if (!mapState.isOverlayEnabled('fdsnGeofon') ||
                            _geofonStations.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return FdsnStationLayer(stations: _geofonStations);
                      },
                    ),
                    Consumer<QuakeProvider>(
                      builder: (context, provider, child) {
                        final irData = provider.cencIrData;
                        if (irData == null) return const SizedBox.shrink();
                        return CencIrLayer(data: irData);
                      },
                    ),
                    const UserLocationLayer(),
                    Consumer<MapStateProvider>(
                      builder: (context, mapState, child) {
                        if (!mapState.showEstimatedEpicenter) {
                          return const SizedBox.shrink();
                        }
                        return _buildEstimatedEpicenterMarker();
                      },
                    ),
                    Consumer<MapStateProvider>(
                      builder: (context, mapState, child) {
                        if (!mapState.showEstimatedEpicenter) {
                          return const SizedBox.shrink();
                        }
                        return _buildNearestStationMarker();
                      },
                    ),
                    Consumer<MapStateProvider>(
                      builder: (context, mapState, child) {
                        if (!mapState.isOverlayEnabled('volcanoLayer')) {
                          return const SizedBox.shrink();
                        }
                        return VolcanoLayer(
                          sites: _volcanoSites,
                          showMarkers: false,
                        );
                      },
                    ),
                    Consumer<QuakeProvider>(
                      builder: (context, provider, child) {
                        final unifiedEvents = provider.unifiedEvents;
                        final hasUnified = unifiedEvents.isNotEmpty;
                        final cameraDatasetKey = _cameraDatasetKey(provider);
                        if (cameraDatasetKey != _lastCameraDatasetKey) {
                          _lastCameraDatasetKey = cameraDatasetKey;
                          _queueCameraPolicyRefresh();
                        }

                        if (!hasUnified) {
                          _lastFirstEventId = null;
                          _lastEventPointFocusSignature = null;
                          return const SizedBox.shrink();
                        }

                        if (hasUnified) {
                          final first = unifiedEvents.first;
                          if (first.eventId != _lastFirstEventId) {
                            _lastFirstEventId = first.eventId;
                            // kanameishi: 鏂颁簨浠跺埌杈炬椂璁剧疆涓存椂鑱氱劍 (瀵归綈 tempEqlists 6.5s)
                            final mapEv = provider.unifiedMapEvents.first;
                            if (mapEv.latitude != 0 || mapEv.longitude != 0) {
                              _requestEventPointFocus(
                                mapEv,
                                'unified:${first.eventId}',
                                force: true,
                                hold: const Duration(milliseconds: 6500),
                              );
                            } else {
                              _queueCameraPolicyRefresh(force: true);
                            }
                          }
                        }

                        final allLayers = <Widget>[];
                        final userPos = LocationService().currentPosition;
                        final userLatLng = userPos != null
                            ? LatLng(userPos.latitude, userPos.longitude)
                            : null;

                        if (hasUnified) {
                          final mapEvents = provider.unifiedMapEvents;
                          final layerCount = math.min(
                            unifiedEvents.length,
                            mapEvents.length,
                          );
                          for (int i = 0; i < layerCount; i++) {
                            final u = unifiedEvents[i];
                            final qm = mapEvents[i];
                            final layerKey = _mapLayerKey(qm, u.eventId, i);

                            {
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

                              if (regionSource.isNotEmpty && qm.magnitude > 0) {
                                allLayers.add(
                                  IntensityFillLayer(
                                    key: ValueKey('intensity_$layerKey'),
                                    magnitude: qm.magnitude,
                                    depth: qm.depth,
                                    hypoLat: qm.latitude,
                                    hypoLng: qm.longitude,
                                    source: regionSource,
                                    mode: useJma
                                        ? IntensityFillMode.jma
                                        : IntensityFillMode.csis,
                                    minIntensity: 1.0,
                                    opacity: 0.35,
                                    enabled: true,
                                    warnAreaJson: u.warnArea,
                                  ),
                                );
                              }
                            }

                            allLayers.add(
                              QuakeWaveLayer(
                                key: ValueKey('unified_$layerKey'),
                                event: qm,
                                showWaves: u.isEew,
                                userPosition: userLatLng,
                                colorMode: SWaveColorMode.alert,
                                blinkOn: u.isEew ? _blinkOn : true,
                              ),
                            );
                          }
                        }

                        // P/S wave circles now drawn at estimated epicenter

                        return Stack(children: allLayers);
                      },
                    ),
                    Consumer<QuakeProvider>(
                      builder: (context, provider, _) {
                        final cmts = provider.activeInfoEvents
                            .where(
                              (e) => e.event.source == QuakeSourceType.fssnCmt,
                            )
                            .map((e) => FssnCmtMarker.fromQuakeMessage(e.event))
                            .toList();
                        return FssnCmtLayer(markers: cmts);
                      },
                    ),
                    Consumer<MapStateProvider>(
                      builder: (context, mapProvider, child) {
                        final selected = mapProvider.selectedHistoryEvent;
                        return HistoryMarkerLayer(event: selected);
                      },
                    ),
                    Consumer<QuakeProvider>(
                      builder: (context, provider, child) {
                        final jma = provider.jmaTsunami;
                        final nmefc = provider.nmefcTsunami;
                        if (jma == null && nmefc == null) {
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
                          ],
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        // NIED 鍥炴斁鐘舵€佸彔鍔犲眰
        _buildReplayOverlay(),
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
              '鍥炴斁  $timeText  $stepText',
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

  /// 鎺ㄧ畻闇囦腑鏍囪: P 娉㈠湀(姘磋壊) + S 娉㈠湀(鎸夐渿搴︾潃鑹? + 涓績鐐?  /// 瀵归綈妯℃嫙鍣?sb3: S 娉㈤鑹叉寜 JMA 闇囧害 5 绾э紝鍦嗛殢鍦板浘缂╂斁

  Widget _buildEstimatedEpicenterMarker() {
    return Consumer<MapStateProvider>(
      builder: (context, mapState, child) {
        if (!mapState.showEstimatedEpicenter) return const SizedBox.shrink();
        final epi = _latestDetectSnapshot;
        if (epi.hypoLat == null || epi.hypoLng == null) {
          return const SizedBox.shrink();
        }
        if (epi.stage == ShakeDetectStage.idle) return const SizedBox.shrink();

        final point = LatLng(epi.hypoLat!, epi.hypoLng!);
        final zoom = mapState.mapController?.camera.zoom ?? 7.0;
        final zoomScale = math.pow(2, 7 - zoom);
        final shindo = epi.maxShindo > 0 ? epi.maxShindo.toDouble() : 0.0;
        final intensity = epi.maxShindo > 0 ? epi.maxShindo : 1.0;
        final size = intensity * 20.0 * zoomScale;
        final sColor = _sWaveColor(shindo);
        final accent = _estimateAccentColor(epi);

        return ValueListenableBuilder<int>(
          valueListenable: _waveTick,
          builder: (context, tick, child) {
            final circles = <CircleMarker<Object>>[
              // 瀹炲績涓績鐐?(S 娉㈤渿搴﹁壊)
              CircleMarker(
                point: point,
                radius: math.max(7.0, size * 0.24),
                color: accent.withValues(alpha: 0.18),
                borderColor: accent.withValues(alpha: 0.82),
                borderStrokeWidth: 1.4,
              ),
              // 鍐呭湀 (S 娉㈤渿搴﹁壊)
              CircleMarker(
                point: point,
                radius: math.max(18.0, size * 0.62),
                color: Colors.transparent,
                borderColor: accent.withValues(alpha: 0.22),
                borderStrokeWidth: 1.2,
              ),
            ];

            // P/S 娉㈠悓蹇冨渾 (瀵归綈 kanameishi: 浣跨敤 JMA2001/JB 璧版椂琛?
            // 璧版椂琛ㄦ湭鍔犺浇鏃?fallback 鍒板浐瀹氭尝閫?
            double pRadiusKm = 0;
            double sRadiusKm = 0;

            if (_niedDetectFirstAt != null) {
              final elapsed =
                  DateTime.now()
                      .difference(_niedDetectFirstAt!)
                      .inMilliseconds /
                  1000.0;
              final depth = epi.hypoDepth ?? 0.0;
              final tts = TravelTimeService();

              if (tts.isLoaded) {
                var pInfo = tts.calcWaveDistance(
                  'jma2001',
                  true,
                  depth,
                  elapsed,
                );
                if (pInfo.radius > 2000) {
                  pInfo = tts.calcWaveDistance('jb', true, depth, elapsed);
                }
                pRadiusKm = pInfo.radius;

                var sInfo = tts.calcWaveDistance(
                  'jma2001',
                  false,
                  depth,
                  elapsed,
                );
                if (sInfo.radius > 2000) {
                  sInfo = tts.calcWaveDistance('jb', false, depth, elapsed);
                }
                sRadiusKm = sInfo.radius;
              } else {
                final depthFactor = depth > 0
                    ? (1.0 - (depth / 700) * 0.15).clamp(0.85, 1.0)
                    : 1.0;
                pRadiusKm = elapsed * QuakeCalculator.pWaveSpeed * depthFactor;
                sRadiusKm = elapsed * QuakeCalculator.sWaveSpeed * depthFactor;
              }
            }

            final pRadiusM = pRadiusKm > 0 ? pRadiusKm * 1000 : 0.0;
            final sRadiusM = sRadiusKm > 0 ? sRadiusKm * 1000 : 0.0;

            // P 娉㈠湀鍏堢敾 (搴曞眰, 姘磋壊)
            circles.insert(
              0,
              CircleMarker(
                point: point,
                radius: pRadiusM,
                useRadiusInMeter: true,
                color: const Color(0x144FA8FF),
                borderColor: const Color(0x664FA8FF),
                borderStrokeWidth: 1.15,
              ),
            );

            // S 娉㈠湀鍚庣敾 (涓婂眰, 闇囧害鑹?
            circles.add(
              CircleMarker(
                point: point,
                radius: sRadiusM,
                useRadiusInMeter: true,
                color: sColor.withValues(alpha: 0.08),
                borderColor: sColor.withValues(alpha: 0.42),
                borderStrokeWidth: 1.4,
              ),
            );

            return Stack(
              children: [
                CircleLayer(circles: circles),
                MarkerLayer(
                  markers: [
                    Marker(
                      width: 88,
                      height: 88,
                      point: point,
                      alignment: Alignment.center,
                      child: _EstimatedEpicenterMarkerVisual(
                        color: accent,
                        maxShindo: epi.maxShindo,
                        depthKm: epi.hypoDepth,
                        confidence: epi.hypoConfidence,
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

  /// S 娉㈠湀棰滆壊 (鎸?JMA 闇囧害 5 绾э紝瀵归綈 Scratch 妯℃嫙鍣?

  static Color _sWaveColor(double shindo) {
    if (shindo >= 6.5) return const Color(0xFF54068E); // 闇囧害7: 娴撶传
    if (shindo >= 5.5) return const Color(0xFFA30A6B); // 闇囧害6寮? 绱孩
    if (shindo >= 4.5) return const Color(0xFFFF6666); // 闇囧害5寮? 绾?
    if (shindo >= 2.5) return const Color(0xFFFFFF77); // 闇囧害3-4: 榛?
    return const Color(0xFF3AFF6F); // 闇囧害1-2: 缁?
  }

  // 鈹€鈹€鈹€ Scratch: 鏈€鐭偣琛ㄧず (nearest station to hypocenter) 鈹€鈹€鈹€

  static Color _estimateAccentColor(ShakeDetectionSnapshot snapshot) {
    if (snapshot.strongCount > 0 || snapshot.maxShindo >= 4) {
      return const Color(0xFFFF8A3D);
    }
    if (snapshot.detectedCount > 0 || snapshot.maxShindo >= 1) {
      return const Color(0xFF3FE08F);
    }
    return const Color(0xFF57B6FF);
  }

  void _updateNearestStationToHypo(double hypoLat, double hypoLng) {
    final stations = _niedStations
        .where((s) => s.isActive && s.level >= 0)
        .toList();
    if (stations.isEmpty) {
      _nearestStationToHypo = null;
      return;
    }
    final hypoPoint = LatLng(hypoLat, hypoLng);
    NiedStation? nearest;
    var best = double.infinity;
    for (final s in stations) {
      final d = _haversine(hypoPoint, s.coordinate);
      if (d < best) {
        best = d;
        nearest = s;
      }
    }
    _nearestStationToHypo = nearest?.coordinate;
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

  /// 鏈€杩戠珯楂樹寒鏍囪 (Scratch: 鏈€鐭偣琛ㄧず)

  Widget _buildNearestStationMarker() {
    final nearest = _nearestStationToHypo;
    if (nearest == null) return const SizedBox.shrink();
    if (_latestDetectSnapshot.stage == ShakeDetectStage.idle) {
      return const SizedBox.shrink();
    }
    final accent = _estimateAccentColor(_latestDetectSnapshot);
    return MarkerLayer(
      markers: [
        Marker(
          width: 24,
          height: 24,
          point: nearest,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.14),
              border: Border.all(
                color: accent.withValues(alpha: 0.82),
                width: 1.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.28),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildOptionalOverlayLayers(MapStateProvider mapState) {
    final layers = <Widget>[];
    void addOverlay(String key) {
      if (!mapState.isOverlayEnabled(key)) return;
      layers.add(
        TileLayer(
          urlTemplate: MapConfig.overlayUrlByKey(key),
          userAgentPackageName: 'flutterrhythmquake/1.0',
          tileProvider: AllowAnyCertTileProvider(),
        ),
      );
    }

    addOverlay('cloudLayer');
    addOverlay('windLayer');
    addOverlay('rainLayer');
    addOverlay('cnContour');
    return layers;
  }
}

class _EstimatedEpicenterMarkerVisual extends StatelessWidget {
  final Color color;
  final int maxShindo;
  final double? depthKm;
  final double? confidence;

  const _EstimatedEpicenterMarkerVisual({
    required this.color,
    required this.maxShindo,
    required this.depthKm,
    required this.confidence,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = maxShindo >= 4 ? Colors.black : Colors.white;
    final confidenceText = confidence == null
        ? '--'
        : '${(confidence!.clamp(0.0, 0.99) * 100).round()}%';
    final depthText = depthKm == null ? '--' : '${depthKm!.round()}km';

    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.22),
              border: Border.all(color: color, width: 1.6),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.24),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          Container(
            width: 1.5,
            height: 34,
            color: color.withValues(alpha: 0.88),
          ),
          Container(
            width: 34,
            height: 1.5,
            color: color.withValues(alpha: 0.88),
          ),
          Positioned(
            top: 48,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xE0121824),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.60)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: DefaultTextStyle(
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        maxShindo < 0 ? '--' : '$maxShindo',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(depthText),
                    const SizedBox(width: 6),
                    Text(confidenceText),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
