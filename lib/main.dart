import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        debugPrintThrottled,
        defaultTargetPlatform,
        kIsWeb,
        kReleaseMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/quake_provider.dart';
import 'providers/map_state_provider.dart';
import 'providers/notification_settings_provider.dart';
import 'providers/background_settings_provider.dart';
import 'providers/page_background_provider.dart';
import 'screens/main_screen.dart';
import 'widgets/map/map_config.dart';
import 'core/frame_rate_limiter.dart';
import 'core/nied_replay_logger.dart';
import 'services/database_helper.dart';
import 'services/ntp_service.dart';
import 'services/desktop_init.dart';
import 'services/location_service.dart';
import 'services/background_service.dart';
import 'services/tts_service.dart';
import 'services/sound_effect_service.dart';
import 'services/obs_automation_runtime_service.dart';
import 'services/wauth_service.dart';
import 'services/wauth_credential_store.dart';
import 'services/sources/source_manager.dart';
import 'services/sources/wolfx_service.dart';
import 'services/sources/whews_service.dart';
import 'services/sources/jian_service.dart';
import 'services/sources/fan_service.dart';
import 'services/sources/nowquake_cenc_intensity_service.dart';
import 'services/sources/p2pquake_service.dart';
import 'services/sources/mock_input_service.dart';
import 'services/sources/global_quake_service.dart';
import 'services/sources/fdsn_motion_service.dart';
import 'services/debug/local_inject_server.dart';
import 'services/sources/china_weather_alert_map_service.dart';
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

const String _fanZxyCacheMigrationKey = 'fan_zxy_tile_cache_cleared_20260822';

void _configureImageCache() {
  final cache = PaintingBinding.instance.imageCache;
  if (_isMobilePlatform) {
    cache.maximumSize = 256;
    cache.maximumSizeBytes = 64 * 1024 * 1024;
    return;
  }
  // Desktop GIF inject + map tiles otherwise keep the Flutter defaults
  // (1000 / 100MB) and leave RSS elevated after long tests.
  cache.maximumSize = 320;
  cache.maximumSizeBytes = 80 * 1024 * 1024;
}

Future<void> _clearLegacyFanTileCacheOnce(SharedPreferences prefs) async {
  if (prefs.getBool(_fanZxyCacheMigrationKey) ?? false) return;
  final cache = PaintingBinding.instance.imageCache;
  cache.clear();
  cache.clearLiveImages();
  await prefs.setBool(_fanZxyCacheMigrationKey, true);
}

void _startDeferredServices(
  SharedPreferences prefs,
  GlobalQuakeService globalQuake,
  WhewsService whews,
  WAuthCredentials whewsCredentials,
) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(SoundEffectService().warmUp());
    unawaited(() async {
      // A saved/manual location is restored before this callback. Only new
      // mobile installs need an automatic request after the first UI frame.
      if (_isMobilePlatform && LocationService().currentPosition == null) {
        unawaited(LocationService().requestCurrentPosition());
      }

      // Epicenter bins + travel times load on first use (see getFEName /
      // TravelTimeService.ensureLoaded) to keep steady-state RAM lower.
      if (!BackgroundService().isAndroidConnectionHostedByForegroundService) {
        SourceManager().startAll();
      }
      unawaited(_verifyAndEnableWhews(prefs, whews, whewsCredentials));
      if (!BackgroundService().isAndroidConnectionHostedByForegroundService &&
          (prefs.getBool(GlobalQuakeService.enabledPreferenceKey) ?? false)) {
        globalQuake.connect();
      }

      // NTP 网络对时与本地注入服务延迟 2 秒后台启动，彻底释放冷启动 CPU
      Timer(const Duration(seconds: 2), () {
        NtpService().startPeriodicSync();
        unawaited(LocalInjectServer.startIfEnabled(prefs: prefs));
      });

      if (!kIsWeb) {
        try {
          await DatabaseHelper().database;
          Timer(const Duration(seconds: 4), () {
            unawaited(DatabaseHelper().cleanOldData());
          });
        } catch (e) {
          debugPrint('Deferred database init failed: $e');
        }
      }
    }());
  });
}

