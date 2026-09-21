/// 后台服务与系统通知
///
/// 负责：
/// - 监听应用生命周期（前台 / 后台，仅移动端）
/// - 初始化并调度系统本地通知
/// - 在前后台切换时发布状态变更，供地图/数据源组件响应
/// - 在后台收到 EEW / 信息事件时弹出系统通知
/// - 在 Android 上启动前台服务，保证切后台后 EEW / 信息源仍能连接
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show
        AndroidFlutterLocalNotificationsPlugin,
        AndroidInitializationSettings,
        AndroidNotificationChannel,
        AndroidNotificationDetails,
        DarwinInitializationSettings,
        DarwinNotificationDetails,
        FlutterLocalNotificationsPlugin,
        Importance,
        InitializationSettings,
        NotificationDetails,
        Priority;

import 'package:local_notifier/local_notifier.dart' as local;

import '../models/unified_quake_data.dart';
import '../models/unified_event_presentation.dart';
import '../models/quake_message.dart';
import '../models/cenc_ir_data.dart';
import '../models/weather_alarm.dart';
import '../models/tsunami_message.dart';
import '../models/source_status.dart';
import '../providers/background_settings_provider.dart';
import 'sources/source_manager.dart';
import 'background_source_manager.dart';

/// 应用前后台状态
enum AppLifecycleStateExt {
  /// 用户正在与应用交互
  foreground,

  /// 应用不可见，但进程仍在运行
  background,

