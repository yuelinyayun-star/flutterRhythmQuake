import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/quake_message.dart';
import '../models/cenc_ir_data.dart';
import '../models/weather_alarm.dart';
import '../models/unified_quake_data.dart';
import '../models/tsunami_message.dart';
import '../models/source_status.dart';
import 'background_event_processor.dart';
import 'background_source_reload_plan.dart';
import 'epicenter_region_service.dart';
import 'location_service.dart';
import 'ntp_service.dart';
import 'quake_event_adapter.dart';
import 'sources/emsc_eqlist_service.dart';
import 'sources/eqlist/cwa_eqlist_service.dart';
import 'sources/eqlist/cenc_eqlist_service.dart';
import 'sources/eqlist/jma_eqlist_service.dart';
import 'sources/fan_service.dart';
import 'sources/global_quake_service.dart';
import 'sources/mock_input_service.dart';
import 'sources/nowquake_cenc_intensity_service.dart';
import 'sources/p2pquake_service.dart';
import 'sources/source_manager.dart';
import 'sources/usgs_eqlist_service.dart';
import 'sources/wolfx_service.dart';
import 'sources/whews_service.dart';
import 'sources/jian_service.dart';
import 'wauth_credential_store.dart';
import 'foreground_station_payload.dart';
import 'sources/cwa_station_service.dart';
import 'sources/kma_monitor.dart';
import 'sources/lmoni_image_service.dart';
import 'sources/nied_monitor.dart';
import 'sources/nied_background_worker.dart';
import 'sources/nied_yahoo_service.dart';
import 'sources/palert_service.dart';
import 'sources/seisjs_service.dart';
import 'sources/snet_service.dart';
import 'sources/whews_station_service.dart';
import 'sources/whews_socket_client.dart';
import 'sources/cenc_cmt_service.dart';
import 'sources/usgs_cmt_service.dart';
import 'sources/jma_cmt_service.dart';
import 'sources/fnet_cmt_service.dart';
import 'sources/hinet_aqua_cmt_service.dart';
import 'sources/lpgm_monitor_service.dart';
import 'sources/fdsn_station_service.dart';
import 'sources/fdsn_motion_service.dart';
import 'sources/fan_radar_service.dart';
import 'sources/fan_satellite_cloud_service.dart';
import 'sources/jma_radar_service.dart';
import 'sources/jma_satellite_cloud_service.dart';
import 'sources/nsmc_satellite_cloud_service.dart';
import 'sources/jma_volcano_map_service.dart';
import 'sources/typhoon_service.dart';
import 'sources/cma_local_weather_service.dart';
import 'sources/jma_local_weather_service.dart';
import 'sources/jma_lpgm_service.dart';
import 'sources/jma_megaquake_advisory_service.dart';
import 'sources/china_weather_alert_service.dart';
import '../core/local_weather_region.dart';

final List<StreamSubscription> _backgroundSubscriptions = [];
final List<Timer> _backgroundTimers = [];
SourceManager? _backgroundManager;
BackgroundEventProcessor? _backgroundEventProcessor;

void setBackgroundJmaVolcanoPushEnabled(bool enabled) {
  _backgroundEventProcessor?.jmaVolcanoPushEnabled = enabled;
  _backgroundSettings?[BackgroundEventProcessor.jmaVolcanoPushEnabledPreferenceKey] =
      enabled;
}

void reloadBackgroundJianCredentials() {
  _backgroundManager?.getSource<JianService>()?.reloadCredentials();
}

SourceStatusUpdate? backgroundJianStatus() {
  final jian = _backgroundManager?.getSource<JianService>();
  return jian == null
      ? null
      : SourceStatusUpdate(jian.name, jian.connectionStatus,
          authenticationStatus: jian.authenticationStatus,
          credentialInfo: jian.credentialInfo);
}
UsgsEqlistService? _backgroundOfficialUsgs;
EmscEqlistService? _backgroundOfficialEmsc;
CwaEqlistService? _backgroundOfficialCwa;
CencEqlistService? _backgroundOfficialCenc;
JmaEqlistService? _backgroundOfficialJma;
Timer? _backgroundSeenStatePersistTimer;
final List<StreamSubscription<dynamic>> _backgroundStationSubscriptions = [];
final List<StreamSubscription<dynamic>> _backgroundCmtSubscriptions = [];
final List<StreamSubscription<dynamic>> _backgroundAuxSubscriptions = [];
LmoniImageService? _backgroundLmoni;
NiedMonitorService? _backgroundNiedMonitor;
NiedYahooService? _backgroundYahoo;
KmaMonitorService? _backgroundKma;
CwaStationService? _backgroundCwa;
SnetService? _backgroundSnet;
SeisJsService? _backgroundSeisJs;
PAlertService? _backgroundPAlert;
WhewsStationService? _backgroundWhewsNied;
WhewsStationService? _backgroundWhewsSnet;
WhewsStationService? _backgroundWhewsKma;
CencCmtService? _backgroundCencCmt;
UsgsCmtService? _backgroundUsgsCmt;
JmaCmtService? _backgroundJmaCmt;
FnetCmtService? _backgroundFnetCmt;
HinetAquaCmtService? _backgroundHinetAquaCmt;
LpgmMonitorService? _backgroundLpgm;
FdsnStationService? _backgroundEarthScopeStations;
FdsnStationService? _backgroundGeofonStations;
FdsnMotionService? _backgroundFdsnMotion;
FanRadarService? _backgroundFanRadar;
FanRadarService? _backgroundCmaPrecipitation;
FanSatelliteCloudService? _backgroundFanSatellite;
JmaRadarService? _backgroundJmaRadar;
JmaSatelliteCloudService? _backgroundJmaSatelliteCloud;
NsmcSatelliteCloudService? _backgroundNsmcSatelliteCloud;
JmaVolcanoMapService? _backgroundVolcanoMap;
TyphoonService? _backgroundTyphoon;
ChinaWeatherAlertService? _backgroundChinaWeather;
CmaLocalWeatherService? _backgroundCmaWeather;
JmaLocalWeatherService? _backgroundJmaWeather;
JmaLpgmService? _backgroundJmaLpgm;
JmaMegaquakeAdvisoryService? _backgroundJmaMegaquake;
Map<String, Object>? _backgroundSettings;
String _backgroundNiedSource = 'lmoni';

void setBackgroundPAlertDetectionSensitivity(int value) {
  _backgroundPAlert?.setSensitivity(value);
}

Map<String, Object> _settingsSnapshot(SharedPreferences prefs) => {
  for (final key in prefs.getKeys())
    if (!BackgroundSourceReloadPlan.runtimeKeys.contains(key) &&
        prefs.get(key) != null)
      key: prefs.get(key)!,
};

