import 'dart:async';

import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        debugPrintThrottled,
        defaultTargetPlatform,
        kIsWeb,
        kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/quake_provider.dart';
import 'providers/map_state_provider.dart';
import 'providers/notification_settings_provider.dart';
import 'providers/background_settings_provider.dart';
import 'screens/main_screen.dart';
import 'widgets/map/map_config.dart';
import 'core/frame_rate_limiter.dart';
import 'core/nied_replay_logger.dart';
import 'core/travel_time_service.dart';
import 'services/database_helper.dart';
import 'services/ntp_service.dart';
import 'services/desktop_init.dart';
import 'services/location_service.dart';
import 'services/background_service.dart';
import 'services/epicenter_region_service.dart';
import 'services/tts_service.dart';
import 'services/wauth_service.dart';
import 'services/sources/source_manager.dart';
import 'services/sources/wolfx_service.dart';
import 'services/sources/whews_service.dart';
import 'services/sources/fan_service.dart';
import 'services/sources/nowquake_cenc_intensity_service.dart';
import 'services/sources/p2pquake_service.dart';
import 'services/sources/mock_input_service.dart';
import 'services/sources/global_quake_service.dart';
import 'services/sources/fdsn_motion_service.dart';
import 'widgets/map/quake_map_view.dart';
import 'widgets/ui/ui_runtime_flags.dart';

bool _shouldDropLogMessage(String message) {
  return message.contains('accessibility_bridge') ||
      message.contains('AXTree') ||
      message.contains('Nodes left pending by the update') ||
      message.contains('_RawReceivePort._handleMessage') ||
      message.contains('dart:isolate-patch') ||
      message.contains('dart:ui/hooks');
}

bool get _disableWindowsAccessibilitySemantics =>
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.windows &&
    !const bool.fromEnvironment('RQ_ENABLE_ACCESSIBILITY_SEMANTICS');

bool get _isMobilePlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

Future<void> _preferInitialMobileLandscape() async {
  if (!_isMobilePlatform) return;
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
}

void _configureMobileImageCache() {
  if (!_isMobilePlatform) return;
  final cache = PaintingBinding.instance.imageCache;
  cache.maximumSize = 256;
  cache.maximumSizeBytes = 64 * 1024 * 1024;
}

void _releaseMobileOrientationAfterFirstFrame() {
  if (!_isMobilePlatform) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  });
}

void _startDeferredServices(
  SharedPreferences prefs,
  GlobalQuakeService globalQuake,
) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(() async {
      // A saved/manual location is restored before this callback. Only new
      // mobile installs need an automatic request after the first UI frame.
      if (_isMobilePlatform && LocationService().currentPosition == null) {
        unawaited(LocationService().requestCurrentPosition());
      }

      if (!kIsWeb) {
        try {
          await DatabaseHelper().database;
          unawaited(DatabaseHelper().cleanOldData());
        } catch (e) {
          debugPrint('Deferred database init failed: $e');
        }
      }

      await EpicenterRegionService.instance.load();
      unawaited(TravelTimeService().load());
      SourceManager().startAll();
      if (prefs.getBool(GlobalQuakeService.enabledPreferenceKey) ?? false) {
        globalQuake.connect();
      }
    }());
  });
}

Widget _buildPlatformSemanticsWrapper(BuildContext context, Widget? child) {
  final app = child ?? const SizedBox.shrink();
  if (!_disableWindowsAccessibilitySemantics) return app;
  return ExcludeSemantics(child: app);
}