  /// 状态未知或尚未初始化
  unknown,
}

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static const MethodChannel _systemSettingsChannel = MethodChannel(
    'flutterrhythmquake/system_settings',
  );

  /// 当前是否处于后台
  AppLifecycleStateExt _state = AppLifecycleStateExt.unknown;
  AppLifecycleStateExt get state => _state;
  bool get isInBackground => _state == AppLifecycleStateExt.background;

  BackgroundSettingsProvider? _settings;
  final ValueNotifier<bool> connectionHostingNotifier = ValueNotifier(false);

  /// 状态变化回调集合
  final Set<void Function(AppLifecycleStateExt)> _stateListeners = {};

  bool _initialized = false;
  int _notificationId = 0;

  // Android 前台服务相关状态
  bool _foregroundServiceConfigured = false;
  bool _isForegroundServiceRunning = false;

  StreamSubscription<Map<String, dynamic>?>? _foregroundEventSubscription;
  StreamSubscription<Map<String, dynamic>?>? _foregroundQuakeSubscription;
  StreamSubscription<Map<String, dynamic>?>? _foregroundListSubscription;
  StreamSubscription<Map<String, dynamic>?>? _foregroundCencIrSubscription;
  StreamSubscription<Map<String, dynamic>?>? _foregroundWeatherSubscription;
  StreamSubscription<Map<String, dynamic>?>? _foregroundTsunamiSubscription;
  StreamSubscription<Map<String, dynamic>?>? _foregroundStatusSubscription;
  StreamSubscription<Map<String, dynamic>?>? _foregroundStationSubscription;
  StreamSubscription<Map<String, dynamic>?>? _foregroundCmtSubscription;
  StreamSubscription<Map<String, dynamic>?>? _foregroundAuxSubscription;
  final _foregroundUnifiedController =
      StreamController<UnifiedQuakeData>.broadcast();
  final _foregroundQuakeController = StreamController<QuakeMessage>.broadcast();
  final _foregroundListController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _foregroundCencIrController = StreamController<CencIrData>.broadcast();
  final _foregroundWeatherController =
      StreamController<WeatherAlarm>.broadcast();
  final _foregroundTsunamiController =
      StreamController<TsunamiMessage>.broadcast();
  final _foregroundStatusController =
      StreamController<SourceStatusUpdate>.broadcast();
  final _foregroundStationController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _foregroundCmtController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _foregroundAuxController =
      StreamController<Map<String, dynamic>>.broadcast();

  static const String _foregroundChannelId = 'rhythmquake_foreground_service';
  static const String _foregroundNotificationTitle = 'RhythmQuake 后台运行中';
  static const String _foregroundNotificationContent = '正在连接地震预警与信息源';

  /// Android 前台服务是否正在运行（由主 isolate 维护）。
  bool get isAndroidForegroundServiceActive => _isForegroundServiceRunning;

  /// Android 前台服务已实际运行并接管连接时，主 isolate 不应再启动相同数据源。
  bool get isAndroidConnectionHostedByForegroundService =>
      !kIsWeb &&
      Platform.isAndroid &&
      (_settings?.enabled ?? false) &&
      _isForegroundServiceRunning;

  void _onSettingsChanged() {
    _syncConnectionHostingState();
    if (!_initialized || !Platform.isAndroid) return;
    if (_settings?.enabled ?? false) {
      unawaited(_startForegroundServiceIfNeededSafely());
    } else {
      unawaited(stopForegroundService(force: true));
    }
  }

  void _syncConnectionHostingState() {
    final next = isAndroidConnectionHostedByForegroundService;
    if (connectionHostingNotifier.value != next) {
      connectionHostingNotifier.value = next;
    }
  }

  Stream<UnifiedQuakeData> get onForegroundUnifiedEvent =>
      _foregroundUnifiedController.stream;
  Stream<QuakeMessage> get onForegroundQuakeEvent =>
      _foregroundQuakeController.stream;
  Stream<Map<String, dynamic>> get onForegroundSourceList =>
      _foregroundListController.stream;
  Stream<CencIrData> get onForegroundCencIrData =>
      _foregroundCencIrController.stream;
  Stream<WeatherAlarm> get onForegroundWeatherAlarm =>
      _foregroundWeatherController.stream;
  Stream<TsunamiMessage> get onForegroundTsunamiEvent =>
      _foregroundTsunamiController.stream;
  Stream<SourceStatusUpdate> get onForegroundSourceStatus =>
      _foregroundStatusController.stream;
  Stream<Map<String, dynamic>> get onForegroundStationData =>
      _foregroundStationController.stream;
  Stream<Map<String, dynamic>> get onForegroundCmtList =>
      _foregroundCmtController.stream;
  Stream<Map<String, dynamic>> get onForegroundAuxData =>
      _foregroundAuxController.stream;

  /// Android 系统是否允许本应用发送通知。
  ///
  /// Android 13 及以上对应 POST_NOTIFICATIONS 运行时权限；旧版本对应
  /// 系统设置中的应用通知总开关。其他平台返回 null。
  Future<bool?> areNotificationsEnabled() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      return await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled();
    } catch (e) {
      debugPrint('[NotificationPermission] query failed: $e');
      return null;
    }
  }

  /// 请求 Android 13 及以上的通知权限；旧版本由插件返回当前可用状态。
  Future<bool?> requestNotificationPermission() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      return await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('[NotificationPermission] request failed: $e');
      return null;
    }
  }

  /// 打开 Android 当前应用的系统通知设置页。
  Future<bool> openNotificationSettings() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _systemSettingsChannel.invokeMethod<bool>(
            'openNotificationSettings',
          ) ??
          false;
    } catch (e) {
      debugPrint('[NotificationPermission] open settings failed: $e');
      return false;
    }
  }

  /// 注册状态监听器
  void addStateListener(void Function(AppLifecycleStateExt) listener) {
    _stateListeners.add(listener);
  }

  /// 移除状态监听器
  void removeStateListener(void Function(AppLifecycleStateExt) listener) {
    _stateListeners.remove(listener);
  }

  /// 初始化通知渠道与生命周期监听
  ///
  /// Web 平台不初始化。Windows 使用 local_notifier；Android / iOS / macOS 使用
  /// flutter_local_notifications。
  Future<void> initialize(
    WidgetsBinding binding, {
    BackgroundSettingsProvider? settings,
  }) async {
    if (_initialized) return;
    _settings = settings;
    _settings?.addListener(_onSettingsChanged);
    _syncConnectionHostingState();

    if (!_supportsNotifications) {
      _initialized = true;
      return;
    }

    if (Platform.isWindows) {
      await local.LocalNotifier.instance.setup(
        appName: 'RhythmQuake',
        shortcutPolicy: local.ShortcutPolicy.requireCreate,
      );
      _initialized = true;
      return;
    }

    const backgroundChannel = AndroidNotificationChannel(
      'rhythmquake_background',
      '后台地震通知',
      description: '应用处于后台时接收地震预警与信息事件通知',
      importance: Importance.high,
    );

    const foregroundChannel = AndroidNotificationChannel(
      _foregroundChannelId,
      '前台服务通知',
      description: '保证应用在后台时仍能持续接收地震预警与信息源数据',
      importance: Importance.low,
    );

    final androidNotifications = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidNotifications?.createNotificationChannel(backgroundChannel);
    await androidNotifications?.createNotificationChannel(foregroundChannel);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );
    await _notificationsPlugin.initialize(initSettings);

    _initialized = true;
  }

  /// 监听生命周期变化
  ///
  /// 通常在 MyApp 的 State 中通过 [AppLifecycleListener] 调用。
  /// Android 平台在后台功能开启后保持前台服务运行。
  void onLifecycleStateChanged(AppLifecycleState state) {
    if (!isBackgroundHandlingEnabled) return;
    final ext = switch (state) {
      AppLifecycleState.resumed => AppLifecycleStateExt.foreground,
      AppLifecycleState.inactive ||
      AppLifecycleState.hidden ||
      AppLifecycleState.paused => AppLifecycleStateExt.background,
      _ => AppLifecycleStateExt.unknown,
    };
    if (_state == ext) return;
    _state = ext;

    // Android：后台功能开启时，数据连接由独立前台服务 isolate 维护。
    // 生命周期变化只负责确保服务继续运行；主 isolate 不再建立第二套连接。
    if (Platform.isAndroid && (_settings?.enabled ?? false)) {
      unawaited(_startForegroundServiceIfNeededSafely());
    }

    for (final listener in _stateListeners.toList()) {
      listener(ext);
    }
  }

  /// 发送 EEW 后台系统通知
  Future<void> showEewNotification(
    UnifiedQuakeData event, {
    double localIntensity = 0.0,
  }) async {
    if (!_initialized || !_supportsNotifications) return;
    if (_settings != null && !_settings!.matchesEewThreshold(localIntensity)) {
      return;
    }

    final title = event.isCanceled ? '地震预警取消' : '地震预警';
    final body = _buildEewBody(event, localIntensity);
    await _show(title, body, isCritical: !event.isCanceled);
  }

  /// 发送信息事件后台系统通知
  Future<void> showReportNotification(UnifiedQuakeData event) async {
    if (!_initialized || !_supportsNotifications) return;
    if (_settings == null || !_settings!.canNotifyReport) return;

    final presentation = UnifiedEventPresentation.fromEvent(event);
    await _show(presentation.title, presentation.notificationBody);
  }

  /// 由前台轻通知逻辑触发的 EEW 系统通知（不检查后台设置）。
  Future<void> showEewSystemNotification(
    UnifiedQuakeData event, {
    double localIntensity = 0.0,
  }) async {
    if (!_initialized || !_supportsNotifications) return;

    final title = event.isCanceled ? '地震预警取消' : '地震预警';
    final body = _buildEewBody(event, localIntensity);
    await _show(title, body, isCritical: !event.isCanceled);
  }

  /// 由前台轻通知逻辑触发的信息事件系统通知（不检查后台设置）。
  Future<void> showReportSystemNotification(UnifiedQuakeData event) async {
    if (!_initialized || !_supportsNotifications) return;

    final presentation = UnifiedEventPresentation.fromEvent(event);
    await _show(presentation.title, presentation.notificationBody);
  }

  Future<void> _show(
    String title,
    String body, {
    bool isCritical = false,
  }) async {
    _notificationId++;

    if (Platform.isWindows) {
      final notification = local.LocalNotification(title: title, body: body);
      await notification.show();
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      'rhythmquake_background',
      '后台地震通知',
      channelDescription: '应用处于后台时接收地震预警与信息事件通知',
      importance: isCritical ? Importance.max : Importance.high,
      priority: isCritical ? Priority.max : Priority.high,
      // 使用系统默认通知音
      playSound: true,
      enableVibration: isCritical,
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );
    await _notificationsPlugin.show(_notificationId, title, body, details);
  }

  String _buildEewBody(UnifiedQuakeData event, double localIntensity) {
    final buffer = StringBuffer();
    if (event.isCanceled) {
      buffer.write('本次地震预警已取消。');
    } else {
      buffer.write(
        '震源 ${event.hypocenter}，M${event.magnitude.toStringAsFixed(1)}，',
      );
      buffer.write('${event.depthText}。');
      if (localIntensity > 0) {
        buffer.write('本地预估烈度 ${localIntensity.toStringAsFixed(1)}。');
      }
    }
    return buffer.toString();
  }

  /// 配置 Android 前台服务（仅在 Android 平台生效）。
  ///
  /// 应在 [main] 中初始化通知渠道后调用，确保切后台时能拉起前台服务。
  Future<void> configureForegroundService() async {
    if (!Platform.isAndroid) return;
    if (_foregroundServiceConfigured) return;

    await _configureForegroundService(
      autoStartOnBoot: _settings?.autoStartOnBoot ?? false,
    );
  }

  /// 更新插件 BootReceiver 使用的开机启动配置，不重启当前服务。
  Future<void> setAutoStartOnBoot(bool enabled) async {
    if (!Platform.isAndroid) return;
    await _configureForegroundService(autoStartOnBoot: enabled);
  }

  Future<void> _configureForegroundService({
    required bool autoStartOnBoot,
  }) async {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: backgroundEntryPoint,
        autoStart: false,
        autoStartOnBoot: autoStartOnBoot && (_settings?.enabled ?? false),
        isForegroundMode: true,
        notificationChannelId: _foregroundChannelId,
        initialNotificationTitle: _foregroundNotificationTitle,
        initialNotificationContent: _foregroundNotificationContent,
        foregroundServiceTypes: [AndroidForegroundType.specialUse],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: backgroundEntryPoint,
        onBackground: onIosBackground,
      ),
    );
    _bindForegroundServiceEvents(service);
    _foregroundServiceConfigured = true;
    if (_settings?.enabled ?? false) {
      await _startForegroundServiceIfNeededSafely();
    }
  }

  void _bindForegroundServiceEvents(FlutterBackgroundService service) {
    _foregroundEventSubscription ??= service
        .on('foregroundUnifiedEvent')
        .listen((payload) {
          if (payload == null) return;
          try {
            _foregroundUnifiedController.add(UnifiedQuakeData.fromMap(payload));
          } catch (error, stack) {
            debugPrint('前台服务统一事件解码失败: $error\n$stack');
          }
        });
    _foregroundQuakeSubscription ??= service.on('foregroundQuakeEvent').listen((
      payload,
    ) {
      if (payload == null) return;
      try {
        _foregroundQuakeController.add(
          QuakeMessage.fromMap(Map<String, dynamic>.from(payload)),
        );
      } catch (error, stack) {
        debugPrint('前台服务原始事件解码失败: $error\n$stack');
      }
    });
    _foregroundListSubscription ??= service.on('foregroundSourceList').listen((
      payload,
    ) {
      if (payload != null) _foregroundListController.add(payload);
    });
    _foregroundCencIrSubscription ??= service.on('foregroundCencIrData').listen(
      (payload) {
        if (payload == null) return;
        try {
          _foregroundCencIrController.add(CencIrData.fromMap(payload));
        } catch (error, stack) {
          debugPrint('前台服务 CENC 烈度解码失败: $error\n$stack');
        }
      },
    );
    _foregroundWeatherSubscription ??= service
        .on('foregroundWeatherAlarm')
        .listen((payload) {
          if (payload == null) return;
          try {
            _foregroundWeatherController.add(WeatherAlarm.fromMap(payload));
          } catch (error, stack) {
            debugPrint('前台服务天气预警解码失败: $error\n$stack');
          }
        });
    _foregroundTsunamiSubscription ??= service
        .on('foregroundTsunamiEvent')
        .listen((payload) {
          if (payload == null) return;
          try {
            _foregroundTsunamiController.add(TsunamiMessage.fromMap(payload));
          } catch (error, stack) {
            debugPrint('前台服务海啸事件解码失败: $error\n$stack');
          }
        });
    _foregroundStatusSubscription ??= service
        .on('foregroundSourceStatus')
        .listen((payload) {
          if (payload == null) return;
          final name = payload['sourceName']?.toString();
          final rawStatus = payload['status']?.toString();
          if (name == null || rawStatus == null) return;
          SourceStatus? status;
          for (final candidate in SourceStatus.values) {
            if (candidate.name == rawStatus) {
              status = candidate;
              break;
            }
          }
          if (status != null) {
            _foregroundStatusController.add(SourceStatusUpdate(name, status));
          }
        });
    _foregroundStationSubscription ??= service
        .on('foregroundStationData')
        .listen((payload) {
          if (payload != null) _foregroundStationController.add(payload);
        });
    _foregroundCmtSubscription ??= service.on('foregroundCmtList').listen((
      payload,
    ) {
      if (payload != null) _foregroundCmtController.add(payload);
    });
    _foregroundAuxSubscription ??= service.on('foregroundAuxData').listen((
      payload,
    ) {
      if (payload != null) _foregroundAuxController.add(payload);
    });
  }

  /// 只回传前台服务已有气象实况，不发起 HTTP 请求或重建连接。
  void requestLocalWeatherState() {
    if (!isAndroidConnectionHostedByForegroundService) return;
    FlutterBackgroundService().invoke('requestLocalWeatherState');
  }

  /// Updates detector parameters without restarting background connections.
  void updatePAlertDetectionSensitivity(int sensitivity) {
    if (!isAndroidConnectionHostedByForegroundService) return;
    FlutterBackgroundService().invoke('palertDetectionSensitivity', {
      'value': sensitivity.clamp(1, 3),
    });
  }

  /// 设置改变后要求前台服务重新读取 SharedPreferences 并重建连接。
  Future<void> requestSourceReload({bool force = false}) async {
    if (!isAndroidConnectionHostedByForegroundService) return;
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke('reloadSources', {'force': force});
    }
  }

  /// 安全地尝试启动前台服务，避免 Android 12+ 限制导致未处理异常。
  Future<void> _startForegroundServiceIfNeededSafely() async {
    if (!Platform.isAndroid) return;
    if (!(_settings?.enabled ?? false)) return;
    try {
      await startForegroundService();
    } on PlatformException catch (e, stack) {
      debugPrint('启动前台服务失败: $e');
      debugPrint('堆栈: $stack');
    }
  }

  /// 启动 Android 前台服务（仅在 Android 平台生效）。
  Future<void> startForegroundService() async {
    if (!Platform.isAndroid) return;

    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      _isForegroundServiceRunning = true;
      _syncConnectionHostingState();
      return;
    }
    _isForegroundServiceRunning = false;
    _syncConnectionHostingState();
    await service.startService();
    _isForegroundServiceRunning = await service.isRunning();
    _syncConnectionHostingState();
  }

  /// 停止 Android 前台服务（仅在 Android 平台生效）。
  Future<void> stopForegroundService({bool force = false}) async {
    if (!Platform.isAndroid) return;
    if (!force && (_settings?.enabled ?? false)) {
      debugPrint('保持 Android 前台服务运行：后台功能仍开启，忽略非强制停止请求');
      return;
    }
    if (!_isForegroundServiceRunning) {
      // 即使本地标记未运行，也尝试停止，避免进程重启后状态不一致。
      final service = FlutterBackgroundService();
      if (await service.isRunning()) {
        service.invoke('stopService');
      }
      _isForegroundServiceRunning = false;
      _syncConnectionHostingState();
      return;
    }

    final service = FlutterBackgroundService();
    service.invoke('stopService');
    _isForegroundServiceRunning = false;
    _syncConnectionHostingState();
  }

  /// 当前平台是否支持后台生命周期处理与 Android 前台服务（仅 Android / iOS）。
  bool get isBackgroundHandlingEnabled {
    if (kIsWeb) return false;
    if (Platform.isAndroid || Platform.isIOS) return true;
    return false;
  }

  /// 当前平台是否支持系统本地通知（Android / iOS / macOS / Windows / Linux）。
  bool get _supportsNotifications {
    if (kIsWeb) return false;
    return true;
  }
}