/// Returns false when a non-station setting needs the established full reload.
Future<bool> reloadBackgroundStationSettings() async {
  final previous = _backgroundSettings;
  if (previous == null) return false;
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final next = _settingsSnapshot(prefs);
  final plan = BackgroundSourceReloadPlan(previous, next);
  if (plan.requiresFullReload) return false;
  for (final station in plan.stations) {
    switch (station) {
      case 'nied':
        _backgroundNiedMonitor!.stop();
        NiedBackgroundWorker.instance.stop();
        _backgroundLmoni!.stop();
        _backgroundYahoo!.stop();
        _backgroundWhewsNied!.stop();
        _backgroundNiedSource = prefs.getString('nied_data_source') ?? 'lmoni';
        if (prefs.getBool('api_source_nied_monitor_enabled') ?? true) {
          if (_backgroundNiedSource == 'yahoo') {
            _backgroundYahoo!.start();
          } else if (_backgroundNiedSource != 'whews') {
            _backgroundNiedMonitor!.configureEndpoint(_backgroundNiedSource);
            _backgroundLmoni!.start();
            _backgroundNiedMonitor!.start();
          }
        }
      case 'kma':
        _backgroundKma!.disconnect();
        _backgroundWhewsKma!.stop();
        final source = prefs.getString('kma_data_source') ?? 'pews';
        if ((prefs.getBool('api_source_kma_pews_enabled') ?? true) &&
            source != 'whews') {
          _backgroundKma!.setConnectionSource(source);
          _backgroundKma!.setExternalInputEnabled(false);
          _backgroundKma!.connect();
        }
      case 'snet':
        _backgroundSnet!.stopMonitoring();
        _backgroundWhewsSnet!.stop();
        if ((prefs.getBool('api_source_snet_enabled') ?? true) &&
            prefs.getString('snet_data_source') != 'whews') {
          unawaited(_backgroundSnet!.startMonitoring());
        }
      case 'trem':
        _backgroundCwa!.stop();
        if (prefs.getBool('trem_station_enabled') ?? true) {
          _backgroundCwa!.start();
        }
      case 'seisjs':
        _backgroundSeisJs!.disconnect();
        if (prefs.getBool('api_source_wolfx_seisjs_enabled') ?? true) {
          _backgroundSeisJs!.connect();
        }
      case 'palert':
        _backgroundPAlert!.stop();
        if (prefs.getBool('api_source_palert_enabled') ?? true) {
          _backgroundPAlert!.start();
        }
    }
  }
  if (plan.stations.any(
    (station) => const {'nied', 'kma', 'snet'}.contains(station),
  )) {
    await _startBackgroundWhewsStationsIfAuthorized(
      prefs,
      whewsNied: _backgroundWhewsNied!,
      whewsKma: _backgroundWhewsKma!,
      whewsSnet: _backgroundWhewsSnet!,
      only: plan.stations,
    );
  }
  _backgroundSettings = next;
  return true;
}

Iterable<Map<String, dynamic>> backgroundLocalWeatherSnapshots() sync* {
  final cma = _backgroundCmaWeather;
  final jma = _backgroundJmaWeather;
  if (cma != null) {
    yield ForegroundStationPayload.cmaWeather(cma.stateNotifier.value);
  }
  if (jma != null) {
    yield ForegroundStationPayload.jmaWeather(jma.stateNotifier.value);
  }
}

Future<void> syncBackgroundSatelliteCloudLayers() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final jma = prefs.getBool('map_overlay_jmaSatelliteCloudLayer') ?? false;
  final nsmc = prefs.getBool('map_overlay_nsmcSatelliteCloudLayer') ?? false;
  if (jma) {
    _backgroundJmaSatelliteCloud?.start();
  } else {
    _backgroundJmaSatelliteCloud?.stop(clear: true);
  }
  if (nsmc) {
    _backgroundNsmcSatelliteCloud?.start();
  } else {
    _backgroundNsmcSatelliteCloud?.stop(clear: true);
  }
  for (final key in const [
    'map_overlay_jmaSatelliteCloudLayer',
    'map_overlay_nsmcSatelliteCloudLayer',
  ]) {
    final value = prefs.getBool(key);
    if (value == null) {
      _backgroundSettings?.remove(key);
    } else {
      _backgroundSettings?[key] = value;
    }
  }
}

Iterable<Map<String, dynamic>> backgroundSatelliteCloudSnapshots() sync* {
  final jma = _backgroundJmaSatelliteCloud;
  final nsmc = _backgroundNsmcSatelliteCloud;
  if (jma?.isRunning == true && jma!.latestFrame != null) {
    yield ForegroundStationPayload.jmaSatelliteCloud(jma.latestFrame!);
  }
  if (nsmc?.isRunning == true && nsmc!.latestFrame != null) {
    yield ForegroundStationPayload.nsmcSatelliteCloud(nsmc.latestFrame!);
  }
}

