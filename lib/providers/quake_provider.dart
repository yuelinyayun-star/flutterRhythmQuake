/// 地震数据状态管理提供者
///
/// 本模块是应用的核心状态管理器，负责：
/// - 接收和处理来自各数据源的地震消息
/// - 管理活动预警和信息事件
/// - 计算距离和预估烈度
/// - 触发语音警报和窗口提醒
/// - 管理历史地震记录
///
/// ## 数据流程
///
/// 1. 数据源服务通过 EventBus 发布 QuakeMessage
/// 2. QuakeProvider 接收消息并计算距离/烈度
/// 3. 根据消息类型分发到预警列表或信息列表
/// 4. 触发相应的通知和语音警报
/// 5. 更新 UI 显示
///
/// ## 预警分类
///
/// - **预警事件**: 来自预警系统的紧急地震速报
/// - **信息事件**: 来自地震台网的正式测定结果

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/event_bus.dart';
import '../services/location_service.dart';
import '../services/tts_service.dart';
import '../services/sound_effect_service.dart';
import '../services/windows_manager.dart';
import '../services/database_helper.dart';
import '../services/ntp_service.dart';
import '../services/sources/source_manager.dart';
import '../services/sources/fan_service.dart';
import '../services/sources/china_weather_alert_service.dart';
import '../services/sources/typhoon_service.dart';
import '../services/sources/wolfx_service.dart';
import '../services/sources/p2pquake_service.dart';
import '../services/sources/mock_input_service.dart';
import '../services/sources/global_quake_service.dart';
import '../services/sources/eqlist/eqlist_manager.dart';
import '../core/intensity_calculator.dart';
import '../core/calculator.dart';
import '../models/quake_message.dart';
import '../models/unified_quake_data.dart';
import '../models/eew_event_group.dart';
import '../models/source_status.dart';
import '../models/cenc_ir_data.dart';
import '../models/weather_alarm.dart';
import '../models/typhoon_data.dart';
import '../models/tsunami_message.dart';
import '../core/utils/alert_voice_helper.dart';
import '../core/utils/quake_time.dart';

/// 活动预警事件
///
/// 表示一个正在显示的地震预警事件，包含距离和预估烈度信息。
/// 参考 kanameishi 的 EewEvent 类设计，支持同一事件的多次更新。
class ActiveWarning {
  /// 地震事件数据
  QuakeMessage event;

  /// 距离用户的距离 (km)
  double distance;

  /// 预估烈度
  double estimatedIntensity;

  /// 上次播报的倒计时秒数
  ///
  /// 用于避免重复播报相同的倒计时。
  int lastSpokenSeconds;

  /// 是否已静默
  bool mute;

  /// 自动移除定时器
  Timer? dismissTimer;

  /// 剩余显示时间（秒）
  ///
  /// 对于初始加载恢复的 EEW，已过去的时间需要从总超时中扣除。
  /// 为 null 时使用 timeoutSeconds（实时事件）。
  int? remainingSeconds;

  ActiveWarning({
    required this.event,
    required this.distance,
    required this.estimatedIntensity,
    this.lastSpokenSeconds = -1,
    this.mute = false,
    this.dismissTimer,
    this.remainingSeconds,
  });

  /// 更新事件数据
  ///
  /// 保留上一报的播报状态，避免重复播报。
  void update(QuakeMessage newEvent, double newDistance, double newIntensity) {
    final preservedOrigin = event.originTime;
    event = newEvent.copyWith(originTime: preservedOrigin);
    distance = newDistance;
    estimatedIntensity = newIntensity;
  }

  /// 获取过期时间（秒）
  ///
  /// 参考 kanameishi 的过期策略：
  /// - 取消报：20秒
  /// - 警报级 (isWarn)：max(震级, 6) * 60 秒
  /// - 普通：max(震级, 3) * 60 秒
  int get timeoutSeconds {
    if (event.isCanceled) return 20;
    final mag = event.magnitude;
    if (event.isWarn) return ((mag > 6 ? mag : 6) * 60).ceil();
    return ((mag > 3 ? mag : 3) * 60).ceil();
  }
}

/// 活动信息事件
///
/// 表示一个正在显示的地震信息事件（非预警）。
class ActiveInfoEvent {
  /// 地震事件数据
  final QuakeMessage event;

  /// 距离用户的距离 (km)
  final double distance;

  /// 预估烈度
  final double estimatedIntensity;

  /// 接收时间
  final DateTime receivedAt;

  ActiveInfoEvent({
    required this.event,
    required this.distance,
    required this.estimatedIntensity,
    required this.receivedAt,
  });
}

/// 地震数据提供者
///
/// 应用核心状态管理器，使用 ChangeNotifier 模式。
/// 管理所有地震相关的状态和业务逻辑。
class QuakeProvider with ChangeNotifier {
  /// 当前显示的事件
  QuakeMessage? _currentEvent;

  /// 当前事件距离用户的距离 (km)
  double _currentDistance = 0.0;

  /// 当前事件的预估烈度
  double _estimatedIntensity = 0.0;

  /// 上次播报的倒计时秒数
  int _lastSpokenSeconds = -1;

  /// 倒计时定时器
  Timer? _countdownTimer;

  /// 活动预警列表
  final List<ActiveWarning> _activeWarnings = [];

  /// 当前轮播索引
  int _currentWarningIndex = 0;

  /// 轮播定时器
  Timer? _carouselTimer;

  /// 信息事件自动关闭定时器
  Timer? _infoDismissTimer;

  /// 信息事件自动关闭时长（秒）
  static const int _infoDismissDuration = 120;

  /// 临时信息显示计时器（有预警时信息事件显示5秒后切回预警）
  Timer? _tempInfoDisplayTimer;

  /// 临时显示信息事件的时长（秒）
  static const int _tempInfoDisplayDuration = 10;

  /// 是否正在临时显示信息事件
  bool _isShowingTempInfo = false;

  /// 所有预警和信息事件过期时的回调
  void Function()? onAllEventsExpired;

  /// 活动信息事件列表
  final List<ActiveInfoEvent> _activeInfoEvents = [];

  /// CENC 烈度速报数据
  CencIrData? _cencIrData;

  /// CENC 烈度速报列表缓存（供手动选择使用）
  List<Map<String, dynamic>> _cencIrList = [];

  /// 气象预警数据
  WeatherAlarm? _weatherAlarm;
  bool _weatherLocalOnly = false;
  String _weatherLocalAdminLevel = 'county';
  double? _weatherFallbackLat;
  double? _weatherFallbackLng;
  List<String> _weatherLocalKeywords = const [];
  final ChinaWeatherAlertService _chinaWeatherService =
      ChinaWeatherAlertService();
  List<TyphoonData> _activeTyphoons = const [];
  final TyphoonService _typhoonService = TyphoonService();
  bool _typhoonLayerEnabled = false;

  /// JMA 海啸情报
  TsunamiMessage? _jmaTsunami;

  /// NMEFC 海啸预警
  TsunamiMessage? _nmefcTsunami;

  /// 统一事件列表（新统一管道）
  final List<UnifiedQuakeData> _unifiedEvents = [];

  final List<EewEventGroup> _eewHistory = [];

  List<EewEventGroup> get eewHistory => List.unmodifiable(_eewHistory);

  /// 统一事件列表当前索引
  int _currentUnifiedIndex = 0;

  /// 统一事件流订阅列表
  final List<StreamSubscription> _unifiedSubscriptions = [];

  /// 统一事件自动轮播定时器
  Timer? _unifiedCarouselTimer;

  /// 统一事件每事件独立关闭定时器 (eventId → Timer)
  final Map<String, Timer> _unifiedDismissTimers = {};

  /// 已关闭的统一事件ID集合，防止重新出现
  final Set<String> _dismissedUnifiedIds = {};

  /// 无可靠更新时间的信息源已见事件，防止很久后的正文修正重新顶到主 UI。
  final Map<String, DateTime> _seenNoUpdateInfoEvents = {};
  static const String _seenNoUpdateInfoEventsKey = 'seen_no_update_info_events';
  static const Duration _seenNoUpdateInfoTtl = Duration(hours: 48);
  static const int _maxSeenNoUpdateInfoEvents = 500;

  /// 已关闭的旧管道事件ID集合，防止已关闭事件通过旧管道重新出现
  final Set<String> _dismissedLegacyIds = {};

  /// kanameishi 式 EEW 已过期事件记录: "source|eventId" → 最高 reportNum
  /// 防止已终止的旧报重新出现
  final Map<String, int> _ignoredEewIds = {};
  static const int _maxIgnoredEewIds = 10;
  final Set<String> _eewCautionSoundIds = {};
  final Set<String> _eewWarnSoundIds = {};
  final Map<TsunamiSource, int> _lastTsunamiStatusForSound = {};

  /// 是否正在显示信息事件
  bool get _legacyActiveQuakePipelineDisabled => true;

  bool _isShowingInfoEvent = false;

  /// 地震列表管理器
  final EqlistManager _eqlist = EqlistManager();
  Timer? _eqlistStartTimer;

  /// 扁平化的历史列表
  List<QuakeMessage> _flatHistory = [];

  /// 按数据源分组的历史记录
  Map<String, List<QuakeMessage>> get historyBySource =>
      _eqlist.getAllBuckets();

  /// 获取历史列表
  List<QuakeMessage> get historyList => _flatHistory;

  /// 震级过滤器
  double _magFilter = 0;

  /// 各信息事件源独立震级过滤器（source → 最低震级，0=不过滤）
  final Map<QuakeSourceType, double> _sourceInfoMagFilters = {};
  static const String _sourceMagFilterPrefix = 'source_mag_filter_';

  /// 是否显示旧事件更新报（默认关闭，过期信息事件不显示卡片）
  bool _showStaleInfoEvent = false;

  /// 获取是否显示旧事件更新报
  bool get showStaleInfoEvent => _showStaleInfoEvent;

  /// 设置是否显示旧事件更新报
  void setShowStaleInfoEvent(bool value) {
    _showStaleInfoEvent = value;
    notifyListeners();
  }

  /// 数据源过滤器
  Set<String> _sourceFilter = {
    'jmaEqlist',
    'cencEqlist',
    'usgsEqlist',
    'fssnEqlist',
    'kmaEqlist',
    'cwaEqlist',
    'emscEqlist',
  };

  double get magFilter => _magFilter;
  Set<String> get sourceFilter => _sourceFilter;

  /// 获取各信息事件源震级过滤器
  Map<QuakeSourceType, double> get sourceInfoMagFilters =>
      Map.unmodifiable(_sourceInfoMagFilters);

  /// 获取支持独立震级过滤的信息事件源列表
  static List<QuakeSourceType> get infoMagFilterSources => [
    QuakeSourceType.cenc,
    QuakeSourceType.usgs,
    QuakeSourceType.cwa,
    QuakeSourceType.fssn,
    QuakeSourceType.p2p,
    QuakeSourceType.hko,
    QuakeSourceType.emsc,
    QuakeSourceType.bcsf,
    QuakeSourceType.gfz,
    QuakeSourceType.usp,
    QuakeSourceType.kma_eq,
    QuakeSourceType.ningxia,
    QuakeSourceType.guangxi,
    QuakeSourceType.shanxi,
    QuakeSourceType.beijing,
    QuakeSourceType.yunnan,
  ];

  /// 设置指定信息事件源的震级阈值
  void setSourceInfoMagFilter(QuakeSourceType source, double threshold) {
    if (threshold == 0) {
      _sourceInfoMagFilters.remove(source);
    } else {
      _sourceInfoMagFilters[source] = threshold;
    }
    notifyListeners();
  }

  Future<void> _loadSourceInfoMagFilters() async {
    final prefs = await SharedPreferences.getInstance();
    _sourceInfoMagFilters.clear();
    for (final source in infoMagFilterSources) {
      final threshold = prefs.getDouble(
        '$_sourceMagFilterPrefix${source.name}',
      );
      if (threshold != null && threshold != 0) {
        _sourceInfoMagFilters[source] = threshold;
      }
    }
    notifyListeners();
  }