void main() async {
  RhythmFrameRateBinding.ensureInitialized();
  _configureMobileImageCache();

  FlutterError.onError = (details) {
    final msg = details.exceptionAsString();
    if (_shouldDropLogMessage(msg)) return;
    FlutterError.presentError(details);
  };

  debugPrint = (String? message, {int? wrapWidth}) {
    if (message == null) return;
    if (_shouldDropLogMessage(message)) return;
    if (kReleaseMode) return;
    debugPrintThrottled(message, wrapWidth: wrapWidth);
  };

  // 1. 桌面端数据库初始化（Web 自动跳过——条件导入走 stub）
  initDesktopDatabase();

  // 2. 基础服务初始化
  if (!kIsWeb) {}

  // 启动 NTP 同步
  NtpService().startPeriodicSync();

  // 加载走时表

  // 初始化位置服务

  // 2.5 加载持久化设置
  final prefs = await SharedPreferences.getInstance();
  await TtsService().init();
  final savedLat = prefs.getDouble('map_view_lat');
  final savedLng = prefs.getDouble('map_view_lng');
  if (savedLat != null && savedLng != null) {
    LocationService().setCurrentLatLng(savedLat, savedLng);
  }
  NiedReplayLogger.instance.loadPreferencesFrom(prefs);
  UiRuntimeFlags.weatherMarqueeEnabledNotifier.value =
      prefs.getBool('weather_marquee_enabled') ?? false;
  UiRuntimeFlags.niedHypCurvePanelVisibleNotifier.value =
      prefs.getBool(UiRuntimeFlags.niedHypCurvePanelVisiblePreferenceKey) ??
      false;
  MapConfig.configureMapbox(
    username:
        prefs.getString(MapConfig.mapboxUsernameKey) ??
        MapConfig.mapboxUsername,
    styleId:
        prefs.getString(MapConfig.mapboxStyleIdKey) ?? MapConfig.mapboxStyleId,
    accessToken: prefs.getString(MapConfig.mapboxAccessTokenKey) ?? '',
  );
  await prefs.remove('tencent_wmts_api_key');
  await prefs.remove('tencent_wmts_secret_key');
  final fanServerIndex = prefs.getInt('fan_default_server_index') ?? 0;
  final savedTileKey = prefs.getString('tile_key') ?? 'petalLight';
  final tileKey = MapConfig.normalizeBaseTileKey(savedTileKey);
  if (tileKey != savedTileKey) {
    await prefs.setString('tile_key', tileKey);
  }
  final fdsnStationLimit = FdsnMotionService.normalizeStationLimit(
    prefs.getInt(FdsnMotionService.stationLimitPreferenceKey) ??
        FdsnMotionService.defaultStationLimit,
  );
  QuakeMapView.fdsnStationLimitNotifier.value = fdsnStationLimit;
  FdsnMotionService().targetStationLimitNotifier.value = fdsnStationLimit;

  // 3. 注册并启动地震数据源
  final wolfx = WolfxService();
  final whews = WhewsService(
    apiToken: prefs.getString(WAuthService.apiTokenPreferenceKey) ?? '',
  );
  final fan = FanService(
    apiKey: prefs.getString(FanService.apiKeyPreferenceKey) ?? '',
  );
  final nowQuakeCencIr = NowQuakeCencIntensityService();
  final nowQuakeCencIrEnabled =
      prefs.getBool(NowQuakeCencIntensityService.preferenceKey) ?? true;
  fan.setCencIrRequestsEnabled(!nowQuakeCencIrEnabled);
  fan.setDefaultServerIndex(fanServerIndex);
  final p2p = P2PQuakeService();
  final mock = MockInputService();
  final globalQuake = GlobalQuakeService();
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
  SourceManager().registerSource(wolfx);
  SourceManager().registerSource(whews);
  SourceManager().registerSource(fan);
  SourceManager().registerSource(nowQuakeCencIr);
  SourceManager().registerSource(p2p);
  SourceManager().registerSource(mock);
  SourceManager().registerSource(globalQuake);
  SourceManager().setSourceEnabled(
    'FAN',
    prefs.getBool('api_source_fan_enabled') ?? true,
  );
  SourceManager().setSourceEnabled(nowQuakeCencIr.name, nowQuakeCencIrEnabled);
  SourceManager().setSourceEnabled(
    'Wolfx',
    prefs.getBool('api_source_wolfx_enabled') ?? true,
  );
  SourceManager().setSourceEnabled(
    'WHEWS',
    (prefs.getBool(WhewsService.enabledPreferenceKey) ?? false) &&
        (prefs.getBool(WhewsService.apiAuthorizedPreferenceKey) ?? false) &&
        (prefs.getString(WAuthService.accessTokenPreferenceKey) ?? '')
            .trim()
            .isNotEmpty &&
        (prefs.getString(WAuthService.apiTokenPreferenceKey) ?? '')
            .trim()
            .isNotEmpty,
  );
  SourceManager().setSourceEnabled(
    'P2P',
    prefs.getBool('api_source_p2pquake_enabled') ?? true,
  );
  _startDeferredServices(prefs, globalQuake);

  // 4. 桌面端窗口初始化（Web 自动跳过）
  initDesktopWindow();

  final notificationSettings = NotificationSettingsProvider();
  await notificationSettings.load(prefs);

  final backgroundSettings = BackgroundSettingsProvider();
  await backgroundSettings.load(prefs);
  await BackgroundService().initialize(
    WidgetsBinding.instance,
    settings: backgroundSettings,
  );
  // 配置 Android 前台服务；非 Android 平台自动跳过。
  await BackgroundService().configureForegroundService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => _createQuakeProvider(prefs)),
        ChangeNotifierProvider(
          create: (_) => _createMapStateProvider(tileKey, prefs),
        ),
        ChangeNotifierProvider.value(value: notificationSettings),
        ChangeNotifierProvider.value(value: backgroundSettings),
      ],
      child: const RhythmQuakeApp(),
    ),
  );
}