/// 前台服务 isolate 中运行的 EEW/信息数据源管理
///
/// 与主 isolate 隔离，不共享 SourceManager 单例状态。
/// 仅负责在 Android 前台服务期间保持关键数据源连接并直接弹出系统通知。
///
/// 重新初始化 SourceManager 与相关源，订阅统一事件流，满足阈值时直接弹出通知。
Future<void> startBackgroundSources({
  required void Function(UnifiedQuakeData event, bool isUpdate) onUnifiedEvent,
  required void Function(QuakeMessage event) onQuakeEvent,
  required void Function(String source, List<QuakeMessage> events) onSourceList,
  required void Function(CencIrData data) onCencIrData,
  required void Function(String source, List<Map<String, dynamic>> items)
  onCencIrList,
  required void Function(WeatherAlarm alarm) onWeatherAlarm,
  required void Function(TsunamiMessage event) onTsunamiEvent,
  required void Function(SourceStatusUpdate update) onSourceStatus,
  required void Function(Map<String, dynamic> payload) onStationData,
  required void Function(String source, List<Map<String, dynamic>> items)
  onCmtList,
  required void Function(Map<String, dynamic> payload) onAuxData,
}) async {
  if (kIsWeb || !Platform.isAndroid) return;

  await stopBackgroundSources();

  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  await EpicenterRegionService.instance.load();
  final initialSettings = _settingsSnapshot(prefs);

  // 恢复用户位置（与主 isolate 一致）
  final savedLat = prefs.getDouble('map_view_lat');
  final savedLng = prefs.getDouble('map_view_lng');
  if (savedLat != null && savedLng != null) {
    LocationService().setCurrentLatLng(savedLat, savedLng);
  } else {
    // 没有手动设置位置时，尝试获取一次当前位置（IP 兜底）
    unawaited(LocationService().requestCurrentPosition());
  }

  // 启动时间同步
  NtpService().startPeriodicSync();

  // 加载源震级过滤设置，与主 isolate 保持一致
  final sourceMagFilters = <String, double>{};
  const magFilterPrefix = 'source_mag_filter_';
  for (final entry in prefs.getKeys().where(
    (k) => k.startsWith(magFilterPrefix),
  )) {
    sourceMagFilters[entry] = prefs.getDouble(entry) ?? 0.0;
  }
  late final BackgroundEventProcessor processor;
  processor = BackgroundEventProcessor(
    sourceInfoMagFilters: sourceMagFilters,
    jmaVolcanoPushEnabled: prefs.getBool(
      BackgroundEventProcessor.jmaVolcanoPushEnabledPreferenceKey,
    ) ?? true,
    infoActionWhitelist:
        prefs.getString(
          BackgroundEventProcessor.infoActionWhitelistPreferenceKey,
        ) ??
        '',
    seenUsgsInfoBodyKeys: _readSeenRows(
      prefs,
      BackgroundEventProcessor.seenUsgsInfoBodyKeysPreferenceKey,
      const Duration(hours: 24),
    ),
    seenEmscInfoBodyKeys: _readSeenRows(
      prefs,
      BackgroundEventProcessor.seenEmscInfoBodyKeysPreferenceKey,
      const Duration(hours: 24),
    ),
    seenCwaInfoBodyKeys: _readSeenRows(
      prefs,
      BackgroundEventProcessor.seenCwaInfoBodyKeysPreferenceKey,
      const Duration(hours: 24),
    ),
    seenNoUpdateInfoEvents: _readSeenRows(
      prefs,
      BackgroundEventProcessor.seenNoUpdateInfoEventsPreferenceKey,
      const Duration(hours: 48),
    ),
    seenUnifiedInfoEvents: _readSeenRows(
      prefs,
      BackgroundEventProcessor.seenUnifiedInfoEventsPreferenceKey,
      const Duration(hours: 48),
    ),
    acceptedEewReportNums: _readAcceptedEewRows(prefs),
    onSeenStateChanged: () {
      _backgroundSeenStatePersistTimer?.cancel();
      _backgroundSeenStatePersistTimer = Timer(
        const Duration(milliseconds: 250),
        () => unawaited(_persistBackgroundSeenState(prefs, processor)),
      );
    },
  );

  _backgroundEventProcessor = processor;

  // 创建新的源实例（isolate 内为独立对象，避免与主 isolate 共享状态）
  final wolfx = WolfxService();
  final whews = WhewsService(apiToken: '');
  final fan = FanService(
    apiKey: prefs.getString(FanService.apiKeyPreferenceKey) ?? '',
  );
  final nowQuakeCencIr = NowQuakeCencIntensityService();
  final jian = JianService();
  final nowQuakeCencIrEnabled =
      prefs.getBool(NowQuakeCencIntensityService.preferenceKey) ?? true;
  fan.setCencIrRequestsEnabled(!nowQuakeCencIrEnabled);
  fan.setDefaultServerIndex(prefs.getInt('fan_default_server_index') ?? 0);
  final p2p = P2PQuakeService();
  final mock = MockInputService();
  final globalQuake = GlobalQuakeService();
  final officialUsgs = UsgsEqlistService();
  final officialEmsc = EmscEqlistService();
  final officialCwa = CwaEqlistService();
  final officialCenc = CencEqlistService();
  final officialJma = JmaEqlistService();
  final cencCmt = CencCmtService();
  final usgsCmt = UsgsCmtService();
  final jmaCmt = JmaCmtService();
  final fnetCmt = FnetCmtService();
  final hinetAquaCmt = HinetAquaCmtService();
  final lpgm = LpgmMonitorService();
  final earthScopeStations = FdsnStationService.earthScope;
  final geofonStations = FdsnStationService.geofon;
  final fdsnMotion = FdsnMotionService();
  final fanRadar = FanRadarService();
  final precipitation = FanRadarService.precipitation();
  final fanSatellite = FanSatelliteCloudService();
  final jmaRadar = JmaRadarService();
  final jmaSatelliteCloud = JmaSatelliteCloudService();
  final nsmcSatelliteCloud = NsmcSatelliteCloudService();
  final volcanoMap = JmaVolcanoMapService();
  final typhoon = TyphoonService();
  final chinaWeather = ChinaWeatherAlertService();
  final cmaWeather = CmaLocalWeatherService();
  final jmaWeather = JmaLocalWeatherService();
  final jmaLpgm = JmaLpgmService();
  final jmaMegaquake = JmaMegaquakeAdvisoryService();
  _backgroundFanRadar = fanRadar;
  _backgroundCmaPrecipitation = precipitation;
  _backgroundFanSatellite = fanSatellite;
  _backgroundJmaRadar = jmaRadar;
  _backgroundJmaSatelliteCloud = jmaSatelliteCloud;
  _backgroundNsmcSatelliteCloud = nsmcSatelliteCloud;
  _backgroundVolcanoMap = volcanoMap;
  _backgroundTyphoon = typhoon;
  _backgroundChinaWeather = chinaWeather;
  _backgroundCmaWeather = cmaWeather;
  _backgroundJmaWeather = jmaWeather;
  _backgroundJmaLpgm = jmaLpgm;
  _backgroundJmaMegaquake = jmaMegaquake;
  _backgroundEarthScopeStations = earthScopeStations;
  _backgroundGeofonStations = geofonStations;
  _backgroundFdsnMotion = fdsnMotion;
  _backgroundLpgm = lpgm;
  _backgroundCencCmt = cencCmt;
  _backgroundUsgsCmt = usgsCmt;
  _backgroundJmaCmt = jmaCmt;
  _backgroundFnetCmt = fnetCmt;
  _backgroundHinetAquaCmt = hinetAquaCmt;
  final lmoni = LmoniImageService();
  final niedMonitor = NiedMonitorService();
  final niedSource = prefs.getString('nied_data_source') ?? 'lmoni';
  _backgroundNiedSource = niedSource;
  final yahoo = NiedYahooService();
  final kma = KmaMonitorService();
  final cwa = CwaStationService();
  final snet = SnetService();
  final seisJs = SeisJsService();
  final pAlert = PAlertService();
  pAlert.setSensitivity(prefs.getInt('shake_sensitivity') ?? 2);
  final whewsNied = WhewsStationService(
    kind: WhewsStationKind.nied,
    apiToken: '',
  );
  final whewsSnet = WhewsStationService(
    kind: WhewsStationKind.snet,
    apiToken: '',
  );
  final whewsKma = WhewsStationService(
    kind: WhewsStationKind.kma,
    apiToken: '',
  );
  _backgroundLmoni = lmoni;
  _backgroundNiedMonitor = niedMonitor;
  _backgroundYahoo = yahoo;
  _backgroundKma = kma;
  _backgroundCwa = cwa;
  _backgroundSnet = snet;
  _backgroundSeisJs = seisJs;
  _backgroundPAlert = pAlert;
  _backgroundWhewsNied = whewsNied;
  _backgroundWhewsSnet = whewsSnet;
  _backgroundWhewsKma = whewsKma;
  globalQuake.configureServers(
    primaryHost:
        prefs.getString(GlobalQuakeService.primaryHostPreferenceKey) ??
        GlobalQuakeService.defaultPrimaryHost,
    primaryPort:
        prefs.getInt(GlobalQuakeService.primaryPortPreferenceKey) ??
        GlobalQuakeService.defaultPort,
    secondaryHost:
        prefs.getString(GlobalQuakeService.secondaryHostPreferenceKey) ??
        GlobalQuakeService.defaultSecondaryHost,
    secondaryPort:
        prefs.getInt(GlobalQuakeService.secondaryPortPreferenceKey) ??
        GlobalQuakeService.defaultPort,
  );
  globalQuake.configureFirstReportMagnitudeFilter(
    prefs.getDouble(
          GlobalQuakeService.firstReportMagnitudeThresholdPreferenceKey,
        ) ??
        0,
  );

  // 注册到 isolate 内的 SourceManager（新的单例实例）
  final manager = SourceManager();
  _backgroundManager = manager;
  wolfx.onJmaEqlistUpdated = (items) => onSourceList('jma', items);
  fan.onFssnListUpdated = (items) => onSourceList('fssn', items);
  fan.onCencListUpdated = (items) => onSourceList('cenc', items);
  fan.onCwaListUpdated = (items) => onSourceList('cwa', items);
  fan.onCencIrData = onCencIrData;
  nowQuakeCencIr.onCencIrData = onCencIrData;
  fan.onCencIrListUpdated = (items) => onCencIrList('fan', items);
  nowQuakeCencIr.onCencIrListUpdated =
      (items) => onCencIrList('nowquake', items);
  fan.onWeatherAlarm = onWeatherAlarm;
  whews.onWeatherAlarm = onWeatherAlarm;
  manager.registerSource(wolfx);
  manager.registerSource(whews);
  manager.registerSource(jian);
  manager.setSourceEnabled(jian.name,
    prefs.getBool(JianService.enabledPreferenceKey) ?? false);
  manager.registerSource(fan);
  manager.registerSource(nowQuakeCencIr);
  manager.registerSource(p2p);
  manager.registerSource(mock);
  manager.registerSource(globalQuake);
  manager.setSourceEnabled(
    'FAN',
    prefs.getBool('api_source_fan_enabled') ?? true,
  );
  manager.setSourceEnabled(nowQuakeCencIr.name, nowQuakeCencIrEnabled);
  manager.setSourceEnabled(
    'Wolfx',
    prefs.getBool('api_source_wolfx_enabled') ?? true,
  );
  manager.setSourceEnabled('WHEWS', false);
  manager.setSourceEnabled(
    'P2P',
    prefs.getBool('api_source_p2pquake_enabled') ?? true,
  );

  var nowQuakeStatus = SourceStatus.disconnected;
  var fanCencIrFallbackActive = !nowQuakeCencIrEnabled;
  void syncFanCencIrRequests() {
    if (nowQuakeStatus == SourceStatus.connected &&
        nowQuakeCencIr.hasUsableList) {
      fanCencIrFallbackActive = false;
    } else if (!nowQuakeCencIrEnabled ||
        nowQuakeStatus == SourceStatus.error ||
        nowQuakeStatus == SourceStatus.disconnected ||
        (nowQuakeCencIr.hasCompletedListRequest &&
            !nowQuakeCencIr.hasUsableList)) {
      fanCencIrFallbackActive = true;
    }
    fan.setCencIrRequestsEnabled(fanCencIrFallbackActive);
  }
  nowQuakeCencIr.onListAvailabilityChanged = syncFanCencIrRequests;
  _backgroundSubscriptions.add(manager.onStatusUpdate.listen((update) {
    if (update.sourceName == nowQuakeCencIr.name) {
      nowQuakeStatus = update.status;
      syncFanCencIrRequests();
    }
    onSourceStatus(update);
  }));
  _backgroundSubscriptions.add(manager.onQuakeEvent.listen(onQuakeEvent));

  // 先桥接所有事件，再连接基础 API；测站和地图图层不应阻塞列表获取。
  for (final stream in [
    jian.onUnifiedEvent,
    wolfx.onUnifiedEvent,
    whews.onUnifiedEvent,
    fan.onUnifiedEvent,
    nowQuakeCencIr.onUnifiedEvent,
    p2p.onUnifiedEvent,
    mock.onUnifiedEvent,
    globalQuake.onUnifiedEvent,
  ]) {
    _backgroundSubscriptions.add(stream.listen(
      (event) => _handleUnifiedEvent(event, processor, onUnifiedEvent),
    ));
  }
  for (final stream in [
    p2p.onTsunamiEvent,
    fan.onTsunamiEvent,
    whews.onTsunamiEvent,
    mock.onTsunamiEvent,
  ]) {
    _backgroundSubscriptions.add(stream.listen(onTsunamiEvent));
  }
  manager.startAll();

  void handleOfficialCurrent(String source, Map<String, dynamic> data) {
    final event = QuakeEventAdapter.convert(source, data, 0);
    if (event != null) {
      _handleUnifiedEvent(event, processor, onUnifiedEvent);
    }
  }

  if (_isInfoSourceEnabled(prefs, QuakeSourceType.usgs)) {
    _backgroundOfficialUsgs = officialUsgs;
    officialUsgs.onListUpdated = (items) => onSourceList('usgs', items);
    officialUsgs.onCurrentUpdated = (data) =>
        handleOfficialCurrent('usgsEqlist', data);
    officialUsgs.start();
  }
  if (_isInfoSourceEnabled(prefs, QuakeSourceType.emsc)) {
    _backgroundOfficialEmsc = officialEmsc;
    officialEmsc.onListUpdated = (items) => onSourceList('emsc', items);
    officialEmsc.onCurrentUpdated = (data) =>
        handleOfficialCurrent('emsc', data);
    officialEmsc.start();
  }
  if (_isInfoSourceEnabled(prefs, QuakeSourceType.cwa)) {
    _backgroundOfficialCwa = officialCwa;
    officialCwa.onListUpdated = (items) => onSourceList('cwa', items);
    officialCwa.onCurrentUpdated = (data) =>
        handleOfficialCurrent('cwaEqlist', data);
    officialCwa.start();
  }
  if (_isInfoSourceEnabled(prefs, QuakeSourceType.cenc)) {
    _backgroundOfficialCenc = officialCenc;
    officialCenc.onListUpdated = (items) => onSourceList('cenc', items);
    officialCenc.start();
  }
  if (_isInfoSourceEnabled(prefs, QuakeSourceType.jma_fan)) {
    _backgroundOfficialJma = officialJma;
    officialJma.onListUpdated = (items) => onSourceList('jma', items);
    officialJma.start();
  }

  await _restoreBackgroundWhews(prefs, manager, whews);

  void stationStatus(String source, bool connected) {
    onSourceStatus(
      SourceStatusUpdate(
        source,
        connected ? SourceStatus.connected : SourceStatus.error,
      ),
    );
  }

  lmoni.onStatusChanged = (connected) => stationStatus('NIED', connected);
  yahoo.onStatusChanged = (connected) => stationStatus('NIED', connected);
  kma.onStatusChanged = (connected) => stationStatus('KMA', connected);
  cwa.onStatusChanged = (connected) => stationStatus('TREM', connected);
  snet.onStatusChanged = (connected) => stationStatus('S-net', connected);
  seisJs.onStatusChanged = (connected) => stationStatus('SeisJS', connected);
  pAlert.onStatusChanged = (connected) => stationStatus('P-Alert', connected);
  kma.onShakeDetected = (value) => onStationData({
    'kind': 'signal',
    'source': 'kma',
    'action': 'detected',
    'value': value,
    'detectedAt': DateTime.now().toUtc().toIso8601String(),
  });
  kma.onShakeExpired = () =>
      onStationData({'kind': 'signal', 'source': 'kma', 'action': 'expired'});
  cwa.onShakeDetected = (value) => onStationData({
    'kind': 'signal',
    'source': 'trem',
    'action': 'detected',
    'value': value,
    'detectedAt': DateTime.now().toUtc().toIso8601String(),
  });
  cwa.onShakeExpired = () =>
      onStationData({'kind': 'signal', 'source': 'trem', 'action': 'expired'});
  pAlert.onShakeDetected = (value) => onStationData({
    'kind': 'signal',
    'source': 'palert',
    'action': 'detected',
    'value': value,
    'detectedAt': DateTime.now().toUtc().toIso8601String(),
  });
  pAlert.onShakeExpired = () => onStationData({
    'kind': 'signal',
    'source': 'palert',
    'action': 'expired',
  });
  whewsNied.stateNotifier.addListener(() {
    onSourceStatus(SourceStatusUpdate('NIED', _whewsState(whewsNied)));
  });
  whewsSnet.stateNotifier.addListener(() {
    onSourceStatus(SourceStatusUpdate('S-net', _whewsState(whewsSnet)));
  });
  whewsKma.stateNotifier.addListener(() {
    onSourceStatus(SourceStatusUpdate('KMA', _whewsState(whewsKma)));
  });

  _backgroundStationSubscriptions.add(
    lmoni.stationStream.listen((stations) {
      if (stations != null) {
        onStationData(
          ForegroundStationPayload.nied(
            stations,
            source: _backgroundNiedSource,
          ),
        );
      }
    }),
  );
  _backgroundStationSubscriptions.add(
    yahoo.stationStream.listen((stations) {
      if (stations != null) {
        onStationData(ForegroundStationPayload.nied(stations, source: 'yahoo'));
      }
    }),
  );
  _backgroundStationSubscriptions.add(
    kma.stationStream.listen((stations) {
      onStationData(
        ForegroundStationPayload.kma(
          stations,
          dataTime: kma.dataTimeNotifier.value,
        ),
      );
    }),
  );
  _backgroundStationSubscriptions.add(
    cwa.stationStream.listen((stations) {
      onStationData(
        ForegroundStationPayload.cwa(
          stations,
          dataTime: cwa.dataTimeNotifier.value,
        ),
      );
    }),
  );
  _backgroundStationSubscriptions.add(
    snet.stationStreamFromCallback.listen((stations) {
      onStationData(ForegroundStationPayload.snet(stations));
    }),
  );
  _backgroundStationSubscriptions.add(
    seisJs.stationStream.listen((stations) {
      onStationData(
        ForegroundStationPayload.seisjs(
          stations,
          dataTime: seisJs.dataTimeNotifier.value,
        ),
      );
    }),
  );
  _backgroundStationSubscriptions.add(
    pAlert.stationStream.listen((stations) {
      onStationData(
        ForegroundStationPayload.palert(
          stations,
          dataTime: pAlert.dataTimeNotifier.value,
          receivedTime: pAlert.receivedTimeNotifier.value,
          detection: pAlert.detectionSnapshot,
        ),
      );
    }),
  );
  pAlert.onDetectionChanged = (snapshot) => onStationData(
    ForegroundStationPayload.palert(
      pAlert.stations,
      dataTime: pAlert.dataTimeNotifier.value,
      receivedTime: pAlert.receivedTimeNotifier.value,
      detection: snapshot,
    ),
  );
  _backgroundStationSubscriptions.add(
    whewsNied.frameStream.listen((frame) {
      onStationData(_whewsNiedPayload(frame));
    }),
  );
  _backgroundStationSubscriptions.add(
    whewsSnet.frameStream.listen((frame) {
      onStationData(_whewsSnetPayload(frame));
    }),
  );
  _backgroundStationSubscriptions.add(
    whewsKma.frameStream.listen((frame) {
      onStationData(_whewsKmaPayload(frame));
    }),
  );

  if (prefs.getBool('api_source_nied_monitor_enabled') ?? true) {
    if (niedSource == 'whews') {
      // The authenticated WHEWS station socket is started below.
    } else if (niedSource == 'yahoo') {
      yahoo.start();
    } else {
      niedMonitor.configureEndpoint(niedSource);
      lmoni.start();
      niedMonitor.start();
    }
  }
  if (prefs.getBool('api_source_kma_pews_enabled') ?? true) {
    final kmaSource = prefs.getString('kma_data_source') ?? 'pews';
    if (kmaSource != 'whews') {
      kma.setConnectionSource(kmaSource);
      kma.setExternalInputEnabled(false);
      kma.connect();
    }
  }
  if (prefs.getBool('trem_station_enabled') ?? true) cwa.start();
  if ((prefs.getBool('api_source_snet_enabled') ?? true) &&
      prefs.getString('snet_data_source') != 'whews')
    snet.startMonitoring();
  if (prefs.getBool('api_source_wolfx_seisjs_enabled') ?? true)
    seisJs.connect();
  if (prefs.getBool('api_source_palert_enabled') ?? true) pAlert.start();
  await _startBackgroundWhewsStationsIfAuthorized(
    prefs,
    whewsNied: whewsNied,
    whewsSnet: whewsSnet,
    whewsKma: whewsKma,
  );

  _backgroundAuxSubscriptions.add(
    lpgm.snapshotStream.listen((snapshot) {
      onStationData(ForegroundStationPayload.lpgm(snapshot));
    }),
  );
  if (prefs.getBool('api_source_nied_lpgm_enabled') ?? true) {
    await lpgm.start(interval: const Duration(seconds: 15));
  }

  _backgroundAuxSubscriptions.add(
    earthScopeStations.stationStream.listen((stations) {
      onStationData(
        ForegroundStationPayload.fdsnStations('EarthScope', stations),
      );
    }),
  );
  _backgroundAuxSubscriptions.add(
    geofonStations.stationStream.listen((stations) {
      onStationData(ForegroundStationPayload.fdsnStations('GEOFON', stations));
    }),
  );
  _backgroundAuxSubscriptions.add(
    fdsnMotion.sampleStream.listen((sample) {
      onStationData(ForegroundStationPayload.fdsnMotion(sample));
    }),
  );
  _backgroundAuxSubscriptions.add(
    fanRadar.frameStream.listen((frame) {
      if (frame != null)
        onStationData(ForegroundStationPayload.fanRadar(frame));
    }),
  );
  _backgroundAuxSubscriptions.add(
    fanSatellite.frameStream.listen((frame) {
      if (frame != null) {
        onStationData(ForegroundStationPayload.fanSatellite(frame));
      }
    }),
  );
  _backgroundAuxSubscriptions.add(
    jmaRadar.frameStream.listen((frame) {
      if (frame != null)
        onStationData(ForegroundStationPayload.jmaRadar(frame));
    }),
  );
  _backgroundAuxSubscriptions.add(
    jmaSatelliteCloud.frameStream.listen((frame) {
      if (frame != null) {
        onStationData(ForegroundStationPayload.jmaSatelliteCloud(frame));
      }
    }),
  );
  _backgroundAuxSubscriptions.add(
    nsmcSatelliteCloud.frameStream.listen((frame) {
      if (frame != null) {
        onStationData(ForegroundStationPayload.nsmcSatelliteCloud(frame));
      }
    }),
  );
  _backgroundAuxSubscriptions.add(
    precipitation.frameStream.listen((frame) {
      if (frame != null) {
        onStationData(ForegroundStationPayload.cmaPrecipitation(frame));
      }
    }),
  );
  volcanoMap.onSitesUpdated = (sites) {
    onStationData(ForegroundStationPayload.volcanoSites(sites));
  };
  typhoon.onActiveTyphoonsChanged = (items) {
    onAuxData({
      'kind': 'typhoon',
      'items': items.map((item) => item.toMap()).toList(growable: false),
    });
  };
  cmaWeather.stateNotifier.addListener(() {
    onAuxData(
      ForegroundStationPayload.cmaWeather(cmaWeather.stateNotifier.value),
    );
  });
  chinaWeather.onLocalAlarmChanged = (alarm) {
    onAuxData({'kind': 'chinaWeatherAlarm', 'alarm': alarm?.toMap()});
  };
  jmaWeather.stateNotifier.addListener(() {
    onAuxData(
      ForegroundStationPayload.jmaWeather(jmaWeather.stateNotifier.value),
    );
  });
  jmaLpgm.latestNotifier.addListener(() {
    onAuxData({'kind': 'jmaLpgm', 'bulletin': jmaLpgm.latest?.toMap()});
  });
  jmaMegaquake.activeNotifier.addListener(() {
    onAuxData({
      'kind': 'jmaMegaquake',
      'items': jmaMegaquake.active
          .map((item) => item.toMap())
          .toList(growable: false),
    });
  });
  final fdsnEnabled =
      prefs.getBool('api_source_fdsn_seedlink_enabled') ?? false;
  final fdsnSources = <String>{
    if (prefs.getBool('map_overlay_fdsnEarthScope') ?? false) 'EarthScope',
    if (prefs.getBool('map_overlay_fdsnGeofon') ?? false) 'GEOFON',
  };
  if (fdsnEnabled && fdsnSources.isNotEmpty) {
    final limit =
        prefs.getInt(FdsnMotionService.stationLimitPreferenceKey) ??
        FdsnMotionService.defaultStationLimit;
    if (fdsnSources.contains('EarthScope')) {
      unawaited(earthScopeStations.start());
    }
    if (fdsnSources.contains('GEOFON')) {
      unawaited(geofonStations.start());
    }
    fdsnMotion.connect(stationLimit: limit, enabledSources: fdsnSources);
  }
  if (prefs.getBool('map_overlay_radarChinaLayer') ?? false) {
    fanRadar.start(interval: FanRadarService.refreshInterval);
  }
  if (prefs.getBool('map_overlay_precipitationChinaLayer') ?? false) {
    precipitation.start(interval: FanRadarService.precipitationRefreshInterval);
  }
  if (prefs.getBool('map_overlay_jmaRadarLayer') ?? false) {
    jmaRadar.start(interval: JmaRadarService.refreshInterval);
  }
  if (prefs.getBool('map_overlay_jmaSatelliteCloudLayer') ?? false) {
    jmaSatelliteCloud.start(interval: JmaSatelliteCloudService.refreshInterval);
  }
  if (prefs.getBool('map_overlay_nsmcSatelliteCloudLayer') ?? false) {
    nsmcSatelliteCloud.start(interval: NsmcSatelliteCloudService.refreshInterval);
  }
  if (prefs.getBool('map_overlay_satelliteCloudLayer') ?? false) {
    fanSatellite.start(interval: const Duration(minutes: 30));
  }
  if (prefs.getBool('map_overlay_volcanoLayer') ?? false) {
    volcanoMap.start();
  }
  if (prefs.getBool('map_overlay_typhoonLayer') ?? false) {
    typhoon.start();
  }
  jmaLpgm.start();
  jmaMegaquake.start();

  if (savedLat != null && savedLng != null) {
    if (LocalWeatherRegion.usesJapan(savedLat, savedLng)) {
      unawaited(jmaWeather.startForLocation(savedLat, savedLng));
    } else if (LocalWeatherRegion.usesChina(savedLat, savedLng)) {
      unawaited(cmaWeather.startForLocation(savedLat, savedLng));
      chinaWeather.setLocalAnchor(savedLat, savedLng);
      chinaWeather.setAdminLevel(
        switch (prefs.getString('weather_alarm_local_level') ?? 'county') {
          'province' => ChinaWeatherAdminLevel.province,
          'city' => ChinaWeatherAdminLevel.city,
          _ => ChinaWeatherAdminLevel.county,
        },
      );
      if (prefs.getBool('weather_alarm_local_only') ?? true) {
        chinaWeather.start(intervalSeconds: 90);
      }
    }
  }

  void configureCmt(String source, void Function() start) {
    if ((prefs.getBool('api_source_${source}_cmt_enabled') ?? true)) {
      start();
    }
  }

  cencCmt.onListUpdated = (items) => onCmtList('cencCmt', items);
  usgsCmt.onListUpdated = (items) => onCmtList('usgsCmt', items);
  jmaCmt.onListUpdated = (items) => onCmtList('jmaCmt', items);
  fnetCmt.onListUpdated = (items) => onCmtList('fnetCmt', items);
  hinetAquaCmt.onListUpdated = (items) => onCmtList('hinetAquaCmt', items);
  configureCmt('cenc', cencCmt.start);
  configureCmt('usgs', usgsCmt.start);
  configureCmt('jma', jmaCmt.start);
  configureCmt('fnet', fnetCmt.start);
  configureCmt('hinet_aqua', hinetAquaCmt.start);

  // 定期清理过期 slot，避免内存无限增长
  _backgroundTimers.add(
    Timer.periodic(const Duration(minutes: 1), (_) {
      processor.prune();
    }),
  );

  if (prefs.getBool(GlobalQuakeService.enabledPreferenceKey) ?? false) {
    globalQuake.connect();
  }

  _backgroundSettings = initialSettings;
}