/// Android 前台服务入口点。
///
/// 必须在顶层且带 [@pragma('vm:entry-point')] 注解，否则会被 Dart 树摇优化移除。
@pragma('vm:entry-point')
Future<void> backgroundEntryPoint(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  // Boot/watchdog starts have no UI provider; consult persisted user consent.
  final preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  if (preferences.getBool('background_enabled') != true) {
    await service.stopSelf();
    return;
  }

  Future<void> sendUnifiedEvent(UnifiedQuakeData event) async {
    service.invoke('foregroundUnifiedEvent', event.toMap());
  }

  Future<void> sendQuakeEvent(QuakeMessage event) async {
    service.invoke('foregroundQuakeEvent', event.toMap());
  }

  Future<void> sendSourceList(String source, List<QuakeMessage> events) async {
    service.invoke('foregroundSourceList', {
      'source': source,
      'items': events.map((event) => event.toMap()).toList(),
    });
  }

  Future<void> sendCencIrData(CencIrData data) async {
    service.invoke('foregroundCencIrData', data.toMap());
  }

  Future<void> sendWeatherAlarm(WeatherAlarm alarm) async {
    service.invoke('foregroundWeatherAlarm', alarm.toMap());
  }

  Future<void> sendTsunamiEvent(TsunamiMessage event) async {
    service.invoke('foregroundTsunamiEvent', event.toMap());
  }

  Future<void> sendSourceStatus(SourceStatusUpdate update) async {
    service.invoke('foregroundSourceStatus', {
      'sourceName': update.sourceName,
      'status': update.status.name,
    });
  }

  Future<void> sendStationData(Map<String, dynamic> payload) async {
    service.invoke('foregroundStationData', payload);
  }

  Future<void> sendCmtList(
    String source,
    List<Map<String, dynamic>> items,
  ) async {
    service.invoke('foregroundCmtList', {'source': source, 'items': items});
  }

  Future<void> sendAuxData(Map<String, dynamic> payload) async {
    service.invoke('foregroundAuxData', payload);
  }

  Future<void> startSources() async {
    await startBackgroundSources(
      onUnifiedEvent: sendUnifiedEvent,
      onQuakeEvent: sendQuakeEvent,
      onSourceList: sendSourceList,
      onCencIrData: sendCencIrData,
      onWeatherAlarm: sendWeatherAlarm,
      onTsunamiEvent: sendTsunamiEvent,
      onSourceStatus: sendSourceStatus,
      onStationData: sendStationData,
      onCmtList: sendCmtList,
      onAuxData: sendAuxData,
    );
  }

  Future<void>? reloadFuture;
  bool reloadPending = false;
  bool forceReloadPending = false;
  Future<void> reloadSources({bool force = false}) {
    reloadPending = true;
    forceReloadPending = forceReloadPending || force;
    return reloadFuture ??= () async {
      try {
        while (reloadPending) {
          reloadPending = false;
          final forceReload = forceReloadPending;
          forceReloadPending = false;
          if (forceReload || !await reloadBackgroundStationSettings()) {
            await startSources();
          }
        }
      } finally {
        reloadFuture = null;
      }
    }();
  }

  service.on('requestLocalWeatherState').listen((_) {
    for (final payload in backgroundLocalWeatherSnapshots()) {
      unawaited(sendAuxData(payload));
    }
  });

  await startSources();

  service.on('reloadSources').listen((event) {
    unawaited(reloadSources(force: event?['force'] == true));
  });
  service.on('palertDetectionSensitivity').listen((event) {
    final value = event?['value'];
    if (value is int) setBackgroundPAlertDetectionSensitivity(value);
  });

  // 接收主 isolate 的停止指令
  service.on('stopService').listen((event) {
    unawaited(() async {
      await stopBackgroundSources();
      service.stopSelf();
    }());
  });
}

/// iOS 后台任务入口（flutter_background_service 要求提供，但 iOS 仍走现有 AppLifecycle 逻辑）。
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}