QuakeProvider _createQuakeProvider(SharedPreferences prefs) {
  final provider = QuakeProvider();
  provider.setTyphoonLayerEnabled(
    prefs.getBool('map_overlay_typhoonLayer') ?? false,
  );
  for (final source in QuakeProvider.infoMagFilterSources) {
    final key = 'source_mag_filter_${source.name}';
    final val = prefs.getDouble(key) ?? 0;
    if (val != 0) {
      provider.setSourceInfoMagFilter(source, val);
    }
  }
  return provider;
}

MapStateProvider _createMapStateProvider(
  String tileKey,
  SharedPreferences prefs,
) {
  final provider = MapStateProvider();
  provider.setTileKey(tileKey);
  provider.setPreferredViewMode(
    prefs.getString(MapStateProvider.preferredViewModeKey),
    persist: false,
  );
  provider.setOverlayEnabled(
    'cloudLayer',
    prefs.getBool('map_overlay_cloudLayer') ?? false,
  );
  provider.setOverlayEnabled(
    'windLayer',
    prefs.getBool('map_overlay_windLayer') ?? false,
  );
  provider.setOverlayEnabled(
    'rainLayer',
    prefs.getBool('map_overlay_rainLayer') ?? false,
  );
  provider.setOverlayEnabled(
    'radarChinaLayer',
    prefs.getBool('map_overlay_radarChinaLayer') ?? false,
  );
  provider.setOverlayEnabled(
    'satelliteCloudLayer',
    prefs.getBool('map_overlay_satelliteCloudLayer') ?? false,
  );
  provider.setOverlayEnabled(
    'cnContour',
    prefs.getBool('map_overlay_cnContour') ?? false,
  );
  provider.setOverlayEnabled(
    'volcanoLayer',
    prefs.getBool('map_overlay_volcanoLayer') ?? false,
  );
  provider.setOverlayEnabled(
    'typhoonLayer',
    prefs.getBool('map_overlay_typhoonLayer') ?? false,
  );
  provider.setOverlayEnabled(
    'fdsnEarthScope',
    prefs.getBool('map_overlay_fdsnEarthScope') ?? false,
  );
  provider.setOverlayEnabled(
    'fdsnGeofon',
    prefs.getBool('map_overlay_fdsnGeofon') ?? false,
  );
  provider.setShowEstimatedEpicenter(
    prefs.getBool('show_estimated_epicenter') ?? false,
  );
  return provider;
}

class RhythmQuakeApp extends StatefulWidget {
  const RhythmQuakeApp({super.key});

  @override
  State<RhythmQuakeApp> createState() => _RhythmQuakeAppState();
}

class _RhythmQuakeAppState extends State<RhythmQuakeApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onStateChange: BackgroundService().onLifecycleStateChanged,
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RhythmQuake',
      debugShowCheckedModeBanner: false,
      builder: _buildPlatformSemanticsWrapper,
      theme:
          ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF0A0A0A),
            useMaterial3: true,
          ).copyWith(
            textTheme: ThemeData.dark().textTheme.apply(
              fontFamily: 'MPLUSRounded1c',
            ),
          ),
      home: const MainScreen(),
    );
  }
}