/// 停止前台服务 isolate 中的所有连接，供服务退出和设置重载使用。
Future<void> stopBackgroundSources() async {
  _backgroundSettings = null;
  _backgroundSeenStatePersistTimer?.cancel();
  _backgroundSeenStatePersistTimer = null;
  for (final timer in _backgroundTimers) {
    timer.cancel();
  }
  _backgroundTimers.clear();
  for (final subscription in _backgroundSubscriptions) {
    await subscription.cancel();
  }
  _backgroundSubscriptions.clear();
  for (final subscription in _backgroundStationSubscriptions) {
    await subscription.cancel();
  }
  _backgroundStationSubscriptions.clear();
  for (final subscription in _backgroundCmtSubscriptions) {
    await subscription.cancel();
  }
  _backgroundCmtSubscriptions.clear();
  for (final subscription in _backgroundAuxSubscriptions) {
    await subscription.cancel();
  }
  _backgroundAuxSubscriptions.clear();
  _backgroundNiedMonitor?.stop();
  if (_backgroundNiedMonitor != null) NiedBackgroundWorker.instance.stop();
  _backgroundLmoni?.stop();
  _backgroundYahoo?.stop();
  _backgroundKma?.disconnect();
  _backgroundCwa?.stop();
  _backgroundSnet?.stopMonitoring();
  _backgroundSeisJs?.disconnect();
  _backgroundPAlert?.stop();
  _backgroundWhewsNied?.stop();
  _backgroundWhewsSnet?.stop();
  _backgroundWhewsKma?.stop();
  _backgroundCencCmt?.stop();
  _backgroundUsgsCmt?.stop();
  _backgroundJmaCmt?.stop();
  _backgroundFnetCmt?.stop();
  _backgroundHinetAquaCmt?.stop();
  _backgroundLpgm?.stop();
  _backgroundEarthScopeStations?.stop();
  _backgroundGeofonStations?.stop();
  _backgroundFdsnMotion?.disconnect();
  _backgroundFanRadar?.stop();
  _backgroundCmaPrecipitation?.stop();
  _backgroundFanSatellite?.stop();
  _backgroundJmaRadar?.stop();
  _backgroundJmaSatelliteCloud?.stop(clear: true);
  _backgroundNsmcSatelliteCloud?.stop(clear: true);
  _backgroundVolcanoMap?.stop();
  _backgroundTyphoon?.stop();
  _backgroundChinaWeather?.stop();
  _backgroundCmaWeather?.dispose();
  _backgroundJmaWeather?.dispose();
  _backgroundJmaLpgm?.dispose();
  _backgroundJmaMegaquake?.dispose();
  _backgroundLmoni = null;
  _backgroundNiedMonitor = null;
  _backgroundYahoo = null;
  _backgroundKma = null;
  _backgroundCwa = null;
  _backgroundSnet = null;
  _backgroundSeisJs = null;
  _backgroundPAlert = null;
  _backgroundWhewsNied = null;
  _backgroundWhewsSnet = null;
  _backgroundWhewsKma = null;
  _backgroundCencCmt = null;
  _backgroundUsgsCmt = null;
  _backgroundJmaCmt = null;
  _backgroundFnetCmt = null;
  _backgroundHinetAquaCmt = null;
  _backgroundLpgm = null;
  _backgroundEarthScopeStations = null;
  _backgroundGeofonStations = null;
  _backgroundFdsnMotion = null;
  _backgroundFanRadar = null;
  _backgroundCmaPrecipitation = null;
  _backgroundFanSatellite = null;
  _backgroundJmaRadar = null;
  _backgroundJmaSatelliteCloud = null;
  _backgroundNsmcSatelliteCloud = null;
  _backgroundVolcanoMap = null;
  _backgroundTyphoon = null;
  _backgroundChinaWeather = null;
  _backgroundCmaWeather = null;
  _backgroundJmaWeather = null;
  _backgroundJmaLpgm = null;
  _backgroundJmaMegaquake = null;
  _backgroundOfficialUsgs?.stop();
  _backgroundOfficialUsgs?.onCurrentUpdated = null;
  _backgroundOfficialUsgs?.onListUpdated = null;
  _backgroundOfficialEmsc?.stop();
  _backgroundOfficialEmsc?.onCurrentUpdated = null;
  _backgroundOfficialEmsc?.onListUpdated = null;
  _backgroundOfficialCwa?.stop();
  _backgroundOfficialCwa?.onCurrentUpdated = null;
  _backgroundOfficialCwa?.onListUpdated = null;
  _backgroundOfficialCenc?.stop();
  _backgroundOfficialCenc?.onListUpdated = null;
  _backgroundOfficialJma?.stop();
  _backgroundOfficialJma?.onListUpdated = null;
  _backgroundOfficialUsgs = null;
  _backgroundOfficialEmsc = null;
  _backgroundOfficialCwa = null;
  _backgroundOfficialCenc = null;
  _backgroundOfficialJma = null;
  _backgroundManager?.getSource<JianService>()?.dispose();
  _backgroundManager?.reset();
  _backgroundManager = null;
  _backgroundEventProcessor = null;
}

