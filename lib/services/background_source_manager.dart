import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/calculator.dart';
import '../core/intensity_calculator.dart';
import '../models/quake_message.dart';
import '../models/unified_quake_data.dart';
import '../models/unified_event_presentation.dart';
import '../providers/background_settings_provider.dart';
import 'background_event_processor.dart';
import 'epicenter_region_service.dart';
import 'location_service.dart';
import 'ntp_service.dart';
import 'quake_event_adapter.dart';
import 'sources/emsc_eqlist_service.dart';
import 'sources/eqlist/cwa_eqlist_service.dart';
import 'sources/fan_service.dart';
import 'sources/global_quake_service.dart';
import 'sources/mock_input_service.dart';
import 'sources/nowquake_cenc_intensity_service.dart';
import 'sources/p2pquake_service.dart';
import 'sources/source_manager.dart';
import 'sources/usgs_eqlist_service.dart';
import 'sources/wolfx_service.dart';
import 'sources/whews_service.dart';
import 'wauth_service.dart';

final List<StreamSubscription> _backgroundSubscriptions = [];
int _backgroundNotificationId = 0;
Timer? _backgroundSeenStatePersistTimer;

/// 前台服务 isolate 中运行的 EEW/信息数据源管理
///
/// 与主 isolate 隔离，不共享 SourceManager 单例状态。
/// 仅负责在 Android 前台服务期间保持关键数据源连接并直接弹出系统通知。
///
/// 重新初始化 SourceManager 与相关源，订阅统一事件流，满足阈值时直接弹出通知。
Future<void> startBackgroundSources(
  FlutterLocalNotificationsPlugin notifications,
) async {
  if (kIsWeb || !Platform.isAndroid) return;

  final prefs = await SharedPreferences.getInstance();
  await EpicenterRegionService.instance.load();

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

  // 加载后台通知设置
  final settings = BackgroundSettingsProvider();
  await settings.load(prefs);

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

  // 创建新的源实例（isolate 内为独立对象，避免与主 isolate 共享状态）
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
  fan.setDefaultServerIndex(prefs.getInt('fan_default_server_index') ?? 0);
  final p2p = P2PQuakeService();
  final mock = MockInputService();
  final globalQuake = GlobalQuakeService();
  final officialUsgs = UsgsEqlistService();
  final officialEmsc = EmscEqlistService();
  final officialCwa = CwaEqlistService();
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

  // 注册到 isolate 内的 SourceManager（新的单例实例）
  final manager = SourceManager();
  manager.registerSource(wolfx);
  manager.registerSource(whews);
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
  manager.setSourceEnabled(
    'WHEWS',
    prefs.getBool(WhewsService.enabledPreferenceKey) ?? false,
  );
  manager.setSourceEnabled(
    'P2P',
    prefs.getBool('api_source_p2pquake_enabled') ?? true,
  );

  // 若用户开启 GlobalQuake 桥接则连接
  if (prefs.getBool(GlobalQuakeService.enabledPreferenceKey) ?? false) {
    globalQuake.connect();
  }

  manager.startAll();

  // 定期清理过期 slot，避免内存无限增长
  Timer.periodic(const Duration(minutes: 1), (_) {
    processor.prune();
  });

  // 订阅统一事件，先经过 BackgroundEventProcessor 处理，再决定是否弹通知
  _backgroundSubscriptions.add(
    wolfx.onUnifiedEvent.listen(
      (event) => _handleUnifiedEvent(event, settings, notifications, processor),
    ),
  );
  _backgroundSubscriptions.add(
    whews.onUnifiedEvent.listen(
      (event) => _handleUnifiedEvent(event, settings, notifications, processor),
    ),
  );
  _backgroundSubscriptions.add(
    fan.onUnifiedEvent.listen(
      (event) => _handleUnifiedEvent(event, settings, notifications, processor),
    ),
  );
  _backgroundSubscriptions.add(
    nowQuakeCencIr.onUnifiedEvent.listen(
      (event) => _handleUnifiedEvent(event, settings, notifications, processor),
    ),
  );
  _backgroundSubscriptions.add(
    p2p.onUnifiedEvent.listen(
      (event) => _handleUnifiedEvent(event, settings, notifications, processor),
    ),
  );
  _backgroundSubscriptions.add(
    mock.onUnifiedEvent.listen(
      (event) => _handleUnifiedEvent(event, settings, notifications, processor),
    ),
  );
  _backgroundSubscriptions.add(
    globalQuake.onUnifiedEvent.listen(
      (event) => _handleUnifiedEvent(event, settings, notifications, processor),
    ),
  );

  void handleOfficialCurrent(String source, Map<String, dynamic> data) {
    final event = QuakeEventAdapter.convert(source, data, 0);
    if (event != null) {
      _handleUnifiedEvent(event, settings, notifications, processor);
    }
  }

  if (_isInfoSourceEnabled(prefs, QuakeSourceType.usgs)) {
    officialUsgs.onCurrentUpdated = (data) =>
        handleOfficialCurrent('usgsEqlist', data);
    officialUsgs.start();
  }
  if (_isInfoSourceEnabled(prefs, QuakeSourceType.emsc)) {
    officialEmsc.onCurrentUpdated = (data) =>
        handleOfficialCurrent('emsc', data);
    officialEmsc.start();
  }
  if (_isInfoSourceEnabled(prefs, QuakeSourceType.cwa)) {
    officialCwa.onCurrentUpdated = (data) =>
        handleOfficialCurrent('cwaEqlist', data);
    officialCwa.start();
  }
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
/// 再按后台通知设置决定是否弹系统通知。
void _handleUnifiedEvent(
  UnifiedQuakeData event,
  BackgroundSettingsProvider settings,
  FlutterLocalNotificationsPlugin notifications,
  BackgroundEventProcessor processor,
) {
  final result = processor.process(event);
  if (result.type == BackgroundEventResultType.dropped ||
      result.event == null) {
    return;
  }

  final processedEvent = result.event!;
  final isUpdate = result.type == BackgroundEventResultType.update;

  if (processedEvent.isEew) {
    if (!settings.canNotifyEew) return;
    final localIntensity = _computeLocalIntensityForEvent(processedEvent);
    if (!settings.matchesEewThreshold(localIntensity)) return;
    _showNotification(
      notifications,
      processedEvent.isCanceled ? '地震预警取消' : '地震预警',
      _buildEewBody(processedEvent, localIntensity),
      isCritical: !processedEvent.isCanceled,
    );
  } else {
    // 信息事件仅在首次收到时通知，更新时不重复弹出
    if (isUpdate) return;
    if (!settings.canNotifyReport) return;
    final presentation = UnifiedEventPresentation.fromEvent(processedEvent);
    _showNotification(
      notifications,
      presentation.title,
      presentation.notificationBody,
    );
  }
}

/// 基于单个事件计算本地预估烈度。
///
/// 优先根据用户位置与震源距离计算；当缺少用户位置或事件经纬度时，
/// 再 fallback 到事件自身 maxIntensity，避免显示震中烈度作为本地烈度。
double _computeLocalIntensityForEvent(UnifiedQuakeData event) {
  final userPos = LocationService().currentPosition;
  final lat = event.lat;
  final lng = event.lng;
  if (userPos != null && lat != null && lng != null) {
    try {
      final distance = QuakeCalculator.haversineDistance(
        userPos.latitude,
        userPos.longitude,
        lat,
        lng,
      );
      return IntensityCalculator.calculate(
        mag: event.magnitude,
        distance: distance,
      );
    } catch (e) {
      debugPrint('后台服务本地烈度计算失败: $e');
    }
  }
  final maxIntensity = double.tryParse(event.maxIntensity);
  if (maxIntensity != null && maxIntensity > 0) {
    return maxIntensity;
  }
  return 0.0;
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

Future<void> _showNotification(
  FlutterLocalNotificationsPlugin notifications,
  String title,
  String body, {
  bool isCritical = false,
}) async {
  final androidDetails = AndroidNotificationDetails(
    'rhythmquake_background',
    '后台地震通知',
    channelDescription: '应用处于后台时接收地震预警与信息事件通知',
    importance: isCritical ? Importance.max : Importance.high,
    priority: isCritical ? Priority.max : Priority.high,
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
  await notifications.show(_backgroundNotificationId++, title, body, details);
}