  Future<void> setWeatherLocalOnly(bool value, {bool persist = true}) async {
    if (_weatherLocalOnly == value && !persist) {
      _rebuildWeatherLocalProfile();
      _syncChinaWeatherMode();
      notifyListeners();
      return;
    }
    _weatherLocalOnly = value;
    // 避免模式切换后短暂显示旧来源（全局/本地）残留预警内容
    _weatherAlarm = null;
    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('weather_alarm_local_only', value);
    }
    if (_weatherLocalOnly) {
      _rebuildWeatherLocalProfile();
    }
    _syncChinaWeatherMode();
    notifyListeners();
  }

  Future<void> setWeatherLocalAdminLevel(
    String level, {
    bool persist = true,
  }) async {
    final normalized = _normalizeWeatherLocalLevel(level);
    if (_weatherLocalAdminLevel == normalized && !persist) {
      _syncChinaWeatherMode();
      notifyListeners();
      return;
    }
    _weatherLocalAdminLevel = normalized;
    // 层级切换后先清空旧告警，等待新层级结果回填
    if (_weatherLocalOnly) {
      _weatherAlarm = null;
    }
    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('weather_alarm_local_level', normalized);
    }
    _syncChinaWeatherMode();
    notifyListeners();
  }

  Future<void> _loadWeatherLocalPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _weatherLocalOnly = prefs.getBool('weather_alarm_local_only') ?? false;
    _weatherLocalAdminLevel = _normalizeWeatherLocalLevel(
      prefs.getString('weather_alarm_local_level') ?? 'county',
    );
    _weatherFallbackLat = prefs.getDouble('map_view_lat');
    _weatherFallbackLng = prefs.getDouble('map_view_lng');
    _rebuildWeatherLocalProfile();
    _syncChinaWeatherMode();
    notifyListeners();
  }

  void _rebuildWeatherLocalProfile() {
    final anchor = _localAnchor();
    final province = _inferProvince(anchor.$1, anchor.$2);
    _weatherLocalKeywords = _keywordsForProvince(province);
  }

  void _syncChinaWeatherMode() {
    final anchor = _localAnchor();
    _chinaWeatherService.setLocalAnchor(anchor.$1, anchor.$2);
    _chinaWeatherService.setProvinceKeywords(_weatherLocalKeywords);
    _chinaWeatherService.setAdminLevel(
      _toWeatherAdminLevel(_weatherLocalAdminLevel),
    );
    if (_weatherLocalOnly) {
      _chinaWeatherService.start(intervalSeconds: 90);
    } else {
      _chinaWeatherService.stop();
    }
  }

  String _normalizeWeatherLocalLevel(String level) {
    switch (level) {
      case 'province':
      case 'city':
      case 'county':
        return level;
      default:
        return 'county';
    }
  }

  ChinaWeatherAdminLevel _toWeatherAdminLevel(String level) {
    switch (level) {
      case 'province':
        return ChinaWeatherAdminLevel.province;
      case 'city':
        return ChinaWeatherAdminLevel.city;
      case 'county':
      default:
        return ChinaWeatherAdminLevel.county;
    }
  }

  (double, double) _localAnchor() {
    final pos = LocationService().currentPosition;
    if (pos != null) return (pos.latitude, pos.longitude);
    final lat = _weatherFallbackLat ?? 29.30;
    final lng = _weatherFallbackLng ?? 120.09;
    return (lat, lng);
  }

  static const Map<String, (double, double)> _provinceCenters = {
    '北京': (39.93, 116.40),
    '天津': (39.14, 117.21),
    '河北': (38.05, 114.49),
    '山西': (37.87, 112.56),
    '内蒙古': (40.82, 111.67),
    '辽宁': (41.80, 123.38),
    '吉林': (43.88, 125.32),
    '黑龙江': (45.80, 126.53),
    '上海': (31.25, 121.49),
    '江苏': (32.06, 118.80),
    '浙江': (30.27, 120.15),
    '安徽': (31.87, 117.28),
    '福建': (26.05, 119.33),
    '江西': (28.68, 115.86),
    '山东': (36.65, 117.00),
    '河南': (34.76, 113.65),
    '湖北': (30.58, 114.30),
    '湖南': (28.21, 112.94),
    '广东': (23.12, 113.31),
    '广西': (22.81, 108.30),
    '海南': (20.02, 110.33),
    '重庆': (29.54, 106.53),
    '四川': (30.57, 104.07),
    '贵州': (26.63, 106.71),
    '云南': (25.04, 102.68),
    '西藏': (29.65, 91.12),
    '陕西': (34.34, 108.94),
    '甘肃': (36.06, 103.82),
    '青海': (36.62, 101.78),
    '宁夏': (38.47, 106.27),
    '新疆': (43.83, 87.63),
    '香港': (22.29, 114.19),
    '澳门': (22.19, 113.55),
    '台湾': (23.97, 120.96),
  };

  static const Map<String, List<String>> _provinceExtraKeywords = {
    '浙江': ['浙江', '浙江省', '杭州', '宁波', '温州', '金华', '义乌'],
    '江苏': ['江苏', '江苏省', '南京', '苏州', '无锡', '常州'],
    '上海': ['上海', '沪'],
    '安徽': ['安徽', '安徽省', '合肥'],
    '福建': ['福建', '福建省', '福州', '厦门'],
    '江西': ['江西', '江西省', '南昌'],
    '广东': ['广东', '广东省', '广州', '深圳'],
  };

  String? _inferProvince(double lat, double lng) {
    String? best;
    double bestDist = double.infinity;
    for (final entry in _provinceCenters.entries) {
      final d = QuakeCalculator.haversineDistance(
        lat,
        lng,
        entry.value.$1,
        entry.value.$2,
      );
      if (d < bestDist) {
        bestDist = d;
        best = entry.key;
      }
    }
    if (bestDist > 700) return null;
    return best;
  }

  List<String> _keywordsForProvince(String? province) {
    if (province == null || province.isEmpty) return const [];
    final base = <String>[province, '${province}省', '${province}市'];
    final extra = _provinceExtraKeywords[province] ?? const [];
    return [...base, ...extra];
  }

  /// 设置震级过滤器
  void setMagFilter(double v) {
    _magFilter = v;
    _rebuildFlat();
    notifyListeners();
  }

  /// 切换数据源过滤器
  void toggleSource(String key) {
    if (_sourceFilter.contains(key))
      _sourceFilter.remove(key);
    else
      _sourceFilter.add(key);
    _rebuildFlat();
    notifyListeners();
  }

  /// 更新数据源状态
  ///
  /// 用于手动更新特定数据源的连接状态。
  /// 通常在数据源服务初始化或状态变化时调用。
  ///
  /// 参数：
  /// - [sourceName]: 数据源名称
  /// - [status]: 新的连接状态
  void updateSourceStatus(String sourceName, SourceStatus status) {
    _sourceStatuses[sourceName] = status;
    notifyListeners();
  }

  /// 数据源状态映射
  ///
  /// 记录各数据源的当前连接状态。
  final Map<String, SourceStatus> _sourceStatuses = {
    'Wolfx': SourceStatus.disconnected,
    'FAN': SourceStatus.disconnected,
    'P2P': SourceStatus.disconnected,
    'NIED': SourceStatus.disconnected,
    'KMA': SourceStatus.disconnected,
    'CENC': SourceStatus.disconnected,
    'S-net': SourceStatus.disconnected,
    'TREM': SourceStatus.disconnected,
    'SeisJS': SourceStatus.disconnected,
  };

  Map<String, SourceStatus> get sourceStatuses => _sourceStatuses;
  QuakeMessage? get currentEvent =>
      _legacyActiveQuakePipelineDisabled ? null : _currentEvent;
  double get currentDistance =>
      _legacyActiveQuakePipelineDisabled ? 0.0 : _currentDistance;
  double get estimatedIntensity =>
      _legacyActiveQuakePipelineDisabled ? 0.0 : _estimatedIntensity;
  WeatherAlarm? get weatherAlarm => _weatherAlarm;
  bool get weatherLocalOnly => _weatherLocalOnly;
  String? get weatherDetectedProvince => _chinaWeatherService.detectedProvince;
  String get weatherLocalAdminLevel => _weatherLocalAdminLevel;
  List<TyphoonData> get activeTyphoons => _activeTyphoons;

  void setTyphoonLayerEnabled(bool enabled) {
    if (_typhoonLayerEnabled == enabled) {
      if (enabled) {
        if (!_typhoonService.isRunning) {
          _typhoonService.start();
        } else {
          _typhoonService.fetchNow();
        }
      }
      return;
    }
    _typhoonLayerEnabled = enabled;
    if (enabled) {
      _typhoonService.start();
      return;
    }
    _typhoonService.stop();
    if (_activeTyphoons.isNotEmpty) {
      _activeTyphoons = const [];
      notifyListeners();
    }
  }

  TsunamiMessage? get jmaTsunami => _jmaTsunami;
  TsunamiMessage? get nmefcTsunami => _nmefcTsunami;

  List<ActiveWarning> get activeWarnings => _legacyActiveQuakePipelineDisabled
      ? const <ActiveWarning>[]
      : List.unmodifiable(_activeWarnings);
  int get currentWarningIndex =>
      _legacyActiveQuakePipelineDisabled ? 0 : _currentWarningIndex;
  int get activeWarningCount =>
      _legacyActiveQuakePipelineDisabled ? 0 : _activeWarnings.length;

  List<ActiveInfoEvent> get activeInfoEvents =>
      _legacyActiveQuakePipelineDisabled
      ? const <ActiveInfoEvent>[]
      : List.unmodifiable(_activeInfoEvents);
  CencIrData? get cencIrData => _cencIrData;
  List<Map<String, dynamic>> get cencIrList => List.unmodifiable(_cencIrList);
  int get activeInfoEventCount =>
      _legacyActiveQuakePipelineDisabled ? 0 : _activeInfoEvents.length;
  bool get isShowingInfoEvent =>
      _legacyActiveQuakePipelineDisabled ? false : _isShowingInfoEvent;
  bool get isShowingTempInfo =>
      _legacyActiveQuakePipelineDisabled ? false : _isShowingTempInfo;
  int get totalDisplayCount => _legacyActiveQuakePipelineDisabled
      ? 0
      : _activeWarnings.length + _activeInfoEvents.length;

  List<UnifiedQuakeData> get unifiedEvents => List.unmodifiable(_unifiedEvents);
  int get currentUnifiedIndex => _currentUnifiedIndex;
  int get unifiedEventCount => _unifiedEvents.length;
  UnifiedQuakeData? get currentUnifiedEvent =>
      _unifiedEvents.isNotEmpty ? _unifiedEvents[_currentUnifiedIndex] : null;

  List<QuakeMessage> get unifiedMapEvents =>
      _unifiedEvents.map(_unifiedToMapMessage).toList();

  /// 是否应该显示气象警报UI
  /// 仅当预警和信息事件都为空时才显示
  bool get shouldShowWeatherAlarm =>
      _unifiedEvents.isEmpty && _weatherAlarm != null;

  /// 构造函数
  ///
  /// 初始化事件监听和数据源状态订阅。
  QuakeProvider() {
    _loadWeatherLocalPrefs();
    _startUnifiedEventsAfterSourcePrefs();

    _eqlist.onAnyUpdated = _rebuildFlat;
    _scheduleEqlistStart();
    _rebuildFlat();

    QuakeEventBus().onNewEvent.listen(
      _handleNewQuake,
      onError: (e, stack) {
        final lines = stack.toString().split('\n');
        final short = lines.take(5).join('\n');
        print('EventBus error: $e\n$short');
      },
    );
    SourceManager().onStatusUpdate.listen((update) {
      _sourceStatuses[update.sourceName] = update.status;
      notifyListeners();
    });

    final fanService = SourceManager().getSource<FanService>();
    if (fanService != null) {
      fanService.onCencIrData = (data) {
        _cencIrData = data;
        notifyListeners();
      };
      fanService.onCencIrListUpdated = (list) {
        _cencIrList = list;
        notifyListeners();
      };
      fanService.onFssnListUpdated = (items) {
        _eqlist.updateFssnList(items);
      };
      fanService.onCencListUpdated = (items) {
        _eqlist.updateCencList(items);
      };
      fanService.onCwaListUpdated = (items) {
        _eqlist.updateCwaList(items);
      };
      fanService.onWeatherAlarm = (alarm) {
        if (_weatherLocalOnly) {
          return;
        }
        _weatherAlarm = alarm;
        if (_unifiedEvents.isEmpty) {
          _currentEvent = null;
          onAllEventsExpired?.call();
        }
        notifyListeners();
      };
    }

    _chinaWeatherService.onLocalAlarmChanged = (alarm) {
      if (!_weatherLocalOnly) return;
      _weatherAlarm = alarm;
      if (_unifiedEvents.isEmpty) {
        _currentEvent = null;
        onAllEventsExpired?.call();
      }
      notifyListeners();
    };

    _typhoonService.onActiveTyphoonsChanged = (typhoons) {
      _activeTyphoons = typhoons;
      notifyListeners();
    };
  }

  void _startUnifiedEventsAfterSourcePrefs() {
    Future.wait([
      _loadSourceInfoMagFilters(),
      _loadSeenNoUpdateInfoEvents(),
    ]).whenComplete(_subscribeUnifiedEvents);
  }

  void _scheduleEqlistStart() {
    _eqlistStartTimer?.cancel();
    _eqlistStartTimer = Timer(const Duration(seconds: 4), () {
      _eqlistStartTimer = null;
      _eqlist.start();
    });
  }

  void _subscribeUnifiedEvents() {
    final wolfxService = SourceManager().getSource<WolfxService>();
    if (wolfxService != null) {
      _unifiedSubscriptions.add(
        wolfxService.onUnifiedEvent.listen(_handleUnifiedEvent),
      );
      wolfxService.onJmaEqlistUpdated = (items) {
        _eqlist.updateJmaList(items);
      };
      wolfxService.onCencEqlistUpdated = (items) {
        _eqlist.updateCencList(items);
      };
    }

    final fanService = SourceManager().getSource<FanService>();
    if (fanService != null) {
      _unifiedSubscriptions.add(
        fanService.onUnifiedEvent.listen(_handleUnifiedEvent),
      );
    }

    final p2pService = SourceManager().getSource<P2PQuakeService>();
    if (p2pService != null) {
      _unifiedSubscriptions.add(
        p2pService.onUnifiedEvent.listen(_handleUnifiedEvent),
      );
    }

    final mockService = SourceManager().getSource<MockInputService>();
    if (mockService != null) {
      _unifiedSubscriptions.add(
        mockService.onUnifiedEvent.listen(_handleUnifiedEvent),
      );
    }

    final globalQuakeService = SourceManager().getSource<GlobalQuakeService>();
    if (globalQuakeService != null) {
      _unifiedSubscriptions.add(
        globalQuakeService.onUnifiedEvent.listen(_handleUnifiedEvent),
      );
    }

    _subscribeTsunamiEvents();
  }

  void _subscribeTsunamiEvents() {
    final p2pService = SourceManager().getSource<P2PQuakeService>();
    if (p2pService != null) {
      _unifiedSubscriptions.add(
        p2pService.onTsunamiEvent.listen(_handleTsunamiEvent),
      );
    }

    final fanService = SourceManager().getSource<FanService>();
    if (fanService != null) {
      _unifiedSubscriptions.add(
        fanService.onTsunamiEvent.listen(_handleTsunamiEvent),
      );
    }

    final mockService = SourceManager().getSource<MockInputService>();
    if (mockService != null) {
      _unifiedSubscriptions.add(
        mockService.onTsunamiEvent.listen(_handleTsunamiEvent),
      );
    }
  }

  void _handleTsunamiEvent(TsunamiMessage tsunami) {
    final previousStatus = _lastTsunamiStatusForSound[tsunami.source];
    _playTsunamiSound(tsunami);
    _speakTsunamiEvent(tsunami, previousStatus: previousStatus);
    switch (tsunami.source) {
      case TsunamiSource.jma:
        _jmaTsunami = tsunami;
        break;
      case TsunamiSource.nmefc:
        _nmefcTsunami = tsunami;
        break;
    }
    notifyListeners();
  }

  void _playTsunamiSound(TsunamiMessage tsunami) {
    final status = tsunami.status;
    final previous = _lastTsunamiStatusForSound[tsunami.source];
    _lastTsunamiStatusForSound[tsunami.source] = status;
    if (status <= 0) {
      final isCancel =
          tsunami.title.contains('解除') || tsunami.titleText.contains('解除');
      if (isCancel && previous != null && previous > 0) {
        SoundEffectService().play('tsunami${previous}cancel');
      }
      return;
    }
    if (previous == null || previous <= 0) {
      SoundEffectService().play('tsunami${status}issue');
    } else if (status != previous) {
      final key = status <= 2
          ? 'tsunami${status}switch'
          : 'tsunami${status}update';
      SoundEffectService().play(key);
    } else {
      SoundEffectService().play('tsunami${status}update');
    }
  }

  static const Map<String, QuakeSourceType> _unifiedToQst = {
    'jmaEew': QuakeSourceType.jma_fan,
    'cwaEew': QuakeSourceType.cwa_eew,
    'ceaEew': QuakeSourceType.cea,
    'scEew': QuakeSourceType.sc_eew,
    'fjEew': QuakeSourceType.fj_eew,
    'cqEew': QuakeSourceType.cq_eew,
    'kmaEew': QuakeSourceType.kma_eew_fan,
    'sa': QuakeSourceType.sa,
    'globalQuakeEew': QuakeSourceType.usgs,
    'jmaEqlist': QuakeSourceType.jma_fan,
    'p2pJmaEqlist': QuakeSourceType.p2p,
    'cwaEqlist': QuakeSourceType.cwa,
    'cencEqlist': QuakeSourceType.cenc,
    'kmaEqlist': QuakeSourceType.kma_eq,
    'usgsEqlist': QuakeSourceType.usgs,
    'fssnEqlist': QuakeSourceType.fssn,
    'fssnCmt': QuakeSourceType.fssnCmt,
    'hko': QuakeSourceType.hko,
    'emsc': QuakeSourceType.emsc,
    'emscEqlist': QuakeSourceType.emsc,
    'bcsf': QuakeSourceType.bcsf,
    'gfz': QuakeSourceType.gfz,
    'usp': QuakeSourceType.usp,
    'ningxia': QuakeSourceType.ningxia,
    'guangxi': QuakeSourceType.guangxi,
    'shanxi': QuakeSourceType.shanxi,
    'beijing': QuakeSourceType.beijing,
    'yunnan': QuakeSourceType.yunnan,
  };

  static final Set<QuakeSourceType> _legacySourcesHandledByUnified =
      Set<QuakeSourceType>.unmodifiable(_unifiedToQst.values.toSet());

  bool _isHandledByUnifiedPipeline(QuakeMessage event) {
    return _legacySourcesHandledByUnified.contains(event.source);
  }

  String _unifiedEventKey(UnifiedQuakeData event) {
    final source = event.isEew ? event.source : _unifiedInfoSlotSource(event);
    return '$source|${_unifiedCanonicalEventId(event)}';
  }

  @visibleForTesting
  String unifiedEventKeyForTest(UnifiedQuakeData event) {
    return _unifiedEventKey(event);
  }

  String _unifiedInfoSlotSource(UnifiedQuakeData event) {
    if (event.isEew) return event.source;
    final noUpdateSourceKey = _noUpdateTimeFanInfoSourceKey(event.source);
    if (noUpdateSourceKey != null) return noUpdateSourceKey;
    return switch (event.source) {
      'p2pJmaEqlist' => 'jmaEqlist',
      _ => event.source,
    };
  }

  String _unifiedCanonicalEventId(UnifiedQuakeData event) {
    if (!event.isEew && _unifiedInfoSlotSource(event) == 'jmaEqlist') {
      final digits = event.eventId.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 12) return digits;
    }
    return event.eventId;
  }

  QuakeSourceType? _unifiedSourceType(UnifiedQuakeData event) {
    if (event.source == 'jmaEqlist' && event.origin == 2) {
      return QuakeSourceType.p2p;
    }
    return _unifiedToQst[event.source];
  }

  bool _isReviewedUnifiedInfoEvent(UnifiedQuakeData event) {
    if (event.isEew) return false;
    final text = '${event.titleText} ${event.reportNumText}'.toLowerCase();
    return text.contains('正式') ||
        text.contains('已核实') ||
        text.contains('reviewed');
  }

  String? _unifiedListBucket(UnifiedQuakeData event) {
    if (event.isEew) return null;
    return switch (event.source) {
      'jmaEqlist' => 'jmaEqlist',
      'p2pJmaEqlist' => 'jmaEqlist',
      'cencEqlist' => 'cencEqlist',
      'usgsEqlist' => 'usgsEqlist',
      'fssnEqlist' => 'fssnEqlist',
      'kmaEqlist' => 'kmaEqlist',
      'cwaEqlist' => 'cwaEqlist',
      'emsc' => 'emscEqlist',
      _ => null,
    };
  }

  QuakeMessage _unifiedToListMessage(UnifiedQuakeData event) {
    final fallbackIntensity = IntensityCalculator.calcCsisLevel(
      event.magnitude,
      event.depth,
      0,
    );
    return _unifiedToQuakeMessage(
      event,
      isHistory: true,
      fallbackMaxIntensity: fallbackIntensity,
    );
  }

  QuakeMessage _unifiedToMapMessage(UnifiedQuakeData event) {
    return _unifiedToQuakeMessage(event);
  }

  QuakeMessage _unifiedToQuakeMessage(
    UnifiedQuakeData event, {
    bool isHistory = false,
    int? fallbackMaxIntensity,
  }) {
    final source = _unifiedSourceType(event) ?? QuakeSourceType.cenc;
    final intensity = double.tryParse(event.maxIntensity);
    final maxIntensity = intensity != null && intensity > 0
        ? intensity.round()
        : fallbackMaxIntensity;
    final isCenc = source == QuakeSourceType.cenc;
    final reviewLabel = isCenc ? _cencReviewLabel(event) : null;
    final reviewType = _unifiedReviewType(event);
    return QuakeMessage(
      source: source,
      eventId: event.eventId,
      location: event.hypocenter,
      magnitude: event.magnitude,
      latitude: event.lat ?? 0,
      longitude: event.lng ?? 0,
      depth: event.depth,
      originTime: event.originTime ?? DateTime.now(),
      reportTime: event.reportTime,
      maxIntensity: maxIntensity,
      jmaShindo: event.useShindo ? event.maxIntensity : null,
      isHistory: isHistory,
      isInfoEvent: !event.isEew,
      infoTypeName: isCenc ? reviewLabel : event.titleText,
      reviewType: isCenc ? _cencReviewType(reviewLabel) : reviewType,
      isWarn: event.isWarn,
      isFinal: event.isFinal,
      isCanceled: event.isCanceled,
      isAssumption: event.isAssumption,
      reportNumText: event.reportNumText,
      nodalPlane1: event.nodalPlane1,
      nodalPlane2: event.nodalPlane2,
    );
  }

  String _cencReviewLabel(UnifiedQuakeData event) {
    final text = '${event.reportNumText} ${event.titleText}'.toLowerCase();
    if (text.contains('正式') || text.contains('reviewed')) return '正式测定';
    return '自动测定';
  }

  String _cencReviewType(String? reviewLabel) {
    return reviewLabel == '正式测定' ? 'reviewed' : 'automatic';
  }

  bool _isCencRecentInfoUpdate(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    if (event.source != 'cencEqlist') return false;
    final oldReportTime = oldEvent.reportTime;
    final newReportTime = event.reportTime;
    if (oldReportTime == null || newReportTime == null) return false;

    // kanameishi 的 CENC 源适配使用真实 ReportTime/createTime 做 30 秒保护。
    // 当本项目因为字段缺失 fallback 到 originTime 时，不套这个窗口，避免误挡相近地震。
    if (oldEvent.originTime != null &&
        oldReportTime.isAtSameMomentAs(oldEvent.originTime!)) {
      return false;
    }
    if (event.originTime != null &&
        newReportTime.isAtSameMomentAs(event.originTime!)) {
      return false;
    }

    final diffMs = newReportTime.difference(oldReportTime).inMilliseconds;
    return diffMs >= 0 && diffMs < 30000;
  }

  bool _isSameUsgsInfoBody(UnifiedQuakeData oldEvent, UnifiedQuakeData event) {
    if (event.source != 'usgsEqlist') return false;
    if (oldEvent.source != event.source) return false;

    // kanameishi 的 USGS 去重比较不包含 reportTime/updateTime：
    // 只有更新时间变化、主体内容未变时跳过，避免重复声音和重复刷新。
    return oldEvent.eventId == event.eventId &&
        oldEvent.titleText == event.titleText &&
        oldEvent.hypocenter == event.hypocenter &&
        _sameDouble(oldEvent.lat, event.lat) &&
        _sameDouble(oldEvent.lng, event.lng) &&
        _sameDouble(oldEvent.depth, event.depth) &&
        _sameDouble(oldEvent.magnitude, event.magnitude) &&
        oldEvent.maxIntensity == event.maxIntensity &&
        oldEvent.originTime?.toUtc() == event.originTime?.toUtc();
  }

  bool _isUsgsSameReportBodyCorrection(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    if (event.source != 'usgsEqlist') return false;
    if (oldEvent.source != event.source) return false;
    if (oldEvent.eventId != event.eventId) return false;
    if (_isSameUsgsInfoBody(oldEvent, event)) return false;

    final oldReportTime = oldEvent.reportTime;
    final newReportTime = event.reportTime;
    if (oldReportTime == null || newReportTime == null) return false;

    return newReportTime.isAtSameMomentAs(oldReportTime);
  }

  @visibleForTesting
  bool isUsgsSameReportBodyCorrectionForTest(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    return _isUsgsSameReportBodyCorrection(oldEvent, event);
  }

  String? _noUpdateTimeFanInfoSourceKey(String source) {
    switch (source) {
      case 'hko':
      case 'hkoEqlist':
        return 'hko';
      case 'emsc':
      case 'emscEqlist':
        return 'emsc';
      case 'bcsf':
      case 'bcsfEqlist':
        return 'bcsf';
      case 'gfz':
      case 'gfzEqlist':
        return 'gfz';
      case 'usp':
      case 'uspEqlist':
        return 'usp';
      case 'fssnCmt':
        return 'fssnCmt';
    }
    return null;
  }

  bool _isNoUpdateTimeFanInfoSource(String source) {
    return _noUpdateTimeFanInfoSourceKey(source) != null;
  }

  bool _isLocalFanInfoWithoutReportTime(String source) {
    switch (source) {
      case 'ningxia':
      case 'guangxi':
      case 'shanxi':
      case 'beijing':
      case 'yunnan':
        return true;
    }
    return false;
  }

  bool _shouldUseArrivalTimeForUnifiedInfo(UnifiedQuakeData event) {
    return !event.isEew &&
        (_showStaleInfoEvent ||
            _isNoUpdateTimeFanInfoSource(event.source) ||
            _isLocalFanInfoWithoutReportTime(event.source));
  }

  String? _seenNoUpdateInfoEventKey(UnifiedQuakeData event) {
    if (event.isEew) return null;
    final sourceKey = _noUpdateTimeFanInfoSourceKey(event.source);
    if (sourceKey == null) return null;
    final eventId = _unifiedCanonicalEventId(event).trim();
    if (eventId.isEmpty) return null;
    return '$sourceKey|$eventId';
  }

  Future<void> _loadSeenNoUpdateInfoEvents() async {
    final prefs = await SharedPreferences.getInstance();
    _seenNoUpdateInfoEvents.clear();
    final now = DateTime.now().toUtc();
    final rows = prefs.getStringList(_seenNoUpdateInfoEventsKey) ?? const [];
    for (final row in rows) {
      final sep = row.lastIndexOf('|');
      if (sep <= 0 || sep >= row.length - 1) continue;
      final key = row.substring(0, sep);
      final seenMs = int.tryParse(row.substring(sep + 1));
      if (seenMs == null) continue;
      final seenAt = DateTime.fromMillisecondsSinceEpoch(seenMs, isUtc: true);
      if (now.difference(seenAt) <= _seenNoUpdateInfoTtl) {
        _seenNoUpdateInfoEvents[key] = seenAt;
      }
    }
    await _persistSeenNoUpdateInfoEvents();
  }

  Future<void> _persistSeenNoUpdateInfoEvents() async {
    _pruneSeenNoUpdateInfoEvents();
    final prefs = await SharedPreferences.getInstance();
    final rows = _seenNoUpdateInfoEvents.entries
        .map((entry) => '${entry.key}|${entry.value.millisecondsSinceEpoch}')
        .toList(growable: false);
    await prefs.setStringList(_seenNoUpdateInfoEventsKey, rows);
  }

  void _pruneSeenNoUpdateInfoEvents() {
    final now = DateTime.now().toUtc();
    _seenNoUpdateInfoEvents.removeWhere(
      (_, seenAt) => now.difference(seenAt) > _seenNoUpdateInfoTtl,
    );
    if (_seenNoUpdateInfoEvents.length <= _maxSeenNoUpdateInfoEvents) return;
    final sorted = _seenNoUpdateInfoEvents.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final removeCount =
        _seenNoUpdateInfoEvents.length - _maxSeenNoUpdateInfoEvents;
    for (var i = 0; i < removeCount; i++) {
      _seenNoUpdateInfoEvents.remove(sorted[i].key);
    }
  }

  void _rememberNoUpdateInfoEvent(
    UnifiedQuakeData event, {
    bool persist = true,
  }) {
    final key = _seenNoUpdateInfoEventKey(event);
    if (key == null) return;
    _seenNoUpdateInfoEvents[key] = DateTime.now().toUtc();
    _pruneSeenNoUpdateInfoEvents();
    if (persist) {
      unawaited(_persistSeenNoUpdateInfoEvents());
    }
  }

  bool _isCurrentNoUpdateInfoEvent(UnifiedQuakeData event) {
    final key = _seenNoUpdateInfoEventKey(event);
    if (key == null) return false;
    return _unifiedEvents.any((item) => _seenNoUpdateInfoEventKey(item) == key);
  }

  bool _shouldSuppressSeenNoUpdateInfoEvent(UnifiedQuakeData event) {
    final key = _seenNoUpdateInfoEventKey(event);
    if (key == null) return false;
    _pruneSeenNoUpdateInfoEvents();
    return _seenNoUpdateInfoEvents.containsKey(key) &&
        !_isCurrentNoUpdateInfoEvent(event);
  }

  @visibleForTesting
  void rememberNoUpdateInfoEventForTest(UnifiedQuakeData event) {
    _rememberNoUpdateInfoEvent(event, persist: false);
  }

  @visibleForTesting
  bool shouldSuppressSeenNoUpdateInfoEventForTest(UnifiedQuakeData event) {
    return _shouldSuppressSeenNoUpdateInfoEvent(event);
  }

  bool _isSameEventBodyChangedWithoutReportTime(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    if (!_isNoUpdateTimeFanInfoSource(event.source)) return false;
    if (_noUpdateTimeFanInfoSourceKey(oldEvent.source) !=
        _noUpdateTimeFanInfoSourceKey(event.source)) {
      return false;
    }
    if (oldEvent.eventId != event.eventId) return false;
    if (event.eventId.trim().isEmpty) return false;

    return oldEvent.titleText != event.titleText ||
        oldEvent.hypocenter != event.hypocenter ||
        !_sameDouble(oldEvent.lat, event.lat) ||
        !_sameDouble(oldEvent.lng, event.lng) ||
        !_sameDouble(oldEvent.depth, event.depth) ||
        !_sameDouble(oldEvent.magnitude, event.magnitude) ||
        oldEvent.maxIntensity != event.maxIntensity ||
        oldEvent.className != event.className ||
        oldEvent.originTime?.toUtc() != event.originTime?.toUtc();
  }

  bool _sameDouble(double? a, double? b) {
    if (a == null || b == null) return a == b;
    return (a - b).abs() < 0.000001;
  }

  String? _unifiedReviewType(UnifiedQuakeData event) {
    final text = '${event.reportNumText} ${event.titleText}'.toLowerCase();
    if (text.contains('正式') ||
        text.contains('已核实') ||
        text.contains('reviewed') ||
        text.contains('confirmed')) {
      return 'reviewed';
    }
    if (text.contains('自动') ||
        text.contains('待核实') ||
        text.contains('automatic') ||
        text.contains('unverified')) {
      return 'automatic';
    }
    return null;
  }

  void _syncUnifiedToListBucket(UnifiedQuakeData event) {
    final bucket = _unifiedListBucket(event);
    if (bucket == null) return;
    _eqlist.upsertBucketItem(bucket, _unifiedToListMessage(event));
  }

  bool _isCwaEew(UnifiedQuakeData event) {
    return event.isEew && event.source == 'cwaEew';
  }

  bool _isWolfxCwaEew(UnifiedQuakeData event) {
    return _isCwaEew(event) && event.origin == 0;
  }

  bool _isFanCwaEew(UnifiedQuakeData event) {
    return _isCwaEew(event) && event.origin != 0;
  }

  bool _shouldKeepExistingCwaWolfx(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    return _isWolfxCwaEew(oldEvent) &&
        _isFanCwaEew(event) &&
        oldEvent.eventId == event.eventId;
  }

  bool _shouldAllowCwaWolfxTakeover(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
    int reportNum,
    int? storedReportNum,
  ) {
    if (!_isFanCwaEew(oldEvent) ||
        !_isWolfxCwaEew(event) ||
        oldEvent.eventId != event.eventId ||
        storedReportNum == null) {
      return false;
    }
    final oldReportNum = _extractReportNum(oldEvent.reportNumText);
    return reportNum == storedReportNum && reportNum == oldReportNum;
  }

  void _handleUnifiedEvent(UnifiedQuakeData event) {
    debugPrint(
      'QuakeProvider: received unified event: eventId=${event.eventId}, source=${event.source}, isEew=${event.isEew}, mag=${event.magnitude}',
    );

    // kanameishi: EEW 过期检查（安全网）
    // 初始加载恢复的 EEW 如果已经过期，不应该显示
    if (event.isEew) {
      final elapsedSec = QuakeTime.calcPassedSecondsUnified(event);
      final timeoutSec = QuakeTime.eewTimeoutSecondsUnified(event);
      if (elapsedSec >= timeoutSec) {
        debugPrint(
          'QuakeProvider: EEW 已过期，跳过: eventId=${event.eventId} elapsed=${elapsedSec}s timeout=${timeoutSec}s',
        );
        return;
      }
    }

    if (!event.isEew) {
      final qst = _unifiedSourceType(event);
      if (qst != null) {
        final threshold = _sourceInfoMagFilters[qst];
        if (threshold != null && threshold < 0) {
          debugPrint('QuakeProvider: 信息事件源已设为不接收，丢弃 ${event.source}');
          return;
        }
        if (threshold != null && threshold > 0 && event.magnitude < threshold) {
          return;
        }
      }
    }

    final eventKey = _unifiedEventKey(event);
    final existingIndex = event.isEew
        ? _unifiedEvents.indexWhere(
            (e) => e.source == event.source && e.eventId == event.eventId,
          )
        : _unifiedEvents.indexWhere(
            (e) =>
                !e.isEew &&
                _unifiedInfoSlotSource(e) == _unifiedInfoSlotSource(event),
          );
    final existingEvent = existingIndex >= 0
        ? _unifiedEvents[existingIndex]
        : null;
    if (_shouldBlockDismissedUnifiedEvent(event) &&
        _dismissedUnifiedIds.contains(eventKey)) {
      // 旧事件拦截必须在同 source slot 替换前执行，防止已关闭事件重新顶回 UI。
      // 只有正式/已核实测定允许覆盖此前关闭的自动测定。
      if (_isReviewedUnifiedInfoEvent(event)) {
        debugPrint('QuakeProvider: 正式测定覆盖已关闭事件: eventId=${event.eventId}');
        _dismissedUnifiedIds.remove(eventKey);
      } else {
        debugPrint('QuakeProvider: 事件已关闭，跳过: eventId=${event.eventId}');
        return;
      }
    }

    if (_shouldSuppressSeenNoUpdateInfoEvent(event)) {
      debugPrint(
        'QuakeProvider: no-update info event already seen, list only: source=${event.source} eventId=${event.eventId}',
      );
      _syncUnifiedToListBucket(event);
      notifyListeners();
      return;
    }

    if (event.isEew) {
      final eewKey = eventKey;
      final reportNum = _extractReportNum(event.reportNumText);
      final storedReportNum = _ignoredEewIds[eewKey];
      if (existingEvent != null &&
          _shouldKeepExistingCwaWolfx(existingEvent, event)) {
        debugPrint('QuakeProvider: CWA EEW 已有 Wolfx，同事件 FAN 不覆盖: $eewKey');
        return;
      }
      if (storedReportNum != null && reportNum <= storedReportNum) {
        final canTakeover =
            existingEvent != null &&
            _shouldAllowCwaWolfxTakeover(
              existingEvent,
              event,
              reportNum,
              storedReportNum,
            );
        if (canTakeover) {
          debugPrint(
            'QuakeProvider: CWA EEW Wolfx 接管同报号 FAN: $eewKey #$reportNum',
          );
        } else {
          debugPrint(
            'QuakeProvider: 已忽略过期的 EEW: $eewKey #$storedReportNum >= #$reportNum',
          );
          return;
        }
      }
      _addToEewHistory(event);
    }

    // 信息事件按 source slot 匹配（参照 kanameishi 的 eqlistList 按 source 匹配逻辑）
    // P2PQ 的 JMA 地震信息和其它 JMA 地震信息共享一个当前 slot。
    if (existingIndex >= 0) {
      final oldEvent = _unifiedEvents[existingIndex];
      final oldKey = _unifiedEventKey(oldEvent);
      var suppressInfoActions = false;
      if (event.isEew) {
        final eewKey = eventKey;
        final reportNum = _extractReportNum(event.reportNumText);
        final storedReportNum = _ignoredEewIds[eewKey];
        if (_shouldKeepExistingCwaWolfx(oldEvent, event)) {
          debugPrint('QuakeProvider: CWA EEW 已有 Wolfx，同事件 FAN 更新不覆盖: $eewKey');
          return;
        }
        if (storedReportNum != null && reportNum <= storedReportNum) {
          final canTakeover = _shouldAllowCwaWolfxTakeover(
            oldEvent,
            event,
            reportNum,
            storedReportNum,
          );
          if (canTakeover) {
            debugPrint(
              'QuakeProvider: CWA EEW Wolfx 更新接管同报号 FAN: $eewKey #$reportNum',
            );
          } else {
            debugPrint(
              'QuakeProvider: 已忽略过期的 EEW 更新: $eewKey #$storedReportNum >= #$reportNum',
            );
            return;
          }
        }
        _ignoredEewIds[eewKey] = reportNum;
      } else {
        // 信息事件按 source 匹配：参照 kanameishi 的 EqlistEvent.update()
        // 只有 reportTime 比旧的更新时才更新（防止重复推送触发声音/重置定时器）
        if (_isSameUsgsInfoBody(oldEvent, event)) {
          debugPrint(
            'QuakeProvider: USGS 主体内容未变化，仅更新时间变化，按 kanameishi 跳过: eventId=${event.eventId}',
          );
          return;
        }
        final oldReportTime = oldEvent.reportTime;
        final newReportTime = event.reportTime;
        if (oldReportTime != null && newReportTime != null) {
          if (_isCencRecentInfoUpdate(oldEvent, event)) {
            debugPrint(
              'QuakeProvider: CENC 信息事件 30秒内更新，按 kanameishi 源适配跳过: eventId=${event.eventId}',
            );
            return;
          }
          final oldOriginTime = oldEvent.originTime;
          final newOriginTime = event.originTime;
          final isNewerReport = newReportTime.isAfter(oldReportTime);
          final isNewerOrigin =
              newReportTime.isAtSameMomentAs(oldReportTime) &&
              oldOriginTime != null &&
              newOriginTime != null &&
              newOriginTime.isAfter(oldOriginTime);
          final isSameEventBodyCorrection =
              _isSameEventBodyChangedWithoutReportTime(oldEvent, event);
          final isUsgsSameReportBodyCorrection =
              _isUsgsSameReportBodyCorrection(oldEvent, event);
          suppressInfoActions = isUsgsSameReportBodyCorrection;
          if (!isNewerReport &&
              !isNewerOrigin &&
              !isSameEventBodyCorrection &&
              !isUsgsSameReportBodyCorrection) {
            debugPrint(
              'QuakeProvider: 信息事件不新于当前 source slot，跳过: source=${event.source} eventId=${event.eventId}',
            );
            return;
          }
        }
        // 清除旧 eventId 的 dismissed 标记
        if (oldKey != eventKey) {
          _dismissedUnifiedIds.remove(oldKey);
          _unifiedDismissTimers[oldKey]?.cancel();
          _unifiedDismissTimers.remove(oldKey);
        }
      }
      _dismissedUnifiedIds.remove(eventKey);
      final isNewInfoEvent =
          !event.isEew &&
          _unifiedCanonicalEventId(oldEvent) != _unifiedCanonicalEventId(event);
      if (!event.isEew &&
          !isNewInfoEvent &&
          _isNoUpdateTimeFanInfoSource(event.source)) {
        suppressInfoActions = true;
      }
      final arrivedAt = isNewInfoEvent
          ? (event.arrivedAt ?? DateTime.now())
          : oldEvent.arrivedAt;
      final nextEvent = !event.isEew
          ? _mergeUnifiedInfoEvent(oldEvent, event)
          : event;
      _unifiedEvents[existingIndex] = nextEvent.copyWith(arrivedAt: arrivedAt);
      _sortUnifiedEvents();
      _startUnifiedCarousel();
      // EEW 每次更新重置定时器；信息事件更新不重置，防止连续推送导致事件挂住
      if (event.isEew) {
        _setupUnifiedDismissTimer(event);
      } else if (event.source == 'jmaEqlist' ||
          event.source == 'p2pJmaEqlist') {
        _setupUnifiedDismissTimer(event);
      } else if (isNewInfoEvent) {
        _unifiedDismissTimers[oldKey]?.cancel();
        _unifiedDismissTimers.remove(oldKey);
        _setupUnifiedDismissTimer(event);
      } else if (!_unifiedDismissTimers.containsKey(eventKey)) {
        _setupUnifiedDismissTimer(event);
      }
      _syncUnifiedToListBucket(nextEvent);
      _rememberNoUpdateInfoEvent(nextEvent);
      if (!suppressInfoActions) {
        _playUnifiedSound(nextEvent, isFirst: false);
      }
      notifyListeners();
      return;
    }

    _unifiedEvents.insert(
      0,
      event.copyWith(arrivedAt: event.arrivedAt ?? DateTime.now()),
    );
    if (event.isEew) {
      _ignoredEewIds[eventKey] = _extractReportNum(event.reportNumText);
    }
    _sortUnifiedEvents();
    _currentUnifiedIndex = 0;
    _startUnifiedCarousel();
    _setupUnifiedDismissTimer(event);
    _syncUnifiedToListBucket(event);
    _rememberNoUpdateInfoEvent(event);
    _playUnifiedSound(event, isFirst: true);

    notifyListeners();
  }

  UnifiedQuakeData _mergeUnifiedInfoEvent(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    if (!_isSameUnifiedJmaInfoEvent(oldEvent, event)) return event;

    var merged = event.copyWith(eventId: oldEvent.eventId);

    if (_jmaInfoTitleRank(event.titleText) <
        _jmaInfoTitleRank(oldEvent.titleText)) {
      merged = merged.copyWith(titleText: oldEvent.titleText);
    }

    if (!_hasKnownUnifiedShindo(event) && _hasKnownUnifiedShindo(oldEvent)) {
      merged = merged.copyWith(
        maxIntensity: oldEvent.maxIntensity,
        className: oldEvent.className,
      );
    }

    if (event.warnArea.trim().isEmpty && oldEvent.warnArea.trim().isNotEmpty) {
      merged = merged.copyWith(warnArea: oldEvent.warnArea);
    }

    if (!_hasUnifiedHypocenter(event) && _hasUnifiedHypocenter(oldEvent)) {
      merged = merged.copyWith(
        hypocenter: oldEvent.hypocenter,
        lat: oldEvent.lat,
        lng: oldEvent.lng,
      );
    }

    if (event.magnitude < 0 && oldEvent.magnitude >= 0) {
      merged = merged.copyWith(magnitude: oldEvent.magnitude);
    }

    if (event.depth < 0 && oldEvent.depth >= 0) {
      merged = merged.copyWith(
        depth: oldEvent.depth,
        depthText: oldEvent.depthText,
      );
    }

    return merged;
  }

  @visibleForTesting
  UnifiedQuakeData mergeUnifiedInfoEventForTest(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    return _mergeUnifiedInfoEvent(oldEvent, event);
  }

  bool _isSameUnifiedJmaInfoEvent(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    if (oldEvent.isEew || event.isEew) return false;
    if (_unifiedInfoSlotSource(oldEvent) != 'jmaEqlist' ||
        _unifiedInfoSlotSource(event) != 'jmaEqlist') {
      return false;
    }
    final oldId = _unifiedCanonicalEventId(oldEvent);
    final newId = _unifiedCanonicalEventId(event);
    return oldId.isNotEmpty && oldId == newId;
  }

  int _jmaInfoTitleRank(String title) {
    if (title.contains('各地の震度')) return 4;
    if (title.contains('震度・震源') || title.contains('震源・震度')) return 3;
    if (title.contains('震源')) return 2;
    if (title.contains('震度速報')) return 1;
    return 0;
  }

  bool _hasKnownUnifiedShindo(UnifiedQuakeData event) {
    final value = event.maxIntensity.trim();
    return value.isNotEmpty && value != '-' && value != '?' && value != '不明';
  }

  bool _hasUnifiedHypocenter(UnifiedQuakeData event) {
    final name = event.hypocenter.trim();
    if (name.isEmpty || name.contains('調査中') || name.contains('调查中')) {
      return false;
    }
    return event.lat != null && event.lng != null;
  }

  void _playUnifiedSound(UnifiedQuakeData event, {required bool isFirst}) {
    if (event.isEew) {
      if (event.isCanceled) {
        SoundEffectService().play('cancel');
        _speakUnifiedEvent(event, phase: 'cancel', isUpdate: false);
        return;
      }
      if (isFirst) {
        SoundEffectService().play('issue');
      } else if (event.isFinal) {
        SoundEffectService().play('final');
      } else {
        SoundEffectService().play('update');
      }

      final eewKey = '${event.source}|${event.eventId}';
      var phase = isFirst ? 'first' : (event.isFinal ? 'final' : 'update');
      if (event.isWarn && _eewWarnSoundIds.add(eewKey)) {
        _eewCautionSoundIds.add(eewKey);
        SoundEffectService().play('warn');
        phase = isFirst ? 'first' : 'warn';
      } else if (_isCautionClass(event.className) &&
          _eewCautionSoundIds.add(eewKey)) {
        SoundEffectService().play('caution');
        phase = isFirst ? 'first' : 'caution';
      }
      _speakUnifiedEvent(event, phase: phase, isUpdate: !isFirst);
      return;
    }

    SoundEffectService().play(_infoSoundKey(event));
    _speakUnifiedEvent(
      event,
      phase: isFirst ? 'first' : 'update',
      isUpdate: !isFirst,
    );
  }

  void _speakUnifiedEvent(
    UnifiedQuakeData event, {
    required String phase,
    required bool isUpdate,
  }) {
    final text = AlertVoiceHelper.generateUnifiedEventText(event, phase: phase);
    final reportKey = event.reportNumText.trim().isEmpty
        ? phase
        : '${phase}_${event.reportNumText.trim()}';
    TtsService().speakEvent(
      text,
      dedupeKey: '${_unifiedEventKey(event)}:$reportKey',
      isUpdate: isUpdate && phase != 'cancel' && phase != 'final',
      delay: const Duration(milliseconds: 1250),
    );
  }

  void _speakTsunamiEvent(TsunamiMessage tsunami, {int? previousStatus}) {
    final isUpdate = previousStatus != null && previousStatus == tsunami.status;
    final text = AlertVoiceHelper.generateTsunamiText(
      tsunami,
      isUpdate: isUpdate,
    );
    TtsService().speakEvent(
      text,
      dedupeKey:
          'tsunami:${tsunami.source.name}:${tsunami.id}:${tsunami.status}',
      isUpdate: isUpdate,
      delay: const Duration(milliseconds: 1250),
    );
  }

  bool _isCautionClass(String className) {
    return className == 'green' ||
        className == 'yellow' ||
        className == 'orange' ||
        className == 'dark-orange' ||
        className == 'red' ||
        className == 'dark-red' ||
        className == 'purple';
  }

  String _infoSoundKey(UnifiedQuakeData event) {
    if (event.isCanceled) return 'cancel';
    final source = event.source;
    final title = event.titleText;
    if (source == 'jmaEqlist' || source == 'p2pJmaEqlist') {
      if (title.contains('震度速報')) return 'prompt';
      if (title.contains('震源')) return 'hypocenter';
      return 'detail';
    }
    if (source == 'cencEqlist') {
      return title.contains('自动') || title.contains('自動')
          ? 'hypocenter'
          : 'detail';
    }
    if (source == 'usgsEqlist') {
      return title.contains('自动') ||
              title.contains('自動') ||
              title.contains('Automatic')
          ? 'hypocenter'
          : 'detail';
    }
    if (source == 'fssnEqlist') {
      if (title.contains('取消')) return 'cancel';
      if (title.contains('自动') || title.contains('自動')) return 'hypocenter';
      return 'detail';
    }
    return 'detail';
  }

  int _extractReportNum(String text) {
    if (text.isEmpty) return 1;
    final match = RegExp(r'\d+').firstMatch(text);
    if (match == null) return 1;
    return int.tryParse(match.group(0) ?? '1') ?? 1;
  }

  void _addToEewHistory(UnifiedQuakeData event) {
    final groupIndex = _eewHistory.indexWhere(
      (g) => g.eventId == event.eventId,
    );
    if (groupIndex >= 0) {
      _eewHistory[groupIndex] = _eewHistory[groupIndex].addReport(event);
    } else {
      _eewHistory.insert(
        0,
        EewEventGroup(
          eventId: event.eventId,
          reports: [event],
          firstArrivedAt: event.arrivedAt ?? DateTime.now(),
        ),
      );
    }
    if (_eewHistory.length > 100) {
      _eewHistory.removeRange(100, _eewHistory.length);
    }
  }

  void _sortUnifiedEvents() {
    _unifiedEvents.sort((a, b) {
      if (a.isEew && !b.isEew) return -1;
      if (!a.isEew && b.isEew) return 1;
      final aTime = a.arrivedAt ?? DateTime.now();
      final bTime = b.arrivedAt ?? DateTime.now();
      return bTime.compareTo(aTime);
    });
  }

  int _getUnifiedDismissSeconds(UnifiedQuakeData event) {
    final mag = event.magnitude;
    if (event.isEew) {
      if (event.isCanceled) return 20;
      if (event.isWarn) return (mag > 6 ? mag : 6).ceil() * 60;
      return (mag > 3 ? mag : 3).ceil() * 60;
    } else {
      int seconds = 300;
      if (event.className.contains('orange') || mag >= 6.0) seconds = 600;
      if (event.className.contains('red') || mag >= 7.0) seconds = 900;
      if (event.className == 'purple' || mag >= 7.5) seconds = 1200;
      if (event.isCanceled) seconds = 60;
      return seconds;
    }
  }

  /// 旧管道信息事件过期秒数（仅按震级判断，与统一管道逻辑一致）
  int _getDismissSecondsForInfo(double magnitude) {
    int seconds = 300;
    if (magnitude >= 6.0) seconds = 600;
    if (magnitude >= 7.0) seconds = 900;
    if (magnitude >= 7.5) seconds = 1200;
    return seconds;
  }

  void _setupUnifiedDismissTimer(UnifiedQuakeData event) {
    final key = _unifiedEventKey(event);
    _unifiedDismissTimers[key]?.cancel();
    final totalSeconds = _getUnifiedDismissSeconds(event);

    // 参照 kanameishi 的 time -= passedTime 逻辑
    // 使用 reportTime（信息事件）或 originTime（EEW）计算已过去时间
    // 当 showStaleInfoEvent 开启时，信息事件不减去已过去时间（显示完整时长）
    int elapsedSec;
    if (event.isEew) {
      elapsedSec = QuakeTime.calcPassedSecondsUnified(event);
    } else if (_shouldUseArrivalTimeForUnifiedInfo(event)) {
      elapsedSec = 0;
    } else {
      final reportTime = event.reportTime ?? event.originTime;
      if (reportTime != null) {
        elapsedSec = QuakeTime.calcPassedSecondsFromDateTime(
          reportTime,
          Duration(hours: event.timeZone),
        );
      } else {
        elapsedSec = QuakeTime.calcPassedSecondsUnified(event);
      }
    }

    final remainingSeconds = (totalSeconds - elapsedSec).clamp(1, totalSeconds);
    _unifiedDismissTimers[key] = Timer(Duration(seconds: remainingSeconds), () {
      final index = _unifiedEvents.indexWhere(
        (e) => _unifiedEventKey(e) == key,
      );
      if (index >= 0) _removeUnifiedEvent(index);
    });
  }

  void _removeUnifiedEvent(int index) {
    final event = _unifiedEvents[index];
    final key = _unifiedEventKey(event);
    _rememberNoUpdateInfoEvent(event);
    if (_shouldBlockDismissedUnifiedEvent(event)) {
      _dismissedUnifiedIds.add(key);
    }
    _unifiedDismissTimers[key]?.cancel();
    _unifiedDismissTimers.remove(key);
    _unifiedEvents.removeAt(index);

    if (event.isEew) {
      final reportNum = _extractReportNum(event.reportNumText);
      _ignoredEewIds[key] = reportNum;
      if (_ignoredEewIds.length > _maxIgnoredEewIds) {
        final firstKey = _ignoredEewIds.keys.first;
        _ignoredEewIds.remove(firstKey);
      }
    }

    if (_dismissedUnifiedIds.length > 200) {
      final firstKey = _dismissedUnifiedIds.first;
      _dismissedUnifiedIds.remove(firstKey);
    }

    if (_unifiedEvents.isEmpty) {
      _currentUnifiedIndex = 0;
      _unifiedCarouselTimer?.cancel();
      onAllEventsExpired?.call();
    } else {
      _currentUnifiedIndex = _currentUnifiedIndex.clamp(
        0,
        _unifiedEvents.length - 1,
      );
      _startUnifiedCarousel();
    }

    notifyListeners();
  }

  bool _shouldBlockDismissedUnifiedEvent(UnifiedQuakeData event) {
    if (!event.isEew && event.source == 'cwaEqlist') return false;
    return true;
  }

  void _clearLegacyActiveQuakePipeline() {
    for (final warning in _activeWarnings) {
      warning.dismissTimer?.cancel();
    }
    _activeWarnings.clear();
    _activeInfoEvents.clear();
    _currentWarningIndex = 0;
    _isShowingInfoEvent = false;
    _isShowingTempInfo = false;
    _currentDistance = 0.0;
    _estimatedIntensity = 0.0;
    _countdownTimer?.cancel();
    _carouselTimer?.cancel();
    _infoDismissTimer?.cancel();
    _tempInfoDisplayTimer?.cancel();
    if (_unifiedEvents.isEmpty) {
      _currentEvent = null;
    }
  }

  void nextUnified() {
    if (_unifiedEvents.length <= 1) return;
    _currentUnifiedIndex = (_currentUnifiedIndex + 1) % _unifiedEvents.length;
    notifyListeners();
  }

  void prevUnified() {
    if (_unifiedEvents.length <= 1) return;
    _currentUnifiedIndex =
        (_currentUnifiedIndex - 1 + _unifiedEvents.length) %
        _unifiedEvents.length;
    notifyListeners();
  }

  void _startUnifiedCarousel() {
    _unifiedCarouselTimer?.cancel();
    if (_unifiedEvents.length <= 1) return;
    _unifiedCarouselTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      nextUnified();
    });
  }

  /// 重建扁平化历史列表
  ///
  /// 根据过滤条件从各数据源桶中合并历史记录。
  void _rebuildFlat() {
    try {
      final merged = <QuakeMessage>[];
      final buckets = historyBySource;
      for (final entry in buckets.entries) {
        if (!_sourceFilter.contains(entry.key)) continue;
        final sourceType = _unifiedToQst[entry.key];
        final sourceThreshold = sourceType == null
            ? null
            : _sourceInfoMagFilters[sourceType];
        if (sourceThreshold != null && sourceThreshold < 0) continue;
        for (final e in entry.value) {
          if (sourceThreshold != null &&
              sourceThreshold > 0 &&
              e.magnitude < sourceThreshold) {
            continue;
          }
          if (_magFilter > 0 && e.magnitude < _magFilter) continue;
          merged.add(e);
        }
      }
      _dedupeJmaHistoryEvents(merged);
      merged.sort((a, b) {
        final utcA = _toUtc(a);
        final utcB = _toUtc(b);
        return utcB.compareTo(utcA);
      });
      if (merged.length > 100) merged.removeRange(100, merged.length);
      _flatHistory = merged;
      notifyListeners();
    } catch (e) {
      print('_rebuildFlat error: $e');
    }
  }

  void _dedupeJmaHistoryEvents(List<QuakeMessage> items) {
    final seen = <String, int>{};
    var i = 0;
    while (i < items.length) {
      final key = _jmaHistoryDedupeKey(items[i]);
      if (key == null) {
        i++;
        continue;
      }
      final existingIndex = seen[key];
      if (existingIndex == null) {
        seen[key] = i;
        i++;
        continue;
      }
      final preferred = _preferJmaHistoryEvent(items[existingIndex], items[i]);
      items[existingIndex] = preferred;
      items.removeAt(i);
    }
  }

  String? _jmaHistoryDedupeKey(QuakeMessage event) {
    if (!_isJmaHistorySource(event.source)) return null;
    final location = event.location.trim().replaceAll(RegExp(r'\s+'), '');
    if (location.isEmpty) return null;
    final originMinute =
        _toUtc(event).millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute;
    final magnitude = (event.magnitude * 10).round();
    final depth = event.depth.round();
    return '$originMinute|$location|$magnitude|$depth';
  }

  bool _isJmaHistorySource(QuakeSourceType source) {
    return source == QuakeSourceType.wolfx ||
        source == QuakeSourceType.jma_fan ||
        source == QuakeSourceType.p2p;
  }

  QuakeMessage _preferJmaHistoryEvent(QuakeMessage a, QuakeMessage b) {
    final aReviewed = _isReviewedJmaHistoryEvent(a);
    final bReviewed = _isReviewedJmaHistoryEvent(b);
    if (aReviewed != bReviewed) return bReviewed ? b : a;
    final aReport = a.reportTime;
    final bReport = b.reportTime;
    if (aReport != null && bReport != null && bReport.isAfter(aReport)) {
      return b;
    }
    return a;
  }

  bool _isReviewedJmaHistoryEvent(QuakeMessage event) {
    final text =
        '${event.infoTypeName ?? ''} ${event.reviewType ?? ''} '
                '${event.reportNumText ?? ''} ${event.tsunamiWarning ?? ''}'
            .toLowerCase();
    return text.contains('reviewed') ||
        text.contains('confirmed') ||
        text.contains('正式') ||
        text.contains('確定') ||
        text.contains('已核实');
  }

  /// 将地震事件时间转换为 UTC 时间
  ///
  /// 用于排序时统一比较不同时区的事件。
  /// - 日本/韩国数据源: originTime 被视为 UTC+9，转换为 UTC
  /// - 其他数据源: originTime 被视为 UTC+8，转换为 UTC
  DateTime _toUtc(QuakeMessage event) {
    final t = event.originTime;
    final offset = QuakeTime.isJapanSource(event.source)
        ? const Duration(hours: 9)
        : const Duration(hours: 8);
    return DateTime.utc(
      t.year,
      t.month,
      t.day,
      t.hour,
      t.minute,
      t.second,
      t.millisecond,
      t.microsecond,
    ).subtract(offset);
  }

  /// 判断是否为预警数据源
  ///
  /// 预警数据源提供紧急地震速报，需要优先显示和语音提醒。
  bool _isWarningSource(QuakeSourceType source) {
    switch (source) {
      case QuakeSourceType.wolfx:
      case QuakeSourceType.cenc:
      case QuakeSourceType.sc_eew:
      case QuakeSourceType.fj_eew:
      case QuakeSourceType.cq_eew:
      case QuakeSourceType.cwa_eew:
      case QuakeSourceType.cea:
      case QuakeSourceType.cea_pr:
      case QuakeSourceType.jma_fan:
      case QuakeSourceType.sa:
      case QuakeSourceType.kma_eew_fan:
        return true;
      default:
        return false;
    }
  }

  /// 判断是否为信息事件数据源
  ///
  /// 信息事件数据源提供正式测定的地震信息。
  bool _isInfoEventSource(QuakeSourceType source) {
    switch (source) {
      case QuakeSourceType.cenc:
      case QuakeSourceType.usgs:
      case QuakeSourceType.cwa:
      case QuakeSourceType.fssn:
      case QuakeSourceType.fssnCmt:
      case QuakeSourceType.p2p:
      case QuakeSourceType.hko:
      case QuakeSourceType.emsc:
      case QuakeSourceType.bcsf:
      case QuakeSourceType.gfz:
      case QuakeSourceType.usp:
      case QuakeSourceType.kma_eq:
      case QuakeSourceType.ningxia:
      case QuakeSourceType.guangxi:
      case QuakeSourceType.shanxi:
      case QuakeSourceType.beijing:
      case QuakeSourceType.yunnan:
        return true;
      default:
        return false;
    }
  }

  /// 处理新地震事件
  ///
  /// 从 EventBus 接收地震消息并进行处理。
  void _handleNewQuake(QuakeMessage event) async {
    try {
      await _handleNewQuakeInternal(event);
    } catch (e, stack) {
      final lines = stack.toString().split('\n');
      final short = lines.take(5).join('\n');
      print('_handleNewQuake error: $e\n$short');
    }
  }

  /// 处理新地震事件的内部实现
  ///
  /// 完整的事件处理流程：
  /// 1. 存入数据库
  /// 2. 计算距离和烈度
  /// 3. 更新预警/信息列表
  /// 4. 触发通知和语音
  Future<void> _handleNewQuakeInternal(QuakeMessage event) async {
    if (_isHandledByUnifiedPipeline(event)) {
      debugPrint(
        'QuakeProvider: 旧管道拦截，改走新管道: source=${event.source} eventId=${event.eventId}',
      );
      return;
    }

    try {
      await DatabaseHelper().insertQuake(event);
    } catch (e) {
      print('Database insert error: $e');
    }

    if (event.source == QuakeSourceType.cwa ||
        event.source == QuakeSourceType.cwa_eew) {
      debugPrint(
        'QuakeProvider: 收到CWA事件 source=${event.source} eventId=${event.eventId} isHistory=${event.isHistory} isInfoEvent=${event.isInfoEvent} mag=${event.magnitude}',
      );
    }

    if (_legacyActiveQuakePipelineDisabled) {
      _clearLegacyActiveQuakePipeline();
      if (event.isHistory ||
          event.isInfoEvent ||
          _isInfoEventSource(event.source)) {
        _routeToBucket(event);
        _rebuildFlat();
      }
      if (_unifiedEvents.isEmpty) {
        _currentEvent = null;
        onAllEventsExpired?.call();
      }
      notifyListeners();
      return;
    }

    if (event.isHistory) {
      _routeToBucket(event);
      _rebuildFlat();
      return;
    }

    // kanameishi: EEW 过期检查（旧管道安全网）
    // 对预警事件，检查是否已经过期，过期则直接入桶不显示预警卡片
    final bool isWarningForExpiry =
        _isWarningSource(event.source) && !event.isInfoEvent;
    if (isWarningForExpiry) {
      final elapsedSec = QuakeTime.calcPassedSeconds(event);
      final timeoutSec = QuakeTime.eewTimeoutSeconds(event);
      if (elapsedSec >= timeoutSec) {
        debugPrint(
          'QuakeProvider: EEW 已过期(旧管道)，入桶: eventId=${event.eventId} elapsed=${elapsedSec}s timeout=${timeoutSec}s',
        );
        _routeToBucket(event);
        _rebuildFlat();
        return;
      }
    }

    // 信息事件过期检查（旧管道安全网，与统一管道逻辑一致）
    final bool treatAsInfo = _isInfoEventSource(event.source);
    if (treatAsInfo && !_showStaleInfoEvent) {
      final reportTime = event.reportTime;
      if (reportTime != null) {
        final elapsedSec = QuakeTime.calcPassedSeconds(event);
        final dismissSec = _getDismissSecondsForInfo(event.magnitude);
        if (elapsedSec >= dismissSec) {
          debugPrint(
            'QuakeProvider: 信息事件已过期(旧管道)，入桶: eventId=${event.eventId} elapsed=${elapsedSec}s dismiss=${dismissSec}s',
          );
          _routeToBucket(event);
          _rebuildFlat();
          return;
        }
      }
    }

    // 信息事件源震级过滤：该源设了阈值且震级低于阈值则丢弃
    // 必须在 _routeToBucket 之前检查，防止低震级事件进入列表
    if (treatAsInfo) {
      final threshold = _sourceInfoMagFilters[event.source];
      if (threshold != null && threshold < 0) {
        debugPrint('QuakeProvider: 信息事件源已设为不接收，丢弃 ${event.source}');
        return;
      }
      if (threshold != null && threshold > 0 && event.magnitude < threshold) {
        debugPrint(
          'QuakeProvider: 信息事件震级过滤 [$threshold] 丢弃 ${event.source} M${event.magnitude}',
        );
        return;
      }
    }

    _routeToBucket(event);

    final userPos = LocationService().currentPosition;
    double distance = 0.0;
    if (userPos != null) {
      try {
        distance = QuakeCalculator.haversineDistance(
          userPos.latitude,
          userPos.longitude,
          event.latitude,
          event.longitude,
        );
      } catch (e) {
        print('Distance calculation error: $e');
        distance = 0.0;
      }
    }

    double intensity = 0.0;
    if (event.maxIntensity != null && event.maxIntensity! > 0) {
      intensity = event.maxIntensity!.toDouble();
    } else if (userPos != null) {
      try {
        intensity = IntensityCalculator.calculate(
          mag: event.magnitude,
          distance: distance,
        );
      } catch (e) {
        print('Intensity calculation error: $e');
        intensity = 0.0;
      }
    }

    QuakeMessage runtimeEvent = event;
    bool updatedExistingWarning = false;

    // 分发逻辑：isInfoEvent 覆盖优先
    // 某些源（如 cenc）可同时为预警源和情报源，靠 isInfoEvent 区分
    final bool treatAsWarning =
        _isWarningSource(event.source) && !event.isInfoEvent;

    if (_dismissedLegacyIds.contains(event.eventId)) {
      final changed = _purgeLegacyEventEntries(event.eventId);
      debugPrint('QuakeProvider: [旧管道] 事件已关闭，跳过: eventId=${event.eventId}');
      if (changed) {
        _reconcileLegacyDisplayAfterRemoval();
      }
      return;
    }

    if (treatAsWarning) {
      if (event.isCanceled) {
        // 取消报：标记并缩短过期时间
        final existingIndex = _activeWarnings.indexWhere(
          (w) => w.event.eventId == event.eventId,
        );
        if (existingIndex >= 0) {
          runtimeEvent = event.copyWith(
            originTime: _activeWarnings[existingIndex].event.originTime,
          );
          _activeWarnings[existingIndex].event = runtimeEvent;
          _activeWarnings[existingIndex].dismissTimer?.cancel();
          _activeWarnings[existingIndex].dismissTimer = Timer(
            Duration(seconds: 20),
            () {
              _removeWarning(existingIndex);
            },
          );
          updatedExistingWarning = true;
        }
      } else {
        final existingIndex = _activeWarnings.indexWhere(
          (w) => w.event.eventId == event.eventId,
        );
        if (existingIndex >= 0) {
          updatedExistingWarning = true;
          final preservedOrigin =
              _activeWarnings[existingIndex].event.originTime;
          runtimeEvent = event.copyWith(originTime: preservedOrigin);
          _activeWarnings[existingIndex].update(
            runtimeEvent,
            distance,
            intensity,
          );
          _resetWarningDismiss(existingIndex);
        } else {
          // kanameishi: 计算剩余显示时间
          // 用 QuakeTime.calcPassedSeconds 正确处理时区
          final elapsedSec = QuakeTime.calcPassedSeconds(event);
          final totalTimeout = QuakeTime.eewTimeoutSeconds(event);
          final remaining = (totalTimeout - elapsedSec).clamp(1, totalTimeout);
          final warning = ActiveWarning(
            event: event,
            distance: distance,
            estimatedIntensity: intensity,
            remainingSeconds: elapsedSec > 0 ? remaining : null,
          );
          _activeWarnings.insert(0, warning);
          _currentWarningIndex = 0;
          _isShowingInfoEvent = false;
          _setupWarningDismiss(warning, 0);
          _startCarousel();
        }
      }
    } else if (treatAsInfo) {
      final existingIndex = _activeInfoEvents.indexWhere(
        (i) => i.event.eventId == event.eventId,
      );
      if (existingIndex >= 0) {
        final old = _activeInfoEvents[existingIndex];
        final preservedOrigin = old.event.originTime;
        runtimeEvent = event.copyWith(
          originTime: preservedOrigin,
          // 保留旧事件中的 reportNumText（FAN cenc 不设它，但 jma_fan 会设）
          reportNumText: old.event.reportNumText,
        );
      }
      final infoEvent = ActiveInfoEvent(
        event: runtimeEvent,
        distance: distance,
        estimatedIntensity: intensity,
        receivedAt: DateTime.now(),
      );
      if (existingIndex >= 0) {
        _activeInfoEvents[existingIndex] = infoEvent;
      } else {
        _activeInfoEvents.insert(0, infoEvent);
      }
      _sortInfoEvents();

      if (_activeWarnings.isNotEmpty) {
        _showTempInfoEvent(infoEvent);
      } else {
        _isShowingInfoEvent = true;
        _startCarousel();
        _startInfoDismissTimer();
      }
    }

    final bool isSameCurrentEvent =
        _currentEvent?.eventId == runtimeEvent.eventId;
    _currentEvent = runtimeEvent;
    _currentDistance = distance;
    _estimatedIntensity = intensity;
    if (!isSameCurrentEvent) {
      _lastSpokenSeconds = -1;
    }

    try {
      await DatabaseHelper().insertQuake(event);
    } catch (e) {
      print('Database insert error (2nd): $e');
    }

    if (!kIsWeb && Platform.isWindows) _handleWindowsAlert(event);

    if (!isSameCurrentEvent || !updatedExistingWarning) {
      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _updateCountdownLogic();
      });
    }

    notifyListeners();
  }

  /// 启动轮播定时器
  ///
  /// 当有多个活动事件时，自动轮播显示。
  void _startCarousel() {
    _carouselTimer?.cancel();
    final total =
        _activeWarnings.length +
        (_isShowingInfoEvent ? _activeInfoEvents.length : 0);
    if (total <= 1) return;
    _carouselTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      try {
        if (_activeWarnings.isNotEmpty) {
          _currentWarningIndex =
              (_currentWarningIndex + 1) % _activeWarnings.length;
          final warning = _activeWarnings[_currentWarningIndex];
          _currentEvent = warning.event;
          _currentDistance = warning.distance;
          _estimatedIntensity = warning.estimatedIntensity;
          _lastSpokenSeconds = warning.lastSpokenSeconds;
        } else if (_activeInfoEvents.isNotEmpty) {
          _currentWarningIndex =
              (_currentWarningIndex + 1) % _activeInfoEvents.length;
          final info = _activeInfoEvents[_currentWarningIndex];
          _currentEvent = info.event;
          _currentDistance = info.distance;
          _estimatedIntensity = info.estimatedIntensity;
          _lastSpokenSeconds = -1;
        }
        notifyListeners();
      } catch (e) {
        print('Carousel timer error: $e');
      }
    });
  }

  /// 临时显示信息事件
  ///
  /// 当有预警事件时收到信息事件，临时显示5秒后切回预警。
  void _showTempInfoEvent(ActiveInfoEvent infoEvent) {
    _tempInfoDisplayTimer?.cancel();
    _isShowingTempInfo = true;
    _currentEvent = infoEvent.event;
    _currentDistance = infoEvent.distance;
    _estimatedIntensity = infoEvent.estimatedIntensity;
    notifyListeners();

    _tempInfoDisplayTimer = Timer(
      Duration(seconds: _tempInfoDisplayDuration),
      () {
        _isShowingTempInfo = false;
        if (_activeWarnings.isNotEmpty) {
          _currentWarningIndex = _currentWarningIndex.clamp(
            0,
            _activeWarnings.length - 1,
          );
          _switchToWarning(_currentWarningIndex);
        } else if (_activeInfoEvents.isNotEmpty) {
          _isShowingInfoEvent = true;
          _switchToInfoEvent(0);
        } else {
          _currentEvent = null;
          onAllEventsExpired?.call();
        }
        notifyListeners();
      },
    );
  }

  /// 启动信息事件自动关闭定时器
  ///
  /// 信息事件在指定时间后自动关闭。
  void _startInfoDismissTimer() {
    _infoDismissTimer?.cancel();
    _infoDismissTimer = Timer(Duration(seconds: _infoDismissDuration), () {
      if (_activeInfoEvents.isNotEmpty) {
        final dismissed = _activeInfoEvents.removeAt(0);
        _dismissedLegacyIds.add(dismissed.event.eventId);
        if (_dismissedLegacyIds.length > 200) {
          _dismissedLegacyIds.remove(_dismissedLegacyIds.first);
        }
        if (_activeInfoEvents.isEmpty) {
          _isShowingInfoEvent = false;
          _currentEvent = null;
          onAllEventsExpired?.call();
        } else {
          _currentEvent = _activeInfoEvents[0].event;
          _currentDistance = _activeInfoEvents[0].distance;
          _estimatedIntensity = _activeInfoEvents[0].estimatedIntensity;
        }
        notifyListeners();
      }
    });
  }

  /// 对信息事件进行排序
  ///
  /// 优先显示本地区域的事件，并优先使用官方数据源。
  void _sortInfoEvents() {
    _activeInfoEvents.sort((a, b) {
      final aLat = a.event.latitude;
      final aLon = a.event.longitude;
      final bLat = b.event.latitude;
      final bLon = b.event.longitude;

      final aInChina = _isInChina(aLat, aLon);
      final bInChina = _isInChina(bLat, bLon);
      final aInJapan = _isInJapan(aLat, aLon);
      final bInJapan = _isInJapan(bLat, bLon);
      final aInTaiwan = _isInTaiwan(aLat, aLon);
      final bInTaiwan = _isInTaiwan(bLat, bLon);

      final aIsPreferred =
          (aInChina && a.event.source == QuakeSourceType.cenc) ||
          (aInJapan && a.event.source == QuakeSourceType.wolfx) ||
          (aInTaiwan && a.event.source == QuakeSourceType.cwa);
      final bIsPreferred =
          (bInChina && b.event.source == QuakeSourceType.cenc) ||
          (bInJapan && b.event.source == QuakeSourceType.wolfx) ||
          (bInTaiwan && b.event.source == QuakeSourceType.cwa);

      if (aIsPreferred && !bIsPreferred) return -1;
      if (!aIsPreferred && bIsPreferred) return 1;

      if (aInChina && !bInChina) return -1;
      if (!aInChina && bInChina) return 1;
      if (aInJapan && !bInJapan) return -1;
      if (!aInJapan && bInJapan) return 1;
      if (aInTaiwan && !bInTaiwan) return -1;
      if (!aInTaiwan && bInTaiwan) return 1;

      return b.receivedAt.compareTo(a.receivedAt);
    });
  }

  /// 判断坐标是否在中国境内
  bool _isInChina(double lat, double lon) {
    return lat >= 18.0 && lat <= 54.0 && lon >= 73.0 && lon <= 135.0;
  }

  /// 判断坐标是否在日本境内
  bool _isInJapan(double lat, double lon) {
    return lat >= 24.0 && lat <= 46.0 && lon >= 122.0 && lon <= 146.0;
  }

  /// 判断坐标是否在台湾境内
  bool _isInTaiwan(double lat, double lon) {
    return lat >= 21.0 && lat <= 26.0 && lon >= 119.0 && lon <= 122.0;
  }

  /// 切换到下一个预警/信息事件
  void nextWarning() {
    if (_legacyActiveQuakePipelineDisabled) return;
    if (_activeWarnings.isNotEmpty) {
      _currentWarningIndex =
          (_currentWarningIndex + 1) % _activeWarnings.length;
      _switchToWarning(_currentWarningIndex);
    } else if (_activeInfoEvents.isNotEmpty) {
      _currentWarningIndex =
          (_currentWarningIndex + 1) % _activeInfoEvents.length;
      _switchToInfoEvent(_currentWarningIndex);
    }
  }

  /// 切换到上一个预警/信息事件
  void prevWarning() {
    if (_legacyActiveQuakePipelineDisabled) return;
    if (_activeWarnings.isNotEmpty) {
      _currentWarningIndex =
          (_currentWarningIndex - 1 + _activeWarnings.length) %
          _activeWarnings.length;
      _switchToWarning(_currentWarningIndex);
    } else if (_activeInfoEvents.isNotEmpty) {
      _currentWarningIndex =
          (_currentWarningIndex - 1 + _activeInfoEvents.length) %
          _activeInfoEvents.length;
      _switchToInfoEvent(_currentWarningIndex);
    }
  }

  /// 切换到指定索引的预警事件
  void _switchToWarning(int index) {
    if (_legacyActiveQuakePipelineDisabled) return;
    final warning = _activeWarnings[index];
    _currentEvent = warning.event;
    _currentDistance = warning.distance;
    _estimatedIntensity = warning.estimatedIntensity;
    _lastSpokenSeconds = warning.lastSpokenSeconds;
    _isShowingInfoEvent = false;
    _startCarousel();
    notifyListeners();
  }

  /// 切换到指定索引的信息事件
  void _switchToInfoEvent(int index) {
    if (_legacyActiveQuakePipelineDisabled) return;
    final info = _activeInfoEvents[index];
    _currentEvent = info.event;
    _currentDistance = info.distance;
    _estimatedIntensity = info.estimatedIntensity;
    _lastSpokenSeconds = -1;
    _isShowingInfoEvent = true;
    _startCarousel();
    notifyListeners();
  }

  /// 关闭指定的预警事件
  bool _purgeLegacyEventEntries(String eventId) {
    if (_legacyActiveQuakePipelineDisabled) return false;
    var changed = false;
    _activeWarnings.removeWhere((w) {
      if (w.event.eventId != eventId) return false;
      w.dismissTimer?.cancel();
      changed = true;
      return true;
    });
    _activeInfoEvents.removeWhere((i) {
      if (i.event.eventId != eventId) return false;
      changed = true;
      return true;
    });
    if (_currentEvent?.eventId == eventId) {
      changed = true;
    }
    return changed;
  }

  void _reconcileLegacyDisplayAfterRemoval() {
    if (_legacyActiveQuakePipelineDisabled) {
      _clearLegacyActiveQuakePipeline();
      notifyListeners();
      return;
    }
    if (_activeWarnings.isEmpty && _activeInfoEvents.isEmpty) {
      _currentEvent = null;
      _currentDistance = 0;
      _estimatedIntensity = 0;
      _lastSpokenSeconds = -1;
      _carouselTimer?.cancel();
      _countdownTimer?.cancel();
      _tempInfoDisplayTimer?.cancel();
      _isShowingTempInfo = false;
      _isShowingInfoEvent = false;
      onAllEventsExpired?.call();
      notifyListeners();
      return;
    }

    if (_activeWarnings.isNotEmpty) {
      _currentWarningIndex = _currentWarningIndex.clamp(
        0,
        _activeWarnings.length - 1,
      );
      _switchToWarning(_currentWarningIndex);
      return;
    }

    _currentWarningIndex = _currentWarningIndex.clamp(
      0,
      _activeInfoEvents.length - 1,
    );
    _switchToInfoEvent(_currentWarningIndex);
  }

  void dismissWarning(String eventId) {
    if (_legacyActiveQuakePipelineDisabled) return;
    _activeWarnings.removeWhere((w) => w.event.eventId == eventId);
    _dismissedLegacyIds.add(eventId);
    if (_dismissedLegacyIds.length > 200) {
      _dismissedLegacyIds.remove(_dismissedLegacyIds.first);
    }
    if (_activeWarnings.isEmpty) {
      _carouselTimer?.cancel();
      if (_activeInfoEvents.isNotEmpty) {
        _isShowingInfoEvent = true;
        _currentWarningIndex = 0;
        _switchToInfoEvent(0);
      } else {
        _currentEvent = null;
        _countdownTimer?.cancel();
        onAllEventsExpired?.call();
      }
    } else {
      _currentWarningIndex = _currentWarningIndex.clamp(
        0,
        _activeWarnings.length - 1,
      );
      _switchToWarning(_currentWarningIndex);
    }
    notifyListeners();
  }

  /// 关闭指定的信息事件
  void dismissInfoEvent(String eventId) {
    if (_legacyActiveQuakePipelineDisabled) return;
    _activeInfoEvents.removeWhere((i) => i.event.eventId == eventId);
    _dismissedLegacyIds.add(eventId);
    if (_dismissedLegacyIds.length > 200) {
      _dismissedLegacyIds.remove(_dismissedLegacyIds.first);
    }
    if (_activeInfoEvents.isEmpty && _activeWarnings.isEmpty) {
      _currentEvent = null;
      _carouselTimer?.cancel();
      _countdownTimer?.cancel();
      onAllEventsExpired?.call();
    } else if (_isShowingInfoEvent && _activeInfoEvents.isNotEmpty) {
      _currentWarningIndex = _currentWarningIndex.clamp(
        0,
        _activeInfoEvents.length - 1,
      );
      _switchToInfoEvent(_currentWarningIndex);
    }
    notifyListeners();
  }

  /// 更新 CENC 烈度速报数据
  void updateCencIrData(CencIrData data) {
    _cencIrData = data;
    notifyListeners();
  }

  /// 手动请求 CENC 烈度速报详情
  ///
  /// 根据事件 [id] 发送 cencirdetail 请求，
  /// 获取完整烈度数据并在地图上显示。
  void requestCencIrDetail(String id) {
    final fanService = SourceManager().getSource<FanService>();
    fanService?.requestCencIrDetail(id);
  }

  /// 清除当前地图上的 CENC 烈度速报数据
  void clearCencIrData() {
    _cencIrData = null;
    notifyListeners();
  }

  /// 处理 Windows 平台的预警窗口
  void _handleWindowsAlert(QuakeMessage event) async {
    try {
      if (_estimatedIntensity >= 2.0 || event.magnitude >= 4.5) {
        await WindowsManager().forceShowAlert();
      }
    } catch (e) {
      print('_handleWindowsAlert error: $e');
    }
  }

  /// 将事件路由到对应的数据桶
  void _routeToBucket(QuakeMessage event) {
    try {
      switch (event.source) {
        case QuakeSourceType.fssn:
          _eqlist.addFssnItem(event);
          _rebuildFlat();
          break;
        case QuakeSourceType.kma_eq:
          _eqlist.addKmaItem(event);
          _rebuildFlat();
          break;
        case QuakeSourceType.kma_eew_fan:
          // KMA EEW 不上列表，仅作为预警卡片显示
          break;
        case QuakeSourceType.cwa:
          _eqlist.addCwaItem(event);
          _rebuildFlat();
          break;
        case QuakeSourceType.cwa_eew:
          // CWA EEW 不上列表，仅作为预警卡片显示
          break;
        case QuakeSourceType.cenc:
          _eqlist.addCencItem(event);
          _rebuildFlat();
          break;
        case QuakeSourceType.cea:
        case QuakeSourceType.cea_pr:
        case QuakeSourceType.hko:
        case QuakeSourceType.emsc:
        case QuakeSourceType.bcsf:
        case QuakeSourceType.gfz:
        case QuakeSourceType.usp:
        case QuakeSourceType.ningxia:
        case QuakeSourceType.guangxi:
        case QuakeSourceType.shanxi:
        case QuakeSourceType.beijing:
        case QuakeSourceType.yunnan:
          // 不上列表，仅作为信息事件卡片显示
          break;
        default:
          break;
      }
    } catch (e) {
      print('_routeToBucket error: $e');
    }
  }

  /// 更新倒计时逻辑
  ///
  /// 每秒执行一次，计算地震波到达倒计时并触发语音提醒。
  void _updateCountdownLogic() {
    try {
      if (_currentEvent == null) return;

      _cleanExpiredWarnings();

      if (_isShowingInfoEvent && _activeWarnings.isEmpty) {
        notifyListeners();
        return;
      }

      final double sArrival = _currentDistance / 3.5;
      final normalizedOrigin = QuakeTime.normalizedOriginLocal(_currentEvent!);
      final double elapsed = QuakeCalculator.getElapsedSeconds(
        normalizedOrigin,
        NtpService().now,
      );
      final int countdown = (sArrival - elapsed).floor();
      _triggerVoiceAlert(countdown);
      if (countdown < -60) {
        _countdownTimer?.cancel();
        if (!kIsWeb && Platform.isWindows) {
          try {
            WindowsManager().resetWindowState();
          } catch (_) {}
        }
      }
      notifyListeners();
    } catch (e) {
      print('_updateCountdownLogic error: $e');
    }
  }

  /// 清理过期的预警和信息事件
  void _cleanExpiredWarnings() {
    try {
      final now = NtpService().now;
      _activeWarnings.removeWhere((w) {
        if (w.dismissTimer?.isActive == true) return false;
        final elapsed = now
            .toUtc()
            .difference(w.event.originTime.toUtc())
            .inSeconds
            .abs();
        final expired = elapsed > w.timeoutSeconds + 60;
        if (expired) {
          _dismissedLegacyIds.add(w.event.eventId);
        }
        return expired;
      });
      _activeInfoEvents.removeWhere((i) {
        final elapsed = now.difference(i.receivedAt).inSeconds;
        final expired = elapsed > 300;
        if (expired) {
          _dismissedLegacyIds.add(i.event.eventId);
        }
        return expired;
      });
      if (_dismissedLegacyIds.length > 200) {
        _dismissedLegacyIds.remove(_dismissedLegacyIds.first);
      }
      if (_activeWarnings.isEmpty && _activeInfoEvents.isEmpty) {
        _currentEvent = null;
        _carouselTimer?.cancel();
        _countdownTimer?.cancel();
        _tempInfoDisplayTimer?.cancel();
        _isShowingTempInfo = false;
        _isShowingInfoEvent = false;
        onAllEventsExpired?.call();
      } else if (_activeWarnings.isNotEmpty) {
        if (_currentWarningIndex >= _activeWarnings.length) {
          _currentWarningIndex = 0;
          _switchToWarning(0);
        }
      } else if (_activeInfoEvents.isNotEmpty) {
        if (_currentWarningIndex >= _activeInfoEvents.length) {
          _currentWarningIndex = 0;
          _switchToInfoEvent(0);
        }
      }
    } catch (e) {
      print('_cleanExpiredWarnings error: $e');
    }
  }

  /// 设置预警自动移除定时器
  ///
  /// 参考 kanameishi 的 terminate 策略。
  void _setupWarningDismiss(ActiveWarning warning, int index) {
    warning.dismissTimer?.cancel();
    final int dismissSec = warning.remainingSeconds ?? warning.timeoutSeconds;
    warning.dismissTimer = Timer(Duration(seconds: dismissSec), () {
      _removeWarning(index);
    });
  }

  /// 重置预警自动移除定时器
  ///
  /// 事件更新时重置定时器，延长显示时间。
  void _resetWarningDismiss(int index) {
    if (index >= 0 && index < _activeWarnings.length) {
      _setupWarningDismiss(_activeWarnings[index], index);
    }
  }

  /// 移除预警
  ///
  /// 从活动预警列表中移除并清理资源。
  void _removeWarning(int index) {
    if (index >= 0 && index < _activeWarnings.length) {
      final removed = _activeWarnings[index];
      _dismissedLegacyIds.add(removed.event.eventId);
      if (_dismissedLegacyIds.length > 200) {
        _dismissedLegacyIds.remove(_dismissedLegacyIds.first);
      }
      _activeWarnings[index].dismissTimer?.cancel();
      _activeWarnings.removeAt(index);
      if (_activeWarnings.isEmpty) {
        _carouselTimer?.cancel();
        _currentWarningIndex = 0;
        _isShowingTempInfo = false;
        if (_activeInfoEvents.isNotEmpty) {
          _isShowingInfoEvent = true;
          _switchToInfoEvent(0);
        } else {
          _currentEvent = null;
          onAllEventsExpired?.call();
        }
      } else {
        if (_currentWarningIndex >= _activeWarnings.length) {
          _currentWarningIndex = 0;
        }
        final warning = _activeWarnings[_currentWarningIndex];
        _currentEvent = warning.event;
        _currentDistance = warning.distance;
        _estimatedIntensity = warning.estimatedIntensity;
      }
      notifyListeners();
    }
  }

  /// 触发语音警报
  ///
  /// 根据倒计时播报相应的语音提醒。
  void _triggerVoiceAlert(int countdown) {
    try {
      if (_currentEvent == null) return;
      if (_lastSpokenSeconds == -1 && countdown > 0) {
        final text = AlertVoiceHelper.generateLegacyAlertText(
          _currentEvent!,
          countdown,
          _estimatedIntensity,
        );
        TtsService().speakEvent(
          text,
          dedupeKey: 'legacy:${_currentEvent!.eventId}:initial',
          isUpdate: false,
          delay: const Duration(milliseconds: 900),
        );
        _lastSpokenSeconds = countdown;
        return;
      }
      if (countdown <= 10 && countdown > 0 && countdown != _lastSpokenSeconds) {
        TtsService().speakCountdown(_currentEvent!.eventId, countdown);
        _lastSpokenSeconds = countdown;
      } else if (countdown == 0 && _lastSpokenSeconds != 0) {
        TtsService().speakArrival(_currentEvent!.eventId);
        _lastSpokenSeconds = 0;
      }
    } catch (e) {
      print('_triggerVoiceAlert error: $e');
    }
  }

  /// 释放资源
  @override
  void dispose() {
    _eqlistStartTimer?.cancel();
    _eqlistStartTimer = null;
    _eqlist.onAnyUpdated = null;
    _eqlist.stop();
    _countdownTimer?.cancel();
    _carouselTimer?.cancel();
    _tempInfoDisplayTimer?.cancel();
    _infoDismissTimer?.cancel();
    for (final timer in _unifiedDismissTimers.values) {
      timer.cancel();
    }
    _unifiedDismissTimers.clear();
    _unifiedCarouselTimer?.cancel();
    for (final sub in _unifiedSubscriptions) {
      sub.cancel();
    }
    _chinaWeatherService.stop();
    _typhoonService.stop();
    super.dispose();
  }
}