SourceStatus _whewsState(WhewsStationService service) {
  return switch (service.stateNotifier.value) {
    WhewsSocketState.connected => SourceStatus.connected,
    WhewsSocketState.connecting => SourceStatus.connecting,
    WhewsSocketState.disconnected => SourceStatus.disconnected,
    WhewsSocketState.unauthorized ||
    WhewsSocketState.error => SourceStatus.error,
  };
}

Map<String, dynamic> _whewsNiedPayload(WhewsStationFrame frame) => {
  'kind': 'whewsNied',
  'dataTime': frame.dataTime.toIso8601String(),
  'coordinates': frame.coordinates
      .map((value) => {'lat': value.latitude, 'lng': value.longitude})
      .toList(growable: false),
  'values': frame.values,
  'pga': frame.pga,
  'pgv': frame.pgv,
};

Map<String, dynamic> _whewsSnetPayload(WhewsStationFrame frame) => {
  'kind': 'whewsSnet',
  'dataTime': frame.dataTime.toIso8601String(),
  'coordinates': frame.coordinates
      .map((value) => {'lat': value.latitude, 'lng': value.longitude})
      .toList(growable: false),
  'values': frame.values,
};

Map<String, dynamic> _whewsKmaPayload(WhewsStationFrame frame) => {
  'kind': 'whewsKma',
  'dataTime': frame.dataTime.toIso8601String(),
  'coordinates': frame.coordinates
      .map((value) => {'lat': value.latitude, 'lng': value.longitude})
      .toList(growable: false),
  'values': frame.values,
};