Future<void> _verifyAndEnableWhews(
  SharedPreferences prefs,
  WhewsService whews,
  WAuthCredentials credentials,
) async {
  final hasRequestedWhews =
      (prefs.getBool(WhewsService.enabledPreferenceKey) ?? false) ||
      (prefs.getBool(QuakeMapView.whewsNiedEnabledPreferenceKey) ?? false) ||
      (prefs.getBool(QuakeMapView.whewsSnetEnabledPreferenceKey) ?? false) ||
      (prefs.getBool(QuakeMapView.whewsKmaEnabledPreferenceKey) ?? false);
  if (!hasRequestedWhews || !credentials.isComplete) {
    await prefs.setBool(WhewsService.apiAuthorizedPreferenceKey, false);
    SourceManager().setSourceEnabled('WHEWS', false);
    return;
  }

  final auth = WAuthService();
  final previousApiAuthorized =
      prefs.getBool(WhewsService.apiAuthorizedPreferenceKey) ?? false;
  try {
    final status = await auth.inspectStoredAuthorization(preferences: prefs);
    if (status.credentials.accessToken != credentials.accessToken ||
        status.credentials.apiToken != credentials.apiToken) {
      return;
    }

    if (status.shouldForgetLogin) {
      await prefs.setBool(WhewsService.apiAuthorizedPreferenceKey, false);
      SourceManager().setSourceEnabled('WHEWS', false);
      whews.setApiToken('');
      QuakeMapView.whewsApiTokenNotifier.value = '';
      QuakeMapView.whewsNiedEnabledNotifier.value = false;
      QuakeMapView.whewsSnetEnabledNotifier.value = false;
      QuakeMapView.whewsKmaEnabledNotifier.value = false;
      return;
    }

    if (status.accessAuthorized && status.userInfo != null) {
      await prefs.setString(
        WAuthService.userInfoPreferenceKey,
        jsonEncode(status.userInfo),
      );
    }

    if (status.apiAuthorized) {
      await prefs.setBool(WhewsService.apiAuthorizedPreferenceKey, true);
      whews.setApiToken(status.credentials.apiToken);
      QuakeMapView.whewsApiTokenNotifier.value = status.credentials.apiToken;
      QuakeMapView.whewsNiedEnabledNotifier.value =
          prefs.getBool(QuakeMapView.whewsNiedEnabledPreferenceKey) ?? false;
      QuakeMapView.whewsSnetEnabledNotifier.value =
          prefs.getBool(QuakeMapView.whewsSnetEnabledPreferenceKey) ?? false;
      QuakeMapView.whewsKmaEnabledNotifier.value =
          prefs.getBool(QuakeMapView.whewsKmaEnabledPreferenceKey) ?? false;
      SourceManager().setSourceEnabled(
        'WHEWS',
        prefs.getBool(WhewsService.enabledPreferenceKey) ?? false,
      );
      return;
    }

    if (status.hasTransientVerificationFailure && previousApiAuthorized) {
      whews.setApiToken(credentials.apiToken);
      QuakeMapView.whewsApiTokenNotifier.value = credentials.apiToken;
      QuakeMapView.whewsNiedEnabledNotifier.value =
          prefs.getBool(QuakeMapView.whewsNiedEnabledPreferenceKey) ?? false;
      QuakeMapView.whewsSnetEnabledNotifier.value =
          prefs.getBool(QuakeMapView.whewsSnetEnabledPreferenceKey) ?? false;
      QuakeMapView.whewsKmaEnabledNotifier.value =
          prefs.getBool(QuakeMapView.whewsKmaEnabledPreferenceKey) ?? false;
      SourceManager().setSourceEnabled(
        'WHEWS',
        prefs.getBool(WhewsService.enabledPreferenceKey) ?? false,
      );
      return;
    }

    await prefs.setBool(WhewsService.apiAuthorizedPreferenceKey, false);
    SourceManager().setSourceEnabled('WHEWS', false);
    whews.setApiToken('');
    QuakeMapView.whewsApiTokenNotifier.value = '';
    QuakeMapView.whewsNiedEnabledNotifier.value = false;
    QuakeMapView.whewsSnetEnabledNotifier.value = false;
    QuakeMapView.whewsKmaEnabledNotifier.value = false;
  } catch (error) {
    if (previousApiAuthorized && credentials.isComplete) {
      whews.setApiToken(credentials.apiToken);
      QuakeMapView.whewsApiTokenNotifier.value = credentials.apiToken;
      QuakeMapView.whewsNiedEnabledNotifier.value =
          prefs.getBool(QuakeMapView.whewsNiedEnabledPreferenceKey) ?? false;
      QuakeMapView.whewsSnetEnabledNotifier.value =
          prefs.getBool(QuakeMapView.whewsSnetEnabledPreferenceKey) ?? false;
      QuakeMapView.whewsKmaEnabledNotifier.value =
          prefs.getBool(QuakeMapView.whewsKmaEnabledPreferenceKey) ?? false;
      SourceManager().setSourceEnabled(
        'WHEWS',
        prefs.getBool(WhewsService.enabledPreferenceKey) ?? false,
      );
      debugPrint('WHEWS startup authorization kept cached: $error');
      return;
    }
    await prefs.setBool(WhewsService.apiAuthorizedPreferenceKey, false);
    SourceManager().setSourceEnabled('WHEWS', false);
    whews.setApiToken('');
    QuakeMapView.whewsApiTokenNotifier.value = '';
    QuakeMapView.whewsNiedEnabledNotifier.value = false;
    QuakeMapView.whewsSnetEnabledNotifier.value = false;
    QuakeMapView.whewsKmaEnabledNotifier.value = false;
    debugPrint('WHEWS startup authorization check failed: $error');
  } finally {
    auth.close();
  }
}

