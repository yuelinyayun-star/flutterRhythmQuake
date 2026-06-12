import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/quake_provider.dart';
import 'providers/map_state_provider.dart';
import 'screens/main_screen.dart';
import 'core/travel_time_service.dart';
import 'services/database_helper.dart';
import 'services/location_service.dart';
import 'services/ntp_service.dart';
import 'services/desktop_init.dart';
import 'services/sources/source_manager.dart';
import 'services/sources/wolfx_service.dart';
import 'services/sources/fan_service.dart';
import 'services/sources/p2pquake_service.dart';
import 'services/sources/mock_input_service.dart';
import 'services/sources/jma_volcano_map_service.dart';

bool _shouldDropLogMessage(String message) {
  return message.contains('accessibility_bridge') ||
      message.contains('AXTree') ||
      message.contains('Nodes left pending by the update') ||
      message.contains('_RawReceivePort._handleMessage') ||
      message.contains('dart:isolate-patch') ||
      message.contains('dart:ui/hooks');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    final msg = details.exceptionAsString();
    if (_shouldDropLogMessage(msg)) return;
    FlutterError.presentError(details);
  };

  debugPrint = (String? message, {int? wrapWidth}) {
    if (message == null) return;
    if (_shouldDropLogMessage(message)) return;
    // ignore: avoid_print
    print(message);
  };

  // 1. 桌面端数据库初始化（Web 自动跳过——条件导入走 stub）
  initDesktopDatabase();

  // 2. 基础服务初始化
  if (!kIsWeb) {
    await DatabaseHelper().database;
    await DatabaseHelper().cleanOldData();
  }

  // 启动 NTP 同步
  NtpService().startPeriodicSync();

  // 加载走时表
  await TravelTimeService().load();

  // 初始化位置服务
  await LocationService().init();

  // 2.5 加载持久化设置
  final prefs = await SharedPreferences.getInstance();
  final fanServerIndex = prefs.getInt('fan_default_server_index') ?? 0;
  final tileKey = prefs.getString('tile_key') ?? 'petalLight';

  // 3. 注册并启动地震数据源
  final wolfx = WolfxService();
  final fan = FanService();
  fan.setDefaultServerIndex(fanServerIndex);
  final p2p = P2PQuakeService();
  final mock = MockInputService();
  final volcanoMap = JmaVolcanoMapService();
  SourceManager().registerSource(wolfx);
  SourceManager().registerSource(fan);
  SourceManager().registerSource(p2p);
  SourceManager().registerSource(mock);
  SourceManager().startAll();
  volcanoMap.start();

  // 4. 桌面端窗口初始化（Web 自动跳过）
  initDesktopWindow();

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
    'fdsnEarthScope',
    prefs.getBool('map_overlay_fdsnEarthScope') ?? false,
  );
  provider.setOverlayEnabled(
    'fdsnGeofon',
    prefs.getBool('map_overlay_fdsnGeofon') ?? false,
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