Future<void> _startBackgroundWhewsStationsIfAuthorized(
  SharedPreferences prefs, {
  required WhewsStationService whewsNied,
  required WhewsStationService whewsSnet,
  required WhewsStationService whewsKma,
  Set<String> only = const {'nied', 'snet', 'kma'},
}) async {
  WAuthCredentials credentials;
  try {
    credentials = await WAuthCredentialStore().readAndMigrate(
      preferences: prefs,
    );
  } catch (_) {
    whewsNied.stop();
    whewsSnet.stop();
    whewsKma.stop();
    debugPrint('WHEWS station credential storage unavailable.');
    return;
  }
  final token = credentials.apiToken.trim();
  final auth = prefs.getBool(WhewsService.enabledPreferenceKey) ?? false;
  whewsNied.setApiToken(token);
  whewsSnet.setApiToken(token);
  whewsKma.setApiToken(token);
  if (token.isEmpty) return;
  if (only.contains('nied') &&
      auth &&
      (prefs.getBool('api_source_nied_monitor_enabled') ?? true) &&
      prefs.getString('nied_data_source') == 'whews' &&
      (prefs.getBool('api_source_whews_nied_enabled') ?? false)) {
    whewsNied.start();
  }
  if (only.contains('snet') &&
      auth &&
      (prefs.getBool('api_source_snet_enabled') ?? true) &&
      prefs.getString('snet_data_source') == 'whews' &&
      (prefs.getBool('api_source_whews_snet_enabled') ?? false)) {
    whewsSnet.start();
  }
  if (only.contains('kma') &&
      auth &&
      (prefs.getBool('api_source_kma_pews_enabled') ?? true) &&
      prefs.getString('kma_data_source') == 'whews' &&
      (prefs.getBool('api_source_whews_kma_station_enabled') ?? false)) {
    whewsKma.start();
  }
}