Widget _buildPlatformSemanticsWrapper(BuildContext context, Widget? child) {
  final app = child ?? const SizedBox.shrink();
  if (!_disableWindowsAccessibilitySemantics) return app;
  return ExcludeSemantics(child: app);
}

void main() async {
  RhythmFrameRateBinding.ensureInitialized();
  _configureImageCache();

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

  // 2. 基础服务初始化（已在 _startDeferredServices 延迟异步启动）
  if (!kIsWeb) {}

  // 2.5 加载持久化设置
  final prefs = await SharedPreferences.getInstance();
  await _clearLegacyFanTileCacheOnce(prefs);
  WAuthCredentials whewsCredentials;
  try {
    whewsCredentials = await WAuthCredentialStore().readAndMigrate(
      preferences: prefs,
    );
  } catch (error) {
    whewsCredentials = const WAuthCredentials();
    await prefs.setBool(WhewsService.apiAuthorizedPreferenceKey, false);
    debugPrint('WAuth secure credential load failed: $error');
  }
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
  final whews = WhewsService(apiToken: '');
  final jian = JianService();
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
  globalQuake.configureFirstReportMagnitudeFilter(
    prefs.getDouble(
          GlobalQuakeService.firstReportMagnitudeThresholdPreferenceKey,
        ) ??
        0,
  );
  SourceManager().registerSource(wolfx);
  SourceManager().registerSource(whews);
  SourceManager().registerSource(jian);
  SourceManager().setSourceEnabled(jian.name,
    prefs.getBool(JianService.enabledPreferenceKey) ?? false);
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
  SourceManager().setSourceEnabled('WHEWS', false);
  SourceManager().setSourceEnabled(
    'P2P',
    prefs.getBool('api_source_p2pquake_enabled') ?? true,
  );
  _startDeferredServices(prefs, globalQuake, whews, whewsCredentials);

  // 4. 桌面端窗口初始化（Web 自动跳过）
  await initDesktopWindow();

  final notificationSettings = NotificationSettingsProvider();
  await notificationSettings.load(prefs);

  final backgroundSettings = BackgroundSettingsProvider();
  await backgroundSettings.load(prefs);
  final pageBackground = PageBackgroundProvider();
  await pageBackground.load(prefs);
  await BackgroundService().initialize(
    WidgetsBinding.instance,
    settings: backgroundSettings,
  );
  // 配置 Android 前台服务；非 Android 平台自动跳过。
  await BackgroundService().configureForegroundService();
  await ObsAutomationRuntimeService().initialize(preferences: prefs);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => _createQuakeProvider(prefs)),
        ChangeNotifierProvider(
          create: (_) => _createMapStateProvider(tileKey, prefs),
        ),
        ChangeNotifierProvider.value(value: notificationSettings),
        ChangeNotifierProvider.value(value: backgroundSettings),
        ChangeNotifierProvider.value(value: pageBackground),
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
    if (prefs.containsKey(key)) {
      final val = prefs.getDouble(key) ?? 0;
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
    'jmaRadarLayer',
    prefs.getBool('map_overlay_jmaRadarLayer') ?? false,
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
    'cnFault',
    prefs.getBool('map_overlay_cnFault') ?? false,
  );
  provider.setOverlayEnabled(
    'jpFault',
    prefs.getBool('map_overlay_jpFault') ?? false,
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
    'weatherStationLayer',
    prefs.getBool('map_overlay_weatherStationLayer') ?? false,
  );
  final weatherAlertEnabled =
      prefs.getBool('map_overlay_weatherAlertLayer') ?? true;
  provider.setOverlayEnabled('weatherAlertLayer', weatherAlertEnabled);
  if (weatherAlertEnabled) {
    ChinaWeatherAlertMapService().start();
  }
  provider.setWeatherStationMode(
    prefs.getString('map_overlay_weatherStationMode') ?? 'auto',
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
