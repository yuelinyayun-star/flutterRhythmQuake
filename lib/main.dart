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
import 'screens/main_screen.dart';
import 'widgets/map/map_config.dart';
import 'core/frame_rate_limiter.dart';
import 'core/nied_replay_logger.dart';
import 'core/travel_time_service.dart';
import 'services/database_helper.dart';
import 'services/ntp_service.dart';
import 'services/desktop_init.dart';
import 'services/sources/source_manager.dart';
import 'services/sources/wolfx_service.dart';
import 'services/sources/fan_service.dart';
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
      if (!kIsWeb) {
        try {
          await DatabaseHelper().database;
          unawaited(DatabaseHelper().cleanOldData());
        } catch (e) {
          debugPrint('Deferred database init failed: $e');
        }
      }

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
  await _preferInitialMobileLandscape();

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
  NiedReplayLogger.instance.loadPreferencesFrom(prefs);
  UiRuntimeFlags.weatherMarqueeEnabledNotifier.value =
      prefs.getBool('weather_marquee_enabled') ?? false;
  MapConfig.configureMapbox(
    username:
        prefs.getString(MapConfig.mapboxUsernameKey) ??
        MapConfig.mapboxUsername,
    styleId:
        prefs.getString(MapConfig.mapboxStyleIdKey) ?? MapConfig.mapboxStyleId,
    accessToken: prefs.getString(MapConfig.mapboxAccessTokenKey) ?? '',
  );
  MapConfig.configureTencentWmts(
    apiKey: prefs.getString(MapConfig.tencentWmtsApiKeyKey) ?? '',
    secretKey: prefs.getString(MapConfig.tencentWmtsSecretKeyKey) ?? '',
  );
  final fanServerIndex = prefs.getInt('fan_default_server_index') ?? 0;
  final tileKey = prefs.getString('tile_key') ?? 'petalLight';
  final fdsnStationLimit = FdsnMotionService.normalizeStationLimit(
    prefs.getInt(FdsnMotionService.stationLimitPreferenceKey) ??
        FdsnMotionService.defaultStationLimit,
  );
  QuakeMapView.fdsnStationLimitNotifier.value = fdsnStationLimit;
  FdsnMotionService().targetStationLimitNotifier.value = fdsnStationLimit;

  // 3. 注册并启动地震数据源
  final wolfx = WolfxService();
  final fan = FanService();
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
  SourceManager().registerSource(fan);
  SourceManager().registerSource(p2p);
  SourceManager().registerSource(mock);
  SourceManager().registerSource(globalQuake);
  _startDeferredServices(prefs, globalQuake);

  // 4. 桌面端窗口初始化（Web 自动跳过）
  initDesktopWindow();

  _releaseMobileOrientationAfterFirstFrame();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => _createQuakeProvider(prefs)),
        ChangeNotifierProvider(
          create: (_) => _createMapStateProvider(tileKey, prefs),
        ),
      ],
      child: const RhythmQuakeApp(),
    ),
  );
}

QuakeProvider _createQuakeProvider(SharedPreferences prefs) {
  final provider = QuakeProvider();
  provider.setTyphoonLayerEnabled(
    prefs.getBool('map_overlay_typhoonLayer') ?? true,
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
    'cnContour',
    prefs.getBool('map_overlay_cnContour') ?? false,
  );
  provider.setOverlayEnabled(
    'volcanoLayer',
    prefs.getBool('map_overlay_volcanoLayer') ?? false,
  );
  provider.setOverlayEnabled(
    'typhoonLayer',
    prefs.getBool('map_overlay_typhoonLayer') ?? true,
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

class RhythmQuakeApp extends StatelessWidget {
  const RhythmQuakeApp({super.key});

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