Future<void> _restoreBackgroundWhews(
  SharedPreferences prefs,
  SourceManager manager,
  WhewsService whews,
) async {
  WAuthCredentials credentials;
  try {
    credentials = await WAuthCredentialStore().readAndMigrate(
      preferences: prefs,
    );
  } catch (_) {
    whews.setApiToken('');
    manager.setSourceEnabled('WHEWS', false);
    debugPrint('WHEWS credential storage unavailable.');
    return;
  }
  whews.setApiToken(credentials.apiToken);
  manager.setSourceEnabled(
    'WHEWS',
    credentials.hasApiToken &&
        (prefs.getBool(WhewsService.enabledPreferenceKey) ?? false),
  );
}

bool _isInfoSourceEnabled(SharedPreferences prefs, QuakeSourceType source) {
  return (prefs.getDouble('source_mag_filter_${source.name}') ?? 0) >= 0;
}

Map<String, DateTime> _readSeenRows(
  SharedPreferences prefs,
  String preferenceKey,
  Duration ttl,
) {
  final now = DateTime.now().toUtc();
  final result = <String, DateTime>{};
  for (final row in prefs.getStringList(preferenceKey) ?? const <String>[]) {
    final separator = row.lastIndexOf('|');
    if (separator <= 0 || separator >= row.length - 1) continue;
    final seenMilliseconds = int.tryParse(row.substring(separator + 1));
    if (seenMilliseconds == null) continue;
    final seenAt = DateTime.fromMillisecondsSinceEpoch(
      seenMilliseconds,
      isUtc: true,
    );
    if (now.difference(seenAt) <= ttl) {
      result[row.substring(0, separator)] = seenAt;
    }
  }
  return result;
}

Future<void> _persistBackgroundSeenState(
  SharedPreferences prefs,
  BackgroundEventProcessor processor,
) async {
  // SharedPreferences 在不同 isolate 中各自缓存，合并前必须刷新磁盘状态。
  await prefs.reload();
  await _persistSeenRows(
    prefs,
    BackgroundEventProcessor.seenUsgsInfoBodyKeysPreferenceKey,
    processor.seenUsgsInfoBodyKeys,
    const Duration(hours: 24),
  );
  await _persistSeenRows(
    prefs,
    BackgroundEventProcessor.seenEmscInfoBodyKeysPreferenceKey,
    processor.seenEmscInfoBodyKeys,
    const Duration(hours: 24),
  );
  await _persistSeenRows(
    prefs,
    BackgroundEventProcessor.seenCwaInfoBodyKeysPreferenceKey,
    processor.seenCwaInfoBodyKeys,
    const Duration(hours: 24),
  );
  await _persistSeenRows(
    prefs,
    BackgroundEventProcessor.seenNoUpdateInfoEventsPreferenceKey,
    processor.seenNoUpdateInfoEvents,
    const Duration(hours: 48),
    maxEntries: 500,
  );
  await _persistSeenRows(
    prefs,
    BackgroundEventProcessor.seenUnifiedInfoEventsPreferenceKey,
    processor.seenUnifiedInfoEvents,
    const Duration(hours: 48),
    maxEntries: 1000,
  );
  await _persistAcceptedEewRows(prefs, processor.acceptedEewReportNums);
}

Future<void> _persistSeenRows(
  SharedPreferences prefs,
  String preferenceKey,
  Map<String, DateTime> processorValues,
  Duration ttl, {
  int? maxEntries,
}) async {
  final merged = _readSeenRows(prefs, preferenceKey, ttl)
    ..addAll(processorValues);
  var entries = merged.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  if (maxEntries != null && entries.length > maxEntries) {
    entries = entries.sublist(entries.length - maxEntries);
  }
  await prefs.setStringList(
    preferenceKey,
    entries
        .map((entry) => '${entry.key}|${entry.value.millisecondsSinceEpoch}')
        .toList(growable: false),
  );
}

Map<String, int> _readAcceptedEewRows(SharedPreferences prefs) {
  return _readAcceptedEewStates(
    prefs,
  ).map((key, value) => MapEntry(key, value.reportNum));
}

Map<String, _AcceptedEewState> _readAcceptedEewStates(SharedPreferences prefs) {
  final now = DateTime.now().toUtc();
  final result = <String, _AcceptedEewState>{};
  final rows =
      prefs.getStringList(
        BackgroundEventProcessor.acceptedEewReportNumsPreferenceKey,
      ) ??
      const <String>[];
  for (final row in rows) {
    final timeSeparator = row.lastIndexOf('|');
    if (timeSeparator <= 0 || timeSeparator >= row.length - 1) continue;
    final reportSeparator = row.lastIndexOf('|', timeSeparator - 1);
    if (reportSeparator <= 0) continue;
    final reportNum = int.tryParse(
      row.substring(reportSeparator + 1, timeSeparator),
    );
    final seenMilliseconds = int.tryParse(row.substring(timeSeparator + 1));
    if (reportNum == null || seenMilliseconds == null) continue;
    final seenAt = DateTime.fromMillisecondsSinceEpoch(
      seenMilliseconds,
      isUtc: true,
    );
    if (now.difference(seenAt) <= const Duration(hours: 24)) {
      final key = row.substring(0, reportSeparator);
      final previous = result[key];
      if (previous == null ||
          reportNum > previous.reportNum ||
          (reportNum == previous.reportNum &&
              seenAt.isAfter(previous.seenAt))) {
        result[key] = _AcceptedEewState(reportNum, seenAt);
      }
    }
  }
  return result;
}

Future<void> _persistAcceptedEewRows(
  SharedPreferences prefs,
  Map<String, int> processorValues,
) async {
  final merged = _readAcceptedEewStates(prefs);
  final now = DateTime.now().toUtc();
  for (final entry in processorValues.entries) {
    final previous = merged[entry.key];
    if (previous == null || entry.value > previous.reportNum) {
      merged[entry.key] = _AcceptedEewState(entry.value, now);
    }
  }
  final entries = merged.entries.toList()
    ..sort((a, b) => a.value.seenAt.compareTo(b.value.seenAt));
  if (entries.length > 100) {
    entries.removeRange(0, entries.length - 100);
  }
  await prefs.setStringList(
    BackgroundEventProcessor.acceptedEewReportNumsPreferenceKey,
    entries
        .map(
          (entry) =>
              '${entry.key}|${entry.value.reportNum}|${entry.value.seenAt.millisecondsSinceEpoch}',
        )
        .toList(growable: false),
  );
}

class _AcceptedEewState {
  const _AcceptedEewState(this.reportNum, this.seenAt);

  final int reportNum;
  final DateTime seenAt;
}

/// 处理统一事件：先经过 [BackgroundEventProcessor] 统一过滤/合并，
/// 只把已接纳结果交给服务回调；后台系统通知由服务处理，UI 效果交给主 isolate。
void _handleUnifiedEvent(
  UnifiedQuakeData event,
  BackgroundEventProcessor processor,
  void Function(UnifiedQuakeData event, bool isUpdate) onUnifiedEvent,
) {
  final result = processor.process(event);
  if (result.type == BackgroundEventResultType.dropped ||
      result.event == null) {
    return;
  }

  onUnifiedEvent(result.event!, result.isUpdate);
}
